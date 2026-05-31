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

/// Discovery list reached from the hub's "Aktuelle Turniere" tile.
///
/// Shows every published (non-draft, not-yet-finished) tournament as a
/// flat list — the per-caller "mine" view now lives behind the hub's
/// "Angemeldete Turniere" tile, and creating is the organizer-gated hub
/// tile, so this screen no longer needs tabs or a FAB.
class TournamentListScreen extends ConsumerWidget {
  const TournamentListScreen({super.key});

  /// Lifecycle states that count as "published / currently listed".
  static const _published = <TournamentStatus>{
    TournamentStatus.published,
    TournamentStatus.registrationOpen,
    TournamentStatus.registrationClosed,
    TournamentStatus.live,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    ref.watch(tournamentListPollingProvider(null));
    final async = ref.watch(tournamentListProvider(null));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentListEyebrow,
        title: l.tournamentListTabPublic,
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
          final published = rows
              .where((t) => _published.contains(t.status))
              .toList(growable: false);
          if (published.isEmpty) {
            return KubbEmptyState(
              title: l.emptyTournamentsTitle,
              body: l.tournamentBrowseEmptyBody,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space4,
              KubbTokens.space12,
            ),
            itemCount: published.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KubbTokens.space3),
            itemBuilder: (context, i) {
              final t = published[i];
              return TournamentCard(
                summary: t,
                onTap: () => context.push(
                  '${TournamentRoutes.detail}/${t.tournamentId.value}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
