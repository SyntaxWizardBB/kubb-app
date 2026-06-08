import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/core/ui/widgets/kubb_skeleton.dart';
import 'package:kubb_app/features/tournament/application/my_active_match_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_match_list_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_standings_screen.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_match_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// H3 — player-facing 3-tab live view of a running tournament (Plan A3).
///
/// Three tabs, default index 0:
///   0. "Mein Match"  — the caller's non-terminal match(es) -> score entry.
///   1. "Uebersicht"  — the full round-grouped match list (reused content).
///   2. "Rangliste"   — live standings (reused content).
///
/// The AppBar carries a top-right "Turnier-Infos" action -> tournament
/// detail (H2 master data). Pure UI: every tab reuses an existing provider
/// (`myActiveMatchesProvider`, `tournamentMatchListProvider`,
/// `tournamentStandingsProvider`) and the extracted reusable bodies, so no
/// list/standings logic is duplicated here.
class TournamentLiveScreen extends ConsumerStatefulWidget {
  const TournamentLiveScreen({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  ConsumerState<TournamentLiveScreen> createState() =>
      _TournamentLiveScreenState();
}

class _TournamentLiveScreenState extends ConsumerState<TournamentLiveScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    // Default tab (index 0) = "Mein Match".
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        // German UI strings (Plan A3). The live view sits outside the
        // l10n-migrated screens; copy is inlined here per the milestone
        // brief so the tab labels read in German verbatim.
        title: 'Live',
        actions: [
          IconButton(
            tooltip: 'Turnier-Infos',
            icon: const Icon(KubbIcons.info),
            color: tokens.fg,
            onPressed: () => context.push(
              '${TournamentRoutes.detail}/${widget.tournamentId}',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            labelColor: tokens.fg,
            unselectedLabelColor: tokens.fgMuted,
            indicatorColor: tokens.primary,
            tabs: const [
              Tab(text: 'Mein Match'),
              Tab(text: 'Uebersicht'),
              Tab(text: 'Rangliste'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _MyMatchTab(tournamentId: widget.tournamentId),
                TournamentMatchListView(tournamentId: widget.tournamentId),
                TournamentStandingsView(tournamentId: widget.tournamentId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Mein Match" tab: the caller's non-terminal matches in this tournament,
/// each tappable into the score-entry detail. Empty -> KubbEmptyState.
class _MyMatchTab extends ConsumerWidget {
  const _MyMatchTab({required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(
      myActiveMatchesProvider(TournamentId(tournamentId)),
    );

    return async.when(
      // AUDIT §4.3 — skeleton list rows instead of a spinner, consistent
      // with the embedded standings/match-list loading patterns.
      loading: () => const _MyMatchSkeleton(),
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
      data: (matches) {
        if (matches.isEmpty) {
          // German empty-state copy per Plan A3 ("kein aktuelles Match").
          return const KubbEmptyState(
            title: 'Kein aktuelles Match',
            body: 'Aktuell hast du kein offenes Match in diesem Turnier. '
                'Sobald die naechste Begegnung ansteht, erscheint sie hier.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(KubbTokens.space4),
          children: [
            for (final m in matches) ...[
              TournamentMatchCard(
                match: m,
                // M1: the card resolves both sides through the central
                // [ParticipantName] helper; no per-call-site name resolver.
                onTap: () => context.push(
                  TournamentRoutes.matchDetail(
                    tournamentId,
                    m.matchId.value,
                  ),
                ),
              ),
              const SizedBox(height: KubbTokens.space2),
            ],
          ],
        );
      },
    );
  }
}

/// AUDIT §4.3 — skeleton placeholder for the "Mein Match" tab while the
/// active-match list loads: three shimmering card-row placeholders.
class _MyMatchSkeleton extends StatelessWidget {
  const _MyMatchSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('myMatch.skeleton'),
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        for (var i = 0; i < 3; i++) ...[
          KubbSkeleton.row(
            key: ValueKey('myMatch.skeleton.row.$i'),
            columns: 3,
            height: 18,
          ),
          const SizedBox(height: KubbTokens.space3),
        ],
      ],
    );
  }
}
