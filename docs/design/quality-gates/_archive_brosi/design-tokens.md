# Quality-Gate: Design-Tokens

**Quelle**: `docs/design/colors_and_type.css` (SSoT)
**Flutter-Pendant**: `lib/core/ui/theme/kubb_tokens.dart`, `lib/core/ui/theme/kubb_theme.dart`
**Stand**: 2026-05-28

## Token-Inventar

### Farben

#### Meadow (Primary-Familie)

| CSS-Variable | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--bk-meadow-50` | `#eef6ec` | `KubbTokens.meadow50` | Light surface tints |
| `--bk-meadow-100` | `#d6ead0` | `KubbTokens.meadow100` | Subtle chips / hover states |
| `--bk-meadow-200` | `#aed3a2` | `KubbTokens.meadow200` | Soft fill |
| `--bk-meadow-300` | `#7fb56f` | `KubbTokens.meadow300` | Dark-mode `primaryHover` |
| `--bk-meadow-400` | `#569748` | `KubbTokens.meadow400` | Dark-mode `primary` |
| `--bk-meadow-500` | `#3a7c2e` | `KubbTokens.meadow500` | Light-mode `primary` (Brand) |
| `--bk-meadow-600` | `#2d6324` | `KubbTokens.meadow600` | Light-mode `primaryHover` |
| `--bk-meadow-700` | `#234e1c` | `KubbTokens.meadow700` | Light-mode `primaryPress` |
| `--bk-meadow-800` | `#1a3a16` | `KubbTokens.meadow800` | High-Contrast `primaryPress` |
| `--bk-meadow-900` | `#112710` | `KubbTokens.meadow900` | Reserve / ink |

#### Wood (Secondary / Accent)

| CSS-Variable | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--bk-wood-50` | `#faf3e6` | `KubbTokens.wood50` | Warm tints |
| `--bk-wood-100` | `#f1e1bf` | `KubbTokens.wood100` | Soft fills |
| `--bk-wood-200` | `#e6c98c` | `KubbTokens.wood200` | Accent backgrounds |
| `--bk-wood-300` | `#d6ab57` | `KubbTokens.wood300` | Reserve |
| `--bk-wood-400` | `#c08a33` | `KubbTokens.wood400` | `accent` (alle Modi) / Heli-Marker |
| `--bk-wood-500` | `#a16f24` | `KubbTokens.wood500` | `accentHover` |
| `--bk-wood-600` | `#80561c` | `KubbTokens.wood600` | High-Contrast `accentHover` |
| `--bk-wood-700` | `#604015` | `KubbTokens.wood700` | Reserve |
| `--bk-wood-800` | `#422c0e` | `KubbTokens.wood800` | Reserve |

#### Chalk (Paper / White-Familie)

| CSS-Variable | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--bk-chalk-0` | `#ffffff` | `KubbTokens.chalk0` | High-Contrast `bg`, `bgRaised` |
| `--bk-chalk-50` | `#fbfaf6` | `KubbTokens.chalk50` | Light-mode `bg` (warm paper), `onPrimary`, `onDanger`, dark `fg` |
| `--bk-chalk-100` | `#f4f1e8` | `KubbTokens.chalk100` | Light-mode `bgSunken` |
| `--bk-chalk-200` | `#e8e2d2` | `KubbTokens.chalk200` | Reserve / dividers |

#### Stone (Neutral / Background-Familie)

| CSS-Variable | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--bk-stone-50` | `#f4f3f0` | `KubbTokens.stone50` | Reserve |
| `--bk-stone-100` | `#e7e5df` | `KubbTokens.stone100` | Reserve |
| `--bk-stone-200` | `#cfccc1` | `KubbTokens.stone200` | Light-mode `line` (hairline) |
| `--bk-stone-300` | `#a8a597` | `KubbTokens.stone300` | Dark-mode `fgMuted` |
| `--bk-stone-400` | `#777567` | `KubbTokens.stone400` | `fgSubtle` (alle Modi) |
| `--bk-stone-500` | `#4d4b40` | `KubbTokens.stone500` | Light-mode `fgMuted` |
| `--bk-stone-600` | `#34322a` | `KubbTokens.stone600` | Reserve |
| `--bk-stone-700` | `#232118` | `KubbTokens.stone700` | Dark-mode `line` |
| `--bk-stone-800` | `#161510` | `KubbTokens.stone800` | Dark-mode `bgRaised` |
| `--bk-stone-900` | `#0c0b07` | `KubbTokens.stone900` | Light-mode `fg`/`lineStrong`, Dark `bg`, `onAccent` |

