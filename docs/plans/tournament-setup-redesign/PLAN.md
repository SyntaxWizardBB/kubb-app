# Umsetzungsplan: Turnier-Setup-Redesign (ADR-0033)

**Bezug:** ADR-0033, ADR-0030, CLAUDE.md, AGENT_PIPELINE_PLAYBOOK. Branch
`feat/tournament-setup-redesign` (von main). **Auto-Commit/Push pro grünem Block.**

## 0. Audit-Befunde (bestimmen den Scope)

- **0.1 Editor-Knoten-Config DÜNN:** `_NodeDialog` erfasst nur pool/roundRobin
  (groupCount/qualifierCount), swiss (rounds), shootoutQuali (slots);
  **singleElim/doubleElim/consolation → leeres `{}`** (keine Per-Runden-Formate/
  Tiebreak/Matchup/Trost-Config). `StageNode.config` ist eine **freie Map** → P3
  erweitert nur Keys, **keine Domain-Migration, kein Engine-Eingriff**.
- **0.2 Config-Widgets teils entkoppelt:** `_KoRoundBlock` (callback-rein, nur
  private→public) + `SwissConfigSection` (public, callback) direkt nutzbar;
  Pool/KO-Step an `TournamentConfigController`/`Draft` gekoppelt → draft-freie
  `*StageConfigPanel`-Widgets extrahieren (eine Quelle, zwei Aufrufer: klassischer
  Wizard-Step + Node-Dialog).
- **0.3 KEINE Graph↔Wizard↔Tournament-Verdrahtung:** Draft hält keinen Graph;
  Wizard verlinkt nur per `context.push(stageGraph)`. **OE-1 GEKLÄRT:** es gibt
  KEINE direkte Apply-RPC — nur `save_stage_graph_template(name,desc,vis,graph
  jsonb,club_id)` → Template-ID, dann `apply_stage_graph_template(tournament_id,
  template_id)`. Frei gebauter Graph beim Submit = auto-save(privat) → apply.
- **0.4 2er-Wahlen FRAGMENTIERT (5 Designs):** `_ScoringOption`/`_OptionRow`
  (Custom-Karten), `SegmentedButton` (Anspielregel), `_ToggleRow`/`SwitchListTile`
  (Switches), `RadioListTile` (seeding/matchup/tiebreak; `_SeedingModeRadios` hat
  **hartkodierte deutsche Strings** → l10n-isieren), `_SelectChip` (Pitch).
- **0.5 Projekt nutzt Goldens** (bracket_canvas_golden) → neue Komponenten kriegen
  Golden-Tests; bestehende Wizard/Editor-Tests müssen grün bleiben.

## 1. Reihenfolge (P1→P2→P3→P4), je Block Domain/Widget→Wizard→Editor, 1 Commit
P1 zuerst (geteilte Komponente ist Voraussetzung für P2-Karten + P3-Editor). P2 vor
P3 (Gabel+Draft-formatMode ist das Gerüst). P3 vor P4 (Config-Panels speisen die
Mobil-Form). „Klassisch = eigener Pfad" ist verbindlich.

## PHASE 1 — Geteilte 2er-Wahl-Komponenten
**P1.1** `lib/core/ui/widgets/kubb_binary_choice.dart` (`KubbBinaryChoice<T>`,
generisch N≥2, EKC/Klassisch-Karten-Design, Tokens, Touch≥48dp, Radio-Icon, selektiert
`bgSunken`+primary-Border) + `kubb_labeled_switch.dart` (`KubbLabeledSwitch`, ersetzt
`_ToggleRow`). Stateless. Tests + **Goldens** (2/3-Options sel/unsel, switch on/off).
**P1.2** Alle Wizard-2er-Wahlen umstellen: `tournament_setup_wizard.dart` (Wertung,
Vorrunde, KO-Typ, Anspielregel→`KubbLabeledSwitch` default-an, Rule-Variants+InviteOnly,
Pitch-Mode/Sort); `_wizard_ko_config_step.dart` (Seeding/Matchup/Tiebreak→
`KubbBinaryChoice`, Round-Tiebreak→`KubbLabeledSwitch`, **Seeding-Strings l10n**). Alte
private Widgets entfernen. Test-Keys/ARB mitziehen. Bestehende Wizard-Tests grün.

