# Quality-Gate: Design-Tokens (Kubb Club)

**Quelle**: `docs/design/colors_and_type.css` (SSoT, `--kc-*` prefix)
**Flutter-Pendant**: `lib/core/ui/theme/kubb_tokens.dart`, `lib/core/ui/theme/kubb_theme.dart`
**Stand**: 2026-05-28 (Rebrand auf Kubb Club)
**Vorgaenger**: `docs/design/quality-gates/_archive_brosi/design-tokens.md` (Brosi-Era, `--bk-*` prefix)
**Audit-Bezug**: `docs/design/AUDIT.md`, `docs/design/REBRAND_README.md`

## Rebrand-Token-Aenderungen

Der Rebrand von "Brosi's Kubb" auf "Kubb Club" laesst die Farb-Hex-Werte bewusst unveraendert — das Token-System uebernimmt 1:1 (siehe `AUDIT.md` 1.: "fast 1:1 uebernommen und unter --kc-* rebrand'et"). Die Aenderungen liegen auf den Schichten Prefix, Typografie und Brand-Assets.

### Prefix-Switch

- `--bk-*` ist nicht entfernt, sondern am Ende von `colors_and_type.css` (Zeilen 358-416) als kompletter Alias-Block auf `--kc-*` durchgeschleift. Migration ist nicht-blockierend; HTML-Previews und Flutter-Surfaces koennen Stueck fuer Stueck umstellen.
- Im Flutter-Code (`kubb_tokens.dart`) gibt es keinen Prefix — die Konstanten heissen `meadow500`, `wood400` etc. Es entsteht also kein Rename-Aufwand auf Dart-Seite, nur die CSS-/HTML-Previews verwenden den neuen Prefix.

### Neue Tokens (in SSoT vorhanden, im Brosi-Audit nicht oder nur teilweise gelistet)

| Token | Wert | Zweck |
|---|---|---|
| `--kc-font-display` | `'Fraunces', 'Bricolage Grotesque', ui-serif, ...` | **Neu**: Fraunces als Display-Font fuer Wordmark, Hero-Heros, Desktop-Marketing |
| `--kc-text-7xl` | `168px` | Desktop hero counter |
| `--kc-radius-3xl` | `28px` | Brand-Cards, Splash-Mark |
| `--kc-shadow-4` | `0 4px 8px ..., 0 24px 48px ...` | Modal-Tier-Elevation |
| `--kc-container-narrow` | `720px` | Layout-Container fuer Lese-fokussiertes Desktop |
| `--kc-container` | `1080px` | Standard-Container |
| `--kc-container-wide` | `1280px` | Wide-Layout |
| `--kc-king` | `#c89b3d` | War bereits in Brosi-Audit dokumentiert, aber als Semantic-Token jetzt prominenter (Brand-Crown) |
| `.kc-wordmark` Klasse | Fraunces, opsz 144, SOFT 30 | **Neu**: dediziert fuer Kubb-Club-Logotype |
| `.kc-pitch-line` Klasse | 2px Linie auf `--kc-line-strong` | **Neu**: Section-Separator |
| Dark Mode (`.kc-dark`) | Surface-Token-Overrides | **Neu in SSoT**: vorher nur in Flutter (`KubbTokens.dark`); jetzt auch CSS-seitig dokumentiert |

### Aenderungen mit funktionaler Wirkung

- **Display-Font-Dualismus**: SSoT trennt explizit `--kc-font-display` (Fraunces) von `--kc-font-ui` (Bricolage). Brosi hatte beides als Bricolage gemappt. Aktueller Alias `--bk-font-display: var(--kc-font-ui)` haelt den Brosi-Code Bricolage-only. **Bedeutung**: mobile App bleibt Bricolage, Desktop/Marketing/Wordmark zieht Fraunces (siehe `colors_and_type.css` Z. 103-110).
- **Drei Mono-Weights** (`JetBrains Mono`: 400, 500, 700) sind im Google-Fonts-Import angefordert; das ist konsequent fuer Counter/Stat-Tabellen, aber Flutter bundelt JetBrains Mono noch nicht.
- **Wood-Skala** endet bei `wood-800`. Es gibt kein `wood-900` (anders als Meadow und Stone, die bis 900 gehen). Bewusste Designentscheidung — kein Defekt.

### Entfernt

Keine Tokens entfernt. Brosi-Aliases bleiben vollstaendig im Bottom-Block der CSS-Datei.

## Token-Inventar (vollstaendig)

### Farben — Meadow (Primary-Familie)

