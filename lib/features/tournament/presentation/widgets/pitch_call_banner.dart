import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/my_active_match_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Player-facing "leg los" surface (spec "TournierStart").
///
/// When the caller has an open match in [tournamentId] — one they
/// participate in that is scheduled or awaiting results — this renders a
/// prominent "Dein Platz: Pitch n — leg los!" card with the opponent and
/// an action that opens the existing match-detail screen. Renders nothing
/// while loading, on error, or when the caller has no open match, so it is
/// safe to drop at the top of any participant view.
class PitchCallBanner extends ConsumerWidget {
  const PitchCallBanner({required this.tournamentId, super.key});

  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myActiveMatchProvider(tournamentId));
    final active = async.maybeWhen<MyActiveMatch?>(
      data: (m) => m,
      orElse: () => null,
    );
    if (active == null) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final opponent = active.opponentName?.trim();
    final opponentLabel = (opponent == null || opponent.isEmpty)
        ? l.tournamentParticipantUnknown
        : opponent;

    return Padding(
      key: const ValueKey('pitch-call-banner'),
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space4,
        0,
      ),
      child: Material(
        color: KubbTokens.meadow500,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          onTap: () => _open(context, active.match),
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(LucideIcons.flag,
                      color: KubbTokens.chalk0, size: 20),
                  const SizedBox(width: KubbTokens.space2),
                  Expanded(
                    child: Text(
                      l.tournamentMatchPitchCallTitle(active.pitchLabel),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: KubbTokens.chalk0,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: KubbTokens.space2),
                Text(
                  l.tournamentMatchPitchCallVersus(opponentLabel),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KubbTokens.chalk0.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: KubbTokens.space3),
                SizedBox(
                  height: KubbTokens.touchMin,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: KubbTokens.chalk0,
                      foregroundColor: KubbTokens.meadow700,
                    ),
                    onPressed: () => _open(context, active.match),
                    icon: const Icon(LucideIcons.play, size: 18),
                    label: Text(l.tournamentMatchPitchCallAction),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, TournamentMatchRef match) {
    context.go(TournamentRoutes.matchDetail(
      tournamentId.value,
      match.matchId.value,
    ));
  }
}