## PHASE 2 — Wizard-Gabel + Graph-Integration + Summary
**P2.1 (Draft):** `tournament_config_draft.dart` + Controller — `TournamentFormatMode
{classic,stageGraph}` (default classic), `StageGraph? stageGraph`, `int? fieldSize`,
`String? appliedTemplateId`; Setter. Klassisch-Pfad unverändert. Tests (classic Default,
Graph round-trip).
**P2.2 (Wizard-Gabel):** `_StepFormat` beginnt mit `KubbBinaryChoice<FormatMode>`-Gabel
**Klassisch / Stufen-Graph erstellen / Vorlage wählen**. classic→heutige Vorrunde×KO;
stageGraph→eingebetteter Builder (+ Template-Bar bei „Vorlage"). Globale Eingaben
(Sets/Zeit/Pitch) für beide sichtbar. `_visibleSteps`/`_stepValid`: bei stageGraph
koConfig-Step überspringen, Validität aus `stageGraphBuilderProvider !hasErrors &&
nodes.isNotEmpty`. `wizardStageGraphEntry`-Sprung-Button entfällt.
**P2.3 (Editor-Reuse):** `StageGraphBuilderBody({embedded})` aus
`stage_graph_builder_screen.dart` extrahieren (ohne Scaffold/AppBar), Wizard hostet es
inline; weiterhin NUR `stageGraphBuilderProvider` (kein Doppel-State). Field-Size aus
`pitchPlan.availablePitches().length` seeden; onChange→`controller.setStageGraph`.
**P2.4 (Submit-Wiring, OE-1):** `_submit()` + `createTournament` — nach create bei
stageGraph: `save_stage_graph_template`(auto-Name, privat) → `apply_stage_graph_template
(newTournamentId, templateId)`; bei „Vorlage gewählt" direkt apply. classic ruft kein
apply. Fehlertoleranz wie `_sendInvites`. Tests (create→apply-Reihenfolge im Repo-Fake).
**P2.5 (Summary):** `_StepSummary` bei stageGraph „Stufen-Graph"-Sektion (Knoten+Config-
Kurzform, Kanten `from→to`+Selektor-Label+seedingIn), nichts weglassen (H2). Tests.

## PHASE 3 — Stufen-Config-Tiefe + Beschriftung + Multi-Kanten
**P3.1 (Panels extrahieren, draft-frei):** `lib/features/tournament/presentation/
widgets/stage_config/{ko,pool,swiss}_stage_config_panel.dart` — props-in/callback-out,
keine Riverpod/Draft-Kopplung. KoPanel: `_KoRoundBlock` (public), Matchup/Tiebreak
(`KubbBinaryChoice`), KO-Size, Trost-Config. PoolPanel: Gruppenzahl, Strategie,
**Qualifikanten KLAR „pro Gruppe" vs „über alle Gruppen"** (zwei explizite Felder/Modus),
„wie viele kommen weiter". SwissPanel: Wrapper. Klassische Steps hosten dieselben Panels
(Verhalten bit-identisch). Tests (Panel-callbacks; Wizard-Regression).
**P3.2 (Node-Dialog volle Panels + Beschriftung):** `_NodeDialog._configFields` je Typ
das passende Panel (Elim/Double/Consolation → volle KO-Parität, heute leer);
`_buildConfig()` schreibt erweiterte `config`-Keys (freie Map, keine Migration);
`_nodeConfigSummary` erweitern; Selektor-Erklärtexte (Top-K/Ränge/Verlierer-Runden/
Nicht-Qualifizierte/Sieger, l10n). Tests (Elim-Knoten hat KO-Config, JSON-round-trip).
**P3.3 (Editor-2er-Wahlen + Multi-Kanten-Klarheit):** Node-/Edge-Dialog-Auswahlen auf
`KubbBinaryChoice`/Kubb-Chips; Edges pro Quellknoten gruppiert, mehrere ausgehende Kanten
klar beschriftet; Validierung sichtbar. Doku `docs/plans/tournament-setup-redesign/
REFERENCE-kubbmaister.md` (Foto-Topologie als baubares Szenario: Hauptbaum + 2 Neben-Cups
aus Verlierer-Kanten). Test (2 Kanten/Knoten; KubbMAIster gegen `validateStageGraph`).

