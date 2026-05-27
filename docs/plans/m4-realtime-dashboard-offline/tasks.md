# M4 — Atomare Task-Liste

> Stand: 2026-05-27
> Bezug: `sprint-plan.md` (Waves, Sub-Milestones), `architecture.md`, `milestone-plan.md`, `open-decisions.md` (alle 7 ODs resolved), ADR-0021, ADR-0022, ADR-0023, ADR-0004, ADR-0006, ADR-0015
> Senior-Sizing: max 100 LOC, max 3 Files, max 1h netto pro Task

## Konvention

- IDs folgen `TASK-M4.<sub>-T<n>`. Sub ∈ {1, 2, 3}. Nummerierung folgt der Wave-Reihenfolge aus `sprint-plan.md`.
- Wave-Nummer bezieht sich auf `sprint-plan.md` §Wave-Plan.
- Agents: `coder-frontend` für Flutter-UI, `coder-data` für DB/Migrations/RPCs/drift, `coder-domain` für `packages/kubb_domain/`, `tester` für Tests/Goldens/Property-Tests, `coder-docs` für Demo-Script.
- TDD-Pflicht im Domain-Package und für Conflict-Resolver/Outbox-Flush: ein Test-Task vor jedem Impl-Task. Test-Task hat `tester` als Agent, Impl-Task hat den passenden `coder-*`.

---

# M4.1 — Realtime-Layer (Wave 1 bis 3)

## TASK-M4.1-T1: RealtimeChannel-Port und Value-Types

- **Type**: domain
- **Size**: M
- **Bounded Context**: core
- **Agent**: coder-domain
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**: `packages/kubb_domain/lib/src/ports/realtime_channel.dart`, `packages/kubb_domain/lib/src/values/realtime_change.dart`
- **LOC-Budget**: ~80

### Goal

Port `RealtimeChannel` plus Value-Types `RealtimeChange`, `RealtimeEventType` (enum insert/update/delete), `RealtimeChannelState` (enum connecting/joined/closed/errored) gemäss `architecture.md` §3.1. Per-Tournament-Channel-Granularität (OD-M4-01) → `subscribe(table, filterColumn, filterValue)`-Signatur.

### Acceptance Criteria

- Given Port-File When `RealtimeChannel`-Klasse importiert Then `abstract interface class` mit `subscribe`, `close`, `stateStream`.
- Given `RealtimeChange`-Konstruktor mit allen Pflicht-Feldern Then `@immutable` plus `==`/`hashCode`.
- Given `RealtimeEventType.update` plus `RealtimeChannelState.joined` Then beide als Dart-Enum verfügbar.
- Given `flutter analyze` Then keine Warnungen.

### Notes

- Code-Block aus `architecture.md` §3.1 ist verbindlich (Method-Signaturen).
- **Contract für M4.1-T2 (Fake-Adapter), M4.1-T4 (Supabase-Adapter), M4.1-T8 (Provider)**: Port-Signatur ist die Quelle der Wahrheit für alle drei Konsumenten.
- Keine Implementierung in dieser Task — nur Interface plus Value-Types.

---

## TASK-M4.1-T2: FakeRealtimeChannel + Tests

- **Type**: tests
- **Size**: M
- **Bounded Context**: core
- **Agent**: tester
- **Dependencies**: TASK-M4.1-T1
- **Wave**: 1
- **Files (anticipated)**: `packages/kubb_domain/lib/src/test_support/fake_realtime_channel.dart`, `packages/kubb_domain/test/test_support/fake_realtime_channel_test.dart`
- **LOC-Budget**: ~90

### Goal

In-Memory-Implementierung von `RealtimeChannel` für Test-Doppel-Setup (R-M4-G3-Mitigation). Manuelles `emit()`-API für Tests, dedupliziert pro Channel-Key, hält `stateStream` als BehaviorSubject.

### Acceptance Criteria

- Given `FakeRealtimeChannel().subscribe(table='t', filterColumn='c', filterValue='v')` When `fake.emit(channelKey, RealtimeChange(...))` Then Subscriber sieht Change.
- Given zwei `subscribe`-Calls mit gleichem Key Then beide Subscriber kriegen Events (Broadcast).
- Given `close(key)` When alle Subscriber abgemeldet Then `stateStream(key)` schliesst.
- Given Tests laufen Then alle grün.

### Notes

- `package:kubb_domain/test_support/` ist exportierbar für Konsumenten-Tests.
- **Contract für M4.1-T14 (e2e-Test), M4.2-T7 (Dashboard-Widget-Tests), M4.2-T13 (Public-Widget-Tests)**: Fake-API (`emit`, `setState`) wird in allen drei Konsumenten wiederverwendet.

---

