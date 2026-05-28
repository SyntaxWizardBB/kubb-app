# Quality-Gate Index: Desktop UI Kit (Kubb Club)

**Quelle**: `docs/design/ui_kits/desktop/` (11 Screens + Demo-HTML, 13 JSX-Files)
**Flutter-Pendant**: FEHLT vollstaendig — App ist Phone-First (390 dp)
**Status**: Referenz fuer Tablet- und Desktop-Polish, **nach Rebrand-MVP**
**AUDIT-Bezug**: AUDIT.md §4.1 (Master/Detail auf Tablet, Desktop-Kit als Referenz)
**Stand**: 2026-05-28

## Worum es geht

Das Desktop-Kit ist ein React-/JSX-Prototyp, der zeigt, wie Kubb Club als Tablet- und Desktop-Anwendung aussehen soll. Es ist **kein** Flutter-Code und auch nicht als Code-Vorlage gedacht — es ist eine visuelle Spezifikation. Das Kit nutzt dieselben Tokens wie das Mobile-Kit (`docs/design/colors_and_type.css`) und denselben Sprachgebrauch (deutsch, Identifier englisch). Der zentrale Layout-Move ist **Master/Detail** mit fixer Sidebar links und Content-Bereich rechts.

## Screen-Tabelle (11 Screens + Modals)

| Screen | Quelle | Master/Detail | Spalten | Wichtigster Move |
|---|---|---|---|---|
| Dashboard | `DashboardScreen.jsx` | nein (Hero + Grid) | 1.4fr / 1fr | Tournament-Hero-Tile, Recent-Sessions-Liste, Distanzen, Leaderboard |
| Training (live) | `TrainingScreen.jsx` | ja | 340 / 1fr | Config-Aside, Live-Counter, 6-Pad-Tap-Grid |
| Match (live) | `MatchScreen.jsx` | ja (Pitch + Right) | 1.1fr / 1fr | Pitch-SVG, Score-Strip, Per-Wurf-Log; Lobby/Live/Result-Stages |
| Tournament | `TournamentScreen.jsx` | ja | 380 / 1fr | Turnier-Liste, Hero, Subtabs (Tabelle/Bracket/Mein Match/Spielplan/Regeln) |
| Stats | `StatsScreen.jsx` | nein (Hero + Split) | 1.5fr / 1fr | Sniper/Finisseur-Tab, Periode, Heatmap, Highlights |
| Summary | `SummaryScreen.jsx` | nein (Hero + Split) | 1.6fr / 1fr | Verdict-Hero in Meadow, Per-Distanz-Tabelle bzw. Stick-Log |
| Profile | `ProfileScreen.jsx` | ja | 360 / 1fr | Identity-Aside, Auth + Security + Visibility + Danger, Modals |
| Settings | `SettingsScreen.jsx` | ja (3 Spalten) | 260 / 1fr / 300 | Side-Nav fuer Sektionen, Content, Quick-Actions-Aside |
| FinisseurStick | `FinisseurStickScreen.jsx` | ja (3 Spalten) | 340 / 1fr / 320 | Stock-Liste, Per-Stock-Eingabe, Pitch-Preview |
| AppSettingsModal | `AppSettingsModal.jsx` | nein (Dialog) | 520 dp Modal | Quick-Edit App-Preferences |
| CsvExportModal | `CsvExportModal.jsx` | nein (Dialog) | 880 dp Modal | Zeitraum, Modi, Spalten, Live-Vorschau |
| Shared-Komponenten | `shared.jsx` | n/a | n/a | `Shell`, `Sidebar` (240 dp), `TopBar`, `Card`, `PrimaryBtn`, `SecondaryBtn`, `DIcon` |

Plus `index.html` als Demo-Renderer (Browser-Frame-Vorschau, Theme-Toggle, Route-Persistenz im localStorage).

## Master/Detail-Pattern — Spec

### Grundidee

