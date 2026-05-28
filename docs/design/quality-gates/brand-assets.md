# Quality-Gate: Brand-Assets (Kubb Club)

**Quelle**: `docs/design/preview/brand-*.html` (5 Previews) + `docs/design/assets/*.svg` (6 SVGs)
**Flutter-Pendant**: `lib/core/ui/icons.dart`, `assets/` (Flutter-Bundle), `android/app/src/main/res/`, `ios/Runner/Assets.xcassets/`, `web/`
**Stand**: 2026-05-28 (Rebrand `--bk-*` → `--kc-*`, Kubb Club)
**Cross-Reference**: `docs/design/AUDIT.md` §2.1 (Rebrand-Blocker), §2.2 (Launch Screens), §5 (Brand-Glyphen als CustomPainter)

> Diese Datei ist das Brand-Audit. Komponenten-Library siehe `component-library.md`.

---

## Logo-Varianten

Das Mark zeigt durchgehend: drei Wurfstöcke (Wood) plus eine goldene Krone auf einem grünen Sockel — der Königsstoss als Brand-Hero. Variationen unterscheiden sich nur im Backdrop und im Kontext.

### A — Logo-Mark (Standard)
- **File**: `docs/design/assets/logo-mark.svg` (240 × 240, Radius 52)
- **Backdrop**: Meadow-Gradient `#56a142 → #1f4615`, Inset-Border `#fbfaf6` opacity 0.35
- **Use-Cases**:
  - App-Icon iOS/Android (primary)
  - Web-PWA `Icon-512.png` / `Icon-192.png`
  - Home-AppBar Logo-Slot (klein, 32 dp)
  - Splash-Screen-Variante A + B + C + E (Meadow + Chalk + Web-Lockup)
- **Empfohlene Sizes (Bundle)**: 16 / 24 / 32 / 48 / 64 / 96 / 128 / 192 / 512 / 1024
- **On-Color-Pairings**: funktioniert auf Chalk-, Wood- und Stone-Backgrounds dank eigener Meadow-Card. Auf Meadow-Background → Roundel-Variante stattdessen.

### B — Logo-Mark-Chalk
- **File**: `docs/design/assets/logo-mark-chalk.svg`
- **Backdrop**: Chalk-Gradient `#fbfaf6 → #ece6d2` mit Pitch-Lines (grüne Spielfeld-Striche unten) und roten Augen-Detail
- **Use-Cases**:
  - Empty-States ("noch keine Sessions" / "keine Friends") — wirkt skizziert, nicht final
  - Tutorial-Vignette für Onboarding-Slide 1–2
  - On-light Backgrounds wo das Standard-Mark zu kontrastarm wäre
- **Empfohlene Sizes**: 96 / 128 / 192
- **On-Color-Pairings**: nur auf Light-Backgrounds (`--kc-bg`, `--kc-bg-raised`). Niemals auf Meadow oder Ink.

### C — Logo-Mark-Ink
- **File**: `docs/design/assets/logo-mark-ink.svg`
- **Backdrop**: Ink-Gradient `#232118 → #0a0905` plus grüner Radial-Glow
- **Use-Cases**:
  - Dark-Mode Default-Mark
  - Splash-Variante D (Dusk Mode)
  - Dark-Mode Empty-States
- **Empfohlene Sizes**: 96 / 128 / 192 / 512
- **On-Color-Pairings**: auf Ink-Background (`--kc-stone-900`), auf Wood-Backgrounds (Tournament-Card). Nicht auf Meadow — zu dunkel auf grün.

### D — Logo-Mark-Roundel
- **File**: `docs/design/assets/logo-mark-roundel.svg`
- **Backdrop**: rundes Meadow-Disk mit umlaufender Schrift "KUBB · CLUB" oben und "★ EST. 2025 ★" unten, Krone+Stäbe als kleinerer Crest in Chalk-Inneren
- **Use-Cases**:
  - Achievements / Badges (siehe AUDIT.md §4.6)
  - Tournament-Trophäen-Karte
  - Share-Sheet "Match-Karte" Header
  - Veranstalter-Stempel (Saison-Anmeldung)
- **Empfohlene Sizes**: 96 / 128 / 192 / 256
- **On-Color-Pairings**: stand-alone — der Roundel hat eigene Border. Kein zusätzlicher Background nötig.

