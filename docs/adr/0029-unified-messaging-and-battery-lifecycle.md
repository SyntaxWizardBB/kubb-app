# ADR-0029: Unified Messaging Framework und Battery-Lifecycle

- **Status**: Accepted
- **Date**: 2026-06-06
- **Amends**: ADR-0021 (Realtime-Subscription-Architektur — erweitert das Per-Tournament-Channel-/Reconnect-Modell [`RealtimeChannel`-Port, Per-Tournament-CDC, Refcount/Backoff, `realtimeFallbackProvider`] zu einem app-weiten Transport- und Lifecycle-Regime, ersetzt es nicht; Amends impliziert die Abhängigkeit)
- **Depends on**: ADR-0001 (Tech-Stack — Supabase Realtime ist im SDK), ADR-0002 (Bounded Contexts — Messaging ist Cross-Cut, kein neuer Kontext), ADR-0004 (Scaling-Strategie — Tier-Limits 200 / 500 concurrent), ADR-0022 (Offline-Sync-Outbox — Abgrenzung zum behaltenen Outbox-Polling), ADR-0026 (Anon-Spectator-Revision — Broadcast/`private:false` für anon, kein Per-Row-RLS für anon)
- **Followups**: löst die in ADR-0021 (anon-Realtime-Lifecycle / app-weite Reconnect-Sequenz, in §Negativ/§Folgepunkte offen gelassen) und ADR-0026 §Negativ ("Realtime für anon ist separater Folgepfad, Wave 4") markierten Punkte ein.
- **Bezug**: `docs/plans/realtime-messaging/messaging-framework-plan.md` (§1 Problem/Inventar, §2.5 Decision Rule, §2.3 Inbox-Spine, §3.2–3.5 Client-Pattern/Provider, §3.4 Lifecycle, §6.1 Push-Seam, §7.3 Hosted-vs-local, §9 Owner-Entscheidungen 2026-06-06)

> **Reines DESIGN-/Entscheid-Dokument.** Dieses ADR legt die verbindliche
> Transport-Auswahlregel, das Lifecycle-Regime und die Ziel-Client-API fest. Es
> enthält bewusst **keine** Sprint-/Implementierungs-Roadmap und keinen Code-Dump;
> Ziel-Identifier werden namentlich genannt, weil ihre Existenz und ihr Vertrag
> Teil der Entscheidung sind. Sequencing und Implementierung erfolgen in späteren
> Sprints auf Branch `feat/realtime-sync`.

## Kontext

Der Akku-Verbrauch dieser App wird heute nicht durch CPU oder Rendering dominiert,
sondern durch **Radio-Wake-ups**. Jeder Polling-Tick (`Timer.periodic` +
Riverpod-`invalidate`/`refreshFromRemote`) zwingt das Mobilfunk-/WLAN-Radio aus dem
Idle-Zustand in den aktiven Sende-/Empfangsmodus. Der teure Posten ist nicht die
abgefragte Zeile, sondern der Aufweck-Vorgang selbst und der anschliessende
Tail-Power-Schwanz, in dem das Radio noch hochgetaktet bleibt. Ein per-Sekunde-Poll,
der „nichts Neues" zurückgibt, kostet damit fast genauso viel wie einer, der ein
echtes Update bringt.

Es existiert bereits ein guter Realtime-Layer für Turniere: dedizierte
per-Tournament Postgres-CDC (`SupabaseRealtimeChannel` mit Refcount, 500 ms
Close-Debounce und Exponential-Backoff 1/2/4/8/30 s; `RealtimeChannel`-Port aus
ADR-0021) sowie anon-Broadcast über `realtime.send` (`public_tournament_realtime.dart`
+ Migration `20260601000031`, ADR-0026). Die Server-State-Discovery auf den **übrigen**
Screens ist jedoch reines Intervall-Polling. Inventar mit den IST-Code-Intervallen:

