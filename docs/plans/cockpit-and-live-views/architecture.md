# Architektur — Cockpit, Live-Views, Match-Entry, Realtime & Typ-Graph-Editor

**Status:** Architektur-Entwurf, eine Architect-Runde pro Welle (W0–W5).
**Bezug:** Forward-Specs unter `docs/specs/` (Realtime-Sync-Fixes, Live-Views+Inbox, Match-Entry+Home-Tile, Organizer-Cockpit), ADR-0029 (Battery-Invariante), ADR-0041 (Push-Freshness, importiert).
**Level:** senior (TDD-first, additive Migrationen, pgTAP für jede RPC-Berührung, security-checker bei Grant/RLS/SECURITY DEFINER).

---

## 0. Kontext

Sechs Wellen ziehen die nächste Tournament-Iteration durch: vom Spec-Import über
Realtime-Korrektheit, Match-Entry-Quick-Wins und config-adaptive Live-Views bis zum
Veranstalter-Cockpit als einziger Steuerzentrale und dem produktiven Wiring des
fertig gebauten Typ-Graph-Editors. Alles bleibt im Bounded Context `tournament/`
(hexagonal-light, ADR-0002), der Realtime-Transport in `core/data/realtime/` bleibt
transport-agnostisch, das Domain-Package `packages/kubb_domain/` bleibt Flutter-frei.

Leitplanken über alle Wellen:

- **Additiv**, kein destruktiver Schema-Drop. Migrationen sind `CREATE OR REPLACE`
  mit re-stated Bodies plus der neuen Projektion; alte App-Versionen schreiben weiter.
- Wire-Felder werden **null-tolerant** dekodiert (`_asIntOrNull`, nicht `_asInt`),
  damit alte CDC-Rows und Fakes nicht crashen.
- Migrations-Timestamps sind wellenübergreifend koordiniert (höchste bestehende ist
  `20261316000000`): W0 belegt `20261317000000`, W3 `20261321000000`, W4
  `20261322000000`–`20261324000000`.

### Stale-Briefing-Korrekturen (Stand main)

Zwei Annahmen im ursprünglichen Auftrag sind überholt — der Code ist schon weiter:

1. **`pitch_number`-Spalte existiert bereits** seit `20260525000001:67` und wird von
   `_tournament_assign_pitches` / `_tournament_assign_pitches_from_stage_node` beim
   Pairing gespeist. Wave 0 macht deshalb **nur Projektion + Wire**, keine
   Schema-Migration.
2. **Das Override-Gate ist bereits `tournament_caller_can_administer`** (seit
   `20261281000000`, P2-S-Gate-Split, ADR-0032; im latest `20261314000000`). Die im
   Briefing genannte creator-only-Stelle (`20261250000000:60`) ist superseded.
   `tournament_caller_can_manage` ist nur ein deprecated Alias und wird vom Override
   nicht mehr aufgerufen. W0-T10 **verifiziert und friert das Gate per pgTAP ein**,
   es baut es nicht.

### Abgenommene Owner-Entscheide

| # | Entscheid | Folge |
|---|---|---|
| **1** | Override-Gate auf `caller_can_administer` (Club-Admin, nicht creator-only) | Faktisch bereits erfüllt (siehe Korrektur 2). W0-T10 friert es nur per pgTAP ein. |
| **2** | Echtes `pitch_number` bis in den Client durchreichen (Projektion in `match_get`/`list` + `TournamentMatchRef.pitchNumber`) | W0 liefert das Feld als saubere einzige Quelle. W4 konsumiert `ref.pitchNumber` direkt; die duplizierten W4-Pitch-Tasks entfallen (siehe §5, Reconciliation). |
| **3** | Direkter Punkte-Eintrag generalisiert den bestehenden Override-Schreibweg (kein eigener RPC) | W4 ruft `tournament_organizer_override` begründungsfrei (reason optional). Audit bleibt erhalten. ADR-0044. |

---

## 1. Wave 0 — Spec-Import + pitch_number-Fundament

### Übersicht
Importiert die 4 Forward-Specs und den Push-Freshness-ADR (umnummeriert von
origin-0035 auf die nächste freie 0041) von `origin/docs/schoch-buchholz-spec` auf
main, exponiert das bereits existierende `pitch_number`-Feld bis in den Client
(RPC-Projektion + Wire-Model + Banner-Speisung) und verfestigt das Override-Gate per
pgTAP. Reines additives Fundament.

### Bounded Contexts
`tournament/` (hexagonal-light): Wire-Decoder in
`lib/features/tournament/data/tournament_models.dart`, Port-Type `TournamentMatchRef`
in `packages/kubb_domain/lib/src/ports/tournament_remote.dart` (pure Dart),
Presentation in `pitch_call_banner.dart`. Server-Layer (`supabase/migrations` +
`supabase/tests`) liegt quer zu `tournament/`. ADR/Spec-Dateien sind reine `docs/`.
`pitch_number` bleibt ein skalares Wire-Feld am Ref — kein Cross-Context-Join.

### Komponenten
- `docs/adr/0041-push-critical-freshness-and-delta-catchup.md` — NEU, Import von
  origin-0035, umnummeriert auf 0041. main-0035 (`vorrunde-ranking-from-stage-type`)
  bleibt unangetastet.
- `docs/specs/{realtime-sync-fixes,live-views-and-inbox,match-entry-and-home-tile,organizer-cockpit-dashboard}-spec.md`
  — NEU, 1:1-Import. Nur die Realtime-Spec trägt 0035-Cross-Refs (9 Vorkommen),
  die auf 0041 mitgezogen werden.
- `packages/kubb_domain/lib/src/ports/tournament_remote.dart` —
  `TournamentMatchRef` bekommt `final int? pitchNumber` (default null) nach
  `stageNodeId`.
