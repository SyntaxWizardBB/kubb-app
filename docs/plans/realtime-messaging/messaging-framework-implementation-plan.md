# Unified Messaging Framework — Umbau-Plan (Implementation)

**Status:** Plan — ready to implement
**Branch (Vorschlag):** `feat/realtime-sync`
**Verbindliche Grundlage:** [ADR-0029 — Unified Messaging and Battery Lifecycle](../../adr/0029-unified-messaging-and-battery-lifecycle.md) (Accepted, 2026-06-06) und [messaging-framework-plan.md](./messaging-framework-plan.md).

> **Zweck.** Dieser Plan ist die sequenzierte, einzeln mergebare Umsetzung von ADR-0029. Er **verfeinert** die dortigen Vorgaben (Transport-Auswahlregel, Battery-Lifecycle-Regime, Ziel-Client-API) und widerspricht ihnen nicht. ADR-0029 **amendiert** ADR-0021 — der `RealtimeChannel`-Port, der Refcount/500-ms-Debounce/Backoff-Adapter und der Polling-Fallback bleiben gültige Basis und werden nur generalisiert. Es wird **kein neuer Mechanismus** erfunden; alle Bausteine existieren bereits prototypisch im Tournament-Pfad und werden auf einen app-weiten Vertrag gehoben.

---

## (a) Zielbild in drei Sätzen

1. Jede Cross-Device-/Sync-/Notification-Stelle nutzt den **billigsten passenden Transport** (Broadcast → Inbox → CDC → Listen-Invalidierung/Push, erster Treffer gewinnt) über **genau eine** multiplexte WebSocket, statt heute ~7.200–9.000 Foreground-Wake-ups/h durch 14 unabhängige `Timer.periodic`-Poller.
2. Authentifizierter Per-User-State bekommt **echtes CDC** auf einer indexierten Single-Column-Filterspalte (`user_id`/`team_id`/`tournament_id`/`id`); Freunde sind die EINE Ausnahme über die denormalisierte, Trigger-gepflegte `friend_edges`-Tabelle; anon-Spectator bleibt Broadcast.
3. Im Hintergrund gilt **0 Sockets + 0 Timer** (Push ist der einzige Background-Wake-Pfad, vorerst gestubbt); Polling existiert nur noch als Failure-Mode (≥60 s `errored` → 30 s, anon 10 s), schaltbar über den Kill-Switch `realtimeEnabledFlagProvider`.

---

## (b) Vollständige Inventur — alle 27 Stellen mit Ziel-Transport & Migrations-Status

Alle Pfade relativ zu `/home/lukas/Workbench/FlutterKubbClub/KubbProj/`. Die Spalte **Auflösung** dokumentiert explizit, wo die Owner-§9-Verschärfung (echtes CDC) die ältere Inventur-/Plan-§4-Klassifikation (`inbox-invalidation`) ablöst.

### b.1 Polling-Stellen, die migriert werden (Server-Discovery)

| Stelle | Datei | Heute | Ziel-Transport | Auflösung / Migrations-Status | Phase |
|---|---|---|---|---|---|
| Inbox messages | `lib/features/inbox/application/inbox_controller.dart` | `Timer.periodic 1s` + `refreshFromRemote` | **CDC** `inboxRealtimeChannelKey` | Drift-cache-Variante: CDC ersetzt nur den Discovery-Timer, `refreshFromRemote` bleibt. Publication-ADD nötig; RLS `user_id=auth.uid()` existiert bereits. | P1 |
| Friends list | `lib/features/social/application/social_providers.dart` | `Timer.periodic 1s` + `invalidate(friendsListProvider)` | **CDC** `friendsRealtimeChannelKey` via `friend_edges` | Inventur sagte `inbox-invalidation`; §9 verschärft auf echtes CDC. `friendships` ist composite-PK → neue denormalisierte `friend_edges`-Tabelle + Trigger. | P3 |
| Team list | `lib/features/team/application/team_providers.dart` | `Timer.periodic 4s` + `invalidate(teamListProvider)` | **CDC** `myTeamsRealtimeChannelKey` | Inventur sagte `inbox-invalidation`; §9 → echtes CDC auf `team_memberships.user_id`. Additive `self_read`-Policy nötig. | P7 |
| Team detail | `lib/features/team/application/team_providers.dart` | `Timer.periodic 4s` + `invalidate(teamDetailProvider(teamId))` | **CDC** `teamRealtimeChannelKey` | CDC auf `team_memberships.team_id`; bestehende Pool-Policy deckt. | P7 |
| Match detail | `lib/features/match/application/match_providers.dart` | `Timer.periodic 1s` + `invalidate`, Terminal-Stop | **CDC** `matchRealtimeChannelKey` (`matches:id`) | Inventur sagte `inbox-invalidation`; §9 → Single-Row-CDC auf `public.matches.id` (RPC `match_get` liest `public.matches`, NICHT `tournament_matches` — disjunkte uuid-Räume). Eigene Publication-/RLS-Migration nötig (SRV-09). | P7 |
| Tournament list | `lib/features/tournament/application/tournament_list_provider.dart` | `Timer.periodic 5s` + `invalidate` | **CDC** `myTournamentsRealtimeChannelKey` | Inventur sagte `inbox-invalidation`; §9 → echtes CDC auf `tournament_participants.user_id`. Additive `self_read`-Policy nötig. | P7 |
| Tournament detail | `lib/features/tournament/application/tournament_list_provider.dart` | `Timer.periodic 5s` + `invalidate`, Terminal-Stop | **CDC** `tournamentRealtimeChannelKey` (`tournament_matches:tournament_id`) | CDC bestehend; Polling löschen. **`tournaments`-Tabelle wird bewusst NICHT publiziert** (ADR-0029 Broadcast-Regel) → reine Status-only-Transition = akzeptierte 30-s-Restlücke. | P7 |
| Tournament bracket | `lib/features/tournament/application/tournament_bracket_provider.dart` | `Timer.periodic 5s` | **Broadcast** `tournamentBroadcastTopic` (CDC `tournamentBracketRealtimeProvider` LIVE) | NICHT löschen → von unconditional auf **fallback-gated** umbauen. Keine neue Server-Migration. | P2 |
| Tournament match list | `lib/features/tournament/application/tournament_match_providers.dart` | `Timer.periodic 5s` (unconditional, Gating fehlt) | **Broadcast** / CDC LIVE | Von unconditional auf fallback-gated; an generalisierten Fallback-Provider koppeln. | P2 |
| Tournament match detail | `lib/features/tournament/application/tournament_match_providers.dart` | `Timer.periodic 5s`, Terminal-Stop | **Broadcast** / CDC LIVE | Gating fertigstellen. | P2 |
| Tournament pool standings | `lib/features/tournament/presentation/tournament_pool_standings_screen.dart` | `Timer.periodic 5s` | **Broadcast** | Von unconditional auf fallback-gated. | P2 |
| Public tournament anon | `lib/features/tournament/application/public_tournament_polling_provider.dart` | `Timer.periodic 10s` | **Broadcast** (anon, `tournamentBroadcastTopic`) | Bleibt als anon-Fallback (kein CDC für anon, ADR-0026), aber auf **10 s fallback-gated** + Kill-Switch „Live-Modus aus". | P2/P4 |

