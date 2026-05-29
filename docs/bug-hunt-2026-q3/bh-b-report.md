# Bug-Hunter B — Sprint-C Mini-Sweep Report

Branch: `sprintC-bh-b`
Worktree: `/tmp/kubb-c-bh-b`
Scope: Realtime / Anon / Public-Tournament-Substanz aus Sprint-C Wave 2-3.
Modus: NUR Analyse, kein Fix.

Befunde sind nach `BH-B-NN` durchnummeriert. Severity P0 = funktional kaputt
oder Privacy-Bruch, P1 = sicher reproduzierbares Fehlverhalten, P2 = Risiko
oder Designluecke, P3 = Cosmetic / Maintenance-Schuld.

---

## BH-B-01 — Reconnect nach Offline-Phase: kein Status-Tracking, kein Backoff
**Severity:** P1
**Datei:** `lib/features/tournament/data/public_tournament_realtime.dart:271-274` (`_open`)
**Eintritt:** Spectator oeffnet PublicTournamentScreen, geht offline (z.B.
Tunnel), kommt zurueck.
**Begruendung:** `channel..subscribe()` wird ohne Status-Callback aufgerufen.
Der Adapter weiss nicht, ob der Channel `channelError` oder `timedOut`
geliefert hat, und triggert keinen Resubscribe. Vergleiche
`lib/core/data/realtime/supabase_realtime_channel.dart:71-110`
(`_handleStatus` + `_scheduleReconnect` mit Backoff) — das ist die
Referenz-Implementation in der Codebasis. Der Public-Pfad ist dadurch nach
einem Disconnect dauerhaft "stumm", obwohl Supabase die Socket-Verbindung
unter Umstaenden wieder herstellt. Tests decken das nicht ab.

## BH-B-02 — `watch()` inkrementiert `refCount` ohne Listener: Leak bei "Stream-erstellt-aber-nie-listened"
**Severity:** P2
**Datei:** `lib/features/tournament/data/public_tournament_realtime.dart:207-210` + `231-235`
**Eintritt:** Code-Pfad ruft `adapter.watch(tid)` und verwirft das Future-/
Stream-Handle ohne `.listen(...)` (z.B. Riverpod-Provider mit Build-Fehler
direkt nach `watch()`).
**Begruendung:** `refCount += 1` laeuft synchron in `watch()`. Der
korrespondierende `refCount -= 1` haengt am `onCancel` des **outer**
`StreamController.broadcast()`. Hat dieser nie einen Listener, feuert
`onCancel` nie → `_ChannelEntry` und der zugehoerige `RealtimeChannel`
bleiben offen, der Slot in `_entries[topic]` ist belegt. Korrekt waere,
den Refcount im `onListen` des outer Controllers zu inkrementieren oder
nach dem `listen(...)`-Setup zu zaehlen.

## BH-B-03 — `handlePayload` kann nach `controller.close()` adden → "Bad state" Race
**Severity:** P2
**Datei:** `lib/features/tournament/data/public_tournament_realtime.dart:267` (inside `_open`)
**Eintritt:** Letzter Listener canceled (onCancel laeuft `await
_client.removeChannel(...)` + `entry.controller.close()`), aber ein
Realtime-Broadcast-Paket schwebt in der `onBroadcast`-Callback-Queue und
ruft `handlePayload` nach `controller.close()` auf.
**Begruendung:** `handlePayload` ruft `entry.controller.add(event)` ohne
`isClosed`-Check. `StreamController.add` auf einen geschlossenen
broadcast-Controller wirft `Bad state: Cannot add event after closing`.
Im Worst Case `Zone.uncaught` → Crash in Release. Eine `if
(!entry.controller.isClosed)` Guard waere die Fix-Linie.

## BH-B-04 — `private: false` ist als Channel-Default angenommen, aber nicht explizit gesetzt
**Severity:** P2
**Datei:** `lib/features/tournament/data/public_tournament_realtime.dart:246`
(`final channel = _client.channel(topic);`)
**Eintritt:** supabase_flutter dreht zu einer Major-Version, in der
`RealtimeChannelConfig.private` Default `true` ist.
**Begruendung:** Der Code verlaesst sich auf den heutigen Default des
`channel()`-Aufrufs (`RealtimeChannelConfig(private: false)`). Das ist
implizit; ein Lib-Update wuerde den anon-Pfad lautlos brechen — der Channel
wuerde joinen, aber niemals Broadcasts liefern. Korrekt waere `channel(topic,
opts: RealtimeChannelConfig(private: false))` als selbstdokumentierender,
update-resistenter Setter. Der ADR-Kommentar (Z. 240–245) macht das
deutlich, der Code befolgt es nicht.

