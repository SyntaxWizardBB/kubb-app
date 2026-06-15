# ADR-0033: Setup-Wizard-Redesign — vereinheitlichte 2er-Wahlen & Stufen-Graph-Integration

- **Status**: Proposed
- **Date**: 2026-06-15
- **Bezug**: ProjectPlan.txt „TournierSetup"; ADR-0030 (Stufen-Graph-Framework);
  `humanPlan/MilestoneTournaments.txt` (Wizard-Felder/Configs); Referenz-Foto
  `022b2b52-…jpeg` (KubbMAIster: Hauptbaum + Klingnauer „roter Weg" + Höseler
  „weisser Weg" aus Verlierer-Pfaden); Vorarbeit `2b6fccc` (Stufen-Graph-Einstieg
  vom Hub in den Setup-Wizard verschoben).
- **Code-Quelle (Ist verifiziert)**:
  - Wizard: `lib/features/tournament/presentation/tournament_setup_wizard.dart`
    (2er-Wahlen `_ScoringOption`, `_OptionRow`, `_ToggleRow`, `SegmentedButton`),
    `widgets/_wizard_ko_config_step.dart`, `_wizard_pool_config_step.dart`,
    `swiss_config_section.dart`.
  - Stufen-Graph: `stage_graph_builder_screen.dart` (Form- **und** Canvas-View,
    Validierung, Save/Apply-Template); Domain
    `packages/kubb_domain/.../stage_graph/` (StageNode/StageEdge/EdgeSelector incl.
    `LosersOfRounds`); **Engine vollständig**: `tournament_generate_stage_matches`,
    `tournament_run_stage_graph`, `tournament_route_completed_stage`,
    `tournament_start_stage_graph`, `tournament_stage_ranking`,
    `apply/save_stage_graph_template` (Migrationen `…223–230`, `…247/248`;
    Tabellen `tournament_stages/_edges/_inputs/_templates`).

> **Reines DESIGN-/Entscheid-Dokument.** Phasen-Plan + Tests materialisiert der
> separate Plan.

## Kontext & Motivation

Der Setup-Wizard hat für **2er-Entscheidungen fünf verschiedene Designs**
(Custom-Karten `_ScoringOption`/`_OptionRow`, Material-`RadioListTile`, `Switch`,
`SegmentedButton`) — uneinheitlich und „nicht schön" (ProjectPlan). Der **Stufen-
Graph ist technisch schon weit** (Engine + Editor + Modell **existieren**, die
Multi-Cup-Topologie des Fotos ist serverseitig lauffähig), aber:
- der Editor hängt nur als **Sprung-Button** im Wizard (`wizardStageGraphEntry`),
  keine echte Format-Gabel;
- pro Stufe fehlt die **volle Vorrunde/KO-Konfiguration** wie im klassischen Setup;
- **Beschriftung/Erklärung** fehlt (was bedeutet „Qualifikanten pro Gruppe vs. über
  alle Gruppen", was bewirkt jede Option, wie viele kommen weiter);
- **Multi-Kanten** sind im Modell da, aber im Editor nicht klar nutzbar;
- der **Canvas** ist nicht geräte-abhängig (soll nur Desktop sein, Mobil geführt);
- die **Zusammenfassung** zeigt den gewählten Graph nicht.

## Entscheidung

### 1. Vereinheitlichte 2er-Wahl-Komponente
Eine geteilte Komponente in `lib/core/ui` (`KubbBinaryChoice` im EKC/Klassisch-
Karten-Design; Token-konform, Design-System) + `KubbLabeledSwitch` für „default-an"-
Schalter (Anspielregel 2-4-6). **ALLE** 2er/kleinen Wahlen im Wizard darauf umstellen
(Wertung, Vorrunde-Typ, KO-Typ, Seeding-Quelle, KO-Matchup, KO-Tiebreak, Anspielregel,
Rule-Variants). **Auch im Stufen-Graph-Editor** verbindlich verwenden. Eine Quelle.

### 2. „Klassisch" bleibt ein eigener Pfad (GELOCKT, User)
Kein Umbau von „Klassisch" zu einem Preset-Graphen. Der Format-Schritt (Screen 3)
wird eine **Gabel**: **Klassisch** (heutiger Vorrunde×KO-Pfad, unverändert) /
**Stufen-Graph erstellen** / **Vorlage wählen**. Genau eine Wahl; danach läuft der
Wizard im gewählten Modus weiter.

### 3. Stufen-Graph in den Wizard integrieren (statt Sprung-Button)
Wählt man Graph/Vorlage, ist der Builder **Teil des Wizard-Flusses**: die **globalen
Eingaben** (Teilnehmerzahl, Felder/Pitches, Stammdaten) gelten für den Graph; nach dem
Bauen/Wählen geht es zu Config → **Zusammenfassung mit allen Graph-Details**. Engine,
Editor und Modell werden **wiederverwendet** (existieren).

### 4. Volle Stufen-Konfiguration (pro Knoten)
Jede Stufe ist so konfigurierbar wie im klassischen Setup: erkennbar **Vorrunde**
(Schoch / Gruppenphase inkl. Gruppenanzahl, Grouping-Strategie, Qualifikanten) **oder
KO** (single/double/consolation, Per-Runden-Format mit Tiebreak/Sätzen/Zeit/Matchup
wie in der normalen KO-Config). Durch **Wiederverwendung/Extraktion** der bestehenden
Config-Widgets (`_wizard_ko_config_step`, `_wizard_pool_config_step`,
`swiss_config_section`, `_KoRoundBlock`).

### 5. Beschriftung & Klarheit (zentral)
Jedes Config-Feld trägt Bedeutung **und Wirkung**. Explizit: „Qualifikanten **pro
Gruppe**" vs. „über alle Gruppen" eindeutig benennen; pro Stufe „**wie viele kommen
weiter**"; Selektor-Typen (Top-K, Ränge, **Verlierer bestimmter Runden**,
Nicht-Qualifizierte, Sieger) verständlich erklärt. Das KubbMAIster-Foto als
**dokumentiertes, baubares Referenz-Szenario** (Hauptbaum + zwei Neben-Cups aus
Verlierer-Kanten).