## TASK-M4.1-T3: BracketAdvanceEvent Value-Type

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/bracket_advance_event.dart`, `packages/kubb_domain/test/tournament/bracket_advance_event_test.dart`
- **LOC-Budget**: ~50

### Goal

`BracketAdvanceEvent`-Value-Type gemäss `architecture.md` §3.5 (Code-Block) — `tournamentId`, `advancedMatchId`, `targetRound`, `targetMatchNumber`, `winnerParticipant`, `at`.

### Acceptance Criteria

- Given Konstruktor mit allen Pflicht-Feldern Then Instanz erstellt, `@immutable`.
- Given zwei Events mit gleichen Feldern Then `==` ist `true`.
- Given Tests Then grün.

### Notes

- **Contract für M4.1-T5 (`TournamentRemote.watchBracketAdvances` Return-Type)**.

---

## TASK-M4.1-T4: SupabaseRealtimeChannel-Adapter

- **Type**: data
- **Size**: L
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T1
- **Wave**: 2
- **Files (anticipated)**: `lib/core/data/realtime/supabase_realtime_channel.dart`
- **LOC-Budget**: ~100

### Goal

Konkrete `RealtimeChannel`-Impl. Channel-Sharing per Key (Reference-Counter), `supabase.channel(name).on(postgres_changes, ...)`-Setup, Exp-Backoff-Reconnect (1/2/4/8/30 s), 500 ms Debounce vor finalem Close (R-M4.1-2-Mitigation).

### Acceptance Criteria

- Given Adapter `.subscribe(table='tournament_matches', filterColumn='tournament_id', filterValue=':id')` When Supabase sendet ein UPDATE-Event Then Subscriber bekommt `RealtimeChange(eventType=update, ...)`.
- Given zwei `.subscribe`-Calls mit gleichem Key Then nur ein Supabase-WS-Channel wird geöffnet.
- Given `.close(key)` aufgerufen während noch ein Subscriber dranhängt Then Channel bleibt offen.
- Given Channel-State wechselt nach `errored` Then `stateStream(key)` emittiert `RealtimeChannelState.errored`.
- Given `errored` + Backoff-Tick Then Adapter versucht `.resubscribe()`.

### Notes

- Per-Tournament-Channel (OD-M4-01) — Filter ist `tournament_id=:id`.
- RLS-Auth via Standard-JWT (OD-M4-07) — keine eigene Token-Verwaltung.
- Reference-Counter + 500 ms Debounce explizit für R-M4.1-2.
- **Contract für M4.1-T7 (Adapter-Smoke-Tests)**: `_referenceCount(key)` als `@visibleForTesting` exponieren.

---

## TASK-M4.1-T5: TournamentRemote-Port-Erweiterung (watch-Methoden)

- **Type**: domain
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M4.1-T1, TASK-M4.1-T3
- **Wave**: 2
- **Files (anticipated)**: `packages/kubb_domain/lib/src/ports/tournament_remote.dart`
- **LOC-Budget**: ~60

### Goal

Drei neue Methoden auf `TournamentRemote`: `Stream<TournamentMatchRef> watchMatch(TournamentMatchId)`, `Stream<TournamentMatchRef> watchTournamentMatches(TournamentId)`, `Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId)`. `watchMatch` ersetzt den M1-Placeholder (empty stream).

### Acceptance Criteria

- Given Port-File When kompiliert Then drei neue Methoden auf `TournamentRemote` deklariert.
- Given bestehende Fakes/Adapter Then `flutter analyze` zeigt unimplemented members — wird in M4.1-T9 erfüllt.
- Given Dokumentations-Kommentare aus `architecture.md` §3.5 Then im Code übernommen.

### Notes

- Additiv — keine bestehende Methode wird gebrochen.
- **Contract für M4.1-T8 (Realtime-Provider), M4.1-T9 (Adapter-Impls)**: Method-Signaturen + Return-Types verbindlich. `watchMatch` ist Per-Tournament-Channel intern + Client-side-Filter auf `matchId`.

---

## TASK-M4.1-T6: MatchEventRepository.watchEvents Port-Erweiterung

- **Type**: domain
- **Size**: S
- **Bounded Context**: match
- **Agent**: coder-domain
- **Dependencies**: TASK-M4.1-T1
- **Wave**: 2
- **Files (anticipated)**: `packages/kubb_domain/lib/src/ports/match_event_repository.dart`
- **LOC-Budget**: ~30

### Goal

Additiv `Stream<MatchEvent> watchEvents(MatchId id)` auf `MatchEventRepository`. Solo-Match-Pfad (ADR-0014) bleibt unverändert, UI nutzt diese Methode in M4 noch nicht — nur Port + Adapter werden gleichgezogen.

### Acceptance Criteria

- Given Port-File When kompiliert Then `watchEvents(MatchId)` deklariert.
- Given Doku-Kommentar Then verweist auf `RealtimeChannel`-Port als Transport.

### Notes

- M4-UI nutzt das nicht — Port-Konsistenz.
- **Contract für M4.1-T9 (Adapter-Impl)**.

---

## TASK-M4.1-T7: Adapter-Smoke-Tests SupabaseRealtimeChannel

- **Type**: tests
- **Size**: M
- **Bounded Context**: core
- **Agent**: tester
- **Dependencies**: TASK-M4.1-T4
- **Wave**: 2
- **Files (anticipated)**: `test/core/data/realtime/supabase_realtime_channel_test.dart`
- **LOC-Budget**: ~100

### Goal

Tests verifizieren Reference-Counter, Backoff-Timing (mit `FakeAsync`/`fake_async`-Paket aus dev_dependencies), Debounce-Verhalten. Ohne echten Supabase — Supabase-Client wird gemockt.

### Acceptance Criteria

- Given zwei `subscribe`-Calls mit gleichem Key When `close(key)` einmal aufgerufen Then Channel bleibt offen, Counter ist 1.
- Given Counter auf 0 When 500 ms vergangen Then Supabase-Channel wird unsubscribed.
- Given Channel-State wechselt zu `errored` When 1 s vergeht Then erster Reconnect-Versuch; nach 1+2+4+8=15 s vier Versuche; danach 30 s-Intervall.
- Given vor 500 ms-Debounce ein neuer `subscribe`-Call mit gleichem Key Then Channel bleibt offen, Counter wieder auf 1.

### Notes

- `package:fake_async` aus dev_dependencies für Timer-Tests.
- Mock `SupabaseClient` via Riverpod-Override.

---

## TASK-M4.1-T8: Realtime-Provider

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T5
- **Wave**: 3
- **Files (anticipated)**: `lib/features/tournament/application/tournament_realtime_provider.dart`
- **LOC-Budget**: ~100

### Goal

Drei `family`-Provider: `tournamentMatchListRealtimeProvider.family<TournamentId>`, `tournamentMatchDetailRealtimeProvider.family<TournamentMatchId>`, `tournamentBracketRealtimeProvider.family<TournamentId>`. Konsumieren `TournamentRemote.watch*`-Methoden, invalidieren die jeweiligen Polling-Provider bei Events.

### Acceptance Criteria

- Given `ProviderContainer.read(tournamentMatchListRealtimeProvider(tid))` When `FakeRealtimeChannel.emit(...)` (via FakeTournamentRemote) Then `tournamentMatchListProvider(tid)` wird invalidiert.
- Given `tournamentMatchDetailRealtimeProvider(matchId)` When Stream-Event mit fremdem `matchId` Then ignoriert (Client-side-Filter per OD-M4-01).
- Given Provider wird `autoDispose` Then nach letztem Listener-Close wird Stream-Subscription gecancelt.

### Notes

- Per-Tournament-Channel-Filter (OD-M4-01) plus Client-side `matchId`-Match.
- **Contract für M4.1-T10/T11/T12, M4.2-T4/T8/T11**: Provider-Signaturen wiederverwendet.

---

## TASK-M4.1-T9: Adapter-Impls (Supabase + Fake) für watch-Methoden

- **Type**: data
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T5, TASK-M4.1-T6, TASK-M4.1-T4
- **Wave**: 3
- **Files (anticipated)**: `lib/features/tournament/data/supabase_tournament_remote.dart` (extend), `lib/features/tournament/data/fake_tournament_remote.dart` (extend), `lib/features/match/data/supabase_match_event_repository.dart` (extend)
- **LOC-Budget**: ~100

### Goal

`SupabaseTournamentRemote` implementiert `watchMatch`, `watchTournamentMatches`, `watchBracketAdvances` via `RealtimeChannel`-Port (Adapter aus T4). `FakeTournamentRemote` implementiert die drei Methoden via `FakeRealtimeChannel` (aus T2). `SupabaseMatchEventRepository` implementiert `watchEvents` via Port.

### Acceptance Criteria

- Given `SupabaseTournamentRemote.watchTournamentMatches(tid)` When unterliegendes Adapter emittiert `RealtimeChange` Then Stream emittiert `TournamentMatchRef` (geparst aus `newRow`).
- Given `FakeTournamentRemote` Then alle Stream-Methoden verwenden `FakeRealtimeChannel`-Instanz.
- Given `flutter analyze` Then keine unimplemented members mehr.

### Notes

- `watchBracketAdvances` filtert clientseitig auf `status='finalized'` und mappt zu `BracketAdvanceEvent`.
- Parser nutzt bestehende `TournamentMatchRef.fromJson`-Logik aus M1.

---

## TASK-M4.1-T10: Polling-Fallback-Switch

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T8
- **Wave**: 3
- **Files (anticipated)**: `lib/features/tournament/application/realtime_fallback_provider.dart`
- **LOC-Budget**: ~60

### Goal

Provider `realtimeFallbackProvider.family<TournamentId>` lauscht auf `RealtimeChannel.stateStream` für den per-Tournament-Channel-Key, emittiert `true` (Polling-aktiv) wenn State länger als 60 s `errored` oder wenn Feature-Flag `realtime_enabled=false`. Match-List/Detail-Provider konsumieren das.

### Acceptance Criteria

- Given Channel-State ist `joined` Then `realtimeFallbackProvider(tid)` emittiert `false`.
- Given Channel-State wechselt zu `errored` und bleibt 60 s Then emittiert `true`.
- Given Channel reconnected zu `joined` Then emittiert `false` (Polling deaktiviert).
- Given Feature-Flag `realtime_enabled=false` Then emittiert immer `true`.

### Notes

- Polling-Provider aus M1–M3 bleiben unverändert. Sie werden in T12 conditional auf `realtimeFallbackProvider` aktiviert.
- OD-M4-02-Empfehlung A umgesetzt.

---

## TASK-M4.1-T11: RealtimeStateBanner-Widget

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T4, TASK-M4.1-T8
- **Wave**: 3
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/realtime_state_banner.dart`
- **LOC-Budget**: ~70