- `lib/features/tournament/data/tournament_models.dart` —
  `tournamentMatchRefFromRow` (~Z487) und `tournamentMatchRefFromCdcRow` (~Z361)
  lesen `pitchNumber: _asIntOrNull(row[pitch_number])`.
- `lib/features/tournament/presentation/widgets/pitch_call_banner.dart` — Banner
  zeigt `ref.pitchNumber` des eigenen aktiven Matches statt clientseitiger
  PitchPlan-Ableitung.
- `lib/features/tournament/application/my_active_match_provider.dart` —
  Stub-Doc (Z22 "no pitch_number yet") entfernen.

### Server-Änderungen (additiv)
- **Migration `20261317000000_match_get_list_pitch_number.sql`** (`CREATE OR REPLACE`):
  `tournament_match_get` (Basis-Body `20261306000000`) und `tournament_list_matches`
  (Basis `20261212000000`) je um `'pitch_number', m.pitch_number` im
  `jsonb_build_object` ergänzt. Bodies 1:1 re-stated, nur die neue Projektion.
- **Keine Schema-Migration** — Spalte `pitch_number smallint NULL` existiert bereits.
- **Kein neuer Index** (`match_get` per PK, `list` per bestehendem
  `tournament_id`-Index), **keine RLS-Änderung** (`pitch_number` fällt unter die
  bestehenden `tournament_matches`-Grants).
- **Override-Gate:** keine Migration. `tournament_organizer_override` gatet bereits
  auf `caller_can_administer`. W0-T10 friert das per pgTAP ein.

### Wire-Model-Änderungen
`TournamentMatchRef.pitchNumber` (`int?`, default null), gefüllt aus der Wire-Spalte
`pitch_number`. Null-tolerant — alte RPC-Revisionen, Fakes und CDC-Rows ohne die
Spalte dekodieren weiterhin sauber. `PitchPlan` (`tournament_setup.dart`) bleibt
unverändert: es ist die Setup-Zeit-Quelle, die der Server beim Pairing in
`m.pitch_number` materialisiert; der Client liest ab jetzt das materialisierte Feld.

### ADRs
Keine neuen ADRs. ADR-0041 wird in W0-T02 importiert (Body finalisiert W1-T18).

### Acceptance-Form
- pgTAP `match_pitch_number_projection_test.sql`: Turnier mit PitchPlan starten,
  Runde pairen → `match_get(match).pitch_number` und `list_matches(t)[].pitch_number`
  tragen den Assign-Wert (Muster aus `stage_node_group_pitch_assignment_test.sql`).
- pgTAP `override_gate_administer_test.sql`: Club-Admin (nicht creator) darf
  overriden, fremder User bekommt `42501` — Regression-Freeze.
- dart-Unit (kubb_domain): `tournamentMatchRefFromRow` mappt `pitch_number` korrekt
  und bleibt null bei fehlender Spalte.
- Spec/ADR-Import: stepValidator L1/2 + `grep 'ADR-0035'` in der importierten
  Realtime-Spec == 0 Treffer.

### Risiken
Reihenfolge **innerhalb** der Welle: Migration (Projektion) MUSS vor dem
Wire-Decoder gemerged sein, sonst zeigt der Banner nie eine Nummer (fällt
null-tolerant zurück). Banner-Umstellung hängt am Wire-Feld. Nicht regredieren: die
null-Toleranz aller bestehenden Decoder, das Gate-Verhalten (pgTAP friert ein, keine
Body-Änderung), die deprecated-Alias-Kette `caller_can_manage → can_administer`.
ADR-0041 darf NICHT die main-0035 (vorrunde-ranking) überschreiben.

---

## 2. Wave 1 — Realtime-Korrektheit v1

### Übersicht
Macht die kritischen Realtime-Concerns frisch und crash-fest: Live-Rangliste ans
`tournament_matches`-CDC hängen, Reconnect/Resume erzwingt einen garantierten
Voll-Refetch-Catch-up (v1; Delta-Cursor folgt später), fünf Robustheits-Guards
verhindern "StreamController closed" / Zombie-Channel / Doppel-Timer unter Last,
Participants/Check-in kommt ins generalisierte Fallback-Gate, das vorhandene
Banner-Paar wird auf Standings/Live gezogen, und zuletzt wird die
Kritikalitäts-Stufe deklarativ am `channel_keys`-Builder verankert. Alles additiv:
keine neue Library, keine Server-Migration, kein Schema-Drop.

### Bounded Contexts
Primär `tournament/` (Application: Invalidator- + Resume-Catch-up-Provider;
Presentation: Banner auf Standings/Live). `core/`-Infrastructure:
`lib/core/data/realtime/` (RealtimeChannelLifecycle-Mixin +
SupabaseRealtimeChannel-Adapter), transport-agnostisch. `packages/kubb_domain/`:
`channel_keys.dart` + Port `realtime_channel.dart` für die Kritikalitäts-Stufe.
`data/`: `public_tournament_realtime.dart` (Broadcast-Adapter, refCount-Cleanup).
Der `RealtimeLifecycleController` ist bereits live-wired über
`realtimeLifecycleControllerProvider`.

### Komponenten
- `supabase_realtime_channel.dart:63` — disposed-Guard: vor
  `entry.changeController.add(...)` im `onPostgresChanges`-Callback auf
  `entry.disposed` prüfen (Bug 4.1).
- `realtime_channel_lifecycle.dart:94-105` `disposeEntry` — `teardownTransport`
  defensiv kapseln; Mixin-Kontrakt "must not throw" absichern (Bug 4.2).
- `realtime_fallback_provider.dart:81-117` — `controller.isClosed`-Guard vor
  `controller.add` in `emit()` und im connecting/closed-Pfad; single-flight für
  `pendingFlip` beim errored↔joined-Flackern (Bug 4.3).
- `realtime_channel_lifecycle.dart:83-90` `closeRef` + `scheduleReconnect:136` —
  `backoffIndex` bei manuellem closeRef/Re-Join auf 0 zurücksetzen (Bug 4.4).
  `pushState:122` macht das bei joined bereits; closeRef ergänzen.
