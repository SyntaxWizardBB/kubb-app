# Quality-Gate: Shared Components

**Quelle**: `docs/design/ui_kits/app/shared.jsx`
**Flutter-Pendant**: `lib/core/ui/icons.dart`, `lib/core/ui/widgets/kubb_app_bar.dart`, `lib/core/ui/widgets/`
**Stand**: 2026-05-28

## Inventar wiederverwendbarer Komponenten

`shared.jsx` exportiert genau zwei Symbole am Window-Scope: `Icon` (Icon-Bibliothek) und `AppBar` (Header-Komponente). Beides sind die Fundamente fuer alle Sekundaer-Screens (Profil, Stats, Settings, FinisseurConfig, FinisseurStick, EightM, Summary).

### 1. `Icon` — 24px Stroke-Icon-Library

**Quelle**: inline-SVGs, monochromatisch via `currentColor`. Strichbreite uniformly `2`–`2.5`, `strokeLinecap="round"`, `strokeLinejoin="round"`.

**API pro Icon**: `<Icon.<Name> {...props}/>` mit beliebigen SVG-Props (className, width, height, style).

**Liste mit Verwendung**:

| Glyph | Default-Groesse | Einsatzort im Kit |
|---|---|---|
| `Plus` | 24 | Counter-Increment (Sniper) |
| `Minus` | 24 | Counter-Decrement (Sniper) |
| `Close` | 22 | Sheet-Close, Modal-Close |
| `Settings` / `Gear` | 22 | Settings-Entry-Point |
| `Back` | 22 | AppBar-Leading |
| `Check` | 22 | Success-Verdict, Form-Confirm |
| `X` | 22 | Negativ-Verdict |
| `Heli` | 22 | Helikopterwurf-Marker (Sniper, Finisseur) |
| `Trophy` / `Cup` | 22 | Tournier-Tile (Home) |
| `Stat` | 22 | Stats-Entry-Point |
| `Target` | 22 | Sniper-Branding |
| `Flame` | 22 | Streak-Anzeige (Stats) |
| `King` | 22 | Koenigsstoss-Marker (Finisseur) |
| `Eye` / `EyeOff` | 22 | Password-Show-Toggle (Profile) |
| `Menu` | 22 | Home-Top-Left Hamburger |
| `Profile` | 22 | Home-Top-Right Avatar-Slot |
| `ChevronRight` | 20 | Listenzeilen-Affordance |
| `Plus2` | 20 | FAB-Icon, "Neue Session" |
| `Star` | 22 | Awards (Chriesi) |
| `Trash` | 20 | Destruktive Actions |
| `Download` | 20 | CSV-Export |
| `Lock` | 20 | Passwort-Aenderung (Profile) |
| `Mail` | 20 | E-Mail-Aenderung (Profile) |
| `Filter` | 22 | Filter-Sheet-Trigger (Stats) |
| `Google` / `Apple` | 20 | OAuth-Provider-Buttons |

**Flutter-Aequivalent**: `lib/core/ui/icons.dart`. Aktuell in Verwendung sind `lucide_icons` (Standard-Set) plus eigene `KubbIcons` fuer Brand-Glyphen. Mapping ist nicht 1:1: das JSX-Kit zeichnet eigene SVGs, Flutter wraps Lucide. Brand-spezifische Glyphen (`Heli`, `King`, `Cup`, `Target` mit Bullseye) sollten als CustomPainter oder dedizierte Lucide-Picks (`LucideIcons.crown`, `LucideIcons.target`) explizit verifiziert werden.

**Vorschlag fuer neue Widgets**: keine — bestehender `KubbIcon`-Wrapper deckt das Pattern ab. Pruefen, ob alle 25 Icon-Namen oben einem konsistenten Lucide-Mapping zugewiesen sind.

### 2. `AppBar` — universeller Sekundaer-Screen-Header

**Quelle JSX**:
```js
<AppBar eyebrow="Account" title="Profil" onBack={...} right={<button/>} sticky={false}/>
```