### Goal

Widget `RealtimeStateBanner` zeigt einen schmalen Stack-Banner über dem Screen-Content. Zustände: "verbinde…" (orange, `connecting`), "live" (grün, `joined`), "offline, Polling aktiv" (gelb, nach 60 s `errored`). 1.5 s Auto-Hide bei `joined`.

### Acceptance Criteria

- Given `stateStream` emittiert `connecting` Then Banner zeigt l10n-String `realtimeConnecting`.
- Given `joined` Then Banner zeigt `realtimeLive` für 1.5 s, dann hide.
- Given `errored` für >60 s Then Banner zeigt `realtimePolling`.
- Given Widget-Test rendert die drei Zustände Then Snapshot passt.

### Notes

- l10n-Keys werden in T13 angelegt — String-Literals als Konstanten in dieser Datei für TDD.

---

## TASK-M4.1-T12: Screen-Migration auf Realtime-Provider

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T8, TASK-M4.1-T10, TASK-M4.1-T11
- **Wave**: 3
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_match_detail_screen.dart` (edit), `lib/features/tournament/presentation/tournament_match_list_screen.dart` (edit), `lib/features/tournament/presentation/tournament_detail_screen.dart` (edit)
- **LOC-Budget**: ~80

### Goal

Match-Detail-Screen und Match-List-Screen konsumieren neue `*RealtimeProvider` statt direkter Polling-Provider. Polling-Provider wird nur aktiviert wenn `realtimeFallbackProvider(tid) == true`. `RealtimeStateBanner` im Screen-Header eingebunden.

### Acceptance Criteria

- Given Screen geöffnet When Realtime-Provider liefert Daten Then Polling-Provider ist nicht aktiv.
- Given `realtimeFallbackProvider(tid) == true` Then Polling-Provider wird zusätzlich beobachtet (Daten kommen vom älteren der beiden, UI rebuildet bei beiden).
- Given Widget-Tests bestehende Match-Detail-Tests Then grün (Realtime-Provider-Override via `FakeRealtimeChannel`).

### Notes

- Bestehende Screen-Tests müssen Provider-Overrides ergänzen (FakeRealtimeChannel + FakeTournamentRemote).
- **Single-File-Risiko**: drei Screen-Files. Wenn parallele M3-Arbeit am Detail-Screen läuft, Merge-Konflikt-Hotspot — keiner aktuell, weil M3 abgeschlossen ist.

---

## TASK-M4.1-T13: l10n DE-Strings für Banner

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T11
- **Wave**: 3
- **Files (anticipated)**: `lib/l10n/app_de.arb` (edit), `lib/l10n/app_en.arb` (edit, optional Stub)
- **LOC-Budget**: ~30

### Goal

DE-Strings `realtimeLive` ("Live"), `realtimePolling` ("Offline — Polling aktiv"), `realtimeConnecting` ("Verbinde…"). Generator-Lauf grün.

### Acceptance Criteria

- Given ARB-Datei erweitert When `flutter pub run intl_utils:generate` Then keine Fehler.
- Given `S.of(context).realtimeLive` im Banner-Code Then liefert "Live".

---

## TASK-M4.1-T14: Realtime-e2e-Test

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M4.1-T8, TASK-M4.1-T9, TASK-M4.1-T10, TASK-M4.1-T11, TASK-M4.1-T12
- **Wave**: 3
- **Files (anticipated)**: `test/integration/tournament_realtime_e2e_test.dart`
- **LOC-Budget**: ~100

### Goal

Zwei `ProviderContainer`-Instanzen (simuliert zwei Phones), jeweils mit `FakeTournamentRemote` + `FakeRealtimeChannel`. Phone-A emittiert Score-Update-Event → Phone-B sieht Update in <1 s ohne Polling-Trigger. Reconnect-Smoke: Channel `errored` für >60 s → Polling-Fallback-Provider liefert weiter, Channel `joined` → Polling deaktiviert.

### Acceptance Criteria

- Given zwei Container When Phone-A `FakeRealtimeChannel.emit(...)` Then Phone-B `tournamentMatchListRealtimeProvider` rebuildet.
- Given Channel-State `errored` >60 s (mit `fake_async`) Then `realtimeFallbackProvider(tid) == true`.
- Given Channel `joined` zurück Then `realtimeFallbackProvider(tid) == false`.

### Notes

- Kein echter Supabase-Aufruf. Pure Test mit Fakes.
- Pre-Demo-Smoke (manueller WLAN-Drop) gehört in `demo-script.md` (T16 in M4.3).

---

# M4.2 — Live-Dashboard + Spectator-View (Wave 4 bis 6)

## TASK-M4.2-T1: Migration tournaments.public-Flag + Anon-RLS-Policies

- **Type**: data
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: —
- **Wave**: 4
- **Files (anticipated)**: `supabase/migrations/20260701000002_tournaments_public_flag.sql`
- **LOC-Budget**: ~100

### Goal

Spalte `tournaments.public bool DEFAULT true NOT NULL`, RLS-Policy `tournaments_public_read FOR SELECT TO anon USING (public = true AND status IN ('published','registration_open','registration_closed','live','finalized'))`, analoge `FOR SELECT TO anon`-Policies für `tournament_matches`, `tournament_participants`, `tournament_set_scores` (jeweils JOIN auf `tournaments.public=true`). View `public_tournament_roster_view` (nur `display_name`, keine E-Mail/User-IDs).

### Acceptance Criteria

- Given Migration läuft When `\d tournaments` Then Spalte `public` mit Default `true` existiert, NOT NULL.
- Given anon-JWT Caller When `SELECT * FROM tournaments WHERE id=:id` für `public=true` Then Row sichtbar.
- Given anon-JWT Caller When `SELECT * FROM tournaments WHERE id=:id` für `public=false` Then leer.
- Given anon-JWT Caller When `UPDATE tournaments SET ...` Then 42501.
- Given Migration auf bestehender DB Then alle existierenden Rows haben `public=true`.

### Notes

- OD-M4-03 (anon mit Public-RLS) umgesetzt.
- OD-M4-07 (RLS-basiert, kein ChannelAuthToken).
- R-M4.2-2-Mitigation: View `public_tournament_roster_view` projiziert nur `display_name`. Roster-Anonymisierungs-Toggle pro Turnier ist M5+ — hier nur die View.
- **Contract für M4.2-T2 (pgTAP), M4.2-T8/T9 (Public-Screens)**: RLS-Policies sind die Lese-Wahrheit für anon.

---

## TASK-M4.2-T2: pgTAP Anon-RLS-Tests

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M4.2-T1
- **Wave**: 4
- **Files (anticipated)**: `supabase/tests/public_rls_test.sql` (pgTAP) **oder** `test/integration/public_rls_test.dart`
- **LOC-Budget**: ~100

### Goal

Drei Pflicht-Fälle plus weitere Edge-Cases. Sicherheitskritisch — Merge-Gate für M4.2 (R-M4.2-1).

### Acceptance Criteria

- Given anon-JWT When `SELECT * FROM tournaments WHERE id=:public_id` Then Row.
- Given anon-JWT When `SELECT * FROM tournaments WHERE id=:non_public_id` Then leer.
- Given anon-JWT When `SELECT * FROM tournament_matches WHERE tournament_id=:public_id` Then Rows.
- Given anon-JWT When `SELECT * FROM tournament_matches WHERE tournament_id=:non_public_id` Then leer.
- Given anon-JWT When `UPDATE tournaments SET ...` Then 42501.
- Given anon-JWT When `INSERT INTO tournament_matches ...` Then 42501.
- Given anon-JWT When `UPDATE tournament_set_scores ...` Then 42501.

### Notes

- Wenn pgTAP nicht verfügbar: Dart-Integration-Test gegen lokale Supabase, analog M3-Test-Strategie.
- Security-Checker-Agent (Workbench-Rules) bevorzugt.

---

## TASK-M4.2-T3: Anon-Session-Bootstrap

- **Type**: data
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: —
- **Wave**: 4
- **Files (anticipated)**: `lib/core/data/supabase/anon_session.dart`
- **LOC-Budget**: ~60

### Goal

`AnonSessionBootstrapper`-Provider — beim ersten Public-Route-Hit `supabase.auth.signInAnonymously()` oder Token-Refresh aus `flutter_secure_storage`. Idempotent — wenn Anon-Session schon aktiv, no-op.

### Acceptance Criteria

- Given keine Session When `ensureAnonSession()` Then `signInAnonymously()` aufgerufen, JWT in `flutter_secure_storage` cached.
- Given gecachtes JWT (nicht expired) When `ensureAnonSession()` Then aus Storage geladen, kein Server-Call.
- Given authentifizierte Session vorhanden When `ensureAnonSession()` Then no-op.

### Notes

- OD-M4-03 — Build-Time-Public Anon-Key bleibt.
- **Contract für M4.2-T10 (Public-Router)**: Bootstrapper wird vor Public-Screen-Mount aufgerufen.

---

## TASK-M4.2-T4: TournamentLiveDashboardProvider

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T8
- **Wave**: 5
- **Files (anticipated)**: `lib/features/tournament/application/tournament_live_dashboard_provider.dart`
- **LOC-Budget**: ~100

### Goal

`tournamentLiveDashboardProvider.family<TournamentId>` aggregiert `tournamentMatchListRealtimeProvider`, gruppiert nach `pitch_number`, berechnet Farbcode pro Pitch: grau (`scheduled`), grün (`live`, beide Teams haben gemeldet), gelb (`live` aber kein Score-Update seit >2 min), rot (`disputed`).

### Acceptance Criteria

- Given Match-Liste mit drei Matches auf drei Pitches Then Dashboard-Map hat drei Einträge.
- Given Match-Status `disputed` Then Pitch-Color ist `red`.
- Given Match `live` plus `last_updated_at < now() - 2 min` Then Pitch-Color ist `yellow`.
- Given Match `live` plus aktuelles Update Then Pitch-Color ist `green`.

### Notes

- Polling-Fallback wird automatisch genutzt wenn Realtime-Provider via Wave-3-Switch auf Polling fällt — keine Extra-Logik nötig.
- **Contract für M4.2-T5 (Dashboard-Screen)**: Map<PitchNumber, PitchStatus> ist Provider-Output.

---

## TASK-M4.2-T5: Tournament-Live-Dashboard-Screen

- **Type**: frontend
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.2-T4
- **Wave**: 5
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_live_dashboard_screen.dart`, `lib/features/tournament/presentation/widgets/pitch_status_card.dart`
- **LOC-Budget**: ~100

