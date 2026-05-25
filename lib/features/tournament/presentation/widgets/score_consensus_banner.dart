import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Yellow info-strip shown on the match-detail screen whenever the
/// consensus retry counter is above 1. Caps at the spec's max of 3.
class ScoreConsensusBanner extends StatelessWidget {
  const ScoreConsensusBanner({required this.attempt, super.key});

  /// 1-based consensus round counter. The banner hides when 1.
  final int attempt;

  static const int maxAttempts = 3;

  @override
  Widget build(BuildContext context) {
    if (attempt <= 1) return const SizedBox.shrink();
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: KubbTokens.space3),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: KubbTokens.wood100,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: KubbTokens.wood400, width: 2),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertTriangle, color: KubbTokens.wood600),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              l.tournamentMatchConsensusAttempt(attempt, maxAttempts),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