### b.2 Bereits LIVE (CDC/Broadcast) — nur Konsolidierung (Wave 0)

| Stelle | Datei | Status | Auflösung |
|---|---|---|---|
| Realtime tournament match CDC | `lib/features/tournament/application/tournament_realtime_provider.dart` | LIVE (ADR-0021, OD-M4-01) | Bleibt; konsumiert künftig zentralen Singleton + zentrale Keys. |
| Realtime tournament match detail CDC | `lib/features/tournament/application/tournament_realtime_provider.dart` | LIVE | Bleibt. |
| Realtime tournament bracket advances | `lib/features/tournament/application/tournament_realtime_provider.dart` | LIVE (OD-M4-01) | Bleibt; trägt Bracket-Live, Polling wird nur fallback-gated. |
| Realtime fallback channel state machine | `lib/features/tournament/application/realtime_fallback_provider.dart` | LIVE | **Wird zum dünnen Delegator** auf generalisierten `realtimePollingFallbackProvider(channelKey)`. |
| Public tournament anon broadcast | `lib/features/tournament/data/public_tournament_realtime.dart` | LIVE (ADR-0026, W3-T5) | Wird **thin mapper** auf neuen `BroadcastChannel`-Port; Privacy-Whitelist bleibt. |
| Realtime adapter (CDC) | `lib/core/data/realtime/supabase_realtime_channel.dart` | LIVE | Lifecycle-Mechanik wird in geteilten Mixin extrahiert; pause/resume-Snapshot ergänzt. |
| Lamport clock server stream sync | `lib/features/match/application/lamport_clock_provider.dart` | LIVE (M4.3-T4) | **Gap:** erzeugt heute eigene Adapter-Instanz statt Singleton → nach Wave-0-Singleton auf `realtimeChannelProvider` umstellen (Folge-Task). |

### b.3 Bewusst NICHT migriert — `keep-as-is` (Lösch-Regel-Ausnahme, ADR-0029 §380-388)

Diese Stellen wecken das Radio nicht (UI-Ticker / lokales Drift / Crypto-Token) und bleiben unverändert. Der Lifecycle-Controller pausiert lediglich den `KeypairSessionRefresher` (one-shot, kein periodisches Server-Polling); UI-Ticker folgen Flutters Frame-Lifecycle.