| Screen | Intervall | Quelle |
|---|---|---|
| Friends | 1 s | `social_providers.dart:28` |
| Inbox | 1 s | `inbox_controller.dart:40` |
| Teams (Liste + Detail) | 4 s | `team_providers.dart:22,33` |
| Match Live-Detail | 1 s pro Match | `match_providers.dart:44` |
| Tournament Liste/Detail | 5 s | `tournament_list_provider.dart:58,73` |
| Tournament Match Liste/Detail | 5 s | `tournament_match_providers.dart:36,58` |
| Bracket / Pool-Standings | 5 s | `tournament_bracket_provider.dart:26,54` |
| Public Spectator (Fallback) | 10 s | `public_tournament_polling_provider.dart:19` |

Keiner dieser Timer pausiert im Hintergrund. Ein User, der nur auf Friends + Inbox
sitzt, erzeugt bereits **~7.200 Polling-Wake-ups/Stunde**; mit zusätzlich offenen
Teams-/Tournament-Screens klettert das auf **>9.000/Stunde**. Schlimmer: backgrounded
laufen alle Timer ungebremst weiter — ein in den Hintergrund geschobener Screen leert
den Akku in ~10 Minuten, ohne dass der User die App überhaupt sieht.

Der IST-Code bestätigt zugleich, dass die Ziel-Bausteine **teilweise schon stehen**:
`realtimeEnabledFlagProvider`, der turnier-spezifische `realtimeFallbackProvider`,
`tournamentRealtimeChannelKey()` und `realtimeChannelProvider` existieren bereits
(`realtime_fallback_provider.dart`). Was fehlt, ist die **Verallgemeinerung** dieses
Musters auf alle Concerns — und namentlich die **Inbox-CDC**: die Inbox nutzt heute
ausschliesslich 1-s-`Timer.periodic`, `inboxRealtimeChannelKey()` existiert nicht.

Zwei Ziele sind verbindlich: **(A)** Cross-Device-Updates fühlen sich instant an;
**(B)** der Akku hält den ganzen Tag.

## Entscheidung

Wir ersetzen das Per-Screen-Intervall-Polling durch eine **einheitliche
Realtime-Messaging-Schicht** und formalisieren diese als verbindliches Framework, das
**alle** zukünftige Cross-Device-, Sync- und Notification-Arbeit by default nutzen
muss. Die Entscheidung hat drei Teile: eine Transport-Auswahlregel (was wird wie
zugestellt), ein Lifecycle-Regime (wann ist das Radio offen) und eine Client-API (wie
konsumiert der Client State).

### 1. Transport-Auswahlregel — „lowest-cost transport that fits"

Für jeden Bedarf wird der **billigste Transport** gewählt, der die Anforderung noch
trägt. „Billig" meint zuerst **Radio-Wake-ups** (der dominierende Battery-Faktor) und
erst danach Server-Aufwand. Die Regel ist verbindlich, damit am Call-Site nicht jedes
Mal neu abgewogen (und im Zweifel zu Polling gegriffen) wird. Der Entscheidungsbaum
wird **von oben nach unten** ausgewertet; der erste Treffer gewinnt:

```
1. Ist das Publikum anonym / Fan-out / braucht PII-gestrippte oder abgeleitete Payload?
   └─ JA → BROADCAST  (realtime.send-Trigger, private:false für anon)

2. Ist es eine durable, user-adressierte Notification, die offline / cold start
   überleben, im Inbox-UI erscheinen (und später Push treiben) muss?
   └─ JA → INBOX  (Schreiben in public.user_inbox_messages; Client = EINE CDC-Sub darauf)

3. Braucht ein authentifizierter Client Live-Row-State einer Tabelle, die er ohnehin
   lesen darf, filterbar über EINE indexierte Spalte (tournament_id / team_id /
   user_id / id)?
   └─ JA → CDC  (RealtimeChannel.subscribe; kein Server-Code, RLS autorisiert)

4. Ist es eine LISTE ohne Single-Column-User-Scope (my-teams, my-tournaments)?
   └─ Invalidierung über das INBOX-CDC-Event treiben; Polling nur als Fallback.

   Out-of-app-Wake nötig (backgrounded/closed)?
   └─ PUSH (zukünftig, §4) — gespeist von derselben user_inbox_messages-Zeile.
```