**Props**:
- `eyebrow?: string` — kleine Caps-Headline ueber dem Title (optional)
- `title: string` — Display-Font, 18px, weight 700
- `onBack?: () => void` — wenn vorhanden, zeigt Back-Icon links; sonst 48px-Spacer
- `right?: ReactNode` — optionaler Slot rechts (Filter-Button, Edit-Button, ...)
- `sticky?: boolean` — wenn true: `position: sticky, top: 0, zIndex: 10`

**Visual-Spec aus JSX**:
- Header padding: `54px 12px 6px` (top accounts for iOS-Notch im ios-frame; in Flutter SafeArea)
- Back-Button: `48 x 48`, transparent, `borderRadius: 12`, Color `var(--bk-fg)`
- Title: `flex: 1`, `textAlign: center`, font Display, `letterSpacing: -0.02em`, `whiteSpace: nowrap`, `textOverflow: ellipsis`
- Eyebrow: 11px, weight 600, `letterSpacing: 0.08em`, uppercase, `color: var(--bk-fg-muted)`
- Right-Slot: `minWidth: 48`, `justify-content: flex-end`

**Flutter-Pendant**: `lib/core/ui/widgets/kubb_app_bar.dart` — `KubbAppBar` mit `eyebrow`, `title`, `leading`, `actions`, `automaticallyImplyLeading`. Implementiert `PreferredSizeWidget` (`Size.fromHeight(88)`).

**Mapping Property-by-Property**:

| JSX-Prop | Flutter-Pendant | Mapping-Status |
|---|---|---|
| `eyebrow` | `eyebrow` | passt |
| `title` | `title` | passt |
| `onBack` | `leading: IconButton(...)` ODER `automaticallyImplyLeading` | passt; Flutter laesst Go-Router-pop automatisch zu |
| `right` | `actions: Widget?` | passt — JSX erwartet beliebigen Node, Flutter erwartet **einen** Widget |
| `sticky` | nicht abgebildet | Flutter-Scaffold platziert AppBar ueber Body, `sticky` ist Web-Spezialitaet — kein Mismatch |

**Abweichungen / Beobachtungen**:
- JSX zentriert den Title, Flutter laesst den Title link-buendig (Material-Default mit `Expanded`-Column ohne expliziten `alignment`). Pruefen ob Center-Alignment im Design gewuenscht ist — die JSX-Style-Tabelle setzt `textAlign: center`.
- JSX setzt `whiteSpace: nowrap; overflow: hidden; textOverflow: ellipsis` — Flutter hat `maxLines: 1, overflow: TextOverflow.ellipsis`. Passt.
- JSX-Title `letter-spacing: -0.02em` (–0.36 bei 18px), Flutter hat `letterSpacing: -0.36`. Passt.
- JSX-Eyebrow `letter-spacing: 0.08em` (~0.88 bei 11px), Flutter hat `letterSpacing: 0.88`. Passt.
- AppBar-Padding-Top JSX `54px` vs. Flutter `KubbTokens.space6` (24). Differenz wird vom Scaffold/SafeArea kompensiert; visuell pruefen.

### 3. Implizit geteilte Sub-Komponenten (mehrfach im Kit, aber nicht in `shared.jsx` exportiert)

Diese Patterns wiederholen sich ueber mehrere Screens. Sie gehoeren noch nicht zur shared-Library, sind aber Wiederverwendungs-Kandidaten:

#### 3.1 Bottom-Sheet-Pattern

Verwendet in: `HomeScreen` (Training-Sheet), `StatsScreen` (Filter-Sheet), `ProfileScreen` (Password-Sheet, Email-Sheet), `AppSettingsModal`, `CsvExportModal`.