- `public_tournament_realtime.dart:213-258` — refCount-Decrement + `_entries.remove`
  + Channel-Cleanup auch im Subscribe-Fehlerpfad, nicht nur in `onCancel` (Bug 4.5).
- NEU `tournamentStandingsRealtimeProvider` —
  `StreamProvider.autoDispose.family<TournamentMatchRef, TournamentId>`, watcht
  `remote.watchTournamentMatches`, ruft je CDC-Event
  `ref.invalidate(tournamentStandingsProvider(id))`. Analog
  `tournamentMatchListRealtimeProvider:22`.
- `tournament_standings_screen.dart:56-60` + `tournament_live_screen.dart` —
  `ref.watch(tournamentStandingsRealtimeProvider(id))` als Subscribe-Anker plus
  RealtimeStatusBanner/RealtimeStateBanner einhängen.
- NEU `realtimeCatchupProvider` — hört auf den Übergang nach joined (Rejoin) und
  invalidiert die kritischen Read-Provider des Concerns genau einmal pro Rejoin
  (Voll-Refetch v1). Resume deckt `RealtimeLifecycleController.reconnectKeys` ab.
- `tournament_match_providers.dart` — gegateten Participants-Fallback-Poller
  (analog `tournamentMatchListPollingProvider`) ergänzen, gegated auf
  `realtimeFallbackProvider(tournamentId)`.
- `channel_keys.dart` + `realtime_channel.dart` (kubb_domain) —
  `RealtimeCriticality{critical, normal}`-Enum + Mapping je Builder
  (`tournamentRealtimeChannelKey → critical`, `my*`/friends/inbox → normal).

### Server-Änderungen
Keine — rein clientseitig. `tournament_matches`/`tournament_participants` sind
bereits in der `supabase_realtime`-Publication (`20261236000000`), der
Lamport-Counter existiert (Voraussetzung für die spätere Delta-Phase, hier
ungenutzt). Vorab zu verifizieren (Spec §0, kein Code): `pg_publication_tables` auf
Prod prüfen plus monotone `202612xx`-Migrations-Sequenz bestätigen — Befund als
Notiz, keine Migration.

### Wire-Model-Änderungen
Keine an `TournamentMatchRef`. Einzige Domain-Erweiterung ist additiv und nicht-wire:
das `RealtimeCriticality`-Enum plus eine `criticalityFor(channelKey)`-Annotation.
Kein Feld an bestehenden Refs, keine CDC-Row-Projektion geändert (Delta-Cursor-
Persistenz kommt erst in der Folge-Welle).

### ADRs
- **ADR-0041:** Realtime-v1-Korrektheit — Standings als first-class CDC-Concern,
  garantierter Voll-Refetch-Catch-up bei Rejoin/Resume, deklarative
  Kritikalitäts-Stufe am `channel_keys`-Builder. Amendiert ADR-0029, v1-Schritt zum
  Zielbild. Datei aus W0-T02 importiert, Body in W1-T18 finalisiert.

### Acceptance-Form
Riverpod-Tests mit `FakeRealtimeChannel` als Truth-Source plus
ProviderContainer-Override von `realtimeChannelProvider`:
- **Standings-CDC:** `fake.emit(tournament_matches-update)` → `tournamentStandingsProvider(id)` re-evaluiert (5.1).
- **Catch-up:** `debugTransitionTo(errored→joined)` bzw. `resume()` → kritische
  Read-Provider genau einmal pro Rejoin refetcht (5.2/5.3, Zähl-Assertion).
- **Robustheit:** dispose-während-Event feuert kein add (5.4); errored↔joined-Flackern
  erzeugt genau einen Fallback-Timer und kein add-after-close (5.5); backoffIndex
  resettet nach closeRef (4.4); Broadcast-refCount == 0 nach fehlgeschlagenem
  subscribe (4.5).
- **Check-in-Fallback:** Participants-Poller invalidiert `tournamentDetailProvider`
  in der Fallback-Kadenz (5.6).
- **Banner:** widget-Test errored > 60 s → "Live unterbrochen"-Strip auf Standings,
  verschwindet bei joined (5.7).
- **Kritikalität:** domain-Unit `criticalityFor(tournamentRealtimeChannelKey) == critical`,
  my-teams == normal (5.8).

### Risiken
Nicht regredieren: (1) Battery-Invariante ADR-0029 — kein neuer `Timer.periodic`,
kein gehaltener Hintergrund-Socket; der Participants-Fallback-Poller MUSS gegated
sein. (2) Der Catch-up-Invalidate darf NICHT auf `tournamentRoundScheduleProvider`
oder andere CDC-Fold-Provider zielen — ein invalidate würde den akkumulierten Fold
zurücksetzen (Doc-Block `tournament_realtime_provider.dart:138`); nur fetch-basierte
FutureProvider invalidieren. (3) autoDispose-/refCount-Teardown im Adapter nicht
verändern (referenceCount-Smoke-Test bleibt grün). (4) RealtimeStateBanner /
RealtimeStatusBanner nicht duplizieren — wiederverwenden. **Harte Reihenfolge** (Spec
§6): Guards (§4.1/§4.3) VOR allem; dann Standings-Invalidator; dann Catch-up; dann
Fallback+Banner; Kritikalitäts-Stufe (§2) ZULETZT.

---

## 3. Wave 2 — Match-Entry Quick-Wins

### Übersicht
Vier reine UI-/Presentation-Verbesserungen am Spieler-Match-Eingabe-Screen und im
Home-Hub: Satzanzahl aus der Veranstalter-Config statt fix 3 (S3), Zurück-Button mit
canPop-Fallback statt fixer Match-Liste (S1), Match-Clock plus Pitch-Header in die
Kopf-Kachel mit gelockertem Pre-Start-Gate (S2), und die grüne PitchCall-Kachel
cross-tournament-tauglich in den Home-Hub, beide alten Kacheln raus (S4). Keine
Server-, Schema- oder Wire-Model-Änderung.

