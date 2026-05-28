# Quality-Gate: Tournament (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/TournamentScreen.jsx`
**Flutter-Pendant**: Tournament-Liste + Detail + Standings + Bracket-Sub-Tabs als Phone-Screens (`lib/features/tournament/`) — Desktop-Master/Detail FEHLT
**Tablet/Desktop-Breakpoints**: ab 900 dp Master/Detail (380 dp / flex); ab 1280 dp Bracket horizontal sichtbar ohne Scroll
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (Master/Detail)
- TopBar: Eyebrow `Turniere · Saison 2025`, Title `Tour & Liga`, Subtitle + `Suchen` + `Turnier hosten` Buttons.
- Body Split (`grid-template-columns: 380px 1fr`, gap 20, `padding: 24px 32px 32px`).
- **LEFT** (Aside, 380 dp, `overflow-y: auto`, max-height `calc(100vh - 220px)`):
  - Filter-Row: 4 Pill-Chips (Alle / Anmelden / Live / Archiv), aktiv = `--kc-stone-900`.
  - Tournament-Tiles (Card-aehnlich, padding `14px 16px`, `border-radius: 14`, `box-shadow: inset 0 0 0 1.5px transparent`):
    - Aktiv: inset Meadow-500 Border.
    - Tile-Head: When (mono) + StatusTag (Anstehend/Anmeldung/LIVE/Archiv mit Token-Tones).
    - Tile-Name: 18 px display weight 700.
    - Tile-Sub: Calendar-Icon + Date + Trenner + City + Teams.
    - Optional: Foot-Registered (Green-Dot + Role) oder Foot-Result (`Ergebnis: 3. Rang`).
