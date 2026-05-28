# Quality-Gate: Dashboard (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/DashboardScreen.jsx`
**Flutter-Pendant**: existiert als Phone-Home (`lib/features/home/`) — Desktop-Layout FEHLT
**Tablet/Desktop-Breakpoints**: ab 900 dp greift das Hero-Row + Two-Column-Grid; ab 1280 dp volle Breite (max 1280 dp Content)
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur
- TopBar (Standard, eyebrow + title 44 px + subtitle + 2 Buttons).
- Body `padding: 24px 40px 48px`, `max-width: 1280`, vertikales Layout (`gap: 24`).
- **Hero-Row** (`grid-template-columns: 1.55fr 1fr`, gap 18):
  - Links: grosse Tournament-Tile (`min-height: 212`), Wood-Gradient-Background, Eyebrow + Title 48 px + Sub + 3 Meta-Items + Chevron-Arrow oben rechts.
  - Rechts: Card "Heute" (Trefferrate 72 px, Delta, 3 Mini-Stats) + Invite-Pill darunter.
- **Main-Grid** (`grid-template-columns: 1.4fr 1fr`, gap 18):
  - Linke Spalte: "Letzte Sessions" Card (Session-Rows mit Tag/Rate/Sub/When/Chevron) + "Trefferrate 4 Wochen" Card mit Big-Sparkline (140 dp Hoehe).
  - Rechte Spalte: "Pro Distanz" Card (Bar-Liste mit Rate-Track, Trend, N) + "BKC Diese Woche" Leaderboard (You-Highlight) + News-Card.

### Farben (Tokens)
- Tournament-Tile: `linear-gradient(135deg, --kc-wood-500 0%, --kc-wood-600 100%)`, Text `--kc-chalk-50`, `box-shadow: --kc-shadow-2`.
- Today-Card: Standard-Card mit `--kc-meadow-600` als grosse Zahl.
- Session-Row Rate-Color: `--kc-miss` (tone='bad') / `--kc-meadow-600` (tone='fin-clean') / `--kc-fg` (default).
- DistRow Track: `linear-gradient(90deg, --kc-meadow-400, --kc-meadow-600)`.
- Leaderboard You-Row: `--kc-meadow-50` Background.

### Typografie
- Tournament-Tile Title: 48 px display, opsz 96, weight 700, letter-spacing -0.025em.
- Today-Big: 72 px ui, weight 800, line-height 1, letter-spacing -0.04em, `tabular-nums`, color `--kc-meadow-600`.
- Session-Rate: 20 px ui bold tabular.
- DistRow Val: 16 px ui weight 700 tabular.
- Mini-Labels durchgaengig mono 10 px uppercase 0.06em / 0.08em letter-spacing.

### Spacing
- Body-Gap 24, Hero-Row-Gap 18, Main-Grid-Gap 18, Card-Inner padding 18 – 20.
- Session-Row Padding `14px 20px`, Border-Top auf jeder Zeile.

### Border-Radius
- Tournament-Tile 18, Cards 16, Invite-Pill 14, Chips 999.

### Shadows
- Tournament-Tile `--kc-shadow-2`, Invite-Pill `--kc-shadow-1`, Cards Default `--kc-shadow-1`.

### Icons
- `DIcon.Plus` (Training starten), `DIcon.Calendar` (Diese Woche), `DIcon.Chevron` (Tile-Arrow, alle "Mehr"-Links).

## Komponenten-Inventar

- Aus `shared.jsx`: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `CardHeader`, `DIcon`.
- Lokal definiert: `SessionRow`, `Mini`, `DistRow`, `BigSparkline` (SVG, 540 × 140, Gradient-Fill + Line + End-Dot).

**Unterschied Mobile**: Phone-Home (`HomeScreen.jsx` mobile) hat keine Hero-Row und kein Multi-Column-Grid — alles untereinander, Tournament-Tile schmaler, Leaderboard fehlt vermutlich oder ist als Bottom-Sheet versteckt.

**Flutter-Aequivalente**:
- BigSparkline → `CustomPainter` mit `Path` und Linear-Gradient `Shader`.
- DistRow-Track → einfach `LinearProgressIndicator` + Token-Override oder eigenes `Container` mit `Stack`.
- Tournament-Tile → `InkWell` + `Container` mit `LinearGradient`.

