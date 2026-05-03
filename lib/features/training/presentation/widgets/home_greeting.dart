import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

class HomeGreeting extends StatelessWidget {
  const HomeGreeting({required this.eyebrow, required this.greeting, super.key});

  final String eyebrow;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: t.labelSmall?.copyWith(
            fontSize: 11, fontWeight: FontWeight.w600,
            letterSpacing: 0.88, color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          greeting,
          style: t.headlineMedium?.copyWith(
            fontSize: 28, fontWeight: FontWeight.w800,
            letterSpacing: -0.56, color: tokens.fg,
          ),
        ),
      ],
    );
  }
}
