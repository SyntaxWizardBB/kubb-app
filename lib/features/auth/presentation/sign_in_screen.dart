import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/data/supabase_auth_adapter.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/oauth_provider_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Cold-start entry per design brief #1 / template `SignInScreen.jsx`.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  _SignInLoading? _loading;
  bool _showError = false;

  bool get _showApple => !kIsWeb && Platform.isIOS;

  Future<void> _onPickGoogle() => _dispatchOAuth(AuthProvider.google);

  Future<void> _onPickApple() => _dispatchOAuth(AuthProvider.apple);

  Future<void> _dispatchOAuth(AuthProvider provider) async {
    if (_loading != null) return;
    final offline = !ref.read(connectivityServiceProvider).isOnline;
    if (offline) {
      // The standing offline banner already explains why OAuth is
      // blocked; no need to also flip the error banner.
      return;
    }
    setState(() {
      _loading = provider == AuthProvider.google
          ? _SignInLoading.google
          : _SignInLoading.apple;
      _showError = false;
    });
    final adapter = ref.read(supabaseAuthAdapterProvider);
    try {
      await adapter.signInWithOAuth(
        provider == AuthProvider.google
            ? AuthOAuthProvider.google
            : AuthOAuthProvider.apple,
      );
    } on Object {
      // Stable reason-message — we never surface raw exception text to
      // the user (R1-F-01). A successful kickoff leaves the loading
      // spinner on; the actual session arrives later via
      // onAuthStateChange and the router moves on.
      if (!mounted) return;
      setState(() {
        _loading = null;
        _showError = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _loading = null);
  }

  Future<void> _onPickAnonymous() async {
    // P7: creating an account first requires a valid early-access code.
    await GoRouter.of(context).push<void>(AuthRoutes.earlyAccess);
  }

  Future<void> _onPickRestore() async {
    await GoRouter.of(context).push<void>(AuthRoutes.restore);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final offline = !ref.watch(connectivityServiceProvider).isOnline;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: KubbTokens.space4,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: KubbTokens.space8),
                      _BrandBlock(
                        appName: l10n.authAppName,
                        tagline: l10n.authSigninTagline,
                      ),
                      const Spacer(),
                      _SignInCard(
                        children: [
                          if (offline) ...[
                            _OfflineBanner(message: l10n.authSigninOffline),
                            const SizedBox(height: KubbTokens.space3),
                          ],
                          if (_showError) ...[
                            _ErrorBanner(
                              key: const ValueKey('signInOauthError'),
                              message: l10n.authSigninOauthError,
                            ),
                            const SizedBox(height: KubbTokens.space3),
                          ],
                          OAuthProviderButton(
                            provider: AuthProvider.google,
                            label: l10n.authSigninGoogle,
                            loading: _loading == _SignInLoading.google,
                            onPressed: offline ? null : _onPickGoogle,
                          ),
                          const SizedBox(height: KubbTokens.space3),
                          if (_showApple) ...[
                            OAuthProviderButton(
                              provider: AuthProvider.apple,
                              label: l10n.authSigninApple,
                              loading: _loading == _SignInLoading.apple,
                              onPressed: offline ? null : _onPickApple,
                            ),
                            const SizedBox(height: KubbTokens.space3),
                          ],
                          _OrDivider(label: l10n.authSigninOr),
                          const SizedBox(height: KubbTokens.space3),
                          _AnonymousButton(
                            label: l10n.authSigninAnonymous,
                            loading: false,
                            onPressed: _onPickAnonymous,
                          ),
                          const SizedBox(height: KubbTokens.space2),
                          TextButton(
                            onPressed: _onPickRestore,
                            style: TextButton.styleFrom(
                              foregroundColor: tokens.primary,
                            ),
                            child: Text(l10n.authSigninRestore),
                          ),
                        ],
                      ),
                      const SizedBox(height: KubbTokens.space5),
                      _EstFooter(text: 'EST. 2025 · DACH', color: tokens.fgMuted),
                      const SizedBox(height: KubbTokens.space4),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space5,
        KubbTokens.space4,
        KubbTokens.space4,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl + 4),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _EstFooter extends StatelessWidget {
  const _EstFooter({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 3,
        color: color,
      ),
    );
  }
}

enum _SignInLoading { google, apple }

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.appName, required this.tagline});

  final String appName;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusXl + 4),
            boxShadow: [
              BoxShadow(
                color: tokens.fg.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const _KubbLogo(size: 56),
        ),
        const SizedBox(height: KubbTokens.space4),
        Text(
          'Kubb Club'.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          appName,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: tokens.fg,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          tagline,
          style: TextStyle(fontSize: 14, color: tokens.fgMuted),
        ),
      ],
    );
  }
}

/// Two-block kubb mark — wood block left, meadow block right, ground
/// shadow bar. Matches the SVG in the SignInScreen template.
class _KubbLogo extends StatelessWidget {
  const _KubbLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _KubbLogoPainter(),
    );
  }
}

class _KubbLogoPainter extends CustomPainter {
  const _KubbLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    final wood = Paint()..color = KubbTokens.wood400;
    final woodTop = Paint()..color = KubbTokens.wood500;
    final meadow = Paint()..color = KubbTokens.meadow500;
    final meadowTop = Paint()..color = KubbTokens.meadow700;
    final ground = Paint()..color = KubbTokens.stone700;

    final radius = Radius.circular(2 * s);

    canvas
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          10 * s, 20 * s, 28 * s, 54 * s,
          topLeft: radius, topRight: radius,
          bottomLeft: radius, bottomRight: radius,
        ),
        wood,
      )
      ..drawRect(Rect.fromLTRB(10 * s, 20 * s, 28 * s, 26 * s), woodTop)
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          36 * s, 10 * s, 54 * s, 54 * s,
          topLeft: radius, topRight: radius,
          bottomLeft: radius, bottomRight: radius,
        ),
        meadow,
      )
      ..drawRect(Rect.fromLTRB(36 * s, 10 * s, 54 * s, 16 * s), meadowTop)
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          6 * s, 56 * s, 58 * s, 59 * s,
          topLeft: Radius.circular(1.5 * s),
          topRight: Radius.circular(1.5 * s),
          bottomLeft: Radius.circular(1.5 * s),
          bottomRight: Radius.circular(1.5 * s),
        ),
        ground,
      );
  }

  @override
  bool shouldRepaint(covariant _KubbLogoPainter oldDelegate) => false;
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: KubbTokens.wood50,
        border: Border.all(color: KubbTokens.wood200),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: tokens.fg),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: tokens.fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE4E0),
        border: Border.all(color: KubbTokens.miss, width: 1.5),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: KubbTokens.miss),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: KubbTokens.miss),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: tokens.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: tokens.fgMuted,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: tokens.line)),
      ],
    );
  }
}

class _AnonymousButton extends StatelessWidget {
  const _AnonymousButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: tokens.bgSunken,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.line, width: 1.5),
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        ),
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: KubbTokens.touchComfortable,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space5,
              vertical: KubbTokens.space3,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 20, color: tokens.fg),
                const SizedBox(width: KubbTokens.space3),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: tokens.fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