Alle interaktiv-reichen Screens folgen einem zweispaltigen Schema:

- **Master-Spalte** links, fix breit (260 dp / 340 dp / 360 dp / 380 dp je Screen, siehe Tabelle).
- **Detail-Spalte** rechts, `flex: 1`, `min-width: 0` damit innere Truncation funktioniert.
- Auf 3-Spalten-Screens (Settings, FinisseurStick) kommt eine **Aside-Spalte** rechts (~300 dp).
- Globale **Shell-Sidebar** (240 dp) ist immer da und wird durch den Master-Aside nicht ersetzt.

### Breakpoints

| Breite | Layout | Sidebar | Master | Detail |
|---|---|---|---|---|
| < 640 dp | Phone-Layout (bestehende App) | Bottom-Nav | — | Full |
| 640 – 899 dp | Compact-Tablet: Sidebar + Single-Content | Rail (Icon-only, ~80 dp) | — | Full |
| 900 – 1279 dp | Tablet Master/Detail | Rail oder schmale Sidebar | 280 – 320 dp | flex |
| ≥ 1280 dp | Desktop voll | Full-Sidebar (240 dp) | 260 – 380 dp je Screen | flex |

Die JSX-Specs sind fuer 1440 × 920 (siehe `index.html .frame`) gebaut. Werte darunter ziehen sich proportional.

### Globale Shell

Aus `shared.jsx`:

- `Shell` = `Sidebar` + `<main>` flex.
- `Sidebar` = Brand (Logo + Saison-Tag) + 3 Sektionen (`main`, `community`, `account`) + Profile-Footer.
- Sticky `top: 0`, `borderRight: 1px solid var(--kc-line)`.
- Active-State: `background: var(--kc-meadow-50); color: var(--kc-meadow-700)`.
- Badges (z.B. Inbox-Count) als Pill in `--kc-miss`.

### TopBar pro Screen

- `padding: 32px 40px 24px` (Desktop), `borderBottom: 1px solid var(--kc-line)`.
- Eyebrow (mono, uppercase, 11px) + Title (display, 44px) + Subtitle (15px muted).
- `right`-Slot fuer Aktionen (Primary + Secondary Buttons).

## Routing-Strategie fuer Flutter

### Empfehlung: gleicher GoRouter, adaptive Shell

Der bestehende `lib/app/router.dart` definiert die Routes. Tablet/Desktop bekommen **keine** eigenen Routes — die gleichen Paths werden in einem **adaptiven Shell-Widget** anders gerendert.

Konkret:

1. **`AdaptiveScaffold`-Widget** wickelt die ganze App. Auf Phone: bestehendes Verhalten (Tabs/Bottom-Nav + Push-Navigation). Auf Tablet/Desktop: persistente Sidebar (Mapping der Sidebar-Items siehe unten) + Content-Bereich mit `Navigator` der die Route rendert.
2. **Master/Detail per Route-Match**: Auf Detail-Routes (z.B. `/tournament/:id`) wird auf Tablet/Desktop links eine Liste der Geschwister-Entitaeten (Tournaments) gezeigt, rechts das aktive Detail. Auf Phone bleibt es Stack-Push.
3. **Modals bleiben Modals**: `showDialog` auf Tablet/Desktop → zentriertes Dialog-Widget, auf Phone → Bottom-Sheet (bestehende Variante).

### Sidebar-Item → Route-Mapping

| Sidebar-Key (JSX) | Flutter-Route | Hinweis |
|---|---|---|
| `dashboard` | `/` (Home) | Bestehend |
| `training` | `/training/sniper/config` oder `/training/finisseur/config` | Mapping bricht — Desktop nutzt einen Mode-Switch innerhalb des Screens. Vorschlag: neue Route `/training` als Hub. |
| `stats` | `/stats` | Bestehend |
| `tournament` | `/tournaments` (`TournamentRoutes.list`) | Bestehend |
| `match` | `MatchRoutes.newMatch` oder letzter `lobby` | Desktop zeigt direkt Live-Match wenn aktiv |
| `club` | `/teams` oder `/friends` | Existiert in Flutter, im Desktop-Kit `Club & Freunde` betitelt |
| `inbox` | `/inbox` (AuthRoutes.inbox) | Bestehend |
| `profile` | `/profile` | Bestehend |
| `settings` | `/settings` | Bestehend |