**Tie-breaker (binden bei Mehrdeutigkeit):** anon → **muss** Broadcast sein (kein
Per-Row-RLS für anon, ADR-0026). Braucht Offline-Durability / Push → **muss** durch
die Inbox laufen. Sonst → Default auf CDC (keine Migration, RLS trägt die
Autorisierung).

Die Owner-Entscheidung vom 2026-06-06 (§9 des Plans, alle Punkte final) verschärft
Stufe 4: Authentifizierter Per-User-State bekommt **echtes CDC** statt der
Invalidierungs-Variante, wo immer ein Single-Column-Scope herstellbar ist —
`team_memberships.user_id` und `tournament_participants.user_id` für die my-Listen.
**Freunde sind die eine Ausnahme**: `friendships` ist kanonisch low/high-gekeyt, ein
Realtime-Filter kann aber nur auf *einer* Spalte `=` matchen, also gibt es kein
direktes „meine Freunde"-CDC. Dafür kommt eine denormalisierte, Trigger-gepflegte
`friend_edges(owner_user_id, friend_user_id, status)`-Tabelle, CDC-gefiltert auf
`owner_user_id`. Stufe 4 als Inbox-Invalidierung bleibt damit reiner Fallback-Pfad.

#### Transport 1 — Broadcast (anon / Fan-out / kuratiert)

Verbindliches Muster ist der **bereits existierende** anon-Spectator-Pfad aus
ADR-0026: Migration `20260601000031_public_tournament_realtime.sql` +
`public_tournament_realtime.dart`. Server-seitig feuert ein `AFTER INSERT OR UPDATE`-
Trigger und schreibt über `realtime.send(payload, event, topic, false)` ein
**kuratiertes** Event in einen pro-Scope Topic (`public_tournament_events:<tid>`). Der
vierte Parameter `false` (`private:false`) macht das Topic anon-lesbar — kein JWT,
kein `signInAnonymously()`-Round-Trip. Vier nicht verhandelbare Eigenschaften:

- **Explizite Spalten-Whitelist im Trigger** (`jsonb_build_object(...)` aus genau den
  freigegebenen Feldern; **kein** `created_by`/`submitter_user_id`/`user_id`). Die
  Privacy-Garantie liegt serverseitig; der Client whitelisted defensiv ein zweites
  Mal (`PublicTournamentEvent.fromPayload` + `assertPayloadColumnsWhitelisted`).
- **`SECURITY DEFINER`** auf der Trigger-Funktion (`SET search_path = public,
  realtime`), damit sie auch durchläuft, wenn der mutierende RPC-Owner keine Rechte
  auf das `realtime`-Schema hat.
- **Visibility-Gate vor dem Emit** (`public_tournament_is_visible`): Events nur für
  Scopes, die ohnehin öffentlich sichtbar wären.
- **Topic-Name-Helper als Single Source** (`public_tournament_realtime_topic(uuid)`),
  gespiegelt vom Client-Builder (künftig `tournamentBroadcastTopic(TournamentId)`),
  damit Trigger und Client denselben Namensraum treffen und Drift in Tests auffällt.

Broadcast nimmt die `tournament_*`-Tabellen **bewusst nicht** in die Publication auf —
das würde das gesamte Row-Set an alle anonymen Subscriber leaken. Broadcast-Topic-
Konvention: `<domain>_events:<scope_id>`.

#### Transport 2 — Inbox als Notification-Spine + Push-Seam

`public.user_inbox_messages` (Migration `20260504000011`) ist die **eine durable,
user-adressierte** Tabelle: Single-Column-Scope `user_id`, Owner-Read-RLS
(`user_inbox_messages_owner_read`), Drift-Mirror, `refreshFromRemote(userId)`. Jede
durable Notification (Tournament-Go-Live, Team-Invites, Admin-Notices) INSERTet schon
heute hierhin. Die Entscheidung: der Client ersetzt das heutige 1-s-Polling
(`inbox_controller.dart`) durch **eine einzige CDC-Subscription** auf diese Tabelle,
gekeyt über `inboxRealtimeChannelKey(UserId)` → `user_inbox_messages:user_id=<uid>`.
Diese eine Subscription bedient die gesamte Read-Side aller durable Notifications auf
einmal — die grösste Einzel-Reduktion des Vorhabens.

