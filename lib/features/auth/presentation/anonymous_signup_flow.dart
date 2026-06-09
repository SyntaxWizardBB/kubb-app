import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/nickname_availability_provider.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_primary_button.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/wizard_header.dart';
import 'package:kubb_app/features/auth/presentation/disclaimer_block.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Four-step wizard implementing ADR-0011's mnemonic-first signup:
///   1. Nickname entry.
///   2. Mnemonic length choice + display of the freshly generated phrase.
///   3. Acknowledge "I wrote it down" + run keypair_register on the
///      server.
///   4. Success.
///
/// The mnemonic is generated entirely on-device and never sent to the
/// server — the server only ever sees the derived public key. There is
/// no recovery: if the user loses the phrase the account is gone.
class AnonymousSignupFlow extends ConsumerStatefulWidget {
  const AnonymousSignupFlow({required this.earlyAccessCode, super.key});

  /// Validated early-access code carried in from the early-access screen;
  /// re-validated server-side in keypair_register.
  final String earlyAccessCode;

  @override
  ConsumerState<AnonymousSignupFlow> createState() =>
      _AnonymousSignupFlowState();
}

class _AnonymousSignupFlowState extends ConsumerState<AnonymousSignupFlow> {
  _Step _step = _Step.nickname;
  String _nickname = '';
  int _wordCount = 12;
  bool _ack = false;
  bool _submitting = false;
  String? _error;

  void _toMnemonicStep(String nickname) {
    setState(() {
      _nickname = nickname;
    });
    ref.read(accountSetupControllerProvider.notifier).generateMnemonic(
          nickname: nickname,
          wordCount: _wordCount,
        );
    setState(() => _step = _Step.mnemonic);
  }

  void _regenerate() {
    ref.read(accountSetupControllerProvider.notifier).generateMnemonic(
          nickname: _nickname,
          wordCount: _wordCount,
        );
    setState(() => _ack = false);
  }

  void _changeLength(int count) {
    setState(() => _wordCount = count);
    ref.read(accountSetupControllerProvider.notifier).generateMnemonic(
          nickname: _nickname,
          wordCount: count,
        );
    setState(() => _ack = false);
  }

  Future<void> _submit() async {
    final mnemonic =
        ref.read(accountSetupControllerProvider).maybeWhen(
              mnemonicReady: (_, mnemonic, _) => mnemonic,
              orElse: () => '',
            );
    if (mnemonic.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    await ref.read(accountSetupControllerProvider.notifier).submitConfirmed(
          nickname: _nickname,
          mnemonic: mnemonic,
          earlyAccessCode: widget.earlyAccessCode,
        );
    if (!mounted) return;
    final result = ref.read(accountSetupControllerProvider);
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
      switch (_step) {
        case _Step.mnemonic:
          _step = _Step.nickname;
        case _Step.nickname:
        case _Step.success:
          break;
      }
    });
  }

  void _close() {
    GoRouter.of(context).pop();
  }

  void _finish() {
    GoRouter.of(context).go(AuthRoutes.onboardingTour);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final stepIdx = _step.index;
    final title = switch (_step) {
      _Step.nickname => l10n.authSignupNicknameTitle,
      _Step.mnemonic => 'Mnemonic-Phrase',
      _Step.success => l10n.authSignupSuccessTitle,
    };

    final mnemonicState = ref.watch(accountSetupControllerProvider);
    final mnemonic = mnemonicState.maybeWhen(
      mnemonicReady: (_, mnemonic, _) => mnemonic,
      orElse: () => '',
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            WizardHeader(
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
                  _Step.nickname => _NicknameStep(onContinue: _toMnemonicStep),
                  _Step.mnemonic => _MnemonicStep(
                      mnemonic: mnemonic,
                      wordCount: _wordCount,
                      ack: _ack,
                      onAckChanged: (v) => setState(() => _ack = v),
                      onChangeLength: _changeLength,
                      onRegenerate: _regenerate,
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

enum _Step { nickname, mnemonic, success }

class _NicknameStep extends ConsumerStatefulWidget {
  const _NicknameStep({required this.onContinue});

  final ValueChanged<String> onContinue;

  @override
  ConsumerState<_NicknameStep> createState() => _NicknameStepState();
}

class _NicknameStepState extends ConsumerState<_NicknameStep> {
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
    final formatErr = _validate(context, _nick);

    // Live uniqueness check (BUG-2): only runs once the format is valid.
    final availability = formatErr == null && _isValid()
        ? ref.watch(nicknameAvailabilityProvider(_nick.trim()))
        : null;
    final isTaken = availability?.maybeWhen(
          data: (a) => a == NicknameAvailability.taken,
          orElse: () => false,
        ) ??
        false;
    final isChecking = availability?.isLoading ?? false;
    // Show the format error first; if the format is fine but the name is
    // taken, show the taken error. Otherwise no error.
    final err = formatErr ?? (isTaken ? l10n.nicknameTakenError : null);

    final hasName = _nick.trim().isNotEmpty;
    // Scrollable so the on-screen keyboard never overflows the step on short
    // devices (the avatar + field + hints + button can exceed the inset-shrunk
    // viewport). Replaces the former Spacer-pinned layout.
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: KubbTokens.space4),
        Center(
          child: AvatarInitialPreview(
            nickname: _nick,
            label: hasName
                ? _nick
                : l10n.authSignupNicknameAvatarHint,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        Text(
          l10n.authSignupNicknameLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.fgMuted,
            letterSpacing: 1.2,
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
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
              borderSide: BorderSide(color: tokens.lineStrong, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
              borderSide: BorderSide(
                color: err != null ? KubbTokens.miss : tokens.lineStrong,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (err != null)
          Text(
            err,
            style: const TextStyle(
              fontSize: 12,
              color: KubbTokens.miss,
              fontWeight: FontWeight.w600,
            ),
          )
        else if (isChecking)
          Text(
            l10n.nicknameCheckingHint,
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          )
        else
          Text(
            l10n.authSignupNicknameHelper,
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          ),
        const SizedBox(height: KubbTokens.space4),
        const _RecoveryHint(),
        const SizedBox(height: KubbTokens.space8),
        AuthPrimaryButton(
          label: l10n.authCommonContinue,
          // Block "Weiter" while the name is confirmed taken (BUG-2). The
          // in-flight debounce window does not gate the button — the server
          // re-validates in keypair_register regardless.
          onPressed: _isValid() && !isTaken
              ? () => widget.onContinue(_nick)
              : null,
        ),
        const SizedBox(height: KubbTokens.space5),
      ],
      ),
    );
  }
}

/// Live preview disc — gradient ring + meadow circle with the first
/// uppercase character of the nickname, falling back to "?". Mirrors
/// the avatar treatment on ProfileScreen so the cue carries through.
class AvatarInitialPreview extends StatelessWidget {
  const AvatarInitialPreview({
    required this.nickname,
    required this.label,
    super.key,
  });

  final String nickname;
  final String label;

  @override
  Widget build(BuildContext context) {
    final trimmed = nickname.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final muted = trimmed.isEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: muted
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [KubbTokens.meadow500, KubbTokens.wood500],
                  ),
            color: muted ? tokens.line : null,
          ),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: muted ? tokens.bgSunken : tokens.primary,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: muted ? tokens.fgMuted : tokens.onPrimary,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: tokens.fgMuted,
          ),
        ),
      ],
    );
  }
}

