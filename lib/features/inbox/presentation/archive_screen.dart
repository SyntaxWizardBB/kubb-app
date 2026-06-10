import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';

/// Read-only view of the user's archived messages, reached from the drawer.
///
/// Archived messages are not part of the active inbox or the local cache —
/// they are fetched straight from the server. A single destructive action
/// permanently deletes them: server-side via `inbox_purge_archived` (only
/// `archived_at` rows; still-needed records like tournament registrations
/// live in other tables and are untouched), and there is nothing to remove
/// locally because the drift mirror never caches archived rows.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(archivedInboxProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(title: 'Archiv'),
      body: async.when(
        data: (msgs) {
          if (msgs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: KubbTokens.space4),
              child: KubbEmptyState(
                title: 'Kein Archiv',
                body: 'Archivierte Nachrichten erscheinen hier. Du kannst sie '
                    'später endgültig löschen.',
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(archivedInboxProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(KubbTokens.space4),
                    itemCount: msgs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: KubbTokens.space2),
                    itemBuilder: (context, i) =>
                        _ArchivedTile(message: msgs[i]),
                  ),
                ),
              ),
              _PurgeBar(count: msgs.length),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              'Archiv konnte nicht geladen werden:\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: KubbTokens.miss),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchivedTile extends StatelessWidget {
  const _ArchivedTile({required this.message});

  final InboxMessage message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _kindLabel(message.kind),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: tokens.fgMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.subject,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
            ),
          ),
          if (message.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              message.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: tokens.fgMuted),
            ),
          ],
        ],
      ),
    );
  }

  String _kindLabel(InboxMessageKind kind) {
    switch (kind) {
      case InboxMessageKind.notice:
        return 'HINWEIS';
      case InboxMessageKind.verificationRequest:
        return 'BESTÄTIGUNG';
      case InboxMessageKind.system:
        return 'SYSTEM';
      case InboxMessageKind.teamInvitation:
        return 'TEAM-EINLADUNG';
      case InboxMessageKind.teamMemberRemoved:
        return 'TEAM-ÄNDERUNG';
      case InboxMessageKind.teamDissolved:
        return 'TEAM AUFGELÖST';
      case InboxMessageKind.clubInvitation:
        return 'VEREINS-EINLADUNG';
      case InboxMessageKind.clubMemberRemoved:
        return 'VEREINS-ÄNDERUNG';
      case InboxMessageKind.clubJoinRequest:
        return 'BEITRITTSANFRAGE';
      case InboxMessageKind.tournamentInvitation:
        return 'TURNIER-EINLADUNG';
      case InboxMessageKind.tournamentShootout:
        return 'SHOOT-OUT';
      case InboxMessageKind.tournamentFinished:
        return 'TURNIER BEENDET';
    }
  }
}

class _PurgeBar extends ConsumerStatefulWidget {
  const _PurgeBar({required this.count});

  final int count;

  @override
  ConsumerState<_PurgeBar> createState() => _PurgeBarState();
}

class _PurgeBarState extends ConsumerState<_PurgeBar> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space2,
          KubbTokens.space4,
          KubbTokens.space4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Endgültiges Löschen entfernt die archivierten Nachrichten '
              'unwiderruflich. Turnieranmeldungen und andere aktive Daten '
              'bleiben erhalten.',
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
            const SizedBox(height: KubbTokens.space2),
            KubbButton(
              variant: KubbButtonVariant.danger,
              onPressed: _busy ? null : _confirmAndPurge,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Alle ${widget.count} endgültig löschen'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndPurge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archiv endgültig löschen?'),
        content: const Text(
          'Alle archivierten Nachrichten werden unwiderruflich gelöscht. '
          'Turnieranmeldungen und andere noch benötigte Daten bleiben '
          'bestehen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen',
                style: TextStyle(color: KubbTokens.miss)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final deleted =
          await ref.read(inboxActionsProvider).purgeArchived();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$deleted Nachrichten gelöscht')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