Der Push-Seam ist **ein** `AFTER INSERT`-Trigger auf `user_inbox_messages` (Muster
analog `20260601000031`), der zweierlei tut: `realtime.send` eines kuratierten,
PII-freien Nudge **jetzt** (`id`, `kind`, `subject`, `sent_at`) für den
Foreground-Wake; und `push_outbox`-Enqueue **später** für den Out-of-app-Wake. Der
Push-Branch wird in diesem Vorhaben **gestubbt** mitgebaut (Owner-Entscheidung §9,
Branch `feat/realtime-sync`), die `push_outbox`-Hälfte bleibt zunächst ein Stub.
**One write, two wakes** — derselbe INSERT speist Foreground-Realtime *und*
Background-Push und garantiert Parität zwischen beiden Pfaden.

#### Transport 3 — CDC (authentifizierter Live-Row-State)

Der bestehende `RealtimeChannel`-Port (`subscribe(table, filterColumn, filterValue)`,
`stateStream`, `close`) + `SupabaseRealtimeChannel`-Adapter bleibt **unverändert** und
ist der Default-Transport. Er kann ausschliesslich **Single-Column-Equality** filtern
— das ist Absicht und prägt die Migrations-Konsequenzen unten. Kein Server-Code: die
Autorisierung trägt vollständig die RLS-SELECT-Policy der Tabelle; der Client sieht
per CDC genau die Rows, die er auch per Query sehen dürfte. CDC-Key-Konvention:
`<table>:<column>=<value>`.

### 2. Battery-Lifecycle — drei Radio-Regime

Wir steuern den Auf-/Abbau des Realtime-Radios über den Flutter-`AppLifecycleState`.
Die harte Regel lautet: *Nichts hält das Radio offen, während die App `paused` ist.
Foreground = genau EINE WebSocket. Background = NULL Sockets + NULL Timer. Push ist
der einzige Background-Wake-Pfad. Per-Sekunde-Polling wird gelöscht, nicht nur
pausiert.*

| Regime (`AppLifecycleState`) | Transport | Wake-Quelle | Idle-Drain |
|---|---|---|---|
| `resumed` (Foreground) | EINE multiplexte WebSocket, N Kanäle (Supabase-Singleton) | Server-Push über die offene Socket | instant (<1 s), Socket bereits offen, ~0 idle |
| `inactive` (transient: App-Switcher, Anruf, kurzes Lock) | Socket halten, no-op | — | Teardown/Reconnect-Thrash vermeiden |
| `paused` / `detached` (Background/closed) | OS-Push (zukünftig), Socket abgebaut | OS-Push-Dienst (nicht unser Radio) | NULL Sockets + NULL Timer, ~0 idle |

Wake-up-Ziele gegenüber heute:

| Szenario | Heute | Ziel |
|---|---|---|
| Inbox + Friends Foreground | ~7.200/h | ~1 Socket-Frame pro echtem Event (≈0 idle) |
| Backgrounded | Timer feuern weiter | 0 (nur Push) |
| Realtime down (Fallback) | n/a | ~120/h (30-s-Kadenz) |

Der Lifecycle-Controller (Ziel-Datei `lib/app/app.dart`) implementiert die folgenden
**zwingenden** Transitionen:

- **`resumed`** — Reihenfolge ist verbindlich, sonst Auth-Storm:
  1. **`forceReSignWireSession` ZUERST** — frischer Wire-JWT. Andernfalls treffen die
     rejoinenden Kanäle auf einen abgelaufenen Token und laufen in einen
     `join → 401 → backoff`-Sturm.
  2. Kanäle reconnecten, die bei `pause` aktiv waren — **Inbox immer**;
     tournament/match-Kanäle **nur, wenn der Screen noch gemountet ist**.
  3. `KeypairSessionRefresher` resumen.