### E — Logo-Monogram
- **File**: `docs/design/assets/logo-monogram.svg`
- **Inhalt**: gleicher Crest wie Standard-Mark, aber ohne Card-Backdrop — pure Wurfstöcke + Krone auf transparent
- **Use-Cases**:
  - Inline-Glyph in Body-Text ("Kubb Club Member")
  - Watermark in PDFs / CSV-Exports
  - Loading-Skeleton-Vignette (klein zentriert auf grauem Hintergrund)
  - Favicon-Fallback (16/32)
- **Empfohlene Sizes**: 16 / 24 / 32 / 48 / 64
- **On-Color-Pairings**: jedes Background, muss aber genug Kontrast haben — der Crest ist grösstenteils Wood-Ton.

### F — Logo-Wordmark
- **File**: `docs/design/assets/logo-wordmark.svg` (640 × 200)
- **Inhalt**: Mark links (Meadow-Variante), rechts "Kubb" + "Club." als Fraunces 76 px / 68 px (Club. in Meadow-Grün), darunter "EST. 2025 · DACH" als JetBrains Mono 11 px, Gold-Hairline rechts
- **Use-Cases**:
  - Splash-Variante A / C / E (Wordmark-Lockup)
  - Web-Header / Marketing-Site
  - E-Mail-Footer
  - Onboarding-Slide 1 (Welcome)
  - LaunchScreen Tablet/Desktop (Variante E)
- **Empfohlene Sizes**: PNG bei 320 / 480 / 640 / 960 Breite, plus SVG als Master
- **On-Color-Pairings**: auf hellem Background — der Text ist `#0c0b07`. Für Dark-Mode separate Wordmark-Variante nötig oder Text-Color-Swap.

---

## Wordmark

Das Wordmark ist eigenständig in `logo-wordmark.svg` und in den Splash-Varianten A/C/D/E inline gerendert.

**Typografie**
- "Kubb" + "Club." → Fraunces, weight 700, `font-variation-settings: 'opsz' 144, 'SOFT' 30`
- "Club." in `--kc-meadow-500` (sonst `--kc-fg`)
- Tagline "EST. 2025 · DACH" → JetBrains Mono 11 px, letter-spacing 0.3em, uppercase

**Drift**: das SVG-Wordmark rendert "Club" mit Punkt, die Splash-Previews mit Punkt — konsistent. Web-Tagline ist im Wordmark `· DACH`, in den Splash-Captions teils ohne Region. Vor Web-Build vereinheitlichen.

**Use-Cases**
- Splash-Screens (alle Wide-Varianten)
- Web-Header (PNG bei 480 / 640 Breite)
- E-Mail
- PDF-Exporte (CSV/Tournament-Report)

---

## Splash-Screens

`brand-splash.html` zeigt 4 Mobile-Varianten + 1 Web/Tablet-Variante.

### Variante A — Meadow + Wordmark (Empfehlung als Standard)
- Background: Meadow-Gradient `#56a142 → #1f4615`
- Mark (140 dp) zentral oben, dann Wordmark "Kubb Club." (Club. in Gold-Yellow `#d9b14a`), Pitch-Hairline, Tagline
- Loader: Pill-Bar 120 × 3 dp am unteren Drittel, animiert sliding `#fce19a`
- Grass-Ticks am unteren Rand (≈24 sticks, height 8–16 dp, opacity 0.55)
- Rise-Animation: Mark 0.8 s ease, Wordmark 0.15 s delay, Tagline 0.30 s delay

### Variante B — Mark Only (App-Store-Konform)
- Gleicher Meadow-Background, nur Mark 170 dp zentriert
- Loader: 3 Breathing-Dots statt Pill
- Empfehlung: **iOS LaunchScreen.storyboard** und **Android `launch_background.xml`** (Apple verbietet UI-Text auf LaunchScreens, also Mark-only)

### Variante C — Chalk Daytime
- Background: Chalk-Gradient `#fbfaf6 → #ece6d2`
- Mark + Wordmark (Text `#0c0b07`, "Club." in Meadow), Pitch-Hairline in Meadow opacity 0.7
- Loader: dunkle Pill auf hellem Grund
- **Verwendung**: Light-Mode-User-Preference oder Tageszeit-aware Variante (post-Phase-1)

### Variante D — Ink Dusk Mode
- Background: Ink-Radial + Vertical Gradient (`#232118 → #0a0905` + Meadow-Glow)
- Mark = `logo-mark-ink.svg` (mit Inner-Glow-Filter)
- Wordmark in `#fbfaf6`, "Club." in Gold `#d9b14a`, Tagline in Gold opacity 0.8
- Breathing-Dots-Loader
- **Verwendung**: Dark-Mode-User-Preference oder System-Dark-Mode