| CSS-Var | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--kc-meadow-50` | `#eef6ec` | `KubbTokens.meadow50` | Light surface tints |
| `--kc-meadow-100` | `#d6ead0` | `KubbTokens.meadow100` | Subtle chips / hover states |
| `--kc-meadow-200` | `#aed3a2` | `KubbTokens.meadow200` | Soft fill |
| `--kc-meadow-300` | `#7fb56f` | `KubbTokens.meadow300` | Dark-mode `primaryHover` |
| `--kc-meadow-400` | `#569748` | `KubbTokens.meadow400` | Dark-mode `primary` |
| `--kc-meadow-500` | `#3a7c2e` | `KubbTokens.meadow500` | Light-mode `primary` (Brand) |
| `--kc-meadow-600` | `#2d6324` | `KubbTokens.meadow600` | Light-mode `primaryHover`, `hit` |
| `--kc-meadow-700` | `#234e1c` | `KubbTokens.meadow700` | Light-mode `primaryPress` |
| `--kc-meadow-800` | `#1a3a16` | `KubbTokens.meadow800` | High-Contrast `primaryPress` |
| `--kc-meadow-900` | `#112710` | `KubbTokens.meadow900` | Reserve / ink |

### Farben — Stone (Neutral / BG)

| CSS-Var | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--kc-stone-50` | `#f4f3f0` | `KubbTokens.stone50` | Reserve |
| `--kc-stone-100` | `#e7e5df` | `KubbTokens.stone100` | Reserve |
| `--kc-stone-200` | `#cfccc1` | `KubbTokens.stone200` | Light-mode `line` |
| `--kc-stone-300` | `#a8a597` | `KubbTokens.stone300` | Dark-mode `fgMuted` |
| `--kc-stone-400` | `#777567` | `KubbTokens.stone400` | `fgSubtle` (alle Modi) |
| `--kc-stone-500` | `#4d4b40` | `KubbTokens.stone500` | Light-mode `fgMuted` |
| `--kc-stone-600` | `#34322a` | `KubbTokens.stone600` | Reserve |
| `--kc-stone-700` | `#232118` | `KubbTokens.stone700` | Dark-mode `line` |
| `--kc-stone-800` | `#161510` | `KubbTokens.stone800` | Dark-mode `bgRaised` |
| `--kc-stone-900` | `#0c0b07` | `KubbTokens.stone900` | Light-mode `fg`/`lineStrong`, Dark-mode `bg`, `onAccent` |

### Farben — Wood (Secondary / Accent)

| CSS-Var | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--kc-wood-50` | `#faf3e6` | `KubbTokens.wood50` | Warm tints |
| `--kc-wood-100` | `#f1e1bf` | `KubbTokens.wood100` | Soft fills |
| `--kc-wood-200` | `#e6c98c` | `KubbTokens.wood200` | Accent backgrounds |
| `--kc-wood-300` | `#d6ab57` | `KubbTokens.wood300` | Reserve |
| `--kc-wood-400` | `#c08a33` | `KubbTokens.wood400` | `accent` (alle Modi), Heli-Marker |
| `--kc-wood-500` | `#a16f24` | `KubbTokens.wood500` | `accentHover` |
| `--kc-wood-600` | `#80561c` | `KubbTokens.wood600` | High-Contrast `accentHover` |
| `--kc-wood-700` | `#604015` | `KubbTokens.wood700` | Reserve |
| `--kc-wood-800` | `#422c0e` | `KubbTokens.wood800` | Reserve |

### Farben — Chalk (Background-Surface)

| CSS-Var | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--kc-chalk-0` | `#ffffff` | `KubbTokens.chalk0` | High-Contrast `bg`/`bgRaised` |
| `--kc-chalk-50` | `#fbfaf6` | `KubbTokens.chalk50` | Light-mode `bg` (warm paper), `onPrimary`, `onDanger`, dark `fg` |
| `--kc-chalk-100` | `#f4f1e8` | `KubbTokens.chalk100` | Light-mode `bgSunken` |
| `--kc-chalk-200` | `#e8e2d2` | `KubbTokens.chalk200` | Reserve / dividers |

### Farben — Semantic (Action / Outcome)

| CSS-Var | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--kc-hit` | `#2d6324` | `KubbTokens.hit` (= meadow600) | Treffer |
| `--kc-miss` | `#b73a2a` | `KubbTokens.miss` | Fehlschuss / `danger` |
| `--kc-heli` | `#c08a33` | `KubbTokens.heli` (= wood400) | Helikopter — caution |
| `--kc-penalty` | `#8a1f3d` | `KubbTokens.penalty` | Strafkubb |
| `--kc-king` | `#c89b3d` | `KubbTokens.king` | Koenig (gilded) |

Hinweis: SSoT definiert nur diese fuenf "Outcome-Tokens". Es gibt **keinen** dedizierten `--kc-success`, `--kc-warning`, `--kc-info`, `--kc-caution` Token — `caution` ist die semantische Rolle, die `--kc-heli` traegt (siehe `colors-semantic.html` Zelle "Heli · caution"). Der Brief erwaehnt `caution` als moeglichen neuen Token; der ist **nicht** als eigener Hex-Eintrag vorhanden, sondern Rolle des Wood-400.

