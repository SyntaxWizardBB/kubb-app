# Quality-Gate: Shared Components (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/shared.jsx`
**Flutter-Pendant**: FEHLT — Phone-First, kein Desktop-Shell vorhanden
**Tablet/Desktop-Breakpoints**: ab 640 dp Compact-Tablet (Rail), ab 900 dp Master/Detail, ab 1280 dp Full Sidebar (240 dp)
**Stand**: 2026-05-28

## Visual-Spec

### Sidebar (`Sidebar`)
- Breite fix 240 dp, `position: sticky; top: 0`, volle Hoehe.
- Hintergrund `--kc-bg-raised`, Right-Border `1px solid --kc-line`.
- Padding `20px 14px 14px`, vertikales Layout mit `gap: 8`.
- Brand-Header: 36 × 36 Logo + Stack aus Brand-Name (display, 18 px, weight 700, letter-spacing -0.02em, opsz 36) + Brand-Tag (mono, 10 px, uppercase, letter-spacing 0.08em).
- Nav-Items: `min-height: 40`, `padding: 10px 12px`, `border-radius: 10`, Icon 20 dp + Label + optional Badge.
  - Inactive: `color: --kc-fg-muted`.
  - Active: `background: --kc-meadow-50`, `color: --kc-meadow-700`.
- Drei Sektionen: `main` (Dashboard, Training, Statistik, Turniere, Match), `community` (Club & Freunde, Inbox), `account` (Profil, Einstellungen).
- Badge: Pill 20 × 20 dp, `--kc-miss`, weiss, 11 px bold (z.B. Inbox-Count).
- Profile-Footer: Avatar 36 dp (`--kc-meadow-500`), Name + Sub (mono 10 px), Chevron rechts.

### TopBar (`TopBar`)
- `padding: 32px 40px 24px`, `border-bottom: 1px solid --kc-line`.
- Layout: zwei Spalten (`flex`, `justify-content: space-between`, `align-items: flex-end`).
- Eyebrow: mono, 11 px, weight 600, uppercase, letter-spacing 0.1em, `--kc-fg-muted`.
- Title: display, 44 px, weight 700, line-height 1.05, letter-spacing -0.025em, opsz 72.
- Subtitle: 15 px, `--kc-fg-muted`, `max-width: 560`.
- Right-Slot fuer Actions (gap 10).

### Buttons
- **PrimaryBtn** (3 sizes: sm 36 dp / md 44 dp / lg 52 dp):
  - Background `--kc-meadow-600`, color `--kc-on-primary`, `border-radius: 12`, `box-shadow: --kc-shadow-1`, weight 700, letter-spacing -0.01em.
- **SecondaryBtn** (sm/md, 3 tones):
  - `default`: `--kc-bg-raised`, `--kc-fg`, `inset 0 0 0 1.5px --kc-stone-200`.
  - `ink`: `--kc-stone-900` bg, `--kc-chalk-50` text.
  - `ghost`: transparent, `--kc-fg`.
- Beide: Icon + Label, `display: inline-flex; gap: 8; white-space: nowrap`.

### Card (`Card`, `CardHeader`)
- Background `--kc-bg-raised`, `border-radius: 16`, default padding 20.
- `raised` (default): `box-shadow: --kc-shadow-1`, kein Border.
- `raised={false}`: `border: 1px solid --kc-line`, kein Shadow.
- `CardHeader`: Eyebrow (mono 10 px) + Title (ui 18 px bold) + optional Right-Slot.

### Icons (`DIcon`)
- Stroke-Icons, viewBox `0 0 24 24`, default 20 × 20 (Plus 18 / 18, Plus2 20 / 20).
- Stroke-Width 2 (Plus2 2.5), `currentColor`, rounded line-caps + joins.
- Vorhanden: Home, Target, Stat, Cup, Users, Profile, Gear, Inbox, Plus, Plus2, Minus, Search, Chevron, King, Flame, Heli, Bell, Pause, Stop (filled), Undo, Calendar.

## Komponenten-Inventar

Aus `shared.jsx` exportiert via `window.*`:

| Komponente | Zweck | Flutter-Aequivalent |
|---|---|---|
| `Shell` | Sidebar + Main-Wrap | Eigenes `AdaptiveShell`-Widget |
| `Sidebar` | Persistente Navigation | `NavigationRail` (extended) + Custom-Styling |
| `TopBar` | Page-Header Eyebrow/Title/Subtitle | Custom `KCAppBar` (kein Material-`AppBar` — Layout zu spezifisch) |
| `PrimaryBtn`/`SecondaryBtn` | Action-Buttons mit Tone/Size-Varianten | `ElevatedButton`/`OutlinedButton`/`TextButton` mit Theme-Override |
| `Card`/`CardHeader` | Container + Header | `Material` + `Container`-Wrapper |
| `DIcon` | Icon-Set | `flutter_svg` mit SVGs aus dem Kit, oder selektive `Icons` von Material 3 (wo Mapping passt) |

