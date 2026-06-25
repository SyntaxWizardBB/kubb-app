import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/account_upgrade_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_app_bar.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_secondary_button.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/oauth_provider_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Anonymous-keypair → OAuth upgrade screen per design brief #6
/// (M5-T09, template `AccountLinkScreen.jsx`).
class AccountLinkScreen extends ConsumerStatefulWidget {
  const AccountLinkScreen({super.key});

  @override
  ConsumerState<AccountLinkScreen> createState() => _AccountLinkScreenState();
}

class _AccountLinkScreenState extends ConsumerState<AccountLinkScreen> {
  bool get _showApple => !kIsWeb && Platform.isIOS;

  void _back() {
    GoRouter.of(context).pop();
  }

  Future<void> _link(AuthProvider provider) async {
    await ref
        .read(accountUpgradeControllerProvider.notifier)
        .linkOAuth(provider);
  }

  String _bannerForCode(AppLocalizations l10n, String code) {
    switch (code) {
      case 'oauth_subject_in_use':
        return l10n.authLinkErrorSubjectInUse;
      case 'forked_user_has_data':
        return l10n.authLinkErrorForkedHasData;
      case 'oauth_token_invalid':
      case 'oauth_provider_mismatch':
      case 'oauth_launch_failed':
        return l10n.authLinkErrorOauthInvalid;
      case 'challenge_not_found':
      case 'challenge_expired':
      case 'signature_invalid':
      case 'no_account_for_public_key':
        return l10n.authLinkErrorChallenge;
      case 'callback_timeout':
        return l10n.authLinkErrorTimeout;
      case 'keypair_seed_missing':
      case 'not_keypair':
        return l10n.authLinkErrorSeedMissing;
      default:
        return l10n.authLinkErrorBanner;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(accountUpgradeControllerProvider);

    final busy = state.maybeWhen(
      launching: (_) => true,
      awaitingCallback: (_) => true,
      reconciling: (_) => true,
      orElse: () => false,
    );
    final done = state.maybeWhen(
      done: () => true,
      orElse: () => false,
    );
    final errorCode = state.maybeWhen(
      failed: (code, _) => code,
      orElse: () => null,
    );
    final busyProvider = state.maybeWhen(
      launching: (p) => p,
      awaitingCallback: (p) => p,
      reconciling: (p) => p,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
          child: Column(
            children: [
              AuthAppBar(
                eyebrow: l10n.authLinkEyebrow,
                title: l10n.authLinkTitle,
                onBack: _back,
              ),
              const SizedBox(height: KubbTokens.space5),
              _IntroBlock(
                heading: l10n.authLinkHeading,
                body: l10n.authLinkExplanation,
              ),
              const SizedBox(height: KubbTokens.space5),
              OAuthProviderButton(
                provider: AuthProvider.google,
                variant: OAuthButtonVariant.secondary,
                label: l10n.authLinkGoogleLabel,
                loading: busy && busyProvider == AuthProvider.google,
                onPressed: busy ? null : () => _link(AuthProvider.google),
              ),
              if (_showApple) ...[
                const SizedBox(height: KubbTokens.space3),
                OAuthProviderButton(
                  provider: AuthProvider.apple,
                  variant: OAuthButtonVariant.secondary,
                  label: l10n.authLinkAppleLabel,
                  loading: busy && busyProvider == AuthProvider.apple,
                  onPressed: busy ? null : () => _link(AuthProvider.apple),
                ),
              ],
              if (errorCode != null) ...[
                const SizedBox(height: KubbTokens.space3),
                _Banner(
                  tone: _BannerTone.error,
                  message: _bannerForCode(l10n, errorCode),
                ),
              ],
              if (done) ...[
                const SizedBox(height: KubbTokens.space3),
                _Banner(
                  tone: _BannerTone.info,
                  message: l10n.authLinkSuccessBanner,
                ),
              ],
              const Spacer(),
              _FallbackNote(message: l10n.authLinkFallbackKept),
              const SizedBox(height: KubbTokens.space3),
              AuthSecondaryButton(
                label: l10n.authCommonBack,
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

class _IntroBlock extends StatelessWidget {
  const _IntroBlock({required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: KubbTokens.meadow100,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.lock_outline,
            color: KubbTokens.meadow600,
            size: 28,
          ),
        ),
        const SizedBox(height: KubbTokens.space3),
        Text(
          heading,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: -0.4,
            color: tokens.fg,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: tokens.fgMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _FallbackNote extends StatelessWidget {
  const _FallbackNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space3,
      ),
      decoration: BoxDecoration(
        color: KubbTokens.meadow100,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: KubbTokens.meadow500,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check, size: 14, color: Colors.white),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: KubbTokens.meadow800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _BannerTone { info, error }

class _Banner extends StatelessWidget {
  const _Banner({required this.tone, required this.message});

  final _BannerTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, icon) = switch (tone) {
      _BannerTone.error => (
          const Color(0xFFFBE4E0),
          KubbTokens.miss,
          KubbTokens.miss,
          Icons.error_outline,
        ),
      _BannerTone.info => (
          KubbTokens.meadow100,
          KubbTokens.meadow600,
          KubbTokens.meadow800,
          Icons.check_circle_outline,
        ),
    };
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 1.5),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