## PHASE 4 — Plattform-Adaptivität
**P4.1 (Canvas Desktop-only):** `lib/core/ui/platform_capabilities.dart`
(`isCanvasCapablePlatform` = `!kIsWeb && (macOS||Windows||Linux)` o. breites Web +
Breakpoint). `stage_graph_builder_screen.dart` Form/Canvas-Toggle nur bei
desktop+Breite; sonst Form erzwungen. Test (kein Toggle auf Mobil-Breite).
**P4.2 (Mobil-Form geführt):** `_StageGraphFormView` als Mobil-Variante (Stufen-Liste +
Kanten-Auswahl), schreibt denselben `stageGraphBuilderProvider`. P3-Erklärungen
wiederverwenden. Test (Mobil-Form == Canvas-Graph).

## 4. Risiken + Absicherung
- **Klassisch↔Graph-Wechsel:** Draft hält Graph SEPARAT von koConfig/vorrundeType →
  Moduswechsel überschreibt nichts; beide koexistieren; nur Submit wertet `formatMode`.
  EDIT-Mode leitet `formatMode` aus geladenem Turnier ab. Test „hin-und-zurück verliert
  nichts".
- **Editor-Reuse ohne Doppel-State:** nur `stageGraphBuilderProvider`; embedded Body
  body-only. **Kein Engine-Eingriff** (config-Map frei; Submit nutzt save+apply).
- **Plattform-Gating** zentral + testbar. **Test-Keys/l10n** pro Block mitziehen.

## 5. Offene Entscheidungen (mit Empfehlung)
1. **OE-1 GEKLÄRT:** save-template(privat)+apply (keine direkte RPC).
2. **System-Presets** (KubbMAIster/Gruppen→KO/+2-Cups) read-only über `is_system`-
   Templates als Startpunkte (Empf.).
3. **Mobil-Editor:** geführte Stufen-Liste + Kanten-Dropdown, gleiche Panels, kein
   Drag&Drop (Empf.).
4. **Globaler Config-Schritt gemeinsam** für beide Modi (Empf.).
5. **Moduswechsel** ohne Verwerfen/Dialog (Empf.).

## 6. Verifikation je Block
`flutter gen-l10n` falls ARB; `flutter analyze` 0 Fehler; `flutter test --no-pub`
(betroffene + Goldens grün); Design-Abgleich `docs/design/`; git-Scope nur erwartete
Dateien, 1 Commit/Block, kein `git add -A`.

### Critical Files
`tournament_setup_wizard.dart` · `stage_graph_builder_screen.dart` ·
`widgets/_wizard_ko_config_step.dart` · `data/tournament_config_draft.dart` ·
`data/stage_graph_templates_repository.dart` (save/apply RPC-Namen) ·
`lib/core/ui/widgets/kubb_button.dart` (Referenz für neue Choice-Widgets).

## 7. Phase P5 — Nachtrag aus Compliance-Review (§8 + §4)

P1–P4 sind in main-branch; Review-Ergebnis: §8 partial, §4 missing (ADR-Nachtrag
2026-06-18). P5 schließt beide. **Klassisch-Pfad bleibt bit-identisch.**

**Config-Key-Schema (eine Quelle, UI schreibt = Engine liest), in `StageNode.config`:**
Bestehende Keys (camelCase) bleiben: `groupCount`, `qualifierCount`, `rounds`,
`slots`, `with_reset`. NEU (snake_case, spiegelt Klassik-JSON, kein Template-Daten-
Migrat): `ko_matchup` (seed_high_vs_low|one_vs_two), `ko_tiebreak_method`
(classic_kingtoss_removal|mighty_finisher_shootout), `ko_round_formats`
(`[MatchFormatSpec.toJson()]`, Index 0 = Runde 1), `grouping_strategy`
(snake|random|seeded), `random_seed`.

