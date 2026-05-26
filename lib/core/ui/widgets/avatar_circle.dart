import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Round avatar with one or two uppercase letters on a brand-palette
/// background. Pure view — caller resolves the color and initials.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    required this.initials,
    required this.color,
    this.size = 88,
    super.key,
  });

  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: KubbTheme.fontFamily,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: tokens.onPrimary,
          height: 1,
        ),
      ),
    );
  }
}
