// ignore_for_file: avoid_multiple_declarations_per_line — dense palette tables
//
// Source of truth: `docs/design/colors_and_type.css` (canonical `--kc-*` block).
// Konstanten und Felder hier spiegeln direkt die `--kc-*`-Tokens. Die
// `--bk-*`-Aliases im CSS-Fuss bleiben fuer HTML-Previews bestehen, sind aber
// nicht der Bezugspunkt fuer Flutter. Werte 1:1 zur CSS-Variante; bitte beim
// Update beide Seiten gemeinsam pflegen.
import 'package:flutter/material.dart';

@immutable
class KubbTokens extends ThemeExtension<KubbTokens> {
  const KubbTokens({
    required this.bg, required this.bgRaised, required this.bgSunken,
    required this.fg, required this.fgMuted, required this.fgSubtle,
    required this.line, required this.lineStrong,
    required this.primary, required this.primaryHover, required this.primaryPress,
    required this.onPrimary, required this.accent, required this.accentHover,
    required this.onAccent, required this.danger, required this.onDanger,
  });

  /// `--kc-bg` / `--kc-bg-raised` / `--kc-bg-sunken` — Surface-Schichten.
  final Color bg, bgRaised, bgSunken;
  /// `--kc-fg` / `--kc-fg-muted` / `--kc-fg-subtle` — Vordergrund-Stufen.
  final Color fg, fgMuted, fgSubtle;
  /// `--kc-line` / `--kc-line-strong` — Trenner.
  final Color line, lineStrong;
  /// `--kc-primary` / `--kc-primary-hover` / `--kc-primary-press` / `--kc-on-primary`.
  final Color primary, primaryHover, primaryPress, onPrimary;
  /// `--kc-accent` / `--kc-accent-hover` / `--kc-on-accent`.
  final Color accent, accentHover, onAccent;
  /// `--kc-danger` / `--kc-on-danger` — Fehlschuss-/Destructive-Tier.
  final Color danger, onDanger;

  // Brand palettes — identical across modes. Namen spiegeln `--kc-<scale>-<step>`.

  // Wiese / `--kc-meadow-*` — primary brand.
  static const meadow50 = Color(0xFFEEF6EC);   // --kc-meadow-50
  static const meadow100 = Color(0xFFD6EAD0);  // --kc-meadow-100
  static const meadow200 = Color(0xFFAED3A2);  // --kc-meadow-200
  static const meadow300 = Color(0xFF7FB56F);  // --kc-meadow-300
  static const meadow400 = Color(0xFF569748);  // --kc-meadow-400
  static const meadow500 = Color(0xFF3A7C2E);  // --kc-meadow-500 (primary)
  static const meadow600 = Color(0xFF2D6324);  // --kc-meadow-600
  static const meadow700 = Color(0xFF234E1C);  // --kc-meadow-700
  static const meadow800 = Color(0xFF1A3A16);  // --kc-meadow-800
  static const meadow900 = Color(0xFF112710);  // --kc-meadow-900

  // Holz / `--kc-wood-*` — accent / tournament tile.
  static const wood50 = Color(0xFFFAF3E6);     // --kc-wood-50
  static const wood100 = Color(0xFFF1E1BF);    // --kc-wood-100
  static const wood200 = Color(0xFFE6C98C);    // --kc-wood-200
  static const wood300 = Color(0xFFD6AB57);    // --kc-wood-300
  static const wood400 = Color(0xFFC08A33);    // --kc-wood-400 (accent)
  static const wood500 = Color(0xFFA16F24);    // --kc-wood-500
  static const wood600 = Color(0xFF80561C);    // --kc-wood-600
  static const wood700 = Color(0xFF604015);    // --kc-wood-700
  static const wood800 = Color(0xFF422C0E);    // --kc-wood-800

  // Kreide / `--kc-chalk-*` — pitch-line whites & off-whites.
  static const chalk0 = Color(0xFFFFFFFF);     // --kc-chalk-0
  static const chalk50 = Color(0xFFFBFAF6);    // --kc-chalk-50 (warm paper, default bg)
  static const chalk100 = Color(0xFFF4F1E8);   // --kc-chalk-100
  static const chalk200 = Color(0xFFE8E2D2);   // --kc-chalk-200

  // Stein / `--kc-stone-*` — warmed neutrals.
  static const stone50 = Color(0xFFF4F3F0);    // --kc-stone-50
  static const stone100 = Color(0xFFE7E5DF);   // --kc-stone-100
  static const stone200 = Color(0xFFCFCCC1);   // --kc-stone-200
  static const stone300 = Color(0xFFA8A597);   // --kc-stone-300
  static const stone400 = Color(0xFF777567);   // --kc-stone-400
  static const stone500 = Color(0xFF4D4B40);   // --kc-stone-500
  static const stone600 = Color(0xFF34322A);   // --kc-stone-600
  static const stone700 = Color(0xFF232118);   // --kc-stone-700
  static const stone800 = Color(0xFF161510);   // --kc-stone-800
  static const stone900 = Color(0xFF0C0B07);   // --kc-stone-900 (ink)

