import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/presentation/disclaimer_block.dart';
import 'package:kubb_app/features/auth/presentation/passphrase_input.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Three-step wizard per design brief #2 (M5-T03 + T06 + T07).
class AnonymousSignupFlow extends ConsumerStatefulWidget {
  const AnonymousSignupFlow({super.key});

  @override
  ConsumerState<AnonymousSignupFlow> createState() =>
      _AnonymousSignupFlowState();
}

class _AnonymousSignupFlowState extends ConsumerState<AnonymousSignupFlow> {
  _Step _step = _Step.nickname;
  String _nickname = '';
  String _passphrase = '';
  bool _ack = false;
  bool _submitting = false;
  String? _error;

  void _toStep2(String nickname) {
    setState(() {
      _nickname = nickname;
      _step = _Step.disclaimer;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    await ref.read(accountSetupControllerProvider.notifier).submit(
          nickname: _nickname,
          passphrase: _passphrase,
        );
    final result = ref.read(accountSetupControllerProvider);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      result.maybeWhen(
        done: (_) => _step = _Step.success,
        failed: (reason) => _error = reason,
        orElse: () {},
      );
    });
  }

  void _back() {
    setState(() {
      _step = _Step.nickname;
    });
  }

  void _close() {
    GoRouter.of(context).pop();
  }

  void _finish() {
    GoRouter.of(context).go('/onboarding-tour');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final stepIdx = _step.index;
    final title = switch (_step) {
      _Step.nickname => l10n.authSignupNicknameTitle,
      _Step.disclaimer => l10n.authSignupDisclaimerTitle,
      _Step.success => l10n.authSignupSuccessTitle,
    };

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            _WizardHeader(
              step: stepIdx,
              total: 3,
              eyebrow: l10n.authSignupEyebrow,
              title: title,
              onBack: stepIdx > 0 && _step != _Step.success ? _back : null,
              onClose: _step != _Step.success ? _close : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space6,
                ),
                child: switch (_step) {
                  _Step.nickname => _NicknameStep(onContinue: _toStep2),
                  _Step.disclaimer => _DisclaimerStep(
                      passphrase: _passphrase,
                      onPassphraseChanged: (v) =>
                          setState(() => _passphrase = v),
                      ack: _ack,
                      onAckChanged: (v) => setState(() => _ack = v),
                      submitting: _submitting,
                      error: _error,
                      onSubmit: _submit,
                    ),
                  _Step.success => _SuccessStep(onFinish: _finish),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Step { nickname, disclaimer, success }

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.step,
    required this.total,
    required this.eyebrow,
    required this.title,
    this.onBack,
    this.onClose,
  });

  final int step;
  final int total;
  final String eyebrow;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space2,
        KubbTokens.space2,
        KubbTokens.space2,
        KubbTokens.space3,
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: KubbTokens.touchMin,
                height: KubbTokens.touchMin,
                child: onBack != null
                    ? IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: l10n.authCommonBack,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  l10n.authWizardStepCount(step + 1, total),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.fgMuted,
                  ),
                ),
              ),
              SizedBox(
                width: KubbTokens.touchMin,
                height: KubbTokens.touchMin,
                child: onClose != null
                    ? IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                        tooltip: l10n.authCommonClose,
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(
            eyebrow,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
              color: tokens.primary,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: tokens.fg,
              ),
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          _StepDots(current: step, total: total),
        ],
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= current ? tokens.primary : KubbTokens.stone200,
              borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _NicknameStep extends StatefulWidget {
  const _NicknameStep({required this.onContinue});

  final ValueChanged<String> onContinue;

  @override
  State<_NicknameStep> createState() => _NicknameStepState();
}

class _NicknameStepState extends State<_NicknameStep> {
  String _nick = '';