**Was unterscheidet sich von Mobile**: Mobile-Pendant (`docs/design/ui_kits/app/shared.jsx`) liefert iOS-Frame-Wrapper, Bottom-Tab-Nav, Touch-Target-Sizes ≥ 48 dp. Desktop-Variante ersetzt Bottom-Nav durch Sidebar, nutzt kleinere Touch-Targets (40 dp ist OK fuer Maus), und fuegt Eyebrow/Subtitle-Slots zur TopBar hinzu.

## Interaktions-Pattern

- **Mouse-Hover**: im JSX nicht explizit gestyled — Flutter-Default-Hover-Tints reichen.
- **Keyboard-Navigation**:
  - Tab-Order: Sidebar → TopBar-Actions → Content-Pane → optional Right-Aside.
  - Esc: schliesst Modals.
  - Sidebar-Items sind `<button>`, also tab-fokussierbar.
  - **Cmd+K** / globale Suche ist im Kit nicht modelliert — bleibt Backlog (`SearchBtn` taucht nur in Tournament als sichtbarer Search-Trigger auf).
- **Multi-Pane-Sync**: Aktive Sidebar-Item → `route`-State; Master-Listen-Auswahl → lokaler `activeId`-State im jeweiligen Screen. Auf Flutter via Riverpod-Provider abbilden.
- **Loading/Error/Empty**: im Kit nicht modelliert. Per AUDIT.md §4.2-4.4 sind Empty/Loading/Offline-States eigene Backlog-Items.
- **Desktop-spezifisch**: Sidebar bleibt waehrend ganzen App-Lebens stehen; kein Splash zwischen Route-Wechseln.

## Accessibility

- **Tab-Order**: Logo → Sidebar-Items in Reihenfolge → Content-Buttons. Sollte mit `FocusTraversalGroup` in Flutter erzwingbar sein.
- **Focus-Ring**: im JSX nicht definiert — **muss aus Tokens kommen**. Vorschlag: `--kc-meadow-500` Outline, 2 px, 2 px Offset. ADR-Kandidat.
- **Min-Window-Width**: Sidebar 240 + Master 280 + Detail 320 = **840 dp**. Unter 900 dp wird die Sidebar zur Rail (~80 dp).
- **Touch-Targets**: Sidebar-Items 40 dp — auf Tablet grenzwertig (WCAG empfiehlt 44 dp). Aufweiten wenn Touch-Geraet erkannt.
- **Kontrast**: Active-State `--kc-meadow-50` Background mit `--kc-meadow-700` Text ist WCAG AA tauglich (Token-Sheet ist auf AA geprueft).

## Quality-Gate-Checkliste

- [ ] Sidebar nutzt exakt `--kc-bg-raised`, `--kc-line`, `--kc-meadow-50/700` Tokens.
- [ ] Sidebar-Width 240 dp respektiert auf Desktop.
- [ ] Sticky-Verhalten beim Scrollen funktioniert.
- [ ] Badge-Counts werden live aus den jeweiligen Providers gefuettert (Inbox, Tournament).
- [ ] TopBar `padding: 32px 40px 24px` und nicht-elliptisches Title-Truncation.
- [ ] Buttons in allen drei Tones + drei Sizes vorhanden, mit Hover/Focus/Disabled-States aus Material 3 + Token-Override.
- [ ] Card-Shadow konsistent `--kc-shadow-1` (Standard) bzw. `--kc-shadow-2` (Hero-Tiles).
- [ ] Icons als SVG-Assets aus dem Kit kopiert oder via `flutter_svg` eingebunden.
- [ ] Keyboard-Tab durchlaeuft Sidebar → TopBar → Content.
- [ ] Focus-Ring sichtbar und tokenisiert.

## Implementations-Hinweise fuer Flutter

- **Foundation-Widget**: `AdaptiveShell({ required Widget child, required String activeKey, required ValueChanged<String> onRoute })` — eigenes Widget, intern `LayoutBuilder` + Switch zwischen `BottomNavScaffold` (Phone) und `SidebarScaffold` (Tablet/Desktop).
- **Material 3 `NavigationRail`** ist ein guter Startpunkt fuer die Sidebar, aber muss massiv ueberschrieben werden (Sektionen, Badges, Profile-Footer, Brand-Header). Vielleicht besser handgerollt mit `Column` + `ListTile`.
- **`flutter_adaptive_scaffold`-Paket**: liefert Breakpoint-Logik (`Breakpoints.large` = ≥ 1240 dp), kann aber Sidebar nicht so kustomisieren wie das Kit verlangt. → Nur als Breakpoint-Source nutzen.
- **TopBar als `SliverPersistentHeader`** wenn Content scrollt und Header sticky bleibt; sonst flaches Widget.
- **Buttons via Theme**: `elevatedButtonTheme` + `outlinedButtonTheme` mit Token-gebundenen Farben — keine Per-Call-Styling-Wiederholung.
- **Komplexitaet**: **M-L**. Foundation-Sprint, blockiert alle anderen Desktop-Sprints. Geschaetzt 3-4 Tage.
- Tokens kommen aus `docs/design/colors_and_type.css` und sind in `lib/core/theme/` bereits gemappt (siehe Mobile-Setup) — Sidebar nutzt dieselben Token-Namen.