### Semantic Surface Tokens (mode-aware)

| CSS-Var | Flutter | Light | Dark | High-Contrast |
|---|---|---|---|---|
| `--kc-bg` | `tokens.bg` | `chalk50` | `stone900` | `chalk0` |
| `--kc-bg-raised` | `tokens.bgRaised` | `chalk0` | `stone800` | `chalk0` |
| `--kc-bg-sunken` | `tokens.bgSunken` | `chalk100` | `#050402` | `#f0efe8` |
| `--kc-bg-inverse` | (fehlt) | `stone900` | `chalk50` | — |
| `--kc-fg` | `tokens.fg` | `stone900` | `chalk50` | `#000000` |
| `--kc-fg-muted` | `tokens.fgMuted` | `stone500` | `stone300` | `#1a1a1a` |
| `--kc-fg-subtle` | `tokens.fgSubtle` | `stone400` | `stone400` | `stone400` |
| `--kc-fg-inverse` | (fehlt) | `chalk50` | `stone900` | — |
| `--kc-line` | `tokens.line` | `stone200` | `stone700` | `#000000` |
| `--kc-line-strong` | `tokens.lineStrong` | `stone900` | `chalk50` | `#000000` |
| `--kc-primary` | `tokens.primary` | `meadow500` | `meadow400` | `#0f4a08` |
| `--kc-primary-hover` | `tokens.primaryHover` | `meadow600` | `meadow300` | `meadow700` |
| `--kc-primary-press` | `tokens.primaryPress` | `meadow700` | `meadow700` | `meadow800` |
| `--kc-on-primary` | `tokens.onPrimary` | `chalk50` | `stone900` | `chalk0` |
| `--kc-accent` | `tokens.accent` | `wood400` | `wood400` | `#6e3c00` |
| `--kc-accent-hover` | `tokens.accentHover` | `wood500` | `wood500` | `wood600` |
| `--kc-on-accent` | `tokens.onAccent` | `stone900` | `stone900` | `chalk0` |
| `--kc-danger` | `tokens.danger` | `miss` | `miss` | `miss` |
| `--kc-on-danger` | `tokens.onDanger` | `chalk50` | `chalk50` | `chalk0` |

### Typografie

| Token | Wert | Flutter-Pendant | Status |
|---|---|---|---|
| `--kc-font-display` | `Fraunces, Bricolage, ui-serif, ...` | **fehlt** (kein Fraunces gebundelt) | **Fehlt** |
| `--kc-font-ui` | `Bricolage Grotesque, system-ui, ...` | `KubbTheme.fontFamily = 'BricolageGrotesque'` (bundled) | Vorhanden |
| `--kc-font-body` | dito | dito | Vorhanden |
| `--kc-font-mono` | `JetBrains Mono, SF Mono, Menlo, ...` | **fehlt** (kein Mono-Asset, kein google_fonts) | **Fehlt** |

**Type-Scale** (aus `colors_and_type.css` Z. 113-124 + Previews `type-display.html`, `type-counter.html`, `type-body.html`, `type-mono.html`):

| Token | Wert | Verwendung im Preview | Flutter |
|---|---|---|---|
| `--kc-text-2xs` | `11px` | Overline (`type-body.html`) | Fehlt |
| `--kc-text-xs` | `13px` | Caption, Mono-Tabellen-Body | Fehlt |
| `--kc-text-sm` | `15px` | Body-Small | Fehlt |
| `--kc-text-base` | `17px` | Body (`type-body.html`) | Fehlt |
| `--kc-text-lg` | `20px` | — | Fehlt |
| `--kc-text-xl` | `24px` | h3 (`type-body.html`) | Fehlt |
| `--kc-text-2xl` | `32px` | h2 inline-Beispiel | Fehlt |
| `--kc-text-3xl` | `44px` | h1 inline-Beispiel | Fehlt |
| `--kc-text-4xl` | `60px` | display inline-Beispiel | Fehlt |
| `--kc-text-5xl` | `84px` | **primary counter** (`type-counter.html` "Treffer: 11") | Fehlt |
| `--kc-text-6xl` | `120px` | hero counter | Fehlt |
| `--kc-text-7xl` | `168px` | desktop hero counter (neu) | Fehlt |

**Weights**:

| Token | Wert | Flutter |
|---|---|---|
| `--kc-w-regular` | `400` | Implizit |
| `--kc-w-medium` | `500` | Fehlt als Token |
| `--kc-w-semibold` | `600` | Fehlt |
| `--kc-w-bold` | `700` | Fehlt |
| `--kc-w-black` | `800` | Fehlt |

**Line-Heights**:

| Token | Wert | Flutter |
|---|---|---|
| `--kc-lh-tight` | `1.05` | Fehlt |
| `--kc-lh-snug` | `1.2` | Fehlt |
| `--kc-lh-normal` | `1.45` | Fehlt |
| `--kc-lh-loose` | `1.6` | Fehlt |

**Letter-Spacing**:

| Token | Wert | Flutter |
|---|---|---|
| `--kc-tracking-tight` | `-0.02em` | Fehlt |
| `--kc-tracking-normal` | `0` | Fehlt |
| `--kc-tracking-wide` | `0.04em` | Fehlt |
| `--kc-tracking-uppercase` | `0.08em` | Fehlt |

**Tabular-Nums-Konfiguration**: `colors_and_type.css` Z. 319-340 definiert `.kc-counter`, `.kc-counter-hero` und `.kc-mono` mit `font-variant-numeric: tabular-nums` und `font-feature-settings: 'tnum' 1, 'ss01' 1`. Flutter braucht das Aequivalent `TextStyle(fontFeatures: [FontFeature.tabularFigures()])` — heute nicht eingebaut. `type-mono.html` zeigt die Wirkung: rechtsbuendige `ms`-Spalte rastert sauber, ohne Spalten-Wackeln.

**Semantic Type-Klassen** (CSS-only):

| Klasse | Font | Size | Weight | LH | Tracking |
|---|---|---|---|---|---|
| `.kc-display` | display | `5xl` (84) | bold | tight | tight |
| `.kc-h1` | display | `4xl` (60) | bold | tight | tight |
| `.kc-h2` | display | `3xl` (44) | semibold | snug | tight |
| `.kc-h3` | ui | `xl` (24) | semibold | snug | — |
| `.kc-body` | body | `base` (17) | — | normal | — |
| `.kc-body-sm` | body | `sm` (15) | — | normal | — |
| `.kc-caption` | body | `xs` (13) | — | normal | — (fg-muted) |
| `.kc-overline` | ui | `xs` (13) — Preview nutzt 11px | semibold | — | uppercase (0.08em) |
| `.kc-counter` | ui | `5xl` (84) | bold | 0.9 | -0.04em |
| `.kc-counter-hero` | ui | `6xl` (120) | black | 0.85 | -0.05em |
| `.kc-mono` | mono | — | — | — | — |
| `.kc-wordmark` | display | — | bold | — | -0.03em (opsz 144) |

### Spacing-Scale (4px-Basis)

| Token | Wert | Flutter | Status |
|---|---|---|---|
| `--kc-space-0` | `0` | (fehlt) | Fehlt |
| `--kc-space-1` | `4px` | `space1` | Vorhanden |
| `--kc-space-2` | `8px` | `space2` | Vorhanden |
| `--kc-space-3` | `12px` | `space3` | Vorhanden |
| `--kc-space-4` | `16px` | `space4` | Vorhanden |
| `--kc-space-5` | `20px` | `space5` | Vorhanden |
| `--kc-space-6` | `24px` | `space6` | Vorhanden |
| `--kc-space-8` | `32px` | `space8` | Vorhanden |
| `--kc-space-10` | `40px` | `space10` | Vorhanden |
| `--kc-space-12` | `48px` | `space12` | Vorhanden |
| `--kc-space-14` | `56px` | (fehlt) | **Fehlt** |
| `--kc-space-16` | `64px` | (fehlt) | **Fehlt** |
| `--kc-space-20` | `80px` | (fehlt) | **Fehlt** |
| `--kc-space-24` | `96px` | (fehlt) | **Fehlt** |
| `--kc-space-32` | `128px` | (fehlt, neu in SSoT) | **Fehlt** |

`spacing-scale.html` markiert `space-12` (48 dp = Touch-Floor) und `space-16` (64 dp = comfortable primary action) mit einem Stern — beide sind hartes UX-Goal aus dem Tournament-Spec.

**Containers** (`colors_and_type.css` Z. 168-171):

| Token | Wert | Flutter |
|---|---|---|
| `--kc-container-narrow` | `720px` | Fehlt |
| `--kc-container` | `1080px` | Fehlt |
| `--kc-container-wide` | `1280px` | Fehlt |

### Border-Radius

| Token | Wert | Flutter | Status |
|---|---|---|---|
| `--kc-radius-xs` | `2px` | (fehlt) | **Fehlt** |
| `--kc-radius-sm` | `4px` | `radiusSm` | Vorhanden |
| `--kc-radius-md` | `8px` | `radiusMd` | Vorhanden |
| `--kc-radius-lg` | `12px` | `radiusLg` | Vorhanden |
| `--kc-radius-xl` | `16px` | `radiusXl` | Vorhanden |
| `--kc-radius-2xl` | `20px` | (fehlt) | **Fehlt** |
| `--kc-radius-3xl` | `28px` | (fehlt, neu in SSoT) | **Fehlt** |
| `--kc-radius-pill` | `999px` | `radiusPill` | Vorhanden |