## BH-B-05 — Whitelist-Pruefung ist debug-only → Trigger-Leak fliesst im Release-Build still durch
**Severity:** P2
**Datei:** `lib/features/tournament/data/public_tournament_realtime.dart:258-264`
**Eintritt:** Future Migration ergaenzt z.B. `submitter_user_id` im
Trigger-Payload. Debug-Test schlaegt aus, aber Release-Build laeuft.
**Begruendung:** `assert(() { assertPayloadColumnsWhitelisted(...); return
true; }(), ...)` wird im Release-Mode komplett rausoptimiert.
`PublicTournamentEvent.fromPayload` verwirft unbekannte Keys still — der
Leak landet zwar nicht im Dart-State, **wandert aber durch den
Realtime-Topic an alle anonymen Subscriber** (das Topic ist
`private: false`). Der Privacy-Anker liegt damit allein auf der
Server-Seite. ADR-0026 §Realtime und Worker-Briefing fordern aber explizit
einen "client-side defensive whitelist check". Empfehlung: zumindest
Release-Logging (kein Throw) statt komplettem No-Op.

## BH-B-06 — Trigger emittiert auf INSERT auch bei Tournament-Bulk-Bracket-Build
**Severity:** P3
**Datei:** `supabase/migrations/20260601000031_public_tournament_realtime.sql:113-119` + `230-234`
**Eintritt:** `tournament_start_ko_phase` oder Round-Robin-Plan-Generator
fuegt N Matches in einer Transaktion ein.
**Begruendung:** Der Skip-Guard greift nur fuer `TG_OP = 'UPDATE'`. Jedes
`INSERT` feuert ein `realtime.send()` → N Broadcast-Pakete pro Bracket-
Aufbau. Spectator-UI invalidiert N-mal denselben Provider in Folge. Kein
Funktionsbug, aber Realtime-Quota-/UI-Thrash-Risiko bei groesseren
Turnieren. Loesung waere ein deferrable-Trigger oder Statement-Level-
Trigger, der ein aggregiertes `bracket_built`-Event sendet.

## BH-B-07 — Tournament-Status-Transition `public → private` schliesst Topic nicht aktiv
**Severity:** P2
**Datei:** `supabase/migrations/20260601000031_public_tournament_realtime.sql:121-123`
**Eintritt:** Organisator deaktiviert `public` waehrend ein Spectator
verbunden ist.
**Begruendung:** Der Trigger respektiert `public_tournament_is_visible`
und emittiert ab da nichts mehr — *keine* Daten-Leakage. **Aber:** der
bestehende Channel des Spectators bleibt offen, kein "tournament gone
private"-Signal wird gesendet. Die UI zeigt weiter den letzten Snapshot.
Erwartetes Verhalten gemaess ADR-0026 unklar, aber ohne aktives
Visibility-End-Event hat der Spectator keinen Trigger fuer den
`_notPublic`-Placeholder. Realer User-Pfad: Spectator sieht "alte"
Daten, bis er manuell refresht und die RPC `null` zurueckgibt. Empfehlung:
ein `visibility_changed`-Event aus einem AFTER-UPDATE-Trigger auf
`tournaments` (mit gleicher Whitelist-Disziplin).

