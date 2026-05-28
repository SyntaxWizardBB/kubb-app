# Quality-Gate: Finisseur-Konfiguration

**Quelle**: docs/design/ui_kits/app/FinisseurConfigScreen.jsx (`window.FinisseurConfigScreen`)
**Flutter-Pendant**: lib/features/training/presentation/finisseur_config_screen.dart
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (top-down)

1. **Topbar** (inline, nicht der `shared.AppBar` — der JSX baut die Topbar selber)
   - Back-Icon links (48x48)
   - Title-Stack zentriert: Eyebrow `Finisseur` (uppercase, 11px), darunter `Konfiguration` (20px display, weight 700)
   - Rechter Slot leer (48px Spacer)
2. **Preview-Block** in `bgRaised`-Card, 16px Margin seitlich, 14px innen
   - Reihe 1: Feldkubbs als kleine Holzklötzchen (`14x24`, `wood400` Body, `wood600` Top-2px-Border, `radiusSm` 2px)
   - Pitch-Line: 80% Breite, 2px hoch, `lineStrong`
   - Reihe 2: Basiskubbs als grössere Holzklötzchen (`18x32`, `wood300` Body, `wood500` Top-2px-Border)
   - Preview-Label: `{field} / {base}  ·  6 Stöcke` (display 18px weight 700, `fgMuted`)
3. **Stepper Feldkubbs** (label "Feldkubbs (eingeworfen)", Range `0..10`)
   - Header-Zeile: Label uppercase 11px + Range mono 11px rechts
   - Stepper-Reihe: 64px Minus-Button | flexibler Wert-Container (64px hoch) | 64px Plus-Button
   - Wert-Container: `bgRaised`, `radiusXl` (14px im Design), 2px inset Border in `meadow500` (primary)
   - Wert-Text: display 36px, weight 800, tabular-nums
4. **Stepper Basiskubbs** (label `Basiskubbs · max ${maxBase}`, Range `0..maxBase`)
   - Identisches Layout wie oben, aber `accent="wood"` → Border `wood400` statt `meadow500`
5. **Constraint-Note**: kleine mono-spaced Zeile "Total maximal 10 Kubbs · Basis maximal 5. Aktuell **<sum> / 10**." (11px `fgMuted`)
6. **Preset-Block**
   - Header: "PRESETS" eyebrow + optional Save-Pill rechts (nur wenn aktuelle Wert-Kombination noch nicht als Preset existiert)
   - Preset-Reihe: wrapping Chips, jeweils mit Label + Ratio (Preset-Chip 48px Mindesthöhe, 14px Radius). User-Presets haben ein x-Badge oben rechts (22x22 Circle in `stone900`) zum Löschen.
   - Built-in: Standard 7/3, 5/5, 10/0, Spät 3/5
7. **Start-Button** "Finisseur starten" — primary, 60px hoch, `radiusXl` 16px, font 18px weight 700, am Screen-Ende mit `margin-top: auto`
8. **SavePresetSheet** (modal, Bottom-Sheet): kommt hoch wenn aktuelle Werte gespeichert werden sollen
   - Grabber, Eyebrow "Preset speichern" + `{f}/{b}` als Titel
   - Name-Input mit Placeholder `z. B. Heim-Setup`
   - Zwei Buttons (Abbrechen / Speichern) als 2-Spalten-Grid

### Farben (aus Tokens)