### Elevation / Shadows

| Token | Wert | Flutter | Verwendung (aus `elevation.html`) |
|---|---|---|---|
| `--kc-shadow-1` | `0 1px 0 rgb(12 11 7 / .06), 0 1px 2px rgb(12 11 7 / .06)` | (fehlt) | hairline |
| `--kc-shadow-2` | `0 1px 2px / .06, 0 4px 12px / .08` | (fehlt) | card |
| `--kc-shadow-3` | `0 2px 4px / .08, 0 12px 24px / .12` | (fehlt) | sheet |
| `--kc-shadow-4` | `0 4px 8px / .10, 0 24px 48px / .18` | (fehlt, neu in SSoT) | modal |
| `--kc-shadow-pressed` | `inset 0 2px 0 rgb(12 11 7 / .18)` | (fehlt) | pressed state |
| `--kc-focus-ring` | `0 0 0 3px chalk-50, 0 0 0 6px meadow-500` | (fehlt) | accessibility |

### Motion / Durations

`motion.html` ist neu und macht die Tokens explizit demonstrierbar (animierter Progress-Bar pro Dauer).

| Token | Wert | Flutter | Verwendung |
|---|---|---|---|
| `--kc-ease-standard` | `cubic-bezier(0.2, 0, 0, 1)` | (fehlt) | utilitarian transitions (tap, micro-feedback) |
| `--kc-ease-emphasized` | `cubic-bezier(0.3, 0, 0, 1)` | (fehlt) | route transitions, sheet opens |
| `--kc-dur-fast` | `120ms` | (fehlt) | taps, micro-feedback (button-tap) |
| `--kc-dur-base` | `200ms` | (fehlt) | standard transitions (banner-slide) |
| `--kc-dur-slow` | `320ms` | (fehlt) | sheets, modals, route changes (sheet open/close) |

Aus `motion.html` Z. 18: "No bounces" — Curve-Wahl ist bewusst nicht-elastisch.

### Touch-Targets

| Token | Wert | Flutter | Status |
|---|---|---|---|
| `--kc-touch-min` | `48px` | `KubbTokens.touchMin` (48) | Vorhanden |
| `--kc-touch-comfortable` | `64px` | `KubbTokens.touchComfortable` (64) | Vorhanden |

### Hi-Contrast-Modus (`.kc-hc`)

| Override | Wert | Flutter (`KubbTokens.highContrast`) | Match |
|---|---|---|---|
| `--kc-bg` | `#ffffff` | `chalk0` | Ja |
| `--kc-bg-raised` | `#ffffff` | `chalk0` | Ja |
| `--kc-bg-sunken` | `#f0efe8` | `Color(0xFFF0EFE8)` | Ja |
| `--kc-fg` | `#000000` | `Color(0xFF000000)` | Ja |
| `--kc-fg-muted` | `#1a1a1a` | `Color(0xFF1A1A1A)` | Ja |
| `--kc-line` | `#000000` | `Color(0xFF000000)` | Ja |
| `--kc-primary` | `#0f4a08` | `Color(0xFF0F4A08)` | Ja |
| `--kc-on-primary` | `#ffffff` | `chalk0` | Ja |
| `--kc-accent` | `#6e3c00` | `Color(0xFF6E3C00)` | Ja |
| `--kc-shadow-1..3` | `0 0 0 Npx #000` (flat) | (kein Shadow-Token) | Override laeuft leer |

Hi-Contrast existiert als `KubbTheme.highContrast()` Factory. Auto-Switch via `MediaQuery.highContrast` ist noch nicht verdrahtet.

### Dark-Modus (`.kc-dark`)

Neu in SSoT (Z. 229-246). Werte stimmen mit `KubbTokens.dark` ueberein. `primaryPress` wird in CSS nicht ueberschrieben (faellt auf Light-Wert `meadow700` zurueck); Flutter setzt explizit `meadow700` — match.

### Brand-Assets-Tokens

Nicht in `colors_and_type.css` definiert, kommen aus den HTML-Previews `brand-logo.html`, `brand-logo-marks.html`, `brand-splash.html`, `brand-wordmark.html`, `brand-backgrounds.html`.

| Asset-Klasse | Groessen / Varianten | Flutter-Pendant |
|---|---|---|
| Logo-Mark | 16, 24, 32, 48, 64, 96 px Roundel | Fehlt (kein Konstanten-Block) |
| Mark-Roundel (Crest auf Meadow-Disk) | Standard-App-Icon | Fehlt |
| Mark-Chalk (Mark auf Chalk-50) | Light-Splash, Cards | Fehlt |
| Mark-Ink (Mark auf Stone-900) | Dark-Splash, Inverse | Fehlt |
| Splash-Variants | A: Meadow-bg, B: Chalk-bg | Fehlt |
| Wordmark | Fraunces opsz 144, SOFT 30, tracking -0.03em | `.kc-wordmark` CSS-Klasse — keine Flutter-Konstante |