- **P5.1 §8-Summary (kein Engine-Eingriff).** `_StepSummary` (tournament_setup_wizard.dart
  ~2616) rendert statt 2 Counts: Knoten (id/Typ/Seeding/Config), Kanten (from→to/
  Selektor inkl. LosersOfRounds/seedingIn). Null-Template-Fall (`stageGraph==null` &&
  `appliedTemplateId!=null` → Graph aus `stageGraphBuilderProvider` + Template-Name).
  Neues `widgets/stage_graph_summary_view.dart` (stateless, reuse Label-Mapper +
  promoted `stageNodeConfigSummary`). +Regressionstest (built + template-Modus).
- **P5.2 §4 Domain (pure-Dart, keine Migration).** Neues
  `kubb_domain/.../stage_graph/stage_node_config.dart`: typisierte read/write-Helper
  über die freie Map (reuse MatchFormatSpec/KoMatchup/KoTiebreakMethod/
  PoolGroupingStrategy). +Round-trip-Tests.
- **P5.3 §4 Engine-Konsum — AUFGETEILT (Engine-Surface-Investigation 2026-06-18,
  Owner „auch Klassik nachrüsten" → ADR-0034).** Befund: Matchup & Tiebreak sind
  AUCH klassisch nur Stubs; Pool-Splitter `_tournament_compute_pools` existiert;
  KO-Tiebreak hat KEINE Infrastruktur (Pool-Shootout ≠ KO-Match-Tie). Reihenfolge
  sicher→riskant:
  - **P5.3a Pool-Multi-Gruppen (Stage)** — `tournament_generate_stage_matches`
    (latest 20261261000000) ruft `_tournament_compute_pools` für pool-Knoten mit
    `group_count`/`grouping_strategy`/`random_seed`. Additiv, berührt Klassik nicht.
  - **P5.3b Matchup-Konsum (Klassik + Stage, ADR-0034 §1)** —
    `_tournament_compute_ko_bracket` (+`_de_bracket`) additiver Param
    `p_matchup DEFAULT 'seed_high_vs_low'`; nur Round-1-Pairing verzweigt,
    Aufstiegs-Slots unverändert. Klassik aus `tournaments.ko_matchup`, Stage aus
    `config`. Pure-Dart `_standardBracketOrder` mitziehen. Bracket-Goldens prüfen.
  - **P5.3c Per-Runden-Format (Stage-Runde 1)** — neuer
    `_tournament_schedule_stage_ko_seconds` (analog `_tournament_schedule_ko_seconds`
    20261251000000, liest `tournament_stages.config->ko_round_formats`).
    Ehrlich-teilweise: spätere Stage-KO-Runden haben noch keinen Scheduler
    (ADR-0031-Nachbau) — dokumentiert.
  - **P5.3d Tiebreak-Methoden-Konsum (ADR-0034 §2, EIGENES Feature, ZULETZT)** —
    Scoring-/Finalize-Flow-Eingriff, keine bestehende Infrastruktur; eigener Block
    + eigene Tests; fasst Match-Generierung NICHT an.
  Guardrails: additiv, Stale-Body per-Funktion-Höchst-Timestamp, Probe in
  BEGIN/ROLLBACK, KEIN db reset, KEIN CDC/Publication-Eingriff.
- **P5.4 §4 UI-Extraktion (draft-frei).** `widgets/stage_config/` mit
  `ko_stage_config_panel` (reuse `_KoRoundBlock`→public, KubbBinaryChoice für
  Matchup/Tiebreak, Consolation), `pool_stage_config_panel` (Grouping + „pro Gruppe"),
  `swiss_stage_config_panel` (über bestehende, bereits draft-freie SwissConfigSection).
  Klassik-Steps hosten dieselben Panels → bit-identisch.
- **P5.5 §4 Node-Dialog-Wiring.** `_NodeDialog` rendert pro Typ die Panels;
  `_buildConfig` schreibt die neuen Keys via P5.2-Writer (single_elim/consolation nicht
  mehr `{}`). `stageNodeConfigSummary` deckt neue Keys (Tile + Summary konsistent).
- **P5.6 Tests/DoD.** Engine-Probe + Round-trip + Summary grün; analyze 0 Fehler;
  Suite grün; 1 Commit/Phase, Push auf Ansage.

**OP2 (3 System-Presets) folgt NACH P5** (Migrations-Seed, sobald Knoten volle Config
tragen). **§2** bleibt als 2+1-Gabel (ADR-Wortlaut nachgezogen) — kein Umbau.