## BH-B-08 — `publicTournamentPollingProvider` + `publicLiveModeProvider` sind dead code
**Severity:** P2
**Datei:** `lib/features/tournament/application/public_tournament_polling_provider.dart`,
`lib/features/tournament/application/public_live_mode_provider.dart`,
ungenutzt in `public_tournament_screen.dart`.
**Eintritt:** Static-Search — beide Provider haben keinen Konsumenten
ausser einem Kommentar-Cross-Reference.
**Begruendung:** Die Wave-3-Migration auf den Realtime-Pfad hat die alten
M4.2-T11-Provider stehen lassen. Folgen: (a) Dead-Code-Drift —
zukuenftige Bug-Fixes laufen ins Leere, (b) der ADR-fundierte "Polling
default, Live-Mode per Toggle"-Pfad ist nicht erreichbar; jeder Public-
Page-View startet jetzt einen Realtime-Channel (Cost / Realtime-Quota), c)
`publicTournamentPollingProvider` ruft `tournamentMatchListProvider`
(authentifizierter Pfad!) — wenn jemand den irrtuemlich wieder einhaengt,
laeuft der anon-Spectator gegen `auth.uid()`-Guard. Entweder Provider
entfernen oder die Live-Mode-Toggle-Architektur restaurieren.

## BH-B-09 — `PublicMatchScreen` ist nicht realtime-wired
**Severity:** P2
**Datei:** `lib/features/tournament/presentation/public/public_match_screen.dart`
**Eintritt:** Spectator oeffnet Direct-Match-Link, ein Score-Update kommt
herein.
**Begruendung:** Der Single-Match-Screen liest nur `publicMatchDetailProvider`
und macht *keinen* `ref.listen` auf `publicTournamentEventsProvider`. Der
Trigger feuert zwar `match_status` mit der konkreten `match_id`, aber der
Screen invalidert seinen Provider nicht. Inkonsistenz zur Tournament-View;
Spectator muss manuell refreshen. Klassischer Pull-only-Pfad genau auf der
Surface, die Realtime briefte.

## BH-B-10 — `SupabasePublicTournamentRealtime` ist nicht von Tests abgedeckt
**Severity:** P1
**Datei:** `test/features/tournament/data/public_tournament_realtime_test.dart`
**Eintritt:** Test-Coverage-Audit der Realtime-Schicht.
**Begruendung:** Die Tests nutzen ausschliesslich `_FakeRealtime`, das
selbst neu im Test-File definiert ist. Der Production-Adapter
(`SupabasePublicTournamentRealtime` mit RefCount, removeChannel,
onBroadcast-Wiring, Whitelist-Assert) ist nicht instrumentiert. Konkret
ungeprueft: (a) Doppel-`watch(tid)` -> ein einziger `channel()`-Call, (b)
letzter Listener -> `removeChannel`-Call, (c) `payload['payload']`-vs.-
Top-Level-Envelope-Fallback, (d) `assert`-Pfad fuer leakage in Debug.
Hier liegt das Risiko von BH-B-01 / BH-B-02 / BH-B-03 / BH-B-04.

## BH-B-11 — Kein pgTAP-Test fuer Trigger-Funktionen + Visibility-Helper
**Severity:** P1
**Datei:** `supabase/tests/` (Fehlt komplett — kein Test referenziert
`public_tournament_emit_match_event`,
`public_tournament_emit_proposal_event`, `public_tournament_is_visible`,
`public_tournament_realtime_topic`).
**Eintritt:** `grep -rn 'public_tournament_emit\|public_tournament_realtime_topic\|public_tournament_is_visible' supabase/tests/` -> 0 Treffer.
**Begruendung:** Migration 20260601000031 implementiert
SECURITY-DEFINER-Trigger + Visibility-Gate, aber `supabase/tests/` deckt
keinen einzigen Privacy-Anker auf SQL-Ebene. ADR-0026 §"pgTAP-Tests
erweitert" und das Migration-Headerkommentar versprechen explizit
"Whitelist-Pflege in Migration und Decoder synchron". Ohne pgTAP-Test
zerfaellt der Privacy-Anker beim naechsten Spalten-Add im
`tournament_matches`-Schema. Acceptance "Kein PII im Topic-Payload"
nicht serverseitig pinbar.