`docs/design/AUDIT.md` 2.1 listet die Pixel-Groessen pro Platform (iOS 1024..20, Android 192..48 + Adaptive, Web PWA 512/192/maskable, Favicon 16/32/180). Das ist noch ein Export-Schritt, keine Flutter-Tokens.

## Flutter-Mapping-Audit

### Erfuellt (CSS und Flutter konsistent)

- Komplette **Meadow** 50..900 — Hex-Werte Bit-genau.
- Komplette **Wood** 50..800 — Hex-Werte Bit-genau.
- Komplette **Chalk** 0/50/100/200 — Hex-Werte Bit-genau.
- Komplette **Stone** 50..900 — Hex-Werte Bit-genau.
- Alle 5 **Outcome-Tokens** (`hit`, `miss`, `heli`, `penalty`, `king`).
- **Surface-Tokens** in Light + Dark + Hi-Contrast korrekt verdrahtet (modulo `bgInverse`/`fgInverse`, siehe unten).
- **Spacing 1..12** (4..48 px).
- **Radius sm/md/lg/xl/pill**.
- **Touch-Targets** 48/64 dp.
- **Bricolage Grotesque** bundled.
- **Hi-Contrast-Mode** als Theme-Factory.

### Fehlt (in CSS, nicht in Flutter)

| Bereich | Token / Asset | Auswirkung |
|---|---|---|
| Surface | `bgInverse`, `fgInverse` | Snackbar/Tooltip auf inverter Surface ohne Token |
| Typo | `--kc-font-display` (Fraunces) | Wordmark, Hero-Headlines koennen Brand-Font nicht ziehen |
| Typo | `--kc-font-mono` (JetBrains Mono) | Stat-Tabellen, per-stick-Logs (siehe `type-mono.html`) ohne Mono-Font |
| Typo | Komplette Text-Scale `2xs..7xl` (11..168 px) | Counter-Screens, Display-Hierarchie nicht Token-driven |
| Typo | Weights `regular..black` als Token | Inkonsistente Font-Weight-Wahl |
| Typo | Line-Heights `tight..loose` | Vertical Rhythm nicht Token-driven |
| Typo | Letter-Spacings `tight..uppercase` | Tracking ad-hoc |
| Typo | `tabular-nums` Counter-Style (`FontFeature.tabularFigures()`) | Counter wackelt beim Hochzaehlen |
| Typo | `KubbTextStyles` Holder fuer `.kc-display`, `.kc-h1..3`, `.kc-body`, `.kc-counter`, `.kc-mono`, `.kc-wordmark` | UI muss TextStyle pro Stelle neu zusammenbauen |
| Spacing | `space14/16/20/24/32` (56/64/80/96/128 px) | Hero-Layouts, Container-Padding auf Tablet greifen Magic Numbers |
| Spacing | Container-Maxes `narrow/default/wide` (720/1080/1280) | Tablet/Desktop-Layout (`AUDIT.md` 4.1) ohne Token-Grenze |
| Radius | `radiusXs` (2 px), `radius2xl` (20 px), `radius3xl` (28 px) | Brand-Cards, Splash-Mark, Chip-Detail ausserhalb Token |
| Shadow | `shadow1/2/3/4` als `List<BoxShadow>` | Card/Sheet/Modal-Elevation ohne System |
| Shadow | `shadowPressed` (inset) | Pressed-State per Hand (in Flutter via `InkWell.splashColor` / `Container`-Border) |
| Focus | `focusRing` (3px chalk + 3px meadow) | Custom Focus-Indicator pro Widget |
| Motion | `easeStandard`, `easeEmphasized` (`Curve`) | Animations-Kurven inkonsistent |
| Motion | `durFast/Base/Slow` (`Duration`) | Animations-Dauer inkonsistent |
| Brand | Logo-Mark-Sizes (16/24/32/48/64/96) als Konstanten | Asset-Wahl per Hand |
| Brand | Wordmark als `Text`-Widget-Konstante | Wordmark wird pro Stelle neu gestyled |

### Abweichend (Wert-Mismatch)

Keine direkten Hex- oder Namens-Abweichungen. Alle 38 Farb-Tokens in `kubb_tokens.dart` matchen Bit-genau die `--kc-*`-SSoT.

Bewusste Erweiterung: `KubbTokens.highContrast.primaryPress = meadow800`. CSS `.kc-hc` ueberschreibt `--kc-primary-press` nicht, faellt also auf Light-Wert `meadow700`. Flutter ist hier strenger (tiefere Press-Farbe) — keine Regel-Verletzung, koennte aber bewusst dokumentiert werden.

### Rebrand-Drift (Flutter haelt Brosi-Era, Design hat Kubb Club)

