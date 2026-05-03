import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

enum KubbTapPadTone { hit, miss, heli, ghost }

class KubbTapPad extends StatelessWidget {
  const KubbTapPad({
    required this.label,
    required this.sign,
    required this.tone,
    required this.onTap,
    super.key,
  });

  static const double minHeight = 84;

  final String label;
  final String sign;
  final KubbTapPadTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final palette = _resolve(tokens);

    return Material(
      color: palette.background,
      borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
      child: Ink(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
          border: palette.border,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: palette.foreground,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    sign,
                    style: TextStyle(
                      color: palette.foreground,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _PadPalette _resolve(KubbTokens tokens) {
    switch (tone) {
      case KubbTapPadTone.hit:
        return _PadPalette(background: KubbTokens.hit, foreground: Colors.white);
      case KubbTapPadTone.miss:
        return _PadPalette(background: KubbTokens.miss, foreground: Colors.white);
      case KubbTapPadTone.heli:
        return _PadPalette(background: KubbTokens.heli, foreground: KubbTokens.stone900);
      case KubbTapPadTone.ghost:
        return _PadPalette(
          background: tokens.bgRaised,
          foreground: tokens.fg,
          border: Border.all(color: tokens.line, width: 2),
        );
    }
  }
}

class _PadPalette {
  _PadPalette({required this.background, required this.foreground, this.border});

  final Color background;
  final Color foreground;
  final BoxBorder? border;
}