### Bounded Contexts
`tournament/` ausschliesslich Presentation:
`tournament_match_detail_screen.dart`, `widgets/pitch_call_banner.dart`, lesend gegen
`myActiveTournamentMatchProvider` / `myActiveMatchProvider`. `training/` nur in der
Presentation: `home_screen.dart` als Konsument der tournament-Provider (Cross-Context
über das Value-Objekt `MyActiveTournamentMatch`, kein DB-Join). Domain-Package
unangetastet.

### Komponenten
- `tournament_match_detail_screen.dart:142` — Helper `_maxSetsFor` analog
  `_maxBasekubbsFor`: liest `matchFormatConfig['max_sets']`, fällt auf
  `(2*sets_to_win-1)` zurück (Override-Screen-Vorlage `:69-79`), Minimum 1; ersetzt
  `const _maxSets:74`.
- `:180` + `:681` — beide `>= _maxSets`-Callsites (`_addSet`-Guard, Add-Button) auf
  das config-derivierte Cap umstellen, einmal in `_renderBody` berechnet.
- `:463-466` — BackButton von `context.go(matchesFor(...))` auf
  `Navigator.canPop(context) ? pop() : go(matchesFor)` (S1).
- `:586-632` + `_Header:802-869` — Clock-Gate von `!readOnly && startedAt != null`
  auf `!readOnly && duration > 0` lockern (rendert "wartet auf Start" auch ohne
  startedAt); Pitch-Header in `_Header`: "Runde X · Pitch N" statt "Runde X — Spiel Y".
- `pitch_call_banner.dart:19-31` — cross-tournament-Variante (dünner Home-Wrapper,
  der `MyActiveTournamentMatch` in die bestehende Banner-Darstellung füttert und
  `_open` auf `tournament.tournamentId.value` routet).
- `home_screen.dart:121-124` + `:201-233` — `_OngoingMatchCard`-Block und -Klasse
  entfernen, TournierCard-Platzhalter (`:125-130`) entfernen, stattdessen die grüne
  Cross-Tournament-PitchCall-Kachel conditional (`ongoingMatch != null`); ungenutzte
  Imports bereinigen.
- `lib/l10n/app_de.arb` — ARB-Key für "Runde X · Pitch N" plus "wartet auf
  Start"-Label; `generated/*.dart` im selben Commit via `flutter gen-l10n`.

### Server-Änderungen
Keine. `matchFormatConfig` (`max_sets`/`sets_to_win`) wird bereits vom create-RPC
geliefert; S3 liest denselben bestehenden Wire-Block.

### Wire-Model-Änderungen
Keine.

> **Pitch-Header-Quelle (Reconciliation, siehe §5 + Owner-Entscheid 2):** Da das
> echte `pitch_number` in W0 landet, zeigt der Match-Entry-Header `ref.pitchNumber`
> aus W0 — KEIN `matchNumberInRound`-Stand-in. Damit entfällt das ursprünglich
> geplante Stand-in-ADR (ADR-0042 gestrichen). W2-T05 konsumiert `ref.pitchNumber`
> und hängt zusätzlich an W0-T08 (Wire-Feld).

### ADRs
Keine eigenen mehr. Das ursprünglich vorgesehene Stand-in-ADR (ADR-0042) ist
gestrichen, weil das echte Feld kommt.

### Acceptance-Form
Reine Flutter-Widget-Tests:
- **S3:** `matchFormatConfig {max_sets:5}` → Add-Button bis 5 aktiv, ab 5 disabled;
  `{max_sets:3}` → bei 3 disabled; ohne Key → Fallback aus `sets_to_win`, Minimum 1.
- **S1:** poppbarer Stack → BackButton-Tap landet in der Herkunft; ohne poppbaren
  Stack → `go(matchesFor)`-Fallback (MockGoRouter).
- **S2:** `startedAt == null` → Clock-Widget rendert "wartet auf Start" statt
  `SizedBox.shrink`; `_Header`-Text enthält Pitch-Label, nicht "Spiel".
- **S4:** `home_screen` mit `myActiveTournamentMatchProvider` data ≠ null → genau eine
  grüne PitchCall-Kachel (ValueKey), kein `_OngoingMatchCard`, kein
  TournierCard-Platzhalter; data == null → keine Match-Kachel.

### Risiken
Nicht regredieren: (1) der bestehende Clock-Pfad für laufende Tournaments mit
`startedAt != null` inkl. RoundPhaseCountdown-Schedule-Logik (ADR-0031) — das
Lockern darf den Running/Hold-Zustand nicht zerstören, nur den
`startedAt == null`-Fall ergänzen; (2) `_maxSetsFor` darf nie `< drafts.length`
cappen (Remove-Logik bleibt min 1); (3) Conflict-Auto-Push (`:447-452`) und
PitchCallBanner im Detail-Screen (`:475`) bleiben unberührt. **Reihenfolge:** S3
zuerst (isoliert). S4 hängt an der cross-tournament-Banner-Variante: erst die
Banner-Erweiterung, DANN der Home-Umbau — netto exakt eine Match-Kachel.

---

## 4. Wave 3 — Live-Views config-adaptiv

### Übersicht
Macht die drei Live-Reiter (Mein Match / Übersicht / Rangliste) config-bewusst: die
Rangliste nutzt die zum Vorrunden-Typ passende Tiebreak-Kette und schaltet bei
Gruppenphase auf eine gruppierte Tabelle, die Übersicht hängt ein Gruppen-Label an
jedes Match und zeigt bei laufender KO-Phase den Bracket-Baum statt der Rundenliste,
Header-Bezeichnungen folgen Einzel/Team. Zusätzlich kommt die Inbox-Bell auf die
Live-Sicht und die heute fehlenden Nicht-Eingabe-Screens. Server-Änderungen additiv
(RPC-Spalten + Wire-Parse), kein Schema-Drop.