### Variante E — Web/Tablet Horizontal Lockup
- Wide-Format 480 × 300 (skaliert auf 1280 × 800)
- Mark (96 dp) links, Wordmark (48 px) rechts, alles auf Meadow-Background
- Loader unten zentriert
- **Verwendung**: `web/index.html` Body-Loader und Tablet-Splash

### Platform-Pflicht-Anforderungen

#### iOS — `LaunchScreen.storyboard`
- **Aktuell**: Flutter-Default (weisses Bild, kein Branding)
- **Soll**: zentriertes `logo-mark.svg` als PDF-Asset oder PNG@3x, Background-Color = Meadow-Gradient (per UIImageView mit Gradient-Image)
- **Pflicht**:
  - Storyboard-File: `ios/Runner/Base.lproj/LaunchScreen.storyboard`
  - Asset-Catalog: `ios/Runner/Assets.xcassets/LaunchImage.imageset/` (LaunchImage.png @1x / @2x / @3x bei 100/200/300 px Logo-Höhe)
  - Background-Color via Color-Asset oder Storyboard-Background-View

#### Android — `launch_background.xml`
- **Aktuell**: `android/app/src/main/res/drawable/launch_background.xml` ist Default (weiss, kein Logo)
- **Soll**:
  ```xml
  <layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@drawable/kc_splash_meadow"/>
    <item android:gravity="center"><bitmap android:src="@mipmap/ic_launcher" android:gravity="center"/></item>
  </layer-list>
  ```
- **Pflicht**:
  - `drawable/kc_splash_meadow.xml` (gradient-drawable mit `startColor=#56a142`, `endColor=#1f4615`)
  - Logo in `mipmap-*dpi/ic_launcher.png` aus der App-Icon-Pipeline (siehe unten)
  - Auch `drawable-v21/launch_background.xml` updaten

#### Web — `web/index.html`
- **Aktuell**: Standard Flutter-Loader (weiss)
- **Soll**: `<body>`-Pre-Loader mit Meadow-Background + zentriertem Mark + Pill-Loader, ersetzt durch Flutter wenn `flutter_bootstrap.js` lädt
- **Pflicht**:
  - Inline-Style oder externes CSS `splash.css` mit Meadow-Gradient
  - `<img src="icons/Icon-192.png">` als Mark
  - `web/manifest.json` → `background_color: "#3a7c2e"`, `theme_color: "#3a7c2e"`

---

## Brand-Backgrounds

`brand-backgrounds.html` zeigt 4 Backdrop-Patterns für Hero-Bereiche.

### Meadow Gradient
- `linear-gradient(180deg, #3a7c2e 0%, #2d6324 100%)`
- **Use-Cases**: Match-Tag Hero auf Home, Tournament-Detail-Header, Active-Session-Indicator
- **Flutter**: `Container(decoration: BoxDecoration(gradient: LinearGradient(...)))` als `KubbBackground.meadow` Wrapper

### Ink — Night Play
- `#0c0b07` flat
- **Use-Cases**: Stats-Tab Hero, Achievements-Screen Background, Dark-Mode Default für Modals
- **Flutter**: `KubbBackground.ink`

### Chalk — Pitch Lines
- `--kc-chalk-50` Background + repeating-linear-gradient (28 / 30 px) als Pitch-Line-Pattern, opacity 0.55
- **Use-Cases**: Training-Wiese-Hero, Empty-State-Backdrop, Profile-Cover
- **Flutter**: `KubbBackground.chalkPitch` mit `CustomPainter` für die Linien (cheap, < 30 LOC)

### Wood — Tournament/Saison
- `linear-gradient(180deg, #a16f24 0%, #604015 100%)`
- **Use-Cases**: Tournament-Card Hero, Saison-Übersicht-Header, Veranstalter-Bereich
- **Flutter**: `KubbBackground.wood`

**Vorschlag**: alle vier als statisches `lib/core/ui/widgets/kubb_background.dart` mit `enum KubbBackgroundTone { meadow, ink, chalkPitch, wood }`. Etwa 60 LOC, zentralisiert alle Hero-Painters.

---

## App-Icon-Pipeline (AUDIT.md §2.1 — Rebrand-Blocker)

> **Diese Pipeline blockiert TestFlight + Play Console Submission.** Die SVG-Master existieren, die rasterized PNGs für die Plattform-Asset-Kataloge fehlen.

