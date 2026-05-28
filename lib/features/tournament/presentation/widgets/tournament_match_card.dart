import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_status_chip.dart';
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
              // W3-T4: central status mapping replaces the local
              // `_StatusPill` so `disputed` paints penalty, `finalized`
              // paints info (meadow-500 solid), `awaiting` paints heli
              // (wood-100) — each status now has a distinct tone.
              KubbStatusChip.tournamentMatch(status: match.status, l: l),
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

}