### Goal

Grid-Layout mit `PitchStatusCard` pro Pitch (Farbe per Provider, Pitch-Nummer, Match-Number, Teams, Sets-Stand, Status-Label). Pull-to-refresh erzwingt Re-Subscribe via `ref.invalidate(realtimeChannelProvider)`.

### Acceptance Criteria

- Given Dashboard geöffnet für Turnier mit 4 Pitches Then 4 Karten in Grid.
- Given Karte ist `red` Then Border-Color rot, Status-Text "strittig".
- Given Klick auf Karte Then Navigation auf bestehenden Match-Detail-Screen.
- Given Pull-to-refresh Then Channel wird re-subscribed (Refresh-Indicator zeigt 1 s).

### Notes

- Tablet-Layout: `GridView.count(crossAxisCount=3)` für 7"-Tablet quer.
- Phone-Layout: `crossAxisCount=2`, scrollbar.

---

## TASK-M4.2-T6: Route + Veranstalter-Detail-Verlinkung

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.2-T5
- **Wave**: 5
- **Files (anticipated)**: `lib/app/router.dart` (edit), `lib/features/tournament/presentation/tournament_detail_screen.dart` (edit)
- **LOC-Budget**: ~40

### Goal

go_router-Route `/tournaments/:id/live` → `TournamentLiveDashboardScreen`. Button "Live-Dashboard öffnen" im Veranstalter-Tournament-Detail-Screen-Header (sichtbar wenn Caller=Veranstalter und Turnier-Status ∈ {live, finalized}).