### Bounded Contexts
Primär `tournament/`: Domain-Helfer im pure-Dart-Package
`packages/kubb_domain/src/tournament/`, Wire-Parse + Provider in
`lib/features/tournament/{data,application}`, Reiter-UI in der Presentation. `core/`:
`InboxBellAction` ist bereits ein wiederverwendbares Widget. `inbox/` unverändert.
Format/Phase-Entscheidung lebt als pure Funktion im Domain-Package, die UI liest sie
über `tournamentDetailProvider`. `qualifiersPerGroup`/`format`/`tiebreakerOrder`
kommen ausschliesslich aus dem `TournamentDetailHeader`.

### Komponenten
- `tiebreaker.dart` — NEU: `tiebreakerCriterionFromWire(String)` (snake_case-Token →
  `TiebreakerCriterion`, z.B. `total_points`, `buchholz`, `buchholz_minus_h2h`,
  `kubb_difference`, `wins`; unbekannt → null) und `tiebreakerChainFromTokens` als
  Fallback-Pfad für reine roundRobin-Konfigs.
- `standings.dart` — NEU: `standingsChainFor(TournamentFormat, List<String> tiebreakerOrder)`
  — bevorzugt die format-feste Vorrunde-Kette (`schoch`/`schochThenKo` →
  `chainForStageType(schoch)` = Punkte → Buchholz; `roundRobinThenKo`/Gruppe →
  `chainForStageType(groupPhase)` = Punkte → KubbDiff, KEIN Buchholz), sonst
  `tiebreakerChainFromTokens` als Config-Fallback; ersetzt die hart verdrahtete Kette.
- `tournament_match_providers.dart:184-189` — `tournamentStandingsProvider`: const
  `TiebreakerChain` durch `standingsChainFor(detail.format, detail.tiebreakerOrder)`
  ersetzen (Fallback EKC/roundRobin wenn `detail == null`).
- `tournament_remote.dart:469-535` — `TournamentDetailHeader`: Getter
  `qualifiersPerGroup` (aus `setup['pool_phase_config']['qualifiers_per_group']`,
  Default 2) und `isTeam` (`teamSize > 1`); kein Konstruktor-Breaking-Change.
- `tournament_pool_standings_screen.dart` — NEU: `TournamentPoolStandingsView` (Body
  ohne Scaffold/AppBar, `qualifiersPerGroup`-Param) zum Einbetten.
- `tournament_standings_screen.dart:188-225` — `_HeaderRow`: Label "Spieler" durch
  Einzel/Team-Variante (neuer ARB `tournamentStandingsTeam`), gespeist aus
  `header.isTeam`.
- `tournament_bracket_screen.dart` — NEU: `TournamentBracketView`
  (`async.when` → `BracketCanvas`, `nameFor`/`consolationName`) ohne Scaffold/AppBar.
- `tournament_live_screen.dart` — Rangliste-Reiter: Format-Switch flach vs.
  gruppiert; Übersicht-Reiter: bei laufender KO-Phase `TournamentBracketView` statt
  `TournamentMatchListView`.
- `tournament_match_list_screen.dart:103-162` — `_MatchListBody`: Gruppen-Label
  rendern (primär `group_label` dann `roundNumber`, Header "Gruppe A · Runde 1" bei
  Gruppenphase, sonst "Runde N").
- `tournament_models.dart:486-516` — `tournamentMatchRefFromRow`: `groupLabel` aus
  `row['group_label']` parsen (null-safe).
- Profil/Achievements/Friends/Team-Listen/Meine-Trainings — `InboxBellAction` in die
  jeweilige AppBar-actions einhängen.

### Server-Änderungen (additiv)
- **Migration `20261321000000_w3_list_matches_phase_group.sql`** (`CREATE OR REPLACE`):
  `tournament_list_matches` (SETOF, Basis `20261212000000`) um zwei jsonb-Keys
  `'phase'` (`m.phase`) und `'group_label'` (`m.group_label`). Beide Spalten
  existieren bereits (`group_label` seit `20261201000010`). GRANT EXECUTE an
  authenticated, kein Drop, kein Schema-Change.
- Kein neuer Index (Filter per `tournament_id`, bereits indiziert), keine
  RLS-Änderung (re-stated byte-kompatibel ausser den zwei neuen Keys).

### Wire-Model-Änderungen
`TournamentMatchRef.groupLabel` (`String?`, default null) — additiv, bricht keine
Fakes/CDC-Rows (Muster identisch zu `phase`/`stageNodeId`). `operator==` und
`hashCode` um `groupLabel` erweitern. `TournamentDetailHeader`: keine
Konstruktor-Änderung, nur zwei berechnete Getter.

### ADRs
- **ADR-0043:** Tiebreak-Kette format-getrieben statt user-config in der
  Standings-Projektion — die Live-Rangliste leitet die Kette aus dem Format/Stage-Typ
  ab (`chainForStageType`), die persistierte `tiebreakerOrder` dient nur als Fallback
  für reine roundRobin-Turniere. Begründet durch vorrunde-ranking-spec §6.2 (Buchholz
  in Gruppen sinnlos); weicht von der wörtlichen Task-Formulierung
  "String → TiebreakerCriterion durchreichen" ab.

### Acceptance-Form
- domain (dart test): `tiebreakerCriterionFromWire` mappt jeden bekannten Token,
  unbekannte auf null; `standingsChainFor(schoch,..)` → Punkte → Buchholz,
  `(roundRobinThenKo,..)` → Punkte → KubbDiff ohne Buchholz, `(roundRobin, customTokens)`
  folgt den Tokens.
