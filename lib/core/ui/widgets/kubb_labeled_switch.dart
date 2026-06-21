import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/wizard_help.dart';

/// Shared title + subtitle + trailing [Switch] row for the setup wizard's
/// on/off toggles (rule variants, invite-only, and the "Anspiel 2-4-6"
/// default-on switch).
///
/// ADR-0033 P1: replaces the inline `_ToggleRow` / `SwitchListTile` one-offs
/// with one token-driven component.
///
/// The [info] glyph follows the same help-mode rule as the field scaffold: it
/// only shows when an explainer is given AND [WizardHelp.show] is on for the
/// step.
/// Outside a wizard (no [WizardHelp] in scope) help mode reads as off, so the
/// glyph stays hidden — the same quiet default the rest of the wizard uses.
class KubbLabeledSwitch extends StatelessWidget {
  const KubbLabeledSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.info,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Optional explainer glyph rendered between the text and the switch.
  final Widget? info;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final showInfo = info != null && WizardHelp.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 11, color: tokens.fgMuted),
                  ),
                ],
              ],
            ),
          ),
          if (showInfo) info!,
          const SizedBox(width: KubbTokens.space3),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: tokens.primary,
          ),
        ],
      ),
    );
  }
}
