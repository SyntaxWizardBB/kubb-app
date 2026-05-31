import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/club/application/club_membership_controller.dart';
import 'package:kubb_app/features/club/application/club_providers.dart';
import 'package:kubb_app/features/club/data/club_models.dart';
import 'package:kubb_app/features/club/presentation/club_routes.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// "Meine Vereine" in the friends-screen idiom: one integrated search field.
/// With a query it searches ALL clubs and lets you request to join from the
/// results; empty, it shows the clubs you belong to. The FAB founds a new club
/// (gated server-side on the early-access organizer capability).
class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  final _requested = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  Future<void> _request(ClubWire club) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(clubMembershipControllerProvider.notifier)
        .requestJoin(ClubId(club.id));
    if (!mounted) return;
    final failed = ref.read(clubMembershipControllerProvider).hasError;
    setState(() {
      if (!failed) _requested.add(club.id);
    });
    messenger.showSnackBar(SnackBar(
      content: Text(failed
          ? 'Anfrage nicht möglich (bereits Mitglied oder Anfrage offen).'
          : 'Beitrittsanfrage an ${club.displayName} gesendet.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(title: 'Meine Vereine'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(ClubRoutes.create),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Verein gründen'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: KubbTokens.space2),
            TextField(
              controller: _queryCtrl,
              autocorrect: false,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Verein suchen & beitreten…',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                  borderSide: BorderSide(color: tokens.lineStrong),
                ),
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
            Expanded(
              child: _query.length >= 2
                  ? _SearchResults(
                      query: _query,
                      requested: _requested,
                      onRequest: _request,
                    )
                  : const _MyClubs(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The caller's own clubs (no query). Tapping opens the club detail.
class _MyClubs extends ConsumerWidget {
  const _MyClubs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clubListProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(clubListProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text('Vereine konnten nicht geladen werden:\n$e',
                style: const TextStyle(fontSize: 13, color: KubbTokens.miss)),
          ),
        ]),
        data: (clubs) {
          if (clubs.isEmpty) {
            return ListView(children: const [
              SizedBox(height: KubbTokens.space8),
              KubbEmptyState(
                title: 'Noch kein Verein',
                body: 'Suche oben nach einem Verein zum Beitreten oder gründe '
                    'mit dem Plus-Knopf einen eigenen.',
              ),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: KubbTokens.space12),
            itemCount: clubs.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: KubbTokens.space2),
            itemBuilder: (context, i) => _ClubRow(
              club: clubs[i],
              onTap: () => context.push(ClubRoutes.detailFor(clubs[i].id)),
            ),
          );
        },
      ),
    );
  }
}

/// Directory search results — tap "Anfragen" to request to join.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.query,
    required this.requested,
    required this.onRequest,
  });

  final String query;
  final Set<String> requested;
  final Future<void> Function(ClubWire) onRequest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(clubSearchProvider(query));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Fehler: $e',
            style: const TextStyle(color: KubbTokens.miss)),
      ),
      data: (clubs) {
        if (clubs.isEmpty) {
          return Center(
            child: Text('Kein Verein gefunden für „$query".',
                style: TextStyle(fontSize: 14, color: tokens.fgMuted)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: KubbTokens.space12),
          itemCount: clubs.length,
          separatorBuilder: (_, _) => const SizedBox(height: KubbTokens.space2),
          itemBuilder: (context, i) {
            final club = clubs[i];
            return _ClubRow(
              club: club,
              trailing: requested.contains(club.id)
                  ? Text('Angefragt',
                      style: TextStyle(fontSize: 13, color: tokens.fgMuted))
                  : KubbButton(
                      variant: KubbButtonVariant.secondary,
                      size: KubbButtonSize.small,
                      onPressed: () => onRequest(club),
                      child: const Text('Anfragen'),
                    ),
            );
          },
        );
      },
    );
  }
}

class _ClubRow extends StatelessWidget {
  const _ClubRow({required this.club, this.onTap, this.trailing});

  final ClubWire club;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space3),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.bgSunken,
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                ),
                child: Icon(LucideIcons.shield, size: 20, color: tokens.fg),
              ),
              const SizedBox(width: KubbTokens.space3),
              Expanded(
                child: Text(
                  club.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
              ),
              trailing ??
                  Icon(LucideIcons.chevronRight,
                      size: 18, color: tokens.fgMuted),
            ],
          ),
        ),
      ),
    );
  }
}
