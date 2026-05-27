import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Compact inline marker shown in the match-detail header while an
/// outbox row is queued (no `acknowledgedAt`). The label uses inline
/// German copy on purpose — the l10n keys land with TASK-M4.3-T14 and
/// are wired in parallel; the visible string is fixed so the marker is
/// usable before that swap.
class ScorePendingIndicator extends StatelessWidget {
  const ScorePendingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      margin: const EdgeInsets.only(top: KubbTokens.space2),
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: KubbTokens.wood50,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        border: Border.all(color: KubbTokens.wood300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(KubbTokens.wood600),
            ),
          ),
          const SizedBox(width: KubbTokens.space2),
          Text(
            'ausstehend, wird übertragen',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Red conflict banner surfaced when the outbox holds a row with
/// `lastErrorCode='STALE_CONSENSUS_ROUND'`. Explains the
/// R-M4.3-3-mitigation flow and offers a re-entry callback that scrolls
/// the user back to the score input.
class ScoreConflictBanner extends StatelessWidget {
  const ScoreConflictBanner({required this.onReenter, super.key});

  /// Invoked when the user taps "Erneut eingeben". The caller is
  /// responsible for resetting drafts / scrolling to the score input;
  /// the banner itself does not mutate state.
  final VoidCallback onReenter;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: KubbTokens.space3),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: KubbTokens.miss, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.alertOctagon, color: KubbTokens.miss),
              SizedBox(width: KubbTokens.space2),
              Expanded(
                child: Text(
                  'Sync-Konflikt',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: KubbTokens.miss,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          const Text(
            'Dein Vorschlag konnte nicht übertragen werden, weil der '
            'Gegner schon korrigiert hat. Bitte erneut eingeben.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KubbTokens.wood800,
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onReenter,
              style: FilledButton.styleFrom(
                backgroundColor: KubbTokens.miss,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Erneut eingeben'),
            ),
          ),
        ],
      ),
    );
  }
}