### Acceptance Criteria

- Given Tap auf Button im Detail-Screen When Caller=Veranstalter Then Navigation auf `/tournaments/:id/live`.
- Given Caller ist nicht Veranstalter Then Button nicht sichtbar.

### Notes

- **Single-File-Risiko `lib/app/router.dart`**: M4.2-T10 (Public-Routes) ändert dieselbe Datei. Sequenzielle Bearbeitung Wave 5 → Wave 6.

---

## TASK-M4.2-T7: Dashboard-Widget-Tests

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M4.2-T5, TASK-M4.2-T4
- **Wave**: 5
- **Files (anticipated)**: `test/features/tournament/presentation/tournament_live_dashboard_screen_test.dart`
- **LOC-Budget**: ~100

### Goal

Widget-Tests für vier Status-Permutationen (grau/grün/gelb/rot), Pitch-Karte-Snapshot, FakeRealtimeChannel injiziert Match-Updates und Status-Wechsel werden sichtbar.

### Acceptance Criteria

- Given Container mit FakeRealtimeChannel + FakeTournamentRemote When Provider ist scheduled Then alle Karten grau.
- Given `FakeRealtimeChannel.emit(update mit status='disputed')` Then betroffene Karte rot.
- Given Snapshot-Vergleich der Karten-Renders Then matches.

### Notes

- Goldens für die vier Farbpermutationen.

---

## TASK-M4.2-T8: Public-Tournament-Screen

- **Type**: frontend
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.1-T8, TASK-M4.2-T1
- **Wave**: 6
- **Files (anticipated)**: `lib/features/tournament/presentation/public/public_tournament_screen.dart`
- **LOC-Budget**: ~100

### Goal

Drei Tabs: Spielplan (Matches gruppiert nach Runde, bestehende Widgets read-only), Rangliste (bestehende Standings-Widgets), Bracket (M2-Visualizer read-only). Header mit Turnier-Name, Status, Aktuelle Runde, Teilnehmerzahl.

### Acceptance Criteria

- Given Public-Route `/public/tournament/:id` mit `public=true` Then Screen rendert drei Tabs.
- Given Turnier mit `public=false` Then Screen zeigt 404-Sub-Screen "nicht öffentlich".
- Given Tab-Switch Then jeweiliger Inhalt sichtbar.
- Given Bestehende `tournamentMatchListRealtimeProvider`-Konsum Then Live-Updates bei Live-Modus-AN.

### Notes

- R-M4.2-2: Roster-Spalten zeigen nur `display_name` (via View `public_tournament_roster_view`).
- Bestehende Widgets im Read-only-Mode wiederverwenden — kein Score-Eingabe-Button.

---

## TASK-M4.2-T9: Public-Match-Screen

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.2-T8
- **Wave**: 6
- **Files (anticipated)**: `lib/features/tournament/presentation/public/public_match_screen.dart`
- **LOC-Budget**: ~80

### Goal

Read-only Match-Sicht: Teams, aktueller Sets-Stand, Match-Status. Keine Eingabe-Buttons, keine Aktions-Menüs.

### Acceptance Criteria

- Given Public-Route `/public/match/:matchId` Then Screen rendert Sets-Stand.
- Given Match-Updates über Realtime (wenn Live-Modus an) Then Screen aktualisiert sich.
- Given anon-JWT Then keine Schreib-Buttons sichtbar.

### Notes

- Wiederverwendung Sets-Stand-Widget aus M1.

---

## TASK-M4.2-T10: go_router-Public-Routes + Anon-Bootstrap

- **Type**: frontend
- **Size**: M
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.2-T8, TASK-M4.2-T9, TASK-M4.2-T3
- **Wave**: 6
- **Files (anticipated)**: `lib/app/router.dart` (edit), `lib/app/public_router_shell.dart` (neu)
- **LOC-Budget**: ~80

### Goal

go_router-Routen `/public/tournament/:id` und `/public/match/:matchId` ohne Auth-Guard. `PublicRouterShell` ruft `anonSessionBootstrapperProvider.ensureAnonSession()` vor dem Mount des Child-Screens.

### Acceptance Criteria

- Given unauthenticated Browser When `/public/tournament/:id` aufgerufen Then Screen rendert ohne Login-Redirect.
- Given Public-Route-Hit Then Anon-Session ist active vor Provider-Konsum.
- Given Tap auf Match in Public-Tournament-Spielplan Then Navigation auf `/public/match/:matchId`.

### Notes

- **Single-File-Risiko `lib/app/router.dart`**: Konsekutiv nach T6 mergen.

---

## TASK-M4.2-T11: Live-Modus-Toggle auf Public-Screen

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.2-T8, TASK-M4.1-T8
- **Wave**: 6
- **Files (anticipated)**: `lib/features/tournament/presentation/public/public_tournament_screen.dart` (edit)
- **LOC-Budget**: ~60

### Goal

Toggle im Public-Header: "Live-Modus" (Switch). Default AUS für anonyme Caller (R-M4.2-3-Mitigation per OD-M4-01). Bei AUS: 10-s-Polling-Provider. Bei AN: Realtime-Subscribe wird aktiviert.

### Acceptance Criteria

- Given Public-Tournament-Screen frisch geöffnet (anon) Then Toggle AUS, Polling 10 s aktiv.
- Given User tippt Toggle Then Realtime-Provider wird subscribed, Polling deaktiviert.
- Given Toggle AUS Then Realtime-Subscription wird unsubscribed (Reference-Counter aus Adapter).

### Notes

- Skaliert linear zu engagierten Zuschauern, nicht viralen Visits — Tier-1-Schutz.

---

## TASK-M4.2-T12: l10n DE-Strings für M4.2

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.2-T5, TASK-M4.2-T8, TASK-M4.2-T9
- **Wave**: 6
- **Files (anticipated)**: `lib/l10n/app_de.arb` (edit), `lib/l10n/app_en.arb` (edit, optional Stub)
- **LOC-Budget**: ~50

### Goal

Strings: `liveDashboardTitle`, `liveDashboardOpenButton`, `pitchStatusScheduled`, `pitchStatusLive`, `pitchStatusStalled`, `pitchStatusDisputed`, `publicTournamentSchedule`, `publicTournamentStandings`, `publicTournamentBracket`, `liveModeToggle`, `publicNotAvailable` ("Dieses Turnier ist nicht öffentlich").

### Acceptance Criteria

- Given ARB-Datei erweitert When Generator-Lauf Then keine Fehler.
- Given Bezug aus T5/T8/T9 Then Strings im jeweiligen Screen sichtbar.

---

