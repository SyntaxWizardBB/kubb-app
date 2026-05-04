import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/passphrase_change_controller.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_app_bar.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_primary_button.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_secondary_button.dart';
import 'package:kubb_app/features/auth/presentation/passphrase_input.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Passphrase change screen per design brief #7 (M5-T10, template
/// `PassphraseChangeScreen.jsx`). Three fields: old, new, confirm.
class PassphraseChangeScreen extends ConsumerStatefulWidget {
  const PassphraseChangeScreen({super.key});

  @override
  ConsumerState<PassphraseChangeScreen> createState() =>
      _PassphraseChangeScreenState();
}

class _PassphraseChangeScreenState
    extends ConsumerState<PassphraseChangeScreen> {
  String _oldPass = '';
  String _newPass = '';
  String _confirm = '';

  void _back() {
    GoRouter.of(context).pop();
  }

  Future<void> _submit() async {
    final nickname = ref.read(authControllerProvider).maybeWhen(
          data: (s) => s.displayName,
          orElse: () => null,
        );
    if (nickname == null) return;
    await ref.read(passphraseChangeControllerProvider.notifier).change(
          nickname: nickname,
          oldPassphrase: _oldPass,
          newPassphrase: _newPass,
        );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(passphraseChangeControllerProvider);

    final saving = state.maybeWhen(
      changing: () => true,
      orElse: () => false,
    );
    final hasError = state.maybeWhen(
      failed: (_) => true,
      orElse: () => false,
    );
    final success = state.maybeWhen(
      done: () => true,
      orElse: () => false,
    );

    final newOk = _newPass.length >= 12;
    final matches = _newPass.isNotEmpty && _newPass == _confirm;
    final oldOk = _oldPass.isNotEmpty;
    final canSubmit = oldOk && newOk && matches && !saving;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
          child: Column(
            children: [
              AuthAppBar(
                eyebrow: l10n.authPassphraseChangeEyebrow,
                title: l10n.authPassphraseChangeTitle,
                onBack: _back,
              ),
              const SizedBox(height: KubbTokens.space4),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PassphraseInput(
                        value: _oldPass,
                        onChanged: (v) => setState(() => _oldPass = v),
                        label: l10n.authPassphraseChangeOldLabel,
                        helper: hasError
                            ? null
                            : l10n.authPassphraseChangeOldHelper,
                        error: hasError
                            ? l10n.authPassphraseChangeError
                            : null,
                        autofocus: true,
                      ),
                      const SizedBox(height: KubbTokens.space4),
                      PassphraseInput(
                        value: _newPass,
                        onChanged: (v) => setState(() => _newPass = v),
                        label: l10n.authPassphraseChangeNewLabel,
                        helper: l10n.authPassphraseChangeNewHelper,
                        showStrength: true,
                      ),
                      const SizedBox(height: KubbTokens.space4),
                      PassphraseInput(
                        value: _confirm,
                        onChanged: (v) => setState(() => _confirm = v),
                        label: l10n.authPassphraseChangeConfirmLabel,
                        helper: _confirm.isNotEmpty && !matches
                            ? null
                            : l10n.authPassphraseChangeConfirmHelper,
                        error: _confirm.isNotEmpty && !matches
                            ? l10n.authPassphraseChangeConfirmMismatch
                            : null,
                      ),
                      if (success) ...[
                        const SizedBox(height: KubbTokens.space4),
                        _SuccessBanner(
                          message: l10n.authPassphraseChangeSuccess,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AuthPrimaryButton(
                label: saving
                    ? l10n.authPassphraseChangeSubmitting
                    : l10n.authPassphraseChangeSubmit,
                onPressed: canSubmit ? _submit : null,
                loading: saving,
              ),
              const SizedBox(height: KubbTokens.space2),
              AuthSecondaryButton(
                label: l10n.authPassphraseChangeCancel,
                onPressed: _back,
              ),
              const SizedBox(height: KubbTokens.space5),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: KubbTokens.meadow100,
        border: Border.all(color: KubbTokens.meadow600, width: 1.5),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 18,
            color: KubbTokens.meadow800,
          ),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: KubbTokens.meadow800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
