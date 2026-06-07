import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_state_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_status_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_match_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Match list for one tournament, grouped by round. Tap a row to open
/// the match-detail score-entry screen. Polled at 5s.
class TournamentMatchListScreen extends ConsumerWidget {
  const TournamentMatchListScreen({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final id = TournamentId(tournamentId);
    final l = AppLocalizations.of(context);
    // M4.1-T12: realtime first, polling only when the per-tournament
    // channel has fallen back (M4.1-T10).
    ref.watch(tournamentMatchListRealtimeProvider(id));
    final fallbackActive = ref
        .watch(realtimeFallbackProvider(id))
        .maybeWhen(data: (v) => v, orElse: () => false);
    if (fallbackActive) {
      ref.watch(tournamentMatchListPollingProvider(id));
    }
    final async = ref.watch(tournamentMatchListProvider(id));

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        title: Text(l.tournamentMatchListTitle),
        leading: BackButton(onPressed: () => context.go(TournamentRoutes.hub)),
        actions: [
          IconButton(
            tooltip: l.tournamentStandingsTitle,
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () =>
                context.go(TournamentRoutes.standings(tournamentId)),
          ),
        ],
      ),
      body: Column(
        children: [
          RealtimeStateBanner(tournamentId: id),
          RealtimeStatusBanner(tournamentId: id),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(KubbTokens.space5),
                  child: Text(
                    '${l.tournamentMatchLoadError}: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: KubbTokens.miss),
                  ),
                ),
              ),
              data: (matches) => _MatchListBody(
                tournamentId: tournamentId,
                matches: matches,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchListBody extends StatelessWidget {
  const _MatchListBody({required this.tournamentId, required this.matches});

  final String tournamentId;
  final List<TournamentMatchRef> matches;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    if (matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(
            l.tournamentMatchListEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.fgMuted),
          ),
        ),
      );
    }
    final byRound = <int, List<TournamentMatchRef>>{};
    for (final m in matches) {
      byRound.putIfAbsent(m.roundNumber, () => <TournamentMatchRef>[]).add(m);
    }
    final rounds = byRound.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        for (final r in rounds) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
            child: Text(
              l.tournamentMatchListRound(r),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
                letterSpacing: 0.5,
              ),
            ),
          ),
          for (final m in byRound[r]!) ...[
            TournamentMatchCard(
              match: m,
              // CF3 / K08: the card prefers the server-projected
              // display name (single -> nickname, team -> team name).
              // This resolver is only the null/empty fallback, so it
              // returns the localized placeholder instead of a UUID
              // substring.
              nameFor: (id) => l.tournamentParticipantUnknown,
              onTap: () => context.go(
                TournamentRoutes.matchDetail(tournamentId, m.matchId.value),
              ),
            ),
            const SizedBox(height: KubbTokens.space2),
          ],
        ],
      ],
    );
  }
}
