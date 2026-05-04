import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/restore_controller.dart';
import 'package:kubb_app/features/auth/presentation/passphrase_input.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Two-step restore wizard per design brief #5 (M5-T08).
///
/// Step 1: nickname input. Step 2: passphrase input that drives
/// [RestoreController]. Cooldown state from the controller is rendered
/// as a countdown badge instead of the input.
class RestoreFlow extends ConsumerStatefulWidget {
  const RestoreFlow({super.key});

  @override
  ConsumerState<RestoreFlow> createState() => _RestoreFlowState();
}

class _RestoreFlowState extends ConsumerState<RestoreFlow> {
  _Step _step = _Step.nickname;
  String _nickname = '';

  void _toStep2(String nickname) {
    setState(() {
      _nickname = nickname;
      _step = _Step.passphrase;
    });
  }

  void _back() {
    setState(() => _step = _Step.nickname);
  }

  void _close() {
    GoRouter.of(context).pop();
  }

  void _onRestoreDone() {
    GoRouter.of(context).go('/');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final stepIdx = _step.index;
    final title = switch (_step) {
      _Step.nickname => l10n.authRestoreNicknameTitle,
      _Step.passphrase => l10n.authRestorePassphraseTitle,
    };

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            _WizardHeader(
              step: stepIdx,
              total: 2,
              eyebrow: l10n.authRestoreEyebrow,
              title: title,
              onBack: stepIdx > 0 ? _back : null,
              onClose: _close,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space6,
                ),
                child: switch (_step) {
                  _Step.nickname => _NicknameStep(onContinue: _toStep2),
                  _Step.passphrase => _PassphraseStep(
                      nickname: _nickname,
                      onRestoreDone: _onRestoreDone,
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Step { nickname, passphrase }

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
            hintText: l10n.authRestoreNicknamePlaceholder,
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
            l10n.authRestoreNicknameHelper,
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

class _PassphraseStep extends ConsumerStatefulWidget {
  const _PassphraseStep({
    required this.nickname,
    required this.onRestoreDone,
  });

  final String nickname;
  final VoidCallback onRestoreDone;

  @override
  ConsumerState<_PassphraseStep> createState() => _PassphraseStepState();
}

class _PassphraseStepState extends ConsumerState<_PassphraseStep> {
  String _pass = '';

  Future<void> _submit() async {
    await ref.read(restoreControllerProvider.notifier).restore(
          nickname: widget.nickname,
          passphrase: _pass,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(restoreControllerProvider);

    ref.listen<RestoreState>(restoreControllerProvider, (_, next) {
      next.whenOrNull(done: (_) => widget.onRestoreDone());
    });

    final restoring = state.maybeWhen(
      restoring: () => true,
      orElse: () => false,
    );
    final cooldownUntil = state.maybeWhen(
      cooldown: (until) => until,
      orElse: () => null,
    );
    final errorReason = state.maybeWhen(
      failed: (reason) => reason,
      orElse: () => null,
    );

    final passOk = _pass.length >= 12;
    final canSubmit = passOk && !restoring && cooldownUntil == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: KubbTokens.space3),
        if (cooldownUntil != null)
          _CooldownBadge(until: cooldownUntil)
        else ...[
          PassphraseInput(
            value: _pass,
            onChanged: (v) => setState(() => _pass = v),
            helper: l10n.authRestorePassphraseHelper,
            autofocus: true,
          ),
          if (errorReason != null) ...[
            const SizedBox(height: KubbTokens.space3),
            Container(
              padding: const EdgeInsets.all(KubbTokens.space3),
              decoration: BoxDecoration(
                color: const Color(0xFFFBE4E0),
                border: Border.all(color: KubbTokens.miss, width: 1.5),
                borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              ),
              child: Text(
                l10n.authRestoreError,
                style: const TextStyle(
                  fontSize: 13,
                  color: KubbTokens.miss,
                ),
              ),
            ),
          ],
        ],
        const Spacer(),
        _PrimaryButton(
          label: restoring
              ? l10n.authRestoreSubmitting
              : l10n.authRestoreSubmit,
          onPressed: canSubmit ? _submit : null,
          loading: restoring,
        ),
        const SizedBox(height: KubbTokens.space5),
      ],
    );
  }
}

class _CooldownBadge extends StatefulWidget {
  const _CooldownBadge({required this.until});

  final DateTime until;

  @override
  State<_CooldownBadge> createState() => _CooldownBadgeState();
}

class _CooldownBadgeState extends State<_CooldownBadge> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now().toUtc();
    final diff = widget.until.difference(now);
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
    });
    if (diff.isNegative || diff.inSeconds == 0) {
      _ticker?.cancel();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seconds = _remaining.inSeconds;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space4,
          vertical: KubbTokens.space3,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF2D6),
          border: Border.all(
            color: const Color(0xFFD4AE3B),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.timer_outlined,
                color: Color(0xFF9A6B00),
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.authRestoreCooldownTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3D2C00),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.authRestoreCooldownMessage(seconds),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF3D2C00),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