#### Semantic

| CSS-Variable | Hex | Flutter-Token | Verwendung |
|---|---|---|---|
| `--bk-hit` | `#2d6324` | `KubbTokens.hit` (= `meadow600`) | Treffer |
| `--bk-miss` | `#b73a2a` | `KubbTokens.miss` | Fehlschuss / `danger` |
| `--bk-heli` | `#c08a33` | `KubbTokens.heli` (= `wood400`) | Helikopter (caution) |
| `--bk-penalty` | `#8a1f3d` | `KubbTokens.penalty` | Strafkubb |
| `--bk-king` | `#c89b3d` | `KubbTokens.king` | König (gilded) |

#### Semantic Surface Tokens (mode-aware, via `KubbTokens` ThemeExtension)

| CSS-Variable | Flutter-Token | Light | Dark | High-Contrast |
|---|---|---|---|---|
| `--bk-bg` | `tokens.bg` | `chalk50` | `stone900` | `chalk0` |
| `--bk-bg-raised` | `tokens.bgRaised` | `chalk0` | `stone800` | `chalk0` |
| `--bk-bg-sunken` | `tokens.bgSunken` | `chalk100` | `#050402` | `#f0efe8` |
| `--bk-bg-inverse` | (fehlt) | — | — | — |
| `--bk-fg` | `tokens.fg` | `stone900` | `chalk50` | `#000000` |
| `--bk-fg-muted` | `tokens.fgMuted` | `stone500` | `stone300` | `#1a1a1a` |
| `--bk-fg-subtle` | `tokens.fgSubtle` | `stone400` | `stone400` | `stone400` |
| `--bk-fg-inverse` | (fehlt) | — | — | — |
| `--bk-line` | `tokens.line` | `stone200` | `stone700` | `#000000` |
| `--bk-line-strong` | `tokens.lineStrong` | `stone900` | `chalk50` | `#000000` |
| `--bk-primary` | `tokens.primary` | `meadow500` | `meadow400` | `#0f4a08` |
| `--bk-primary-hover` | `tokens.primaryHover` | `meadow600` | `meadow300` | `meadow700` |
| `--bk-primary-press` | `tokens.primaryPress` | `meadow700` | `meadow700` | `meadow800` |
| `--bk-on-primary` | `tokens.onPrimary` | `chalk50` | `stone900` | `chalk0` |
| `--bk-accent` | `tokens.accent` | `wood400` | `wood400` | `#6e3c00` |
| `--bk-accent-hover` | `tokens.accentHover` | `wood500` | `wood500` | `wood600` |
| `--bk-on-accent` | `tokens.onAccent` | `stone900` | `stone900` | `chalk0` |
| `--bk-danger` | `tokens.danger` | `miss` | `miss` | `miss` |
| `--bk-on-danger` | `tokens.onDanger` | `chalk50` | `chalk50` | `chalk0` |

### Typografie