Die Sidebar selbst ist also **eine UI-Komponente**, kein Routing-Konzept — sie ruft `context.go(...)` mit den Standard-Routes.

### Empfohlene Pakete

- **`flutter_adaptive_scaffold`** (offizielles Flutter-Paket): liefert `AdaptiveScaffold`, Breakpoints, Sidebar-Navigation. Reicht fuer 80% der Use-Cases.
- Alternativ: handgerollt mit `LayoutBuilder` + `MediaQuery.sizeOf(context).width`. Mehr Kontrolle, mehr Code.
- **`flutter_staggered_grid_view`** kann fuer den Bracket-View (TournamentScreen) helfen, ist aber nicht zwingend — `CustomScrollView` reicht.
- **Keine** Custom-Pakete fuer Sidebar — `NavigationRail` aus Material 3 plus eigenes Styling deckt das Desktop-Kit ab.

## Token-Inventar — Desktop-spezifisch

Das Desktop-Kit nutzt die gleichen Tokens wie das Mobile-Kit. Neu auftauchend oder besonders prominent:

- **Display-Sizes hoeher**: TopBar-Title 44 px, Tournament-Tile 48 px, Score-Number 84 – 160 px (Match-Result-Hero), TodayBig 72 px.
- **Tab-Patterns**: Pill-Switcher (Stage-Switch, Period-Row, Tab-Row) konsistent mit `border-radius: 999px`, Inactive auf `--kc-bg-sunken`, Active auf `--kc-stone-900`.
- **Card-Shadows**: `--kc-shadow-1` Standard, `--kc-shadow-2` fuer Hero-Tiles, `--kc-shadow-3`/`--kc-shadow-4` fuer Modals.
- **Live-Indikator**: roter Punkt + Box-Shadow-Halo (Tournament-Hero, Match-LIVE).
- **Padding-Konvention**: `padding: 24px 40px 48px` fuer Body unter TopBar (1280 dp max-Width); 32 px Side-Padding bei Split-Layouts.

## Was Desktop hat, was Mobile nicht hat

- **Sidebar als persistente Navigation** (Mobile hat Bottom-Tab + Drawer).
- **Master/Detail-Listen** statt Push-Navigation auf Tournament, Profile, Settings, FinisseurStick.
- **Per-Throw-Log** als sichtbare Seitenleiste im Match (Mobile zeigt eher nur den letzten Wurf).
- **Pitch-Diagram als grosses SVG** in Match und FinisseurStick — Mobile zeigt vermutlich Mini-Variante.
- **Keyboard-Hints** (FinisseurStick zeigt `0…7`, `H`, `K` als kbd-Elemente).
- **Stage-Switch** im Match (Lobby / Live / Result als Pill-Tabs im TopBar-Right).
- **3-Spalten-Layouts** (Settings, FinisseurStick) — Mobile undenkbar.
- **Hover-States impliziert** — Buttons haben `cursor: pointer`, aber explizite `:hover`-Styles fehlen im Kit, das ist Lieferaufgabe der Flutter-Umsetzung (Material-Standard reicht).

**Was Desktop nicht hat**, was Mobile hat: explizite Auth-Onboarding-Screens (SignIn, AnonymousSignup, Restore, AccountLink, DeleteAccount, OnboardingTour) fehlen im Desktop-Kit komplett. Friends/Groups-Screens auch nicht ausgemalt. Public Tournament/Match-Spectator-Views ebenfalls nicht — sind aber im Router definiert.

