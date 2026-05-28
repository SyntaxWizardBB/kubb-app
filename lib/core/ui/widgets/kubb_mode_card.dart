import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Brand-Tone-Vokabular fuer Akzent-Streifen auf Tiles und Chips.
///
/// Wird parallel von `KubbChip` (Sprint B, W2) genutzt; bewusst hier
/// kolokiert, damit `KubbModeCard` keine Cross-Branch-Abhaengigkeit hat.
/// Sobald `kubb_chip.dart` zentralisiert ist, wandert die Definition
/// dorthin und dieser File konsumiert nur noch.
enum KubbChipTone {
  /// Sniper · 8 m — Meadow (primary brand).
  sniperMeadow,

  /// Finisseur — Stone-900 ink.
  finisseurInk,

  /// Match — Wood-400 (accent).
  matchWood,

  /// Tournament — Wood-500 (deeper wood).
  tournamentWood,

  /// 4-m-Linie / Newcomer — Meadow-300 (lighter brand).
  line4mMeadowSoft,

  /// Neutraler Outline-Ton (ohne Akzent-Stripe-Farbe).
  neutral,
}

/// Generisches Mode-Tile fuer HomeScreen + TrainingSheet.
///
/// Layout (vgl. `docs/design/preview/components-modecard.html` Inset-Variant
/// und Mobile-Kit `HomeScreen.jsx`):
///   ┌─┬─────────────────────────────────────────────┐
///   │ │  [icon 24]    Title 18 bold · Subtitle 13   │
///   └─┴─────────────────────────────────────────────┘
///   ^ optionaler 4-px Akzent-Streifen (accentTone)
///
/// - Radius 14 dp (Inset-Card, kleiner als Brand-Tile mit 18 dp Full-Bg).
/// - Press-State: scale 0.98, 120 ms (Material-InkWell zusaetzlich).
/// - `disabled`: 50 % Opacity, kein onTap.
class KubbModeCard extends StatefulWidget {
  const KubbModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    super.key,
    this.accentTone,
    this.onTap,
    this.disabled = false,
  });

  /// Display 18 px Bold.
  final String title;

  /// Body 13 px stone-500.
  final String subtitle;

  /// Lucide- oder KubbIcons-Glyph, 24 dp.
  final IconData icon;

  /// Optionaler Akzent-Stripe links (4 dp breit).
  final KubbChipTone? accentTone;

  /// Tap-Callback; bei `null` oder `disabled == true` ignoriert.
  final VoidCallback? onTap;

  /// Setzt Opacity 0.5 und unterbindet Tap.
  final bool disabled;

  static const double borderRadius = 14;
  static const double minHeight = 64;
  static const double accentStripeWidth = 4;
  static const Duration pressDuration = Duration(milliseconds: 120);
  static const double pressedScale = 0.98;

  @override
  State<KubbModeCard> createState() => _KubbModeCardState();
}

class _KubbModeCardState extends State<KubbModeCard> {
  bool _pressed = false;

  bool get _interactive => !widget.disabled && widget.onTap != null;

  void _setPressed(bool value) {
    if (!_interactive) return;
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final accentColor = _accentColor(widget.accentTone);

    final titleStyle = textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.36,
      color: tokens.fg,
      height: 1.15,
    );
    final subtitleStyle = textTheme.bodySmall?.copyWith(
      fontSize: 13,
      color: KubbTokens.stone500,
      height: 1.25,
    );

    final card = Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbModeCard.borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _interactive ? widget.onTap : null,
        onHighlightChanged: _setPressed,
        borderRadius: BorderRadius.circular(KubbModeCard.borderRadius),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: tokens.line),
            borderRadius: BorderRadius.circular(KubbModeCard.borderRadius),
          ),
          constraints: const BoxConstraints(minHeight: KubbModeCard.minHeight),
          child: Row(
            children: [
              if (accentColor != null)
                Container(
                  width: KubbModeCard.accentStripeWidth,
                  // Stripe fills the full tile height (no fixed value so
                  // multi-line subtitles wachsen sauber mit).
                  constraints: const BoxConstraints(
                    minHeight: KubbModeCard.minHeight,
                  ),
                  color: accentColor,
                )
              else
                const SizedBox(width: KubbModeCard.accentStripeWidth),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KubbTokens.space3, KubbTokens.space3,
                  KubbTokens.space3, KubbTokens.space3,
                ),
                child: Icon(widget.icon, size: 24, color: tokens.fg),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: KubbTokens.space3,
                    horizontal: KubbTokens.space1,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: subtitleStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: KubbTokens.space3),
            ],
          ),
        ),
      ),
    );

    final scaled = AnimatedScale(
      duration: KubbModeCard.pressDuration,
      curve: Curves.easeOut,
      scale: _pressed ? KubbModeCard.pressedScale : 1,
      child: card,
    );

    return Semantics(
      button: true,
      enabled: _interactive,
      label: widget.title,
      hint: widget.subtitle,
      child: Opacity(
        opacity: widget.disabled ? 0.5 : 1,
        child: IgnorePointer(
          ignoring: !_interactive,
          child: scaled,
        ),
      ),
    );
  }

  Color? _accentColor(KubbChipTone? tone) {
    if (tone == null) return null;
    switch (tone) {
      case KubbChipTone.sniperMeadow:
        return KubbTokens.meadow500;
      case KubbChipTone.finisseurInk:
        return KubbTokens.stone900;
      case KubbChipTone.matchWood:
        return KubbTokens.wood400;
      case KubbChipTone.tournamentWood:
        return KubbTokens.wood500;
      case KubbChipTone.line4mMeadowSoft:
        return KubbTokens.meadow300;
      case KubbChipTone.neutral:
        return null;
    }
  }
}
