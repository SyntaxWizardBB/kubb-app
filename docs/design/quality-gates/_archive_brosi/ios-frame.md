# Quality-Gate: iOS-Frame (Screen-Shell-Pattern)

**Quelle**: docs/design/ui_kits/app/ios-frame.jsx
**Flutter-Pendant**: lib/app/app.dart (`MaterialApp.router`) + `Scaffold` + `KubbAppBar` + `SafeArea` pro Screen
**Stand**: 2026-05-28

## Visual-Spec

Das iOS-Frame-File definiert das aeussere Geruest fuer das HTML/JSX-Prototyping. Es ist KEIN Pixel-fuer-Pixel-Ziel der App — sondern die Demonstrationshuelle, in der die einzelnen Screens im Browser-Preview gerendert werden. Fuer Flutter heisst das: das Frame-Pattern wird nicht 1:1 nachgebaut, sondern via Material-Scaffold + SafeArea + KubbAppBar geliefert. Das Quality-Gate dokumentiert das Mapping, damit alle Screens dasselbe Shell-Verhalten teilen.

- **Layout-Struktur (Prototyp-Frame)**
  - `IOSDevice` Container: 402 x 874 px (iPhone-15-Pro-Maess), Radius 48 px, Drop-Shadow als Geraete-Look.
  - Status-Bar (Time + Signal + Wifi + Battery) oben, 44 dp hoch, ueberdeckt von Dynamic-Island (126 x 37 px, top: 11 px).
  - Optional `IOSNavBar`: Glass-Pill Back-Button + Glass-Pill Trailing-Icon + Large-Title (34 px Bold).
  - Content-Slot mit `flex: 1; overflow: auto`.
  - Optionale Keyboard-Komponente am Bottom (iOS-26-Liquid-Glass-Layout).
  - Home-Indicator-Pill (139 x 5 px) ueber allem mit `pointer-events: none`.

- **Layout-Struktur (Flutter-Mapping)**
  - `MaterialApp.router` als Root, liefert Themen und Routing.
  - `Scaffold(backgroundColor: tokens.bg, appBar: KubbAppBar(...), body: ...)` pro Screen.
  - `SafeArea` impliziert ueber `Scaffold`-Default (Top und Bottom).
  - Status-Bar-Styling via `SystemUiOverlayStyle.dark/light`, basierend auf `tokens.bg`-Helligkeit.
  - Tab-Bar gibt es nicht — Navigation laeuft ueber `go_router` Push-Stack.
  - Home-Indicator wird vom OS gerendert; in Flutter genuegt `SafeArea` am Bottom.

- **Farben (Frame-Chrome)**
  - Status-Bar-Glyph (Time/Battery): `#000` im Light-Mode, `#fff` im Dark-Mode -> in Flutter via `SystemUiOverlayStyle(statusBarIconBrightness)`.
  - Glass-Pill Light-Mode: `rgba(255,255,255,0.5)` + Backdrop-Filter — kein direktes Flutter-Aequivalent. Wir nutzen stattdessen flache `KubbAppBar`-Buttons.
  - Glass-Pill Dark-Mode: `rgba(120,120,128,0.28)` + Backdrop-Filter.
  - Nav-Bar-Title-Light: `#000`; Dark: `#fff`.
  - Inset-List-Card-Background: `#fff` light / `#1C1C1E` dark.

- **Typografie**
  - Frame-Status-Bar: `-apple-system, "SF Pro"`, 17 px / 22 px line, FontWeight 590.
  - Large-Title (Nav-Bar): 34 px / 41 px / 700 / letterSpacing 0.4.
  - List-Header (uppercase): 13 px, `rgba(60,60,67,0.6)`, padding 8/36/6.
  - List-Row: 17 px, letterSpacing -0.43.
  - Diese iOS-Werte werden in Flutter NICHT 1:1 uebernommen — `KubbAppBar` nutzt eigene Display-Font + 18 px Title (siehe Visual-Spec der Screen-Quality-Gates).

- **Spacing**
  - Status-Bar Padding: 21 px oben / 19 px unten / 24 px seitlich (Prototype only).
  - Nav-Bar Padding: 62 px Top (laesst Platz fuer Status-Bar + Dynamic-Island) / 10 px Bottom / 16 px horizontal.
  - List-Card Aussenrand: 16 px (`space4`).
  - Home-Indicator Bottom-Padding: 8 px / Pill-Hoehe 5 px / Container-Hoehe 34 dp.

