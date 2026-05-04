import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Tone of the wizard eyebrow + title block.
///
///   * `primary` — coloured eyebrow (`tokens.primary`), large 24-pt title,
///     extra horizontal padding around the title. Used by signup and
///     restore flows.
///   * `danger`  — red eyebrow (`KubbTokens.miss`), slightly smaller
///     22-pt title, no extra padding. Used by the delete-account flow.
enum WizardHeaderTone { primary, danger }

/// Header bar for multi-step wizard flows: back/close buttons, step
/// counter, eyebrow, title, and optional progress dots.
///
/// Pass [showStepDots] = false to hide the dot row (used by the
/// delete-account flow, which only has two pages and uses tone-coding
/// instead of progress affordance).
class WizardHeader extends StatelessWidget {
  const WizardHeader({
    required this.step,
    required this.total,
    required this.eyebrow,
    required this.title,
    this.onBack,
    this.onClose,
    this.showStepDots = true,
    this.tone = WizardHeaderTone.primary,
    super.key,
  });

  final int step;
  final int total;
  final String eyebrow;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final bool showStepDots;
  final WizardHeaderTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final isDanger = tone == WizardHeaderTone.danger;
    final eyebrowColor = isDanger ? KubbTokens.miss : tokens.primary;

    final titleWidget = Text(
      title,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: isDanger ? 22 : 24,
        fontWeight: FontWeight.w800,
        letterSpacing: isDanger ? -0.4 : -0.6,
        color: tokens.fg,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space2,
        KubbTokens.space2,
        KubbTokens.space2,
        KubbTokens.space3,
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: KubbTokens.touchMin,
                height: KubbTokens.touchMin,
                child: onBack != null
                    ? IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: l10n.authCommonBack,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  l10n.authWizardStepCount(step + 1, total),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.fgMuted,
                  ),
                ),
              ),
              SizedBox(
                width: KubbTokens.touchMin,
                height: KubbTokens.touchMin,
                child: onClose != null
                    ? IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                        tooltip: l10n.authCommonClose,
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(
            eyebrow,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: eyebrowColor,
            ),
          ),
          const SizedBox(height: 4),
          if (isDanger)
            titleWidget
          else
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
              child: titleWidget,
            ),
          if (showStepDots) ...[
            const SizedBox(height: KubbTokens.space3),
            _StepDots(current: step, total: total),
          ],
        ],
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= current ? tokens.primary : KubbTokens.stone200,
              borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
