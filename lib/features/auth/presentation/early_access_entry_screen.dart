import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_primary_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

/// First gate after the splash (P7): a valid early-access code (XXXX-XXXX) is
/// required before a profile can be created — app use without login is not
/// possible. Returning users restore their existing keypair without a code.
class EarlyAccessEntryScreen extends ConsumerStatefulWidget {
  const EarlyAccessEntryScreen({super.key});

  @override
  ConsumerState<EarlyAccessEntryScreen> createState() =>
      _EarlyAccessEntryScreenState();
}

class _EarlyAccessEntryScreenState
    extends ConsumerState<EarlyAccessEntryScreen> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  bool get _complete => _codeCtrl.text.length == 9; // XXXX-XXXX

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final kind = await Supabase.instance.client.rpc<String?>(
        'validate_early_access_code',
        params: <String, dynamic>{'p_code': _codeCtrl.text.trim()},
      );
      if (!mounted) return;
      if (kind == null) {
        setState(() {
          _busy = false;
          _error = 'Ungültiger Code.';
        });
        return;
      }
      setState(() => _busy = false);
      // Code is valid — hand off to the sign-in choice (OAuth or Gast). The
      // validated code rides along so the Gast path can found a club without a
      // second prompt; keypair_register re-validates it server-side.
      await GoRouter.of(context)
          .push<void>(AuthRoutes.signIn, extra: _codeCtrl.text.trim());
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Prüfung fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Scaffold(
      backgroundColor: tokens.bg,
      // resizeToAvoidBottomInset (default true) + the scroll view below keep
      // the form clear of the keyboard with no overflow.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(KubbTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: KubbTokens.space8),
              Text(
                'Early Access',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: tokens.fg,
                ),
              ),
              const SizedBox(height: KubbTokens.space2),
              Text(
                'Gib deinen Zugangscode ein, um ein Profil anzulegen. '
                'Der Code hat das Format XXXX-XXXX.',
                style: TextStyle(fontSize: 15, height: 1.5, color: tokens.fgMuted),
              ),
              const SizedBox(height: KubbTokens.space6),
              TextField(
                controller: _codeCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                inputFormatters: [_CodeFormatter()],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  hintText: 'XXXX-XXXX',
                  errorText: _error,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                    borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: KubbTokens.space5),
              AuthPrimaryButton(
                label: 'Weiter',
                loading: _busy,
                onPressed: _complete && !_busy ? _continue : null,
              ),
              const SizedBox(height: KubbTokens.space4),
              Center(
                child: TextButton(
                  onPressed: () =>
                      GoRouter.of(context).push<void>(AuthRoutes.restore),
                  child: const Text('Konto wiederherstellen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Masks input to XXXX-XXXX: up to 8 alphanumerics, uppercased, dash after 4.
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw =
        newValue.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final trimmed = raw.length > 8 ? raw.substring(0, 8) : raw;
    final buffer = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      if (i == 4) buffer.write('-');
      buffer.write(trimmed[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