- widget: Gruppenphase → gruppierte Tabelle (`_GroupTile`) (5.1); Übersicht zeigt
  "Gruppe A · Runde 1" (5.2); Team-Header zeigt "Team", Einzel "Spieler" (5.4);
  `status=live` + KO-Matches → BracketCanvas statt MatchListBody (5.6);
  `InboxBellAction.byTooltip('Postfach')` auf Live + Nicht-Eingabe-Screens findbar,
  auf Score-Eingabe/Wizard NICHT (5.5).
- pgTAP: `tournament_list_matches` gibt `phase` und `group_label` zurück.

### Risiken
Nicht regredieren: die bestehende EKC/roundRobin-Standings-Reihenfolge (Fallback bei
`detail == null` exakt altes Verhalten), die per-set-wins-Synthese in
`tournamentStandingsProvider` (nur die TiebreakerChain-Zeile ändern,
`_resultFromMatch` unangetastet), die byte-kompatible Restated-Form von
`tournament_list_matches`. Die InboxBell-Ausschluss-Logik (KEINE Bell auf
Eingabe/Config/Wizard, Spec §4) darf nicht auf einen Eingabe-Screen geraten.
**Reihenfolge:** (1) Domain-Helfer + Wire-`groupLabel` + RPC-Migration zuerst →
(2) DetailHeader-Getter + View-Extraktionen (Pool/Bracket) + MatchList-Label
parallel → (3) Live-Screen-Verdrahtung zuletzt. **Cross-Wave:** W3 setzt
W1-Realtime (`tournamentMatchListRealtimeProvider`, `realtimeFallbackProvider`) und
W2-Daten (`group_label`-Befüllung, `pool_phase_config`) voraus; ohne befülltes
`group_label` fällt die Übersicht still auf reine Rundengruppierung zurück (kein
Crash).

---

## 5. Wave 4 — Cockpit-Steuerung

### Übersicht
Macht das Veranstalter-Cockpit (`/tournament/:id/dashboard`) zur einzigen
Steuerzentrale: Timer-Statusanzeige (Runde N / Pause + Restzeit) und additives
Verlängern/Verkürzen der laufenden Runde, Pitch-Nummer + begründungsfreier direkter
Punkte-Eintrag pro Match-Kachel, ein Cross-Turnier-Check-in-Screen aus der Übersicht,
und als letzter Schritt die Entkernung des Detail-Screens (alle canManage-Blöcke ins
Cockpit migriert, dann entfernt + "→ Dashboard"-Button). Alle Schreibwege bauen auf
bestehenden, server-gegateten RPCs auf; net-new sind nur ein additiver Timer-RPC und
ein Such-RPC für den Cross-Check-in.

> **Reconciliation — pitch_number kommt aus W0:** Das echte `pitch_number` landet
> bereits in W0-T05/T08 (Projektion in `match_get`/`list` + `TournamentMatchRef.pitchNumber`
> inkl. beider Parser). W4 **konsumiert `ref.pitchNumber` direkt**. Die ursprünglich
> hier geplanten Pitch-Tasks sind deshalb redundant und **gestrichen** (siehe
> Task-Liste W4-T01/T02/T03 in `tasks.md`, klar markiert). Die Pitch-Badge-UI
> (W4-T04) bleibt und hängt direkt an W0-T08.

### Bounded Contexts
`tournament/`: Domain in `packages/kubb_domain/` (`TournamentMatchRef`-Feld,
Timer-Restzeit-Formel in `round_schedule.dart`/`match_timer.dart`), Port
`TournamentRemote`, Adapter in `data/`, Application in `application/`, UI in der
Presentation. `core/` nur für Tokens/Widgets. Pitch und Check-in laufen über
bestehende `TournamentParticipant`/`MatchRef`-Value-Objects. Server-Gate
`tournament_caller_can_administer` / `_can_manage` bleibt Security-Boundary
(fail-closed), UI-Gate ist reine UX.

### Komponenten
- `widgets/schedule_control_bar.dart` — Statusanzeige (Runde N / Pause + Restzeit
  unter dem Primär-Toggle) + neue +/− Schritt-Buttons und Direkteingabe für
  Rundenzeit; konsumiert `TournamentRoundScheduleRef` (status, matchSeconds, startsAt,
  endsAt, pausedAt) skew-korrekt.
- `organizer_dashboard_detail_screen.dart` — `_MatchRow`: Pitch-Badge
  (`match.pitchNumber`) + "Punkte eintragen"-CTA neben Override/Forfeit; verdrahtet
  die Timer-extend-Callbacks an die ControlBar.
- `tournament_override_controller.dart` — neuer reason-freier Submit-Pfad
  `submitDirect(matchId, setsToWin)` ohne `isReasonValid()`-Precondition,
  wiederverwendet `toSetScores()`/`isScoreDecisive()`.
- `tournament_override_screen.dart` — Editor-Wiederverwendung als "Punkte eintragen"
  im direct-Modus (Reason-Feld ausgeblendet) via Modus-Flag.
- `tournament_providers.dart` — `TournamentActions`: `extendRound`/`shortenRound`,
  `directScore`, `searchCheckinTargets`.
- `tournament_remote.dart` — Port: `adjustRoundTime(TournamentId, int deltaSeconds)`,
  `searchCheckinTargets(query) -> List<CheckinSearchHit>`.
- `tournament_repository.dart` — Adapter für `tournament_adjust_round_time` und
  `tournament_search_checkin_targets`.
- `tournament_models.dart` — `CheckinSearchHit`-Wire-Parsing.
- `cross_checkin_screen.dart` — NEU: Suchfeld + Trefferliste (Team/Spieler →
  Turnier-Anmeldung) + Check-in-Button, erreichbar aus `organizer_dashboard_screen.dart`.
- `organizer_dashboard_screen.dart` — Einstiegspunkt in den Cross-Check-in-Screen.
- `tournament_detail_screen.dart` — ZULETZT: alle canManage-Blöcke
  (Check-in-Counter+Toggle, `TournamentEscalationPanel`, `_Actions`-Lifecycle)
  entfernen, durch einzelnen "→ Dashboard"-Button (`TournamentRoutes.dashboardDetail`)
  ersetzen.