### iOS Asset Catalog
**Path**: `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
**Pflicht-Sizes** (alle als PNG @1x):

| Size (px) | Filename-Konvention | Zweck |
|---|---|---|
| 1024 | `Icon-App-1024x1024@1x.png` | App-Store-Marketing |
| 180 | `Icon-App-60x60@3x.png` | iPhone @3x |
| 167 | `Icon-App-83.5x83.5@2x.png` | iPad Pro |
| 152 | `Icon-App-76x76@2x.png` | iPad @2x |
| 120 | `Icon-App-60x60@2x.png` | iPhone @2x |
| 87 | `Icon-App-29x29@3x.png` | Spotlight @3x |
| 80 | `Icon-App-40x40@2x.png` | Spotlight @2x |
| 76 | `Icon-App-76x76@1x.png` | iPad @1x |
| 60 | `Icon-App-20x20@3x.png` | Notifications @3x |
| 58 | `Icon-App-29x29@2x.png` | Settings @2x |
| 40 | `Icon-App-20x20@2x.png` | Notifications @2x |
| 29 | `Icon-App-29x29@1x.png` | Settings @1x |
| 20 | `Icon-App-20x20@1x.png` | Notifications @1x |

**Source-SVG**: `docs/design/assets/logo-mark.svg`
**Contents.json** muss alle Einträge referenzieren (Apple-Schema).

### Android Mipmap
**Path**: `android/app/src/main/res/mipmap-<dpi>/ic_launcher.png`

| Density | Size (px) | DPI |
|---|---|---|
| mdpi | 48 | 1× |
| hdpi | 72 | 1.5× |
| xhdpi | 96 | 2× |
| xxhdpi | 144 | 3× |
| xxxhdpi | 192 | 4× |

**Aktuell**: alle 5 PNGs existieren als Flutter-Default — müssen mit Kubb-Club-Mark überschrieben werden.

**Adaptive Icon (Android 8+)**:
- `mipmap-anydpi-v26/ic_launcher.xml` (existiert wahrscheinlich nicht — neu)
- Foreground: `ic_launcher_foreground.xml` — nur der Crest (Wurfstöcke + Krone, ohne Card-Background) auf 108 × 108 dp Layer, sicherer Bereich 66 × 66 dp
- Background: `ic_launcher_background.xml` — Meadow-Gradient als Vector-Drawable oder als Solid Color (`#3a7c2e`)
- **Source**: `logo-monogram.svg` für Foreground (keine Card), Meadow-Gradient für Background

### Web PWA
**Path**: `web/icons/`

| Size (px) | Filename (existiert) | Soll |
|---|---|---|
| 192 | `Icon-192.png` | aus `logo-mark.svg` rasterisiert |
| 512 | `Icon-512.png` | aus `logo-mark.svg` rasterisiert |
| 192 maskable | `Icon-maskable-192.png` | aus `logo-monogram.svg` (Crest) auf Meadow-Solid mit 20 % Safe-Zone-Padding |
| 512 maskable | `Icon-maskable-512.png` | wie oben in 512 |

**Manifest** (`web/manifest.json`):
- `name`: "Kubb Club"
- `short_name`: "Kubb Club"
- `background_color`: "#3a7c2e" (Meadow)
- `theme_color`: "#3a7c2e"
- Icons-Array auf neue PNGs zeigen

### Favicon
**Path**: `web/`

| Asset | Size | Source |
|---|---|---|
| `favicon.png` | 16 + 32 (multi-PNG oder ICO) | `logo-monogram.svg` rasterisiert |
| `favicon.ico` | 16, 32, 48 in einer ICO | empfohlen für Legacy-Browser |
| `apple-touch-icon.png` | 180 × 180 | `logo-mark.svg` rasterisiert |

`web/index.html` muss `<link rel="apple-touch-icon" href="apple-touch-icon.png">` referenzieren.

---

## SVG-zu-PNG-Pipeline

**Empfehlung**: Node-basiertes Script mit Sharp (Cross-Platform, deterministisch, deutlich schneller als ImageMagick für 30+ Sizes).

**Setup**: `scripts/build-icons.mjs` (one-off, nicht in Flutter-Build-Chain)
```bash
npm install --save-dev sharp
```

**Beispiel-Befehl pro iOS-Size**:
```js
import sharp from 'sharp';
await sharp('docs/design/assets/logo-mark.svg')
  .resize(180, 180)
  .png()
  .toFile('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png');
```

**Alternative**: ImageMagick (falls Node nicht erwünscht)
```bash
convert -background none -density 1024 \
  docs/design/assets/logo-mark.svg -resize 180x180 \
  ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png
```

