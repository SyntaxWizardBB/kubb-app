import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/training/application/cloud_training_provider.dart';
import 'package:kubb_app/features/training/data/cloud_training_repository.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Management view for the user's own online-saved training sessions (P2:
/// "online gespeichert … und man soll die auch löschen können").
///
/// Lists the cloud aggregates and lets the owner delete any of them. Deleting
/// removes only the online copy (the one friends can see); the local drift
/// history is untouched.
class MyTrainingSessionsScreen extends ConsumerWidget {
  const MyTrainingSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(myTrainingSessionsProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(
        title: 'Meine Online-Sessions',
        actions: [InboxBellAction()],
      ),
      body: async.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: KubbTokens.space4),
              child: KubbEmptyState(
                title: 'Keine Online-Sessions',
                body: 'Abgeschlossene Trainings werden online gespeichert und '
                    'erscheinen hier. Freunde können deine Statistik daraus '
                    'sehen — hier kannst du Sessions wieder löschen.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myTrainingSessionsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(KubbTokens.space4),
              itemCount: sessions.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: KubbTokens.space2),
              itemBuilder: (context, i) => _SessionRow(session: sessions[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              'Sessions konnten nicht geladen werden:\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: KubbTokens.miss),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.session});

  final CloudTrainingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final String tag;
    final String detail;
    if (session.isFinisseur) {
      tag = 'Finisseur';
      detail = (session.win ?? false) ? 'Gewonnen' : 'Verloren';
    } else {
      tag = 'Sniper';
      final dist = session.distanceM == null
          ? ''
          : '${session.distanceM!.toStringAsFixed(1)} m · ';
      detail = '$dist${session.hitRate ?? 0}% · ${session.throws ?? 0} Würfe';
    }
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                Text(
                  '$detail · ${_relativeTime(session.completedAt)}',
                  style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Löschen',
            icon: const Icon(LucideIcons.trash2, size: 18),
            color: KubbTokens.miss,
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session löschen?'),
        content: const Text(
          'Diese Online-Session wird gelöscht und ist danach auch für Freunde '
          'nicht mehr sichtbar.',
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
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(cloudTrainingRepositoryProvider).delete(session.id);
      ref.invalidate(myTrainingSessionsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session gelöscht')),
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

String _relativeTime(DateTime utc) {
  final now = DateTime.now().toUtc();
  final diff = now.difference(utc);
  if (diff.inMinutes < 1) return 'gerade eben';
  if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min';
  if (diff.inHours < 24) return 'vor ${diff.inHours} Std';
  if (diff.inDays == 1) return 'gestern';
  if (diff.inDays < 7) return 'vor ${diff.inDays} Tagen';
  if (diff.inDays < 30) return 'vor ${(diff.inDays / 7).floor()} Wochen';
  return 'vor ${(diff.inDays / 30).floor()} Monaten';
}
