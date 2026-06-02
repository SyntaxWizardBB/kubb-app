# P6 — Umsetzungsplan (Setup-Wizard-Redesign)

> **Status:** Entwurf zur Freigabe. Setzt [P6_SETUP_WIZARD_SPEC.md](P6_SETUP_WIZARD_SPEC.md)
> um. Reihenfolge nach Abhängigkeit & Risiko: erst Design-Lock (ADR), dann
> risikoarmer UI-Umbau, dann die zwei echten Domänen-Features.
> Jeder Block: implementieren → Review-Agent gegen Spec + Regeln → Tests grün.

## Abhängigkeits-Reihenfolge

```
ADR-0028 (Trostturnier)  ── Design-Lock, kein Code, Freigabe
        │
Block A  ── Wizard-UI-Umbau (Screens 1–6, inkl. Modell-B-Konfig-Eingaben)
        │
   ┌────┴────┬───────────┐
Block B    Block C     Block D ── parallelisierbar (unabhängig)
(Pitch-    (KO-Modal)  (Shoot-Out: Domain+Server+UI)
 Editor)
        │
Block E  ── Trostturnier-Engine (braucht ADR-0028 + Block-A-Konfig)
```

---

## ADR-0028 — Trostturnier (Modell B)  *(Design-Lock, zuerst)*

Kein Code, nur Entscheid-Dokument zur Freigabe. Legt fest:

- **Bracket-Struktur:** Hauptbaum (Single-Elim, bestehende ADR-0017) + separater
  Trostturnier-Baum. Kein Grand-Final-Merge (Abgrenzung zu ADR-0027).
- **Gestaffelter Loser-Feed:** deterministische Funktion `consolationDropTarget(
  mainRound, position, mainSize)` analog zu `lbDropTarget` — welcher Hauptbaum-
  Verlierer steigt in welche Trostturnier-Runde ein. Halbfinal-Verlierer → Spiel
  um Platz 3 (nicht Trostturnier).
- **Direkt-Einspeisung aus Vorrunde:** die `directToConsolation`-Teams seeden die
  frühen Trostturnier-Runden; gestaffelte Verlierer kommen je nach Ausscheide-
  Runde dazu.
- **Byes im Trostturnier erlaubt** (anders als Hauptbaum), wenn die Einsteiger-
  zahlen pro Runde keine Zweierpotenz ergeben — Bye-Vergabe-Regel definieren.
- **Konfig-Form (snake_case p_setup):** `consolation_main_bracket_size`,
  `consolation_direct_count`, `consolation_name`, `consolation_round_formats[]`.
- **Endrang-Berechnung:** Hauptbaum 1–4 (Final + Spiel um 3), danach Trostturnier-
  Platzierungen.

---

## Block A — Wizard-UI-Umbau  *(grösster, aber risikoarm: meist Umbau/Entfernen)*

**Dateien:** `tournament_setup_wizard.dart`, `widgets/_wizard_*`,
`tournament_config_draft.dart`, `tournament_config_controller.dart`, `app_de.arb`.

1. **Global:** `KubbAppBar` — Schritt-Name als `title` (gross/fett), „Neues
   Turnier" als `eyebrow` (klein). Auf allen Setup-Screens.
2. **Screen 3 „Vorrunde":** umbenennen; „Kein KO" (`KoType.none`) aus UI +
   Default Single-Out; Vorrunde-Scoring auf **nur Max. Sätze** (gerade erlaubt,
   `maxSets`-Min nicht mehr an `setsToWin` gekoppelt); `setsToWin`-Feld + Prelim-
   Tiebreak-Toggle aus der Vorrunde entfernen. Match-Zeit/Pause bleiben.
3. **Screen 1 Liga:** Liga-Chips (global) einblenden, wenn Verein gewählt; sonst
   ausblenden. League-relevance aus `clubId != null` + gewählter Liga ableiten.
   **Screen 4 (`_StepKind.league`) entfernen** inkl. `_wizard_league_step.dart`,
   `wizard_league_points_step.dart`.