| CSS-Variable | Wert (CSS) | Flutter-Pendant | Status |
|---|---|---|---|
| `--bk-font-display` | `Bricolage Grotesque` | `KubbTheme.fontFamily = 'BricolageGrotesque'` (bundled, `assets/fonts/`) | Vorhanden |
| `--bk-font-body` | `Bricolage Grotesque` | Selber wie Display | Vorhanden |
| `--bk-font-mono` | `JetBrains Mono` | (fehlt) | **Fehlt** |
| `--bk-text-2xs` | `11px` | (kein Token) | Fehlt |
| `--bk-text-xs` | `13px` | (kein Token) | Fehlt |
| `--bk-text-sm` | `15px` | (kein Token) | Fehlt |
| `--bk-text-base` | `17px` | (kein Token) | Fehlt |
| `--bk-text-lg` | `20px` | (kein Token) | Fehlt |
| `--bk-text-xl` | `24px` | (kein Token) | Fehlt |
| `--bk-text-2xl` | `32px` | (kein Token) | Fehlt |
| `--bk-text-3xl` | `44px` | (kein Token) | Fehlt |
| `--bk-text-4xl` | `60px` | (kein Token) | Fehlt |
| `--bk-text-5xl` | `84px` (Counter) | (kein Token) | Fehlt |
| `--bk-text-6xl` | `120px` (Hero) | (kein Token) | Fehlt |
| `--bk-w-regular..black` | 400/500/600/700/800 | implizit über Font-Weights | Teilweise |
| `--bk-lh-tight..loose` | 1.05 / 1.2 / 1.45 / 1.6 | (kein Token) | Fehlt |
| `--bk-tracking-*` | tight / normal / wide / uppercase | (kein Token) | Fehlt |

Anmerkung: `kubb_theme.dart` setzt `textTheme` via `Typography.{black|white}MountainView.apply(fontFamily: 'BricolageGrotesque', ...)` — Bricolage wird global angewendet, aber das Scale-Mapping (CSS `--bk-text-*` → Material `TextStyle`) ist nicht explizit verdrahtet. Counter-spezifische Styles (`bk-counter`, `bk-counter-hero`) mit `tabular-nums` existieren nicht als Flutter-Pendant.

### Spacing (4px-Basis)

| CSS-Variable | Wert | Flutter-Token | Status |
|---|---|---|---|
| `--bk-space-0` | `0` | (kein Token) | Fehlt |
| `--bk-space-1` | `4px` | `KubbTokens.space1` | Vorhanden |
| `--bk-space-2` | `8px` | `KubbTokens.space2` | Vorhanden |
| `--bk-space-3` | `12px` | `KubbTokens.space3` | Vorhanden |
| `--bk-space-4` | `16px` | `KubbTokens.space4` | Vorhanden |
| `--bk-space-5` | `20px` | `KubbTokens.space5` | Vorhanden |
| `--bk-space-6` | `24px` | `KubbTokens.space6` | Vorhanden |
| `--bk-space-8` | `32px` | `KubbTokens.space8` | Vorhanden |
| `--bk-space-10` | `40px` | `KubbTokens.space10` | Vorhanden |
| `--bk-space-12` | `48px` | `KubbTokens.space12` | Vorhanden |
| `--bk-space-14` | `56px` | (fehlt) | **Fehlt** |
| `--bk-space-16` | `64px` | (fehlt) | **Fehlt** |
| `--bk-space-20` | `80px` | (fehlt) | **Fehlt** |
| `--bk-space-24` | `96px` | (fehlt) | **Fehlt** |

### Border-Radius

| CSS-Variable | Wert | Flutter-Token | Status |
|---|---|---|---|
| `--bk-radius-xs` | `2px` | (fehlt) | **Fehlt** |
| `--bk-radius-sm` | `4px` | `KubbTokens.radiusSm` | Vorhanden |
| `--bk-radius-md` | `8px` | `KubbTokens.radiusMd` | Vorhanden |
| `--bk-radius-lg` | `12px` | `KubbTokens.radiusLg` | Vorhanden |
| `--bk-radius-xl` | `16px` | `KubbTokens.radiusXl` | Vorhanden |
| `--bk-radius-2xl` | `20px` | (fehlt) | **Fehlt** |
| `--bk-radius-pill` | `999px` | `KubbTokens.radiusPill` | Vorhanden |

### Elevation / Shadows