**Gemeinsame Visual-Spec**:
- Backdrop: `position: absolute, inset: 0, background: rgba(12,11,7, 0.45–0.55), zIndex: 10–30`
- Sheet: `width: 100%, background: var(--bk-bg-raised)` oder `var(--bk-bg)`, `borderTopLeftRadius: 24, borderTopRightRadius: 24`
- Grabber: `36 x 4, background: var(--bk-stone-200), borderRadius: 999`, zentriert, `marginBottom: 6`
- Head: eyebrow + h2 (`fontSize: 22, weight: 700, letterSpacing: -0.02em`) + Close-Button-Slot rechts
- Body-Padding: `10px 18px 28-32px`

**Flutter-Pendant**: `lib/core/ui/widgets/kubb_bottom_sheet.dart` — pruefen ob das Pattern dort identisch implementiert ist.

**Vorschlag**: Falls noch nicht zentralisiert, `KubbBottomSheet` als Standard-Wrapper mit Slot-API (`eyebrow`, `title`, `body`, `actions`) konsolidieren.

#### 3.2 Section-Header / Eyebrow-Label

Wiederholtes Pattern ueber alle Screens:
```js
{ fontSize:11, fontWeight:600, letterSpacing:'0.08em', textTransform:'uppercase', color:'var(--bk-fg-muted)' }
```

Eigener Token / Widget waere `KubbEyebrowText(text)` oder Theme-`labelSmall`-Variante. Aktuell wird das in jedem Screen inline gebaut (siehe Flutter `_SectionHead`-Innerclass in `stats_screen.dart`).

**Vorschlag**: `KubbSectionLabel` oder `KubbEyebrow`-Widget im `core/ui/widgets/` anlegen.

#### 3.3 Segmented Control (`Seg`)

Definiert inline in `ProfileScreen.jsx`:
```js
function Seg({ value, options, onChange }) { ... }
```

Style:
- Container: `background: var(--bk-bg-sunken), borderRadius: 999, padding: 3`
- Buttons: `flex: 1, minHeight: 36, padding: 0 10px, borderRadius: 999`
- Active: `background: var(--bk-stone-900), color: var(--bk-chalk-50)`

**Flutter-Aequivalent**: kein dediziertes Widget identifiziert. `lib/core/ui/widgets/` enthaelt `kubb_counter`, `kubb_tap_pad` — kein Seg.

**Vorschlag**: `KubbSegmentedControl<T>` Widget anlegen (M2-Polish-Task), genutzt von Profile (Wurfhand, Stamm-Distanz) und Stats (Sniper/Finisseur-Tab als Alternative zur TabBar).

#### 3.4 Field-Row (Label + Value/Input)

In `ProfileScreen.jsx` als `Field({ label, children })`. Style:
- Container: `flex-direction: column, gap: 6, padding: 10px 0, borderBottom: 1px solid var(--bk-line)`
- Label: 11px, weight 600, `letterSpacing: 0.08em`, uppercase, muted

**Vorschlag**: `KubbFieldRow` als Standard-Listenzeile fuer Settings/Profile/Form-Sections.

#### 3.5 NavRow (Icon + Label/Sub + Chevron)

In Profile (Email, Passwort, Provider) und impliziert in Home-Recent. Style:
- Row: `padding: 10px 0, minHeight: 60, borderBottom: 1px solid var(--bk-line)`
- Icon-Slot: `36 x 36, background: var(--bk-bg-sunken), borderRadius: 10`
- Text-Slot: `flex: 1`, Label 15px / Display, Sub 12px muted
- Affordance: `<Icon.ChevronRight/>` rechts ODER Pill-Badge

**Vorschlag**: `KubbNavRow` als Standard-Listenzeile in Profile/Settings/Inbox.

#### 3.6 Sparkline-Chart

In `StatsScreen.jsx` als `Sparkline({ points, tone })`. SVG-based, weighted area + stroke + endpoint-circle.

**Flutter-Aequivalent**: `lib/features/stats/presentation/widgets/stats_trend_chart.dart`. Pruefen ob die Visual-Spec passt (tone-switch fuer Sniper-Gruen vs. Finisseur-Wood).

#### 3.7 Hero-Number-Block

In `StatsScreen.jsx` als `Hero({ label, value, unit, big, tone })`. Display-Number bis 56px mit kleinerer Unit. Tone-Switch: `wood | muted | default`.

