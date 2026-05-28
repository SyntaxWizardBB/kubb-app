# Quality-Gate: Finisseur Per-Stick Eingabe (Mobile)

**Quelle**: `docs/design/ui_kits/app/FinisseurStickScreen.jsx`
**Flutter-Pendant**: `lib/features/training/presentation/finisseur_stick_screen.dart`
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **AppBar** (via `BK.AppBar`): Eyebrow `Finisseur · {field}/{base}`, Title `Stock {current+1} / 6` (Slash-Teil in opacity 0.5), Back-Button.
2. **Stick-Progress-Pips**: 6 horizontale Pips (Width gleich verteilt, max 48 each, Height 6, gap 8). Farbtoenung pro Stick je Outcome:
   - `pending` (zukuenftig): stone-200
   - `active` (aktueller Stick): stone-900
   - `done`: meadow-500
   - `heli`: heli (wood-400)
   - `penalty`: penalty (#8A1F3D)
   - `king`: king (#C89B3D)
   - `empty`: stone-200
3. **Remaining-Block** (Inset-Card): 2 Spalten, jeweils Label (uppercase 11px) + Value (Display 32px `tabular-nums`):
   - Feldkubbs uebrig (Default-Farbe `meadow-600`)
   - Basiskubbs uebrig (Farbe `wood-500`)
   - Trennlinie 1px in `line` zwischen den Spalten.
4. **Feldkubbs-Section**: Eyebrow + Range-Meta (`0–{fieldMaxThisStick}`). Big-Row mit Chips 0..max (Grid auto-fit minmax 56px). Aktiver Chip stone-900 + chalk-50. Wenn `fieldMaxThisStick === 0`: Empty-Text "keine Feldkubbs mehr — direkt 8m oder Koenig".
5. **Toggle-Grid** (2 Spalten):
   - **8m-Treffer** (nur wenn `remBaseBefore > 0`): "Wurf auf Basiskubb". Tone: meadow-600 wenn on.
   - **Helikopter**: "ungueltig, Stock weg". Tone: heli. Setzt andere Felder zurueck.
   - **Koenigswurf** (nur wenn `kingPossible`): "am Ende" oder Detail. Tone: king.
6. **Strafkubb-Section** (nur erster Stock, nicht bei Heli, base > 0): zwei `PenaltyThrowRow`-Bloecke:
   - "1× geworfen — erster Strafkubb-Wurf"
   - "2× geworfen — zweiter Strafkubb-Wurf"
   - Jeder zeigt Readout `{v} / {max}` und Chip-Row 0..max. Aktiver Chip: `penalty` (rot-dunkel).
7. **King-Detail-Card** (nur wenn `king` gesetzt): Inset-Card mit king-Inset-Border, zwei Zeilen mit Segmented-Controls:
   - Position: oben / unten
   - Outcome: Treffer / verfehlt
8. **Next-Button**: full-width, meadow-500, Display 18px weight 700, "Stock {n+1}" bzw. "Session abschliessen" am letzten Stock.

### Farben (Tokens)

| Element | Token |
|---|---|
| Pip-pending/empty | `--bk-stone-200` |
| Pip-active | `--bk-stone-900` |
| Pip-done | `--bk-meadow-500` |
| Pip-heli | `--bk-heli` |
| Pip-penalty | `--bk-penalty` |
| Pip-king | `--bk-king` |
| Remaining-Field-Val | `--bk-meadow-600` |
| Remaining-Base-Val | `--bk-wood-500` |
| Big-Chip-Off | `--bk-bg-raised` + inset 2px line |
| Big-Chip-On | `--bk-stone-900` |
| Toggle-Default-On | `--bk-meadow-600` (#fff text) |
| Toggle-Heli-On | `--bk-heli` (stone-900 text) |
| Toggle-King-On | `--bk-king` (stone-900 text) |
| Penalty-Chip-On | `--bk-penalty` |
| Seg-On | `--bk-stone-900` + chalk-50 |
| Next-Btn | `--bk-primary` |

### Typografie

- Section-Head: 11px weight 600 uppercase tracking 0.08em fg-muted.
- Section-Meta: Mono 10px fg-subtle.
- Big-Chip: Display 24px weight 800 `tabular-nums`.
- Remaining-Val: Display 32px weight 800 `tabular-nums`.
- Toggle-Label: Display 15px weight 700.
- Toggle-Sub: 11px opacity 0.85.
- Penalty-Throw-Label: Display 15px weight 700.
- Penalty-Throw-Sub: 11px fg-muted.
- Penalty-Throw-Readout-N: Display 22px weight 800.
- Penalty-Num-Chip: Display 18px weight 800.
- Seg-Btn: Display 13px weight 600.
- Next-Btn: Display 18px weight 700.

### Spacing

- Stick-Row: `padding 4px 16px 10px`, gap 8.
- Remaining: `margin 4px 16px 14px`, padding 10/8.
- Section: `padding 2px 16px 6px`.
- Big-Row: gap 8, padding implicit via section.
- Toggle-Grid: `padding 10px 16px 6px`, 2 cols gap 8.
- Penalty-Throw-Col: gap 10.
- Penalty-Throw: padding `10px 14px 12px`, gap 8.
- King-Detail-Card: `margin 8px 16px 0`, padding `10px 14px`, gap 8.
- Next-Btn: `margin 14px 16px 28px`, minHeight 60.

### Border-Radius

- Pips: 3
- Remaining-Card: 16
- Big-Chip: 14
- Toggle: 14
- Penalty-Throw-Card: 14
- Penalty-Num-Chip: 10
- King-Detail-Card: 14, `inset 0 0 0 2px king` als Border
- Seg-Container: 999, Inner-Btn 999
- Next-Btn: 16

### Shadows

- Keine prominenten Shadows; alles flat mit `inset` Borders.

### Icons

Keine direkten Icons in den Tap-Targets — Buttons sind text-only. AppBar-Back nutzt `Icon.Back`.

### Brand-Elemente

Keine Brand-Glyphen — funktional pure.

## Komponenten-Inventar

- `FinisseurStickScreen` — Hauptkomponente.
- `PenaltyThrowRow` — Strafkubb-Eingabezeile (Label + Sub + Readout + Chip-Row).
- `Toggle` — generischer Toggle-Button (Label + Sub, tone-Variante).
- `Segmented` — generischer Segmented-Control.
- Importiert: `BK.Icon, BK.AppBar`.

## Interaktions-Pattern

- **`sticks`-State**: Array von 6 Stick-Objekten `{ field, eightM, p1, p2, heli, king }`.
- **`current`-State**: Index des aktuellen Sticks (0..5).
- **Update-Pattern**: `update(patch)` patcht nur den aktuellen Stick.
- **Heli setzen**: setzt alles andere zurueck (`field:0, eightM:false, p1:0, p2:0, king:null`).
- **Field-Max-Berechnung**: `fieldMaxThisStick = remFieldBefore` (remaining-Field vor diesem Stick, ohne aktuelles Update).
- **`eightMPossible`**: `remBaseBefore > 0`.
- **`kingPossible`**: `(allDown || lastStick) && !heli`. `allDown = fieldDownIfApplied >= field && baseDownIfApplied >= base`.
- **`PenaltyThrowRow`**:
  - p1: max ist `max(0, base - p2)`
  - p2: max ist `max(0, base - p1)`
  - Beide zusammen <= base.
- **King-Detail**: bei `king` gesetzt, kann Position (oben/unten) und Outcome (Treffer/verfehlt) gewaehlt werden.
- **`next()`**: `current < 5` → naechster Stick; sonst `onFinish(sticks)`.

### Loading / Error / Empty-States

- Keine async-States.
- Empty-Hinweis "keine Feldkubbs mehr" wenn `fieldMaxThisStick === 0`.
- Penalty-Empty wenn `max === 0`.

### Spezifisch fuer diesen Screen

- **Strafkubb-Doppelwurf**: NEU im Spec. Strafkubbs sind 2 Wuerfe (`1×` und `2×`), jeder kann mehrere Strafkubbs umwerfen. Summe <= base.
- **Strafkubbs nur am ersten Stock**: Spec sagt "Strafkubbs aus dem letzten Halbsatz werden zu Beginn gesetzt". Konsequenz: ab Stock 2 erscheinen die Penalty-Rows nicht mehr.
- **Helikopter blendet andere NICHT aus**, deaktiviert sie aber (Disabled-Style mit `opacity 0.35, pointerEvents none`).
- **Koenigswurf erscheint nur** wenn (a) letzter Stock oder (b) alle Kubbs gefallen.
- **King-Detail-Box** erscheint inline unter dem Toggle-Grid, mit `box-shadow: inset 0 0 0 2px var(--bk-king)` als deutliches visuelles Marker.

## Accessibility

- AppBar-Back 48x48 ✅.
- Big-Chips: 60dp hoch ✅.
- Toggle-Buttons: 64dp ✅.
- Penalty-Num-Chip: 44dp — **knapp unter 48dp Standard**, aber Spec-konform fuer "compact chips".
- Seg-Btn: 36dp — **unter 48dp**. Problematisch fuer Touch — Flutter sollte das aufstocken.
- Tabular-Nums auf allen Werten ✅.

## Quality-Gate-Checkliste

- [x] Tap-Logik (`field`, `eightM`, `heli`, `penalty`, `king`) dokumentiert.
- [x] Constraints (p1+p2 <= base, kingPossible-Trigger) explizit.
- [x] Pip-Toenung pro Outcome konsistent.
- [ ] **Seg-Btn 36dp < 48dp** — Accessibility-Problem.
- [ ] **Penalty-Num-Chip 44dp < 48dp** — knapp, aber pragmatisch in compact-Layout.
- [x] Heli setzt andere Werte zurueck (State-Disziplin).
- [x] Tabular-Nums.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Strafkubb-Doppelwurf-Pattern** (p1, p2 mit Sum <= base) ist neu — pruefen, ob Flutter das bereits so modelliert (`packages/kubb_domain/lib/src/finisseur/`).
2. **King-Detail-Card mit Segmented-Controls**: Flutter sollte `Card` mit `SegmentedButton` nutzen (Material 3).
3. **Pip-Progress-Row**: Flutter koennte `Row` mit `Expanded`-Children und farbigem `Container` realisieren — Detail-Tones (heli, penalty, king) explizit mappen.
4. **`eightMPossible` und `kingPossible` als conditional UI**: gut fuer Flutter via `if (...) Toggle(...)` direkt im Build-Tree.
5. **`current === 5`** triggert "Session abschliessen" am Next-Btn-Label. Flutter sollte denselben Text-Switch haben.
6. **Disabled-State** auf Toggles und Big-Chips bei `heli`: opacity 0.35 + pointerEvents none. Flutter: `IgnorePointer` + `Opacity`.