- `tournament_routes.dart` — Route für `crossCheckin`.

### Server-Änderungen (additiv)
- **`tournament_adjust_round_time(p_tournament_id uuid, p_delta_seconds int)`** —
  NEU (Migration `20261323000000`): `pg_advisory_xact_lock` + Gate
  `tournament_caller_can_manage` (`42501`); `UPDATE tournament_round_schedule SET
  match_seconds = greatest(0, match_seconds + p_delta_seconds), ends_at = ends_at +
  make_interval(secs => p_delta_seconds) WHERE status IN ('call','running','awaiting_results')`;
  schreibt NUR die Schedule-Zeile (CDC pusht gratis); REVOKE public+anon, GRANT
  authenticated.
- **`tournament_search_checkin_targets(p_query text)`** — NEU (Migration
  `20261324000000`): SECURITY DEFINER, sucht confirmed Participants/Teams per ILIKE
  über Turniere mit `status IN ('registration_open','registration_closed','live')`
  UND `tournament_caller_can_manage(t.id)`; RETURNS jsonb mit `participant_id`,
  `tournament_id`, `display_name`, `checked_in_at`; Trigram-Index
  `CREATE INDEX IF NOT EXISTS` auf `user_profiles.nickname`/`teams.display_name`.
- KEIN Schema-Drop, KEINE Änderung an `tournament_organizer_override` (akzeptiert
  bereits scheduled/awaiting_results/disputed + reason 1..500 — Direct-Score nutzt es
  unverändert), KEINE Änderung an checkin/undo_checkin.

> **Timestamp-Kollision aufgelöst:** Das Briefing nannte für W4 ebenfalls
> `20261317000000` — das ist von W0-T05 belegt. W4 nutzt deshalb `20261322000000`
> (entfällt nach Reconciliation, da die list-Pitch-Migration redundant ist),
> `20261323000000` (adjust_round_time) und `20261324000000` (search_checkin_targets).

### Wire-Model-Änderungen
`TournamentMatchRef.pitchNumber` kommt aus W0 (kein eigenes Feld in W4). Neuer
DTO `CheckinSearchHit` (participantId, tournamentId, tournamentName, displayName,
checkedInAt) im Port-File. `TournamentRoundScheduleRef` bleibt unverändert
(matchSeconds/endsAt tragen den extend-Delta bereits). `TournamentOverrideDraft`:
reason wird optional behandelt (kein Feldwechsel, nur Submit-Pfad-Variante).

### ADRs
- **ADR-0044:** Direkter Punkte-Eintrag generalisiert `tournament_organizer_override`
  — kein eigener RPC, der bestehende Override-Schreibweg wird begründungsfrei (reason
  optional) für nicht-strittige Matches wiederverwendet; Audit bleibt erhalten
  (wer/wann/wert). (Owner-Entscheid 3.)
- **ADR-0045:** Timer-Verstellen als additiver Schreibweg auf `match_seconds`/`ends_at`
  der laufenden Schedule-Zeile — kein neues Pause-Modell, skew-konforme Anzeige via
  vorhandene CDC-Push statt Polling.

### Acceptance-Form
- pgTAP pro RPC: `tournament_adjust_round_time` (positiver+negativer Delta, Clamp auf
  ≥ 0, Gate-`42501` für Nicht-Manager, terminal/completed unberührt, NUR schedule
  geschrieben); `tournament_search_checkin_targets` (Scope: nur Check-in-Phase UND
  eigener Veranstalter, fremde/Nicht-Manager liefern leer, ILIKE-Treffer korrekt).
- domain dart test: `TournamentMatchRef`-Parser mappt `pitch_number` (kommt aus W0);
  Restzeit nach extend = neue `matchSeconds − elapsed`.
- widget: ScheduleControlBar zeigt "Runde N"/"Pause" + Restzeit, feuert
  extend/shorten bei +/− und Direkteingabe; `_MatchRow` zeigt Pitch-Badge +
  "Punkte eintragen"-CTA, dispatcht reason-freien `submitDirect`;
  `cross_checkin_screen` rendert Treffer und ruft `checkinParticipant`;
  `tournament_detail_screen` zeigt für canManage NUR "→ Dashboard" und KEINE
  Eskalations-/Lifecycle-/Check-in-Blöcke mehr (negativer Existenz-Test).

### Risiken
Nicht regredieren: laufende/finalisierte Matches (Override-RPC byte-identisch,
adjust-RPC fasst `tournament_matches` nie an); Pause/Resume/Skip-Verhalten und die
CDC-Fold-Mechanik von `tournamentRoundScheduleProvider` (kein `ref.invalidate` darauf
— extend muss via CDC pushen, NICHT die Detail-Fold reseten);
`tournament_list_matches`-Konsumenten; bestehender Override-Flow im Conflict/Detail-
Pfad. **Harte Reihenfolge:** (1) Detail-Entkernung ZULETZT — erst muss
Check-in + Lifecycle + Moderation vollständig im Cockpit erreichbar sein, sonst
Funktionsverlust; (2) Port-Erweiterung VOR Adapter VOR Actions VOR UI; (3)
reason-freier Submit-Pfad VOR der "Punkte eintragen"-CTA. Timer-extend, Direct-Score
und Cross-Check-in sind innerhalb der Welle unabhängig parallelisierbar;
Detail-Entkernung sammelt am Ende ein.

---

## 6. Wave 5 — Typ-Graph-Editor verdrahten (Ebene 2 UI-Wiring)