**Flutter-Aequivalent**: `stats_aggregate_block.dart`. Verifikation, dass `big` und `tone` Varianten existieren.

#### 3.8 Verdict-Banner (Summary)

In `SummaryScreen.jsx` als `<div style={verdict}>`. Tonal: Meadow-Gruen fuer Success, Stone-700 fuer Fail. 90px Display-Number.

**Flutter-Aequivalent**: `_Verdict` / `_FinisseurVerdict` inline in `summary_screen.dart`. Wiederverwendungs-Kandidat: `KubbVerdictBanner` als geteiltes Widget.

#### 3.9 Pill (Multi-Distance-Breakdown)

In `SummaryScreen.jsx` als `Pill({ tone, label, value, dim })`. Kleine vertikal gestapelte Statistik-Kachel.

**Flutter-Pendant**: nicht identifiziert. Kandidat fuer `KubbStatPill`-Widget.

## Design-Tokens — Mapping `shared.jsx`/CSS zu `KubbTokens`

Quelle: `docs/design/colors_and_type.css` definiert die CSS-Variablen. `KubbTokens` in `lib/core/ui/theme/kubb_tokens.dart` ist das Flutter-Spiegelbild.

### Farb-Tokens (verifiziert gegen das Kit-CSS)

| CSS-Variable | Flutter-Pendant | Hex |
|---|---|---|
| `--bk-bg` (light) | `tokens.bg` = `chalk50` | `#FBFAF6` |
| `--bk-bg-raised` | `tokens.bgRaised` = `chalk0` | `#FFFFFF` |
| `--bk-bg-sunken` | `tokens.bgSunken` = `chalk100` | `#F4F1E8` |
| `--bk-fg` | `tokens.fg` = `stone900` | `#0C0B07` |
| `--bk-fg-muted` | `tokens.fgMuted` = `stone500` | `#4D4B40` |
| `--bk-line` | `tokens.line` = `stone200` | `#CFCCC1` |
| `--bk-line-strong` | `tokens.lineStrong` = `stone900` | `#0C0B07` |
| `--bk-primary` | `tokens.primary` = `meadow500` | `#3A7C2E` |
| `--bk-on-primary` | `tokens.onPrimary` = `chalk50` | `#FBFAF6` |
| `--bk-meadow-500/600/100` | `KubbTokens.meadow500/600/100` | `#3A7C2E / #2D6324 / #D6EAD0` |
| `--bk-wood-500/400/100` | `KubbTokens.wood500/400/100` | `#A16F24 / #C08A33 / F1E1BF` |
| `--bk-stone-900/700/200/100` | `KubbTokens.stone900/700/200/100` | passend |
| `--bk-chalk-50` | `KubbTokens.chalk50` | `#FBFAF6` |
| `--bk-hit` | `KubbTokens.hit` | `#2D6324` |
| `--bk-miss` | `KubbTokens.miss` / `tokens.danger` | `#B73A2A` |
| `--bk-heli` | `KubbTokens.heli` | `#C08A33` |
| `--bk-penalty` | `KubbTokens.penalty` | `#8A1F3D` |
| `--bk-king` | `KubbTokens.king` | `#C89B3D` |
| `--bk-danger` | `tokens.danger` | `KubbTokens.miss` (`#B73A2A`) |

**Beobachtung**: Das Kit nutzt zusaetzlich `--bk-on-danger`. In `KubbTokens` ist das `onDanger: chalk50`. Passt.

### Typografie-Tokens

| CSS | Flutter |
|---|---|
| `var(--bk-font-display)` | Bricolage Grotesque (per ThemeData / google_fonts) |
| `var(--bk-font-body)` | Bricolage Grotesque |
| `var(--bk-font-mono)` | JetBrains Mono |
| `fontVariantNumeric: tabular-nums` | `FontFeature.tabularFigures()` |

### Spacing / Radii / Shadows

