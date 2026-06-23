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
/// Two modes:
///
/// * **Per-tournament** — pass [tournamentId]. Renders when the caller has an
///   open match in that one tournament (the match-detail / live views).
/// * **Cross-tournament** — omit [tournamentId]. Renders the caller's most
///   urgent open match across every registered tournament
///   ([myActiveTournamentMatchProvider]) — the Home-Hub green tile (spec §4).
///
/// Either way it shows "Dein Platz: Pitch n — leg los!" with the opponent and
/// an action that opens the existing match-detail screen. Renders nothing
/// while loading, on error, or when the caller has no open match — so it is
/// safe to drop at the top of any participant view.
class PitchCallBanner extends ConsumerWidget {
  const PitchCallBanner({this.tournamentId, super.key});

  /// The tournament to scope the lookup to. When null the banner folds across
  /// all of the caller's tournaments (Home-Hub tile).
  final TournamentId? tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tid = tournamentId;
    final ({MyActiveMatch match, TournamentId tournamentId})? active;
    if (tid != null) {
      final perTournament = ref.watch(myActiveMatchProvider(tid)).maybeWhen(
            data: (m) => m,
            orElse: () => null,
          );
      active = perTournament == null
          ? null
          : (match: perTournament, tournamentId: tid);
    } else {
      final cross = ref.watch(myActiveTournamentMatchProvider).maybeWhen(
            data: (m) => m,
            orElse: () => null,
          );
      active = cross == null
          ? null
          : (match: cross.active, tournamentId: cross.tournament.tournamentId);
    }
    if (active == null) return const SizedBox.shrink();

    final selected = active;
    final l = AppLocalizations.of(context);
    final opponent = selected.match.opponentName?.trim();
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
          onTap: () => _open(context, selected.tournamentId, selected.match.match),
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
                      l.tournamentMatchPitchCallTitle(selected.match.pitchLabel),
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
                    onPressed: () =>
                        _open(context, selected.tournamentId, selected.match.match),
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

  void _open(
    BuildContext context,
    TournamentId tournamentId,
    TournamentMatchRef match,
  ) {
    context.go(TournamentRoutes.matchDetail(
      tournamentId.value,
      match.matchId.value,
    ));
  }
}