  // Semantic accents — `--kc-hit` / `--kc-miss` / `--kc-heli` / `--kc-penalty` / `--kc-king`.
  static const hit = Color(0xFF2D6324);        // --kc-hit (= meadow600)
  static const miss = Color(0xFFB73A2A);       // --kc-miss
  static const heli = Color(0xFFC08A33);       // --kc-heli (= wood400)
  static const penalty = Color(0xFF8A1F3D);    // --kc-penalty
  static const king = Color(0xFFC89B3D);       // --kc-king (gilded)

  // Touch targets — `--kc-touch-min` / `--kc-touch-comfortable`.
  static const double touchMin = 48, touchComfortable = 64;

  // Spacing scale (4px base) — `--kc-space-<n>`.
  static const double space1 = 4;    // --kc-space-1
  static const double space1half = 6; // half-step: `BK.AppBar` bottom-gap per shared.jsx
  static const double space2 = 8;    // --kc-space-2
  static const double space3 = 12;   // --kc-space-3
  static const double space4 = 16;   // --kc-space-4
  static const double space5 = 20;   // --kc-space-5
  static const double space6 = 24;   // --kc-space-6
  static const double space8 = 32;   // --kc-space-8
  static const double space10 = 40;  // --kc-space-10
  static const double space12 = 48;  // --kc-space-12

  // Radii — `--kc-radius-*`.
  static const double radiusSm = 4;     // --kc-radius-sm
  static const double radiusMd = 8;     // --kc-radius-md
  static const double radiusLg = 12;    // --kc-radius-lg
  static const double radiusXl = 16;    // --kc-radius-xl
  static const double radiusPill = 999; // --kc-radius-pill

  /// Light-Theme — mapping fuer `:root` (CSS default-Surface-Block).
  static const light = KubbTokens(
    bg: chalk50, bgRaised: chalk0, bgSunken: chalk100,
    fg: stone900, fgMuted: stone500, fgSubtle: stone400,
    line: stone200, lineStrong: stone900,
    primary: meadow500, primaryHover: meadow600, primaryPress: meadow700,
    onPrimary: chalk50, accent: wood400, accentHover: wood500,
    onAccent: stone900, danger: miss, onDanger: chalk50,
  );

  /// Dark-Theme — mapping fuer `.kc-dark` Block.
  static const dark = KubbTokens(
    bg: stone900, bgRaised: stone800, bgSunken: Color(0xFF050402),
    fg: chalk50, fgMuted: stone300, fgSubtle: stone400,
    line: stone700, lineStrong: chalk50,
    primary: meadow400, primaryHover: meadow300, primaryPress: meadow700,
    onPrimary: stone900, accent: wood400, accentHover: wood500,
    onAccent: stone900, danger: miss, onDanger: chalk50,
  );

  /// High-Contrast — mapping fuer `.kc-hc` Block.
  static const highContrast = KubbTokens(
    bg: chalk0, bgRaised: chalk0, bgSunken: Color(0xFFF0EFE8),
    fg: Color(0xFF000000), fgMuted: Color(0xFF1A1A1A), fgSubtle: stone400,
    line: Color(0xFF000000), lineStrong: Color(0xFF000000),
    primary: Color(0xFF0F4A08), primaryHover: meadow700, primaryPress: meadow800,
    onPrimary: chalk0, accent: Color(0xFF6E3C00), accentHover: wood600,
    onAccent: chalk0, danger: miss, onDanger: chalk0,
  );

  @override
  KubbTokens copyWith({
    Color? bg, Color? bgRaised, Color? bgSunken, Color? fg, Color? fgMuted,
    Color? fgSubtle, Color? line, Color? lineStrong, Color? primary,
    Color? primaryHover, Color? primaryPress, Color? onPrimary, Color? accent,
    Color? accentHover, Color? onAccent, Color? danger, Color? onDanger,
  }) => KubbTokens(
    bg: bg ?? this.bg, bgRaised: bgRaised ?? this.bgRaised,
    bgSunken: bgSunken ?? this.bgSunken, fg: fg ?? this.fg,
    fgMuted: fgMuted ?? this.fgMuted, fgSubtle: fgSubtle ?? this.fgSubtle,
    line: line ?? this.line, lineStrong: lineStrong ?? this.lineStrong,
    primary: primary ?? this.primary, primaryHover: primaryHover ?? this.primaryHover,
    primaryPress: primaryPress ?? this.primaryPress, onPrimary: onPrimary ?? this.onPrimary,
    accent: accent ?? this.accent, accentHover: accentHover ?? this.accentHover,
    onAccent: onAccent ?? this.onAccent, danger: danger ?? this.danger,
    onDanger: onDanger ?? this.onDanger,
  );

  @override
  KubbTokens lerp(ThemeExtension<KubbTokens>? other, double t) =>
      other is KubbTokens ? other : this;
}