### 6. Multi-Kanten im Editor nutzbar machen
Modell/Engine unterstützen es bereits — der **Editor** muss mehrere ausgehende Kanten
pro Stufe klar erlaubern/beschriften (eine Kante → Final-Block, eine andere →
Zwischen-/Neben-Cup). Validierung (V1–V7 aus ADR-0030) sichtbar.

### 7. Geräte-Adaptivität: Canvas nur Desktop, Mobil geführt
Die **Canvas-View** (visueller DAG, Drag&Drop) nur auf **Desktop** (macOS/Windows/
Linux; ggf. breites Web) sichtbar/aktiv; **Mobil** nutzt die **geführte Form-/Listen-
Variante** (beide schreiben dasselbe Graph-Modell). Plattform-Erkennung
(`Platform.is*`/`kIsWeb` + Breakpoint).

### 8. Zusammenfassung zeigt den Graphen
Der Summary-Schritt rendert den gewählten Stufen-Graph (Knoten, Kanten, Per-Stufen-
Config) — nichts Konfiguriertes wird stillschweigend weggelassen (analog der H2-Regel
für Stammdaten).

## Abgrenzung
- **Kein** Backend-/Engine-Neubau — Stufen-Graph-Engine/Modell/Editor existieren.
- **Nicht** der globale Responsive-Milestone — nur das Canvas-Gating + der geführte
  Mobil-Editor sind hier im Scope.
- Verhalten des **klassischen** Pfads bleibt unverändert (nur die Buttons darin
  wechseln aufs gemeinsame Design).

## Offene Punkte (für den Plan)
1. **Editor-Knoten-Config-Tiefe** prüfen: was kann der Node-Dialog heute, was fehlt zur
   vollen Vorrunde/KO-Parität (Per-Runden-KO-Format, Tiebreak, Qualifikanten).
2. **Vorlagen-UX**: System-Presets (z.B. „KubbMAIster", „Gruppen→KO", „+2 Neben-Cups")
   als read-only Startpunkte + eigene gespeicherte (`save/apply_stage_graph_template`).
3. **Mobil-Editor-Form**: geführte Stufen-Liste mit Kanten-Auswahl — genaue UX.
4. **Gemeinsamer „globaler" Config-Schritt** für beide Pfade (Teilnehmer/Felder/
   Stammdaten) vs. getrennt.
5. **Klassisch↔Graph-Wechsel** im Wizard: was passiert mit bereits Eingegebenem.

> Reihenfolge (Plan): P1 Buttons → P2 Wizard-Gabel + globale Eingaben + Summary →
> P3 Stufen-Config-Tiefe + Beschriftung + Multi-Kanten-UX → P4 Canvas-Desktop/
> Mobil-geführt. „Klassisch = eigener Pfad" ist verbindlich.