## TASK-M4.2-T13: Public-Screen Widget/Snapshot-Tests

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M4.2-T8, TASK-M4.2-T9, TASK-M4.2-T11
- **Wave**: 6
- **Files (anticipated)**: `test/features/tournament/presentation/public/public_tournament_screen_test.dart`, `test/features/tournament/presentation/public/public_match_screen_test.dart`
- **LOC-Budget**: ~100

### Goal

Tests verifizieren Read-only-Verhalten (keine Schreib-Buttons), Anon-JWT-Bootstrap-Mock-Pfad, Live-Modus-Toggle schaltet zwischen Polling und Realtime, `public=false` → 404-Subview.

### Acceptance Criteria

- Given Public-Screen rendert mit `public=true`-Mock Then drei Tabs sichtbar.
- Given Toggle AN → AUS Then `FakeRealtimeChannel.unsubscribed(key)` ist true.
- Given Public-Match-Screen mit Mock-Match Then keine Eingabe-Widgets im Render-Tree.
- Given Snapshot-Vergleich Then matches.

### Notes

- AnonBootstrapper-Provider per `Override` durch Fake ersetzen.

---

# M4.3 — Offline + Sync-Outbox (Wave 7 bis 9)

## TASK-M4.3-T1: drift-Tabelle ScoreSubmissionOutbox + DAO

- **Type**: data
- **Size**: M
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: —
- **Wave**: 7
- **Files (anticipated)**: `lib/core/data/tables/score_submission_outbox.dart`, `lib/core/data/dao/score_submission_outbox_dao.dart`, `lib/core/data/app_database.dart` (edit Schema-Version)
- **LOC-Budget**: ~100

### Goal

drift-Table-Definition gemäss `architecture.md` §3.4 plus DAO. Schema-Version-Bump in `app_database.dart`. `MigrationStrategy.from(N) to (N+1)` ist additiv (`CREATE TABLE IF NOT EXISTS`).

### Acceptance Criteria

- Given Drift-Schema-Build Then `score_submission_outbox`-Tabelle existiert mit allen Spalten aus `architecture.md` §3.4.
- Given UNIQUE-Index `(matchId, consensusRound, setIndex, submitterUserId, lamportCounter, lamportDeviceId)` Then verhindert Duplikat-Insert (drift-Test).
- Given DAO-Methoden `insert`, `pending`, `markAcknowledged`, `markError`, `deleteOlderThan(date)` Then implementiert.
- Given Migration-Test gegen alte DB-Fixture (R-M4.3-1-Mitigation) Then grün.

### Notes

- OD-M4-06 (eigene Tabelle, nicht Update-Flag auf Drafts).
- **Contract für M4.3-T5 (Flusher-Tests), M4.3-T7 (Flusher-Impl), M4.3-T8 (Lamport-Hydration), M4.3-T10 (Repository-Umstellung), M4.3-T13 (GC)**: Spalten-Namen + UNIQUE-Index verbindlich.

---

## TASK-M4.3-T2: Migration score_rpc_idempotency

- **Type**: data
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: —
- **Wave**: 7
- **Files (anticipated)**: `supabase/migrations/20260701000001_score_rpc_idempotency.sql`
- **LOC-Budget**: ~100

### Goal

`tournament_propose_set_score` bekommt zwei optionale Parameter `p_lamport_counter int DEFAULT NULL`, `p_device_id text DEFAULT NULL`. UNIQUE-Index `tournament_set_scores_idempotency_idx` auf `(match_id, consensus_round, set_index, submitter_user_id, lamport_counter, device_id)` WHERE `lamport_counter IS NOT NULL`. RPC-Body: `INSERT ... ON CONFLICT ON CONSTRAINT tournament_set_scores_idempotency_idx DO NOTHING RETURNING ...`; bei Konflikt: bestehenden Match-Snapshot zurückgeben.

### Acceptance Criteria

- Given Migration läuft Then RPC-Signatur hat sechs Parameter (vier alte + zwei neue).
- Given Legacy-Caller ohne Lamport-Felder Then RPC verhält sich wie M1 (kein Idempotency-Check).
- Given Caller mit Lamport+Device-ID + Re-Submit derselben Werte Then keine neue Set-Score-Row, existierender Match zurückgegeben.
- Given Wettbewerbs-Submit (zwei verschiedene Lamport-Counter, sonst gleich) Then beide werden als separate Submits akzeptiert (Drei-Versuche-Konsens greift später).

### Notes

- OD-M4-05 (Lamport jetzt produktiv).
- R-M4.3-2: Device-ID stabil über `flutter_secure_storage` (siehe T7).
- **Contract für M4.3-T3 (pgTAP), M4.3-T6 (Port-Methode)**: Parameter-Namen + Return-Shape verbindlich.

---

## TASK-M4.3-T3: pgTAP Idempotency-Tests

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M4.3-T2
- **Wave**: 7
- **Files (anticipated)**: `supabase/tests/score_rpc_idempotency_test.sql` (pgTAP) **oder** `test/integration/score_rpc_idempotency_test.dart`
- **LOC-Budget**: ~100

### Goal

Tests gegen `tournament_propose_set_score` mit drei Szenarien: Re-Submit-No-Op, Legacy-ohne-Lamport-Standard-Verhalten, Konkurrenz-Submit (zwei verschiedene Counter).

### Acceptance Criteria

- Given erster `propose(... lamport=5, device='A')` Then Set-Score-Row mit `lamport_counter=5`.
- Given zweiter `propose(... lamport=5, device='A')` mit identischem Tupel Then kein neuer Row, gleicher Match-Snapshot.
- Given `propose(... lamport=NULL, device=NULL)` Then Legacy-Pfad, neue Row jedes Mal.
- Given Submit `lamport=5, device='A'` plus Submit `lamport=6, device='A'` (zwei Devices oder zwei Konsens-Runden) Then zwei Rows.

### Notes

- Test ist Merge-Gate für M4.3.

---

## TASK-M4.3-T4: LamportClock-Hydration Property-Tests (Test-First)

- **Type**: tests
- **Size**: M
- **Bounded Context**: match
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 7
- **Files (anticipated)**: `packages/kubb_domain/test/values/lamport_clock_hydration_test.dart`
- **LOC-Budget**: ~100

### Goal

Property-Tests definieren Public-API von `LamportClock.hydrateFromOutbox(matchId, deviceId, outboxMax)` und `observeFromStream(stream)` (per ADR-0006). TDD: rote Tests vor Wave-8-Impl.

### Acceptance Criteria

- Given n Mock-Outbox-Counter [3, 7, 5] für `(match, device)` When `hydrateFromOutbox(match, device, 7)` Then nächster `.tick()` liefert 8.
- Given Hydration aus Outbox-Max=10 plus späteres `observeFromStream` mit Server-Max=15 Then nächster `.tick()` liefert 16.
- Given zwei `LamportClock`-Instanzen für verschiedene `(match, device)`-Paare Then unabhängige Counter.
- Given glados-Property `forall n: hydrate(n) → tick > n` Then grün.

