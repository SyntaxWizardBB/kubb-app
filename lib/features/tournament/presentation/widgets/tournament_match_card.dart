import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// One row in the tournament match list. Compact, tappable card with
/// the two opponents (or "BYE"), a status pill, and the final score
/// when the match is finalised.
class TournamentMatchCard extends StatelessWidget {
  const TournamentMatchCard({
    required this.match,
    required this.nameFor,
    required this.onTap,
    super.key,
  });

  final TournamentMatchRef match;
  final String Function(TournamentParticipantId id) nameFor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final isBye = match.participantB == null;
    final aLabel = match.participantA == null
        ? '?'
        : nameFor(match.participantA!);
    final bLabel = isBye
        ? l.tournamentMatchBye
        : nameFor(match.participantB!);
    final scoreLabel = _scoreLabel(match);
    final statusLabel = _statusLabel(l, match.status);

    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            border: Border.all(color: tokens.line),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.bgSunken,
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                ),
                child: Text(
                  '${match.matchNumberInRound}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: tokens.fgMuted,
                  ),
                ),
              ),
              const SizedBox(width: KubbTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                    Text(
                      bLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isBye ? tokens.fgMuted : tokens.fg,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KubbTokens.space3),
              if (scoreLabel != null)
                Text(
                  scoreLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              const SizedBox(width: KubbTokens.space3),
              _StatusPill(label: statusLabel, status: match.status),
            ],
          ),
        ),
      ),
    );
  }

  String? _scoreLabel(TournamentMatchRef m) {
    if (m.status != TournamentMatchStatus.finalized &&
        m.status != TournamentMatchStatus.overridden) {
      return null;
    }
    final a = m.finalScoreA;
    final b = m.finalScoreB;
    if (a == null || b == null) return null;
    return '$a:$b';
  }

  String _statusLabel(AppLocalizations l, TournamentMatchStatus s) {
    switch (s) {
      case TournamentMatchStatus.scheduled:
        return l.tournamentMatchStatusScheduled;
      case TournamentMatchStatus.awaitingResults:
        return l.tournamentMatchStatusAwaiting;
      case TournamentMatchStatus.disputed:
        return l.tournamentMatchStatusDisputed;
      case TournamentMatchStatus.finalized:
        return l.tournamentMatchStatusFinalized;
      case TournamentMatchStatus.overridden:
        return l.tournamentMatchStatusOverridden;
      case TournamentMatchStatus.voided:
        return l.tournamentMatchStatusVoided;
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.status});

  final String label;
  final TournamentMatchStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final color = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: tokens.fg,
        ),
      ),
    );
  }

  Color _color(TournamentMatchStatus s) {
    switch (s) {
      case TournamentMatchStatus.scheduled:
        return KubbTokens.stone400;
      case TournamentMatchStatus.awaitingResults:
        return KubbTokens.wood400;
      case TournamentMatchStatus.disputed:
        return KubbTokens.miss;
      case TournamentMatchStatus.finalized:
        return KubbTokens.meadow500;
      case TournamentMatchStatus.overridden:
        return KubbTokens.meadow700;
      case TournamentMatchStatus.voided:
        return KubbTokens.stone400;
    }
  }
}