| Verwendung | CSS-Token | KubbTokens |
|---|---|---|
| Screen-Hintergrund | `--bk-bg` | `tokens.bg` |
| Preview-Card | `--bk-bg-raised` | `tokens.bgRaised` |
| Feldkubb-Body | `--bk-wood-400` | `KubbTokens.wood400` (#C08A33) |
| Feldkubb-Top-Border | `--bk-wood-600` | `KubbTokens.wood600` (#80561C) |
| Basiskubb-Body | `--bk-wood-300` | `KubbTokens.wood300` (#D6AB57) |
| Basiskubb-Top-Border | `--bk-wood-500` | `KubbTokens.wood500` (#A16F24) |
| Pitch-Line | `--bk-line-strong` | `tokens.lineStrong` |
| Stepper-Border Feld | `--bk-meadow-500` | `tokens.primary` (light: meadow500) |
| Stepper-Border Basis | `--bk-wood-400` | `KubbTokens.wood400` |
| Step-Button Border | `--bk-line` | `tokens.line` |
| Preset-Active-Background | `--bk-stone-900` | `KubbTokens.stone900` |
| Preset-Active-Text | `--bk-chalk-50` | `KubbTokens.chalk50` |
| Preset-Idle-Border | `--bk-line` | `tokens.line` |
| Save-Pill Border | `--bk-line-strong` | `tokens.lineStrong` |
| Start-Button-BG | `--bk-primary` | `tokens.primary` |
| Start-Button-Text | `--bk-on-primary` | `tokens.onPrimary` |
| Sheet-Input-Border | `--bk-line-strong` | `tokens.lineStrong` |

### Typografie

| Bereich | Font | Grösse | Weight | Sonderregeln |
|---|---|---|---|---|
| Topbar Eyebrow | body | 11px | 600 | uppercase, letter-spacing 0.08em |
| Topbar Name "Konfiguration" | display | 20px | 700 | letter-spacing -0.02em |
| Preview-Label "7 / 3 · 6 Stöcke" | display | 18px | 700 | letter-spacing -0.02em |
| Stepper-Label | body | 11px | 600 | uppercase, letter-spacing 0.08em |
| Stepper-Range "0–10" | mono | 11px | 500 | — |
| Step-Value (grosse Zahl) | display | 36px | 800 | tabular-nums |
| Preset-Label | display | 13px | 600 | line-height 1.1 |
| Preset-Ratio "7/3" | mono | 11px | — | letter-spacing 0.04em |
| Save-Pill | display | 13px | 600 | — |
| Constraint-Note | mono | 11px | 500 | letter-spacing 0.02em |
| Start-Button | display | 18px | 700 | — |
| Sheet-Title `{f}/{b}` | display | 24px | 700 | letter-spacing -0.02em |
| Sheet-Input | body | 16px | 400 | — |
| Sheet-Save/Cancel | display | 16-17px | 700 | — |

### Spacing

- Screen-Padding-Bottom: 8px (`scroll` aktiv)
- Topbar-Padding: `54px 12px 6px` (notch-Reserve oben)
- Preview-Margin: `8px 16px 14px`, Padding `14px 16px 10px`
- Stepper-Padding: `10px 16px` (`space3`/`space4`)
- Stepper-Grid Gap: 10px
- Constraint-Note Padding: `2px 18px 6px`
- Preset-Block Padding: `4px 16px 14px`
- Preset-Reihe Gap: 8px
- Start-Button Margin: `auto 16px 28px` (Auto-Margin schiebt Button an Screen-Unterkante)
- Sheet-Padding: `10px 18px 32px`

### Border-Radius

- Preview-Card: 16px (`radiusXl`)
- Stepper-Wert + Step-Buttons: 14px (kein direkter Token, am nächsten `radiusLg`=12)
- Preset-Chip: 14px
- Save-Pill, Preset-Remove-Badge: 999px (`radiusPill`)
- Start-Button: 16px (`radiusXl`)
- Sheet-Top-Corners: 24px
- Sheet-Input: 12px (`radiusLg`)
- Kubb-Klötzchen: 2px (`radiusSm`)

### Shadows

- Keine Box-Shadows; Border-Effekte komplett via `inset 0 0 0 Xpx <color>`
- Preset-Remove-Badge: `0 1px 2px rgba(0,0,0,0.2)` — einzige Ausnahme

### Icons

| Design | Lucide-Pendant |
|---|---|
| `Icon.Back` | `LucideIcons.arrowLeft` |
| `Icon.Plus` / `Icon.Plus2` | `LucideIcons.plus` |
| `Icon.Minus` | `LucideIcons.minus` |
| `Icon.Close` (Preset-Remove + Sheet-Close) | `LucideIcons.x` |

### Trainings-spezifisch

- **Kubb-Stack-Visualisierung**: zentrale Komponente — kleine Klötzchen oben (Feld), Pitch-Line, grössere Klötzchen unten (Basis). Live-Update bei jedem Stepper-Tap.
- **Constraints**:
  - `field + base <= 10` (10 Kubbs total)
  - `base <= 5` (max 5 Basiskubbs)
  - `maxBase = min(5, 10 - field)`
- **Auto-Clamp**: erhöht der User Feldkubbs, kann das `base` nach unten klemmen. Flutter implementiert ein leicht anderes Verhalten — siehe Abweichungen.
- **Presets**: 4 built-in (Standard 7/3, 5/5, 10/0, Spät 3/5) + persistente User-Presets. Tap auf Preset setzt beide Werte gleichzeitig.
- **Save-Preset-Flow**: nur sichtbar wenn aktuelle Werte noch nicht gespeichert. Tap → Sheet → Name eingeben → Speichern.
- **6 Stöcke** ist hartcodiert im Preview-Label (Finisseur ist immer 6 Wurfstöcke pro Halbsatz).

## Komponenten-Inventar

- `FinisseurConfigScreen` — Top-Level
- `Stepper` (lokal) — Label + Range + Stepper-Reihe
- `SavePresetSheet` (lokal) — Bottom-Sheet zum Preset-Naming
- `Icon.*` (aus `shared.jsx`)
- `AppBar` aus `shared.jsx` wird **nicht** verwendet — der Screen baut die Topbar inline. Inkonsistenz zum Rest.

Flutter:
- `FinisseurConfigScreen` (`ConsumerStatefulWidget`)
- `KubbAppBar` (statt inline)
- `KubbStackPreview` (`lib/features/training/presentation/widgets/kubb_stack_preview.dart`)
- `_Stepper` (private Widget-Klasse) + `_StepBtn`

## Interaktions-Pattern

- **Stepper-Tap**: Plus / Minus inkrementieren / dekrementieren um 1, clamped auf `[min, max]`. Tap-Targets 64px hoch.
- **Field-Increment** im Design senkt `base`, wenn Total-Cap gerissen wird. Flutter implementiert "Swap" — siehe Abweichungen.
- **Preset-Tap**: setzt `(field, base)` auf Preset-Werte ohne Bestätigung.
- **Save-Pill**: erscheint nur wenn `(field, base)` nicht zu einem existierenden Preset passt. Tap → Sheet.
- **User-Preset-Remove**: x-Badge auf User-Presets (built-in haben kein Badge). Tap → sofort gelöscht, ohne Bestätigung.
- **Start-Button**: `onStart({ field, base })` triggert Session-Erstellung. Flutter ruft `ActiveFinisseurNotifier.startSession(playerId, field, base)` → routet zu `/training/finisseur/session/<id>`.
- **Empty-State**: Preset-Reihe leer nur denkbar wenn User alle eigenen Presets löscht — built-ins bleiben immer da.
- **Loading-State**: kein Loading-State im Design, weil keine Async-Daten. Flutter blockt Start-Button auf `profile == null`.
- **Error-State**: nicht modelliert.

## Accessibility-Hinweise

- Step-Buttons 64x64px — `touchComfortable`-Floor sauber gehalten.
- Preset-Chips Mindesthöhe 48px — WCAG-Touch-Floor.
- Preset-Remove-Badge nur 22x22 — **unterhalb** 48dp-Floor. Im Design `aria-label="Preset X entfernen"`, aber Tap-Target ist zu klein für Outdoor / Wurfhandschuhe. Flutter sollte das berücksichtigen (z.B. Long-Press auf Chip statt Mini-Badge, oder Edit-Mode).
- Contrast: `wood400`-Klötzchen auf `bgRaised` (chalk0/stone800) — im Light-Theme ausreichend (#C08A33 auf #FFFFFF ~ 3.8:1), im Dark-Theme `wood400` auf `stone800` knapp unter 4.5:1 — für die rein dekorative Preview akzeptabel.
- Constraint-Note ist 11px mono — am Lesbarkeits-Floor. Ist informativ, nicht kritisch.
- Aktiver Preset-Chip: `stone900`-Hintergrund mit `chalk50`-Text → hoher Kontrast (>15:1).

## Quality-Gate-Checkliste

- [ ] Layout-Struktur 1:1 (Topbar → Preview → Stepper Feld → Stepper Basis → Constraint-Note → Presets → Start-Button)
- [ ] Topbar nutzt `KubbAppBar` (Konsistenz mit Sniper/Stick-Screen) — aktuell inline im Design, Flutter sollte `KubbAppBar` verwenden
- [ ] Preview als `bgRaised`-Card mit `radiusXl` und Margin 16px
- [ ] Kubb-Klötzchen-Farben aus `KubbTokens.wood300/400/500/600`
- [ ] Pitch-Line in `lineStrong`, 2px, 80% Breite
- [ ] Preview-Label-Format `{field} / {base} · 6 Stöcke`
- [ ] Feld-Stepper Border in `tokens.primary` (meadow500)
- [ ] Basis-Stepper Border in `KubbTokens.wood400`
- [ ] Step-Buttons 64x64, `radiusXl` 14-16
- [ ] Wert-Container 64px hoch mit display 36px weight 800 tabular-nums
- [ ] Constraint-Werte: `TOTAL_MAX=10`, `BASE_HARD=5`
- [ ] Auto-Clamp bei Feld-Increment (Design) oder Swap-Verhalten (Flutter aktuell) — Verhalten dokumentiert + getestet
- [ ] Built-in Presets: Standard 7/3, 5/5, 10/0, Spät 3/5
- [ ] User-Presets persistiert (Flutter: Drift oder SharedPreferences — Design hat nur State)
- [ ] Save-Pill nur sichtbar wenn `(field, base)` kein existierendes Preset matched
- [ ] Preset-Tap setzt beide Werte synchron
- [ ] Start-Button auf 60px Höhe, `tokens.primary`
- [ ] i18n: `finisseurConfigEyebrow`, `finisseurConfigTitle`, `finisseurConfigPreviewSubtitle`, `finisseurConfigFieldLabel`, `finisseurConfigBaseLabel`, `finisseurConfigConstraint`, `finisseurConfigStartButton` aus AppLocalizations
- [ ] Domain-Begriffe deutsch: "Feldkubbs", "Basiskubbs", "Stöcke", "Finisseur", "Kubb"
- [ ] Touch-Targets: Steppers >= 64dp, Presets >= 48dp
- [ ] Constraint-Note zeigt live `field + base` und maximalen Wert
- [ ] Preset-Remove via Long-Press oder Edit-Mode (statt 22px Mini-Badge)
- [ ] SavePresetSheet als ModalBottomSheet implementiert (falls Feature in Flutter geplant)
- [ ] Back-Pfad routet zurück zum Home

## Bekannte Abweichungen (Flutter aktuell vs. Design)

1. **Topbar inline im Design vs. `KubbAppBar` in Flutter**: Design baut die Topbar selber (Back-Button + zentrierter Title-Stack + leerer rechter Slot). Flutter nutzt konsistent `KubbAppBar` — vernünftige Vereinheitlichung, kein Bug.
2. **Auto-Clamp vs. Swap bei Field-Increment**:
   - **Design** (`setFieldClamped`): erhöht Feld auf `nf`, setzt Basis auf `min(BASE_HARD, TOTAL_MAX - nf)` wenn nötig — d.h. Basis wird **abgeschnitten** wenn Feld die Total-Grenze sprengt.
   - **Flutter** (`_incField`): macht erst Plain-Increment, wenn Total-Cap gerissen wird und Basis > 0 ist, wird Basis um 1 reduziert ("Swap" Feld+1 / Basis−1).
   - **Beide Ansätze** erfüllen die Constraints, aber das visuelle Verhalten unterscheidet sich. Flutter behält "Total bleibt konstant" bei, Design lässt Total wachsen bis Cap.
3. **Presets sind ausschliesslich im JSX-State**, Flutter implementiert sie aktuell **gar nicht** (keine Preset-Chips im `FinisseurConfigScreen`). HIGH-Severity-Lücke: 4 built-in Presets + User-Presets-Save-Flow fehlen komplett.
4. **Constraint-Note**: Flutter zeigt nur `field + base` als Live-Wert. Design zeigt zusätzlich harte Caps `Total maximal 10 Kubbs · Basis maximal 5`.
5. **Stepper-Range-Label** im Header (rechts): Design zeigt `0–10` bzw. `0–<maxBase>`, Flutter zeigt `min–max` (statisch `0–_baseHardMax` für Basis, also `0–5` immer — nicht den dynamisch berechneten `maxBase`).
6. **Preview-Aspect-Ratio**: Klötzchen-Grössen exakt (`14x24` und `18x32`) sollten im `KubbStackPreview` validiert werden.
7. **Save-Preset-Sheet**: existiert in Flutter nicht. Wenn Presets implementiert werden, Sheet-Pattern muss neu gebaut werden.
8. **AppBar-Eyebrow vs. Topbar-Eyebrow**: Design hat im Topbar-Title-Stack zwei Zeilen (Eyebrow + Name). Flutter `KubbAppBar` rendert das Layout etwas anders — Audit auf Konsistenz nötig.
9. **`onBack` Verhalten**: Design routet via Prop, Flutter routet `context.go('/')` — aus Live-Config zurück zum Home. Erwartungskonform.
