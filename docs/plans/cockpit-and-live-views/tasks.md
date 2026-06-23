# Tasks — Cockpit, Live-Views, Match-Entry, Realtime & Typ-Graph-Editor

**Status:** Sprint-Backlog (atomare Tasks für `/workflows/implement`).
**Bezug:** `docs/plans/cockpit-and-live-views/architecture.md` (W0 -> W5),
`sprint-plan.md`, ADR-0041/0043/0044/0045, Forward-Specs unter `docs/specs/`.
**Level:** senior (TDD-first, Conventional-Commit-Scopes, pgTAP je RPC-Berührung,
security-checker bei Grant/RLS/SECURITY DEFINER).
**Atomarität (senior):** <=100 LOC, <=3 Dateien, <=1h pro Task, ein Agent pro Task,
Dependencies azyklisch (DAG).

> **Legende Size:** S = 0.5-1h, M = 1-3h, L = 3-5h (mit senior-Faktor 0.8).
> **Legende Type:** docs | tests | data (SQL/Migration) | security | domain | frontend (UI/Riverpod).
> **Agent-Mapping:** docs -> coder(docs); domain/data -> coder(domain/data); frontend -> coder(frontend);
> tests -> tester; SQL/RPC/RLS-Review -> security-checker.

> **Gestrichen (dedupliziert nach W0):** W4-T01, W4-T02, W4-T03 (pitch_number kommt
> aus W0), W2-T08 (ADR-0042 obsolet). IDs bleiben zur Nachvollziehbarkeit erhalten
> und sind unten klar als GESTRICHEN markiert. 87 geplant -> 83 aktiv.

---

# W0 — Spec-Import + pitch_number-Fundament

Additives Fundament. Importiert die 4 Forward-Specs + ADR-0041, projiziert das
bereits existierende pitch_number bis in den Client und friert das Override-Gate
per pgTAP ein. KEINE Schema-Migration, KEINE Gate-Migration (beides existiert
bereits — siehe `architecture.md` §0 Stale-Briefing-Korrekturen).

---

## W0-T01: 4 Forward-Specs von origin/docs/schoch-buchholz-spec auf main importieren (1:1)

- **Type:** docs · **Size:** S · **Context:** docs/ (kein Bounded Context) · **Agent:** coder(docs) · **Dependencies:** - · **Files:** docs/specs/realtime-sync-fixes-spec.md, docs/specs/live-views-and-inbox-spec.md, docs/specs/match-entry-and-home-tile-spec.md, docs/specs/organizer-cockpit-dashboard-spec.md

### Acceptance (Given/When/Then)
Given origin/docs/schoch-buchholz-spec enthält die 4 Specs / When git show <ref>:<pfad> > docs/specs/<datei> für alle 4 / Then alle 4 Dateien existieren auf main, sind nicht leer, valides Markdown (stepValidator L1/2)

### Notes
git show statt cherry-pick (nur Datei-Inhalt 1:1). Pitfall: nur diese 4 Specs, nicht die ganze Branch mergen. Cross-Refs der realtime-sync-Spec werden erst in W0-T03 umgezogen.

---

## W0-T02: Push-Freshness-ADR als docs/adr/0041 importieren (umnummeriert von origin-0035)

- **Type:** docs · **Size:** S · **Context:** docs/ (kein Bounded Context) · **Agent:** coder(docs) · **Dependencies:** - · **Files:** docs/adr/0041-push-critical-freshness-and-delta-catchup.md

### Acceptance (Given/When/Then)
Given origin-ADR-0035 (push-freshness) / When als docs/adr/0041-*.md importiert, Header Status/Date übernommen / Then 0041 existiert, ADR-Pflichtsektionen (Entscheidung/Kontext/Alternativen/Konsequenzen/Status) vorhanden, main-0035-vorrunde-ranking.md UNVERÄNDERT

### Notes
KRITISCH: 0041, NICHT 0035 — main-0035 ist vorrunde-ranking und darf nicht überschrieben werden. ADR-0041 ist auch das Ziel-ADR von W1 (W1-T18 schreibt den v1-Korrektheits-Body in dieselbe Datei).

---

## W0-T03: Cross-Refs ADR-0035 -> ADR-0041 in realtime-sync-fixes-spec umziehen (9 Vorkommen) + Verifikations-grep

- **Type:** docs · **Size:** S · **Context:** docs/ (kein Bounded Context) · **Agent:** coder(docs) · **Dependencies:** W0-T01, W0-T02 · **Files:** docs/specs/realtime-sync-fixes-spec.md

### Acceptance (Given/When/Then)
Given die importierte Spec referenziert ADR-0035 in Z6/42/46/55/59/61/149/151/155 / When alle Vorkommen des Refs auf ADR-0041 umgezogen / Then grep -c 'ADR-0035' docs/specs/realtime-sync-fixes-spec.md == 0 UND 'ADR-0041' vorhanden

### Notes
Nur diese eine Spec hat 0035-Refs (die anderen 3 sind 1:1). Pitfall: kein blindes sed über alle docs/, nur die importierte Datei.

---

## W0-T04: pgTAP match_pitch_number_projection_test.sql (TDD: vor Migration)

- **Type:** tests · **Size:** M · **Context:** supabase/tests (quer zu tournament/) · **Agent:** tester · **Dependencies:** - · **Files:** supabase/tests/match_pitch_number_projection_test.sql

### Acceptance (Given/When/Then)
Given Turnier mit PitchPlan gestartet + Runde gepaart / When tournament_match_get(match) und tournament_list_matches(t) aufgerufen / Then beide liefern den vom Assign-Helper gesetzten pitch_number-Wert (initial ROT — Projektion fehlt noch)

### Notes
Muster aus stage_node_group_pitch_assignment_test.sql. TDD-Anker für W0-T05. pitch_number-Spalte existiert seit 20260525000001:67, wird von _tournament_assign_pitches gespeist.

---

## W0-T05: Migration 20261317000000 — pitch_number in tournament_match_get + tournament_list_matches projizieren

- **Type:** data · **Size:** M · **Context:** supabase/migrations (quer zu tournament/) · **Agent:** coder(data) · **Dependencies:** W0-T04 · **Files:** supabase/migrations/20261317000000_match_get_list_pitch_number.sql

### Acceptance (Given/When/Then)
Given W0-T04 ist ROT / When CREATE OR REPLACE tournament_match_get (Basis body 20261306000000) + tournament_list_matches (Basis 20261212000000) je um 'pitch_number', m.pitch_number ergänzt / Then W0-T04 GRÜN, keine Schema-Migration, kein neuer Index, kein RLS-Change

### Notes
Bodies 1:1 re-stated, NUR neue Projektion. KEIN Drop. KEIN Index (get=PK, list=tournament_id-Index existiert). Pitfall: Timestamp 20261317000000 ist hier reserviert — W4 muss eigene Timestamps ab 20261320000000 nehmen (Kollision im Briefing).

---

## W0-T06: security-checker: Migration 20261317000000 Grant/RLS-Review (pitch_number-Projektion)

- **Type:** security · **Size:** S · **Context:** supabase/migrations · **Agent:** security-checker · **Dependencies:** W0-T05 · **Files:** supabase/migrations/20261317000000_match_get_list_pitch_number.sql

### Acceptance (Given/When/Then)
Given die re-stated RPCs / When Grants/RLS gegen Vorgänger-Body diffen / Then GRANT EXECUTE unverändert (authenticated), pitch_number fällt unter bestehende tournament_matches-RLS, keine Privilege-Erweiterung

### Notes
Pflicht-Review nach jeder RPC-Re-Aussage (Grant-Drift-Risiko bei CREATE OR REPLACE). Keine neuen Grants erwartet.

---

## W0-T07: Unit-Test pitchNumber-Decoding (TDD: vor Domain-Feld)

- **Type:** tests · **Size:** S · **Context:** packages/kubb_domain (pure Dart) · **Agent:** tester · **Dependencies:** - · **Files:** packages/kubb_domain/test/ports/tournament_match_ref_pitch_test.dart

### Acceptance (Given/When/Then)
Given eine Row mit pitch_number und eine ohne / When tournamentMatchRefFromRow dekodiert / Then pitchNumber == Wert bzw. null bei fehlender Spalte (initial ROT)

### Notes
TDD-Anker für W0-T08. null-tolerant via _asIntOrNull (NICHT _asInt) — gleiche Konvention wie stageNodeId/setsWonA.

---

## W0-T08: TournamentMatchRef.pitchNumber Feld (Port) + Decoder-Mapping (fromRow + fromCdcRow)

- **Type:** domain · **Size:** S · **Context:** tournament/ (Port pure Dart + data-Adapter) · **Agent:** coder(domain) · **Dependencies:** W0-T05, W0-T07 · **Files:** packages/kubb_domain/lib/src/ports/tournament_remote.dart, lib/features/tournament/data/tournament_models.dart

### Acceptance (Given/When/Then)
Given W0-T07 ist ROT / When 'final int? pitchNumber' (default null) nach stageNodeId ergänzt + tournamentMatchRefFromRow(~Z487) und ...FromCdcRow(~Z361) lesen 'pitchNumber: _asIntOrNull(row[pitch_number])' / Then W0-T07 GRÜN, alte CDC-Rows/Fakes crashen nicht

