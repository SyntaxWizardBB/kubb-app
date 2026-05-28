import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/team/application/team_providers.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Lists the caller's `state = 'pending'` team invitations and lets the
/// user accept or decline each one. Acceptance navigates to the new
/// team detail; rejection only invalidates the list so the card
/// disappears on the next rebuild.
///
/// Route: `/teams/invitations` — opened both from the inbox tap on a
/// `team_invitation` item and (eventually) from a profile shortcut.
class TeamInvitationScreen extends ConsumerWidget {
  const TeamInvitationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(pendingInvitationsProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => GoRouter.of(context).pop()),
        title: const Text('Team-Einladungen'),
      ),
      body: async.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(KubbTokens.space5),
                child: Text(
                  'Keine offenen Einladungen.',
                  style: TextStyle(fontSize: 14, color: tokens.fgMuted),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pendingInvitationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(KubbTokens.space4),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: KubbTokens.space2),
              itemBuilder: (context, i) => _InvitationCard(item: items[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              'Einladungen konnten nicht geladen werden:\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: KubbTokens.miss),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvitationCard extends ConsumerWidget {
  const _InvitationCard({required this.item});

  final PendingTeamInvitation item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final inviterShort = item.invitedByUserId.length >= 8
        ? item.invitedByUserId.substring(0, 8)
        : item.invitedByUserId;
    final created = item.createdAt.toLocal();
    final createdLabel =
        '${created.day}.${created.month}.${created.year}';

    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.all(KubbTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.team.displayName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Liga: ${item.team.leagueMembership}',
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
            const SizedBox(height: 2),
            Text(
              'Von $inviterShort  •  $createdLabel',
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
            const SizedBox(height: KubbTokens.space3),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _respond(context, ref, accept: true),
                    child: const Text('Annehmen'),
                  ),
                ),
                const SizedBox(width: KubbTokens.space3),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _respond(context, ref, accept: false),
                    child: const Text('Ablehnen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref, {
    required bool accept,
  }) async {
    final actions = ref.read(teamActionsProvider);
    try {
      await actions.respondInvitation(
        item.invitationId,
        accept: accept,
        teamId: TeamId(item.team.id),
      );
      if (!context.mounted) return;
      if (accept) {
        context.go('/teams/${item.team.id}');
      }
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    }
  }
}
