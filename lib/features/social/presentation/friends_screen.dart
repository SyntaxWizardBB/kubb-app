import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Phase-1 friends surface (ADR-0012). Two stacked sections:
///   1. A search field that hits the username-prefix RPC and renders
///      a candidate list with the right action button per relationship.
///   2. The caller's existing list, with incoming-pending requests at
///      the top (action needed) followed by accepted friends.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim().toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final friendsAsync = ref.watch(friendsListProvider);
    final callerId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => GoRouter.of(context).pop()),
        title: const Text('Freunde'),
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
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Spielername suchen…',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(KubbTokens.radiusMd),
                  borderSide: BorderSide(color: tokens.lineStrong),
                ),
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
            if (_query.length >= 2)
              Expanded(child: _SearchResults(query: _query, callerId: callerId))
            else
              Expanded(
                child: friendsAsync.when(
                  data: (entries) =>
                      _FriendsList(entries: entries, callerId: callerId),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('Fehler: $e',
                        style: const TextStyle(color: KubbTokens.miss)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.callerId});

  final String query;
  final String? callerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final results = ref.watch(friendSearchProvider(query));
    final actions = ref.read(socialActionsProvider);

    return results.when(
      data: (candidates) {
        if (candidates.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(KubbTokens.space5),
              child: Text(
                'Niemand gefunden für „$query".',
                style: TextStyle(fontSize: 14, color: tokens.fgMuted),
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: candidates.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: KubbTokens.space2),
          itemBuilder: (context, i) => _CandidateTile(
            candidate: candidates[i],
            onSendRequest: () => _runAction(
              context,
              () => actions.sendFriendRequest(candidates[i].userId),
              successMessage: 'Anfrage gesendet',
            ),
            onAccept: () => _runAction(
              context,
              () => actions.acceptFriendRequest(candidates[i].userId),
              successMessage: 'Anfrage angenommen',
            ),
            onRemove: () => _runAction(
              context,
              () => actions.removeFriend(candidates[i].userId),
              successMessage: 'Entfernt',
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Fehler: $e',
            style: const TextStyle(color: KubbTokens.miss)),
      ),
    );
  }
}

class _FriendsList extends ConsumerWidget {
  const _FriendsList({required this.entries, required this.callerId});

  final List<FriendEntry> entries;
  final String? callerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.userPlus, size: 36, color: tokens.fgMuted),
              const SizedBox(height: KubbTokens.space3),
              Text(
                'Noch keine Freunde.\nSuche oben nach einem Spielernamen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: tokens.fgMuted),
              ),
            ],
          ),
        ),
      );
    }
    final actions = ref.read(socialActionsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(friendsListProvider),
      child: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: KubbTokens.space2),
        itemBuilder: (context, i) => _FriendTile(
          entry: entries[i],
          callerId: callerId,
          onAccept: () => _runAction(
            context,
            () => actions.acceptFriendRequest(entries[i].userId),
            successMessage: 'Anfrage angenommen',
          ),
          onReject: () => _runAction(
            context,
            () => actions.rejectFriendRequest(entries[i].userId),
            successMessage: 'Anfrage abgelehnt',
          ),
          onRemove: () => _runAction(
            context,
            () => actions.removeFriend(entries[i].userId),
            successMessage: 'Freund entfernt',
          ),
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.onSendRequest,
    required this.onAccept,
    required this.onRemove,
  });

  final FriendCandidate candidate;
  final VoidCallback onSendRequest;
  final VoidCallback onAccept;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final Widget trailing;
    switch (candidate.relationship) {
      case FriendRelationship.none:
        trailing = FilledButton.icon(
          onPressed: onSendRequest,
          icon: const Icon(LucideIcons.userPlus, size: 16),
          label: const Text('Hinzufügen'),
        );
      case FriendRelationship.pendingOutgoing:
        trailing = Text(
          'Angefragt',
          style: TextStyle(fontSize: 12, color: tokens.fgMuted),
        );
      case FriendRelationship.pendingIncoming:
        trailing = FilledButton(
          onPressed: onAccept,
          child: const Text('Annehmen'),
        );
      case FriendRelationship.accepted:
        trailing = TextButton.icon(
          onPressed: onRemove,
          icon: const Icon(LucideIcons.userMinus, size: 16),
          label: const Text('Entfernen'),
        );
    }
    return _UserTile(
      nickname: candidate.nickname,
      subtitle: _relationshipLabel(candidate.relationship),
      trailing: trailing,
    );
  }

  String _relationshipLabel(FriendRelationship r) {
    switch (r) {
      case FriendRelationship.none:
        return 'Spieler';
      case FriendRelationship.pendingOutgoing:
        return 'Anfrage gesendet';
      case FriendRelationship.pendingIncoming:
        return 'Wartet auf deine Antwort';
      case FriendRelationship.accepted:
        return 'Bereits Freund';
    }
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({
    required this.entry,
    required this.callerId,
    required this.onAccept,
    required this.onReject,
    required this.onRemove,
  });

  final FriendEntry entry;
  final String? callerId;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final isIncomingPending =
        entry.isPending && entry.requestedBy != callerId;
    final isOutgoingPending =
        entry.isPending && entry.requestedBy == callerId;

    final Widget trailing;
    final String subtitle;
    if (isIncomingPending) {
      subtitle = 'Möchte dich als Freund hinzufügen';
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onReject,
            icon: const Icon(LucideIcons.x, size: 18),
            tooltip: 'Ablehnen',
          ),
          FilledButton(
            onPressed: onAccept,
            child: const Text('Annehmen'),
          ),
        ],
      );
    } else if (isOutgoingPending) {
      subtitle = 'Anfrage gesendet';
      trailing = Text(
        'wartet…',
        style: TextStyle(fontSize: 12, color: tokens.fgMuted),
      );
    } else {
      subtitle = 'Freund';
      trailing = IconButton(
        onPressed: onRemove,
        icon: const Icon(LucideIcons.userMinus, size: 18),
        tooltip: 'Entfernen',
      );
    }

    return _UserTile(
      nickname: entry.nickname,
      subtitle: subtitle,
      trailing: trailing,
      highlight: isIncomingPending,
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.nickname,
    required this.subtitle,
    required this.trailing,
    this.highlight = false,
  });

  final String nickname;
  final String subtitle;
  final Widget trailing;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial = nickname.isEmpty ? '?' : nickname[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFBF2D6) : tokens.bgRaised,
        border: Border.all(
          color: highlight ? const Color(0xFFD4AE3B) : tokens.line,
          width: highlight ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: KubbTokens.meadow600,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

Future<void> _runAction(
  BuildContext context,
  Future<void> Function() action, {
  required String successMessage,
}) async {
  try {
    await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successMessage)),
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