## BH-B-12 — Visibility-Status-Liste in Trigger + RPC + Policy dupliziert (Drift-Risiko)
**Severity:** P3
**Datei:** `supabase/migrations/20260601000031_public_tournament_realtime.sql:82-88`,
`supabase/migrations/20260901000001_public_tournament_rpcs.sql:51-57` + `158-164`,
`supabase/migrations/20260701000002_tournaments_public_flag.sql:39-46`.
**Eintritt:** Neuer Status (z.B. `qualifying`) wird zur sichtbaren
Lifecycle-Phase hinzugefuegt.
**Begruendung:** Heute existieren **drei** Stellen mit der gleichen
`status IN ('published','registration_open','registration_closed',
'live','finalized')`-Liste. `public_tournament_is_visible` ist als
Helper definiert, wird aber nur vom Trigger verwendet — die RPC
`public_tournament_get` ruft ihn nicht, sondern dupliziert das Pattern.
Empfehlung: RPC ueber den Helper routen, Tabellen-Policy ebenfalls;
verifiziert die Gating-Identitaet, die der ADR fordert.

## BH-B-13 — `tournament_matches`-Trigger: Score-Patch in `awaiting_results` triggert kein Event, obwohl `consensus_round` bumpt
**Severity:** P2
**Datei:** `supabase/migrations/20260601000031_public_tournament_realtime.sql:113-119`
**Eintritt:** Spieler reicht Set-Score ein, `consensus_round` bumpt von 1
auf 2, Status bleibt `awaiting_results`, kein `final_score_*`/`winner`
gesetzt.
**Begruendung:** Der Skip-Guard prueft `status`, `winner_participant`,
`final_score_a/b` — `consensus_round` ist **nicht** im Distinctness-Check.
Konsequenz: Das `tournament_set_score_proposals`-INSERT-Trigger feuert ein
`proposal_created`-Event (gut). Aber kein `match_status`-Event mit der
neuen `consensus_round`, obwohl der Client die `consensus_round` aus dem
Match-Payload liest. Wenn der Client also nur `match_status` listened und
auf der `proposal_created`-Branch noch keinen `setNumber` bekommt, sieht
er die Runden-Progression spaeter. Empfehlung: `consensus_round` ebenfalls
in den Distinctness-Check aufnehmen oder dokumentieren, warum die
`proposal_created`-Quelle ausreicht.

## BH-B-14 — Channel-Topic-Name nutzt `id::text` ohne Whitespace-/Format-Normalisierung
**Severity:** P3
**Datei:** `supabase/migrations/20260601000031_public_tournament_realtime.sql:55` vs.
`lib/features/tournament/data/public_tournament_realtime.dart:174-175`
**Eintritt:** Domain-Layer-Code uebergibt `TournamentId` mit ungueltigem
UUID-Substring (z.B. eingegebener Slug).
**Begruendung:** Server cast `uuid::text` immer in
Standard-UUID-Form (`xxxxxxxx-xxxx-...`), Client tut `id.value`
unveraendert. Beide Pfade gehen heute davon aus, dass `TournamentId.value`
schon ein valider UUID-String ist. Defekte Eingaben (Spaces, Casing)
fuehren zu Topic-Drift — der Trigger feuert in einen Namespace, in dem
keiner subscribed ist. Kein Privacy-Issue, aber stumme Funktionslosigkeit.
Empfehlung: Topic-Normalisierung im Client (lowercase, trim) oder
Validierung schon im Domain-Konstruktor.

## BH-B-15 — `tournament_set_score_proposals`-Trigger feuert auch fuer non-public Turniere ein NOTICE-Path mit JOIN
**Severity:** P3
**Datei:** `supabase/migrations/20260601000031_public_tournament_realtime.sql:181-185`
**Eintritt:** Jede Set-Score-Proposal-INSERT, unabhaengig von Tournament-
Public-Flag.
**Begruendung:** Der Trigger laeuft pro Proposal einen
`SELECT tournament_id FROM tournament_matches`-JOIN plus den
Visibility-Check. Fuer non-public-Turniere ist das pro Insert eine
zusaetzliche Lookup-Last. Nicht funktional broken (das Gating ist
korrekt), aber bei hochfrequenter Score-Eingabe in privaten Turnieren
zahlt jeder Insert die JOIN+IS_VISIBLE-Kosten. Optional als
`CREATE TRIGGER ... WHEN (...)`-Clause gateable, falls
`tournament_matches.tournament_id` schon vorab erreichbar waere.