## Interaktions-Pattern

- **Tile-Click** → `onRoute('tournament')`, ganzes Tile ist Button.
- **Session-Row** → `onRoute('stats')` (Detail kommt spaeter aus dem `stats`-Context).
- **Invite-Pill** → `onRoute('match')` (Match-Lobby).
- **CTA-Buttons**: "Training starten" → `onRoute('training')`, "Diese Woche" ist Filter (im JSX nicht implementiert).
- **Mouse-Hover**: nicht explizit, Material-Hover-Tints reichen.
- **Keyboard**: Tab → Tile → Today-Card → Invite-Pill → Recent-Sessions-Liste → Sparkline (skip) → Pro-Distanz-Liste → Leaderboard → News-Card.
- **Loading**: Auf Desktop besonders sichtbar wegen Sidebar — Skeleton-Cards in jedem Slot (siehe AUDIT.md §4.3).
- **Empty**: Erst-Nutzer ohne Sessions → Heute-Card und Recent-Sessions brauchen Empty-Hint mit Vignette + CTA (siehe AUDIT.md §4.2).

## Accessibility

- Tab-Order: Topbar-Buttons → Tournament-Tile → Today-Card (statisch, nicht fokussierbar) → Invite-Pill → Recent-Sessions (jede Row) → Pro-Distanz (statisch) → Leaderboard-You-Row (vielleicht fokussierbar) → News-CTA.
- Focus-Ring: token-basiert (siehe Shared-Components-Gate).
- Min-Window-Width: 1024 dp damit Hero-Row + Main-Grid noch lesbar. Darunter fallback auf Single-Column.
- Tournament-Tile-Text hat hohes Kontrastniveau auf Wood-Gradient — pruefen, dass `--kc-chalk-50` auf `--kc-wood-500` mindestens 4.5:1 erreicht (Token-Sheet sollte das garantieren).

## Quality-Gate-Checkliste

- [ ] Hero-Row Tile + Today-Card Layout exakt 1.55fr / 1fr, Gap 18.
- [ ] Tournament-Tile Wood-Gradient mit `--kc-shadow-2`.
- [ ] Today-Number 72 px in `--kc-meadow-600`, `tabular-nums` aktiv.
- [ ] Session-Rows mit korrekten Tone-Mappings (bad / fin-clean / default).
- [ ] BigSparkline 4-Wochen-Datenreihe rendert, End-Dot sichtbar.
- [ ] DistRow Track-Gradient korrekt (Meadow 400 → 600).
- [ ] Leaderboard You-Row mit Meadow-50 + "du"-Tag.
- [ ] News-Card mit Ink-Tone-Button.
- [ ] Body max-width 1280, Padding 24/40/48.
- [ ] Alle Routes verdrahtet: tournament, training, match, stats.
- [ ] Empty-State pro Card behandelt.

## Implementations-Hinweise fuer Flutter

- **Layout**: Top-Level `CustomScrollView` mit `SliverPadding` + `SliverList`-Sections. Inner Grids via `LayoutBuilder` und `Row`/`Column` mit `Expanded` (Flex 155 / 100, 140 / 100).
- **Sparkline**: eigener `CustomPainter`, ca. 50 LOC. Tests via `goldens`.
- **Tournament-Tile**: `Material(InkWell)` Hover-Effekte; Gradient via `BoxDecoration(gradient: LinearGradient(...))`.
- **Leaderboard**: einfacher `Column` mit `ListTile`-aehnlichen Rows, You-Row hat `BoxDecoration` mit Meadow-50.
- **State**: `dashboardSummaryProvider` (Riverpod) liefert: nextTournament, todayStats, recentSessions[6], byDistance[5], clubLeaderboard[5], newsTeaser. Existiert teilweise (Phone-Home), Desktop kann denselben Provider konsumieren.
- **Pakete**: keine zusaetzlichen. Material 3 + Riverpod reichen.
- **Komplexitaet**: **M-L**. Geschaetzt 3 – 5 Tage inkl. Sparkline + Empty-States. Erste sichtbare Desktop-Auszahlung nach dem AdaptiveShell-Foundation-Sprint.