### Notes

- OD-M4-05 (Lamport jetzt produktiv).
- **Contract für M4.3-T8 (Hydration-Provider-Impl)**: Methoden-Signaturen + Verhalten verbindlich.

---

## TASK-M4.3-T5: OutboxFlusher Property-Tests (Test-First)

- **Type**: tests
- **Size**: L
- **Bounded Context**: core
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 7
- **Files (anticipated)**: `test/core/application/outbox_flusher_test.dart`
- **LOC-Budget**: ~100

### Goal

Tests definieren Public-API von `OutboxFlusher`: Order-Flush nach `queuedAt ASC`, Retry-Loop bei Network-Error (exponential mit Cap), Konflikt-Marker bei `STALE_CONSENSUS_ROUND`-Response. TDD: rote Tests vor Wave-8-Impl. Mock `TournamentRemote.proposeSetScoreWithLamport`.

### Acceptance Criteria

- Given drei Outbox-Rows mit `queuedAt` 10:00, 10:01, 10:02 When Flush Then `proposeSetScoreWithLamport` wird in dieser Reihenfolge aufgerufen.
- Given Mock wirft `SocketException` beim ersten Versuch When Retry Then zweiter Versuch nach Backoff.
- Given Mock wirft `STALE_CONSENSUS_ROUND` Then Outbox-Row bekommt `lastErrorCode='STALE_CONSENSUS_ROUND'`, kein weiterer Retry.
- Given Mock liefert Erfolg Then Row bekommt `acknowledgedAt`.
- Given ConnectivityService-Mock emittiert offline-Status Then Flush pausiert.

### Notes

- **Contract für M4.3-T7 (Impl)**: Methoden `flushPending()`, `onConnectivityChange(online)`, plus Public-API für UI-Konsum verbindlich.

---

## TASK-M4.3-T6: TournamentRemote.proposeSetScoreWithLamport + Adapter-Impls

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.3-T2
- **Wave**: 8
- **Files (anticipated)**: `packages/kubb_domain/lib/src/ports/tournament_remote.dart` (edit), `lib/features/tournament/data/supabase_tournament_remote.dart` (edit), `lib/features/tournament/data/fake_tournament_remote.dart` (edit)
- **LOC-Budget**: ~100

### Goal

Port-Methode `Future<TournamentMatchRef> proposeSetScoreWithLamport({matchId, consensusRound, setIndex, submitter, score, lamportCounter, deviceId})` gemäss `architecture.md` §3.5. `SupabaseTournamentRemote`-Impl ruft RPC mit den sechs Parametern. `FakeTournamentRemote`-Impl simuliert Idempotency-Check im Memory.

### Acceptance Criteria

- Given Port-Methode aufgerufen When Supabase-Adapter Then RPC mit allen sechs Parametern.
- Given Fake-Adapter mit doppeltem `(match, round, set, submitter, counter, device)` Then beim zweiten Aufruf gleicher Match-Snapshot ohne neuen Score.
- Given Fake-Adapter mit `STALE_CONSENSUS_ROUND` injizierbar (via Test-Konfiguration) Then `TournamentScoreConflictException` wird geworfen.

### Notes

- Wiederverwendung der RPC-Wire-Signatur aus T2.

---

## TASK-M4.3-T7: OutboxFlusher-Impl

- **Type**: frontend
- **Size**: L
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.3-T1, TASK-M4.3-T6, TASK-M4.3-T9, TASK-M4.3-T5
- **Wave**: 8
- **Files (anticipated)**: `lib/core/application/outbox_flusher.dart`
- **LOC-Budget**: ~100

### Goal

Konkrete `OutboxFlusher`-Impl macht T5-Property-Tests grün. Connectivity-Listener (T9), `queuedAt`-Order-Flush, Retry-Loop, `lastErrorCode`-Marking, idempotenter Re-Flush.

### Acceptance Criteria

- Given T5-Property-Tests Then alle grün.
- Given Flusher als Riverpod-Provider `outboxFlusherProvider` Then beim App-Start einmal hydratisiert.
- Given Connectivity-Wechsel offline→online Then `flushPending()` wird ausgelöst.

### Notes

- Singleton-Pattern via Riverpod-`Provider` (kein KeepAlive auf Family).

---

## TASK-M4.3-T8: LamportClock-Hydration-Provider

- **Type**: frontend
- **Size**: M
- **Bounded Context**: match
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.3-T1, TASK-M4.3-T4
- **Wave**: 8
- **Files (anticipated)**: `lib/features/match/application/lamport_clock_provider.dart`
- **LOC-Budget**: ~80

### Goal

`LamportClock`-Hydration-Provider. Macht T4-Property-Tests grün. Beim App-Start: `hydrateFromOutbox(matchId, deviceId)` aus drift-DAO (T1). Sobald Realtime-Channel `joined`: `observeFromStream` synct mit Server-Stream-Max.

### Acceptance Criteria

- Given T4-Property-Tests Then alle grün.
- Given Provider als `family<MatchId>` Then pro Match eigener Clock.
- Given App startet offline Then Hydration nur aus Outbox; sobald Realtime joint, Server-Stream übernimmt.

### Notes

- `device_id` aus `flutter_secure_storage` (siehe T9-Service oder eigener Helper).
- R-M4.3-4-Mitigation: Outbox-Counter ist Untergrenze, Server-Stream korrigiert nach oben.

---

## TASK-M4.3-T9: ConnectivityService-Wrapper

- **Type**: data
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: —
- **Wave**: 8
- **Files (anticipated)**: `lib/core/data/connectivity/connectivity_service.dart`, `pubspec.yaml` (edit)
- **LOC-Budget**: ~60

### Goal

`ConnectivityService`-Port abstrahiert `connectivity_plus` plus `FakeConnectivityService` für Tests. Pubspec-Eintrag `connectivity_plus: ^6.x` (aktuelle Major).

### Acceptance Criteria

- Given Port mit `Stream<bool> get onlineStream` und `bool get isOnline` Then deklariert.
- Given `RealConnectivityService` wrapt `Connectivity().onConnectivityChanged`.
- Given `FakeConnectivityService.emit(online: false)` Then Stream emittiert false.
- Given `flutter pub get` Then `connectivity_plus` aufgelöst.

### Notes

- Doku in Commit-Message (per `architecture.md` §5): keine ADR-Pflicht, Plugin-Stand begründet.

---

## TASK-M4.3-T10: tournament_repository.proposeSetScore Umstellung

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.3-T1, TASK-M4.3-T7
- **Wave**: 9
- **Files (anticipated)**: `lib/features/tournament/data/tournament_repository.dart` (edit)
- **LOC-Budget**: ~80

### Goal

`proposeSetScore` schreibt zuerst in Outbox (T1), löst dann sofort `OutboxFlusher.flushPending()` (T7). Bei online sofortiger Flush, bei offline gequeut. Direkter Pfad (RPC-Call ohne Outbox) wird entfernt.

