# Fonts

The Brosi's Kubb design system uses two webfont families, both loaded from Google Fonts:

- **Bricolage Grotesque** — display + body. Picked for its strong display character at large counter sizes and its excellent tabular numerals (the counter on the training screen needs to remain rock-steady as the player taps).
- **JetBrains Mono** — used only in stat tables and monospaced contexts (per-stick log, raw session data).

Both are loaded via `@import` in `colors_and_type.css`. No local font files are checked in for v1.

## Font substitution flag

⚠️ **No brand font was provided** — the user has not yet specified a typeface. **Bricolage Grotesque** was chosen as a placeholder that fits the brand brief: open-source, distinctive but not flashy, with the technical chops needed for outdoor counter UI (tabular nums, strong weight range). If a real brand font exists, swap the two `--bk-font-*` variables in `colors_and_type.css` and drop the corresponding `.woff2` files into this folder.