- **`inactive`** — no-op. Socket bleibt offen; ein transienter Wechsel darf keinen
  Teardown auslösen (Reconnect-Thrash).
- **`paused`** — Debounce **~5 s**, dann: alle Kanäle `unsubscribe` + Socket
  `disconnect` + `KeypairSessionRefresher` pausieren. Der Debounce verhindert, dass
  ein kurzes Lock unnötig teardownt.
- **`detached`** — identischer Teardown, aber sofort (kein Debounce).

Die bei `pause` aktiven Channel-Keys werden über den `pause → resume`-Zyklus
persistiert (Refcount-Map in `SupabaseRealtimeChannel`, Rehydrate-from-Snapshot),
damit Schritt (2) genau die zuvor aktiven Kanäle wiederherstellt und nicht mehr.

**Polling ist nur Failure-Mode.** Es greift ausschliesslich, wenn ein Kanal **≥60 s**
im `errored`-Zustand ist (bestehende `kRealtimeFallbackErroredGrace`), damit kurze
Reconnect-Blips nicht ins Polling kippen. Kadenz dann: **30 s** Foreground, **10 s**
für anon-Spectator (für den es heute keinen CDC-Fallback gibt, ADR-0026). Ein
Boolean-Gate garantiert genau einen aktiven Pfad — Polling läuft nie parallel zu einem
gesunden Kanal und wird beim Reconnect gecancelt.

### 3. Client-API & State-Pflicht (verbindlich)

Authentifizierter Realtime-State wird auf dem Client **ausschliesslich** über
`StreamProvider.autoDispose.family` bezogen — keyed by Entity-Id (`UserId`, `TeamId`,
`MatchId`, `TournamentId`). Das Muster `FutureProvider` + `Timer.periodic` für
Server-State-Discovery wird **gelöscht, nicht pausiert**. Abweichungen (neuer
`Timer.periodic` für Server-State, zweiter Supabase-Client, hand-gebaute
Channel-Keys) gelten als Architekturverstoss und sind im Review zu blocken.

**Subscribe-Lifecycle:** Subscribe beim **ersten** `watch`; der Adapter-Refcount
joint den zweiten Watcher desselben Keys auf denselben Channel. `ref.onDispose` →
Refcount dekrementieren, Teardown erst nach **500 ms Debounce**. Zwei Provider-
Varianten, beide `autoDispose` + family-keyed: **(a) drift-cache** (Inbox) — pro
Event `refreshFromRemote(userId)`, Rückgabe ist der Drift-`watch*`-Stream;
**(b) invalidate-on-tick** (Teams-Liste, Tournament-Liste/Detail, Match) — `listen` +
`invalidateSelf()` pro Event.

**Eine WebSocket, N Kanäle:** genau **ein** Supabase-Client (Singleton), alle Kanäle
multiplexen, **niemals** ein zweiter Client. Globale, screen-unabhängige Signale —
namentlich die **Inbox** als Notification-Spine — werden auf **App-Shell-Scope**
gehalten, damit die durable Subscription über Navigations-Wechsel hinweg lebt.

**Channel-Keys nur über `kubb_domain`-Builder** — nie am Call-Site handgebaut, weil
der `stateStream`-Lookup exakt dieselbe Map-Entry treffen muss wie der `subscribe`-
Call; eine String-Abweichung erzeugt einen toten Channel ohne Updates und ohne
Fehler. Eine Builder-Funktion pro Concern, colocated nach dem Vorbild von
`tournamentRealtimeChannelKey()`:

| Builder | Transport | Key-Form |
| --- | --- | --- |
| `inboxRealtimeChannelKey(UserId)` | CDC | `user_inbox_messages:user_id=<uid>` |
| `teamRealtimeChannelKey(TeamId)` | CDC | `team_memberships:team_id=<tid>` |
| `matchRealtimeChannelKey(MatchId)` | CDC | `matches:id=<mid>` (Standalone-Match, Tabelle `public.matches` — disjunkt von `tournament_matches`) |
| `tournamentRealtimeChannelKey(TournamentId)` | CDC | `tournament_matches:tournament_id=<tid>` (bestehend) |
| `myTeamsRealtimeChannelKey(UserId)` | CDC | `team_memberships:user_id=<uid>` (treibt my-teams-Invalidierung, §4) |
| `myTournamentsRealtimeChannelKey(UserId)` | CDC | `tournament_participants:user_id=<uid>` (treibt my-tournaments-Invalidierung, §4) |
| `friendsRealtimeChannelKey(UserId)` | CDC | `friend_edges:owner_user_id=<uid>` (§4) |
| `tournamentBroadcastTopic(TournamentId)` | Broadcast | `public_tournament_events:<tid>` (Rename des bisherigen Spectator-Topic-Helpers) |

Die user-gescopten my-Listen-Keys (`team_memberships.user_id`,
`tournament_participants.user_id`, `friend_edges.owner_user_id`) sind die
CDC-Targets, deren Row-Writes die jeweilige Listen-Invalidierung treiben — ihre
Migrations-Anforderungen (Publication, RLS-USING-Spalte) stehen in §4.

**Ziel-Provider** (beide bewusst boolesche Gates, keine eigenen Datenquellen — sie
schalten zwischen vorhandenen Pfaden, sie duplizieren keinen State):

- **`realtimePollingFallbackProvider`** — `StreamProvider.autoDispose.family<bool,
  String /*channelKey*/>`. Generalisiert den heutigen turnier-spezifischen
  `realtimeFallbackProvider` (der nur auf `TournamentId` keyt) auf einen beliebigen
  Channel-Key. Monitort `stateStream(channelKey)`; flippt auf `true` (Poll-Mode) bei
  **≥60 s** errored; `true` => `Timer.periodic` mit **30 s** (anon Spectator 10 s);
  cancelt bei Reconnect.
- **`realtimeEnabledFlagProvider`** — Kill-Switch (existiert bereits, default `true`).
  Incident-Response (Feature ohne Deploy auf Polling zurückflippen) und Spectator
  „Live-Modus aus". Wenn `off` → **always poll**.

Eine neue Port-Sibling `broadcast_channel.dart` (`BroadcastChannel` mit
`subscribe`/`close`/`stateStream`) tritt neben `realtime_channel.dart`;
`SupabasePublicTournamentRealtime` wird ein thin mapper darauf. CDC- und
Broadcast-Adapter teilen einen gemeinsamen Lifecycle-Mixin (Refcount, 500 ms
Close-Debounce, 1/2/4/8/30-s-Backoff).

### 4. Migrations-Konsequenzen für neue CDC-Targets

Jeder **neue CDC-Target** (Transport 3) verlangt — anders als Broadcast, der keine
Publication berührt — eine Migration mit drei zusammengehörigen Bausteinen:

1. **Publication explizit.** `ALTER PUBLICATION supabase_realtime ADD TABLE
   public.<table>;` — pro Ziel-Tabelle, verpflichtend. Lokal publiziert Supabase
   `FOR ALL TABLES`, CDC „funktioniert einfach" in Dev und kann in Prod **still
   scheitern**. Ohne explizites `ADD TABLE` ist die Migration nicht vollständig; auf
   Staging verifizieren.
2. **`REPLICA IDENTITY FULL` nur wo Old-Row-Spalten gebraucht werden.** `FULL`
   vergrössert das WAL — bewusst sparsam einsetzen.
3. **RLS-SELECT-Policy deckungsgleich zur CDC-Filterspalte.** Da CDC nur die Rows
   liefert, die die SELECT-Policy durchlässt, muss exakt die Subscribe-Filterspalte
   von einer Policy gedeckt sein (Muster aus `user_inbox_messages`: `USING
   (<filter_column> = auth.uid())`). Für `team_memberships`/`tournament_participants`
   ist `<filter_column>` = `user_id`, für `friend_edges` = `owner_user_id`.
   Filterspalte und RLS-USING-Spalte **müssen dieselbe sein** — sonst lässt entweder
   der Filter zu wenig durch oder die Policy zu viel.