| CSS | Flutter |
|---|---|
| 4 | `KubbTokens.space1` |
| 8 | `KubbTokens.space2` |
| 12 | `KubbTokens.space3` |
| 16 | `KubbTokens.space4` |
| 20 | `KubbTokens.space5` |
| 24 | `KubbTokens.space6` |
| 32 | `KubbTokens.space8` |
| 40 | `KubbTokens.space10` |
| 48 | `KubbTokens.space12` |
| `borderRadius: 4 / 8 / 12 / 16 / 999` | `radiusSm / radiusMd / radiusLg / radiusXl / radiusPill` |
| `--bk-shadow-1 / -2` | nicht direkt im `KubbTokens` — pruefen ob Material-Elevation oder explizite `BoxShadow` |

**Luecke**: `KubbTokens` hat keine `shadow1` / `shadow2` Konstanten. JSX-Kit verwendet `var(--bk-shadow-1)` (Tournier-Card, Mode-Cards) und `var(--bk-shadow-2)` (FAB). Empfehlung: zwei `BoxShadow`-Listen in `KubbTokens` ergaenzen oder via `ThemeData.cardTheme` / `elevatedButtonTheme` standardisieren.

### Touch-Targets

| CSS | Flutter |
|---|---|
| `--bk-touch-min` 48dp | `KubbTokens.touchMin` 48 |
| `--bk-touch-comfortable` 64dp | `KubbTokens.touchComfortable` 64 |

## Quality-Gate-Checkliste — shared library

- [ ] `KubbAppBar` deckt alle JSX-AppBar-Use-Cases ab (eyebrow, title, leading, actions). Title-Alignment (center vs. start) explizit entscheiden.
- [ ] Icon-Mapping: alle 25 JSX-Icon-Namen einem Lucide- oder CustomPainter-Icon zugeordnet (Tabelle in `lib/core/ui/icons.dart`).
- [ ] `KubbBottomSheet`-Wrapper deckt Backdrop + Sheet + Grabber + Head-Slot ab.
- [ ] Section-Eyebrow als wiederverwendbares Widget (`KubbSectionLabel` / `KubbEyebrow`).
- [ ] `KubbSegmentedControl<T>` als Widget existiert (genutzt von Profile + Stats-Tab-Alternative).
- [ ] `KubbFieldRow` und `KubbNavRow` als Standardzeilen verfuegbar.
- [ ] `KubbStatPill` (Multi-Distance-Breakdown) als Widget verfuegbar.
- [ ] `KubbVerdictBanner` (Summary-Hero) als Widget verfuegbar.
- [ ] Shadow-Tokens (`shadow1`, `shadow2`) in `KubbTokens` ergaenzt.
- [ ] Alle Tokens-Namen werden aus `KubbTokens` referenziert — keine inline-Hex-Werte in den Screens (Ausnahme `EditProfileScreen._avatarPalette` ist Domain-Daten, nicht Theme).

## Bekannte Abweichungen (Flutter aktuell vs. Design)

1. **Title-Alignment AppBar**: JSX zentriert; `KubbAppBar` setzt kein explizites Alignment, das `Expanded`-Column laesst es link-buendig. Entscheidung treffen.
2. **Shared-Sheet-Wrapper**: `kubb_bottom_sheet.dart` ist vorhanden, die Inhalts-Sheets (Training-Sheet, Filter-Sheet, Password-Sheet) sind aber alle Custom — pruefen, ob sie auf eine gemeinsame Wrapper-Komponente reduzierbar sind.
3. **`KubbSegmentedControl` fehlt** als geteiltes Widget. Profile-Screen wird das brauchen (Wurfhand, Stamm-Distanz).
4. **`KubbStatPill` fehlt** — derzeit waeren Multi-Distance-Breakdowns im Summary inline gebaut.
5. **Shadow-Tokens fehlen** im `KubbTokens`. Material-Elevation ist nicht 1:1 zur JSX-Spec.
6. **Eyebrow als Widget** — derzeit wird das Pattern in jedem Screen kopiert. Konsolidierung lohnt.
