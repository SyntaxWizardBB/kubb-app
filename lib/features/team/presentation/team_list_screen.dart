import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Two-tab team discovery: "Meine Teams" lists the caller's
/// memberships (server-side via `team_list_for_caller`); "Suchen"
/// filters the same list client-side by display name. Server-side
/// search is deferred to M5 per the M3 task notes.
class TeamListScreen extends ConsumerStatefulWidget {
  const TeamListScreen({super.key});

  @override
  ConsumerState<TeamListScreen> createState() => _State();
}

class _State extends ConsumerState<TeamListScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;
  final TextEditingController _query = TextEditingController();
  String _submitted = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: const KubbAppBar(eyebrow: 'Teams', title: 'Übersicht'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/teams/new'),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Neues Team'),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tab,
            labelColor: tokens.fg,
            unselectedLabelColor: tokens.fgMuted,
            indicatorColor: tokens.primary,
            tabs: const [
              Tab(text: 'Meine Teams'),
              Tab(text: 'Suchen'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                const _List(query: null),
                Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(KubbTokens.space4),
                    child: TextField(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (v) =>
                          setState(() => _submitted = v.trim()),
                      decoration: const InputDecoration(
                        hintText: 'Team-Name suchen',
                        prefixIcon: Icon(LucideIcons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(child: _List(query: _submitted)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.query});

  /// `null` → "Meine Teams" tab (no filter). Non-null → search tab; an
  /// empty string means "no query yet, show everything".
  final String? query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return ref.watch(teamListProvider).when(
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
            final q = query?.toLowerCase() ?? '';
            final shown = q.isEmpty
                ? rows
                : rows
                    .where((t) => t.displayName.toLowerCase().contains(q))
                    .toList(growable: false);
            if (shown.isEmpty) {
              return Center(
                child: Text(
                    query == null
                        ? 'Du bist noch keinem Team beigetreten.'
                        : 'Keine Teams gefunden.',
                    style: TextStyle(fontSize: 14, color: tokens.fgMuted)),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(KubbTokens.space4,
                  KubbTokens.space4, KubbTokens.space4, KubbTokens.space12),
              itemCount: shown.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: KubbTokens.space3),
              itemBuilder: (context, i) => _Card(
                team: shown[i],
                onTap: () => context.go('/teams/${shown[i].id}'),
              ),
            );
          },
        );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.team, required this.onTap});
  final TeamWire team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(team.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: tokens.fg)),
              const SizedBox(height: KubbTokens.space2),
              Text(team.leagueMembership,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
