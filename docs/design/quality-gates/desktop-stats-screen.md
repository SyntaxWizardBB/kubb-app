# Quality-Gate: Stats (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/StatsScreen.jsx`
**Flutter-Pendant**: Stats-Tab als Phone-Screen (`lib/features/stats/`) — Desktop-Charts/Heatmap FEHLT
**Tablet/Desktop-Breakpoints**: ab 900 dp Three-Hero-Grid + Split, ab 1280 dp Full-Width Heatmap-Cells lesbar
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur
- TopBar: Title `Deine Wurf-Konstanz`, Subtitle Aggregat-Hinweis, Buttons `Export CSV` + `Neue Session`.
- Body `padding: 20px 40px 48px`, `max-width: 1280`, Layout-Gap 18.
- **Controls-Row** (`flex space-between`):
  - Tab-Row (Pill-Switcher Sniper-8m / Finisseur-6Stöcke, aktiv Stone-900).
  - Period-Row (Pill-Switcher 7t / 4w / 12w / 1j, aktiv Meadow-500).
- **Hero-Grid** (`grid-template-columns: 1.4fr 1fr 1fr`, gap 18):
  - Card 1: "Trefferrate" Big-Val 64 px Meadow-600 + Delta + BigSparkline (110 dp).
  - Card 2: "Volumen" Big-Val 64 px Fg + Mini-Grid (4 Stats: Treffer / Miss / Heli / Streak).
  - Card 3: "Konstanteste Distanz" + Note + 2 Record-Cards (Streak / Bester Tag).
- **Split** (`grid-template-columns: 1.5fr 1fr`, gap 18):
  - Linke Card: Pro-Distanz/Pro-Konfig-Tabelle (Padding 0, Card-Header in Sub-Padding):
    - Columns: Dist (oder Konfig + Ratio + optional User-Badge) / Verlauf-Bar / Rate / Trend (Pfeil + Wert) / Wuerfe oder Sessions.
    - Track-Gradient: Sniper Meadow-400→600, Finisseur Wood-300→500.
  - Rechte Side-Column:
    - Heatmap-Card: 7 Days × 14 Hours (8-22), OKLCH-basierte Color-Scale, Legend (weniger / 5 Levels / mehr).
    - Highlights-Card: 3 Highlight-Items (Streak / Sauberer 5/5 / ELO-Aufstieg) mit Icon-Tile + Title + Sub.

### Farben (Tokens)
- Hero-Big Color Tab-abhaengig: Sniper Meadow-600, Finisseur Wood-Tones in Sparkline.
- Tab-Active Stone-900. Period-Active Meadow-500.
- Trend-Color: positive Meadow-600, negative Miss.
- Track-Gradient: Sniper-Mode = `linear-gradient(90deg, --kc-meadow-400, --kc-meadow-600)`; Finisseur = `linear-gradient(90deg, --kc-wood-300, --kc-wood-500)`.
- Heatmap-Empty `--kc-stone-100`; Active `oklch(${90 - v*50}% 0.10 145)` — Meadow-Hue, dynamisch.
- Highlight-Icons:
  - Streak: Meadow-100/700 (Flame).
  - Saubere 5/5: Wood-100/500 (King).
  - ELO: Stone-900/Chalk-50 (Cup).
- User-Badge in Finisseur-Konfig-Liste: Meadow-100/700 Pill `eigen`.

### Typografie
- Hero-Big 64 px ui weight 800 tabular.
- Hero-Unit (`%`) 22 px weight 600 muted.
- Distanz-Tabelle TdRate 16 px ui weight 700 tabular.
- Heatmap-Cells aspect-ratio 1:1, kein Text.

### Spacing
- Body-Gap 18, Hero-Grid-Gap 18, Split-Gap 18.
- Table Th `8px 22px`, Td `12px 22px`.
- Heatmap-Grid `gridTemplateColumns: 28px repeat(14, 1fr)`, gap 3.

### Border-Radius
- Cards 16 (default), Hero-Mini 12, Heatmap-Cells 3, Records 10, Highlight-Icons 10, Pills 999.

### Shadows
- Cards Default `--kc-shadow-1`.

### Icons
- `DIcon.Calendar` (Export CSV), `DIcon.Plus` (Neue Session), `DIcon.Chevron` (Sortieren), `DIcon.Flame` (Streak), `DIcon.King` (Saubere 5/5), `DIcon.Cup` (ELO).

## Komponenten-Inventar

- Shared: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `CardHeader`, `DIcon`.
- Lokal:
  - `BigSparkline` (SVG 540 × 110, Tone-aware).
  - `Mini` (label + value + tone + optional unit).
  - `Record` (label + value + sub, Sunken-BG).
  - `Heatmap` (Grid + hmColor-Funktion).
- `hmColor` Funktion: OKLCH-basiert (`oklch(${90 - v*50}% 0.10 145)`), `< 0.05` → Stone-100.

**Unterschied Mobile**: Phone-Stats hat vermutlich Single-Column-Hero, kleinere Sparkline, keine Heatmap (zu klein auf Phone). Desktop fuegt Heatmap + Highlights + 3-Card-Hero hinzu.