- **Border-Radius**
  - Device: 48 px.
  - List-Card (`IOSList`): 26 px — deutlich groesser als unsere 14 px im Settings-Screen. **Bewusste Abweichung in der Flutter-Implementation**: wir halten 14 px, weil das mit dem restlichen App-Style konsistenter ist.
  - Glass-Pill: `9999` (radiusPill).
  - List-Row-Icon: 7 px (`radiusSm`).

- **Shadows**
  - Device: `0 40px 80px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.12)` — Prototype only.
  - Glass-Pill Light: zwei Layer Soft-Shadow.
  - Keyboard: leichter Top-Shadow.
  - Flutter-App rendert direkt am Geraete — keine simulierten Device-Schatten.

- **Icons**
  - Status-Bar-SVGs (Signal/Wifi/Battery) — vom System gerendert.
  - Chevron in List-Row: 8 x 14 px Stroke-Glyph in `rgba(60,60,67,0.3)`.
  - Glass-Pill-Back-Chevron: 12 x 20 px Stroke.
  - Keyboard-Glyphs (Shift/Delete/Return) als Inline-SVGs.

## Komponenten-Inventar (Prototype-seitig)

- `IOSDevice({width, height, dark, title, keyboard, children})` — kompletter Geraete-Frame.
- `IOSStatusBar({dark, time})` — Time + Signal/Wifi/Battery-Glyphs.
- `IOSNavBar({title, dark, trailingIcon})` — Back-Pill + Trailing-Pill + Large-Title.
- `IOSGlassPill({children, dark, style})` — wiederverwendbare Liquid-Glass-Capsule.
- `IOSList({header, dark, children})` — Inset-Card-Container fuer Listen-Rows.
- `IOSListRow({title, detail, icon, chevron, isLast, dark})` — eine Listen-Row.
- `IOSKeyboard({dark})` — iOS-26-Tastatur als statisches Bild.

## Komponenten-Inventar (Flutter-seitig)

- `MaterialApp.router` mit `theme: KubbTheme.light()` / `darkTheme: KubbTheme.dark()` / `themeMode: settings.themeChoice.toThemeMode()`.
- `Scaffold` als Per-Screen-Container.
- `KubbAppBar` als Header (entspricht `IOSNavBar` semantisch, nicht visuell).
- `SafeArea` an strategischen Stellen — meist als `SafeArea(top: false)` in Bottom-Sheets, ansonsten Default-`Scaffold`-Verhalten.
- `OfflineBanner` und `OutboxStatusBanner` als globaler Top-Strip im `MaterialApp.builder`.
- `SystemUiOverlayStyle` (in `KubbTheme`) steuert Status-Bar-Icon-Helligkeit pro Theme.

## Interaktions-Pattern

- **Status-Bar**
  - Flutter: `AnnotatedRegion<SystemUiOverlayStyle>` oder global via `ThemeData.appBarTheme.systemOverlayStyle`. Im aktuellen Setup wird das ueber `KubbTheme` gesteuert; pro Screen ist keine zusaetzliche Annotation noetig.
- **Navigation-Header**
  - `KubbAppBar` ersetzt `IOSNavBar`. Back-Button rendert nur, wenn `Navigator.of(context).canPop()`.
  - Trailing-Slot via `actions`-Parameter (analog zu `right` im `shared.jsx` `AppBar`).
  - Sticky-Verhalten: aktuell nicht implementiert; `KubbAppBar` ist Teil von `Scaffold.appBar`, also automatisch sticky.
- **Safe-Area**
  - Top: `Scaffold` reserviert Platz fuer den `AppBar`, der seinerseits 54 dp Top-Padding hat (siehe `KubbAppBar`-Code), was den iOS-Status-Bar-Bereich beruecksichtigt.
  - Bottom: Bottom-Sheets verwenden `SafeArea(top: false)`, damit der Home-Indicator nicht ueberdeckt wird. Settings-Screen scrollt ohne expliziten `SafeArea`-Wrapper, weil `Scaffold` das default macht.
- **Tab-Bar**
  - Phase 1 hat keine globale Tab-Bar — Home -> Push auf Sub-Screens via `go_router`.
- **Tastatur-Verhalten (kritisch)**
  - Frame-`IOSKeyboard` ist nur Prototype-Sicht.
  - Flutter: Tastatur kommt vom System. Modals MUESSEN `padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)` haben, sonst werden Inhalte ueberdeckt -> Maengel #2.4.
  - Scaffold mit Text-Fields: `resizeToAvoidBottomInset: true` (Default) + `SingleChildScrollView` um den Body.
