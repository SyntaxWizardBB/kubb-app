// ignore_for_file: avoid_multiple_declarations_per_line — dense palette tables
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

  final Color bg, bgRaised, bgSunken, fg, fgMuted, fgSubtle, line, lineStrong;
  final Color primary, primaryHover, primaryPress, onPrimary;
  final Color accent, accentHover, onAccent, danger, onDanger;

  // Brand palettes — identical across modes.
  static const meadow50 = Color(0xFFEEF6EC), meadow100 = Color(0xFFD6EAD0);
  static const meadow200 = Color(0xFFAED3A2), meadow300 = Color(0xFF7FB56F);
  static const meadow400 = Color(0xFF569748), meadow500 = Color(0xFF3A7C2E);
  static const meadow600 = Color(0xFF2D6324), meadow700 = Color(0xFF234E1C);
  static const meadow800 = Color(0xFF1A3A16), meadow900 = Color(0xFF112710);
  static const wood50 = Color(0xFFFAF3E6), wood100 = Color(0xFFF1E1BF);
  static const wood200 = Color(0xFFE6C98C), wood300 = Color(0xFFD6AB57);
  static const wood400 = Color(0xFFC08A33), wood500 = Color(0xFFA16F24);
  static const wood600 = Color(0xFF80561C), wood700 = Color(0xFF604015);
  static const wood800 = Color(0xFF422C0E);
  static const chalk0 = Color(0xFFFFFFFF), chalk50 = Color(0xFFFBFAF6);
  static const chalk100 = Color(0xFFF4F1E8), chalk200 = Color(0xFFE8E2D2);
  static const stone50 = Color(0xFFF4F3F0), stone100 = Color(0xFFE7E5DF);
  static const stone200 = Color(0xFFCFCCC1), stone300 = Color(0xFFA8A597);
  static const stone400 = Color(0xFF777567), stone500 = Color(0xFF4D4B40);
  static const stone600 = Color(0xFF34322A), stone700 = Color(0xFF232118);
  static const stone800 = Color(0xFF161510), stone900 = Color(0xFF0C0B07);

  // Semantic accents.
  static const hit = Color(0xFF2D6324), miss = Color(0xFFB73A2A);
  static const heli = Color(0xFFC08A33), penalty = Color(0xFF8A1F3D);
  static const king = Color(0xFFC89B3D);

  // Touch targets, spacing (4px base), radii.
  static const double touchMin = 48, touchComfortable = 64;
  static const double space1 = 4, space2 = 8, space3 = 12, space4 = 16;
  static const double space5 = 20, space6 = 24, space8 = 32, space10 = 40, space12 = 48;
  static const double radiusSm = 4, radiusMd = 8, radiusLg = 12;
  static const double radiusXl = 16, radiusPill = 999;

  static const light = KubbTokens(
    bg: chalk50, bgRaised: chalk0, bgSunken: chalk100,
    fg: stone900, fgMuted: stone500, fgSubtle: stone400,
    line: stone200, lineStrong: stone900,
    primary: meadow500, primaryHover: meadow600, primaryPress: meadow700,
    onPrimary: chalk50, accent: wood400, accentHover: wood500,
    onAccent: stone900, danger: miss, onDanger: chalk50,
  );

  static const dark = KubbTokens(
    bg: stone900, bgRaised: stone800, bgSunken: Color(0xFF050402),
    fg: chalk50, fgMuted: stone300, fgSubtle: stone400,
    line: stone700, lineStrong: chalk50,
    primary: meadow400, primaryHover: meadow300, primaryPress: meadow700,
    onPrimary: stone900, accent: wood400, accentHover: wood500,
    onAccent: stone900, danger: miss, onDanger: chalk50,
  );

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