| CSS-Variable | Wert | Flutter-Token | Status |
|---|---|---|---|
| `--bk-shadow-1` | `0 1px 0 rgb(12 11 7 / .06), 0 1px 2px rgb(12 11 7 / .06)` | (fehlt) | **Fehlt** |
| `--bk-shadow-2` | `0 1px 2px rgb(12 11 7 / .06), 0 4px 12px rgb(12 11 7 / .08)` | (fehlt) | **Fehlt** |
| `--bk-shadow-3` | `0 2px 4px rgb(12 11 7 / .08), 0 12px 24px rgb(12 11 7 / .12)` | (fehlt) | **Fehlt** |
| `--bk-shadow-pressed` | `inset 0 2px 0 rgb(12 11 7 / .18)` | (fehlt; in Flutter via Material ink, kein Inset möglich) | **Fehlt** |
| `--bk-focus-ring` | `0 0 0 3px var(--bk-chalk-50), 0 0 0 6px var(--bk-meadow-500)` | (fehlt) | **Fehlt** |

### Motion / Durations

| CSS-Variable | Wert | Flutter-Token | Status |
|---|---|---|---|
| `--bk-ease-standard` | `cubic-bezier(0.2, 0, 0, 1)` | (fehlt) | **Fehlt** |
| `--bk-ease-emphasized` | `cubic-bezier(0.3, 0, 0, 1)` | (fehlt) | **Fehlt** |
| `--bk-dur-fast` | `120ms` | (fehlt) | **Fehlt** |
| `--bk-dur-base` | `200ms` | (fehlt) | **Fehlt** |
| `--bk-dur-slow` | `320ms` | (fehlt) | **Fehlt** |

### Touch-Targets

| CSS-Variable | Wert | Flutter-Token | Status |
|---|---|---|---|
| `--bk-touch-min` | `48px` | `KubbTokens.touchMin` (48) | Vorhanden |
| `--bk-touch-comfortable` | `64px` | `KubbTokens.touchComfortable` (64) | Vorhanden |

### Hi-Contrast Mode (`.bk-hc`)

Die CSS-`.bk-hc`-Klasse überschreibt Surface- und Semantic-Tokens auf maximalen Kontrast und flacht Schatten ab.

| CSS-Override | Wert | Flutter-Pendant in `KubbTokens.highContrast` |
|---|---|---|
| `--bk-bg` | `#ffffff` | `chalk0` (= `#FFFFFF`) — match |
| `--bk-bg-raised` | `#ffffff` | `chalk0` — match |
| `--bk-bg-sunken` | `#f0efe8` | `Color(0xFFF0EFE8)` — match |
| `--bk-fg` | `#000000` | `Color(0xFF000000)` — match |
| `--bk-fg-muted` | `#1a1a1a` | `Color(0xFF1A1A1A)` — match |
| `--bk-line` | `#000000` | `Color(0xFF000000)` — match |
| `--bk-primary` | `#0f4a08` | `Color(0xFF0F4A08)` — match |
| `--bk-on-primary` | `#ffffff` | `chalk0` — match |
| `--bk-accent` | `#6e3c00` | `Color(0xFF6E3C00)` — match |
| `--bk-shadow-1..3` | `0 0 0 Npx #000` | (kein Shadow-Token in Flutter) — Override leerläuft |

Hi-Contrast existiert als `KubbTheme.highContrast()` Factory, ist aber nicht in einen Auto-Switch (`ThemeMode` / `MediaQuery.highContrast`) verdrahtet. Aktivierung wäre manuell in Settings (siehe `docs/design/README.md`).

## Flutter-Mapping-Audit

### Erfuellt

- Komplette **Meadow-Palette** 50..900 (10 Werte) — Hex-Werte identisch zur SSoT.
- Komplette **Wood-Palette** 50..800 (9 Werte) — Hex-Werte identisch.
- Komplette **Chalk-Palette** 0/50/100/200 (4 Werte) — Hex-Werte identisch.
- Komplette **Stone-Palette** 50..900 (10 Werte) — Hex-Werte identisch.
- Alle 5 **Semantic Brand Colors**: `hit`, `miss`, `heli`, `penalty`, `king` — Hex-Werte identisch.
- **Semantic Surface Tokens** (bg, bgRaised, bgSunken, fg, fgMuted, fgSubtle, line, lineStrong, primary, primaryHover, primaryPress, onPrimary, accent, accentHover, onAccent, danger, onDanger) — drei Modi (Light, Dark, Hi-Contrast) korrekt verdrahtet.
- **Spacing 1..12** (4..48 px) — 9 Stufen identisch.
- **Border-Radius sm/md/lg/xl/pill** — Werte identisch.
- **Touch-Targets** `touchMin` (48) und `touchComfortable` (64).
- **Display/Body-Font Bricolage Grotesque** als bundled Asset verdrahtet (`KubbTheme.fontFamily`).
- **Hi-Contrast-Tokens** stimmen exakt mit CSS-Overrides überein.