## BH-B-16 — Pull+Push-Race: Trigger feuert zwischen RPC-Read und Re-Read kann zu Out-of-Order-UI fuehren
**Severity:** P2
**Datei:** `lib/features/tournament/presentation/public/public_tournament_screen.dart:61-68`
+ `lib/features/tournament/application/public_tournament_providers.dart:18-25`
**Eintritt:** Realtime-Event #1 trifft ein, screen ruft `ref.invalidate(...)`,
die RPC-Re-Read laeuft 200ms, Event #2 trifft ein und triggert *weitere*
Invalidate, Event #1-Future kommt zurueck **nach** Event #2-Future.
**Begruendung:** `publicTournamentDetailProvider` ist ein
`FutureProvider.family` ohne Last-Write-Wins-Versionierung. Riverpod
serializiert zwar die Invalidations, hat aber keinen
"verwirf alte Antwort"-Schutz, wenn die zweite Antwort frueher
zurueckkommt als die erste. Resultat: UI flackert oder zeigt
Zwischen-Snapshot. Klassischer Pull/Push-Race; lebt schon laenger im
authenticated-Pfad und repliziert sich hier ungefiltert. Mitigation:
Sequence-Stamp/Generation pro `invalidate`.

## BH-B-17 — Bracket-Visualizer zeigt veraltete Daten waehrend laufender KO-Phase
**Severity:** P2
**Datei:** `lib/features/tournament/presentation/public/public_tournament_screen.dart:416-472` (`_BracketTab`)
**Eintritt:** KO-Phase laeuft, `tournament_advance_ko_winner` schreibt
`winner_participant` + bumpt naechste Runde. Realtime-Event kommt, RPC
re-read laeuft, **aber** `_phaseFromWire` mappt `null` und `'group'` beide
auf `null` und filtert die Match-Liste streng.
**Begruendung:** Wenn die neue Runde noch keinen `participant_a/b`
zugewiesen bekommen hat (Trigger-Stall, Race), zeigt der Bracket-Tab
zwischenzeitig "Bracket noch nicht verfuegbar". Das ist mehr ein
Fallback-UX-Problem; nicht falsch, aber bei laufenden KO-Phasen
verwirrend. Eigentlicher Pull/Push-Effekt: User sieht "Bracket leer", obwohl
gerade ein Live-Match laeuft. Zusammenspielt mit BH-B-16.

## BH-B-18 — Drop-Migration 20260601000030: Tournament-Migrations-Folgen-Funktion `group_create` mit `jsonb`-Return-Override bleibt im Namensraum
**Severity:** P3
**Datei:** `supabase/migrations/20260601000030_drop_groups.sql:9`
**Eintritt:** Postgres-Functions-Identitaet ueber `(name, argtypes)`. Beide
Versionen aus 20260507000001 (`uuid`-return) und 20260507000002
(`jsonb`-return) wurden mit gleicher Signatur `group_create(text)`
deklariert; das Drop hier wird die letzte Version (jsonb) entfernen.
**Begruendung:** Korrekt — keine eigentliche Bug, aber das Drop verlaesst
sich auf die Tatsache, dass die jsonb-Version den uuid-Variant durch
`CREATE FUNCTION` ohne `OR REPLACE` (und vorgeschaltetem `DROP`) bereits
abgeloest hat. Wenn ein Squash der Migrations-Historie ohne Schritt
20260507000002 stattfindet, droppt diese Migration den `text`-Variant,
aber die `uuid`-Variant koennte uebrigbleiben. Verifizieren oder
explizit `DROP FUNCTION IF EXISTS public.group_create(text) CASCADE`
plus ein zusaetzliches `DROP FUNCTION ... uuid`-Statement.

## BH-B-19 — Drop-Migration: keine `DROP VIEW`/`DROP POLICY`-Vorabraeumung, Verlass auf CASCADE
**Severity:** P3
**Datei:** `supabase/migrations/20260601000030_drop_groups.sql:18-19`
**Eintritt:** `DROP TABLE ... CASCADE` raeumt heute die RLS-Policies
`groups_owner_select` (`20260507000001_social_graph.sql:65-67`) ab.
**Begruendung:** Funktional korrekt — `CASCADE` raeumt abhaengige
Policies und Indizes mit. Aber Migration-Style-mismatch zur Codebasis,
die in anderen Migrationen explizit `DROP POLICY IF EXISTS ... ON ...`
fuehrt. Audit-Trail wird unschaerfer. Cosmetic.

