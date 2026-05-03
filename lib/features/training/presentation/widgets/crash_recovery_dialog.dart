import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class CrashRecoveryDialog extends ConsumerWidget {
  const CrashRecoveryDialog({required this.session, super.key});

  final Session session;

  static Future<void> show(BuildContext context, Session session) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CrashRecoveryDialog(session: session),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final dateText = DateFormat.yMd('de').add_Hm().format(session.startedAt);

    return AlertDialog(
      title: Text(l.crashRecoveryTitle),
      content: Text(l.crashRecoveryContent(dateText)),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: tokens.danger),
          onPressed: () => _discard(context, ref),
          child: Text(l.crashRecoveryDiscard),
        ),
        TextButton(
          onPressed: () => _save(context, ref),
          child: Text(l.crashRecoverySave),
        ),
        FilledButton(
          onPressed: () => _resume(context, ref),
          child: Text(l.crashRecoveryResume),
        ),
      ],
    );
  }

  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    await ref.read(activeSessionProvider.notifier).resumeFromCrash(session.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    context.go('/training/sniper/session/${session.id}');
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    await ref.read(trainingRepositoryProvider).markCompleted(sessionId: session.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    context.go('/training/summary/${session.id}');
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    await ref.read(trainingRepositoryProvider).discard(sessionId: session.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }
}