| Bereich | Flutter-Stand | SSoT-Stand | Drift |
|---|---|---|---|
| Display-Font | Bricolage Grotesque (single font) | Fraunces fuer `--kc-font-display`, Bricolage fuer `--kc-font-ui` | **Drift**: Flutter kennt nur Bricolage. Mobile-App ist per `AUDIT.md` 1. bewusst Bricolage-only — fuer Wordmark/Hero-Splash braeuchte es Fraunces. |
| Token-Prefix | (keiner — Dart-Konstanten) | `--kc-*` mit `--bk-*`-Aliasen | Kein Code-Drift, aber Doku-Drift: alle Verweise im Code/Tests/Comments lesen noch "bk_*"-Welt, sofern Comments aus Brosi-Era ueberlebt haben |
| Mono-Font | Keiner | JetBrains Mono 400/500/700 | **Drift**: Stat-Tabellen und Per-Stick-Logs in `type-mono.html` brauchen Mono; Flutter rendert mit Bricolage |
| Wordmark | Keine dedizierte Komponente | `.kc-wordmark` Klasse + Fraunces-Setup | **Drift**: App-Title in Header/Splash zieht keinen Brand-Style |
| Brand-Mark | `assets/`-SVGs vorhanden, kein Pixel-Export-Pipeline | `brand-logo.html` / `brand-splash.html` fordern PNG-Pyramide | **Drift**: App-Icon fuer iOS/Android/Web blockiert (`AUDIT.md` 2.1) |
| Onboarding-Tour | Route vorhanden, keine Visuals | `AUDIT.md` 2.4 fordert 3-4 Slides | **Drift**: Route ohne Asset |
| Splash | Flutter-Default | `brand-splash.html` Variante A/B | **Drift** (`AUDIT.md` 2.2) |
| In-App-Strings | Suchen nach `Brosi`/`Brosi's Kubb` noetig (`AUDIT.md` 2.3) | "Kubb Club" | **Drift**: ARB, AndroidManifest, Info.plist, manifest.json |

## Quality-Gate-Checkliste

Status der Token-Implementierung im Flutter-Tree.

- [x] Meadow 50..900 komplett.
- [x] Stone 50..900 komplett.
- [x] Wood 50..800 komplett.
- [x] Chalk 0/50/100/200 komplett.
- [x] Outcome-Tokens (`hit`, `miss`, `heli`, `penalty`, `king`).
- [x] Surface-Tokens Light/Dark/Hi-Contrast verdrahtet.
- [ ] Inverse-Surface-Tokens (`bgInverse`, `fgInverse`).
- [x] Bricolage Grotesque via bundled Font (`KubbTheme.fontFamily`).
- [ ] Fraunces als Display-Font (fuer Wordmark + Hero-Headlines).
- [ ] JetBrains Mono via google_fonts oder bundled Asset.
- [ ] Tabular-Nums (`FontFeature.tabularFigures()`) im Counter-TextStyle.
- [ ] Text-Scale `text2xs..text7xl` (11..168 px) als Token.
- [ ] Font-Weights `wRegular..wBlack` (400..800) als Token.
- [ ] Line-Heights `lhTight..lhLoose` (1.05..1.6) als Token.
- [ ] Letter-Spacings `trackingTight..trackingUppercase` (-0.02..0.08em) als Token.
- [ ] `KubbTextStyles` Holder fuer `.kc-display`/`h1-3`/`body`/`counter`/`mono`/`wordmark`.
- [x] Spacing 1..12 (4..48 px).
- [ ] Spacing 14/16/20/24/32 (56..128 px).
- [ ] Container-Maxes (720/1080/1280) als Konstanten.
- [x] Border-Radius sm/md/lg/xl/pill.
- [ ] Border-Radius xs (2 px), 2xl (20 px), 3xl (28 px).
- [ ] Shadows `shadow1/2/3/4` als `List<BoxShadow>`.
- [ ] Pressed-Inset-Aequivalent (Inset gibt es in Flutter nicht — via `InkWell` oder Container-Border).
- [ ] Focus-Ring-Helper (`BoxDecoration` Chalk-inner + Meadow-outer).
- [ ] Motion-Tokens: `durFast/Base/Slow` (`Duration`) und `easeStandard/Emphasized` (`Curve`) in `KubbMotion`.
- [x] Touch-Targets 48 dp und 64 dp.
- [x] Hi-Contrast als Theme-Factory.
- [ ] Hi-Contrast-Auto-Switch (`MediaQuery.highContrast` oder Settings-Toggle).
- [ ] Brand-Logo-Mark-Sizes (16/24/32/48/64/96) als Konstanten.
- [ ] Wordmark als Widget-Konstante (Fraunces 144 / SOFT 30 / -0.03em).
- [ ] Splash-Backgrounds nach `brand-splash.html` (Meadow/Chalk Varianten).
- [ ] Token-Sync-Test (Property-Test: jeder `--kc-*` hat Flutter-Pendant).

