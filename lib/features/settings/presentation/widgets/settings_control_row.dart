import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// A settings row that pairs a label (+ optional subtitle) with a trailing
/// control widget (Switch, SegmentedButton, value text, …).
///
/// Counterpart to `SettingsRow` (which is icon + label + chevron for
/// navigation). This one carries the inline controls used inside the App and
/// Finisseur option groups, so every option row shares one consistent layout
/// instead of the ad-hoc `row()` helper the settings block used before.
class SettingsControlRow extends StatelessWidget {
  const SettingsControlRow({
    required this.label,
    required this.trailing,
    super.key,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space4,
        vertical: KubbTokens.space2,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tokens.fg,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            trailing,
          ],
        ),
      ),
    );
  }
}
