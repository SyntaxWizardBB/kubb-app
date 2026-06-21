import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Per-step "Erklärungen anzeigen" state for the setup wizard. Default off,
/// flipped by [WizardHelpToggle]; `KubbField` reads [show] to surface its info
/// affordance.
class WizardHelp extends InheritedWidget {
  const WizardHelp({
    required this.show,
    required super.child,
    super.key,
  });

  /// Whether explanations are visible for the current step.
  final bool show;

  /// Reads the help state. Returns `false` when no [WizardHelp] is in scope,
  /// so widgets stay quiet by default outside the wizard.
  static bool of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<WizardHelp>();
    return widget?.show ?? false;
  }

  @override
  bool updateShouldNotify(WizardHelp oldWidget) => show != oldWidget.show;
}

/// Toggle that flips the [WizardHelp] state at the top of a step.
class WizardHelpToggle extends StatelessWidget {
  const WizardHelpToggle({
    required this.value,
    required this.onChanged,
    required this.label,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final active = value ? tokens.primary : tokens.fgMuted;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space2,
          vertical: KubbTokens.space1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.helpCircle, size: 16, color: active),
            const SizedBox(width: KubbTokens.space2),
            Text(
              label,
              style: tokens.labelStyle.copyWith(color: active),
            ),
            const SizedBox(width: KubbTokens.space2),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: tokens.primary,
            ),
          ],
        ),
      ),
    );
  }
}