class _RecoveryHint extends StatelessWidget {
  const _RecoveryHint();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF2D6),
        border: Border.all(color: const Color(0xFFD4AE3B), width: 1.5),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 18, color: Color(0xFF5A4500)),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              l10n.authSignupNicknameRecoveryHint,
              style: TextStyle(fontSize: 13, height: 1.4, color: tokens.fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _MnemonicStep extends StatelessWidget {
  const _MnemonicStep({
    required this.mnemonic,
    required this.wordCount,
    required this.ack,
    required this.onAckChanged,
    required this.onChangeLength,
    required this.onRegenerate,
    required this.submitting,
    required this.error,
    required this.onSubmit,
  });

  final String mnemonic;
  final int wordCount;
  final bool ack;
  final ValueChanged<bool> onAckChanged;
  final ValueChanged<int> onChangeLength;
  final VoidCallback onRegenerate;
  final bool submitting;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final words = mnemonic.split(' ').where((w) => w.isNotEmpty).toList();
    final canSubmit = ack && words.length == wordCount && !submitting;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KubbTokens.space2),
          const DisclaimerBlock(),
          const SizedBox(height: KubbTokens.space4),

          // Length picker
          Row(
            children: [
              for (final n in const [12, 15, 18])
                Padding(
                  padding: const EdgeInsets.only(right: KubbTokens.space2),
                  child: ChoiceChip(
                    label: Text('$n Wörter'),
                    selected: wordCount == n,
                    onSelected: submitting ? null : (_) => onChangeLength(n),
                  ),
                ),
            ],
          ),
          const SizedBox(height: KubbTokens.space3),

          // Mnemonic grid
          Container(
            padding: const EdgeInsets.all(KubbTokens.space3),
            decoration: BoxDecoration(
              color: tokens.bg,
              border: Border.all(color: tokens.lineStrong, width: 1.5),
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
            child: Wrap(
              spacing: KubbTokens.space2,
              runSpacing: KubbTokens.space2,
              children: [
                for (var i = 0; i < words.length; i++)
                  _MnemonicWord(index: i + 1, word: words[i]),
              ],
            ),
          ),
          const SizedBox(height: KubbTokens.space2),

          // Helper actions
          Row(
            children: [
              TextButton.icon(
                onPressed: submitting ? null : onRegenerate,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Neue Phrase'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: submitting
                    ? null
                    : () => Clipboard.setData(ClipboardData(text: mnemonic)),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Kopieren'),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space3),

          // Acknowledgment
          InkWell(
            onTap: submitting ? null : () => onAckChanged(!ack),
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
                      'Ich habe meine Mnemonic-Phrase sicher notiert. '
                      'Mir ist bewusst: ohne diese Wörter ist mein Account '
                      'nicht wiederherstellbar.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: KubbTokens.miss,
                ),
              ),
            ),
          ],
          const SizedBox(height: KubbTokens.space5),
          AuthPrimaryButton(
            label: submitting ? 'Account wird erstellt…' : 'Account erstellen',
            onPressed: canSubmit ? onSubmit : null,
            loading: submitting,
          ),
          const SizedBox(height: KubbTokens.space5),
        ],
      ),
    );
  }
}

class _MnemonicWord extends StatelessWidget {
  const _MnemonicWord({required this.index, required this.word});

  final int index;
  final String word;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space2,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: KubbTokens.meadow100,
        borderRadius: BorderRadius.circular(KubbTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$index.',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: KubbTokens.meadow800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            word,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
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
          child: AuthPrimaryButton(
            label: l10n.authSignupSuccessContinue,
            onPressed: onFinish,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
      ],
    );
  }
}