### Notes
dep auf W0-T05: Migration MUSS vor Decoder gemerged sein, sonst liefert RPC das Feld nie (fällt null-tolerant zurück, Banner zeigt keine Nummer). Pitfall: _asIntOrNull, nicht _asInt.

---

## W0-T09: pitch_call_banner.dart auf ref.pitchNumber umstellen + my_active_match_provider Stub-Doc bereinigen

- **Type:** frontend · **Size:** S · **Context:** tournament/ (Presentation + Application) · **Agent:** coder(frontend) · **Dependencies:** W0-T08 · **Files:** lib/features/tournament/presentation/widgets/pitch_call_banner.dart, lib/features/tournament/application/my_active_match_provider.dart

### Acceptance (Given/When/Then)
Given W0-T08 hat pitchNumber am Ref / When Banner ref.pitchNumber des eigenen aktiven Matches zeigt (Quelle my_active_match_provider) statt clientseitiger PitchPlan-Ableitung + Stub-Doc Z22 'no pitch_number yet' entfernt / Then Banner zeigt materialisierte Pitch-Nummer, flutter analyze clean

### Notes
dep W0-T08 (Wire-Feld). PitchPlan in tournament_setup.dart bleibt unverändert (Setup-Zeit-Quelle).

---

## W0-T10: pgTAP override_gate_administer_test.sql (Regression-Freeze des bestehenden Gates)

- **Type:** tests · **Size:** S · **Context:** supabase/tests · **Agent:** tester · **Dependencies:** - · **Files:** supabase/tests/override_gate_administer_test.sql

### Acceptance (Given/When/Then)
Given verifiziertes Gate tournament_caller_can_administer (20261314000000:76) / When Club-admin (nicht creator) tournament_organizer_override aufruft / Then erlaubt; fremder User -> 42501 'caller cannot administer'

### Notes
VERIFIZIEREN statt bauen — Gate ist bereits caller_can_administer (Briefing-Annahme creator-only ist superseded). KEINE Body-Änderung. Muster aus organizer_override_kubb_diff_test.sql. deprecated-Alias caller_can_manage->administer unangetastet. Friert das Gate für W4-Direct-Score ein.

---

# W1 — Realtime-Korrektheit v1

Rein clientseitig, keine Server-Migration. Harte Reihenfolge: Robustheits-Guards
(T01/T03) VOR Standings-CDC (T08) und Catch-up (T10); Kritikalitäts-Stufe (T16)
ZULETZT. ADR-0029-Battery-Invariante nicht regredieren (kein Timer.periodic).

---

## W1-T01: disposed-Guard im CDC-Callback (supabase_realtime_channel.dart:63)

- **Type:** data · **Size:** S · **Context:** core/data/realtime (transport-agnostisch) · **Agent:** coder(data) · **Dependencies:** - · **Files:** lib/core/data/realtime/supabase_realtime_channel.dart

### Acceptance (Given/When/Then)
Given onPostgresChanges-Callback feuert nach dispose / When vor entry.changeController.add(...) auf entry.disposed geprüft / Then kein add-after-close, kein StreamController-closed-Throw (Spec Bug 4.1)

### Notes
ADR-0029-Battery-Invariante: kein neuer Timer. Guards VOR allem anderen in W1 (erhöhte Event-Rate triggert sonst Crashes). Test in W1-T06.

---

## W1-T02: teardownTransport defensiv in disposeEntry kapseln (realtime_channel_lifecycle.dart:94-105)

- **Type:** data · **Size:** S · **Context:** core/data/realtime · **Agent:** coder(data) · **Dependencies:** - · **Files:** lib/core/data/realtime/realtime_channel_lifecycle.dart

### Acceptance (Given/When/Then)
Given teardownTransport wirft bei broadcast-/CDC-Adapter / When in disposeEntry try/catch gekapselt / Then disposeEntry wirft nie (Mixin-Kontrakt 'must not throw', Bug 4.2)

### Notes
refCount-Teardown NICHT verändern (referenceCount-Smoke-Test M4.1-T7 bleibt grün).

---

## W1-T03: Fallback-Gate-Race fixen: isClosed-Guard + single-flight pendingFlip (realtime_fallback_provider.dart:81-117)

- **Type:** data · **Size:** S · **Context:** core/data/realtime · **Agent:** coder(data) · **Dependencies:** - · **Files:** lib/core/data/realtime/realtime_fallback_provider.dart

### Acceptance (Given/When/Then)
Given errored<->joined-Flackern / When controller.isClosed-Guard vor controller.add (emit + connecting/closed-Pfad) + single-flight pendingFlip / Then genau ein Fallback-Timer, kein add-after-close (Bug 4.3)

### Notes
Guards VOR Standings-CDC. Self-rearming Single-Timer, kein Timer.periodic (ADR-0029).

---

## W1-T04: backoffIndex-Reset bei manuellem closeRef (realtime_channel_lifecycle.dart:83-90,136)

- **Type:** data · **Size:** S · **Context:** core/data/realtime · **Agent:** coder(data) · **Dependencies:** - · **Files:** lib/core/data/realtime/realtime_channel_lifecycle.dart

### Acceptance (Given/When/Then)
Given manuelles closeRef/Re-Join / When backoffIndex in closeRef auf 0 zurückgesetzt (pushState:122 macht das bei joined bereits) / Then nächster Fehler startet wieder bei 1s (Bug 4.4)

### Notes
W1-T02 + W1-T04 beide in realtime_channel_lifecycle.dart — sequenziell (depends_on T02) um Edit-Konflikt zu vermeiden.

---

## W1-T05: Broadcast-refCount-Cleanup im subscribe-Fehlerpfad (public_tournament_realtime.dart:213-258)

- **Type:** data · **Size:** S · **Context:** data/ (Broadcast-Adapter) · **Agent:** coder(data) · **Dependencies:** - · **Files:** lib/features/tournament/data/public_tournament_realtime.dart

### Acceptance (Given/When/Then)
Given subscribe schlägt fehl / When refCount-Decrement + _entries.remove + channel-cleanup auch im Fehlerpfad (nicht nur onCancel) / Then refCount==0, kein Zombie-Channel (Bug 4.5)

### Notes
autoDispose/refCount-Teardown-Verhalten darf nicht regredieren.

---

## W1-T06: Test-First: FakeRealtimeChannel-Tests Robustheit (Bug 4.1/4.3/4.4/4.5)

- **Type:** tests · **Size:** S · **Context:** core/data/realtime + data/ · **Agent:** tester · **Dependencies:** - · **Files:** test/core/data/realtime/realtime_robustness_test.dart

### Acceptance (Given/When/Then)
Given FakeRealtimeChannel + ProviderContainer-Override / When dispose-während-Event, errored<->joined-Flackern, closeRef, fehlgeschlagener subscribe simuliert / Then kein add-after-close (5.4), genau ein Fallback-Timer (5.5), backoffIndex==0 nach closeRef, refCount==0 (4.5)

### Notes
TDD: vor/parallel zu T01/T03/T04/T05 geschrieben (Test-First, Senior). FakeRealtimeChannel ist Truth-Source (existiert in test_support).

---

## W1-T07: Test: Standings invalidiert bei tournament_matches-CDC (TDD: vor T08)

- **Type:** tests · **Size:** S · **Context:** tournament/ application · **Agent:** tester · **Dependencies:** - · **Files:** test/features/tournament/application/standings_realtime_test.dart

### Acceptance (Given/When/Then)
Given fake.emit(tournament_matches-update) / When tournamentStandingsRealtimeProvider(id) subscribed / Then tournamentStandingsProvider(id) wird invalidiert/re-evaluiert (5.1, initial ROT)

### Notes
TDD-Anker für W1-T08. Nur fetch-basierte FutureProvider invalidieren, NICHT CDC-Fold-Provider (tournamentRoundScheduleProvider).

---

## W1-T08: tournamentStandingsRealtimeProvider anlegen + Standings ans CDC hängen

- **Type:** domain · **Size:** S · **Context:** tournament/ application · **Agent:** coder(domain/app) · **Dependencies:** W1-T03, W1-T07 · **Files:** lib/features/tournament/application/tournament_realtime_provider.dart

### Acceptance (Given/When/Then)
Given W1-T07 ROT / When StreamProvider.autoDispose.family<TournamentMatchRef,TournamentId> watcht remote.watchTournamentMatches und ruft ref.invalidate(tournamentStandingsProvider(id)) je CDC-Event (analog tournamentMatchListRealtimeProvider:22) / Then W1-T07 GRÜN

### Notes
dep T03 (Fallback-Guard vor erhöhter Event-Rate). Pitfall: nicht tournamentRoundScheduleProvider invalidieren (Fold-Reset, Doc-Block :138).

---

## W1-T09: Test: Catch-up-Refetch genau einmal pro errored->joined und auf resume (TDD)

- **Type:** tests · **Size:** M · **Context:** tournament/ application · **Agent:** tester · **Dependencies:** - · **Files:** test/features/tournament/application/realtime_catchup_test.dart