### Acceptance Criteria

- Given online + Submit Then Outbox-Row entsteht, Flush läuft sofort, Row bekommt `acknowledgedAt` in <1 s (Mock).
- Given offline + Submit Then Outbox-Row entsteht, `acknowledgedAt IS NULL`, UI bekommt Pending-State.
- Given bestehende Score-Tests Then weiterhin grün (Mock-Outbox als InMemory-DAO).

### Notes

- **Breaking-Change**: alle bestehenden Score-Submit-Pfade gehen jetzt durch Outbox. Tests müssen DAO-Override haben.

---

## TASK-M4.3-T11: UI-Marker Pending + Conflict

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.3-T1, TASK-M4.3-T7
- **Wave**: 9
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/score_pending_indicator.dart`, `lib/features/tournament/presentation/tournament_match_detail_screen.dart` (edit)
- **LOC-Budget**: ~80

### Goal

Im Match-Detail-Screen: Outbox-Row ohne `acknowledgedAt` → Pending-Indicator (Spinner + "ausstehend, wird übertragen"). Outbox-Row mit `lastErrorCode='STALE_CONSENSUS_ROUND'` → Konflikt-Banner mit Erklärung + Link "Letzten Vorschlag anzeigen" (R-M4.3-3-Mitigation).

### Acceptance Criteria

- Given Outbox-Row pending Then Pending-Indicator sichtbar im Match-Header.
- Given Outbox-Row mit `STALE_CONSENSUS_ROUND` Then roter Banner mit Erklär-Text plus "Erneut eingeben"-Button (führt zurück zur Score-Eingabe).
- Given Outbox-Row ack'd und gelöscht Then Indicator weg.

### Notes

- l10n-Keys in T14.

---

## TASK-M4.3-T12: Offline-Banner-Widget

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.3-T9, TASK-M4.3-T1
- **Wave**: 9
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/offline_banner.dart`, `lib/app/app_shell.dart` (edit)
- **LOC-Budget**: ~70

### Goal

Globaler Banner im App-Scope (über `Scaffold.body`). Sichtbar wenn `ConnectivityService.isOnline=false`. Text: "Offline — Q Submissions ausstehend" (Q = Outbox-Queue-Size).

### Acceptance Criteria

- Given offline mit 0 pending Then Banner zeigt "Offline".
- Given offline mit 3 pending Then "Offline — 3 Submissions ausstehend".
- Given online Then Banner versteckt.

### Notes

- Sticky am Top, hellgelb, 36px Höhe.

---

## TASK-M4.3-T13: Outbox-GC-Task

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.3-T1
- **Wave**: 9
- **Files (anticipated)**: `lib/core/application/outbox_gc_task.dart`, `lib/app/app_bootstrap.dart` (edit)
- **LOC-Budget**: ~50

### Goal

Beim App-Start: `DELETE FROM score_submission_outbox WHERE acknowledged_at < now() - INTERVAL '30 days'`. Idempotent.

### Acceptance Criteria

- Given alte ack'd-Row (>30 Tage) When App startet Then Row weg.
- Given junge Row (<30 Tage) When App startet Then Row bleibt.
- Given pending Row (unabhängig vom Alter) When App startet Then Row bleibt.

### Notes

- Hook via App-Bootstrap (`runApp`-Vorlauf).

---

## TASK-M4.3-T14: l10n DE-Strings für M4.3

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M4.3-T11, TASK-M4.3-T12
- **Wave**: 9
- **Files (anticipated)**: `lib/l10n/app_de.arb` (edit), `lib/l10n/app_en.arb` (edit, optional Stub)
- **LOC-Budget**: ~40

### Goal

Strings: `scorePending` ("ausstehend, wird übertragen"), `scoreConflictTitle` ("Sync-Konflikt"), `scoreConflictExplanation` ("Dein Vorschlag konnte nicht übertragen werden, weil der Gegner schon korrigiert hat. Bitte erneut eingeben."), `scoreConflictReenterButton` ("Erneut eingeben"), `offlineBannerLabel`, `offlineBannerQueueSize` (mit Plural).

### Acceptance Criteria

- Given ARB erweitert When Generator-Lauf Then keine Fehler.
- Given Plural für `offlineBannerQueueSize` Then korrektes Format `{count, plural, one{...} other{...}}`.

---

## TASK-M4.3-T15: score_offline_sync_e2e_test

- **Type**: tests
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M4.3-T7, TASK-M4.3-T8, TASK-M4.3-T10, TASK-M4.3-T11, TASK-M4.3-T12
- **Wave**: 9
- **Files (anticipated)**: `test/integration/score_offline_sync_e2e_test.dart`
- **LOC-Budget**: ~100

### Goal

End-to-End-Test mit `FakeConnectivityService` + `FakeTournamentRemote`: Offline → drei Set-Scores → Online → assert drei Sets synchronisiert + Pending-Indicator weg. Zweiter Flush (manuell ausgelöst) ist No-Op (Idempotenz).

### Acceptance Criteria

- Given `FakeConnectivityService.emit(online=false)` plus drei `proposeSetScore`-Calls Then Outbox hat drei pending Rows.
- Given `FakeConnectivityService.emit(online=true)` Then alle drei Rows in <100 ms (Test-Time) ack'd.
- Given zweiter `flushPending()` Then keine doppelten RPC-Calls (Mock-Counter verifiziert).
- Given `STALE_CONSENSUS_ROUND` injiziert für einen Submit Then Konflikt-Banner sichtbar im Widget-Render.

### Notes

- Pure Test mit Fakes — kein echter Supabase-Aufruf.

---

## TASK-M4.3-T16: Demo-Script

- **Type**: docs
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-docs
- **Dependencies**: TASK-M4.3-T15
- **Wave**: 9
- **Files (anticipated)**: `docs/plans/m4-realtime-dashboard-offline/demo-script.md`
- **LOC-Budget**: ~80

### Goal

Owner-Demo-Script gemäss `architecture.md` §11 plus Pre-Demo-Checklist (Web-Build-Status, Realtime-Connect-Test, Flugmodus-Toggle-Verlässlichkeit per R-M4.2-3 und §"Demobarkeits-Risiko-Bewertung"). Sieben-Schritte-Flow aus `milestone-plan.md` §"Was nach M4 demobar ist" durchschreiben.

### Acceptance Criteria

- Given Demo-Script Then alle sieben Schritte aus `milestone-plan.md` §"Was nach M4 demobar ist" abgedeckt.
- Given Pre-Demo-Checklist Then Web-Build, Realtime-Connect, Flugmodus-Toggle, Pro-Tier-Upgrade-Option erwähnt.
- Given Demo-Dauer-Schätzung Then 25–35 Min.

### Notes

- Vorbild M3-Demo-Script-Format.
- Hier nur Doku — keine Code-Änderungen.
