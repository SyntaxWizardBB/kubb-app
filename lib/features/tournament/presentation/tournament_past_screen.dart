import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Past tournaments list reached from the hub's "Vergangene Tourniere" tile.
///
/// Shows finished tournaments — finalized ones plus aborted ones, so an
/// organizer can find an aborted tournament here and reactivate or edit it
/// from the detail screen. Reuses the existing list path
/// ([tournamentListProvider]) — one status-filtered slice per terminal status
/// — and the shared [TournamentCard]; tapping a card navigates to the existing
/// detail route, keeping the caller on the tournament tab stack.
class TournamentPastScreen extends ConsumerWidget {
  const TournamentPastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    // Two status-filtered slices: finalized + aborted. A null filter would
    // mix in drafts/published rows, so we ask the server per terminal status
    // and additionally guard below. Mirror the discovery list screen and keep
    // the slices fresh while the screen is open; CDC discovery invalidates
    // them too (no periodic poll).
    ref.watch(tournamentListCdcProvider);
    final finalizedAsync =
        ref.watch(tournamentListProvider(TournamentStatus.finalized));
    final abortedAsync =
        ref.watch(tournamentListProvider(TournamentStatus.aborted));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentPastEyebrow,
        title: l.tournamentPastTitle,
        actions: const [InboxBellAction()],
      ),
      body: switch ((finalizedAsync, abortedAsync)) {
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
          Center(
            child: Padding(
              padding: const EdgeInsets.all(KubbTokens.space5),
              child: Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: KubbTokens.miss),
              ),
            ),
          ),
        (AsyncData(value: final finalized), AsyncData(value: final aborted)) =>
          _PastList(
            // Defensive client-side guard against whatever each slice returns.
            rows: [
              ...finalized
                  .where((t) => t.status == TournamentStatus.finalized),
              ...aborted.where((t) => t.status == TournamentStatus.aborted),
            ],
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PastList extends StatelessWidget {
  const _PastList({required this.rows});

  final List<TournamentSummaryRef> rows;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (rows.isEmpty) {
      return KubbEmptyState(
        title: l.tournamentPastEmptyTitle,
        body: l.tournamentPastEmptyBody,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space12,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: KubbTokens.space3),
      itemBuilder: (context, i) {
        final t = rows[i];
        final detailPath = '${TournamentRoutes.detail}/${t.tournamentId.value}';
        return TournamentCard(
          summary: t,
          onTap: () => context.push(detailPath),
        );
      },
    );
  }
}