## Alternatives considered

### Per-Concern weiter pollen, nur Background pausieren

Statt Polling zu löschen, nur die Timer im `paused`-State stoppen.
**Verworfen wegen**: Die ~7.200–9.000 Foreground-Wake-ups/h bleiben bestehen — Ziel B
(Akku hält den Tag) wird im aktiven Gebrauch nicht erreicht. Und „pausieren" ist
fragiler als „löschen": ein vergessener Resume oder ein nicht abgehängter Timer hält
das Radio im Hintergrund weiter offen. Die harte Regel „gelöscht, nicht pausiert"
macht den Failure-Mode unmöglich statt nur unwahrscheinlich.

### Inbox-Invalidierung auch für authentifizierte Per-User-Listen (Plan-Stufe 4 unverändert)

Der ursprüngliche Plan-Entwurf trieb my-teams/my-tournaments über das Inbox-CDC-Event
und behielt Polling nur als Fallback. **Verworfen** durch Owner-Entscheidung §9
zugunsten von **echtem CDC** direkt auf `team_memberships.user_id` /
`tournament_participants.user_id`. Begründung: ein Inbox-Event als Listen-Tick ist
indirekt (jede Listen-Änderung muss eine Inbox-Zeile erzeugen) und latenzbehaftet;
direktes CDC ist instant und braucht keine Zusatz-Notification. Der Preis — mehr
Server-Aufwand für sauberes CDC (Publication, Policy, ggf. denormalisierte
`friend_edges`) — wurde bewusst akzeptiert.

### Anon-Spectator auf CDC statt Broadcast

**Verworfen** als Constraint, nicht als Abwägung: für anon ist kein Per-Row-RLS
möglich (ADR-0026). Anon bleibt Broadcast mit kuratiertem `private:false`-Topic; das
ist der Tie-breaker, der die Regel bindet.

### Zweiter Supabase-Client / mehrere Sockets pro Screen

**Verworfen**: N unabhängige Sockets vervielfachen die Heartbeat-Wake-ups und sprengen
die Tier-Concurrency-Limits (ADR-0004). Eine multiplexte WebSocket mit N Kanälen ist
sowohl battery- als auch limit-konform.

## Consequences

### Positiv

- Idle-Drain im Foreground fällt von >9.000 Wake-ups/h auf ~1 Socket-Frame pro echtem
  Event; backgrounded auf 0.
- Genau ein offener Socket im Foreground (Supabase-Singleton, N multiplexte Kanäle)
  statt N unabhängiger Timer.
- Updates fühlen sich instant an (<1 s), weil die Socket bereits offen ist, wenn das
  Event eintrifft (Ziel A).
- Eine **einzige verbindliche Regel** am Call-Site statt Ad-hoc-Polling: neue
  Sync-Arbeit hat einen klaren, billigsten Default.
- Der Push-Seam ist bereits angelegt: dieselbe Inbox-Zeile, die Foreground-Realtime
  speist, treibt später Background-Push ohne Parity-Lücke (one write, two wakes).
- Der grösste Teil des Musters existiert schon im Code (`realtimeFallbackProvider`,
  `tournamentRealtimeChannelKey`, Refcount/Backoff-Adapter) — die Schicht wird
  verallgemeinert, nicht neu erfunden.

### Negativ

- **Solange OS-Push nicht implementiert ist, gibt es im Hintergrund KEINE
  Server-Updates.** Bewusster Tradeoff zugunsten ~0 Idle-Drain: bis der Push-Pfad
  live ist, holt die App neue Server-State erst beim `resume` (Inbox- und ggf.
  Screen-Kanäle reconnecten). Der User sieht Änderungen beim nächsten App-Öffnen,
  nicht out-of-app. Der Push-Branch wird gestubbt mitgebaut, die `push_outbox`-Hälfte
  bleibt zunächst Stub.