### Acceptance (Given/When/Then)
Given fake debugTransitionTo(errored->joined) bzw. RealtimeLifecycleController.resume() / When kritische Read-Provider beobachtet / Then genau einmal pro Rejoin refetcht (Zähl-Assertion, 5.2/5.3, initial ROT)

### Notes
TDD-Anker für W1-T10.

---

## W1-T10: realtimeCatchupProvider: garantierter Voll-Refetch bei Rejoin/Resume

- **Type:** domain · **Size:** M · **Context:** tournament/ application · **Agent:** coder(app) · **Dependencies:** W1-T01, W1-T03, W1-T09 · **Files:** lib/features/tournament/application/realtime_catchup_provider.dart

### Acceptance (Given/When/Then)
Given W1-T09 ROT / When Provider auf RealtimeChannelState-Übergang nach joined hört und kritische Read-Provider genau einmal pro Rejoin invalidiert (Voll-Refetch v1) / Then W1-T09 GRÜN, Resume via reconnectKeys abgedeckt

### Notes
ADR-0041. PITFALL: NICHT auf CDC-Fold-Provider zielen (tournamentRoundScheduleProvider) — invalidate würde Fold zurücksetzen. Nur fetch-basierte FutureProvider. dep T01/T03 (Guards vor erhöhter Event-Rate).

---

## W1-T11: Test: Check-in aktualisiert in Fallback-Kadenz (TDD: vor T12)

- **Type:** tests · **Size:** S · **Context:** tournament/ application · **Agent:** tester · **Dependencies:** - · **Files:** test/features/tournament/application/participants_fallback_test.dart

### Acceptance (Given/When/Then)
Given Participants-Poller gegated auf realtimeFallbackProvider(tournamentId) / When Fallback aktiv / Then tournamentDetailProvider wird in Fallback-Kadenz invalidiert (5.6, initial ROT)

### Notes
TDD-Anker für W1-T12.

---

## W1-T12: Participants/Check-in-Fallback-Poller gegated ergänzen

- **Type:** domain · **Size:** S · **Context:** tournament/ application · **Agent:** coder(app) · **Dependencies:** W1-T03, W1-T11 · **Files:** lib/features/tournament/application/tournament_match_providers.dart

### Acceptance (Given/When/Then)
Given W1-T11 ROT / When gegateter Fallback-Poller (analog tournamentMatchListPollingProvider) gegated auf realtimeFallbackProvider(tournamentId) ergänzt / Then W1-T11 GRÜN, self-rearming Single-Timer

### Notes
ADR-0029: MUSS gegated sein, kein unconditional Timer.periodic, kein gehaltener Hintergrund-Socket.

---

## W1-T13: Test: Degraded-Banner auf Standings sichtbar/verschwindet (TDD: vor T14)

- **Type:** tests · **Size:** S · **Context:** tournament/ presentation · **Agent:** tester · **Dependencies:** - · **Files:** test/features/tournament/presentation/standings_banner_test.dart

### Acceptance (Given/When/Then)
Given Standings-Screen / When errored>60s / Then 'Live unterbrochen'-Strip sichtbar; bei joined verschwindet er (5.7, initial ROT)

### Notes
TDD-Anker für W1-T14. Bestehende RealtimeStateBanner/RealtimeStatusBanner wiederverwenden (nicht duplizieren).

---

## W1-T14: Standings-/Live-Screen: RealtimeStatusBanner+RealtimeStateBanner einhängen + Subscribe-Anker

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W1-T08, W1-T13 · **Files:** lib/features/tournament/presentation/tournament_standings_screen.dart, lib/features/tournament/presentation/tournament_live_screen.dart

### Acceptance (Given/When/Then)
Given W1-T13 ROT / When StandingsView.build ref.watch(tournamentStandingsRealtimeProvider(id)) als Subscribe-Anker + Banner-Paar eingehängt, Live-Rangliste-Tab analog / Then W1-T13 GRÜN, keine doppelten Strips auf Match-Detail

### Notes
dep T08 (Provider muss existieren). Banner wiederverwenden, nicht duplizieren.

---

## W1-T15: Test: criticalityFor-Mapping critical/normal pro Builder (TDD: vor T16)

- **Type:** tests · **Size:** S · **Context:** packages/kubb_domain (pure Dart) · **Agent:** tester · **Dependencies:** - · **Files:** packages/kubb_domain/test/realtime/criticality_test.dart

### Acceptance (Given/When/Then)
Given channel-key-Builder / When criticalityFor(tournamentRealtimeChannelKey) bzw. my-teams aufgerufen / Then critical bzw. normal (5.8, initial ROT)

### Notes
TDD-Anker für W1-T16. Reiner dart test im kubb_domain-Paket.

---

## W1-T16: RealtimeCriticality-Enum + criticalityFor-Mapping am channel_keys-Builder

- **Type:** domain · **Size:** S · **Context:** packages/kubb_domain (pure Dart, Flutter-frei) · **Agent:** coder(domain) · **Dependencies:** W1-T15 · **Files:** packages/kubb_domain/lib/src/realtime/channel_keys.dart, packages/kubb_domain/lib/src/ports/realtime_channel.dart

### Acceptance (Given/When/Then)
Given W1-T15 ROT / When RealtimeCriticality{critical,normal}-Enum + Mapping je Builder (tournamentRealtimeChannelKey->critical, my*/friends/inbox->normal) deklarativ / Then W1-T15 GRÜN, kein ad-hoc am Call-Site

### Notes
ZULETZT in W1 (deklarativ, baut auf stabilen Concerns auf). Additiv, kein Wire-Feld, keine JSON-Serialisierung. Builder-API stabil halten (Grundlage für späteren Push/Delta-Tier).

---

## W1-T17: Verifikations-Notiz: pg_publication_tables + monotone 202612xx-Sequenz (kein Code)

- **Type:** docs · **Size:** S · **Context:** supabase (Verifikation, keine Migration) · **Agent:** architect · **Dependencies:** - · **Files:** docs/notes/realtime-publication-verification.md

### Acceptance (Given/When/Then)
Given Prod-DB / When pg_publication_tables auf supabase_realtime geprüft + Migrations-Sequenz 202612xx bestätigt / Then Befund als Notiz dokumentiert, KEINE Migration erzeugt

### Notes
Spec §0. tournament_matches/participants bereits publiziert (20261236000000). Reine Verifikation.

---

## W1-T18: ADR-0041 v1-Korrektheits-Body schreiben (amendiert 0029)

- **Type:** docs · **Size:** S · **Context:** docs/adr · **Agent:** architect · **Dependencies:** W0-T02, W1-T16 · **Files:** docs/adr/0041-push-critical-freshness-and-delta-catchup.md

### Acceptance (Given/When/Then)
Given die in W0-T02 importierte 0041-Datei / When v1-Korrektheits-Entscheidung dokumentiert (Standings first-class CDC, garantierter Voll-Refetch-Catch-up, deklarative Kritikalitäts-Stufe; amendiert 0029, v1-Schritt zu 0035) / Then alle ADR-Pflichtsektionen vorhanden, Status Accepted

### Notes
dep W0-T02 (Datei muss importiert sein) + W1-T16 (Kritikalitäts-Design finalisiert). Delta-Cursor-Phase explizit als Folge-Welle markieren.

---

# W2 — Match-Entry Quick-Wins

Reine UI/Presentation, keine Server-/Wire-Änderung. S3 zuerst (isoliert). S4 erst
Banner-Erweiterung, dann Home-Umbau (netto exakt eine Match-Kachel).

> **Reconciliation B:** Der Pitch-Header (W2-T05) nutzt `ref.pitchNumber` aus W0 —
> KEIN `matchNumberInRound`-Stand-in. Damit entfällt ADR-0042; W2-T08
> (ADR-0042 dokumentieren) ist gestrichen.

---

## W2-T01: S3a: _maxSetsFor-Helper + const _maxSets entfernen, Cap in _renderBody berechnen

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** - · **Files:** lib/features/tournament/presentation/tournament_match_detail_screen.dart

### Acceptance (Given/When/Then)
Given matchFormatConfig liefert max_sets / When _maxSetsFor(AsyncValue<TournamentDetail?>) analog _maxBasekubbsFor liest max_sets bzw. fällt auf (2*sets_to_win-1) zurück, Minimum 1, Cap einmal in _renderBody berechnet / Then const _maxSets:74 entfernt, flutter analyze clean

### Notes
S3 zuerst (isoliert, kleinstes Risiko). Override-Screen-Vorlage tournament_override_screen.dart:69-79. Pitfall: _maxSetsFor darf nie < drafts.length cappen.

---

## W2-T02: S3b: beide Satzanzahl-Callsites auf config-Cap umstellen + WidgetTest best-of-3/5

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W2-T01 · **Files:** lib/features/tournament/presentation/tournament_match_detail_screen.dart, test/features/tournament/presentation/match_detail_maxsets_test.dart