**Flutter-Aequivalente**:
- BigSparkline → eigener `CustomPainter` (Path + Gradient-Fill + End-Dot).
- Heatmap → `GridView` mit Color-Cells, Color-Berechnung in Dart (OKLCH via `package:flutter_color` oder manuell konvertieren). Alternativ: vorberechnete Token-Reihe (`--kc-meadow-50`..`900`).
- Distanz-Tabelle → `DataTable` mit `cells` aus Token-Tiles.

## Interaktions-Pattern

- **Tab-Switch** (Sniper / Finisseur): wechselt Datenquelle + Track-Gradient + Sparkline-Tone.
- **Period-Switch** (7t / 4w / 12w / 1j): filtert Sparkline-Punkte (Slice der Trend-Reihe) und Aggregat-Werte.
- **Sortieren-Btn**: derzeit nur Demo (`Sortieren · Rate ↓`). Backlog.
- **Heatmap-Cell Hover**: zeigt Tooltip `Mo 18:00 — 64%` (im JSX als `title`-Attribut, in Flutter via `Tooltip`-Widget).
- **Export-CSV**: TopBar-Btn oeffnet CSV-Export-Modal (eigener Quality-Gate).
- **Loading**: Heatmap-Cells alle Stone-100 (Skeleton); Sparkline als Linien-Skeleton.
- **Empty**: vor 5 Sessions → "Spiel 5 Sessions fuer Statistik" (AUDIT.md §4.2).

## Accessibility

- **Tab-Order**: Export-CSV → Neue-Session → Tabs (Sniper/Finisseur) → Period (4 Buttons) → Hero-Cards (statisch) → Tabelle-Header (sortable) → Tabelle-Rows → Heatmap (Container fokussierbar?) → Highlights-Items.
- **Focus-Ring**: sichtbar auf Tab-Buttons + Period-Buttons + Tabelle-Headers.
- **Heatmap**: per Tastatur durchnavigierbar machen (jede Cell `focusable`), Screen-Reader-Label `Montag 18 Uhr 64 Prozent`.
- **Min-Window-Width**: 1024 dp fuer Hero-Grid + Heatmap. Darunter Heatmap-Cells zu klein → vertikale Variante.
- **Color-Only-Info**: Heatmap nutzt nur Farbe — Flutter-Pendant sollte alternatives Tooltip-Pattern haben.
- **Sparkline-Animation** (falls animiert): Reduced-Motion respektieren.

## Quality-Gate-Checkliste

- [ ] Tab-Switcher Sniper / Finisseur (Pill, aktiv Stone-900).
- [ ] Period-Switcher 4 Buttons (aktiv Meadow-500), filtert Daten.
- [ ] Hero-Grid 1.4 / 1 / 1, drei Cards.
- [ ] Big-Sparkline mit Gradient-Fill + Line + End-Dot, Tone wechselt mit Tab.
- [ ] Mini-Grid 2 × 2 in "Volumen"-Card.
- [ ] Record-Cards in "Konstanteste Distanz"-Card.
- [ ] Distanz-Tabelle 5 Spalten (Distanz/Konfig, Verlauf-Track, Rate, Trend, Wuerfe/Sessions).
- [ ] Track-Gradient Mode-spezifisch.
- [ ] Trend mit Pfeil (▲/▼/·).
- [ ] User-Badge `eigen` bei Finisseur-Konfig wenn user-defined.
- [ ] Heatmap 7 × 14 Cells, OKLCH-Color-Scale, Legend (weniger/mehr).
- [ ] Heatmap-Tooltip pro Cell.
- [ ] Highlights mit 3 Items + farbigen Icon-Tiles.
- [ ] Body max-width 1280.
- [ ] Empty/Loading-States behandelt.

## Implementations-Hinweise fuer Flutter

- **BigSparkline**: `CustomPainter` ~70 LOC. Tones (Meadow / Wood) via Property. Gradient-Fill via `LinearGradient(...).createShader(Rect)`.
- **Heatmap**: 
  - `GridView.count(crossAxisCount: 15)` mit 7 × 15 = 105 Cells (14 Hours + 1 Label-Cell pro Day-Row).
  - `Color`-Berechnung: OKLCH ist in Flutter nicht nativ. Optionen:
    - `package:hsluv` o.ae. fuer OKLCH-Konversion.
    - Vorberechnete Lookup-Table (z.B. `[meadow50, meadow100, ..., meadow700]` als Steps).
    - Empfehlung: **Lookup-Table mit 6 – 8 Tokens-Stufen**. Liefert deterministische Tokens und keine externe Lib-Abhaengigkeit.
  - Token-Mapping: `v < 0.05` → Stone-100; `< 0.15` → Meadow-50; `< 0.3` → Meadow-100; `< 0.45` → Meadow-200; `< 0.6` → Meadow-300; `< 0.75` → Meadow-400; `< 0.9` → Meadow-500; sonst Meadow-600.
- **Distanz-Tabelle**: `DataTable` (Material) mit Custom-Cells fuer Track-Bar (via `LinearProgressIndicator` + Theme-Override).
- **State**: `statsAggregateProvider(family: (mode, period))` muss existieren oder gebaut werden. Domain ist im `kubb_domain`-Package (Aggregations sind pure functions).
- **Pakete**: keine zwingend neuen. OKLCH-Lib optional (siehe oben).
- **Komplexitaet**: **L**. 5 – 7 Tage. Hauptaufwand: Heatmap + Sparkline-Painter + Tabelle. Logik ist Domain-Pure und gut testbar.
