import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_labeled_switch.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/wizard_number_field.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// One per-KO-round rules card: numeric Sätze-zum-Sieg, Match-Zeit and
/// Pause inputs plus a Tiebreak on/off switch with its own after-time. Edits
/// emit a new [MatchFormatSpec] via [onChanged]; `max_sets` is auto-clamped
/// to `2*setsToWin - 1` so a series can always be decided.
///
/// Props-in / callback-out and draft-free, so it is the single editor for a
/// round's format — used by the classic KO config step AND the stage-graph
/// node dialog (ADR-0033 §4).
class KoRoundBlock extends StatelessWidget {
  const KoRoundBlock({
    required this.title,
    required this.spec,
    required this.onChanged,
    super.key,
  });

  final String title;
  final MatchFormatSpec spec;
  final ValueChanged<MatchFormatSpec> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final timeMin = (spec.timeLimitSeconds / 60).round();
    return Container(
      margin: const EdgeInsets.only(bottom: KubbTokens.space3),
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: tokens.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space1half),
          WizardNumberField(
            label: l10n.tournamentWizardSetsToWinLabel,
            value: spec.setsToWin,
            min: 1,
            max: 4,
            compact: true,
            onChanged: (v) {
              final floor = 2 * v - 1;
              onChanged(
                spec.copyWith(
                  setsToWin: v,
                  maxSets: spec.maxSets < floor ? floor : spec.maxSets,
                ),
              );
            },
          ),
          WizardNumberField(
            label: l10n.tournamentWizardMatchTimeLabel,
            value: timeMin,
            min: 5,
            max: 120,
            compact: true,
            onChanged: (v) => onChanged(spec.copyWith(timeLimitSeconds: v * 60)),
          ),
          WizardNumberField(
            label: l10n.tournamentWizardKoRoundPauseLabel,
            value: (spec.breakBetweenMatchesSeconds / 60).round(),
            min: 0,
            max: 60,
            compact: true,
            onChanged: (v) =>
                onChanged(spec.copyWith(breakBetweenMatchesSeconds: v * 60)),
          ),
          KubbLabeledSwitch(
            title: l10n.tournamentWizardKoRoundTiebreakLabel,
            value: spec.tiebreakEnabled,
            onChanged: (on) => onChanged(
              spec.copyWith(
                tiebreakEnabled: on,
                // Seed a sane after-time when enabling without one set.
                tiebreakAfterSeconds: on
                    ? (spec.tiebreakAfterSeconds ??
                        (spec.timeLimitSeconds - 600)
                            .clamp(60, spec.timeLimitSeconds))
                    : spec.tiebreakAfterSeconds,
              ),
            ),
          ),
          if (spec.tiebreakEnabled)
            WizardNumberField(
              label: l10n.tournamentWizardKoRoundTiebreakAfterLabel,
              value: ((spec.tiebreakAfterSeconds ?? spec.timeLimitSeconds) / 60)
                  .round(),
              min: 1,
              max: timeMin,
              compact: true,
              onChanged: (v) =>
                  onChanged(spec.copyWith(tiebreakAfterSeconds: v * 60)),
            ),
        ],
      ),
    );
  }
}