### Acceptance (Given/When/Then)
Given config {max_sets:5} / When _addSet-Guard:180 + Add-Button onPressed:681 auf Cap umgestellt / Then Add-Button bis 5 aktiv, ab 5 disabled; {max_sets:3} disabled bei 3; ohne Key Fallback aus sets_to_win Minimum 1

### Notes
dep T01 (Helper muss existieren). KO-Finisher/Validation hängt an Satzanzahl — Remove-Logik bleibt min 1.

---

## W2-T03: S1: BackButton auf context.pop() mit canPop-Fallback + Router-Spy-WidgetTest

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** - · **Files:** lib/features/tournament/presentation/tournament_match_detail_screen.dart, test/features/tournament/presentation/match_detail_back_test.dart

### Acceptance (Given/When/Then)
Given poppbarer Navigator-Stack / When BackButton.onPressed:463-466 = Navigator.canPop(context) ? pop() : go(matchesFor(...)) / Then Tap landet in Herkunft; ohne poppbaren Stack -> go(matchesFor)-Fallback (MockGoRouter)

### Notes
Unabhängig von S3. Pitfall: gleiche Datei wie W2-T01/02 — depends_on auf W2-T02 setzen falls parallel-Edit-Risiko; hier eigenständige Zeile 463-466, parallelisierbar.

---

## W2-T04: S2a: Clock-Gate lockern (startedAt==null -> 'wartet auf Start') ohne Running-Regression + WidgetTest

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W2-T03 · **Files:** lib/features/tournament/presentation/tournament_match_detail_screen.dart, test/features/tournament/presentation/match_detail_clock_test.dart

### Acceptance (Given/When/Then)
Given match.startedAt == null / When Clock-Gate:586-632/802-869 von '!readOnly && startedAt!=null' auf '!readOnly && duration>0' gelockert / Then Clock rendert 'wartet auf Start' statt SizedBox.shrink; bei startedAt!=null Running/Hold-Zustand unverändert

### Notes
depends_on W2-T03: selbe Datei (match_detail_screen). PITFALL: RoundPhaseCountdown/ADR-0031-Schedule-Logik darf nicht zerstört werden — nur startedAt==null-Fall ergänzen.

---

## W2-T05: S2b: _Header Pitch statt 'Spiel' (ref.pitchNumber aus W0) + ARB-Key + gen-l10n + WidgetTest

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W2-T04, W0-T08 · **Files:** lib/features/tournament/presentation/tournament_match_detail_screen.dart, lib/l10n/app_de.arb

### Acceptance (Given/When/Then)
Given _Header / When 'Runde X — Spiel Y' durch 'Runde X · Pitch N' (neuer ARB tournamentMatchHeaderRoundPitch, Quelle ref.pitchNumber aus W0) ersetzt + flutter gen-l10n / Then _Header-Text enthält Pitch-Label nicht 'Spiel', ARB<->generated synchron

### Notes
RECONCILIATION B: Header zeigt Pitch aus ref.pitchNumber (W0), KEIN matchNumberInRound-Stand-in. Deshalb zusätzliche Dep auf W0-T08 (Wire-Feld). ADR-0042 entfällt (siehe gestrichenes W2-T08). depends_on W2-T04 (selbe Datei tournament_match_detail_screen.dart, Edit-Konflikt vermeiden).

---

## W2-T06: S4a: PitchCallBanner cross-tournament-tauglich (Wrapper gegen myActiveTournamentMatchProvider) + WidgetTest

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** - · **Files:** lib/features/tournament/presentation/widgets/pitch_call_banner.dart, test/features/tournament/presentation/pitch_call_banner_cross_test.dart

### Acceptance (Given/When/Then)
Given kein tournamentId-Kontext / When dünner Home-Wrapper MyActiveTournamentMatch in bestehende Banner-Darstellung füttert, _open auf tournament.tournamentId.value routet / Then Banner rendert cross-tournament, _open navigiert korrekt

### Notes
S4-Reihenfolge: erst Banner-Erweiterung, DANN Home-Umbau. Pitfall: PitchCallBanner-im-Detail-Screen(:475) bleibt unberührt. ACHTUNG: pitch_call_banner.dart auch von W0-T09 angefasst — falls W0 vor W2 läuft, kein Konflikt; sonst sequenzieren.

---

## W2-T07: S4b: home_screen grüne Kachel conditional + _OngoingMatchCard/TournierCard/Imports entfernen + WidgetTest

- **Type:** frontend · **Size:** M · **Context:** training/ presentation (Konsument tournament-Provider) · **Agent:** coder(frontend) · **Dependencies:** W2-T06 · **Files:** lib/features/training/presentation/home_screen.dart

### Acceptance (Given/When/Then)
Given myActiveTournamentMatchProvider data!=null / When grüne Cross-Tournament-PitchCall-Kachel conditional eingesetzt, _OngoingMatchCard-Block+Klasse(:121-124,:201-233) + TournierCard-Platzhalter(:125-130) + ungenutzte Imports entfernt / Then genau eine Match-Kachel (ValueKey); data==null -> keine Kachel

### Notes
dep W2-T06 (Banner-Variante muss existieren). Netto exakt eine Match-Kachel. Cross-Context über Value-Objekt MyActiveTournamentMatch, kein DB-Join.

---

## W2-T08: ADR Wave-2-Pitch-Header-Quelle dokumentieren  — GESTRICHEN

> **GESTRICHEN — Reconciliation B. Begründung: ADR-0042 (Wave-2-Pitch-Header-Stand-in) entfällt, weil das echte pitch_number aus W0 landet. Der Header (W2-T05) nutzt ref.pitchNumber direkt, ein matchNumberInRound-Stand-in ist nicht mehr nötig — also auch kein dokumentierendes ADR.**

_Ursprüngliche Planung (zur Nachvollziehbarkeit):_ Type docs · Size S · Agent architect · Files `docs/adr/0042-wave2-pitch-header-source.md`

---

## W2-T09: Quality-Gate W2: flutter analyze clean + flutter test grün + ARB<->generated synchron

- **Type:** tests · **Size:** S · **Context:** tournament/ + training/ · **Agent:** tester · **Dependencies:** W2-T02, W2-T05, W2-T07 · **Files:** (Verifikation, keine neue Datei)

