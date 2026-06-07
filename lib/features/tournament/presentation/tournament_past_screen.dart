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
/// Shows only tournaments whose final has been entered and confirmed —
/// i.e. those in [TournamentStatus.finalized]. Reuses the existing list
/// path ([tournamentListProvider]) and the shared [TournamentCard];
/// tapping a card navigates to the existing detail route, keeping the
/// caller on the tournament tab stack.
class TournamentPastScreen extends ConsumerWidget {
  const TournamentPastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    // Fetch finalized tournaments directly via the status-filtered list
    // path. A null filter would mix in drafts/published rows, so we ask
    // the server for the finalized slice and additionally guard below.
    // Mirror the discovery list screen and keep the slice fresh while the
    // screen is open, so a tournament finalized elsewhere appears here. CDC
    // discovery invalidates the finalized slice too (no periodic poll).
    ref.watch(tournamentListCdcProvider);
    final async = ref.watch(tournamentListProvider(TournamentStatus.finalized));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentPastEyebrow,
        title: l.tournamentPastTitle,
        actions: const [InboxBellAction()],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              e.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (rows) {
          // Defensive client-side guard: show exclusively finalized
          // tournaments regardless of what the server returns.
          final finalized = rows
              .where((t) => t.status == TournamentStatus.finalized)
              .toList(growable: false);
          if (finalized.isEmpty) {
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
            itemCount: finalized.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KubbTokens.space3),
            itemBuilder: (context, i) {
              final t = finalized[i];
              final detailPath =
                  '${TournamentRoutes.detail}/${t.tournamentId.value}';
              return TournamentCard(
                summary: t,
                onTap: () => context.push(detailPath),
              );
            },
          );
        },
      ),
    );
  }
}
