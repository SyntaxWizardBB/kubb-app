import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

enum KubbCounterTone { hit, miss, heli, neutral }

class KubbCounter extends StatelessWidget {
  const KubbCounter({
    required this.label,
    required this.value,
    super.key,
    this.tone,
    this.muted = false,
    this.masked = false,
  });

  final String label;
  final int value;
  final KubbCounterTone? tone;
  final bool muted;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final numberColor = masked ? tokens.fgSubtle : _toneColor(tokens);
    final shown = masked ? '—' : value.toString();

    final content = Column(

      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 11 * 0.08,
            color: tokens.fgMuted,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          shown,
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -38 * 0.03,
            color: numberColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    if (!muted) return content;
    return Opacity(opacity: 0.45, child: content);
  }

  Color _toneColor(KubbTokens tokens) {
    switch (tone) {
      case KubbCounterTone.hit:
        return KubbTokens.hit;
      case KubbCounterTone.miss:
        return KubbTokens.miss;
      case KubbCounterTone.heli:
        return KubbTokens.heli;
      case KubbCounterTone.neutral:
      case null:
        return tokens.fg;
    }
  }
}