### Fehlt

| Bereich | Token | Auswirkung |
|---|---|---|
| Surface | `--bk-bg-inverse`, `--bk-fg-inverse` | Inverse-Komponenten (z.B. Snackbar-on-dark) ohne Token |
| Typografie | `--bk-font-mono` (JetBrains Mono) | Stat-Tabellen / per-stick-Logs ohne Mono-Font |
| Typografie | Komplette **Text-Scale** `2xs..6xl` (11..120 px) | Counter-Screens, Display-Hierarchie nicht aus Tokens steuerbar |
| Typografie | `--bk-w-*` Weights als Token | Inkonsistente Font-Weight-Wahl pro Widget |
| Typografie | `--bk-lh-*` Line-Heights | Vertical Rhythm nicht Token-getrieben |
| Typografie | `--bk-tracking-*` Letter-Spacing | Display/Overline-Tracking ad-hoc |
| Typografie | `bk-counter` / `bk-counter-hero` Style mit `tabular-nums` | Counter shifted beim Hochzählen (FontFeature fehlt) |
| Spacing | `space14`, `space16`, `space20`, `space24` (56/64/80/96 px) | Hero-Layouts auf grossen Screens müssen Magic Numbers nutzen |
| Radius | `radiusXs` (2 px), `radius2xl` (20 px) | Chip-Detail und grosse Cards außerhalb Token-System |
| Shadows | `shadow1`, `shadow2`, `shadow3`, `shadowPressed` | Cards/Sheets ohne System-Elevation |
| Focus | `focusRing` (3 px Chalk + 3 px Meadow) | Custom Focus-Indicator pro Widget |
| Motion | `easeStandard`, `easeEmphasized` | Inkonsistente Animations-Kurven |
| Motion | `durFast/Base/Slow` (120/200/320 ms) | Inkonsistente Animations-Dauer |

### Abweichend

Keine direkten Wert- oder Namens-Abweichungen gefunden. Alle 38 Farb-Tokens in `kubb_tokens.dart` matchen Bit-genau die CSS-SSoT.

Anmerkung: `KubbTokens.highContrast.primaryPress` ist auf `meadow800` gemappt — CSS definiert keinen `--bk-primary-press` Override in `.bk-hc`, der Fallback wäre also der Light-Wert `meadow700`. Die Flutter-Variante ist strenger (tiefere Press-Farbe). Keine Regel-Verletzung, aber bewusste Erweiterung wert.

### Flutter-Erweiterungen (in `kubb_tokens.dart`, nicht in `colors_and_type.css`)

- Keine. Alle Flutter-Tokens haben ein direktes CSS-Pendant.

## Quality-Gate-Checkliste (pruefbar)