| Stelle | Datei | Begründung |
|---|---|---|
| Outbox-Pending (2s) | `lib/features/tournament/application/outbox_pending_provider.dart` | Lokales Drift-Read; `pending()`-Query nicht reaktiv selectable (ADR-0022). Kein Radio-Wake. |
| Offline-Banner (60s) | `lib/core/ui/widgets/kubb_offline_banner.dart` | Reiner UI-Timestamp-Aging-Ticker („letzte Sync vor n min"). Kein Netzwerk. |
| Match-Countdown (1s) | `lib/features/tournament/presentation/widgets/match_countdown.dart` | UI-Ticker (mm:ss), `WallClockCountdownTicker`. Keine Discovery. |
| Match-Await (1s) | `lib/features/match/presentation/match_await_others_screen.dart` | UI-Elapsed-Time-Anzeige. |
| Auth keypair session refresh (one-shot) | `lib/features/auth/application/keypair_session_refresher.dart` | Scheduled JWT-Renewal bei `expiresAt − 5min`. Crypto-Token, kein Server-Discovery. Wird vom Lifecycle-Controller pausiert/resumed. |
| Auth restore cooldown (one-shot) | `lib/features/auth/application/restore_controller.dart` | UI-State-Cooldown nach 3 Failures. |
| Auth restore flow UI ticker (1s) | `lib/features/auth/presentation/restore_flow.dart` | Cooldown-Badge-Countdown. |
| Realtime state banner UI (1.5s/60s) | `lib/features/tournament/presentation/widgets/realtime_state_banner.dart` | UI-Badge-Sichtbarkeit, reine Cosmetics. |

### b.4 Offene Gaps aus der Inventur — Entscheidung

- **Lamport-Clock-Adapter-Instanz** (`lamport_clock_provider.dart`): erzeugt heute `SupabaseRealtimeChannel(Supabase.instance.client)` lokal statt des Singletons. → Nach Wave 0 auf `realtimeChannelProvider` umstellen, sonst app-weites Refcount/Multiplexing gebrochen (Folge-Task, in P8 mitgeführt).
- **Training (gesamter Kontext `lib/features/training/`)**: **`keep-as-is` — verbindliche Owner-Vorgabe.** Training (Finisseur/Sniper-Solo-Sessions) pollt keinen Server-State: Persistenz läuft über lokales Drift (`training_repository`/`finisseur_repository`) + `training_sessions`-Cloud-Upsert (`cloud_training_repository.dart`), die „Zuletzt"-Zusammenführung (`recent_sessions_provider.dart`) ist ein einmaliger Read (kein Timer). Es wird **NICHTS** am Training-Sync geändert — kein CDC, kein Umbau, auch nicht opportunistisch. (`training_sessions` wird **nicht** in die Realtime-Publication aufgenommen.)
- **Achievements**: reine Drift-Streams ohne Server-CDC. Korrekt belassen (lokal-persistent). Achievements-Badge-Transport: gemäß Transport-Regel **Broadcast** falls Fan-out/abgeleitet, sonst dokumentiert Drift-only — Entscheidung vor P8-Merge.
- **Public-Fallback-Granularität**: invalidiert heute nur `tournamentMatchListProvider`, nicht Detail. Für anon-Spectator (Liste reicht) belassen.

---

## (c) Framework-Kern (Transport- & Lifecycle-Fundament)

Vier geteilte Bausteine, die danach jeder Concern **nur noch konsumiert** — strikt Generalisierung des bestehenden CDC-Pfads, kein neuer Mechanismus.

1. **Gemeinsamer Lifecycle-Mixin** (Refcount, 500 ms Close-Debounce, `1/2/4/8/30 s`-Backoff, `stateStream`), den CDC- **und** Broadcast-Adapter teilen. Heute dupliziert in `SupabaseRealtimeChannel._ChannelEntry` und `SupabasePublicTournamentRealtime._ChannelEntry`.
2. **`BroadcastChannel`-Port** als Sibling zu `realtime_channel.dart` + `BroadcastMessage`-Value; `SupabasePublicTournamentRealtime` wird thin mapper.
3. **Generalisierter `realtimePollingFallbackProvider`** (`StreamProvider.autoDispose.family<bool, String /*channelKey*/>`) aus dem turnier-spezifischen `realtimeFallbackProvider`. Boolean-Gate, keine eigene Datenquelle. Kadenz (30 s / anon 10 s) gehört in den jeweiligen Concern-Poller, NICHT in das Gate.
4. **Channel-Key-Builder** zentral in `packages/kubb_domain/lib/src/realtime/` — nie mehr handgebaut am Call-Site (sonst toter Channel ohne Fehler).
5. **App-Lifecycle-Controller** + **App-Singleton-Adapter** (`realtimeChannelProvider` / `broadcastChannelProvider` am Bootstrap überschrieben, eine WebSocket / N Kanäle).

### Architektur-Invarianten (verbindlich aus ADR-0029)

- CDC filtert **ausschließlich** über Single-Column-Equality; Port `subscribe(table, filterColumn, filterValue)` bleibt unverändert.
- CDC-Key-Konvention `<table>:<column>=<value>`; Broadcast-Topic `<domain>_events:<scope_id>`. Die `kubb_domain`-Builder MÜSSEN exakt `SupabaseRealtimeChannel._keyFor` / `fakeRealtimeChannelKey` treffen.
- Genau **eine** Supabase-Client-Instanz (Singleton). Refcount multiplext; N Screens auf gleichem Key = 1 Channel.
- Polling **nur** über `realtimePollingFallbackProvider` (≥60 s `errored`). Kein neuer `Timer.periodic` für Server-State.
- Inbox-Subscription auf **App-Shell-Scope** (durable über Navigation, speist das Badge).

> **Konflikt-Auflösung (Architekten):** `framework-core` legt die Key-Builder in `src/realtime/realtime_channel_keys.dart`, `client-migration`/`test-rollout` in `src/realtime/channel_keys.dart`. **Verbindlich: `src/realtime/channel_keys.dart`** (kürzer, konsistent mit dem `test-rollout`-Pfad). Analog liegt der Lifecycle-Controller verbindlich unter `lib/app/realtime_lifecycle_controller.dart` (nicht `lib/core/application/…`), damit er am Shell-Scope sichtbar ist. Der generalisierte Fallback-Provider liegt verbindlich in `lib/features/tournament/application/realtime_fallback_provider.dart` (Umzug nach core optional, nicht blockierend) — der alte `realtimeFallbackProvider(TournamentId)` bleibt als dünner Delegator.

### Kern-Tasks

| Task | Titel | Dateien | Verifikation |
|---|---|---|---|
| **FC-1** | Lifecycle-Mixin extrahieren (Refcount + 500 ms Debounce + 1/2/4/8/30 s Backoff + `stateStream`) | `lib/core/data/realtime/realtime_channel_lifecycle.dart`, `lib/core/data/realtime/supabase_realtime_channel.dart` | `test/core/data/realtime/supabase_realtime_channel_test.dart` unverändert grün; neuer Mixin-Unit-Test über Test-Doppel-Subtyp (2 subscribe→refCount==2, 2. close→nach 500 ms genau 1 `teardownTransport`; `errored`→1/2/4/8/30 s via FakeAsync). |
| **FC-2** | `BroadcastChannel`-Port + `BroadcastMessage`-Value (RealtimeChannelState wiederverwenden, nicht duplizieren) | `packages/kubb_domain/lib/src/ports/broadcast_channel.dart`, `packages/kubb_domain/lib/src/values/broadcast_message.dart`, `packages/kubb_domain/lib/kubb_domain.dart` | `dart test packages/kubb_domain/test/values/broadcast_message_test.dart` (==/hashCode/immutability); `dart analyze packages/kubb_domain` clean. |
| **FC-3** | `FakeBroadcastChannel` + `emit`/`setState`/State-Replay | `packages/kubb_domain/lib/src/test_support/fake_broadcast_channel.dart` | Unit-Test: 2 subscribe teilen Stream; `setState`-Replay an Late-Subscriber; `close` schließt Controller. |
| **FC-4** | `SupabaseBroadcastChannel`-Adapter auf gemeinsamem Mixin; `SupabasePublicTournamentRealtime` → thin mapper | `lib/core/data/realtime/supabase_broadcast_channel.dart`, `lib/features/tournament/data/public_tournament_realtime.dart` | `test/features/tournament/data/public_tournament_realtime_test.dart` (Privacy-Whitelist, `fromPayload`, forbidden columns) grün mit Fake-Backing. |
| **FC-5** | Channel-Key-Builder zentral (`channel_keys.dart`) inkl. Umzug `tournamentRealtimeChannelKey` + Rename `publicTournamentRealtimeTopic`→`tournamentBroadcastTopic` | `packages/kubb_domain/lib/src/realtime/channel_keys.dart`, `packages/kubb_domain/lib/kubb_domain.dart`, `lib/features/tournament/application/realtime_fallback_provider.dart`, `lib/features/tournament/data/public_tournament_realtime.dart` | `dart test packages/kubb_domain/test/realtime/` — golden strings je Builder; Kreuz-Test `tournamentRealtimeChannelKey(id) == fakeRealtimeChannelKey(...) == _keyFor`-Form. |
| **FC-6** | Generalisierter `realtimePollingFallbackProvider<bool,String>`; alter `realtimeFallbackProvider(TournamentId)` → Delegator | `lib/features/tournament/application/realtime_fallback_provider.dart` (+ optional `lib/core/application/`) | `realtime_polling_fallback_provider_test.dart` (joined→false; errored+59 s→false; +1 s→true; reconnect→cancel; flag off→true). |
| **FC-7** | `realtimeChannelProvider` + `broadcastChannelProvider` als App-Singletons am Bootstrap überschreiben; `tournamentRemoteProvider`/`publicTournamentRealtimeProvider` auf `ref.watch` umstellen | `lib/app/bootstrap.dart` bzw. `lib/main.dart`, `lib/features/tournament/data/tournament_repository.dart`, `lib/features/tournament/data/public_tournament_realtime.dart` | Provider-Test: zwei Repos lesen `identical()` Adapter; `tournament_realtime_e2e_test.dart` grün; Bootstrap-Smoke ohne `UnimplementedError`. |
| **FC-8** | `RealtimeLifecycleController` (pause/resume + Snapshot der aktiven Keys; `snapshotActiveKeys`/`disconnectAll`/`reconnectKeys` am Mixin) | `lib/app/realtime_lifecycle_controller.dart`, `lib/core/data/realtime/realtime_channel_lifecycle.dart`, `supabase_realtime_channel.dart`, `supabase_broadcast_channel.dart` | `realtime_lifecycle_controller_test.dart` (fake_async): paused nach 5 s→snapshot=={k1,k2}, `disconnectAll`→0 Kanäle/0 `pendingTimers`; resumed→re-sign ZUERST (Call-Recorder), dann genau k1,k2; inactive→no-op; detached→sofort. |
| **FC-9** | Controller in `KubbApp` verdrahten (Resume-Sequenz; re-sign wandert in Controller) | `lib/app/app.dart` | `app_lifecycle_test.dart` (testWidgets): paused→`disconnectAll` + Refresher pausiert; resumed→re-sign vor reconnect; keine offenen Sockets/Timer im paused-Zweig. |
| **FC-10** | Architektur-Guard: kein neuer `Timer.periodic` für Server-State, Keys nur über Builder, kein zweiter Client | `test/architecture/messaging_framework_guard_test.dart` | Test failt bei neuem ungated `Timer.periodic` außerhalb Allowlist oder handgebautem Key-Literal; grün auf Kern-Stand. |

---

## (d) Server-Seite (CDC-Targets, Inbox-Spine, Migrationen)

### Ausgangslage (verifiziert gegen Migrations)

- **Keine** Tabelle ist heute in `supabase_realtime` publiziert — der einzige Treffer ist ein Kommentar in `20260601000031_public_tournament_realtime.sql`. CDC läuft faktisch nur lokal (CLI publiziert `FOR ALL TABLES`); in Staging/Prod würde `tournament_matches`-CDC **still scheitern**.
- **Inbox-Spine existiert**: `public.user_inbox_messages` (`20260504000011`), Scope `user_id`, RLS `user_inbox_messages_owner_read USING (user_id = auth.uid())` — der Modell-RLS-Fall (Filterspalte == USING-Spalte).
- **Inbox-Producer schreiben bereits** (Friends, Teams, Clubs, Tournament-Registration, Go-Live, Shootout). **KEINE mutation-RPC-Änderungen** (ADR-0029).

### Zentrales RLS-Problem (architekturkritisch)

ADR-0029 verlangt: **Filterspalte und RLS-USING-Spalte MÜSSEN dieselbe sein.** Die bestehenden SELECT-Policies erfüllen das nicht durchgängig:

| Tabelle | CDC-Filterspalte | Bestehende USING | Deckungsgleich? | Maßnahme |
|---|---|---|---|---|
| `user_inbox_messages` | `user_id` | `user_id = auth.uid()` | ✅ | nur Publication-ADD |
| `team_memberships` (`team_id`) | `team_id` | `is_active_team_member(team_id, auth.uid())` | ⚠️ indirekt | Pool-Policy NICHT antasten |
| `team_memberships` (`user_id`, my-teams) | `user_id` | kein `user_id=auth.uid()` | ❌ | **additive** `self_read`-Policy |
| `tournament_participants` (`user_id`) | `user_id` | `EXISTS(tournaments … status<>'draft')` | ❌ | **additive** `self_read`-Policy |
| `tournament_matches` (`tournament_id`/`id`) | `tournament_id`/`id` | `EXISTS(tournaments …)` (nicht spaltengebunden) | ⚠️ deckt beide | keine neue Policy, nur RLS-Test |
| `matches` (Standalone, `id`) | `id` | `matches_participant_read` (`created_by=auth.uid() OR EXISTS match_participants`) | ⚠️ deckt `id`-Filter | keine neue Policy, nur Publication-ADD + RLS-Test (SRV-09) |
| `friendships` | — (composite PK) | `auth.uid() IN (low,high)` | ❌ | → neue `friend_edges` |

Additive Policies sind OR-verknüpft → keine Regression für bestehende Pool-Reads. `is_active_team_member` ist SECURITY DEFINER (Recursion-Fix `20260901000010`) — **nicht antasten**, additive `self_read` (`user_id=auth.uid()`) ist rekursionsfrei.

### CDC-Target-Migrationen (je drei ADR-0029-Bausteine: Publication + REPLICA IDENTITY + Policy)

`REPLICA IDENTITY` überall **DEFAULT** (kein Client liest old-row außer DELETE-Filter via PK). Jede `ALTER PUBLICATION` ist nicht idempotent → DO-Block mit `pg_publication_tables`-Vorab-Check.

> **Vorab-Verifikation (verbindlich in jeder SRV-Task).** Vor dem Festlegen eines Migrations-Dateinamens `ls supabase/migrations | sort | tail` ausführen — der neue Timestamp MUSS strikt NACH der jüngsten bestehenden Migration (`20261205000000`) liegen. Frühere Timestamps (z. B. `20260606*`) sortieren VOR ~30 bereits angewendeten Migrationen und werden auf einer migrierten DB nie ausgeführt → CDC scheitert still.

| Task | Titel | Datei | Verifikation |
|---|---|---|---|
| **SRV-01** | `user_inbox_messages` in Publication (Stufe 1, kleinster Blast-Radius); RLS bereits deckungsgleich | `supabase/migrations/20261206000001_cdc_user_inbox_messages.sql` | psql: `pg_publication_tables` enthält `user_inbox_messages`; pgTAP: User-A sieht `user_id=A`, `user_id=B` leer. |
| **SRV-02** | `tournament_matches` in Publication (CDC legalisieren); keine neue Policy | `supabase/migrations/20261206000002_cdc_tournament_matches.sql` | psql publiziert; pgTAP: published-Turnier-Matches lesbar, draft fremder Creator nicht. |
| **SRV-03** | `team_memberships` CDC + additive `team_memberships_self_read USING (user_id=auth.uid())` | `supabase/migrations/20261206000003_cdc_team_memberships.sql` | pgTAP: `user_id=A`→eigene; `team_id=T`→nur aktives Mitglied; Nicht-Mitglied leer. |
| **SRV-04** | `tournament_participants` CDC + additive `tournament_participants_self_read USING (user_id=auth.uid())` | `supabase/migrations/20261206000004_cdc_tournament_participants.sql` | pgTAP: `user_id=A`→eigene Registrierung auch in draft; `user_id=B` leer. |
| **SRV-05** | `friend_edges` (NEU) + Trigger-Denormalisierung aus `friendships` (beide Richtungen) + Backfill + Publication + RLS `owner_user_id=auth.uid()` | `supabase/migrations/20261206000005_friend_edges_cdc.sql` | psql: publiziert; `friend_edges`-count == 2× `friendships`; pgTAP: accept→(A,B)+(B,A); remove→beide weg; owner-isolation. |
| **SRV-06** | `user_inbox_messages` AFTER-INSERT Push-Seam-Trigger (PII-freier Nudge `id/kind/subject/sent_at`; `push_outbox` Stub) | `supabase/migrations/20261206000006_inbox_push_seam.sql` | psql: INSERT löst `realtime.send` aus, Payload ohne `body`/`action_payload`; pgTAP: Trigger SECURITY DEFINER. |
| **SRV-09** | `public.matches` in Publication (Standalone-Match-CDC, REPLICA IDENTITY DEFAULT); keine neue Policy — bestehende `matches_participant_read` (`created_by=auth.uid() OR EXISTS match_participants`) deckt den `id`-Filter | `supabase/migrations/20261206000007_cdc_matches.sql` | psql: `pg_publication_tables` enthält `matches`; pgTAP-Parität gegen `matches_participant_read`: Creator/Participant lesen eigene Row, Fremder leer. |
| **SRV-07** | Konsolidierte pgTAP-Suite: Realtime-RLS-Parität aller CDC-Targets | `supabase/tests/realtime_cdc_rls_test.sql` | `supabase test db` grün; Filterspalte==USING-Spalte pro Target bewiesen. |
| **SRV-08** | Verifikations-Snapshot: Publication + REPLICA IDENTITY gegen lokalen Stack (erwartet exakt 6 Tabellen, alle `relreplident='d'`, `tournaments` NICHT enthalten) | `supabase/tests/verify_cdc_publication.sql` | psql `-f`: Ist-Menge == Soll-Menge; kein FULL; `tournaments`/`tournament_set_score_proposals` nicht publiziert (Broadcast-only). |

> **Inbox-Spine-Fazit.** Es fehlt **kein** durable Producer-Write für die §9-CDC-Listen — alle Producer schreiben bereits Inbox **und** mutieren die Member-/Participant-/Edge-Row, die CDC trägt. Net-new Server-Code ist nur (a) der Fan-out-Push-Seam-Trigger (SRV-06) und (b) die `friend_edges`-Denormalisierung (SRV-05); reine Publication-ADDs (inkl. `public.matches`, SRV-09) tragen keinen neuen Producer. **Einzige bewusst akzeptierte Polling-Restlücke:** `tournaments`-Status-only-Transitions (`registration_open`→`registration_closed`/`finalized`) ohne Match-/Participant-Write erzeugen kein my-Listen-CDC → 30-s-Fallback-Polling (ADR-0029 Polling=Failure-Mode). Optionale spätere Erweiterung des Go-Live-Inbox-Musters (`20261201000010`) liegt außerhalb dieses Server-Scopes.

### Server-Verifikation

pgTAP-Harness (`supabase test db`, `000-setup-tests-hooks.sql`), Role-Switch via `set_config('role',…)` + JWT-Claim. Pro CDC-Target zwei Ebenen: (1) Publication-Check (`pg_publication_tables` + `relreplident`); (2) RLS-Realtime-Parität (`<filter_col>=eigene-uid`→Rows, `=fremde-uid`→leer). Läuft gegen lokalen Stack (`supabase start` — NixOS-Build-Stolperstein beachten, Memory `local_supabase_edge_auth.md`).

---

## (e) Client-Migration pro Concern

Jede migrierte Stelle behält ihren alten Read-Provider (`*Provider`) unverändert — nur der **Discovery-Mechanismus** wechselt vom Timer auf den Stream. Der alte `*PollingProvider` wird erst gelöscht, **nachdem** Stream-Provider + Fallback verdrahtet und getestet sind (verhindert Doppel-Pfad).

| Task | Concern / Titel | Dateien | Verifikation |
|---|---|---|---|
| **C1-T1** | Inbox-CDC-StreamProvider (Shell-Scope) | `lib/features/inbox/application/inbox_controller.dart`, `lib/app/app.dart`, `supabase/migrations/20261206000001_cdc_user_inbox_messages.sql` | Provider-Test (FakeRealtimeChannel): `emit(inboxKey,change)`→`refreshFromRemote`→`inboxMessagesProvider` emittiert ohne Timer; Staging-Smoke. |
| **C1-T2** | `inboxPollingProvider` löschen + Shell-Wiring + Fallback | `lib/features/inbox/application/inbox_controller.dart`, `lib/app/app.dart`, `test/features/inbox/inbox_controller_test.dart` | grep: keine `inboxPollingProvider`-Referenz; Widget-Test Inbox rendert + CDC-Update; Fallback errored 60 s→30 s. |
| **C2-T1** | `friend_edges` + Trigger + Backfill (Migration = SRV-05) | `supabase/migrations/20261206000005_friend_edges_cdc.sql` | pgTAP Konsistenz; Backfill-Count==2× friendships. |
| **C2-T2** | Friends-CDC-StreamProvider; `friendsPollingProvider` löschen | `lib/features/social/application/social_providers.dart`, `test/features/social/social_providers_test.dart` | Provider-Test: `friend_edges`-change→`friendsListProvider` invalidiert; grep: kein `friendsPollingProvider`. |
| **C3-T1** | `team_memberships` CDC-Migration (= SRV-03) | `supabase/migrations/20261206000003_cdc_team_memberships.sql` | Staging: `user_id`→eigene, `team_id`→Pool; Cross-Device-Beitritt. |
| **C3-T2** | Team-Liste (`myTeams`) + Detail (`team_id`) CDC; Team-Poller löschen | `lib/features/team/application/team_providers.dart`, `test/features/team/team_providers_test.dart` | Provider-Test: membership-CDC invalidiert Liste/Detail; grep: keine `team*PollingProvider`; cross-container Roster-Update. |
| **C4-T1** | `tournament_participants` CDC-Migration (= SRV-04) | `supabase/migrations/20261206000004_cdc_tournament_participants.sql` | Staging: `user_id`→eigene Teilnahmen; Cross-Device. |
| **C4-T2** | Tournament-Liste echtes CDC (`myTournaments`, §9 NICHT inbox-invalidation); Poller löschen | `lib/features/tournament/application/tournament_list_provider.dart`, `test/features/tournament/tournament_list_provider_test.dart` | Provider-Test: participant-CDC invalidiert Liste; grep: kein `tournamentListPollingProvider`. |
| **C4-T3** | Tournament-Detail CDC (`tournament_matches:tournament_id`); Terminal-Stop; Poller löschen | `lib/features/tournament/application/tournament_list_provider.dart`, `test/features/tournament/tournament_detail_realtime_test.dart` | Provider-Test: CDC invalidiert Detail; nach finalized kein weiteres invalidate. |
| **C4-T4** | Bracket + Pool-Standings Poller auf Fallback-Gating (CDC LIVE) | `lib/features/tournament/application/tournament_bracket_provider.dart`, `lib/features/tournament/presentation/tournament_pool_standings_screen.dart`, `test/features/tournament/tournament_bracket_provider_test.dart` | Provider-Test: joined→kein invalidate; errored≥60 s→30 s; Broadcast aktualisiert sofort. |
| **C4-T5** | Tournament-Match Liste/Detail-Poller fallback-gaten (CDC LIVE) | `lib/features/tournament/application/tournament_match_providers.dart`, `test/features/tournament/tournament_match_providers_test.dart` | Provider-Test: joined→kein invalidate; errored≥60 s→Poll; finalized/voided→stop. |
| **C5-T1** | Standalone-Match CDC (`matches:id` auf `public.matches`, §9 NICHT inbox-invalidation; benötigt SRV-09); Terminal-Stop; `matchPollingProvider` löschen | `lib/features/match/application/match_providers.dart`, `supabase/migrations/20261206000007_cdc_matches.sql`, `test/features/match/match_providers_test.dart` | Provider-Test: CDC invalidiert `matchDetailProvider`; finalized→stop; grep: kein `matchPollingProvider`. |
| **C6-T1** | Spectator-Fallback (anon) auf 10 s-Gating + Kill-Switch („Live-Modus aus") | `lib/features/tournament/application/public_tournament_polling_provider.dart`, `test/features/tournament/public_tournament_polling_test.dart` | Provider-Test: joined→kein Poll; errored≥60 s ODER flag off→10 s-invalidate. |
| **C7-T1** | `RealtimeLifecycleController` scharf (= FC-8/FC-9 verdrahtet) | `lib/app/app.dart`, `lib/app/realtime_lifecycle_controller.dart`, `supabase_realtime_channel.dart`, `lib/features/auth/application/keypair_session_refresher.dart`, `test/app/realtime_lifecycle_controller_test.dart` | fake_async: paused→5 s→0 Channels/0 Timer; detached→sofort; resume→re-sign vor reconnect, nur zuvor aktive Keys; inactive→no-op. |
| **C8-T1** | Push-Seam Trigger (= SRV-06, Stub) | `supabase/migrations/20261206000006_inbox_push_seam.sql` | SQL-Test: Insert→`realtime.send` mit Whitelist, kein PII; `push_outbox`-Stub no-op; SECURITY DEFINER. |
| **Z-T1** | `keep-as-is`-Stellen dokumentieren (Inline-Kommentar) + Regression-Guard (= FC-10) | alle keep-as-is-Dateien aus b.3 | grep findet `Timer.periodic` nur in dokumentierter Allowlist + fallback-gateten Providern; CI-Guard schlägt bei neuem ungated Treffer an. |

> **Konflikt-Auflösung (Migrations-Dateinamen).** `backend-migrations` und `client-migration`/`test-rollout` nummerieren teils abweichend (`…000002_friend_edges` vs. `…000005_friend_edges`). **Verbindlich sind die `backend-migrations`-Namen** (`SRV-01`…`SRV-06`), weil sie die RLS-Analyse (additive Policies, `team_memberships`/`tournament_participants` getrennt) vollständig tragen. Die Client-Tasks referenzieren dieselben Migrationsdateien — keine Doppelmigration anlegen.

---

## (f) Test- & Rollout-Strategie

### Test-Doubles (Fundament, vor jeder Migration mergebar)

1. **`FakeBroadcastChannel`** (FC-3) — mirror der Broadcast-Port-Signatur, teilt mit dem CDC-Fake den gemeinsamen Lifecycle-Mixin + State-Replay.
2. **`FakeAppLifecycle`** — steuerbarer Treiber für `resumed/inactive/paused/detached` (deterministisch mit `fake_async`).
3. **Refcount-/Snapshot-Hooks** — der Broadcast-Adapter bietet dieselben `@visibleForTesting`-Hooks wie `SupabaseRealtimeChannel` (`referenceCount`, `hasChannel`, `reconnectAttempts`, `debugTransitionTo`); aktive Keys vor Pause == wiederhergestellte Keys nach Resume, **nicht mehr**.

### Vier verbindliche Test-Klassen

- **(A) Fallback-Gating** (`realtime_polling_fallback_test.dart`): errored<60 s→false; ≥60 s→true; joined-nach-error→cancel+false; Kadenz 30 s / anon 10 s; Boolean-Gate-Exklusivität; Kill-Switch off→immer true.
- **(B) Kill-Switch/Rollback** (`realtime_kill_switch_test.dart`): pro Feature — flag=false→Poll-Pfad funktioniert, keine Doppel-Updates.
- **(C) Battery/Wake-up** (`wake_up_regression_test.dart`): Foreground-Idle 5 min→0 Timer-Wakes; paused (5 s)→0 Channels/0 Timer, detached→sofort; Refcount-Multiplexing (2 subscribe=1 Channel, 2. dispose→Teardown nach 500 ms); Anti-`Timer.periodic`-Guard.
- **(D) Lifecycle-Resume-Reihenfolge** (`realtime_lifecycle_controller_test.dart`): re-sign ZUERST, dann Reconnect (Inbox immer, screen-Kanäle nur wenn gemountet), dann Refresher; paused 5 s-Debounce→Teardown+Refresher-Pause; inactive→no-op.

### Staging-Verifikation — die Publication-Falle (verbindlich pro CDC-Target P1/P3/P7/P8)

Lokal `FOR ALL TABLES` → CDC läuft in Dev, scheitert in Prod still. Daher: (1) explizites `ALTER PUBLICATION … ADD TABLE`; (2) `REPLICA IDENTITY FULL` nur wo old-row gebraucht (heute nirgends); (3) RLS deckungsgleich zur Filterspalte; (4) **Staging-Smoke** je Phase (echtes Event durchspielen + Fremd-Row-Block). Broadcast (P6) berührt die Publication NICHT.

### Quality-Gate pro Phase (alle drei verbindlich)

1. `flutter analyze` sauber (inkl. Anti-`Timer.periodic`-Guard).
2. Volle Suite grün (`flutter test`) inkl. der neuen (A)/(B)/(C)/(D)-Tests dieser Phase. **Repo-Stolperstein:** `pub get` kann durch `file_selector` blockieren → bei Bedarf `--no-pub`.
3. Manueller Check je Phase (siehe Phasen-Tabelle).

---

## (g) Sequenzierte Phasen — einzeln mergebar & grün (kein Big-Bang)

Reihenfolge folgt Plan §7.2 (lowest-risk first), mit der **Owner-§9-Verschärfung über die ältere §4-Plan-Tabelle**: `my-`Listen bekommen echtes CDC statt Inbox-Invalidierung. Inbox-Spine zuerst, weil sie die durable Notification-Schicht und den Push-Seam trägt.

### P0 — Fundament (reiner Additiv-Merge, kein Production-Pfad geändert)
**Tasks:** FC-1, FC-2, FC-3, FC-5, FC-6, FC-7, FC-10 (Guard initial), TR-P0-3 (Controller-Skelett + `FakeAppLifecycle`), Test-Klassen A–D als Gerüst.
**Quality-Gate:** Suite grün; neue Fakes/Ports/Keys kompilieren; `tournament_realtime_e2e_test.dart` grün (Singleton-Override); kein Consumer-Verhalten geändert.
**Abhängigkeiten:** keine. **Risiko:** niedrigstes.

### P1 — Inbox CDC (Notification-Spine)
**Tasks:** SRV-01, C1-T1, C1-T2.
**Inhalt:** Inbox-CDC-StreamProvider auf Shell-Scope (drift-cache-Variante: `refreshFromRemote` fire-and-forget pro Event), `inboxPollingProvider` (1 s) löschen.
**Quality-Gate:** Inbox-Tests + Wake-up-Test (0 Idle-Wakes) + Kill-Switch grün; Staging-Smoke CDC <1 s + RLS blockt fremde Rows.
**Abhängigkeiten:** P0. **Risiko:** Doppel-Update beim Cutover → Drift-Upsert ist idempotent, CDC ersetzt nur den Discovery-Timer.

### P2 — Tournament match/bracket/standings Fallback-Gating (keine Server-Arbeit)
**Tasks:** C4-T4, C4-T5, C6-T1 (anon 10 s).
**Inhalt:** Bracket/Standings von unconditional 5 s auf fallback-gated; match/matchList ans generalisierte Gate koppeln; anon-Spectator 10 s-Gating.
**Quality-Gate:** Fallback-Test (A) je Family; Wake-up-Test kein Poll bei gesundem Kanal; manueller Banner-Check bei erzwungenem Error.
**Abhängigkeiten:** P0 (FC-6). **Risiko:** Doppel-Update Bracket (CDC + 5 s parallel) → Boolean-Gate macht exklusiv.

### P3 — Friends CDC via `friend_edges`
**Tasks:** SRV-05, C2-T1, C2-T2.
**Inhalt:** Trigger-gepflegte `friend_edges`-Denormalisierung + CDC auf `owner_user_id`; `friendsPollingProvider` (1 s) löschen.
**Quality-Gate:** Friends-Tests + **Konsistenz-Test** (jede `friendships`-Mutation → korrekte `friend_edges`-Rows beidseitig) grün; Staging-Publication-Smoke.
**Abhängigkeiten:** P0. **Risiko:** Trigger-Drift → dedizierter Konsistenz-Test + Backfill-Count-Assertion.

### P4 — Fallback-Provider auf alle Families generalisieren + restliche 5-s-Tournament-Polls
**Tasks:** FC-6 (final, parametrisiert), Gating-Vervollständigung über alle Keys, `public_tournament_polling_provider` 10 s anon final.
**Quality-Gate:** parametrisierter Fallback-Test (A) über alle Keys; Wake-up-Regression grün; Kill-Switch pro Family.
**Abhängigkeiten:** P0-Keys + P2-Gating. **Risiko:** große Regression-Surface → parametrisierter Test + Kill-Switch pro Family.

### P5 — Lifecycle-Controller scharf schalten (Battery-Regime)
**Tasks:** FC-8, FC-9, C7-T1.
**Inhalt:** resume (re-sign→reconnect→Refresher), pause (5 s-Debounce→Teardown+Refresher-Pause), detached (sofort), inactive (no-op); Refcount-Snapshot über pause→resume.
**Quality-Gate:** Test (D) Reihenfolge + Pause-Teardown; manueller On-Device-Check Background→Foreground ohne Auth-Storm; Wake-up paused→0 Sockets/Timer.
**Abhängigkeiten:** P0 (Singleton-Adapter mit Snapshot). **Risiko:** Auth-Storm bei falscher Reihenfolge → Order-Assertion-Test.

### P6 — Inbox AFTER-INSERT Fan-out-Trigger (Push-Seam, Stub)
**Tasks:** SRV-06, C8-T1.
**Inhalt:** `realtime.send` PII-freier Nudge (`id/kind/subject/sent_at`), SECURITY DEFINER, `push_outbox`-Hälfte Stub. „One write, two wakes".
**Quality-Gate:** Trigger-Test: INSERT→Broadcast-Nudge ohne `created_by/user_id/email/nickname` (Whitelist-Assertion); Push-Stub no-op; Visibility-Gate.
**Abhängigkeiten:** P1 (Inbox-Tabelle/CDC live). **Risiko:** PII-Leak → explizite Spalten-Whitelist + Client-Defensiv-Whitelist.

### P7 — Tournament-/Team-Detail CDC + my-Listen echtes CDC; fünf Poller löschen
**Tasks:** SRV-02, SRV-03, SRV-04, SRV-09, SRV-07, SRV-08, C3-T1, C3-T2, C4-T1, C4-T2, C4-T3, C5-T1.
**Inhalt:** `matchRealtimeChannelKey` (`matches:id` auf `public.matches`, SRV-09), `teamRealtimeChannelKey`, Tournament-Detail, `myTeams`/`myTournaments` (echtes §9-CDC) treiben Listen-Invalidierung; `teamListPollingProvider`/`teamDetailPollingProvider`/`matchPollingProvider`/`tournamentListPollingProvider`/`tournamentDetailPollingProvider` löschen.
**Quality-Gate:** Per-Feature-Tests grün; je Migration Staging-Publication-Smoke (CDC ankommt + RLS); Inbox-Invalidierung nur als Fallback verdrahtet.
**Abhängigkeiten:** P0-Builder; SRV-07/08 verifizieren alle CDC-Targets. **Risiko:** Hosted-vs-local Publication-Falle pro Target → explizites `ALTER PUBLICATION` + Staging-Smoke.

### P8 — Achievements-Transport klären + Lamport-Singleton (Push deferred)
**Tasks:** Achievements-Gap entscheiden (Broadcast falls Fan-out, sonst Drift-only), Lamport-Clock auf `realtimeChannelProvider`-Singleton umstellen; Push (Token-Tabelle/`push_outbox`/Edge-Function) bleibt Stub. **Training bleibt unangetastet** (`keep-as-is`, siehe b.4) — kein CDC, kein Umbau.
**Quality-Gate:** Tests grün; Transport-Entscheidung dokumentiert + getestet; Push-Stub unverändert; Training-Sync unverändert (Regression-Check: bestehende Training-Tests grün, kein neuer Realtime-Pfad).
**Abhängigkeiten:** P0-Singleton (für Lamport). **Risiko:** niedrig.

---

## (h) Risiken & Rollback

### Kritische Risiken (mit Mitigation)

- **Key-String-Drift:** `stateStream`-Lookup muss EXAKT die `subscribe`-Map-Entry treffen — ein abweichender Builder erzeugt einen toten Channel **ohne Fehler und ohne Updates**. → Alle Keys nur über `kubb_domain`-Builder (FC-5); Roundtrip-Test `Builder == _keyFor == fakeKey` ist nicht verhandelbar.
- **Refcount-Bruch durch parallele Adapter-Instanzen:** solange `tournamentRemoteProvider`/`publicTournamentRealtimeProvider`/Lamport inline `new SupabaseRealtimeChannel(client)` erzeugen, entstehen mehrere Sockets (verstößt gegen „eine WebSocket"). → FC-7 muss vollständig sein, sonst ist der Lifecycle-Controller wirkungslos; Lamport in P8.
- **Resume-Reihenfolge → Auth-Storm:** Reconnect vor `forceReSignWireSession` → join→401→Backoff-Sturm. → Reihenfolge im Controller (nicht im Widget) erzwungen, Call-Recorder-Test (FC-8/Test D).
- **RLS-Filterspalten-Mismatch:** Filterspalte ≠ USING-Spalte → 0 Events oder Leak fremder Rows. → additive `self_read`-Policies (SRV-03/04) statt Umbau der Pool-Policies; SRV-07 erzwingt Parität pro Spalte.
- **Staging/Prod-CDC scheitert still:** lokal `FOR ALL TABLES`, in Prod ohne `ALTER PUBLICATION` toter Channel. → explizites Publication-ADD pro Target + SRV-08 Snapshot-Verify auf Staging.
- **`friend_edges`-Trigger-Drift:** veraltetes/falsches Friends-CDC. → Konsistenz-pgTAP (`friend_edges == 2× friendships`) + Trigger auf alle drei DML-Ops + Backfill im selben Schritt.
- **Pause-Snapshot/Timer-Leaks:** `reconnectKeys` darf nur zuvor aktive Keys wiederherstellen; `disconnectAll` muss alle `reconnect`/`pendingClose`-Timer canceln. → `FakeAsync.pendingTimers`-Assertion (FC-8) Pflicht.
- **Doppelter aktiver Pfad:** CDC + ungeloeschter Poller verdoppeln Wakes. → strikte Reihenfolge je Concern: erst StreamProvider+Fallback verdrahten & testen, DANN Poller löschen.
- **Privacy-Regression:** beim Broadcast-Umbau (FC-4) darf `assertPayloadColumnsWhitelisted` nicht verloren gehen; Push-Nudge `private`-Flag PII-frei (SRV-06). → bestehende Privacy-Tests unverändert grün + Whitelist-Assertion.
- **Inbox-Scope:** versehentlich screen-scoped → Notification-Spine stirbt bei Navigation, Badge friert ein. → explizit App-Shell (C1-T2).
- **Background-Erwartung:** bis Push live ist, gibt es im Hintergrund KEINE Server-Updates (bewusster ~0-Idle-Tradeoff). → Erwartungsmanagement/Release-Note; Updates beim Resume.
- **Repo-Stolperstein:** `pub get` kann durch `file_selector` blockieren → Suite mit `--no-pub`.

### Rollback je Phase über `realtimeEnabledFlagProvider` (Kill-Switch, default `true`, existiert bereits)

- **Incident:** Flag `false` (Remote-Config/Override) → jeder `realtimePollingFallbackProvider` liefert `true` → alle Features fallen instant auf Polling (30 s / anon 10 s) zurück. Kein Datenverlust, nur höhere Latenz (~120 Wakes/h statt instant). Kein Deploy nötig.
- **Phasen-spezifisch:** jede Phase liefert einen Kill-Switch-Test (Klasse B) — Poll-Pfad funktioniert nach Flip, keine Doppel-Updates (Boolean-Gate-Exklusivität).
- **DB-seitig** (P3 `friend_edges`, P6 Trigger): Trigger/Tabelle bleiben bestehen; nur der Client-Pfad flippt. Echte DB-Rollbacks sind separate Down-Migrationen, nicht über das Flag.

---

## Schlüsseldateien (Referenz)

- CDC-Port + neuer Sibling: `packages/kubb_domain/lib/src/ports/realtime_channel.dart`, `…/ports/broadcast_channel.dart`
- Werte: `packages/kubb_domain/lib/src/values/realtime_change.dart`, `…/values/broadcast_message.dart`
- Key-Builder (verbindlich): `packages/kubb_domain/lib/src/realtime/channel_keys.dart`
- Adapter + Lifecycle-Mixin: `lib/core/data/realtime/supabase_realtime_channel.dart`, `…/realtime_channel_lifecycle.dart`, `…/supabase_broadcast_channel.dart`
- Provider/Keys zum Generalisieren: `lib/features/tournament/application/realtime_fallback_provider.dart`
- Broadcast-Impl zum Lift: `lib/features/tournament/data/public_tournament_realtime.dart`
- Lifecycle: `lib/app/app.dart`, `lib/app/realtime_lifecycle_controller.dart`, `lib/features/auth/application/keypair_session_refresher.dart`
- Migrations-Templates: `supabase/migrations/20260601000031_public_tournament_realtime.sql` (Trigger), `supabase/migrations/20260504000011_mnemonic_admin_inbox.sql` (Inbox/Owner-Read-RLS), `supabase/migrations/20260507000001_social_graph.sql` (friendships-Quelle), `supabase/migrations/20260901000010_fix_team_rls_recursion.sql` (`is_active_team_member` — nicht antasten)
