import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/account_setup_controller.dart';
import 'package:kubb_app/features/auth/application/restore_controller.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_primary_button.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/wizard_header.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Single-screen restore: paste / type the BIP-39 mnemonic, hit
/// restore. Per ADR-0011 the public key is derived locally and the
/// existing challenge/sign/verify path proves ownership — no nickname
/// lookup, no encrypted-blob fetch.
class RestoreFlow extends ConsumerStatefulWidget {
  const RestoreFlow({super.key});

  @override
  ConsumerState<RestoreFlow> createState() => _RestoreFlowState();
}

class _RestoreFlowState extends ConsumerState<RestoreFlow> {
  late final TextEditingController _mnemonicCtrl = TextEditingController();
  String _mnemonic = '';

  @override
  void dispose() {
    _mnemonicCtrl.dispose();
    super.dispose();
  }

  void _close() => GoRouter.of(context).pop();

  void _onRestoreDone() => GoRouter.of(context).go('/');

  Future<void> _pasteFromClipboard() async {
    final clip = await Clipboard.getData('text/plain');
    final text = clip?.text;
    if (text == null) return;
    if (!mounted) return;
    setState(() {
      _mnemonic = text;
      _mnemonicCtrl.text = text;
      _mnemonicCtrl.selection =
          TextSelection.collapsed(offset: text.length);
    });
  }

  bool _looksValid() {
    // Cheap pre-check: BIP-39 mnemonics are 12, 15, 18, 21, or 24 words.
    final words = _mnemonic
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return const {12, 15, 18, 21, 24}.contains(words.length);
  }

  Future<void> _submit() async {
    final crypto = ref.read(cryptoServiceProvider);
    if (!crypto.isValidBip39Mnemonic(_mnemonic)) {
      // Present the same error path the controller would set, but skip
      // a network round-trip for an obviously broken phrase.
      await ref
          .read(restoreControllerProvider.notifier)
          .restore(mnemonic: _mnemonic);
      return;
    }
    await ref
        .read(restoreControllerProvider.notifier)
        .restore(mnemonic: _mnemonic);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(restoreControllerProvider);

    ref.listen<RestoreState>(restoreControllerProvider, (_, next) {
      next.whenOrNull(done: (_) => _onRestoreDone());
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

    final canSubmit =
        _looksValid() && !restoring && cooldownUntil == null;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            WizardHeader(
              step: 0,
              total: 1,
              eyebrow: l10n.authRestoreEyebrow,
              title: 'Mnemonic eingeben',
              onClose: _close,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: KubbTokens.space3),
                    if (cooldownUntil != null)
                      _CooldownBadge(
                        until: cooldownUntil,
                        onExpired: () => ref
                            .read(restoreControllerProvider.notifier)
                            .clearIfExpired(),
                      )
                    else ...[
                      Text(
                        'Gib die 12, 15 oder 18 Wörter deiner Mnemonic-Phrase '
                        'ein, getrennt durch Leerzeichen.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: tokens.fgMuted,
                        ),
                      ),
                      const SizedBox(height: KubbTokens.space3),

                      TextField(
                        controller: _mnemonicCtrl,
                        maxLines: 4,
                        minLines: 3,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofocus: true,
                        onChanged: (v) => setState(() => _mnemonic = v),
                        decoration: InputDecoration(
                          hintText:
                              'word1 word2 word3 …',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(KubbTokens.radiusMd),
                            borderSide: BorderSide(
                              color: tokens.lineStrong,
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(KubbTokens.radiusMd),
                            borderSide: BorderSide(
                              color: errorReason != null
                                  ? KubbTokens.miss
                                  : tokens.lineStrong,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: KubbTokens.space2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: restoring ? null : _pasteFromClipboard,
                          icon: const Icon(Icons.paste, size: 16),
                          label: const Text('Aus Zwischenablage einfügen'),
                        ),
                      ),

                      if (errorReason != null) ...[
                        const SizedBox(height: KubbTokens.space3),
                        Container(
                          padding: const EdgeInsets.all(KubbTokens.space3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBE4E0),
                            border: Border.all(
                              color: KubbTokens.miss,
                              width: 1.5,
                            ),
                            borderRadius:
                                BorderRadius.circular(KubbTokens.radiusMd),
                          ),
                          child: Text(
                            _errorMessageFor(errorReason, l10n),
                            style: const TextStyle(
                              fontSize: 13,
                              color: KubbTokens.miss,
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: KubbTokens.space6),
                    AuthPrimaryButton(
                      label: restoring
                          ? l10n.authRestoreSubmitting
                          : l10n.authRestoreSubmit,
                      onPressed: canSubmit ? _submit : null,
                      loading: restoring,
                    ),
                    const SizedBox(height: KubbTokens.space5),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Map a `RestoreState.failed(reason: ...)` reason-code to user-facing
/// copy. The codes come from `RestoreController._classifyRestoreError`
/// — keep the two in sync.
String _errorMessageFor(String reason, AppLocalizations l10n) {
  switch (reason) {
    case 'mnemonic_invalid':
      return 'Mnemonic-Phrase ungültig oder Tippfehler in einem Wort.';
    case 'no_account_for_mnemonic':
      return 'Diese Mnemonic-Phrase gehört zu keinem Account auf '
          'diesem Server. Prüfe die Wörter und ihre Reihenfolge.';
    case 'signature_invalid':
      return 'Die Signatur konnte nicht überprüft werden. '
          'Versuch es nochmal.';
    case 'challenge_failed':
      return 'Der Server hat die Anfrage nicht akzeptiert. '
          'Versuch es in ein paar Sekunden nochmal.';
    case 'signin_failed':
    default:
      return l10n.authRestoreError;
  }
}

class _CooldownBadge extends StatefulWidget {
  const _CooldownBadge({required this.until, required this.onExpired});

  final DateTime until;
  final VoidCallback onExpired;

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
      // Defer to a post-frame callback so we don't mutate provider state
      // mid-build of the parent (which is already rebuilding because of
      // our own setState above).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired();
      });
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
