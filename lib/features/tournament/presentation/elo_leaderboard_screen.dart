import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/core/ui/widgets/kubb_skeleton.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/data/elo_leaderboard_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/elo_leaderboard_row.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Global tournament-ELO best-list ("ELO-Bestenliste", `docs/ELO_RATINGS.md`
/// §7). A single global list over players (never teams) — unlike the
/// 4-tab Rangliste — backed by the RPC `elo_leaderboard_get` via
/// [eloLeaderboardProvider]. Players with `games < 10` carry a provisional
/// badge (marked, not hidden). Reached from the Tournament-Hub; lives on the
/// tournament branch so `context.push` keeps the BottomNav put.
class EloLeaderboardScreen extends ConsumerWidget {
  const EloLeaderboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(eloLeaderboardProvider);
    await ref.read(eloLeaderboardProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final async = ref.watch(eloLeaderboardProvider);
    final myId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.eloLeaderboardEyebrow,
        title: l.eloLeaderboardTitle,
      ),
      body: async.when(
        // Design-System: skeleton rows instead of a spinner (AUDIT §4.3).
        loading: () => const _EloLeaderboardSkeleton(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              l.eloLeaderboardError,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: rows.isEmpty
              // Empty-state wrapped in a scrollable so pull-to-refresh works.
              ? ListView(
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.6,
                      child: KubbEmptyState(
                        title: l.eloLeaderboardEmptyTitle,
                        body: l.eloLeaderboardEmptyBody,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _EloLeaderboardHeader(
                      nameLabel: l.eloLeaderboardColName,
                      eloLabel: l.eloLeaderboardColElo,
                      gamesLabel: l.eloLeaderboardColGames,
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) => EloLeaderboardRowTile(
                          row: rows[i],
                          provisionalLabel: l.eloLeaderboardProvisionalBadge,
                          highlight: myId != null && rows[i].userId == myId,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Column-header strip above the best-list. Column widths line up with
/// [EloLeaderboardRowTile] via [EloLeaderboardColumns].
class _EloLeaderboardHeader extends StatelessWidget {
  const _EloLeaderboardHeader({
    required this.nameLabel,
    required this.eloLabel,
    required this.gamesLabel,
  });

  final String nameLabel;
  final String eloLabel;
  final String gamesLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: tokens.fgMuted,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line, width: 0.5)),
      ),
      child: Row(children: [
        // Rank cell + avatar + gap (space3) align with the row's leading cells.
        const SizedBox(
          width: EloLeaderboardColumns.rank +
              EloLeaderboardColumns.avatar +
              KubbTokens.space3,
        ),
        Expanded(child: Text(nameLabel.toUpperCase(), style: style)),
        SizedBox(
          width: EloLeaderboardColumns.elo,
          child: Text(
            eloLabel.toUpperCase(),
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
        SizedBox(
          width: EloLeaderboardColumns.games,
          child: Text(
            gamesLabel.toUpperCase(),
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
      ]),
    );
  }
}

/// Loading placeholder: header + several [KubbSkeleton.row] lines, matching
/// the data layout (AUDIT §4.3 — skeleton over spinner).
class _EloLeaderboardSkeleton extends StatelessWidget {
  const _EloLeaderboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      key: const Key('elo.leaderboard.skeleton'),
      children: [
        Container(
          color: tokens.bgSunken,
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space3,
            vertical: KubbTokens.space2,
          ),
          child: KubbSkeleton.row(
            key: const Key('elo.leaderboard.skeleton.header'),
            height: 10,
          ),
        ),
        const Divider(height: 1),
        for (var i = 0; i < 8; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
            child: KubbSkeleton.row(
              key: ValueKey('elo.leaderboard.skeleton.row.$i'),
            ),
          ),
      ],
    );
  }
}
