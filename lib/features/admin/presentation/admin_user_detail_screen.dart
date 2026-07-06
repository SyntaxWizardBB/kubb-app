import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/admin/application/admin_providers.dart';
import 'package:kubb_app/features/admin/data/admin_models.dart';
import 'package:kubb_app/features/auth/application/impersonation_controller.dart';

/// Per-user admin actions (M1). Receives the row from the list via `extra`;
/// mutates through the caller-gated `admin_*` RPCs and reflects the result
/// locally + invalidates the list. Impersonation switches the whole session
/// and returns Home (the banner then drives the exit).
class AdminUserDetailScreen extends ConsumerStatefulWidget {
  const AdminUserDetailScreen({required this.row, super.key});

  final AdminUserRow row;

  @override
  ConsumerState<AdminUserDetailScreen> createState() =>
      _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState
    extends ConsumerState<AdminUserDetailScreen> {
  late AdminUserRow _row = widget.row;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(adminUserListProvider);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final repo = ref.read(adminRepositoryProvider);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: 'Nutzer',
        title: _row.nickname.isEmpty ? '(kein Name)' : _row.nickname,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(KubbTokens.space4),
          children: [
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: KubbTokens.space2),
            _sectionLabel('Rechte'),
            SwitchListTile(
              value: _row.canFoundClubs,
              title: const Text('Veranstalter (kann Turniere & Vereine anlegen)'),
              onChanged: (v) => _run(() async {
                await repo.setCapability(
                    userId: _row.userId, capability: 'can_found_clubs', value: v);
                setState(() => _row = _row.copyWith(canFoundClubs: v));
              }),
            ),
            SwitchListTile(
              value: _row.isAdmin,
              title: const Text('Admin (volle Verwaltung)'),
              onChanged: (v) => _run(() async {
                await repo.setCapability(
                    userId: _row.userId, capability: 'is_admin', value: v);
                setState(() => _row = _row.copyWith(isAdmin: v));
              }),
            ),
            const Divider(height: KubbTokens.space6),
            _sectionLabel('Aktionen'),
            ListTile(
              leading: Icon(_row.isSuspended ? Icons.lock_open : Icons.block,
                  color: KubbTokens.miss),
              title: Text(_row.isSuspended ? 'Entsperren' : 'Konto sperren'),
              subtitle: Text(_row.isSuspended
                  ? 'Gesperrt — Login blockiert'
                  : 'Blockiert jeden Login'),
              onTap: () => _run(() async {
                final suspend = !_row.isSuspended;
                await repo.setAccountStatus(
                    userId: _row.userId, suspended: suspend);
                setState(() => _row = _row.copyWith(
                    suspendedAt: suspend ? DateTime.now() : null,
                    clearSuspended: !suspend));
              }),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Nachricht senden'),
              onTap: _promptInbox,
            ),
            ListTile(
              leading: const Icon(Icons.supervised_user_circle),
              title: const Text('Als dieser Nutzer agieren'),
              subtitle: _row.isAdmin
                  ? const Text('Admins können nicht übernommen werden')
                  : null,
              enabled: !_row.isAdmin,
              onTap: _row.isAdmin ? null : _impersonate,
            ),
            const Divider(height: KubbTokens.space6),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: KubbTokens.miss),
              title: const Text('Konto löschen',
                  style: TextStyle(color: KubbTokens.miss)),
              subtitle: const Text('Unwiderruflich — löscht alle Daten'),
              onTap: _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: tokens.fgMuted)),
    );
  }

  Future<void> _impersonate() async {
    final router = GoRouter.of(context);
    await _run(() async {
      await ref.read(impersonationProvider.notifier).start(_row.userId);
    });
    // After the session switches, leave the (now inaccessible) admin area.
    if (mounted && ref.read(impersonationProvider) != null) {
      router.go('/');
    }
  }

  Future<void> _confirmDelete() async {
    final router = GoRouter.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konto löschen?'),
        content: Text(
            '„${_row.nickname}" und alle zugehörigen Daten werden '
            'unwiderruflich gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: KubbTokens.miss),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(adminRepositoryProvider).deleteAccount(userId: _row.userId);
    });
    if (mounted) router.pop();
  }

  Future<void> _promptInbox() async {
    final messenger = ScaffoldMessenger.of(context);
    final subjectController = TextEditingController();
    final bodyController = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nachricht senden'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(labelText: 'Betreff'),
            ),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(labelText: 'Nachricht'),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Senden')),
        ],
      ),
    );
    if (sent != true) {
      subjectController.dispose();
      bodyController.dispose();
      return;
    }
    await _run(() async {
      await ref.read(adminRepositoryProvider).sendInbox(
            userId: _row.userId,
            subject: subjectController.text.trim(),
            body: bodyController.text.trim(),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Nachricht gesendet')));
    });
    subjectController.dispose();
    bodyController.dispose();
  }
}
