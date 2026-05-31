import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/team/application/team_list_provider.dart';
import 'package:kubb_app/features/team/application/team_providers.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Team discovery in the friends-screen idiom: one integrated search field
/// filters the caller's memberships (server-side via `team_list_for_caller`)
/// by display name — no second tab. The FAB founds a new team. Server-side
/// directory search is deferred to a later milestone.
class TeamListScreen extends ConsumerStatefulWidget {
  const TeamListScreen({super.key});

  @override
  ConsumerState<TeamListScreen> createState() => _State();
}

class _State extends ConsumerState<TeamListScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  String _q = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _q = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    // Poll-refresh while the screen is open so teams accepted / changed on
    // another device appear without a manual reload.
    ref.watch(teamListPollingProvider);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(eyebrow: 'Teams', title: 'Übersicht'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/teams/new'),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Neues Team'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: KubbTokens.space2),
            TextField(
              controller: _query,
              autocorrect: false,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Team-Name suchen…',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                  borderSide: BorderSide(color: tokens.lineStrong),
                ),
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
            Expanded(child: _List(query: _q)),
          ],
        ),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.query});

  /// Empty string → show all of the caller's teams. Non-empty → filter by
  /// display name (substring).
  final String query;

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
            final q = query.toLowerCase();
            final shown = q.isEmpty
                ? rows
                : rows
                    .where((t) => t.displayName.toLowerCase().contains(q))
                    .toList(growable: false);
            if (shown.isEmpty) {
              return Center(
                child: Text(
                    q.isEmpty
                        ? 'Du bist noch keinem Team beigetreten.'
                        : 'Keine Teams gefunden.',
                    style: TextStyle(fontSize: 14, color: tokens.fgMuted)),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, KubbTokens.space12),
              itemCount: shown.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: KubbTokens.space3),
              itemBuilder: (context, i) => _Card(
                team: shown[i],
                onTap: () => context.push('/teams/${shown[i].id}'),
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