  String? _validate(BuildContext context, String v) {
    final l10n = AppLocalizations.of(context);
    if (v.isEmpty) return null;
    if (v.length < 3) return l10n.authSignupNicknameTooShort;
    if (v.length > 30) return l10n.authSignupNicknameTooLong;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(v)) {
      return l10n.authSignupNicknameInvalidChars;
    }
    return null;
  }

  bool _isValid() =>
      _nick.length >= 3 &&
      _nick.length <= 30 &&
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(_nick);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final err = _validate(context, _nick);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: KubbTokens.space3),
        Text(
          l10n.authSignupNicknameLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: tokens.fgMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          autofocus: true,
          maxLength: 30,
          onChanged: (v) => setState(() => _nick = v),
          decoration: InputDecoration(
            hintText: l10n.authSignupNicknamePlaceholder,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              borderSide: BorderSide(
                color: err != null ? KubbTokens.miss : tokens.lineStrong,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (err != null)
          Text(
            err,
            style: const TextStyle(fontSize: 12, color: KubbTokens.miss),
          )
        else
          Text(
            l10n.authSignupNicknameHelper,
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          ),
        const Spacer(),
        _PrimaryButton(
          label: l10n.authCommonContinue,
          onPressed: _isValid() ? () => widget.onContinue(_nick) : null,
        ),
        const SizedBox(height: KubbTokens.space5),
      ],
    );
  }
}

class _DisclaimerStep extends StatelessWidget {
  const _DisclaimerStep({
    required this.passphrase,
    required this.onPassphraseChanged,
    required this.ack,
    required this.onAckChanged,
    required this.submitting,
    required this.error,
    required this.onSubmit,
  });

  final String passphrase;
  final ValueChanged<String> onPassphraseChanged;
  final bool ack;
  final ValueChanged<bool> onAckChanged;
  final bool submitting;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final canSubmit = ack && passphrase.length >= 12 && !submitting;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KubbTokens.space2),
          const DisclaimerBlock(),
          const SizedBox(height: KubbTokens.space3),
          InkWell(
            onTap: () => onAckChanged(!ack),
            borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ack ? tokens.primary : Colors.transparent,
                      border: Border.all(color: tokens.lineStrong, width: 1.5),
                      borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: ack
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: KubbTokens.space3),
                  Expanded(
                    child: Text(
                      l10n.authDisclaimerAcknowledge,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          PassphraseInput(
            value: passphrase,
            onChanged: onPassphraseChanged,
            showStrength: true,
            helper: l10n.authPassphraseHelper,
          ),
          if (error != null) ...[
            const SizedBox(height: KubbTokens.space3),
            Container(
              padding: const EdgeInsets.all(KubbTokens.space3),
              decoration: BoxDecoration(
                color: const Color(0xFFFBE4E0),
                border: Border.all(color: KubbTokens.miss, width: 1.5),
                borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              ),
              child: Text(
                l10n.authSignupErrorBanner,
                style: const TextStyle(
                  fontSize: 13,
                  color: KubbTokens.miss,
                ),
              ),
            ),
          ],
          const SizedBox(height: KubbTokens.space5),
          _PrimaryButton(
            label: submitting
                ? l10n.authSignupSubmitting
                : l10n.authSignupSubmit,
            onPressed: canSubmit ? onSubmit : null,
            loading: submitting,
          ),
          if (submitting) ...[
            const SizedBox(height: KubbTokens.space2),
            Text(
              l10n.authSignupSubmittingHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
          ],
          const SizedBox(height: KubbTokens.space5),
        ],
      ),
    );
  }
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: KubbTokens.meadow500,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.check, color: Colors.white, size: 44),
        ),
        const SizedBox(height: KubbTokens.space3),
        Text(
          l10n.authSignupSuccessTitle,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: tokens.fg,
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
          child: Text(
            l10n.authSignupSuccessReminder,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: tokens.fgMuted,
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: _PrimaryButton(
            label: l10n.authSignupSuccessContinue,
            onPressed: onFinish,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      width: double.infinity,
      height: KubbTokens.touchComfortable,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.onPrimary,
          disabledBackgroundColor: tokens.primary.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.onPrimary,
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
            ],
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
