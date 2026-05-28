import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Semantische Tones der Status-Chips.
///
/// Quelle: `docs/design/preview/components-chips.html` und
/// `docs/design/quality-gates/component-library.md` (Chips, Sprint-B).
enum KubbChipTone {
  /// Neutral / "Standard" — stone-100 Background, stone-700 Foreground.
  neutral,

  /// Treffer / Sniper — meadow-100 / meadow-700.
  hit,

  /// Fehlschuss / Strafkubb — `#f8e2dd` / `#7a2517`.
  miss,

  /// Helikopter / Wurfqualifier — wood-100 / wood-700.
  heli,

  /// Strafkubb-Variante (semantisch wie `miss`, separat verfuegbar fuer
  /// kuenftige Differenzierung wie z.B. King-Penalty-Logik).
  penalty,

  /// King — `--kc-king` Background, dunkles Foreground.
  king,

  /// Info / aktive Auswahl — meadow-500 solid, chalk-50 Foreground.
  info,
}

/// Status-Pille im Brand-Look.
///
/// Mindesthoehe 32 dp, Radius `pill`, optionales `icon` links vom `label`.
class KubbChip extends StatelessWidget {
  const KubbChip({
    required this.tone,
    required this.label,
    super.key,
    this.icon,
  });

  /// Mindesthoehe gemaess Preview-Spec.
  static const double minHeight = 32;

  final KubbChipTone tone;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = _resolvePalette();

    return Semantics(
      container: true,
      label: label,
      child: Material(
        color: palette.background,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: palette.foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: palette.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _ChipPalette _resolvePalette() {
    switch (tone) {
      case KubbChipTone.neutral:
        return const _ChipPalette(
          background: KubbTokens.stone100,
          foreground: Color(0xFF34322A), // stone-600 (~700)
        );
      case KubbChipTone.hit:
        return const _ChipPalette(
          background: KubbTokens.meadow100,
          foreground: KubbTokens.meadow700,
        );
      case KubbChipTone.miss:
        return const _ChipPalette(
          background: Color(0xFFF8E2DD),
          foreground: Color(0xFF7A2517),
        );
      case KubbChipTone.heli:
        return const _ChipPalette(
          background: KubbTokens.wood100,
          foreground: KubbTokens.wood700,
        );
      case KubbChipTone.penalty:
        return const _ChipPalette(
          background: Color(0xFFF8E2DD),
          foreground: KubbTokens.penalty,
        );
      case KubbChipTone.king:
        return const _ChipPalette(
          background: KubbTokens.king,
          foreground: KubbTokens.stone900,
        );
      case KubbChipTone.info:
        return const _ChipPalette(
          background: KubbTokens.meadow500,
          foreground: KubbTokens.chalk50,
        );
    }
  }
}

class _ChipPalette {
  const _ChipPalette({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
