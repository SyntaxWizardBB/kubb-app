import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/club/application/club_membership_controller.dart';
import 'package:kubb_app/features/club/application/club_providers.dart';
import 'package:kubb_app/features/club/data/club_models.dart';
import 'package:kubb_app/features/club/presentation/club_routes.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Club detail: header, member roster with role chips, and — for owners /
/// admins — invite-by-nickname plus per-member role editing.
class ClubDetailScreen extends ConsumerWidget {
  const ClubDetailScreen({required this.clubId, super.key});

  final ClubId clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(clubDetailProvider(clubId));
    final myUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        title: async.maybeWhen(
          data: (d) => d.club.displayName,
          orElse: () => 'Verein',
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(KubbTokens.space6),
          child: Text(
            'Verein konnte nicht geladen werden:\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: KubbTokens.miss),
          ),
        ),
        data: (detail) {
          final me = detail.members
              .where((m) => m.userId == myUserId)
              .toList(growable: false);
          final isManager = me.isNotEmpty && me.first.isManager;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(clubDetailProvider(clubId)),
            child: ListView(
              padding: const EdgeInsets.all(KubbTokens.space4),
              children: [
                _SectionLabel('MITGLIEDER (${detail.members.length})',
                    tokens: tokens),
                const SizedBox(height: KubbTokens.space3),
                for (final m in detail.members) ...[
                  _MemberRow(
                    member: m,
                    canEdit: isManager,
                    onEdit: () => _editRoles(context, ref, m),
                  ),
                  const SizedBox(height: KubbTokens.space2),
                ],
                if (isManager) ...[
                  const SizedBox(height: KubbTokens.space4),
                  KubbButton(
                    variant: KubbButtonVariant.secondary,
                    onPressed: () =>
                        context.push(ClubRoutes.addMemberFor(clubId.value)),
                    child: const Text('Mitglied einladen'),
                  ),
                  const SizedBox(height: KubbTokens.space6),
                  _JoinRequests(clubId: clubId),
                ],
                if (me.isNotEmpty) ...[
                  const SizedBox(height: KubbTokens.space6),
                  KubbButton(
                    variant: KubbButtonVariant.danger,
                    onPressed: () => _leave(context, ref),
                    child: const Text('Verein verlassen'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verein verlassen?'),
        content: const Text(
          'Du verlässt diesen Verein. Als letzter Owner musst du zuerst '
          'einen anderen Owner bestimmen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verlassen'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(clubMembershipControllerProvider.notifier);
    await notifier.leave(clubId);
    if (!context.mounted) return;
    if (ref.read(clubMembershipControllerProvider).hasError) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Verlassen nicht möglich (z. B. letzter Owner).'),
      ));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Verein verlassen.')));
    context.pop();
  }

  Future<void> _editRoles(
    BuildContext context,
    WidgetRef ref,
    ClubMemberWire member,
  ) async {
    final isSelf = ref.read(currentUserIdProvider) == member.userId;
    final selected = {...member.roles};
    final saved = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(member.displayName ?? 'Rollen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final role in clubRoles)
                  CheckboxListTile(
                    dense: true,
                    title: Text(_roleLabel(role)),
                    value: selected.contains(role),
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        selected.add(role);
                      } else {
                        selected.remove(role);
                      }
                    }),
                  ),
                if (!isSelf)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: KubbTokens.miss,
                      ),
                      icon: const Icon(Icons.person_remove_outlined, size: 18),
                      label: const Text('Mitglied entfernen'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(_removeMember(context, ref, member));
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, selected),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(clubMembershipControllerProvider.notifier);
    await notifier.setRoles(clubId, UserId(member.userId), saved.toList());
    final failed = ref.read(clubMembershipControllerProvider).hasError;
    messenger.showSnackBar(SnackBar(
      content: Text(
        failed
            ? 'Rollen konnten nicht gespeichert werden (z. B. letzter Owner).'
            : 'Rollen aktualisiert.',
      ),
    ));
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    ClubMemberWire member,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${member.displayName ?? 'Mitglied'} entfernen?'),
        content: const Text('Das Mitglied wird aus dem Verein entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(clubMembershipControllerProvider.notifier);
    await notifier.removeMember(clubId, UserId(member.userId));
    final failed = ref.read(clubMembershipControllerProvider).hasError;
    messenger.showSnackBar(SnackBar(
      content: Text(
        failed
            ? 'Entfernen nicht möglich (z. B. letzter Owner).'
            : 'Mitglied entfernt.',
      ),
    ));
  }
}

/// Pending join requests for managers, with approve/decline. Renders nothing
/// when there are none.
class _JoinRequests extends ConsumerWidget {
  const _JoinRequests({required this.clubId});

  final ClubId clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(clubJoinRequestsProvider(clubId));
    return async.maybeWhen(
      data: (requests) {
        if (requests.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel('BEITRITTSANFRAGEN (${requests.length})',
                tokens: tokens),
            const SizedBox(height: KubbTokens.space3),
            for (final r in requests) ...[
              _JoinRequestRow(
                request: r,
                tokens: tokens,
                onRespond: (accept) => unawaited(() async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref
                      .read(clubMembershipControllerProvider.notifier)
                      .respondJoinRequest(clubId, r.requestId, accept: accept);
                  messenger.showSnackBar(SnackBar(
                    content: Text(accept
                        ? '${r.displayName ?? 'Spieler'} aufgenommen.'
                        : 'Anfrage abgelehnt.'),
                  ));
                }()),
              ),
              const SizedBox(height: KubbTokens.space2),
            ],
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _JoinRequestRow extends StatelessWidget {
  const _JoinRequestRow({
    required this.request,
    required this.tokens,
    required this.onRespond,
  });

  final ClubJoinRequestWire request;
  final KubbTokens tokens;
  final ValueChanged<bool> onRespond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              request.displayName ?? 'Spieler',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ablehnen',
            icon: const Icon(Icons.close, color: KubbTokens.miss),
            onPressed: () => onRespond(false),
          ),
          IconButton(
            tooltip: 'Aufnehmen',
            icon: Icon(Icons.check, color: tokens.primary),
            onPressed: () => onRespond(true),
          ),
        ],
      ),
    );
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'owner':
      return 'Owner (Vereinsleitung)';
    case 'admin':
      return 'Admin';
    case 'member':
      return 'Mitglied';
    case 'referee':
      return 'Schiedsrichter';
    case 'timemaster':
      return 'Timemaster';
    case 'organizer':
      return 'Organisator';
    case 'scorekeeper':
      return 'Anschreiber';
    case 'treasurer':
      return 'Kassier';
    default:
      return role;
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canEdit,
    required this.onEdit,
  });

  final ClubMemberWire member;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        onTap: canEdit ? onEdit : null,
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space3),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName ?? 'Spieler',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final r in member.roles)
                          _RoleChip(label: _roleLabel(r), tokens: tokens),
                      ],
                    ),
                  ],
                ),
              ),
              if (canEdit)
                Icon(Icons.edit_outlined, size: 18, color: tokens.fgMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.tokens});
  final String label;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: tokens.fgMuted),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.tokens});
  final String text;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.88,
          color: tokens.fgMuted,
        ),
      );
}
