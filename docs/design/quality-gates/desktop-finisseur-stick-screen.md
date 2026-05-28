# Quality-Gate: FinisseurStick (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/FinisseurStickScreen.jsx`
**Flutter-Pendant**: Finisseur-Stick-Screen als Phone (`lib/features/training/.../finisseur_stick`) — Desktop-3-Spalten-Layout FEHLT
**Tablet/Desktop-Breakpoints**: ab 900 dp Two-Column (Sticks + Center), ab 1280 dp Three-Column mit Pitch-Preview rechts
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (3 Spalten)
- TopBar: Eyebrow `Finisseur · 7/3 · live`, Title `Stock N von 6`, Subtitle mit Aggregat (`X von 7 Feldkubbs umgeworfen · Y von 3 Basis getroffen`). Right: Vorheriger / Pause / Stop.
- Body Split (`grid-template-columns: 340px 1fr 320px`, gap 18, `padding: 24px 32px 32px`).
- **LEFT** (Aside, 340 dp):
  - Card "6 Stoecke" — Card-Head Eyebrow + Round-Tag (`Halbsatz #4`). Liste aus 6 Stick-Rows (Idx mono + farbiger Vertical-Pip 8 × 36 + Body mit Tag (aktiv/fertig/offen) + Summary-Text + Chevron). Aktiv-Row: Sunken-BG + inset Stone-900 Border.
  - Card "Verbleibend" — 2-Spalten-Grid: Feldkubbs / Basis, jeweils Big 36 px + Max-Sub `/X`. Basis-Color Wood-500.
- **CENTER** (Main, Card padding 22):
  - Center-Head: Eyebrow `Aktiver Stock` + Title `Stock N · was passiert?` 22 px + kbd-Hints rechts (`0`…`N` Feldkubbs / `H` Heli / `K` Koenig).
  - **Sektion Feldkubbs**: Sek-Head (Label + Meta `0 – N`). Wenn `fieldMaxThisStick === 0` → Empty-Card. Sonst Field-Row Grid `repeat(auto-fill, minmax(86px, 1fr))` mit Chips (n-Big 32 px + "Kubb/s"-Label). Aktiv-Chip Stone-900.
  - **Sektion Zusaetzliche Outcomes**: Toggle-Grid `repeat(auto-fit, minmax(180px, 1fr))` mit conditional Toggles:
    - 8m-Treffer (Wood-Tone, nur wenn `eightMPossible`).
    - Helikopter (Heli-Tone, immer).
    - Koenigswurf (King-Tone, nur wenn `kingPossible` — alle Kubbs gefallen ODER letzter Stock).
  - **Koenig-Detail** (wenn king aktiv): Wood-50 BG + King inset Border, Head mit DIcon.King-Icon, Grid 2-Spalten Segmented (Position oben/unten + Outcome Treffer/verfehlt).
  - **Sektion Strafkubbs** (nur Stock 1): 2 PenaltyRows fuer `1x geworfen` und `2x geworfen`, mit Chip-Pickers 0..N.
  - Nav-Row: Vorheriger-Stock-Btn (Ghost) + Naechster-Stock-Btn (Primary) / am Ende `Halbsatz beenden`.
- **RIGHT** (Aside, 320 dp):
  - Card "Live-Feld" — Pitch-Preview SVG (260 × 220) mit Field-Kubbs (Reihe oben), Base-Kubbs (Reihe unten), Mittellinie, Koenig zentral.
  - Card "Halbsatz-Statistik" — 5 Stat-Rows (Stoecke verwendet / Heli / Strafkubbs / Spielzeit / ∅ pro Stock).
  - Card "Tipp" — Beratender Text mit verbleibendem-Treffer-Hinweis.

### Farben
- Pip-Tones: hit Meadow-500, heli Heli-Token, penalty Penalty, king King, pending Stone-200, empty-done Stone-300.
- FieldChip Active: Stone-900 + Chalk-50.
- Toggle-On nach Tone:
  - heli: Heli-Token + Stone-900 Text.
  - king: King-Token + Stone-900 Text.
  - wood (8m): Wood-500 + weiss.
  - default: Meadow-600 + weiss.
