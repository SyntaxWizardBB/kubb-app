// Brand icons substituted with closest Lucide equivalents for F1.
// CustomPainter implementation of the Brosi design glyphs is a future task —
// see docs/design/ui_kits/app/shared.jsx for the original SVG paths.
import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

class KubbIcons {
  const KubbIcons._();

  static const IconData heli = LucideIcons.wind;
  static const IconData king = LucideIcons.crown;
  static const IconData cup = LucideIcons.trophy;
  static const IconData trophy = LucideIcons.trophy;
  static const IconData star = LucideIcons.star;
  static const IconData flame = LucideIcons.flame;
  static const IconData stat = LucideIcons.barChart3;
  static const IconData target = LucideIcons.target;
  static const IconData profile = LucideIcons.user;

  /// Info glyph — opens master-data / details (e.g. the live view's
  /// "Turnier-Infos" action that routes to the tournament detail).
  static const IconData info = LucideIcons.info;

  /// Padlock — marks privacy-scoped content (e.g. the personal ELO that is
  /// only visible to the owner and accepted friends).
  static const IconData lock = LucideIcons.lock;

  /// Multi-figure glyph used for navigation entries that lead to the
  /// player hub (own profile + friends + groups). Distinct from
  /// [profile] so single-user contexts (avatar, details) keep the
  /// single-figure look.
  static const IconData players = LucideIcons.users;
}

class KubbIcon extends StatelessWidget {
  const KubbIcon(this.data, {super.key, this.size = 24, this.color});

  factory KubbIcon.lucide(IconData data, {double size = 24, Color? color}) =>
      KubbIcon(data, size: size, color: color);

  final IconData data;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>();
    return Icon(data, size: size, color: color ?? tokens?.fg);
  }
}