### Acceptance (Given/When/Then)
Given alle W2-Tasks gemerged / When flutter analyze + flutter test + gen-l10n-Diff geprüft / Then analyze 0 issues, alle Tests grün, ARB und generated/*.dart synchron

### Notes
Welle-Abschluss-Gate. depends_on auf alle UI-Endpunkte der Welle.

---

# W3 — Live-Views config-adaptiv

Server-Änderungen additiv (RPC-Spalten + Wire-Parse). Reihenfolge: Domain-Helfer
+ Wire-groupLabel + RPC-Migration zuerst -> DetailHeader-Getter + View-Extraktionen
parallel -> Live-Screen-Verdrahtung zuletzt. Setzt W1-Realtime + W2-Daten
(group_label/pool_phase_config) voraus.

---

## W3-T01: tests: dart-Unit Token-Mapping + Fallback-Kette (TDD: vor T02)

- **Type:** tests · **Size:** S · **Context:** packages/kubb_domain (pure Dart) · **Agent:** tester · **Dependencies:** - · **Files:** packages/kubb_domain/test/tournament/tiebreaker_test.dart

### Acceptance (Given/When/Then)
Given snake_case-Tokens / When tiebreakerCriterionFromWire('total_points'/'buchholz'/'buchholz_minus_h2h'/'kubb_difference'/'wins'/unbekannt) / Then korrekte TiebreakerCriterion bzw. null bei unbekannt; tiebreakerChainFromTokens baut Kette (initial ROT)

### Notes
TDD-Anker für W3-T02.

---

## W3-T02: domain: tiebreakerCriterionFromWire + tiebreakerChainFromTokens

- **Type:** domain · **Size:** S · **Context:** tournament/ (packages/kubb_domain pure Dart) · **Agent:** coder(domain) · **Dependencies:** W3-T01 · **Files:** packages/kubb_domain/lib/src/tournament/tiebreaker.dart

### Acceptance (Given/When/Then)
Given W3-T01 ROT / When tiebreakerCriterionFromWire(String) + tiebreakerChainFromTokens(List<String>) implementiert (unbekannt -> skip/null) / Then W3-T01 GRÜN

### Notes
Fallback-Pfad für reine roundRobin-Konfigs.

---

## W3-T03: tests: dart-Unit standingsChainFor pro Format (TDD: vor T04)

- **Type:** tests · **Size:** S · **Context:** packages/kubb_domain (pure Dart) · **Agent:** tester · **Dependencies:** - · **Files:** packages/kubb_domain/test/tournament/standings_chain_test.dart

### Acceptance (Given/When/Then)
Given Format+tiebreakerOrder / When standingsChainFor(schoch,..)/( roundRobinThenKo,..)/(roundRobin,customTokens) / Then schoch=Punkte->Buchholz, gruppe/rr-ko=Punkte->KubbDiff (KEIN Buchholz), rr=folgt Tokens (initial ROT)

### Notes
TDD-Anker für W3-T04. Begründet durch vorrunde-ranking-spec §6.2 (Buchholz in Gruppen sinnlos).

---

## W3-T04: domain: standingsChainFor(format, tiebreakerOrder) format-getrieben

- **Type:** domain · **Size:** S · **Context:** tournament/ (packages/kubb_domain pure Dart) · **Agent:** coder(domain) · **Dependencies:** W3-T02, W3-T03 · **Files:** packages/kubb_domain/lib/src/tournament/standings.dart

### Acceptance (Given/When/Then)
Given W3-T03 ROT / When standingsChainFor bevorzugt format-feste Kette (chainForStageType) sonst tiebreakerChainFromTokens / Then W3-T03 GRÜN, ersetzt hart verdrahtete Kette

### Notes
dep T02 (Token-Fallback). ADR-0043 format-getriebene Kette.

---

## W3-T05: tests: pgTAP tournament_list_matches liefert phase + group_label (TDD: vor T07)

- **Type:** tests · **Size:** S · **Context:** supabase/tests · **Agent:** tester · **Dependencies:** - · **Files:** supabase/tests/list_matches_phase_group_test.sql

### Acceptance (Given/When/Then)
Given Matches mit group_label/phase / When tournament_list_matches(t) / Then jsonb enthält 'phase' und 'group_label' (initial ROT)

### Notes
TDD-Anker für W3-T06. Bestehende RPC-Test-Suite erweitern.

---

## W3-T06: data: Migration w3_list_matches_phase_group — phase + group_label additiv projizieren

- **Type:** data · **Size:** S · **Context:** supabase/migrations · **Agent:** coder(data) · **Dependencies:** W3-T05 · **Files:** supabase/migrations/20261321000000_w3_list_matches_phase_group.sql

### Acceptance (Given/When/Then)
Given W3-T05 ROT / When CREATE OR REPLACE tournament_list_matches (SETOF, Basis 20261212000000) um 'phase' m.phase + 'group_label' m.group_label / Then W3-T05 GRÜN, GRANT EXECUTE authenticated, kein Drop/Index/RLS-Change

### Notes
Timestamp 20261321000000 (nach W4 reserviert 20261317-20261319; hier wellenübergreifend koordiniert). group_label existiert seit 20261201000010. Byte-gleich plus 2 Keys.

---

## W3-T07: security-checker: Migration w3_list_matches Grant/RLS-Review

- **Type:** security · **Size:** S · **Context:** supabase/migrations · **Agent:** security-checker · **Dependencies:** W3-T06 · **Files:** supabase/migrations/20261321000000_w3_list_matches_phase_group.sql

### Acceptance (Given/When/Then)
Given re-stated RPC / When Grant/RLS gegen Vorgänger diffen / Then GRANT EXECUTE unverändert, keine Privilege-Erweiterung, RLS-Lage byte-kompatibel

### Notes
Pflicht-Review nach RPC-Re-Aussage.

---

## W3-T08: data: TournamentMatchRef.groupLabel-Feld (optional) + ==/hashCode + Parse

- **Type:** data · **Size:** S · **Context:** tournament/ (Port + data-Adapter) · **Agent:** coder(data) · **Dependencies:** W3-T06 · **Files:** packages/kubb_domain/lib/src/ports/tournament_remote.dart, lib/features/tournament/data/tournament_models.dart

### Acceptance (Given/When/Then)
Given W3-T06 liefert group_label / When 'String? groupLabel' (default null) additiv + tournamentMatchRefFromRow:486-516 liest row['group_label'] null-safe + ==/hashCode erweitert / Then alte Fakes/CDC-Rows brechen nicht

### Notes
dep T06 (RPC muss Feld liefern). Muster identisch zu phase/stageNodeId.

---

## W3-T09: domain: TournamentDetailHeader.qualifiersPerGroup + isTeam Getter

- **Type:** domain · **Size:** S · **Context:** tournament/ (packages/kubb_domain pure Dart) · **Agent:** coder(domain) · **Dependencies:** - · **Files:** packages/kubb_domain/lib/src/ports/tournament_remote.dart

### Acceptance (Given/When/Then)
Given TournamentDetailHeader:469-535 / When Getter qualifiersPerGroup (setup['pool_phase_config']['qualifiers_per_group'], Default 2) + isTeam (teamSize>1) / Then KEIN Konstruktor-Breaking-Change, Getter liefern korrekte Werte

### Notes
Nur berechnete Getter, keine Wire-Änderung. Parallel zu T08 möglich (selbe Datei tournament_remote.dart — sequenzieren falls Edit-Konflikt: depends_on T08).

---

## W3-T10: frontend: standingsProvider auf standingsChainFor umstellen

- **Type:** frontend · **Size:** S · **Context:** tournament/ application · **Agent:** coder(frontend) · **Dependencies:** W3-T04 · **Files:** lib/features/tournament/application/tournament_match_providers.dart

### Acceptance (Given/When/Then)
Given W3-T04 / When tournamentStandingsProvider:184-189 const TiebreakerChain durch standingsChainFor(detail.format, detail.tiebreakerOrder) ersetzt (Fallback EKC/roundRobin wenn detail==null) / Then Verhalten bei detail==null exakt alt, _resultFromMatch unangetastet

### Notes
PITFALL: nur die TiebreakerChain-Zeile, per-set-wins-Synthese nicht anfassen. Fallback muss altes EKC-Verhalten liefern.

---

## W3-T11: frontend: TournamentPoolStandingsView aus Pool-Screen extrahieren

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** - · **Files:** lib/features/tournament/presentation/tournament_pool_standings_screen.dart

### Acceptance (Given/When/Then)
Given Pool-Screen mit Scaffold/AppBar / When TournamentPoolStandingsView (Body ohne Scaffold, qualifiersPerGroup-Param) extrahiert analog TournamentStandingsView / Then View einbettbar, bestehender Screen unverändert nutzbar

### Notes
Parallel zu T12 (andere Datei).

---

## W3-T12: frontend: TournamentBracketView aus Bracket-Screen extrahieren

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** - · **Files:** lib/features/tournament/presentation/tournament_bracket_screen.dart

### Acceptance (Given/When/Then)
Given Bracket-Screen / When TournamentBracketView (async.when->BracketCanvas, nameFor/consolationName) ohne Scaffold/AppBar extrahiert / Then View einbettbar in Übersicht-Reiter

### Notes
Parallel zu T11.

---

## W3-T13: frontend: _MatchListBody Gruppen-Label-Gruppierung + 'Gruppe A · Runde 1'-Header + ARB

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W3-T08 · **Files:** lib/features/tournament/presentation/tournament_match_list_screen.dart, lib/l10n/app_de.arb

### Acceptance (Given/When/Then)
Given Matches mit group_label / When _MatchListBody:103-162 primär nach group_label dann roundNumber gruppiert, Header 'Gruppe A · Runde 1' bei Gruppenphase sonst 'Runde N' / Then ARB<->generated synchron, ohne group_label fällt still auf Rundengruppierung zurück

### Notes
dep T08 (groupLabel am Ref). Kein Crash bei null group_label.

---

## W3-T14: frontend: Standings-_HeaderRow Einzel/Team-Bezeichnung (isTeam) + ARB

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W3-T09 · **Files:** lib/features/tournament/presentation/tournament_standings_screen.dart, lib/l10n/app_de.arb

### Acceptance (Given/When/Then)
Given header.isTeam / When _HeaderRow:188-225 'Spieler'(tournamentStandingsPlayer) durch Einzel/Team-Variante (neuer ARB tournamentStandingsTeam) gespeist aus isTeam / Then Team-Turnier zeigt 'Team', Einzel 'Spieler'

### Notes
dep T09 (isTeam-Getter). ACHTUNG: tournament_standings_screen.dart auch von W1-T14 angefasst — wellenübergreifend sequenzieren (W1 vor W3).

---

## W3-T15: frontend: Live-Screen Rangliste-Reiter flach<->gruppiert Format-Switch

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W3-T11, W3-T14 · **Files:** lib/features/tournament/presentation/tournament_live_screen.dart

### Acceptance (Given/When/Then)
Given tournamentDetailProvider.format / When Rangliste-Reiter bei Gruppenphase TournamentPoolStandingsView sonst TournamentStandingsView / Then gruppierte Tabelle (_GroupTile findbar) bei Gruppenphase, sonst Flachliste

### Notes
dep T11 (View) + T14 (Header). tournament_live_screen.dart auch W1-T14 — sequenzieren.

---

## W3-T16: frontend: Live-Screen Übersicht-Reiter KO-Phase -> TournamentBracketView

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W3-T12, W3-T13, W3-T15 · **Files:** lib/features/tournament/presentation/tournament_live_screen.dart

### Acceptance (Given/When/Then)
Given status=live + KO-Matches / When Übersicht-Reiter TournamentBracketView statt TournamentMatchListView / Then BracketCanvas sichtbar bei KO-Phase, sonst MatchListBody mit Gruppen-Label

### Notes
dep T12+T13+T15 (selbe Datei wie T15, sequenziell). Konsumiert alle Vorgänger.

---

## W3-T17: frontend: InboxBellAction auf Live-Sicht + Profil/Achievements/Freunde/Team-Listen/Meine-Trainings

- **Type:** frontend · **Size:** M · **Context:** tournament/ + Nicht-Eingabe-Screens · **Agent:** coder(frontend) · **Dependencies:** - · **Files:** lib/features/tournament/presentation/tournament_live_screen.dart, lib/features/*/presentation/{profile,achievements,friends,team_list,my_trainings}_screen.dart

