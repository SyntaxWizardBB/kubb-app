import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Two-tab discovery screen. Tab 1 surfaces caller-owned drafts; tab 2
/// shows public non-draft tournaments. Both tabs read the same list
/// provider — RLS hides foreign drafts on the server.
class TournamentListScreen extends ConsumerStatefulWidget {
  const TournamentListScreen({super.key});

  @override
  ConsumerState<TournamentListScreen> createState() => _State();
}

class _State extends ConsumerState<TournamentListScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    ref.watch(tournamentListPollingProvider(null));

    final myUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: KubbAppBar(
        eyebrow: l.tournamentListEyebrow,
        title: l.tournamentListTitle,
        actions: const InboxBellAction(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(TournamentRoutes.newTournament),
        icon: const Icon(LucideIcons.plus),
        label: Text(l.tournamentListNewButton),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            labelColor: tokens.fg,
            unselectedLabelColor: tokens.fgMuted,
            indicatorColor: tokens.primary,
            tabs: [
              Tab(text: l.tournamentListTabMine),
              Tab(text: l.tournamentListTabPublic),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _Tab(
                  emptyMessage: l.tournamentListEmptyMine,
                  filter: (s) =>
                      myUserId != null && s.createdBy?.value == myUserId,
                ),
                _Tab(
                  emptyMessage: l.tournamentListEmptyPublic,
                  filter: (s) =>
                      s.status == TournamentStatus.registrationOpen ||
                      s.status == TournamentStatus.registrationClosed ||
                      s.status == TournamentStatus.live,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends ConsumerWidget {
  const _Tab({required this.emptyMessage, required this.filter});

  final String emptyMessage;
  final bool Function(TournamentSummaryRef) filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    // Watched so the tab rebuilds on auth changes; the actual filter
    // for "mine" is enforced via RLS on the server side.
    ref.watch(currentUserIdProvider);
    final async = ref.watch(tournamentListProvider(null));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(e.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss)),
        ),
      ),
      data: (rows) {
        final filtered = rows.where(filter).toList(growable: false);
        if (filtered.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(KubbTokens.space6),
              child: Text(emptyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: tokens.fgMuted)),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(KubbTokens.space4,
              KubbTokens.space4, KubbTokens.space4, KubbTokens.space12),
          itemCount: filtered.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: KubbTokens.space3),
          itemBuilder: (context, i) {
            final t = filtered[i];
            return TournamentCard(
              summary: t,
              onTap: () => context.push(
                  '${TournamentRoutes.detail}/${t.tournamentId.value}'),
            );
          },
        );
      },
    );
  }
}