- [x] Alle Meadow-Farben (50..900) in `KubbTokens`.
- [x] Alle Stone-Farben (50..900) in `KubbTokens`.
- [x] Alle Wood-Farben (50..800) in `KubbTokens`.
- [x] Alle Chalk-Farben (0/50/100/200) in `KubbTokens`.
- [x] Semantic-Tokens (hit, miss, heli, penalty, king).
- [x] Light/Dark/Hi-Contrast Mode-Varianten der Surface-Tokens.
- [x] Bricolage Grotesque für Display/Body via bundled Font verdrahtet.
- [ ] JetBrains Mono für Stat-Logs / Counter via Font-Asset oder `google_fonts`.
- [ ] Text-Scale (`text2xs..text6xl`) als Token oder als `TextTheme`-Mapping aus CSS.
- [ ] Font-Weights (`wRegular..wBlack`) als Token-Konstanten.
- [ ] Line-Heights (`lhTight..lhLoose`) als Token-Konstanten.
- [ ] Letter-Spacing (`trackingTight..trackingUppercase`) als Token-Konstanten.
- [ ] Tabular-Numerals für Stat-Counter (`FontFeature.tabularFigures()`) in einer Counter-TextStyle-Konstante.
- [x] Spacing-Scale 1..12 (4..48 px).
- [ ] Spacing-Scale 14/16/20/24 (56/64/80/96 px) für Hero-Layouts.
- [x] Border-Radius sm/md/lg/xl/pill.
- [ ] Border-Radius xs (2 px) und 2xl (20 px).
- [ ] Shadows `shadow1`, `shadow2`, `shadow3` als `List<BoxShadow>`-Konstanten.
- [ ] Pressed-Inset-Effekt (CSS `inset 0 2px 0 ...`) als Flutter-Äquivalent (z.B. via `InkWell.splashColor` oder `Container` mit Border).
- [ ] Focus-Ring-Helper (Chalk-Inner + Meadow-Outer) als `BoxDecoration`.
- [ ] Motion-Tokens: `durFast/Base/Slow` (Duration) und `easeStandard/Emphasized` (Curve).
- [x] Touch-Min 48 dp und Comfortable 64 dp als Konstanten.
- [x] Hi-Contrast-Variant als ThemeData-Factory (`KubbTheme.highContrast()`).
- [ ] Hi-Contrast in einen Auto-Switch (`MediaQuery.highContrast` oder Settings-Toggle) verdrahtet.
- [ ] Inverse-Surface-Tokens (`bgInverse`, `fgInverse`) für Snackbar/Tooltip auf dark-on-light.
- [ ] Semantic-Type-Klassen (CSS: `bk-display`, `bk-h1..h3`, `bk-body`, `bk-caption`, `bk-overline`) als `TextStyle`-Konstanten in einem `KubbTextStyles`-Holder.

## Bekannte Abweichungen / Folge-Actions

1. **Typografie-Lücke schliessen** (höchste Priorität): Komplettes Text-Scale, Line-Heights, Letter-Spacing, Weights als Token-Konstanten plus ein `KubbTextStyles`-Holder mit `display`, `h1..h3`, `body`, `bodySm`, `caption`, `overline`, `counter`, `counterHero`, `mono`. `counter`/`counterHero` müssen `FontFeature.tabularFigures()` setzen.
2. **JetBrains Mono integrieren**: entweder als bundled Asset in `assets/fonts/` analog zu Bricolage oder über `google_fonts`. Mapping: `KubbTheme.monoFontFamily`.
3. **Shadows**: `shadow1/2/3` und `shadowPressed` als `List<BoxShadow>` in `KubbTokens` (statisch, mode-agnostisch — Hi-Contrast flacht via ThemeExtension-Variante ab).
4. **Spacing-Scale erweitern**: `space14..space24` ergänzen — werden für Tournament-Detail-Header und Hero-Counter gebraucht.
5. **Border-Radius xs/2xl ergänzen**: Lücke schliessen, dann ist die Skala vollständig.
6. **Motion-Tokens**: eigene Klasse `KubbMotion` mit `durFast/Base/Slow: Duration` und `easeStandard/Emphasized: Curve`.
7. **Focus-Ring**: Helper `KubbFocus.ringDecoration(KubbTokens)` der den Doppel-Outline-Effekt rendert.
8. **Hi-Contrast-Auto-Switch**: in `kubb_app.dart` (oder wo `MaterialApp` lebt) auf `MediaQuery.highContrast` reagieren und/oder einen Settings-Toggle anbieten (ist in `docs/design/README.md` so vorgesehen).
9. **Inverse-Surfaces** in `KubbTokens` ergänzen (`bgInverse`, `fgInverse`), damit Snackbar/Tooltip im jeweiligen Mode korrekt invertiert werden.
10. **Token-Sync-Test** als Property-Test einplanen: prüft per Reflection oder Hand-Mapping, dass jeder `--bk-*`-Eintrag in `colors_and_type.css` ein Flutter-Pendant hat — würde künftige Drift verhindern.