### Acceptance (Given/When/Then)
Given Nicht-Eingabe-Screens / When InboxBellAction in AppBar-actions eingehängt (1-3 LOC je Screen) / Then Bell findbar (byTooltip 'Postfach') auf Live/Profil/Achievements/Freunde/Team-Listen/Meine-Trainings, NICHT auf Score-Eingabe/Wizard

### Notes
Unabhängig, jederzeit lauffähig. PITFALL Spec §4: KEINE Bell auf Eingabe/Config/Wizard. >5 Dateien — ggf. splitten falls LOC/Datei-Limit; hier je 1-3 LOC, Sammeltask vertretbar.

---

## W3-T18: tests: flutter widget Reiter config-adaptiv (5.1/5.2/5.4/5.6) + Bell-Präsenz/Absenz (5.5)

- **Type:** tests · **Size:** M · **Context:** tournament/ presentation · **Agent:** tester · **Dependencies:** W3-T16, W3-T17 · **Files:** test/features/tournament/presentation/live_views_config_test.dart

### Acceptance (Given/When/Then)
Given gefakte Provider / When Live-Screen mit Gruppen-/Team-/KO-Config gepumpt / Then gruppierte Tabelle (5.1), 'Gruppe A · Runde 1' (5.2), Team-Header (5.4), BracketCanvas bei KO (5.6), Bell auf Live/Nicht-Eingabe findbar nicht auf Eingabe (5.5)

### Notes
Welle-Abschluss-Test. depends_on auf Live-Screen-Endpunkte.

---

# W4 — Cockpit-Steuerung

Macht das Cockpit zur einzigen Steuerzentrale. Net-new sind nur ein additiver
Timer-RPC und ein Such-RPC. Detail-Entkernung (W4-T25) ZULETZT.

> **Reconciliation A:** `pitch_number` kommt aus W0-T05/T08; W4 konsumiert
> `ref.pitchNumber` direkt. Die duplizierten Pitch-Tasks **W4-T01, W4-T02, W4-T03**
> sind GESTRICHEN (klar markiert, IDs erhalten). W4-T04 (Pitch-Badge) bleibt und
> hängt auf W0-T08 statt auf W4-T03.

---

## W4-T01: pgTAP: tournament_list_matches projiziert pitch_number (TDD: vor T02)  — GESTRICHEN

> **GESTRICHEN — dedupliziert nach W0. Begründung: das echte pitch_number landet bereits in W0-T04 (pgTAP) / W0-T05 (Projektion match_get + list). Dieser list-Pitch-Test ist redundant.**

_Ursprüngliche Planung (zur Nachvollziehbarkeit):_ Type tests · Size S · Agent tester · Files `supabase/tests/list_matches_pitch_number_test.sql`

---

## W4-T02: Migration: tournament_list_matches additiv um pitch_number (falls nicht via W0)  — GESTRICHEN

> **GESTRICHEN — dedupliziert nach W0. Begründung: W0-T05 projiziert pitch_number bereits in tournament_match_get UND tournament_list_matches. Eine zweite list-Migration würde ein Doppel erzeugen — nur EINE Projektion darf existieren.**

_Ursprüngliche Planung (zur Nachvollziehbarkeit):_ Type data · Size S · Agent coder(data) · Files `supabase/migrations/20261322000000_w4_list_matches_pitch.sql`

---

## W4-T03: TournamentMatchRef.pitchNumber Feld + beide Parser + ==/hashCode (falls nicht via W0)  — GESTRICHEN

> **GESTRICHEN — dedupliziert nach W0. Begründung: W0-T08 legt TournamentMatchRef.pitchNumber inkl. beider Parser (fromRow + fromCdcRow) und ==/hashCode an. Ein zweites Feld würde kollidieren — nur EIN pitchNumber-Feld existiert je.**

_Ursprüngliche Planung (zur Nachvollziehbarkeit):_ Type domain · Size S · Agent coder(domain) · Files `packages/kubb_domain/lib/src/ports/tournament_remote.dart, lib/features/tournament/data/tournament_models.dart`

---

## W4-T04: frontend: Pitch-Badge in _MatchRow des Cockpit-Steuerungs-Screens

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W0-T08 · **Files:** lib/features/tournament/presentation/organizer_dashboard_detail_screen.dart, test/features/tournament/presentation/cockpit_pitch_badge_test.dart

### Acceptance (Given/When/Then)
Given match.pitchNumber gesetzt / When _MatchRow Pitch-Badge rendert / Then Badge zeigt Pitch-Nummer; bei null kein Badge

### Notes
RECONCILIATION A: depends_on auf W0-T08 (statt gestrichenem W4-T03). pitch_number kommt aus W0; W4 konsumiert ref.pitchNumber direkt. dep pitchNumber-Fundament (W0-T08 oder W4-T03). HARTE Cross-Wave-Dep: pitch_number-Projektion+Parser VOR Pitch-Badge-UI.

---

## W4-T05: tests: direct-score CTA dispatcht submitDirect, kein Reason-Pflichtfeld (TDD: vor T06)

- **Type:** tests · **Size:** S · **Context:** tournament/ application · **Agent:** tester · **Dependencies:** - · **Files:** test/features/tournament/application/override_direct_test.dart

### Acceptance (Given/When/Then)
Given Direct-Submit / When submitDirect(matchId, setsToWin) ohne reason / Then dispatcht ohne isReasonValid-Precondition, wiederverwendet toSetScores/isScoreDecisive (initial ROT)

### Notes
TDD-Anker für W4-T06.

---

## W4-T06: reason-freier submitDirect-Pfad im TournamentOverrideController

- **Type:** domain · **Size:** S · **Context:** tournament/ application · **Agent:** coder(domain/app) · **Dependencies:** W0-T10, W4-T05 · **Files:** lib/features/tournament/application/tournament_override_controller.dart

### Acceptance (Given/When/Then)
Given W4-T05 ROT + Override-Gate eingefroren (W0-T10) / When submitDirect(matchId, setsToWin) ohne isReasonValid()-Precondition (reason optional/leer) / Then W4-T05 GRÜN, toSetScores/isScoreDecisive wiederverwendet

### Notes
HARTE Cross-Wave-Dep auf W0-T10: Override-Gate-Freeze MUSS stehen, bevor Direct-Score den Schreibweg generalisiert. ADR-0044 Override-Generalisierung. Server-RPC unverändert (akzeptiert reason 1..500, leer ok).

---

## W4-T07: frontend: Override-Screen Direct-Modus (Reason ausblenden + 'Punkte eintragen'-Titel via Flag)

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W4-T06 · **Files:** lib/features/tournament/presentation/tournament_override_screen.dart

### Acceptance (Given/When/Then)
Given Modus-Flag direct / When Editor wiederverwendet, Reason-Feld ausgeblendet, Titel 'Punkte eintragen', kein 'strittig'-Kontext / Then direct-Modus rendert ohne Reason-Pflichtfeld

### Notes
dep T06 (Submit-Pfad). Bestehender Override-Flow im Conflict/Detail-Pfad unberührt.

---

## W4-T08: frontend: 'Punkte eintragen'-CTA in _MatchRow -> Direct-Editor-Route + WidgetTest

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W4-T04, W4-T07 · **Files:** lib/features/tournament/presentation/organizer_dashboard_detail_screen.dart, test/features/tournament/presentation/cockpit_direct_score_test.dart

### Acceptance (Given/When/Then)
Given _MatchRow / When 'Punkte eintragen'-CTA neben Override/Forfeit getappt / Then Direct-Editor-Route geöffnet, dispatcht submitDirect, kein Reason-Pflichtfeld

### Notes
dep T04 (selbe Datei _MatchRow) + T07 (direct-Modus). Sequenziell wegen Edit-Konflikt.

---

## W4-T09: pgTAP: tournament_adjust_round_time (delta+/-, clamp>=0, 42501, terminal unberührt) (TDD: vor T10)

- **Type:** tests · **Size:** M · **Context:** supabase/tests · **Agent:** tester · **Dependencies:** - · **Files:** supabase/tests/adjust_round_time_test.sql

### Acceptance (Given/When/Then)
Given laufende Schedule-Zeile / When tournament_adjust_round_time mit positivem/negativem Delta, Nicht-Manager, terminal/completed / Then match_seconds=greatest(0,..) geclampt, ends_at verschoben, 42501 für Nicht-Manager, terminal unberührt, NUR schedule geschrieben (initial ROT)

### Notes
TDD-Anker für W4-T10.

---

## W4-T10: Migration: tournament_adjust_round_time RPC (additiv, gate+lock+clamp, nur schedule)

- **Type:** data · **Size:** M · **Context:** supabase/migrations · **Agent:** coder(data) · **Dependencies:** W4-T09 · **Files:** supabase/migrations/20261323000000_tournament_adjust_round_time.sql

