# ADR-0008: Design system adoption — Brosi's Kubb tokens

- **Status**: Accepted
- **Date**: 2026-05-02
- **Depends on**: ADR-0001 (Flutter stack), ADR-0002 (Bounded Contexts)

## Context

Up to this ADR the project had no concrete design tokens or visual language. The plan was to define them ad-hoc as features are built — which would have led to inconsistent screens and a Material-3-default look that doesn't match the outdoor, sport-pitch context.

A complete design system was produced externally (HTML/CSS/JSX prototypes plus a fully fleshed-out token file) and lives at `docs/design/`. This ADR formalizes adoption: the system becomes the visual contract for every screen, with tokens mapped one-to-one into the Flutter theme.

## Decision

Adopt the design system at `docs/design/` as the authoritative visual specification for the app.

### Source of truth

- **`docs/design/colors_and_type.css`** — the canonical token file. Every CSS variable maps to a corresponding Flutter token. When a token changes, the CSS file is updated first, then the Flutter side mirrors it.
- **`docs/design/ui_kits/app/*.jsx`** — per-screen prototypes. They are specifications, not code to copy. Flutter widgets are hand-built to match the visual output.
- **`docs/design/preview/*.html`** — component reference renders for individual primitives (buttons, chips, counter, slider, tap-pad).

### Token mapping strategy

CSS variables become Dart fields on a `KubbTokens` class exposed via `ThemeExtension<KubbTokens>`. Naming round-trips:

| CSS variable | Dart access |
|---|---|
| `--bk-meadow-500` | `tokens.meadow500` |
| `--bk-fg-muted` | `tokens.fgMuted` |
| `--bk-hit` | `tokens.hit` |
| `--bk-touch-min` | `tokens.touchMin` (returns `48`) |
| `--bk-radius-lg` | `tokens.radiusLg` (returns `12`) |

Standard Material color slots (`primary`, `secondary`, `surface`, etc.) get filled from semantic tokens (`--bk-primary` → `colorScheme.primary`). Brand-specific slots without a Material counterpart (`hit`, `miss`, `heli`, `penalty`, `king`) live only on the extension.

### Typography

- **Bricolage Grotesque** for display + body
- **JetBrains Mono** for tabular stat data
- Both via the `google_fonts` package (already in stack per ADR-0001 implicit decision; will be added to `pubspec.yaml` during implementation)
- The `bk-counter` and `bk-counter-hero` styles must use `tabular-nums` (`fontFeatures: [FontFeature.tabularFigures()]`) so digits don't shift width as the count changes — this is a hard requirement for the training screens.

### Theme modes

- **Light (default)** — chalk background, ink foreground
- **Dark** — for dusk play and indoor stat review (per `colors_and_type.css` `.bk-dark` block)
- **High-contrast** — for direct sunlight (per `.bk-hc` block). Implemented as a separate `ThemeMode`-like switch in Settings, not auto-bound to system preference initially. May follow system preference in a later iteration.

### Naming changes from the design system

- **"8m-Modus"** is now **"Sniper-Training"** in the UI. The distance is a 4–8 m slider; "8 m" is just the default. All Flutter identifiers and ARB keys use `sniper`, not `eightM`.
- The corresponding Flutter file is `sniper_screen.dart`, not `eight_m_screen.dart`. The legacy filename `EightMScreen.jsx` in `docs/design/ui_kits/app/` stays as-is (it's a snapshot of the design moment) but ignored for naming purposes.

### Heli counter — opt-in via settings

Per owner clarification: the third counter (Heli) is shown by default but can be hidden via a Settings toggle (`Tracking.showHeli`). When hidden:

- The counter strip on the Sniper screen shows only Hit + Miss
- The tap-pad grid drops the two Heli buttons (becomes 4 pads instead of 6)
- Existing sessions with Heli data are preserved; the toggle only affects display

### Icons

Stroke icons in `shared.jsx` are 24 px outlined glyphs. Two-track approach:

- **Generic icons** (Plus, Minus, Close, Settings, Back, Check, X, Eye, EyeOff, Menu, ChevronRight, Trash, Download, Lock, Mail, Filter): the `lucide_icons` package matches the visual style closely enough.
- **Brand-specific glyphs** (Heli, King, Cup, Trophy, Star, Flame, Stat, Target, Profile): hand-built as small `CustomPainter` widgets in `lib/core/ui/icons.dart`. They are simple paths and stay maintainable.

### Vibration

Tap-pad feedback uses `HapticFeedback.lightImpact()` from `package:flutter/services.dart`. Equivalent of the prototype's `navigator.vibrate(8)` on web.

## Alternatives considered

### Alt 1: Material 3 defaults, no custom design system

- **Pro**: Zero design work, smallest first-feature surface.
- **Contra**: Generic, doesn't match the outdoor/sport context. Refactor cost later when branding becomes a requirement.
- **Why rejected**: A complete design exists. Pretending it doesn't would be wasteful.

### Alt 2: Mixed approach — Material defaults + custom branding accents

- **Pro**: Less work than full token system.
- **Contra**: Inconsistency creep. The design system was built as a coherent whole; cherry-picking accents loses the coherence.
- **Why rejected**: Half-measure. Either adopt or don't.

### Alt 3: Use Material 3 dynamic color from a single seed

- **Pro**: Native Material 3 mechanism, automatic palette generation.
- **Contra**: The seed approach would generate palettes that don't match the hand-tuned Wiesen / Holz / Chalk / Stone families. The semantic tokens (Hit, Miss, Heli, Penalty, King) wouldn't be derivable from a single seed.
- **Why rejected**: We have hand-tuned palettes; using them directly is correct, dynamic generation would discard the work.

## Consequences

### Positive

- Visual consistency from the first screen onward.
- Design changes have a single point of edit (CSS file → mirror in Dart).
- The token system is rich enough to express all current screens; future screens get their tokens for free.
- Accessibility is built in: minimum touch targets, light/dark/high-contrast modes, semantic colors.

### Negative

- Two codebases to keep in sync (CSS spec + Dart implementation). Mitigation: the CSS file is small and stable; updates are rare. A future CI check could parse the CSS and assert the Dart side has matching constants — not built initially.
- Custom icons add maintenance vs. relying entirely on a standard pack. Mitigation: brand icons are few (~6) and visually simple.

### Neutral

- `pubspec.yaml` grows by `google_fonts` and `lucide_icons` (already in the stack per ADR-0001 implicit; formally added during F1 implementation).
- The `lib/core/ui/` directory becomes the home for tokens, theme builder, app bar, tap pad, icons, and any other reusable visual primitives.

## Followups

- **Implementation task (F1, M0-T0)**: build `KubbTokens` `ThemeExtension`, light + dark + high-contrast `ThemeData`, register fonts, set up the high-contrast toggle Provider.
- **Implementation task (F1)**: build reusable `KubbAppBar`, `KubbTapPad`, `KubbStat`, `KubbBottomSheet` widgets in `lib/core/ui/`.
- **Implementation task (F1)**: build the brand icon set as `CustomPainter` widgets.
- **Settings entry**: `Tracking.showHeli` boolean, persisted in drift, default `true`.
- **Future**: consider a CSS→Dart token-sync linter as a `dart_test` script that fails CI if the two sides drift.