- Die `resume`-Sequenz ist **ordnungssensitiv** (JWT zuerst); ein Fehler in der
  Reihenfolge führt zu einem `join → 401 → backoff`-Sturm statt zu sauberem Reconnect.
- Per-Sekunde-Polling wird ersatzlos gelöscht; ein degradierter Realtime-Pfad fällt
  auf 30 s (anon 10 s) — spürbar träger als heute, aber nur im Failure-Mode.
- **CDC-Filterspalte und RLS-USING-Spalte können auseinanderlaufen**: deckt die
  SELECT-Policy nicht exakt die Subscribe-Filterspalte, liefert CDC entweder zu wenig
  (broken UI) oder zu viel (Leak). Erfordert Review-Disziplin pro neuem Target.
- **Broadcast-Privacy hängt an manueller Spalten-Whitelist** in Trigger UND
  Client-Decoder; ein neuer Trigger-Patch kann versehentlich eine PII-Spalte
  mitliefern, wenn nicht beide Stellen synchron gepflegt und über
  `assertPayloadColumnsWhitelisted` getestet werden.
- **`friend_edges` ist eine Trigger-gepflegte Denormalisierung** der kanonischen
  `friendships`-Tabelle; Trigger-Drift führt zu falschem/veraltetem Friends-CDC.
  Konsistenz-Tests nötig.

### Neutral

- Behaltenes Polling, das kein Messaging-Concern ist und das Radio nicht weckt, bleibt
  **unverändert** und ist von der Lösch-Regel ausgenommen: Outbox-Pending (2 s,
  lokales Drift-Read, DAO ohne reaktiven `watch`, ADR-0022), Offline-Banner-Label
  (60 s, UI-Timestamp-Aging), Match-Countdown und Auth-Restore-Cooldown (1 s, reine
  UI-Ticker, kein Netzwerk).
- Der `~5 s`-Pause-Debounce ist ein Tuning-Wert; er trägt absichtlich kurze Locks
  über, ohne das Background-Radio offenzuhalten.
- ADR-0021 wird **nicht superseded** — die *Architektur* (RealtimeChannel-Port,
  Refcount/Backoff, Polling-Fallback) bleibt gültig und ist die Basis. ADR-0029
  *amendiert*: es hebt das Per-Tournament-Modell auf einen app-weiten Transport- und
  Lifecycle-Rahmen und löst die in ADR-0021/0026 als Followup markierten Punkte
  (anon-Realtime-Lifecycle, app-weite Reconnect-Sequenz) ein.

### Risiko: Hosted-vs-local Publication

Lokales Supabase publiziert `FOR ALL TABLES` — CDC „funktioniert einfach" in Dev und
kann in Prod **silent failen**. Für die Battery-Ziele ist das doppelt relevant:
Schlägt CDC in Prod still fehl, fällt der Fallback auf 30-s-Polling zurück und der
Battery-Vorteil verpufft unbemerkt. Mitigation: pro CDC-Target verpflichtende
Migration mit explizitem `ALTER PUBLICATION supabase_realtime ADD TABLE …`
(+ `REPLICA IDENTITY FULL` bei Bedarf), auf Staging verifizieren (siehe §4).

## Status-Notiz

Decision Record — Design only, no code changes. Sequencing und Implementierung
erfolgen auf Branch `feat/realtime-sync` in späteren Sprints; der Push-Trigger wird
mit gestubbtem Push-Branch gebaut. Owner-Entscheidungen vom 2026-06-06 (§9 des Plans,
alle 7 final) sind in dieses ADR eingearbeitet: gestubbter Push-Branch, Fallback
30 s / anon 10 s, echtes CDC für authentifizierten Per-User-State (Listen direkt auf
Member-/Participant-Tabelle, Freunde via `friend_edges`), anon-Spectator bleibt
Broadcast, durable Notifications bleiben Inbox-CDC, mehr Server-Aufwand für sauberes
CDC akzeptiert, 5-s-Pause-Debounce. Dieses ADR legt Regel, Regime und Ziel-API fest;
es definiert keinen Code und keine Sprint-Roadmap.