### Acceptance (Given/When/Then)
Given W4-T09 ROT / When NEUE RPC: pg_advisory_xact_lock + tournament_caller_can_manage(42501) + UPDATE tournament_round_schedule SET match_seconds=greatest(0,match_seconds+delta), ends_at=ends_at+make_interval WHERE status IN ('call','running','awaiting_results'); REVOKE public+anon, GRANT authenticated / Then W4-T09 GRÜN

### Notes
ADR-0045 Timer-extend additiv. PITFALL: fasst tournament_matches NIE an. Timestamp 20261323000000 (Briefing 20261317000000 kollidiert mit W0-T05 — bewusst umnummeriert).

---

## W4-T11: security-checker: adjust_round_time Grant/Gate/RLS-Review

- **Type:** security · **Size:** S · **Context:** supabase/migrations · **Agent:** security-checker · **Dependencies:** W4-T10 · **Files:** supabase/migrations/20261323000000_tournament_adjust_round_time.sql

### Acceptance (Given/When/Then)
Given neue RPC / When Gate (caller_can_manage), REVOKE public+anon, GRANT authenticated, SECURITY-Kontext geprüft / Then fail-closed, kein anon-Zugriff, Gate korrekt verdrahtet

### Notes
Pflicht-Review nach neuer RPC mit Grant. Gate ist Security-Boundary.

---

## W4-T12: Port+Adapter: adjustRoundTime über tournament_adjust_round_time RPC

- **Type:** data · **Size:** S · **Context:** tournament/ (Port + data-Adapter) · **Agent:** coder(data) · **Dependencies:** W4-T10 · **Files:** packages/kubb_domain/lib/src/ports/tournament_remote.dart, lib/features/tournament/data/tournament_repository.dart

### Acceptance (Given/When/Then)
Given RPC existiert / When adjustRoundTime(TournamentId, int deltaSeconds) am Port + Adapter-Methode / Then RPC korrekt aufgerufen

### Notes
Port VOR Actions VOR UI (harte Reihenfolge). tournament_remote.dart auch von W4-T03 — sequenzieren falls Edit-Konflikt.

---

## W4-T13: app: TournamentActions.extendRound/shortenRound (CDC-push, kein schedule-invalidate)

- **Type:** domain · **Size:** S · **Context:** tournament/ application · **Agent:** coder(app) · **Dependencies:** W4-T12 · **Files:** lib/features/tournament/application/tournament_providers.dart

### Acceptance (Given/When/Then)
Given Port adjustRoundTime / When extendRound/shortenRound delegieren an Port / Then Schedule-Änderung pusht via CDC, KEIN ref.invalidate(tournamentRoundScheduleProvider)

### Notes
PITFALL: extend muss wie B2s via CDC pushen, NICHT die Detail-Fold reseten (Fold-Mechanik darf nicht regredieren).

---

## W4-T14: tests: ControlBar Status + extend/shorten-Dispatch (+/-, Zahleneingabe) (TDD: vor T15/T16)

- **Type:** tests · **Size:** M · **Context:** tournament/ presentation · **Agent:** tester · **Dependencies:** - · **Files:** test/features/tournament/presentation/schedule_control_bar_test.dart

### Acceptance (Given/When/Then)
Given TournamentRoundScheduleRef / When ControlBar gerendert + +/- und Direkteingabe getappt / Then zeigt 'Runde N'/'Pause' + skew-korrekte Restzeit, feuert extend/shorten-Callback (initial ROT)

### Notes
TDD-Anker für W4-T15+T16.

---

## W4-T15: frontend: ScheduleControlBar Statusanzeige Runde N/Pause + Restzeit

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W4-T13, W4-T14 · **Files:** lib/features/tournament/presentation/widgets/schedule_control_bar.dart

### Acceptance (Given/When/Then)
Given W4-T14 ROT / When Statusanzeige (Runde N / Pause + Restzeit) unter Primär-Toggle, konsumiert TournamentRoundScheduleRef (status/matchSeconds/startsAt/endsAt/pausedAt) skew-korrekt / Then Status-Teil von W4-T14 GRÜN

### Notes
Restzeit-Formel in round_schedule.dart/match_timer.dart bleibt konsistent (CDC pusht gratis).

---

## W4-T16: frontend: ScheduleControlBar +/- Schritt-Buttons + Direkt-Zahleneingabe -> adjust callback

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W4-T15 · **Files:** lib/features/tournament/presentation/widgets/schedule_control_bar.dart

### Acceptance (Given/When/Then)
Given W4-T14 ROT / When +/- Buttons + Direkteingabe extend/shorten-Callback feuern / Then W4-T14 vollständig GRÜN

### Notes
dep T15 (selbe Datei). Verdrahtet an extendRound/shortenRound-Callbacks.

---

## W4-T17: pgTAP: search_checkin_targets Scope (fremd/Nicht-Manager leer, Phase-Filter, ILIKE) (TDD: vor T18)

- **Type:** tests · **Size:** M · **Context:** supabase/tests · **Agent:** tester · **Dependencies:** - · **Files:** supabase/tests/search_checkin_targets_test.sql

### Acceptance (Given/When/Then)
Given confirmed Participants/Teams / When tournament_search_checkin_targets(query) / Then nur Check-in-Phase (registration_open/closed/live) UND eigener Veranstalter (caller_can_manage), fremde/Nicht-Manager leer, ILIKE-Treffer korrekt (initial ROT)

### Notes
TDD-Anker für W4-T18.

---

## W4-T18: Migration: tournament_search_checkin_targets RPC + Trigram-Index

- **Type:** data · **Size:** M · **Context:** supabase/migrations · **Agent:** coder(data) · **Dependencies:** W4-T17 · **Files:** supabase/migrations/20261324000000_tournament_search_checkin_targets.sql

### Acceptance (Given/When/Then)
Given W4-T17 ROT / When NEUE SECURITY DEFINER RPC: ILIKE über confirmed Participants/Teams, status IN ('registration_open','registration_closed','live') UND caller_can_manage(t.id), RETURNS jsonb(participant_id,tournament_id,display_name,checked_in_at), CREATE INDEX IF NOT EXISTS Trigram auf user_profiles.nickname/teams.display_name / Then W4-T17 GRÜN

### Notes
ADR-Scope. Timestamp 20261324000000. SECURITY DEFINER -> security-checker Pflicht (W4-T19).

---

## W4-T19: security-checker: search_checkin_targets RPC + Index Review (SECURITY DEFINER)

- **Type:** security · **Size:** M · **Context:** supabase/migrations · **Agent:** security-checker · **Dependencies:** W4-T18 · **Files:** supabase/migrations/20261324000000_tournament_search_checkin_targets.sql

### Acceptance (Given/When/Then)
Given SECURITY DEFINER RPC / When search_path-Pinning, Scope-Gate (caller_can_manage + Phase-Filter), kein Daten-Leak ausserhalb eigener Turniere, GRANT-Lage geprüft / Then fail-closed, kein Cross-Tenant-Leak, search_path sicher

### Notes
KRITISCH: SECURITY DEFINER + neuer Index erfordert vollen Security-Review (search_path-Injection, Scope-Bypass).

---

## W4-T20: Port+Adapter+CheckinSearchHit-Wire für search_checkin_targets

- **Type:** data · **Size:** S · **Context:** tournament/ (Port + data-Adapter) · **Agent:** coder(data) · **Dependencies:** W4-T18 · **Files:** packages/kubb_domain/lib/src/ports/tournament_remote.dart, lib/features/tournament/data/tournament_models.dart

### Acceptance (Given/When/Then)
Given RPC liefert jsonb / When searchCheckinTargets(query)->List<CheckinSearchHit> am Port + CheckinSearchHit(participantId,tournamentId,tournamentName,displayName,checkedInAt)-Wire-Parsing / Then Treffer korrekt dekodiert

### Notes
Neuer DTO im Port-File. Port VOR Screen.

---

## W4-T21: tests: cross_checkin_screen Treffer-Render + checkin-Dispatch (TDD: vor T22)

- **Type:** tests · **Size:** M · **Context:** tournament/ presentation · **Agent:** tester · **Dependencies:** - · **Files:** test/features/tournament/presentation/cross_checkin_screen_test.dart

### Acceptance (Given/When/Then)
Given gefakte searchCheckinTargets-Treffer / When Suchfeld befüllt + Check-in-Button getappt / Then Trefferliste rendert, checkinParticipant dispatcht (initial ROT)

### Notes
TDD-Anker für W4-T22.

---

## W4-T22: frontend: cross_checkin_screen Suchfeld + Trefferliste + Check-in-Button

- **Type:** frontend · **Size:** L · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W4-T20, W4-T21 · **Files:** lib/features/tournament/presentation/cross_checkin_screen.dart, lib/features/tournament/presentation/tournament_routes.dart

### Acceptance (Given/When/Then)
Given W4-T21 ROT / When Suchfeld + Trefferliste (Team/Spieler->Turnier-Anmeldung) + Check-in-Button (nutzt checkinParticipant) + Route crossCheckin / Then W4-T21 GRÜN