- Toggle Inset-Border: Stone-200 (Off).
- Koenig-Detail Wood-50 BG + King-Inset-Border.
- PenChip-On: Penalty + weiss.
- Pitch-Preview: Meadow-50 BG mit Meadow-200 Border.
- Field-Kubbs Standing: Wood-400 BG mit Wood-600 Border. Knocked: Stone-300 BG mit Stone-400 Border.
- Base-Kubbs Standing: Wood-300/Wood-500. Knocked: Stone-300/Stone-400.
- Koenig: King-Token + Krone in Wood-600 Pfad.

### Typografie
- Field-ChipN 32 px ui weight 800 tabular.
- Field-ChipLbl mono 10 px uppercase.
- Toggle-Lbl 18 px display.
- Stat-Val 16 px ui weight 700.
- RemVal 36 px ui weight 800 Meadow-700.

### Spacing
- Body-Gap 18, Card-Gap 14.
- Section-Gap 18 zwischen Sektionen.
- Field-Row gap 8.
- Toggle-Grid gap 10.

### Border-Radius
- Cards 16. Field-Chips 14. Toggles 14. King-Detail 14. Pen-Chips 8. Pitch-Background 6. Pip 3.

### Shadows
- Cards Default `--kc-shadow-1`.

### Icons
- `DIcon.Undo` (Vorheriger Stock), `DIcon.Pause`, `DIcon.Stop`, `DIcon.King` (Koenig-Detail-Head), `DIcon.Chevron` (Stick-Row).

## Komponenten-Inventar

- Shared: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `CardHeader`, `DIcon`.
- Lokal:
  - `summaryText(stick)` — Helper fuer Stick-Row-Beschriftung.
  - `Toggle` (on / disabled / tone / label / sub / onClick).
  - `Segmented` (Label + value + options + onChange).
  - `PenaltyRow` (label + sub + value + max + onChange, chip-row 0..max).
  - `Stat` (label + value + mono + muted).
  - `PitchPreview` (SVG, field/base counts + downCounts + kingDown).
  - `TONE_COLOR`-Map.

**Unterschied Mobile**: Phone-Pendant zeigt vermutlich nur einen Stock auf einmal, mit Stock-Pager (Swipe) statt Liste. Pitch-Preview entweder fehlt oder als kleines Inline-Element. Stats kommen erst in der Summary. Desktop zeigt **alles parallel**: aktiver Stock + Liste aller Stoecke + Live-Pitch + Live-Stats.

**Flutter-Aequivalente**:
- `PitchPreview` → `CustomPainter` ~50 LOC (deutlich kleiner als der Match-Pitch, weil nur Feld+Basis-Kubbs ohne Strafkubbs im Feld).
- `Segmented` → Material 3 `SegmentedButton`.
- `Toggle` → `Container(InkWell)` mit Token-Backgrounds, nicht der Standard-`Switch`.
- `PenaltyRow` → `Row` mit Header + `Wrap` von ChoiceChips.

## Interaktions-Pattern

- **Stick-Click**: setzt `current` State, Center-Card rendert den gewaehlten Stick.
- **Field-Chip-Click**: `update({ field: n })` — wenn nicht Heli.
- **Toggle-Click**:
  - 8m-Toggle: `update({ eightM: !stick.eightM })`. Disabled wenn Heli.
  - Heli-Toggle: `setHeli(true)` resettet alle anderen Felder. `setHeli(false)` setzt nur `heli: false`.
  - Koenig-Toggle: `update({ king: stick.king ? null : { hit:true, style:'oben' } })`.
- **Koenig-Detail Segmented**: aendert `style` und `hit` im king-Object.
- **PenaltyRow-Chip**: setzt `p1` oder `p2` auf `n`.
- **Nav-Row**: Vorheriger/Naechster Stick wechselt `current`. Letzter Stick → `Halbsatz beenden` → Summary.
- **Keyboard-Hints** (kbd-Anzeige im Header):
  - `0`…`fieldMaxThisStick`: Field-Anzahl waehlen.
  - `H`: Heli toggle.
  - `K`: Koenig toggle.
  - Implementierung Pflicht in Flutter — aequivalente Eingabe-Effizienz.