4. **Screen 5 Gruppenphase:** Sichtbarkeit an `vorrundeType == groupPhase`;
   „Qualifier pro Gruppe"-Eingabe entfernen → read-only berechnet (KO-Grösse ÷
   Gruppen) + Teilbarkeits-Validierung.
5. **Screen 6 K.-o.:** KO-Grösse auf Zweierpotenz beschränken (Byes-Vorschau
   raus); Bronze-Toggle entfernen (immer an); Seeding-Label „aus Vorrunde";
   Mighty-Finisher-Quali-UI + `slots`/`pool`-Felder entfernen.
6. **Schritt-Reihenfolge:** KO-Grösse vor Gruppen-Aufteilung (für die berechneten
   Qualifier). `_visibleSteps` anpassen.
7. **Modell-B-Konfig-Eingaben** (Hauptbaum-Grösse, Direkt-ins-Trostturnier-Zahl,
   Name) in den Draft aufnehmen — UI sichtbar nur bei KoType=Trostturnier. Engine
   konsumiert sie erst in Block E.
8. **Tests:** Wizard-Widget-Tests (Schritt-Sichtbarkeit, Validierung, abgeleitete
   Werte), `tournament_config_draft`-Tests.

## Block B — Pitch „Manuelle Reihenfolge"-Editor

Sortierbare Liste (`ReorderableListView`) der Feldnummern → schreibt
`PitchPlan.order`; nur sichtbar bei `PitchSortStrategy.manual`. Tests.

## Block C — KO-Modell-Erklär-Modal

Info-Icon neben der KO-Auswahl → Bottom-Sheet/Dialog mit den drei Erklärungen aus
P6_KO_MODELS.md (Single-Out / Double-Elim / Trostturnier). l10n-Keys
`tournamentKoModelExplainer*`. Widget-Test.

## Block D — Shoot-Out-Tiebreak  *(Domain + Server + UI)*

**Domain:** quali-relevante Gleichstand-Erkennung an der Cut-Linie (in/um die
Qualifikationsplätze); `mightyFinisherShootout`-Kriterium von No-Op auf „löst per
erfasstem Sieger auf" umstellen. **Server:** Shoot-Out-Datensatz pro Gruppe +
Konsens-RPC (Match-Konsens-Flow wiederverwenden), Ranking-Integration.
**UI:** Shoot-Out-Auftrag (Inbox/Task) + Sieger-Meldung + gegenseitige
Bestätigung. **Tests:** Domain (Cut-Erkennung, Auflösung), Server (RPC), Widget.

## Block E — Trostturnier-Engine (Modell B)  *(grösster Neubau, nach ADR-0028)*

**Domain:** `bracket.dart` — Trostturnier-Baum-Generierung + `consolationDropTarget`.
**Server:** Migrationen — Setup-Felder (Block-A-Konfig persistieren), Bracket-
Generierung beim Start, Loser-Routing bei Match-Abschluss, Endrang. **Read-Path:**
`koMatchRowFromRow`/`bracketFromMatches` um Trostturnier-Phase erweitern.
**UI:** Trostturnier-Bracket-Ansicht (Name aus Konfig). **Tests:** Domain
(Routing, Direkt-Einspeisung, Byes), Server, Read-Path, Widget.

---

## Querschnitt

- **l10n:** alle neuen/geänderten Strings in `app_de.arb`, `flutter gen-l10n`
  (ggf. Retry wegen „generate flag").
- **Migrationen:** additiv, mit `supabase db reset` gegen lokale DB testen — kein
  Reset der genutzten Daten-DB ohne Vorwarnung (Shadow-DB für Probes).
- **Review:** je Block ein Agent gegen P6_SETUP_WIZARD_SPEC.md + die Regeln
  (`docs/rules/`, `ruleSets`, P6_RULES_DECISIONS.md).
- **Commits:** pro Block ein Commit (auf `feat/p6-tournament-setup`), nur auf
  Ansage gepusht.

## Aufwand grob

| Block | Umfang |
|---|---|
| ADR-0028 | klein (Design) |
| A Wizard-UI | gross |
| B Pitch-Editor | klein |
| C KO-Modal | klein |
| D Shoot-Out | mittel |
| E Trostturnier | gross |
