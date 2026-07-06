import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// M3: set/change the login password for an EXISTING account (e.g. a
/// keypair account created before M3). Sets the synthetic email + password
/// on the current session, so afterwards the user can log in with
/// nickname + password. The passphrase recovery is unaffected.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _valid => _pw.text.length >= 8 && _pw.text == _confirm.text && !_busy;

  Future<void> _submit() async {
    final userId = ref.read(currentUserIdProvider);
    final nickname = ref.read(displayProfileProvider)?.displayName ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    if (userId == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Keine aktive Sitzung.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(supabaseAuthAdapterProvider).setEmailPassword(
            email: '$userId@login.kubbclub.ch',
            password: _pw.text,
            nickname: nickname,
          );
      await Supabase.instance.client.rpc<void>('password_credential_mark');
      messenger.showSnackBar(const SnackBar(content: Text('Passwort gesetzt.')));
      if (mounted) router.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final mismatch = _confirm.text.isNotEmpty && _pw.text != _confirm.text;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(eyebrow: 'Konto', title: 'Passwort setzen'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Setze ein Passwort, um dich künftig mit Spielername + '
                'Passwort anzumelden. Deine Wiederherstellungs-Phrase bleibt '
                'zusätzlich gültig.',
                style: TextStyle(color: tokens.fgMuted),
              ),
              const SizedBox(height: KubbTokens.space4),
              TextField(
                controller: _pw,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Neues Passwort',
                  helperText: 'Mindestens 8 Zeichen',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: KubbTokens.space3),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'Passwort wiederholen'),
              ),
              if (mismatch)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 2),
                  child: Text('Die Passwörter stimmen nicht überein.',
                      style: TextStyle(fontSize: 12, color: KubbTokens.miss)),
                ),
              const SizedBox(height: KubbTokens.space5),
              FilledButton(
                onPressed: _valid ? () => unawaited(_submit()) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: KubbTokens.meadow500,
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Passwort speichern'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
