import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';

/// Minimal inbox screen: lists the user's non-archived messages,
/// renders each as a tappable tile that opens a body view, and lets
/// `verification_request` messages be answered with confirm / deny.
///
/// This is the v1 surface for ADR-0011's in-app inbox. It is enough
/// to verify that admin → user delivery works end-to-end. UX polish
/// (filter by kind, search, archive toolbar, push channel) lands in
/// follow-ups.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(inboxMessagesProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(onPressed: () => GoRouter.of(context).pop()),
        title: const Text('Postfach'),
      ),
      body: async.when(
        data: (msgs) {
          if (msgs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(KubbTokens.space5),
                child: Text(
                  'Keine Nachrichten.',
                  style: TextStyle(fontSize: 14, color: tokens.fgMuted),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(inboxMessagesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(KubbTokens.space4),
              itemCount: msgs.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: KubbTokens.space2),
              itemBuilder: (context, i) => _MessageTile(message: msgs[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              'Postfach konnte nicht geladen werden:\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: KubbTokens.miss),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageTile extends ConsumerWidget {
  const _MessageTile({required this.message});

  final InboxMessage message;

  Color _kindBg(InboxMessageKind kind) {
    switch (kind) {
      case InboxMessageKind.notice:
        return KubbTokens.meadow100;
      case InboxMessageKind.verificationRequest:
        return const Color(0xFFFBF2D6);
      case InboxMessageKind.system:
        return const Color(0xFFE8EEF5);
    }
  }

  String _kindLabel(InboxMessageKind kind) {
    switch (kind) {
      case InboxMessageKind.notice:
        return 'Hinweis';
      case InboxMessageKind.verificationRequest:
        return 'Bestätigung';
      case InboxMessageKind.system:
        return 'System';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final actions = ref.read(inboxActionsProvider);

    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      child: InkWell(
        onTap: () async {
          if (message.isUnread) {
            await actions.markRead(message.id);
          }
          if (!context.mounted) return;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _MessageDetail(message: message),
          );
        },
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: KubbTokens.space2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: message.isUnread
                      ? KubbTokens.meadow600
                      : Colors.transparent,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: KubbTokens.space2,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kindBg(message.kind),
                            borderRadius: BorderRadius.circular(
                              KubbTokens.radiusPill,
                            ),
                          ),
                          child: Text(
                            _kindLabel(message.kind),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3D2C00),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _shortTimestamp(message.sentAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.fgMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            message.isUnread ? FontWeight.w800 : FontWeight.w600,
                        color: tokens.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: tokens.fgMuted,
                      ),
                    ),
                    if (message.awaitsReply) ...[
                      const SizedBox(height: KubbTokens.space2),
                      const Text(
                        '→ Antwort erforderlich',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9A6B00),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortTimestamp(DateTime ts) {
    final local = ts.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    return '${local.day}.${local.month}.';
  }
}

class _MessageDetail extends ConsumerWidget {
  const _MessageDetail({required this.message});

  final InboxMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final actions = ref.read(inboxActionsProvider);
    final actionKind = message.actionPayload?['kind'] as String?;
    final matchId = message.actionPayload?['match_id'] as String?;
    final friendUserId = message.actionPayload?['from_user_id'] as String?;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(KubbTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.subject,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
            Text(
              message.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: tokens.fg,
              ),
            ),
            // -- Friend-request action payload --------------------------
            if (actionKind == 'friend_request' && friendUserId != null) ...[
              const SizedBox(height: KubbTokens.space5),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _handleFriendRequest(
                        context,
                        ref,
                        otherUserId: friendUserId,
                        accept: true,
                      ),
                      child: const Text('Annehmen'),
                    ),
                  ),
                  const SizedBox(width: KubbTokens.space3),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleFriendRequest(
                        context,
                        ref,
                        otherUserId: friendUserId,
                        accept: false,
                      ),
                      child: const Text('Ablehnen'),
                    ),
                  ),
                ],
              ),
            ] else
            // -- Match-specific action payloads --------------------------
            if (actionKind == 'match_invite' && matchId != null) ...[
              const SizedBox(height: KubbTokens.space5),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _handleMatchInvite(
                        context,
                        ref,
                        matchId: matchId,
                        accept: true,
                      ),
                      child: const Text('Annehmen'),
                    ),
                  ),
                  const SizedBox(width: KubbTokens.space3),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleMatchInvite(
                        context,
                        ref,
                        matchId: matchId,
                        accept: false,
                      ),
                      child: const Text('Ablehnen'),
                    ),
                  ),
                ],
              ),
            ] else if (actionKind == 'match_round_prompt' &&
                matchId != null) ...[
              const SizedBox(height: KubbTokens.space5),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _handleRoundPrompt(
                    context,
                    ref,
                    messageId: message.id,
                    matchId: matchId,
                  ),
                  child: const Text('Resultat eintragen'),
                ),
              ),
            ] else if (message.awaitsReply) ...[
              // -- Generic confirm / deny fallback ---------------------
              const SizedBox(height: KubbTokens.space5),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await actions.reply(message.id, {'answer': 'confirm'});
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      },
                      child: const Text('Bestätigen'),
                    ),
                  ),
                  const SizedBox(width: KubbTokens.space3),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await actions.reply(message.id, {'answer': 'deny'});
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      },
                      child: const Text('Ablehnen'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: KubbTokens.space3),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await actions.archive(message.id);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.archive_outlined, size: 16),
                label: const Text('Archivieren'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMatchInvite(
    BuildContext context,
    WidgetRef ref, {
    required String matchId,
    required bool accept,
  }) async {
    final inboxActions = ref.read(inboxActionsProvider);
    final matchActions = ref.read(matchActionsProvider);
    try {
      if (accept) {
        await matchActions.acceptInvite(matchId);
      } else {
        await matchActions.declineInvite(matchId);
      }
      await inboxActions.reply(
        message.id,
        {'answer': accept ? 'accept' : 'decline'},
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (accept) {
        // Skip the lobby — the lobby would auto-redirect onward as
        // soon as our acceptance flips the match to `active`. Going
        // straight to the result screen lets both sides land on the
        // same surface where the score is entered.
        context.go('${MatchRoutes.result}/$matchId');
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

  Future<void> _handleFriendRequest(
    BuildContext context,
    WidgetRef ref, {
    required String otherUserId,
    required bool accept,
  }) async {
    final inboxActions = ref.read(inboxActionsProvider);
    final socialActions = ref.read(socialActionsProvider);
    try {
      if (accept) {
        await socialActions.acceptFriendRequest(otherUserId);
      } else {
        await socialActions.rejectFriendRequest(otherUserId);
      }
      // Mark the inbox message as resolved so it stops looking pending
      // in the user's inbox.
      await inboxActions.reply(
        message.id,
        {'answer': accept ? 'accept' : 'decline'},
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'Freundschaftsanfrage angenommen' : 'Anfrage abgelehnt',
          ),
        ),
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

  Future<void> _handleRoundPrompt(
    BuildContext context,
    WidgetRef ref, {
    required String messageId,
    required String matchId,
  }) async {
    final inboxActions = ref.read(inboxActionsProvider);
    try {
      await inboxActions.markRead(messageId);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      context.go('${MatchRoutes.result}/$matchId');
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