- **Backdrop / Modal-Animation**
  - `showModalBottomSheet` mit `isScrollControlled: true` ist der Default fuer alle Sheets (siehe `CsvExportModal`, `KubbBottomSheet`).
  - Backdrop dunkel ~ 55 % Alpha, vom Material-Default ueberschrieben falls noetig.
  - Slide-up-Curve: Material-Default (~ 250 ms ease-out).

## Accessibility

- Tap-Targets
  - `KubbAppBar`-Back-Button: 48 dp x 48 dp via `BoxConstraints.tightFor`.
  - Trailing-Actions im AppBar: minBreite 48 dp via `ConstrainedBox`.
  - System-Back (Android) wird vom Navigator-Stack ohne Extra-Code unterstuetzt.
- Status-Bar-Kontrast: dunkle Glyphs auf hellem `bg`, helle Glyphs auf dunklem `bg` — `SystemUiOverlayStyle` reagiert auf `Brightness`.
- Safe-Area: Home-Indicator + Notch werden via `Scaffold` und `SafeArea` korrekt umflossen — kein Content-Clipping.
- Keyboard-Overflow: Maengel #2.4 fordert explizit, dass alle Forms im Modal beim Keyboard-Open scrollbar bleiben. Quality-Gate gilt fuer alle neuen Modale.
- Text-Skalierung: `MaterialApp` respektiert `MediaQuery.textScaleFactor` — Layout darf nicht hart auf Pixel-Heights brechen. `KubbAppBar.preferredSize` ist fix 88 dp; das ist eine kalkulierte Toleranz, kein Bug.

## Quality-Gate-Checkliste (gilt fuer ALLE Screens)

- [ ] Jeder Screen verwendet `Scaffold(backgroundColor: tokens.bg, appBar: KubbAppBar(...))`.
- [ ] Kein hartes `Padding(top: 54)`-Hack in Screens — `KubbAppBar` handelt das.
- [ ] Status-Bar-Icons matchen das Theme (light Theme -> dunkle Icons, dark Theme -> helle Icons) via `SystemUiOverlayStyle`.
- [ ] Bottom-Sheets nutzen `SafeArea(top: false)` und `viewInsets.bottom`-Padding.
- [ ] `isScrollControlled: true` bei allen Sheets, die einen Form-Input enthalten koennten.
- [ ] Touch-Targets >= 48 dp fuer alle interaktiven Header-Elemente.
- [ ] `MaterialApp.builder` injiziert `OfflineBanner` + `OutboxStatusBanner` als Top-Strip — Layout-Hoehe muss das beruecksichtigen.
- [ ] Theme-Mode-Wechsel (light/dark/highContrast) aendert sowohl `tokens.bg` als auch die Status-Bar-Icon-Helligkeit.
- [ ] Keine Verwendung von iOS-Spezifika wie `CupertinoNavigationBar` — der App-Stil ist Material-3-basiert.
- [ ] go_router-System-Back funktioniert auf Android (gestisch + Back-Button) und iOS (Swipe-from-Edge).

## Bekannte Abweichungen (Flutter aktuell vs. Design)

- **Kein Liquid-Glass-Effekt**. Die JSX-Prototypes nutzen `backdrop-filter: blur(12px) saturate(180%)`, was in Flutter nur via `BackdropFilter` mit `ImageFilter.blur` realisierbar ist und teurer rendert. Quality-Gate-Entscheidung: bewusster Verzicht, weil unser App-Stil "flach, hoher Kontrast, outdoor-lesbar" ist und sich von der iOS-Spielerei abgrenzt.
- **Dynamic-Island wird nicht simuliert**. Die App rendert direkt auf dem Geraet; die Notch wird vom OS und von `SafeArea` korrekt umflossen.
- **Large-Title (34 px) wird nicht uebernommen**. `KubbAppBar` nutzt 18 px Display-Font fuer den Titel. Owner-Entscheidung gemaess Design-System-ADR (ADR-0008).
- **Glass-Pill-Back-Button wird durch Material `IconButton` ersetzt**. Semantisch identisch (Back-Navigation), visuell flacher.
- **Inset-List-Radius**. Design: 26 px, Flutter: 14 px. Konsistente Entscheidung ueber alle Screens.
- **`IOSKeyboard` ist Prototype-only**. Flutter delegiert die Tastatur immer ans OS — keine eigene Keyboard-Komponente.
- **Banner-Strip oben**. `MaterialApp.builder` injiziert `OfflineBanner` + `OutboxStatusBanner` ueber dem Routes-Content. Diese Konstellation existiert im Design nicht (das Frame hat keinen Banner). Flutter-spezifische Erweiterung, sollte aber im Layout-Budget jedes Screens beruecksichtigt sein.
