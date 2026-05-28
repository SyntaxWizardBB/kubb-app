# Quality-Gate: Finisseur Per-Stick Live-Eingabe

**Quelle**: docs/design/ui_kits/app/FinisseurStickScreen.jsx (`window.FinisseurStickScreen`)
**Flutter-Pendant**: lib/features/training/presentation/finisseur_stick_screen.dart (+ `widgets/finisseur_inputs.dart`, `widgets/pip_progress.dart`)
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (top-down)

1. **AppBar** (`shared.AppBar` aus `shared.jsx`)
   - Back-Button links
   - Eyebrow `Finisseur · ${config.field}/${config.base}` (z.B. `Finisseur · 7/3`)
   - Title: `Stock ${current+1} / 6` (mit dem `/ 6` in 0.5 opacity gerendert)
   - Kein rechter Slot
2. **Stick-Progress-Pips**: 6 horizontale Pillen (`flex: 1`, max 48px, Höhe 6px, `radiusSm` 3px), gefärbt je nach Status:
   - `pending` (future): `stone200`
   - `active` (current): `stone900`
   - `done` (Field oder 8m getroffen): `meadow500`
   - `heli`: `--bk-heli` (`wood400`)
   - `penalty` (Strafkubbs aktiv): `--bk-penalty` (#8A1F3D)
   - `king` (King-Throw getroffen): `--bk-king` (#C89B3D)
   - `empty` (untouched, aber in der Vergangenheit): `stone200`
3. **Remaining-Block** (in `bgRaised`-Card)
   - 2 Zellen, durch 1px Divider (`tokens.line`) getrennt
   - Linke Zelle: "Feldkubbs übrig" (11px uppercase Label), Wert 32px display weight 800 in `meadow600` (tokens.primary)
   - Rechte Zelle: "Basiskubbs übrig", Wert 32px in `wood500`
4. **Section "Feldkubbs umgeworfen"** (Phase: field)
   - Section-Head: Label uppercase + Range-Meta `0–${fieldMaxThisStick}` mono
   - Wenn `fieldMaxThisStick === 0`: Empty-Hint italic "keine Feldkubbs mehr — direkt 8m oder König"
   - Sonst: `auto-fit` Grid mit min 56px Chips, 60px Mindesthöhe, display 24px weight 800 tabular-nums. Aktiver Chip: `stone900`-Background, `chalk50`-Text
5. **Toggle-Grid** (2 Spalten 1fr 1fr, gap 8px)
   - **8m-Treffer** (nur sichtbar wenn `remBaseBefore > 0`): Label + Sub "Wurf auf Basiskubb". Aktiv: `meadow600` BG, weiss
   - **Helikopter** (`tone=heli`): aktiv `wood400` BG, `stone900` Text. Klick löscht alle anderen Outcome-Daten für diesen Stock
   - **Königswurf** (`tone=king`, nur sichtbar wenn `kingPossible`): aktiv `wood-ish king`-Color `#C89B3D` BG
6. **Strafkubb-Section** (nur Stock 1, nur wenn `config.base > 0`, nicht im Heli-Mode)
   - Section-Head: "Strafkubbs (vom letzten Halbsatz)" + Meta `${p1+p2} / ${config.base} umgeworfen`
   - 2 PenaltyThrowRow-Cards (1× geworfen, 2× geworfen) jeweils `bgRaised` 14px Radius
   - Pro Row: Label + Sub + Readout `<n> / <max>`, Chip-Reihe von `0..max` als 44x44 Chips. Aktiver Chip: `--bk-penalty`-BG
7. **King-Detail** (sichtbar wenn `stick.king` gesetzt)
   - `bgRaised`-Card, 2px inset Border `--bk-king`
   - Position-Row: Label "Position" + Segmented `oben | unten`
   - Outcome-Row: Label "Outcome" + Segmented `Treffer | verfehlt`
8. **Next-Button**: "Stock N+1" oder "Session abschliessen" beim letzten — primary, 60px hoch

### Farben (aus Tokens)

| Verwendung | CSS-Token | KubbTokens |
|---|---|---|
| Screen-BG | `--bk-bg` | `tokens.bg` |
| Card-BG (Remaining, Section, King-Detail) | `--bk-bg-raised` | `tokens.bgRaised` |
| Section-BG hinter Penalty-Chips | `--bk-bg` | `tokens.bg` (Default-Chip) |
| Sunken-BG (Segmented-Background) | `--bk-bg-sunken` | `tokens.bgSunken` |
| Pip pending / empty | `--bk-stone-200` | `KubbTokens.stone200` |
| Pip active | `--bk-stone-900` | `KubbTokens.stone900` |
| Pip done | `--bk-meadow-500` | `KubbTokens.meadow500` |
| Pip heli, Heli-Toggle aktiv | `--bk-heli` | `KubbTokens.heli` = `#C08A33` (wood400) |
| Pip penalty, Penalty-Chip aktiv | `--bk-penalty` | `KubbTokens.penalty` = `#8A1F3D` |
| Pip king, King-Toggle aktiv, King-Border | `--bk-king` | `KubbTokens.king` = `#C89B3D` |
| Remaining Feld-Wert | `--bk-meadow-600` | `tokens.primary` (light: meadow500 / dark: meadow400 — Design fix meadow600) |
| Remaining Basis-Wert | `--bk-wood-500` | `KubbTokens.wood500` |
| 8m-Toggle aktiv | `--bk-meadow-600` | meadow600 |
| Section-Meta | `--bk-fg-subtle` | `tokens.fgSubtle` |
| Aktiv-Chip (Field-Hits) | `--bk-stone-900` | `KubbTokens.stone900` mit `chalk50` Text |
| Idle-Chip Border | `--bk-line` | `tokens.line` |
| Penalty-Chip Border idle | `--bk-line-strong` | `tokens.lineStrong` |
| Next-Button | `--bk-primary` / `--bk-on-primary` | `tokens.primary` / `tokens.onPrimary` |
| Divider Remaining | `--bk-line` | `tokens.line` |

### Typografie

| Bereich | Font | Grösse | Weight | Sonderregeln |
|---|---|---|---|---|
| AppBar Eyebrow `Finisseur · 7/3` | body | 11px | 600 | uppercase, 0.08em |
| AppBar Title `Stock 2 / 6` | display | 20px | 700 | `/ 6` mit opacity 0.5 |
| Remaining-Label | body | 11px | 600 | uppercase, 0.08em |
| Remaining-Value | display | 32px | 800 | tabular-nums, letter-spacing -0.02em |
| Section-Head | body | 11px | 600 | uppercase, 0.08em |
| Section-Meta | mono | 10px | 500 | normal case |
| Field-Hit-Chip (BigChip) | display | 24px | 800 | tabular-nums |
| Toggle-Label | display | 15px | 700 | — |
| Toggle-Sub | body | 11px | 400 | opacity 0.85 |
| Penalty-Label | display | 15px | 700 | — |
| Penalty-Sub | body | 11px | 400 | `fgMuted` |
| Penalty-Readout-N | display | 22px | 800 | tabular-nums |
| Penalty-Readout-Max | display | 12px | 600 | `fgMuted` |
| Penalty-Chip | display | 18px | 800 | tabular-nums |
| King-Label | body | 11px | 600 | uppercase, 0.08em |
| Segmented-Btn | display | 13px | 600 | — |
| Empty-Hint | body | 12px | 400 | italic, `fgMuted` |
| Next-Button | display | 18px | 700 | — |

### Spacing

- AppBar-Padding: `54px 12px 6px`
- Stick-Pip-Row: `4px 16px 10px`, Gap 8
- Remaining-Block: Margin `4px 16px 14px`, Padding `10px 8px`
- Section-Padding: `2px 16px 6px`
- Big-Chip-Grid: Gap 8px
- Toggle-Grid: Padding `10px 16px 6px`, Gap 8
- Penalty-Row Gap: 10px (zwischen 1× und 2×)
- Penalty-Chips Gap: 6px
- King-Detail Margin: `8px 16px 0`, Padding `10px 14px`
- Next-Button Margin: `14px 16px 28px`
- Screen Padding-Bottom: 32px

### Border-Radius

- Pips: 3px (`radiusSm`-ish)
- Remaining-Card: 16px (`radiusXl`)
- Big-Chip (Field-Hits): 14px
- Toggle: 14px
- Penalty-Card: 14px
- Penalty-Chip: 10px (`radiusMd`-ish)
- King-Detail: 14px
- Segmented-Wrap: 999 (`radiusPill`)
- Segmented-Btn: 999
- Next-Button: 16px (`radiusXl`)

### Shadows

- Keine Box-Shadows; alle Borders via `inset 0 0 0 Xpx <color>` (z.B. King-Detail `inset 0 0 0 2px var(--bk-king)`).

### Icons

Der Stick-Screen nutzt **keine** Lucide-Icons im Body — alle Outcomes sind Text-Buttons. Lediglich der AppBar-Back-Button (`Icon.Back`).

### Trainings-spezifisch

- **Stick-Pip-Progress**: 6 farbige Pillen statt klassischer Step-Indicator. Encodet Stick-Status in einer Farbe pro Pill.
- **Remaining-Block** ist permanent sichtbar — wichtigste Info beim Mid-Stick-Entscheid.
- **Phasen-basierte UI**: 8m, Feld, König, Heli werden je nach Game-State sichtbar / unsichtbar (siehe Logik unten). Im Flutter ist das als explizite `FinisseurPhase` (field / base / king / awaitingContinueDecision) State-Machine umgesetzt. JSX leitet alles aus `eightMPossible`, `kingPossible`, `lastStick`, `allDown` ab.
- **Strafkubb-Block**: nur Stock 1, nur wenn `config.base > 0`, nicht im Heli-Mode. Zwei separate Würfe (1× / 2×), Summe ≤ `config.base`.
- **King-Detail erweitert**: Position (oben / unten) + Outcome (Treffer / verfehlt). Standard Position bei Toggle-On: `oben`.
- **Heli-Mode**: Schliesst alle anderen Eingaben aus für den Stock. Andere Buttons bleiben sichtbar aber `disabled` (opacity 0.35, `pointer-events: none`).

### Logik-Constraints (aus JSX-Source)

- `eightMPossible = remBaseBefore > 0` (Basis ist noch vorhanden)
- `kingPossible = (allDown || lastStick) && !stick.heli` (alle Kubbs sind weg ODER es ist Stock 6; nicht beim Heli)
- `fieldMaxThisStick = remFieldBefore` (kann nicht mehr Feldkubbs umwerfen als noch stehen)
- `penalty1.max = config.base - penalty2` (Cross-Constraint)
- `penalty2.max = config.base - penalty1`

## Komponenten-Inventar

- `FinisseurStickScreen` — Top-Level
- `PenaltyThrowRow` (lokal) — eine Strafkubb-Wurf-Reihe
- `Toggle` (lokal) — 8m / Heli / König-Toggle-Card
- `Segmented` (lokal) — Pill-Group für Position und Outcome
- `AppBar` (aus `shared.jsx`)

Flutter:
- `FinisseurStickScreen` (`ConsumerWidget`)
- `_PhaseProgress` (private, kapselt PipProgress + Verlängerungs-Badge)
- `_RemainingBlock` + `_Cell` (private)
- `_ContinueDecisionBlock` (private — gibt es im Design nicht!)
- aus `widgets/finisseur_inputs.dart`:
  - `FinisseurFieldChips` (Big-Chip-Grid)
  - `FinisseurToggleGrid` + `_Toggle`
  - `FinisseurBasePhasePad` + `_BasePadButton` (gibt es im Design nicht — eigene Base-Phase)
  - `FinisseurPenaltyBlock` + `_PenaltyRow` + `_NumChip`
  - `FinisseurKingDetail` + `_KingRow` + `_SegBtn`
- `PipProgress` (eigenständig in `widgets/pip_progress.dart`)

## Interaktions-Pattern

- **1-Tap-Eingabe pro Sub-Entscheidung**: Field-Hits sind Chips 0..N, 8m/Heli/König sind Toggles, Strafkubbs sind Chips 0..base. Kein Mode-Switch nötig.
- **Heli-Exclusive**: Tap auf Heli-Toggle resettet `field=0, eightM=false, p1=0, p2=0, king=null` für diesen Stock. Andere Buttons bleiben sichtbar aber disabled. Im Flutter ähnlich, plus eigenes "Base-Phase-Pad" mit Hit / Miss / Heli statt 8m-Toggle.
- **King-Tap**: setzt `king = { hit: true, style: 'oben' }`. King-Detail-Card erscheint und kann beide Felder ändern.
- **Next-Button**:
  - Im JSX: bei `current < 5` → `setCurrent(current+1)`, beim letzten → `onFinish(sticks)`
  - Flutter komplexer: `advance()` persistiert Stick in drift via `FinisseurRepository`, transitioniert Phase. Kann zu `done`, `carryOn` oder `needsContinueDecision` führen (Continue-beyond-Sticks-Setting).
- **Back-Pfad**:
  - Design: nur `onBack`-Prop (Routing nach oben delegiert)
  - Flutter: differenziert
    - Past Stock 1 → `rollbackLastStick()` (undo letzten Commit, keine Confirm)
    - Stock 1 untouched → `abortAndDelete()` (silently)
    - Stock 1 mit Edits → `FinisseurAbortConfirm`-Dialog vor Abort
- **Doppel-Tap-Race**: `ActiveFinisseurNotifier._serialize` lockt jede mutierende Operation, `isLocked` exponiert.
- **Continue-beyond-Sticks**: Flutter-only Feature (`AppSettings.continueBeyondSticks`). Nach Stock 6 ohne Sieg fragt UI ob weiterspielen. Kein Pendant im Design.
- **Loading / Empty / Error**:
  - Loading: `CircularProgressIndicator` solange `state == null || settings == null`
  - Empty: nicht möglich — Session existiert immer wenn Screen sichtbar
  - Error: nicht modelliert

## Accessibility-Hinweise

- **Tap-Targets**:
  - BigChips (Field-Hits): 60px hoch — OK
  - Toggle-Cards: 64px hoch — OK
  - Penalty-Chips: 44x44px — knapp **unter** WCAG 48dp-Floor. Outdoor mit Handschuh problematisch. Empfehlung: in Flutter auf min 48px hochziehen.
  - Segmented-Btn: 36px hoch — **unter** WCAG-Floor. Auch in Flutter (`_SegBtn`) auditen.
  - Step-Buttons (Steppers gibt's hier nicht, nur Chips)
- **Kontrast**:
  - `king` #C89B3D auf weissem `bgRaised` → ~2.8:1, **unter** WCAG-AA 4.5. Wird primär als Border/Akzent gebraucht (King-Detail-Border 2px), nicht für Text — akzeptabel.
  - `heli` #C08A33 auf weissem BG → ~3.3:1, **unter** AA für Text. Heli-Toggle-Text ist `stone900` auf `wood400`-BG → OK (5.5:1).
  - `penalty` #8A1F3D auf weiss → 7:1, OK.
  - Aktive Field-Chips: `stone900` BG + `chalk50` Text → >15:1, top.
- **Sun-Readability**: Display-Sizes (32px Remaining, 24px Field-Chip, 36px Stepper-Value im Config) helfen.
- **Pip-Farben** sind die einzige Statusinfo der Stick-Reihe. Bei Farbenblindheit Rot-Grün schwierig (`done` meadow500 vs `penalty` dunkelrot vs `king` gold). Empfehlung: zusätzliches Icon oder Pattern pro Status (in Flutter PipProgress dokumentieren).
- **Aria-Labels** im Design nicht durchgängig gesetzt. Flutter sollte Tooltips an Toggle-Cards setzen (`8m-Treffer · Wurf auf Basiskubb` usw.).

## Quality-Gate-Checkliste

- [ ] Layout-Struktur 1:1 (AppBar → Pips → Remaining → Section "Feldkubbs umgeworfen" → Toggle-Grid → Strafkubb → King-Detail → Next-Button)
- [ ] AppBar Eyebrow `Finisseur · {field}/{base}`, Title `Stock {n} / 6` mit halbtransparentem ` / 6`
- [ ] Pip-Progress 6 Pillen mit 7 Status-Farben (pending, active, done, heli, penalty, king, empty)
- [ ] Remaining-Block in `bgRaised`-Card, 2 Zellen mit Divider
- [ ] Remaining-Werte 32px display, Feld in `tokens.primary`, Basis in `KubbTokens.wood500`
- [ ] Field-Hit-Chips `auto-fit` Grid, min 56px, 60px Höhe
- [ ] Field-Hit-Empty-Hint "keine Feldkubbs mehr — direkt 8m oder König"
- [ ] 8m-Toggle nur sichtbar wenn `remBaseBefore > 0`
- [ ] König-Toggle nur sichtbar wenn `(allDown || lastStick) && !heli`
- [ ] Heli-Toggle resettet alle anderen Outcome-Daten des Sticks
- [ ] Strafkubb-Block nur Stock 1, nur wenn `base > 0`, nicht im Heli-Mode
- [ ] Strafkubb-Cross-Constraint: `p1 + p2 <= config.base`
- [ ] Strafkubb-Chips ≥ 48dp Tap-Target (Audit)
- [ ] King-Detail mit Position (oben/unten) und Outcome (Treffer/verfehlt) Segmented
- [ ] King-Detail-Card hat 2px Border in `KubbTokens.king`
- [ ] Segmented-Buttons ≥ 48dp (aktuell 36 — Audit)
- [ ] Next-Button "Stock N+1" oder "Session abschliessen" beim letzten — primary 60px
- [ ] In-Flight-Lock im Notifier verhindert Doppel-Tap-Race
- [ ] Back: Past Stock 1 → undo letzten Commit, Stock 1 → Abort (mit Confirm bei Edits)
- [ ] Continue-beyond-Sticks-Flow (Flutter-Erweiterung) zeigt eigenen Block mit Continue / Aufgeben
- [ ] i18n: `finisseurStickEyebrow`, `finisseurStickTitle`, `finisseurStickNextStock`, `finisseurStickFinish`, `finisseurStickFinishStick`, `finisseurStickRemainingField`, `finisseurStickRemainingBase`, `continueDecisionTitle/Body/Continue/GiveUp` aus AppLocalizations
- [ ] Domain-Begriffe deutsch: "Stock", "Feldkubbs", "Basiskubbs", "Strafkubb", "Helikopter", "Königswurf", "Treffer", "verfehlt", "Verlängerung"
- [ ] Pip-Status zusätzlich zu Farbe via Pattern / Icon (Accessibility)
- [ ] Heli-Sub-Text "ungültig, Stock weg"
- [ ] 8m-Sub-Text "Wurf auf Basiskubb"
- [ ] Persistence: jeder `advance()` schreibt Stick in drift via `FinisseurRepository.recordStick`

## Bekannte Abweichungen (Flutter aktuell vs. Design)

1. **Phasen-State-Machine**: Flutter splittet die Eingabe in explizite Phasen (`FinisseurPhase.field / base / king / awaitingContinueDecision`). Design hat das alles auf einem Screen, gesteuert über bedingte Sichtbarkeit der 8m/König-Toggles. Flutter ist konzeptuell sauberer, aber UI-Pfad anders:
   - **Design**: 8m-Toggle und Königs-Toggle parallel sichtbar wenn jeweils möglich.
   - **Flutter**: Solange Feldkubbs übrig → Field-Phase mit BigChips + Toggle-Grid (8m + Heli + ggf. King). Sobald Feld leer → eigene Base-Phase mit `FinisseurBasePhasePad` (Hit / Miss / Heli als 3 grosse Pads). Dann ggf. eigene King-Phase.
   - **Konsequenz**: Flutter macht aus dem "8m-Treffer-Toggle" einen eigenen Hit / Miss / Heli-Pad-Screen. Das **weicht stark vom Design ab** — der User sieht in der Base-Phase keine Field-Chips mehr.
2. **Continue-beyond-Sticks-Decision-Block**: Im Design nicht vorhanden. Flutter fragt nach Stock 6 ob weitergespielt werden soll (mit eigenem `_ContinueDecisionBlock` in `bgRaised`-Card mit `wood400` Border, Continue + Give-Up Buttons). Setting-gated über `AppSettings.continueBeyondSticks`.
3. **`Long-Dubbie`-Tracking**: Flutter hat ein `settings.longDubbieTracking` und einen `longDubbiePossible` Branch im Toggle-Grid. Im Design nicht modelliert.
4. **King-Default-Position**: Design setzt beim Toggle-On `style: 'oben'` mit `hit: true`. Flutter setzt analog `KingResult(hit: true, position: KingPosition.oben)` (Default-Konstruktor). OK.
5. **Penalty-Empty-State**: Design zeigt "nicht mehr möglich (Summe ≤ …)" Text, der einen Bug-Trail hat (`{value > 0 ? '…' : '…'}` rendert immer "…"). Flutter sollte das korrigieren oder weglassen.
6. **Sticks > 6**: Flutter erlaubt Verlängerung. Design hardcoded auf 6 (`current === 5` → `onFinish`).
7. **Rollback statt Edit-Vorgang**: Design hat keinen Undo-Mechanismus für bereits gespielte Sticks. Flutter erlaubt `rollbackLastStick()` via Back-Button — UI-Pattern bewusst anders.
8. **Strafkubb-Konditional in Flutter**: aktuell nur im `inFieldPhase` sichtbar (`state.currentIndex == 0 && state.base > 0 && inFieldPhase`). Design zeigt sie im Stock-1-Block parallel zum Field-Hit-Block. Konsistent.
9. **Pip-Tones in Flutter vs. Design**: Design hat 7 Tones (pending, active, done, heli, penalty, king, empty). Flutter `PipProgress` muss alle 7 abdecken — Audit nötig.
10. **AppBar in Design via `shared.AppBar`**, Flutter via `KubbAppBar` — konsistent.
11. **Section-Meta-Anzeige**: Im Design zeigt der Field-Section-Head `0–${fieldMaxThisStick}`. Flutter `FinisseurFieldChips` muss das identisch rendern.
12. **King-Detail-Border**: Design `inset 0 0 0 2px var(--bk-king)`. Flutter macht das via `Border.all(color: KubbTokens.king, width: 2)` — OK.
13. **Sheet-/Modal-Pattern**: Der Stick-Screen hat keine Sheets, alles inline. Flutter ebenso.