### Notes
dep T20 (Port). L-Task — falls >100 LOC/3 Dateien Senior-Limit reisst, in Such-UI + Trefferliste splitten. Erreichbar aus organizer_dashboard_screen (W4-T23).

---

## W4-T23: frontend: Cockpit-Übersicht Einstiegspunkt + Route in Cross-Check-in-Screen

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W4-T22 · **Files:** lib/features/tournament/presentation/organizer_dashboard_screen.dart

### Acceptance (Given/When/Then)
Given Cross-Check-in-Screen + Route existieren / When Button/Tab in Cockpit-Übersicht / Then Navigation zu cross_checkin_screen funktioniert

### Notes
dep T22 (Screen+Route).

---

## W4-T24: frontend: Per-Tournament-Check-in-Sektion in Cockpit-Steuerungs-Screen migrieren (VOR Detail-Entkernung)

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W4-T23 · **Files:** lib/features/tournament/presentation/organizer_dashboard_detail_screen.dart

### Acceptance (Given/When/Then)
Given Check-in-Counter+Toggle bisher im Detail-Screen / When Per-Tournament-Check-in-Sektion ins Cockpit-Steuerungs-Screen migriert / Then Check-in im Cockpit erreichbar, bevor Detail entkernt wird

### Notes
HARTE Reihenfolge: Check-in+Lifecycle+Moderation MUSS vollständig im Cockpit erreichbar sein, bevor W4-T25 den Detail entkernt (sonst Funktionsverlust).

---

## W4-T25: frontend: Detail-Screen entkernen — canManage-Blöcke entfernen, '→ Dashboard'-Button

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W4-T08, W4-T16, W4-T23, W4-T24 · **Files:** lib/features/tournament/presentation/tournament_detail_screen.dart

### Acceptance (Given/When/Then)
Given alle Veranstalter-Funktionen im Cockpit erreichbar / When canManage-Blöcke (Check-in-Counter+Toggle, TournamentEscalationPanel, _Actions-Lifecycle) entfernt, durch '→ Dashboard'-Button (TournamentRoutes.dashboardDetail) ersetzt / Then negativer Existenz-Test: kein TournamentEscalationPanel/Lifecycle/Check-in im Detail, nur '→ Dashboard'

### Notes
ZULETZT in W4 (harte Reihenfolge). dep auf ALLE Cockpit-Migrationen (Direct-Score T08, Timer T16, Cross-Check-in T23, Per-Tournament-Check-in T24). PITFALL: kein Funktionsverlust.

---

# W5 — Typ-Graph-Editor verdrahten (Ebene 2 UI-Wiring)

Reines UI-Wiring: Domain, Validierung, Canvas, Summary und Engine bleiben
unverändert. Body-Toggle ist Voraussetzung für Route-Mount und Wizard-Host;
Editor-Parität (nur ein Provider, eine Serialisierung) ist der Wächter.

---

## W5-T01: tests: Widgettests Toggle-Gating (schmal: kein Toggle; breit+desktop: Toggle+Canvas) (Test-First)

- **Type:** tests · **Size:** S · **Context:** tournament/ presentation · **Agent:** tester · **Dependencies:** - · **Files:** test/features/tournament/presentation/stage_type_graph_builder_screen_test.dart

### Acceptance (Given/When/Then)
Given schmaler Viewport / When Body gepumpt / Then kein SegmentedButton, nur Form; breiter Desktop (debugDefaultTargetPlatformOverride=linux, width>=720) -> Toggle sichtbar + StageTypeGraphCanvas mountbar (find.byType) (initial ROT)

### Notes
TDD-Ausnahme erlaubt: Toggle-Gating-Test VOR T02 (Senior-Default Test-First). Bestehende canvas_test bleibt unverändert grün (Parity-Anker).

---

## W5-T02: frontend: StageTypeGraphBuilderBody auf form/canvas-Toggle + isCanvasAvailable-Gating umbauen

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W5-T01 · **Files:** lib/features/tournament/presentation/stage_type_graph_builder_screen.dart

### Acceptance (Given/When/Then)
Given W5-T01 ROT / When Body von ConsumerWidget(Z59-101) in StatefulWidget mit enum _EditorView{form,canvas}, isCanvasAvailable(MediaQuery.sizeOf.width)-Gating, effectiveView-Clamp, SegmentedButton (l.stageGraphViewForm/-Canvas), Canvas-Mount const StageTypeGraphCanvas(), Form in _StageTypeGraphFormView, embedded-Flag (default false) / Then W5-T01 GRÜN

### Notes
1:1-Muster von _StageGraphBuilderBodyState (Ebene-1, stage_graph_builder_screen.dart:85-152). PITFALL: Canvas+Form mutieren NUR stageTypeGraphBuilderProvider (Parity-Test ist Wächter), kein zweiter State. Ebene-1-Toggle nur als Muster gelesen, unverändert.

---

## W5-T03: frontend: TournamentRoutes.stageTypeGraph-Konstante (statischer Prefix + Doc)

- **Type:** frontend · **Size:** S · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** - · **Files:** lib/features/tournament/presentation/tournament_routes.dart

### Acceptance (Given/When/Then)
Given dynamische /tournament/:id-Route / When static const stageTypeGraph = '/tournament/stage-type-graph' (statischer Prefix gewinnt vor dynamisch) + Doc-Kommentar im stageGraph-Stil / Then Konstante existiert

### Notes
VOR T04 (Router-Eintrag braucht Konstante).

---

## W5-T04: frontend: GoRoute für StageTypeGraphBuilderScreen in router.dart registrieren

- **Type:** frontend · **Size:** S · **Context:** app/ (Routen-Eintrag) · **Agent:** coder(frontend) · **Dependencies:** W5-T02, W5-T03 · **Files:** lib/app/router.dart

### Acceptance (Given/When/Then)
Given Body mit Toggle (T02) + Route-Konstante (T03) / When GoRoute(path:TournamentRoutes.stageTypeGraph, builder: const StageTypeGraphBuilderScreen()) nach stageGraph-Eintrag(Z508-511), im selben Shell-Branch, über detail/:id / Then Route mountet Screen

### Notes
dep T02 (Screen zeigt Body mit Toggle) + T03 (Konstante). PITFALL: über der dynamischen detail/:id-Route platzieren (statischer Prefix gewinnt).

---

## W5-T05: frontend: Wizard-Write-Pfad — 'Stufen-Typ modellieren'-Host + toConfig() in node.config mergen

- **Type:** frontend · **Size:** M · **Context:** tournament/ presentation · **Agent:** coder(frontend) · **Dependencies:** W5-T02 · **Files:** lib/features/tournament/presentation/tournament_setup_wizard.dart

### Acceptance (Given/When/Then)
Given StageNode im Ebene-1-Builder / When 'Stufen-Typ modellieren'-Affordance StageTypeGraphBuilderBody(embedded:true) hostet, onSave -> toConfig() via stageGraphBuilderProvider.notifier.updateNode (gemergtes config-Map) in StageNode.config['type_graph'], Vorbelegung aus node.config['type_graph'] via initialGraph / Then Write-Pfad produktiv

### Notes
dep T02 (embedded-Body). KERN: macht config['type_graph'] produktiv. PITFALL: exakt toConfig()-Form schreiben (Summary-Reader wizard:3079 + Materializer-Migrationen lesen sie bereits; falsche Form bricht Round-Trip). Wizard-Step-Liste _visibleSteps + classic-Pfad nicht brechen — Affordance hängt an StageNode im stageGraph-Modus.

---

## W5-T06: tests: Widgettest Write-Pfad (onSave schreibt config['type_graph'], Summary-Reader liefert Zeilen) + Route-Reachability

- **Type:** tests · **Size:** M · **Context:** tournament/ presentation · **Agent:** tester · **Dependencies:** W5-T04, W5-T05 · **Files:** test/features/tournament/presentation/stage_type_graph_write_path_test.dart

### Acceptance (Given/When/Then)
Given Wizard mit StageNode / When 'Stufen-Typ modellieren' geöffnet, onSave gedrückt / Then Ziel-StageNode.config['type_graph'] enthält Map UND stageTypeGraphSummaryRows liefert >0 Zeilen; Route-Test pusht stageTypeGraph und findet StageTypeGraphBuilderScreen

### Notes
dep T04 (Route) + T05 (Write-Pfad). Parity-Test stage_type_graph_editor_parity_test bleibt unverändert grün (Regressions-Wächter).

---

## W5-T07: Quality-Gate W5: flutter analyze + flutter test + dart analyze kubb_domain clean

- **Type:** tests · **Size:** S · **Context:** tournament/ + packages/kubb_domain · **Agent:** tester · **Dependencies:** W5-T06 · **Files:** (Verifikation, keine neue Datei)

### Acceptance (Given/When/Then)
Given alle W5-Tasks / When flutter analyze + flutter test + dart analyze im Domain-Paket / Then analyze 0 issues, alle Tests grün, Domain-Paket unberührt clean, Parity-Test grün

### Notes
Welle-Abschluss. Domain-Package wurde NICHT angefasst (kein Flutter-Import-Risiko).

---