## Bekannte Abweichungen / Folge-Actions

Priorisierung folgt `AUDIT.md` Sektion 6 (Sprint-Reihenfolge: 1-5 Rebrand-MVP, 6-10 Polish).

### Sprint Rebrand-MVP (blockiert Release)

1. **Brand-Strings ersetzen** (`AUDIT.md` 2.3). `Brosi`/`Brosi's Kubb` raus aus `app_de.arb`, `AndroidManifest.xml`, `Info.plist`, `web/manifest.json`. Kein Token-Thema, aber Voraussetzung fuer alles, was den Wordmark zieht.
2. **App-Icon-Pipeline** (`AUDIT.md` 2.1). PNG-Export aus den Brand-Mark-SVGs. Token-Wirkung: `KubbBrand.markRoundel/Chalk/Ink` als Asset-Pfad-Konstanten ergaenzen, sobald die PNGs existieren.
3. **Splash-Screen** (`AUDIT.md` 2.2). Token-Wirkung: `KubbBrand.splashBackground` (Meadow oder Chalk) + Mark-Asset zentriert.
4. **Fraunces-Font integrieren**. Entweder bundled (`assets/fonts/Fraunces-*.ttf`) oder via `google_fonts`. Mapping: `KubbTheme.displayFontFamily = 'Fraunces'`. Wordmark-Komponente ziehbar machen.
5. **JetBrains Mono integrieren**. Bundled oder `google_fonts`. Mapping: `KubbTheme.monoFontFamily = 'JetBrainsMono'`. Stat-Tabellen + per-stick-Logs.

### Sprint Token-Foundation (notwendig fuer Polish)

6. **`KubbTextStyles` Holder anlegen**. Konstanten fuer `display`, `h1`, `h2`, `h3`, `body`, `bodySm`, `caption`, `overline`, `counter` (mit `FontFeature.tabularFigures()`), `counterHero`, `mono`, `wordmark`. Liest die kommenden Type-Tokens (siehe Punkt 7).
7. **Type-Tokens komplettieren**. Text-Scale 2xs..7xl, Weights, Line-Heights, Letter-Spacings als statische Doubles bzw. `int`-Konstanten in `KubbTokens` (oder einer Schwester-Klasse `KubbType`).
8. **Spacing-Scale erweitern** auf `space14/16/20/24/32`. Container-Maxes als `KubbLayout` mit `narrow/default/wide`.
9. **Radius-Skala komplettieren** mit `radiusXs/2xl/3xl`.
10. **Shadow-Tokens** als `List<BoxShadow>`-Konstanten `shadow1/2/3/4`. `shadowPressed` per Hand-Mapping (Inset existiert in Flutter nicht — Workaround dokumentieren).
11. **Motion-Tokens** in `KubbMotion`-Klasse: `durFast/Base/Slow` als `Duration`, `easeStandard/Emphasized` als `Curve` (`Cubic(0.2, 0, 0, 1)` / `Cubic(0.3, 0, 0, 1)`).
12. **Focus-Ring-Helper**: `BoxDecoration` mit Chalk-50-Outline und Meadow-500-Glow, callbar als `KubbFocus.ringDecoration(KubbTokens)`.
13. **Inverse-Surface-Tokens**: `bgInverse`, `fgInverse` in `KubbTokens`.
14. **Hi-Contrast-Auto-Switch**: in `kubb_app.dart` auf `MediaQuery.highContrast` reagieren plus Settings-Toggle.

### Sprint Token-Hygiene

15. **Token-Sync-Test** als Property-Test (`packages/kubb_domain` oder eigenes Test-Modul). Pruefliste: jeder `--kc-*`-Eintrag aus `colors_and_type.css` hat ein Flutter-Pendant. Verhindert Drift kuenftig.
16. **Doku-Drift abbauen**: Kommentare in `kubb_tokens.dart` und `_archive_brosi/`-Verzeichnis erwaehnen "Brosi"; das kann bleiben (historisch), aber neue Doku zieht `--kc-*`-Prefix.

### Beobachtung ohne Action

- **Wood-Skala** ohne 900-Stufe. Bewusste Designentscheidung, keine Action.
- **`--kc-king`** ist semantisch ein Outcome-Token (Koenigswurf), wird im Rebrand aber auch fuer die Crown des Logo-Marks gezogen. Doppelnutzung ist OK, solange beide Sites denselben Gold-Hex (#c89b3d) halten.
- **`caution`** existiert nicht als eigener Hex-Token. Brief erwaehnte ihn als moeglich neu — derzeit traegt `--kc-heli` die `caution`-Rolle (siehe `colors-semantic.html`). Falls Caution unabhaengig von Heli werden soll, ist das eine neue Token-Entscheidung mit ADR-Bedarf.