## Sprint-Reihenfolge — Empfehlung

Wenn Tablet/Desktop nach dem Rebrand-MVP angegangen wird, folgende Reihenfolge:

1. **AdaptiveScaffold + Sidebar (Sprint 1)** — Foundation. Bricht nichts. Phone-Layout bleibt unveraendert ab `< 900 dp`. Liefert sofort das Tablet-Gefuehl auf den bestehenden Screens.
2. **Dashboard (Sprint 1 spaet)** — Hero-Tile + Recent-Sessions ist der visuelle Eye-Catcher und braucht keine neue Domain-Logik. Reiner UI-Move.
3. **Tournament Master/Detail (Sprint 2)** — hoher Nutzen, weil Organizer das auf Tablet/Laptop nutzen. Bracket-View als CustomPainter oder Lib-Entscheidung faellt hier (eigener ADR).
4. **Match Live (Sprint 3)** — komplex (Pitch-SVG, Live-Log). Wartet auf Realtime aus M4. Liefert das "Make-it-Shine"-Moment.
5. **Stats + Summary (Sprint 4)** — Charts (Sparkline, Heatmap) sind aufwendig, aber unabhaengig von Domain-Aenderungen.
6. **Settings + Profile + Modals (Sprint 5)** — Forms-heavy. Reactive-Forms ist gesetzt, Aufwand ist Layout, nicht Logik.
7. **FinisseurStick + Training (Sprint 6)** — am wenigsten dringend, weil Trainings primaer Phone-Use-Case sind.

### Aufwands-Schaetzung (sehr grob)

Pro Screen bei Senior-Niveau (Faktor 0.8 per `scrum-master.md`):

- Dashboard, Stats, Summary, Profile, Settings: **3 – 5 Tage** je (UI, Forms, kleinere Charts).
- Tournament: **6 – 8 Tage** (Bracket-View ist die Bremse).
- Match: **6 – 10 Tage** (Pitch-SVG → CustomPainter, Live-Log, Stage-Switch).
- FinisseurStick + Training: **5 – 7 Tage** je.
- AppSettingsModal + CsvExportModal: **1 – 2 Tage** je (Forms only).
- AdaptiveScaffold + Sidebar Foundation: **3 – 4 Tage**.

Gesamt: **45 – 65 Tage**, also etwa zwei volle Milestones nach Senior-Sizing — vergleichbar zur M1-Tournament-Foundation in Umfang.

## Pflicht-ADRs vor Implementierungsbeginn

1. **AdaptiveScaffold-Strategie**: `flutter_adaptive_scaffold` vs. handgerollt (siehe oben).
2. **Bracket-Visualisierung**: CustomPainter, externe Lib, oder reine Flex/Wrap-Loesung.
3. **Pitch-SVG → CustomPainter**: das SVG aus `MatchScreen.jsx` muss als `CustomPainter` portiert werden, weil Flutter-SVG-Rendering fuer interaktive Pitches zu unflexibel ist.
4. **Tablet-Routing-Pattern**: gleicher Router mit adaptiver Shell (siehe oben) — als ADR festhalten und mit ADR-0015 (Cross-Platform Sequencing) verzahnen.

## Quality-Gate-Index (alle Screens)

- [Shared Components](desktop-shared-components.md)
- [Dashboard](desktop-dashboard-screen.md)
- [Training (live)](desktop-training-screen.md)
- [Match](desktop-match-screen.md)
- [Tournament](desktop-tournament-screen.md)
- [Stats](desktop-stats-screen.md)
- [Summary](desktop-summary-screen.md)
- [Profile](desktop-profile-screen.md)
- [Settings](desktop-settings-screen.md)
- [FinisseurStick](desktop-finisseur-stick-screen.md)
- [AppSettingsModal](desktop-app-settings-modal.md)
- [CsvExportModal](desktop-csv-export-modal.md)