### Übersicht
Macht den fertig gebauten, aber nirgends gemounteten Ebene-2-Editor
(`StageTypeGraphCanvas` + Body) produktiv erreichbar: Form/Canvas-Toggle im
`StageTypeGraphBuilderBody` mit `isCanvasAvailable`-Gating (1:1-Muster der Ebene-1),
eine standalone Route auf `StageTypeGraphBuilderScreen`, und ein Wizard-Pfad, der
`toConfig()` ruft und `config['type_graph']` auf eine `StageNode` schreibt — dieselbe
jsonb, die der Summary-Reader und die Materializer-Migrationen bereits konsumieren.
Reines UI-Wiring: Domain, Validierung, Canvas, Summary und Engine bleiben unverändert.

### Bounded Contexts
`tournament/`. Layering: ausschliesslich Presentation
(`lib/features/tournament/presentation/`) plus ein dünner Routen-Eintrag in
`lib/app/router.dart`. Application-Layer wird nur GELESEN
(`stageTypeGraphBuilderProvider`, `toConfig`/`loadFromGraph`) — keine neue
Notifier-Logik. Domain-Package NICHT angefasst. `core/ui` nur lesend
(`isCanvasAvailable`, KubbTokens, SegmentedButton-Muster).

### Komponenten
- `stage_type_graph_builder_screen.dart` — `StageTypeGraphBuilderBody` (Z.59-101) von
  `ConsumerWidget` in ein StatefulWidget mit form/canvas-Toggle umbauen (analog
  `_StageGraphBuilderBodyState` in `stage_graph_builder_screen.dart:85-152`): privates
  `enum _EditorView { form, canvas }`, `isCanvasAvailable(MediaQuery.sizeOf(context).width)`-
  Gating, `effectiveView`-Clamp, SegmentedButton
  (`l.stageGraphViewForm`/`-Canvas` wiederverwenden), `const StageTypeGraphCanvas()`-
  Mount. Form-Sektionen wandern in `_StageTypeGraphFormView` (onSave durchreichen).
  Neues `embedded`-Flag (default false) analog `StageGraphBuilderBody.embedded`
  steuert nur Insets/Scroll + Canvas-Fixhöhe (`SizedBox(height: 360)`) im
  Wizard-Inline-Host, forkt NIE den State.
- `tournament_routes.dart` — `static const stageTypeGraph = '/tournament/stage-type-graph'`
  (statischer Prefix gewinnt vor dynamischem `/tournament/:id`; Doc-Kommentar im Stil
  des `stageGraph`-Eintrags Z.46).
- `lib/app/router.dart` — `GoRoute(path: TournamentRoutes.stageTypeGraph, builder: (_, _)
  => const StageTypeGraphBuilderScreen())` direkt nach dem stageGraph-Eintrag
  (Z.508-511), im selben Shell-Branch, über der dynamischen detail/:id-Route.
- `tournament_setup_wizard.dart` — pro StageNode im Ebene-1-Builder eine "Stufen-Typ
  modellieren"-Affordance, die `StageTypeGraphBuilderBody(embedded: true)` hostet und
  `onSave → toConfig()` in `StageNode.config` schreibt (über
  `stageGraphBuilderProvider.notifier.updateNode` mit gemergtem config-Map).
  Vorbelegung via `StageTypeGraphBuilderController(initialGraph)` aus
  `node.config['type_graph']`.

### Server-Änderungen
Keine. Die Materializer-/Advance-/Tiebreak-Migrationen für custom Typ-Graphen
existieren bereits auf main und konsumieren `config['type_graph']` bereits — sie
bleiben unberührt. Kein neues RPC, kein Index, keine RLS-Änderung.

### Wire-Model-Änderungen
Keine. `StageTypeGraph`/`TypeRound`/`TypeField`/`FieldEdge` + `toJson`/`fromJson` +
`validateStageTypeGraph` sind fertig und getestet. Der Wire-Key bleibt
`config['type_graph']` (`stageTypeGraphConfigKey`). Es wird nur der bereits
existierende `toConfig()`-Map an eine `StageNode.config` angehängt —
bit-identisch zu dem, was Summary-Reader und Materializer schon lesen.

### ADRs
Keine.

### Acceptance-Form
flutter widget-Tests:
- **Toggle-Gating:** schmaler Viewport zeigt keinen SegmentedButton und nur die Form;
  breiter Desktop-Viewport (`debugDefaultTargetPlatformOverride = linux`,
  width ≥ 720) zeigt den Toggle und mountet bei Auswahl `StageTypeGraphCanvas`.
- **Route:** Navigation-Test, der `TournamentRoutes.stageTypeGraph` pusht und
  `StageTypeGraphBuilderScreen` findet.
- **Write-Pfad:** Wizard-Test — Stufen-Typ modellieren, onSave, danach enthält die
  Ziel-`StageNode.config['type_graph']` eine Map und `stageTypeGraphSummaryRows`
  liefert > 0 Zeilen.
- **Parität bleibt grün:** `stage_type_graph_editor_parity_test.dart` unverändert
  (`toConfig` byte-identisch über beide Views).

### Risiken
Nicht regredieren: (a) Editor-Parität — Canvas und Form mutieren weiterhin NUR
`stageTypeGraphBuilderProvider`; kein zweiter State, keine zweite Serialisierung
(parity_test ist der Wächter). (b) Ebene-1-Toggle bleibt unverändert (nur als Muster
gelesen). (c) Summary-Reader (`wizard:3079` `stageTypeGraphSummaryRows`) und
Materializer-Migrationen unangetastet; der Write-Pfad muss exakt die `toConfig()`-Form
schreiben, sonst bricht der Round-Trip. (d) Wizard-Step-Liste (`_visibleSteps`) und
classic-Pfad dürfen nicht brechen — die Affordance hängt an einer StageNode im
stageGraph-Modus, nicht am classic-Flow. **Reihenfolge:** Body-Toggle ist
Voraussetzung für Route-Mount und Wizard-Host; Route-Konstante vor Router-Eintrag;
Write-Pfad ist der Kern, der `config['type_graph']` produktiv macht.