- **RIGHT** (Main):
  - **Hero-Card** (padding `22px 26px`, `border-radius: 18`, `box-shadow: --kc-shadow-1`, `background: --kc-bg-raised`):
    - Logo 88 × 88 in Meadow-50 Tile mit Meadow-100 Border.
    - Eyebrow (LIVE / ARCHIVIERT / ANGEMELDET / ANMELDUNG OFFEN) mit optional Red-Live-Dot.
    - Title 36 px display.
    - Hero-Meta-Row: 4 Meta-Items (Datum / Ort / Format / Teams) als mono-Label + ui-Value.
    - Hero-Actions (Column, right-aligned): Primary `Anmelden` / `Match oeffnen` / `Rueckblick`, plus Ghost `Zum Kalender`.
  - **Sub-Tabs** (`border-bottom: 1px solid --kc-line`): Tabelle / Bracket / Mein Match / Spielplan / Regeln. Aktiv = `--kc-fg` Text + Stone-900 Border-Bottom 2 px.
  - **Tab-Content** (eine Card pro Tab):
    - `Standings`: Tabelle 7 Spalten (# / Team / S / N / Diff / Form / Pkt), You-Row Meadow-50 BG, Rank-Bubble (Top-3 in Wood-400).
    - `BracketView`: horizontale Spalten (`overflow-x: auto`), pro Runde mehrere Matches mit zwei Slots + Score. Finale-Card in Wood-100.
    - `MyMatchPanel`: grosser Match-Info-Block mit Avatar-Score-Layout + Match-Note + 2 Actions (Lobby oeffnen / Aufstellung wechseln).
    - `SchedulePanel`: Liste aus Schedule-Rows (Zeit / Round / Court / Teams / Score / Status), You-Rows Meadow-50, Naechstes-Match Wood-100 BG + Wood-500 Left-Border.
    - `RulesPanel`: einfache `<ul>` mit 6 Regeln, fett-formatierte Labels.

### Farben (Tokens)
- StatusTag Tones: upcoming (Meadow-100/700), open (Wood-100/600), live (Stone-900/Chalk-50), done (Stone-100/Fg-Muted).
- Active Tile: inset `--kc-meadow-500` Border.
- Hero-Logo: Meadow-50 BG.
- Live-Dot: `--kc-miss` + Box-Shadow Glow.
- Standings Rank-Bubble Top-3: `--kc-wood-400` BG, weiss.
- Diff-Color: positive Meadow-600, negative Miss, null Fg-Muted.
- Bracket-Final: Wood-100 BG mit Wood-400 inset Border.
- Schedule Naechstes: Wood-100 BG + Wood-500 left-border (4 px inset).

### Typografie
- Hero-Title 36 px display, opsz 72.
- Tile-Name 18 px display.
- Standings Pts-Cell 18 px ui weight 800 tabular.
- BigSparkline not used here.
- Schedule-Vs: 11 px mono.
- Match-TeamScore: 48 px ui weight 800.

### Spacing
- Split-Gap 20, Body-Padding `24px 32px 32px`.
- Tile-Gap 8, Tile-Padding `14px 16px`.
- Hero-Padding `22px 26px`, Hero-Meta-Gap 28.
- Sub-Tabs gap 0 (Bottom-Border Trenner).
- Standings Th-Padding `8px 18px`, Td-Padding `12px 18px`.
- Bracket-Col gap 24 horizontal, gap 14 vertikal.

### Border-Radius
- Hero 18, Tiles 14, Status-Tag 4, Rank-Bubble 999, Pills 999, Bracket-Match 10, Match-Avatar 14, Schedule rows kein eigener Radius.

### Shadows
- Hero-Card `--kc-shadow-1`, Tiles ohne Shadow (Border-Only-Active-State).

### Icons
- `DIcon.Search` (Suchen), `DIcon.Plus` (Turnier hosten / Anmelden), `DIcon.Calendar` (Zum Kalender / Tile-Calendar), `DIcon.Chevron` (Rueckblick), `DIcon.Target` (Match-Lobby).

## Komponenten-Inventar

- Shared: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `CardHeader`, `DIcon`.
- Lokal:
  - `StatusTag` (4 Tones je nach Status).
  - `Meta` (label + value).
  - `Standings` (Table mit 7 Spalten).
  - `BracketView` (horizontale Bracket-Visualisierung).
  - `MyMatchPanel` (next match info).
  - `SchedulePanel` (gesamte Match-Liste).
  - `RulesPanel` (Regel-Liste basierend auf `format`).

**Unterschied Mobile**: Mobile-`TournamentScreen.jsx` zeigt vermutlich Liste-Only mit Detail als eigene Route (Push). Bracket eher als Modal oder eigene Page. Auf Desktop ist alles auf einem Screen sichtbar — das ist der zentrale Master/Detail-Move des Kits.

**Flutter-Aequivalente**:
- StatusTag → `Chip` mit Custom-Background.
- Standings-Table → `DataTable` (Material) oder eigene `Table`-Widget mit `Row`s. `DataTable` ist OK fuer den Anfang.
- BracketView → `CustomScrollView` mit horizontal Pager oder `SingleChildScrollView(scrollDirection: Axis.horizontal)`. Die Bracket-Linien zwischen Matches sind im JSX **nicht** gezeichnet — auf Flutter kann das via `CustomPainter` ergaenzt werden (Backlog: visuelle Verbindungslinien).

## Interaktions-Pattern

- **Tile-Click** → setzt `active`-State, Hero und Subtabs rendern das Detail.
- **Filter-Chips**: filtern die Liste (im JSX nicht implementiert, nur visuell). Provider-basierter Filter auf `tournamentListProvider`.
- **Sub-Tab-Click** → wechselt Tab-Content im Right-Panel.
- **Hero-Actions** kontext-abhaengig:
  - LIVE: `Match oeffnen`.
  - Registered + Upcoming: `Abmelden`.
  - Done: `Rueckblick oeffnen`.
  - Anmeldung offen: `Anmelden · CHF 25`.
- **MyMatchPanel** Lobby-Btn → `onRoute('match')`.
- **Suchen-Button**: oeffnet Search-Sheet (Backlog, Cmd+K-Kandidat).
- **Loading**: Hero + Tab-Content mit Skeleton-Cards.
- **Empty**: 
  - Liste leer → "Noch keine Turniere" Vignette (AUDIT.md §4.2).
  - Bracket leer → "Noch nicht gezogen".
  - Schedule leer → "Spielplan kommt vor Anpfiff".
- **Error**: Sync-Fehler → Snackbar mit Retry.

## Accessibility

- **Tab-Order**: TopBar-Suchen → Hosten → Filter-Chips → Tile-Liste (vertikal) → Hero-Buttons → Sub-Tabs → Tab-Content.
- **Focus-Ring**: zwingend auf Tile-Aktiv-State (Border ist schon Fokus-aehnlich, aber zusaetzlicher Outline schadet nicht).
- **Min-Window-Width**: 1024 dp fuer Master/Detail; unter 900 dp Liste-Only mit Modal-Detail.
- **DataTable-Header**: muss `<th scope="col">` semantisch markiert sein (auf Flutter via Semantics-Wrapper).
- **Live-Dot**: animiert (pulsierend) — fuer Reduced-Motion-User abschaltbar.

## Quality-Gate-Checkliste

- [ ] Master/Detail Split 380 / flex, Gap 20.
- [ ] Filter-Chips mit aktiv-State Stone-900.
- [ ] Tile-States: Default / Active (inset Meadow-500) / Registered (Green-Dot) / Result (Foot-Text).
- [ ] StatusTag 4 Tones (Anstehend / Anmeldung / LIVE / Archiv).
- [ ] Hero mit Logo 88 dp + Title 36 px + 4 Meta + kontextsensitive Actions.
- [ ] Live-Dot pulsiert (Box-Shadow-Halo) wenn LIVE.
- [ ] Sub-Tabs (5 Tabs), aktiv = Stone-900 Bottom-Border 2 px.
- [ ] Standings-Tabelle: 7 Spalten, You-Row Meadow-50, Top-3 Rank-Bubble Wood-400.
- [ ] Form-Cells: W = Meadow-500/weiss, L = Stone-200/muted.
- [ ] Bracket horizontal scrollbar mit Final-Highlight in Wood-100.
- [ ] MyMatchPanel mit Avatar-Score-Layout + Lobby-CTA.
- [ ] Schedule-Rows You-Highlight + Naechstes-Match Wood-Left-Border.
- [ ] Empty/Loading/Error-States behandelt.
- [ ] Routes: tournament-list, tournament-detail, match, register, standings, bracket, etc.

## Implementations-Hinweise fuer Flutter

- **Master/Detail**: `Row` mit `SizedBox(width: 380)` (Aside) + `Expanded` (Main). Aside ist `ListView` mit `KCTournamentTile`-Widget.
- **Standings**: Material `DataTable` reicht initial; spaeter eigenes `Table`-Widget wenn Performance ein Problem ist (Default `DataTable` rendert alle Rows).
- **Bracket**: zwei Optionen:
  - **Einfach**: `SingleChildScrollView(scrollDirection: horizontal)` + `Row` von `Column`s. Linien zwischen Matches **nicht** gezeichnet — wie im JSX.
  - **Reich**: `CustomPainter` der Linien zeichnet. Ueber `Stack` mit Position-Daten der Match-Boxes.
  - ADR-Kandidat: **Wahl Bracket-Visualisierung** — Empfehlung A fuer M2-Foundation, B als Polish-Sprint danach.
- **Sub-Tabs**: `DefaultTabController` + `TabBar` mit Custom-Indicator (Stone-900 Bottom-Border).
- **State**: 
  - `tournamentListProvider` (existiert, family `<TournamentStatus?>`).
  - `selectedTournamentProvider` (neu, lokal in Desktop-View-Model) fuer Master-State.
  - `tournamentDetailProvider(id)` (existiert).
  - `tournamentStandingsProvider(id)` (existiert).
  - `tournamentScheduleProvider(id)` (existiert? sonst neu).
- **Hero-Logo**: Token-gebundenes `Container` mit Meadow-50 BG + `flutter_svg` fuer Logo.
- **Live-Dot-Animation**: `AnimationController` + `Tween` fuer Box-Shadow-Opacity, abschaltbar via `MediaQuery.disableAnimations`.
- **Pakete**: keine zwingend neuen. Spaeter evtl. `flutter_staggered_grid_view` fuer Bracket-Polish.
- **Komplexitaet**: **L**. 6 – 8 Tage. Hauptaufwand: Bracket-Visualisierung + Subtabs-Wiring + Hero-Action-Logik (kontext-abhaengig).
