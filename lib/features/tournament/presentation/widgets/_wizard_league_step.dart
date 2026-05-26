import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Sub-step 4.5 of the tournament setup wizard. Asks the organizer
/// whether the tournament counts towards the league. Default is `false`
/// (conservative — organizers must actively opt in, ADR-0017 §4).
///
/// Kept as a stateless helper so the wizard owns the draft state and
/// hands the current [value] and an [onChanged] callback in. T13 mounts
/// this widget in `tournament_setup_wizard.dart`.
class WizardLeagueStep extends StatelessWidget {
  const WizardLeagueStep({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.tournamentWizardStep45Title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        Container(
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
            color: value ? tokens.bgSunken : tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            border: Border.all(
              color: value ? tokens.primary : tokens.line,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.tournamentWizardLeagueEligibleLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
              ),
              const SizedBox(width: KubbTokens.space3),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: tokens.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        Text(
          l10n.tournamentWizardLeagueEligibleHelper,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: tokens.fgMuted,
          ),
        ),
      ],
    );
  }
}
