import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_field.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Inline configuration block for the Schoch format option in the
/// setup wizard (TASK-M5.3-T10). Lets the organizer type the number of
/// rounds (default `ceil(log2(n))`, OD-M5-04), surfaces the read-only
/// tiebreak order (Buchholz → Direct-Encounter → Random) and, for large
/// fields, hints that more rounds help separate the standings. Schoch is the
/// big-field Vorrunde, so there is no upper participant limit here.
class SchochConfigSection extends StatelessWidget {
  const SchochConfigSection({
    required this.participantCount,
    required this.rounds,
    required this.onRoundsChanged,
    this.info,
    super.key,
  });

  /// Anchor for default/clamp calculations. Wizard hands in
  /// `draft.maxParticipants`.
  final int participantCount;
  final int rounds;
  final ValueChanged<int> onRoundsChanged;

  /// Explainer for the rounds choice. Surfaced via [KubbField] only in help
  /// mode (Schoch rounds is one of the kept, explanation-worthy glyphs).
  final InfoIconButton? info;

  static const int roundsMin = 5;
  static const int roundsMax = 9;

  /// Above this field size the section nudges the organizer towards more
  /// rounds — a hint, never a limit. Schoch handles arbitrary field sizes.
  static const int largeFieldHint = 64;

  /// `clamp(ceil(log2(n)) + 3, 5, 9)` per decision §G — yields the empirical
  /// default of 8 rounds for typical fields (n ≈ 32–128) and never drops
  /// below the lower bound of [roundsMin] for tiny rosters.
  static int defaultRounds(int participantCount) {
    if (participantCount < 2) return roundsMin;
    final raw = (math.log(participantCount) / math.ln2).ceil() + 3;
    return raw.clamp(roundsMin, roundsMax);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final largeField = participantCount > largeFieldHint;
    return Container(
      margin: const EdgeInsets.only(top: KubbTokens.space3),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (largeField) ...[
            Container(
              padding: const EdgeInsets.all(KubbTokens.space2),
              decoration: BoxDecoration(
                color: tokens.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
                border: Border.all(color: tokens.primary),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: tokens.primary),
                  const SizedBox(width: KubbTokens.space2),
                  Expanded(
                    child: Text(
                      l10n.tournamentWizardSchochLargeFieldHint,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
          ],
          KubbField(
            label: l10n.tournamentWizardSchochRoundsLabel,
            info: info,
            helper: l10n.tournamentWizardSchochTiebreak,
            child: WizardNumberField(
              label: l10n.tournamentWizardSchochRoundsLabel,
              value: rounds,
              min: roundsMin,
              max: roundsMax,
              onChanged: onRoundsChanged,
              labelless: true,
            ),
          ),
        ],
      ),
    );
  }
}
