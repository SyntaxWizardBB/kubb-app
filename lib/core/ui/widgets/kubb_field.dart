import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/wizard_help.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// One field scaffold for the setup wizard: a label row, the control, and a
/// helper/error line below. Replaces the hand-rolled `_FieldLabel` +
/// `_HelperText` pairs and folds the per-field info glyph into a single,
/// tokenised place.
///
/// The info affordance only appears when [info] is given AND the step's help
/// mode ([WizardHelp.show]) is on. With help off the label row stays quiet —
/// no glyph, no reserved gap. The label itself is tappable and opens the same
/// sheet, so the explanation is reachable without aiming for the small glyph.
class KubbField extends StatelessWidget {
  const KubbField({
    required this.label,
    required this.child,
    this.helper,
    this.optional = false,
    this.info,
    this.errorText,
    super.key,
  });

  final String label;
  final Widget child;

  /// Quiet hint shown below the control. Hidden while [errorText] is set.
  final String? helper;

  /// Marks the field as optional with a small trailing badge.
  final bool optional;

  /// Explainer for this field. Surfaced only in help mode.
  final InfoIconButton? info;

  /// Validation message shown below the control in the danger colour.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final showInfo = info != null && WizardHelp.of(context);

    final labelText = Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: tokens.labelStyle,
    );

    // In help mode the label opens the same sheet as the glyph; a transparent
    // hit target keeps the touch area comfortable without stretching the row.
    final tappableLabel = showInfo
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => info!.show(context),
            child: labelText,
          )
        : labelText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(child: tappableLabel),
            if (optional) ...[
              const SizedBox(width: KubbTokens.space2),
              Text(
                l10n.tournamentWizardOptional,
                style: tokens.optionalBadgeStyle,
              ),
            ],
            const Spacer(),
            // Fixed trailing column so the glyph (when present) lands in the
            // same spot across fields, and the row height stays put when help
            // toggles on and off.
            SizedBox(
              width: KubbTokens.touchMin,
              height: KubbTokens.touchMin,
              child: showInfo ? Center(child: info) : null,
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space2),
        child,
        if (errorText != null) ...[
          const SizedBox(height: KubbTokens.space1half),
          Text(errorText!, style: tokens.errorStyle),
        ] else if (helper != null) ...[
          const SizedBox(height: KubbTokens.space1half),
          Text(helper!, style: tokens.helperStyle),
        ],
      ],
    );
  }
}
