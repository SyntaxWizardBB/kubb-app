import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/account_deletion_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_primary_button.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_secondary_button.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/wizard_header.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Two-page destructive flow per AK-13 / design brief #8 (M5-T11,
/// template `DeleteAccountScreen.jsx`). Page 1 explains the
/// consequences; page 2 requires an explicit acknowledgement before
/// the destructive button activates.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  _Page _page = _Page.warning;
  bool _ack = false;

  void _back() {
    if (_page == _Page.confirm) {
      setState(() {
        _page = _Page.warning;
        _ack = false;
      });
    } else {
      GoRouter.of(context).pop();
    }
  }

  void _toConfirm() {
    setState(() => _page = _Page.confirm);
  }

  Future<void> _confirmDelete() async {
    final nickname = ref.read(authControllerProvider).maybeWhen(
          data: (s) => s.displayName,
          orElse: () => null,
        );
    await ref
        .read(accountDeletionControllerProvider.notifier)
        .delete(nickname: nickname);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(accountDeletionControllerProvider);

    final deleting = state.maybeWhen(
      deleting: () => true,
      orElse: () => false,
    );
    final hasError = state.maybeWhen(
      failed: (_) => true,
      orElse: () => false,
    );

    final stepIdx = _page.index;
    final title = switch (_page) {
      _Page.warning => l10n.authDeleteWarningTitle,
      _Page.confirm => l10n.authDeleteConfirmTitle,
    };

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            WizardHeader(
              step: stepIdx,
              total: 2,
              eyebrow: l10n.authDeleteEyebrow,
              title: title,
              onBack: _back,
              showStepDots: false,
              tone: WizardHeaderTone.danger,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space6,
                ),
                child: switch (_page) {
                  _Page.warning => _WarningPage(onContinue: _toConfirm),
                  _Page.confirm => _ConfirmPage(
                      ack: _ack,
                      onAckChanged: (v) => setState(() => _ack = v),
                      deleting: deleting,
                      hasError: hasError,
                      onConfirm: _confirmDelete,
                      onCancel: _back,
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

enum _Page { warning, confirm }

class _WarningPage extends StatelessWidget {
  const _WarningPage({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final consequences = [
      l10n.authDeleteConsequenceSessions,
      l10n.authDeleteConsequenceStats,
      l10n.authDeleteConsequenceProfile,
      l10n.authDeleteConsequenceLinkedAccounts,
      l10n.authDeleteConsequenceKeypair,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: KubbTokens.space4),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFFBE4E0),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.warning_amber_rounded,
              color: KubbTokens.miss,
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        Text(
          l10n.authDeleteWarningHeadline,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: tokens.fg,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          l10n.authDeleteWarningSub,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space5),
        for (final c in consequences) ...[
          _ConsequenceItem(text: c),
          const SizedBox(height: KubbTokens.space2),
        ],
        const Spacer(),
        AuthPrimaryButton(
          label: l10n.authDeleteContinueToConfirm,
          onPressed: onContinue,
          tone: AuthButtonTone.danger,
        ),
        const SizedBox(height: KubbTokens.space5),
      ],
    );
  }
}

class _ConsequenceItem extends StatelessWidget {
  const _ConsequenceItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 7),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: KubbTokens.miss,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: KubbTokens.space3),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: tokens.fg,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfirmPage extends StatelessWidget {
  const _ConfirmPage({
    required this.ack,
    required this.onAckChanged,
    required this.deleting,
    required this.hasError,
    required this.onConfirm,
    required this.onCancel,
  });

  final bool ack;
  final ValueChanged<bool> onAckChanged;
  final bool deleting;
  final bool hasError;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final canConfirm = ack && !deleting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: KubbTokens.space4),
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
                    color: ack ? KubbTokens.miss : Colors.transparent,
                    border: Border.all(
                      color: ack ? KubbTokens.miss : tokens.lineStrong,
                      width: 1.5,
                    ),
                    borderRadius:
                        BorderRadius.circular(KubbTokens.radiusSm),
                  ),
                  alignment: Alignment.center,
                  child: ack
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: KubbTokens.space3),
                Expanded(
                  child: Text(
                    l10n.authDeleteAcknowledge,
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
        if (hasError) ...[
          const SizedBox(height: KubbTokens.space3),
          Container(
            padding: const EdgeInsets.all(KubbTokens.space3),
            decoration: BoxDecoration(
              color: const Color(0xFFFBE4E0),
              border: Border.all(color: KubbTokens.miss, width: 1.5),
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
            child: Text(
              l10n.authDeleteErrorBanner,
              style: const TextStyle(fontSize: 13, color: KubbTokens.miss),
            ),
          ),
        ],
        const Spacer(),
        AuthPrimaryButton(
          label: deleting
              ? l10n.authDeleteSubmitting
              : l10n.authDeleteSubmit,
          onPressed: canConfirm ? onConfirm : null,
          loading: deleting,
          tone: AuthButtonTone.danger,
        ),
        const SizedBox(height: KubbTokens.space2),
        AuthSecondaryButton(
          label: l10n.authDeleteCancel,
          onPressed: onCancel,
        ),
        const SizedBox(height: KubbTokens.space5),
      ],
    );
  }
}