## BH-B-20 — Test-Datei testet die Lockstep-Pflicht zwischen Migration-Whitelist und Dart-Whitelist nur einseitig
**Severity:** P2
**Datei:** `test/features/tournament/data/public_tournament_realtime_test.dart:193-202`
**Eintritt:** Trigger emittiert eine *neue legitime* Spalte (z.B. eine
Pool-Phase-Erweiterung), Dart-Whitelist ist nicht synchron gepflegt.
**Begruendung:** Der Drift-Test (`some_new_column` -> StateError) prueft
**Client-side**: Whitelist im Decoder reicht aus, um den Test
fehlzuschlagen. **Migration-side** existiert kein Gegen-Pendant: ein
pgTAP-Test, der die im SQL-`jsonb_build_object`-Aufruf gelisteten Keys
gegen einen Erwartungs-Set vergleicht, fehlt. Folge: Wenn die Migration
einen Key vergisst (z.B. `consensus_round`), faellt das im Flutter-Test
auf — aber wenn umgekehrt die Migration einen Key *hinzufuegt*, ohne den
Dart-Whitelist zu pflegen, ist der Test nur reaktiv (failt erst nach
realtime-load in der Test-Umgebung). Symmetrie fehlt.

## BH-B-21 — `_FakeRealtime` umgeht die `payload['payload']`-Envelope-Verschachtelung im echten Codepfad
**Severity:** P2
**Datei:** `test/features/tournament/data/public_tournament_realtime_test.dart:38-46` vs.
`lib/features/tournament/data/public_tournament_realtime.dart:251-254`
**Eintritt:** Production-Pfad bekommt `{event: 'match_status', payload:
{...}}`-Envelope (Supabase-Realtime-Standardform). Fake pusht direkt das
flache Whitelist-Object.
**Begruendung:** Die Defensiv-Logik in `handlePayload`
(`payload['payload']` extrahieren, sonst Top-Level) wird durch den
`_FakeRealtime` **nicht** verifiziert — der Fake pusht direkt die
gewuenschte Form. Wenn Supabase die Envelope-Form aendert
(Major-Update), schlaegt der Test trotzdem nicht aus. Empfehlung:
Test-Case mit verschachteltem `payload`-Key, der durch den realen
Adapter laeuft (statt durch den Fake).

---

## Summary

Befunde gesamt: 21
P0: 0
P1: 3 (BH-B-01, BH-B-10, BH-B-11)
P2: 11 (BH-B-02, BH-B-03, BH-B-04, BH-B-05, BH-B-07, BH-B-08, BH-B-09, BH-B-13, BH-B-16, BH-B-17, BH-B-20, BH-B-21)
P3: 7 (BH-B-06, BH-B-12, BH-B-14, BH-B-15, BH-B-18, BH-B-19)

P0-Liste: (keine)

Top-3-Risiken (Empfehlung Triage):
1. **BH-B-01** — Reconnect-Loch im Public-Realtime-Adapter; Offline→Online
   liefert keinen Resubscribe. Funktional spuerbar fuer den realen
   Spectator-Pfad.
2. **BH-B-10 + BH-B-11** — Doppel-Testluecke: weder Dart noch pgTAP
   instrumentieren die produktiv aktive Pipeline; Privacy-Anker (kein
   `user_id`/`submitter_user_id`/`email`/`nickname` im Topic) ist nur
   *konzeptionell* gepinnt, nicht im Test.
3. **BH-B-08** — Dead-Code `publicTournamentPollingProvider` +
   `publicLiveModeProvider`: der ADR-vorgesehene "Polling default,
   Live-Mode-Toggle" ist nicht erreichbar, jede Public-Page startet
   sofort einen Realtime-Channel (Cost/Quota), und der Polling-Pfad
   ruft den *authenticated* `tournamentMatchListProvider` — Re-Hookup
   wuerde anon-Pfad killen.

Keine produktiv broken Privacy-Lecks gefunden; der Server-Trigger pflegt
die Spalten-Whitelist sauber. Hauptrisiken liegen in Reconnect-Lifecycle,
fehlender Test-Tiefe und Dead-Code im Pfad-Switcher.
