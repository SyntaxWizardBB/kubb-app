# Brosi's Kubb — Design System

This directory holds the design assets that drive the Flutter app's visual layer. The intent is "outdoor-first, high-contrast training UI" — the app gets used on a meadow, in sunlight, with sweaty fingers, often one-handed.

## Layout

```
design/
├── colors_and_type.css       Single source of truth for tokens (colors, type, spacing, radii, shadows, motion)
├── assets/                   Brand marks (SVG)
├── fonts/                    Font notes; webfonts loaded via @import in colors_and_type.css
├── preview/                  Standalone HTML pages showcasing each component family
├── screenshots/              Static reference renders
└── ui_kits/app/              The mobile app prototypes — what the Flutter screens have to match
```

## How to use this from the Flutter side

The HTML/JSX prototypes are **specifications, not code to copy**. Flutter widgets get hand-built to match the visual output. Translation rules:

- **Tokens** in `colors_and_type.css` map to a `KubbTokens` `ThemeExtension` plus `ThemeData`. CSS variable names round-trip: `--bk-meadow-500` → `tokens.meadow500`.
- **Fonts** load via the `google_fonts` package. Bricolage Grotesque for display + body, JetBrains Mono for stat tables and per-stick logs.
- **Touch targets** stay at the `--bk-touch-min` floor (48 dp). Primary action buttons aim for `--bk-touch-comfortable` (64 dp).
- **Icons** in `ui_kits/app/shared.jsx` are 24 px stroke icons. Closest Flutter equivalent: `lucide_icons` or hand-drawn `CustomPainter` for the brand-specific glyphs (Heli, King, Cup).
- **Vibration** on tap pads → `HapticFeedback.lightImpact()` from `package:flutter/services.dart`.

## What lives where in the app

| Prototype file | Flutter location (planned) |
|---|---|
| `ui_kits/app/HomeScreen.jsx` | `lib/features/home/presentation/home_screen.dart` |
| `ui_kits/app/EightMScreen.jsx` (Sniper) | `lib/features/training/presentation/sniper_screen.dart` |
| `ui_kits/app/FinisseurConfigScreen.jsx` | `lib/features/training/presentation/finisseur_config_screen.dart` |
| `ui_kits/app/FinisseurStickScreen.jsx` | `lib/features/training/presentation/finisseur_stick_screen.dart` |
| `ui_kits/app/SummaryScreen.jsx` | `lib/features/training/presentation/summary_screen.dart` |
| `ui_kits/app/StatsScreen.jsx` | `lib/features/training/presentation/stats_screen.dart` |
| `ui_kits/app/ProfileScreen.jsx` | `lib/features/profile/presentation/profile_screen.dart` |
| `ui_kits/app/SettingsScreen.jsx` | `lib/features/settings/presentation/settings_screen.dart` |
| `ui_kits/app/AppSettingsModal.jsx` | `lib/features/home/presentation/app_settings_modal.dart` |
| `ui_kits/app/CsvExportModal.jsx` | `lib/features/profile/presentation/csv_export_modal.dart` |
| `ui_kits/app/shared.jsx` (`AppBar`, `Icon` library) | `lib/core/ui/kubb_app_bar.dart`, `lib/core/ui/icons.dart` |

## Notes on the design

- **Sniper-Training** is the in-app name for what was previously called "8m-Modus". The distance is a 4–8 m slider; "8 m" is just one configuration.
- **Heli counter** is opt-in via Settings. Players who don't track helicopter throws can hide that column entirely.
- **High-contrast mode** (`.bk-hc` in CSS) becomes a Flutter `ThemeMode` variant or a Material 3 high-contrast surface tonal palette. Triggered manually in Settings; later optionally tied to system preference.

## Binding UI rules

These are versioned, team-wide rules (mirrored from the repo `CLAUDE.md`, which is
local-only and not committed):

- **Tournament detail always renders ALL configured master data** (no silent
  dropping of configured fields). Configured master data (B3.1–B3.4: core match
  format, KO/phase config, P6 metadata) is shown compactly via the shared widget
  `TournamentStammdatenCard`
  (`lib/features/tournament/presentation/widgets/tournament_stammdaten_card.dart`).
  Only unset / NULL / blank fields may be omitted. New master-data fields belong in
  that shared widget, not in a one-off view.

## When the design changes

Edit the prototype, regenerate or replace the affected file in `ui_kits/app/`, update token values in `colors_and_type.css`, and adjust the corresponding Flutter files. The README mapping table above stays the contract.
