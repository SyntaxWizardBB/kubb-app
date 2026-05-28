import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:kubb_app/features/social/data/group_models.dart';
import 'package:kubb_app/features/social/data/group_repository.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Phase-1 groups screen (ADR-0012). Lists the caller's owned + joined
/// groups. FAB opens a "name" prompt to create one. Tap on a row opens
/// the member sheet.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final groups = ref.watch(groupsListProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => GoRouter.of(context).pop()),
        title: const Text('Gruppen'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Neue Gruppe'),
      ),
      body: groups.when(
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(KubbTokens.space5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.groups_outlined, size: 36,
                        color: tokens.fgMuted),
                    const SizedBox(height: KubbTokens.space3),
                    Text(
                      'Noch keine Gruppen.\nLeg eine an für deinen Verein '
                      'oder deine Stamm-Mitspieler.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: tokens.fgMuted),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(groupsListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                KubbTokens.space4,
                KubbTokens.space2,
                KubbTokens.space4,
                96, // FAB clearance
              ),
              itemCount: entries.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: KubbTokens.space2),
              itemBuilder: (context, i) => _GroupTile(entry: entries[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Fehler: $e',
              style: const TextStyle(color: KubbTokens.miss)),
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neue Gruppe'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(
            hintText: 'z.B. Kubb-Verein Bern',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;
    try {
      await ref.read(socialActionsProvider).createGroup(name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gruppe „$name" angelegt')),
      );
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

class _GroupTile extends ConsumerWidget {
  const _GroupTile({required this.entry});

  final GroupListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        onTap: () => _GroupDetailSheet.show(context, entry),
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space3),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KubbTokens.wood300,
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.groups_outlined, color: Colors.white),
              ),
              const SizedBox(width: KubbTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: tokens.fg,
                            ),
                          ),
                        ),
                        if (entry.isOwner)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: KubbTokens.space2,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: KubbTokens.meadow100,
                              borderRadius: BorderRadius.circular(
                                KubbTokens.radiusPill,
                              ),
                            ),
                            child: const Text(
                              'Eigentümer',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: KubbTokens.meadow800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.memberCount} '
                      '${entry.memberCount == 1 ? 'Mitglied' : 'Mitglieder'}',
                      style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: tokens.fgMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet showing the members of a group plus owner-only actions
/// (add friend, remove member, rename, delete).
class _GroupDetailSheet extends ConsumerWidget {
  const _GroupDetailSheet({required this.entry});

  final GroupListEntry entry;

  static Future<void> show(BuildContext context, GroupListEntry entry) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).extension<KubbTokens>()!.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            expand: false,
            builder: (_, scrollCtl) => _GroupDetailSheet(entry: entry),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final membersAsync = ref.watch(groupMembersProvider(entry.groupId));
    final actions = ref.read(socialActionsProvider);
    final callerId = ref.watch(currentUserIdProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space3,
          KubbTokens.space4,
          KubbTokens.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: tokens.fg,
                    ),
                  ),
                ),
                if (entry.isOwner)
                  PopupMenuButton<String>(
                    onSelected: (action) async {
                      switch (action) {
                        case 'rename':
                          await _promptRename(context, ref, entry);
                        case 'delete':
                          await _confirmDelete(context, ref, entry);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Umbenennen'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Löschen'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: KubbTokens.space3),
            Expanded(
              child: membersAsync.when(
                data: (members) => ListView.separated(
                  itemCount: members.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: KubbTokens.space2),
                  itemBuilder: (context, i) {
                    final m = members[i];
                    final canRemove =
                        entry.isOwner && !m.isOwner && m.userId != callerId;
                    return _MemberRow(
                      member: m,
                      onRemove: canRemove
                          ? () async {
                              await actions.removeMember(
                                entry.groupId,
                                m.userId,
                              );
                            }
                          : null,
                    );
                  },
                ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Fehler: $e',
                      style: const TextStyle(color: KubbTokens.miss)),
                ),
              ),
            ),
            if (entry.isOwner) ...[
              const SizedBox(height: KubbTokens.space2),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      _showAddFriendPicker(context, ref, entry),
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('Freund hinzufügen'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onRemove});

  final GroupMember member;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial =
        member.nickname.isEmpty ? '?' : member.nickname[0].toUpperCase();
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
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: KubbTokens.meadow600,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Text(
              member.nickname,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
              ),
            ),
          ),
          if (member.isOwner)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Eigentümer',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: KubbTokens.meadow800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(LucideIcons.x, size: 18),
              tooltip: 'Entfernen',
            ),
        ],
      ),
    );
  }
}

Future<void> _promptRename(
  BuildContext context,
  WidgetRef ref,
  GroupListEntry entry,
) async {
  final controller = TextEditingController(text: entry.name);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Gruppe umbenennen'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 50,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty || name == entry.name) return;
  if (!context.mounted) return;
  await ref.read(socialActionsProvider).renameGroup(entry.groupId, name);
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  GroupListEntry entry,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Gruppe löschen?'),
      content: Text(
        'Die Gruppe „${entry.name}" wird unwiderruflich gelöscht. '
        'Alle Mitglieder verlieren den Zugriff.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: KubbTokens.miss),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Löschen'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  if (!context.mounted) return;
  await ref.read(socialActionsProvider).deleteGroup(entry.groupId);
  if (!context.mounted) return;
  Navigator.of(context).pop(); // close the detail sheet
}

Future<void> _showAddFriendPicker(
  BuildContext context,
  WidgetRef ref,
  GroupListEntry entry,
) async {
  final friends = ref.read(acceptedFriendsProvider);
  if (friends.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Du hast noch keine Freunde, die du hinzufügen kannst.'),
      ),
    );
    return;
  }
  final members = await ref
      .read(groupRepositoryProvider)
      .membersFor(entry.groupId);
  final memberIds = members.map((m) => m.userId).toSet();
  final addable =
      friends.where((f) => !memberIds.contains(f.userId)).toList();
  if (addable.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Alle deine Freunde sind schon in der Gruppe.'),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  final picked = await showModalBottomSheet<FriendEntry>(
    context: context,
    builder: (ctx) {
      final tokens = Theme.of(ctx).extension<KubbTokens>()!;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(KubbTokens.space4),
              child: Text(
                'Freund hinzufügen',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                ),
              ),
            ),
            ...addable.map(
              (f) => ListTile(
                leading: const CircleAvatar(
                  backgroundColor: KubbTokens.meadow600,
                  child: Icon(LucideIcons.user, color: Colors.white, size: 18),
                ),
                title: Text(f.nickname),
                onTap: () => Navigator.of(ctx).pop(f),
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
          ],
        ),
      );
    },
  );
  if (picked == null) return;
  if (!context.mounted) return;
  await ref
      .read(socialActionsProvider)
      .inviteMember(entry.groupId, picked.userId);
}