**Output-Counts (zur Sanity-Prüfung)**:
- iOS: 13 PNGs
- Android (legacy mipmap): 5 PNGs
- Android (adaptive): 2 XML + 1 PNG (Foreground-Asset) + 1 Color (Background)
- Web: 4 PNGs
- Favicon: 2 PNGs + 1 ICO + 1 apple-touch-icon
- **Total**: ~28 raster-Assets + 2-3 XML-Drawables

---

## Quality-Gate-Checkliste

- [ ] Alle 6 Logo-SVG-Varianten in `assets/brand/` deployed (Flutter-Bundle, nicht nur `docs/design/assets/`)
- [ ] `pubspec.yaml` listet `assets/brand/` unter `flutter.assets`
- [ ] App-Icon-PNGs in iOS Asset-Catalog (alle 13 Sizes + Contents.json)
- [ ] App-Icon-PNGs in Android mipmap-*dpi (alle 5 Sizes)
- [ ] Android Adaptive Icon: `mipmap-anydpi-v26/ic_launcher.xml` + Foreground/Background-Drawables
- [ ] Web PWA: 4 Icon-PNGs (192/512 + maskable-Varianten)
- [ ] Favicon: 16/32 ICO + 180 apple-touch-icon in `web/`
- [ ] iOS `LaunchScreen.storyboard` mit Meadow-Background + Mark-Asset ersetzt
- [ ] Android `launch_background.xml` (drawable + drawable-v21) mit Meadow-Gradient + Logo ersetzt
- [ ] Web `index.html` Body-Loader mit Meadow + Mark ersetzt
- [ ] `web/manifest.json`: `name`, `short_name`, `background_color`, `theme_color` auf Kubb Club / Meadow
- [ ] `android/app/src/main/AndroidManifest.xml` → `android:label="Kubb Club"`
- [ ] `ios/Runner/Info.plist` → `CFBundleDisplayName = Kubb Club`
- [ ] `KubbBackground.{meadow,ink,chalkPitch,wood}` als Flutter-Widget implementiert
- [ ] Brand-Glyphen (Heli, King, Cup, Crown) als CustomPainter implementiert — ersetzt Lucide-Substitutes in `lib/core/ui/icons.dart` (siehe AUDIT.md §5)
- [ ] Build-Script `scripts/build-icons.mjs` (Sharp) ist im Repo, dokumentiert in README
- [ ] `KubbAppBar` Home-Variante mit Logo-Slot (Mark 32 dp) angebunden
- [ ] SVG-zu-PNG-Pipeline ist reproduzierbar (Pinned-Sharp-Version, deterministischer Output)

---

## Bekannte Abweichungen / Folge-Actions

- **`lib/core/ui/icons.dart` ist noch auf Lucide-Substitutes** (`heli → wind`, `king → crown`, `cup → trophy`). Kommentar im File kündigt CustomPainter als "future task" an. Solange das nicht fertig ist, ist der Heli-Icon ein generischer Wind-Glyph — Brand-Drift.
- **Splash auf allen Plattformen ist Flutter-Default.** AUDIT.md §2.2 markiert das als Rebrand-Blocker.
- **Wordmark-Tagline-Variante** — SVG hat "EST. 2025 · DACH", Splash-Captions teils nur "EST. 2025". Vor Web-Launch entscheiden, ob die Region (DACH) im Wordmark global mitläuft oder nur in DACH-Region-Builds. Owner-Entscheidung.
- **Roundel als Achievement-Basis** — die Achievements aus AUDIT.md §4.6 sind noch nicht designt. Der Roundel ist Vorlage für 12-15 Badge-Varianten, jeweils mit eigenem Crest im Inneren (z.B. "100 Hits" = Mark + Zahl, "Heli-Master" = Mark + Wind-Glyph).
- **Light/Dark-Mode-Switch im Splash** — Variante C (Chalk) vs. D (Ink) sind manuell wählbar. Empfehlung: System-Preference-aware in Phase 2, vorerst nur Meadow + Mark-only (A/B) ausliefern.
- **Adaptive-Icon Safe-Zone** — Android 8+ croppt den Foreground in verschiedene Shapes (Circle, Square, Rounded, Squircle). Der Crest aus `logo-monogram.svg` muss in einem 66/108-Safe-Bereich liegen, sonst werden Krone-Spitzen abgeschnitten. Vor Export prüfen.
- **Wordmark Dark-Variante fehlt** — `logo-wordmark.svg` hat hartkodierte dunkle Textfarbe (`#0c0b07`). Für Dark-Mode-Header braucht es entweder eine zweite SVG oder ein Runtime-Color-Swap (SVG via `flutter_svg` mit Color-Filter). Owner-Entscheidung.
