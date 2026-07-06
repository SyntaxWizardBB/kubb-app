import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// M3: nickname + password login. Resolves the nickname to its synthetic
/// GoTrue address via `password_login_email_for_nickname`, then signs in.
/// On success the session lands via onAuthStateChange and the router
/// redirects to Home.
class PasswordLoginScreen extends ConsumerStatefulWidget {
  const PasswordLoginScreen({super.key});

  @override
  ConsumerState<PasswordLoginScreen> createState() =>
      _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends ConsumerState<PasswordLoginScreen> {
  final _nick = TextEditingController();
  final _pw = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nick.dispose();
    _pw.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nick.text.trim().length >= 3 && _pw.text.isNotEmpty && !_busy;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = await Supabase.instance.client.rpc<String?>(
        'password_login_email_for_nickname',
        params: <String, dynamic>{'p_nickname': _nick.text.trim()},
      );
      if (email == null) {
        setState(() => _error = 'Kein Konto mit diesem Namen.');
        return;
      }
      await ref.read(supabaseAuthAdapterProvider).signInWithPassword(
            email: email,
            password: _pw.text,
          );
      // Success: onAuthStateChange -> router redirect to Home.
    } on AuthException {
      setState(() => _error = 'Name oder Passwort falsch.');
    } on Object catch (e) {
      setState(() => _error = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(eyebrow: 'Anmelden', title: 'Mit Passwort'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(KubbTokens.space3),
                  decoration: BoxDecoration(
                    color: KubbTokens.miss.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                    border: Border.all(color: KubbTokens.miss),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: KubbTokens.miss)),
                ),
                const SizedBox(height: KubbTokens.space4),
              ],
              TextField(
                controller: _nick,
                autofocus: true,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Spielername'),
              ),
              const SizedBox(height: KubbTokens.space3),
              TextField(
                controller: _pw,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _canSubmit ? unawaited(_submit()) : null,
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: KubbTokens.space5),
              FilledButton(
                onPressed: _canSubmit ? () => unawaited(_submit()) : null,
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
                    : const Text('Anmelden'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