- **Loading**: nicht relevant (lokaler State).
- **Validation**: kingPossible / eightMPossible / fieldMaxThisStick werden live aus prior-Sticks berechnet — Toggles ausblenden statt disablen wenn nicht moeglich.
- **Empty**: Live-Pitch zeigt vollstaendige Aufstellung am Anfang; "Tipp"-Card mit Anweisungstext.

## Accessibility

- **Tab-Order**: TopBar-Buttons → Stick-Liste (vertikal) → Center-Card (Field-Chips, dann Toggles, dann King-Detail wenn aktiv, dann Penalty-Chips) → Nav-Buttons → Right-Aside (Pitch + Stats + Tipp).
- **Focus-Ring**: zwingend, weil Eingabe-Screen.
- **Min-Window-Width**: 1280 dp fuer Three-Column. 900 – 1279 dp: Two-Column (Sticks + Center), Pitch + Stats als untere Sektion oder ausgeblendet. Unter 900 dp: Phone-Layout.
- **Live-Region**: Aggregat-Updates (z.B. `5 von 7 Feldkubbs umgeworfen`) sollten Screen-Reader als `aria-live: polite` ankuendigen.
- **Keyboard-Hints visualisiert**: kbd-Elemente sind nett, aber sollten zusaetzlich als `Tooltip` ueber den Chips/Buttons verfuegbar sein.
- **Disabled-Toggles**: opacity 0.35 + `pointerEvents: none` — fuer Screen-Reader sollte `aria-disabled` gesetzt werden.

## Quality-Gate-Checkliste

- [ ] Three-Column-Split 340 / flex / 320, Gap 18.
- [ ] Stick-Liste mit 6 Rows + farbigem Pip + Body-Text + Tag (aktiv/fertig/offen).
- [ ] Verbleibend-Card 2-Spalten (Feldkubbs Meadow-700 / Basis Wood-500).
- [ ] Center-Card mit Eyebrow + Title 22 px + kbd-Hints.
- [ ] Field-Chips Grid auto-fill, Active Stone-900, Disabled wenn Heli.
- [ ] Toggle-Grid mit Token-Tone-Backgrounds, conditional sichtbar.
- [ ] Koenig-Detail Wood-50 BG mit Segmented-Choices.
- [ ] PenaltyRows nur in Stock 1, Chip-Picker 0..N.
- [ ] Nav-Row mit Vorheriger + Naechster, letzter Stock → Beenden.
- [ ] Pitch-Preview SVG mit Field+Basis-Kubbs, Mittellinie, Koenig.
- [ ] Halbsatz-Statistik 5 Rows.
- [ ] Tipp-Card mit Berechnungstext.
- [ ] Keyboard-Bindings (`0`..N, `H`, `K`).

## Implementations-Hinweise fuer Flutter

- **Domain-Logik**: existiert bereits in `kubb_domain` (Finisseur-State-Machine, pure functions). Desktop-Screen ist nur UI auf bestehendem State.
- **State**: `finisseurSessionControllerProvider` (existiert in Phone-App). `current`-Stick-State lokal in Desktop-View (`StateProvider<int>` reicht).
- **PitchPreview**: `CustomPainter`, ~50 LOC. Parameter: `field`, `base`, `fieldDown`, `baseDown`, `kingDown`.
- **Layout**: `Row(children: [SizedBox(340, ...sticks), Expanded(card), SizedBox(320, ...right)])`.
- **Keyboard-Listener**: `Focus` mit `onKeyEvent`, mappt `0`–`9` auf field-count, `H` auf heli-toggle, `K` auf king-toggle. Muss aktive Stick-State respektieren.
- **Field-Chips**: `Wrap(spacing: 8, runSpacing: 8, children: [...chips])` oder `GridView.builder(crossAxisCount: 5)`.
- **Toggle-Component**: eigenes `KCToggle`-Widget statt Material `Switch`. Token-driven Tones.
- **Live-Aggregat**: berechnet aus `sticks` array im Provider, Center-Card abonniert via `ref.watch`.
- **Komplexitaet**: **L**. 5 – 7 Tage. Hauptaufwand: Pitch-Painter + Toggle-Widget + Keyboard + 3-Spalten-Layout. Logic ist Domain-Pure.
- **Pakete**: keine zwingend neuen.
