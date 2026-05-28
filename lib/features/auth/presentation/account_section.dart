import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Account block rendered at the top of the SettingsScreen per design
/// brief #11 / template `AccountSection.jsx` (M5-T14). Pure read-from-
/// AuthSession widget; navigation routes are wired as part of M6-T07.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(authControllerProvider).maybeWhen(
          data: (s) => s,
          orElse: () => const AuthSession.signedOut(),
        );

    if (!session.isAuthenticated) {
      return const SizedBox.shrink();
    }

    final nickname = session.displayName ?? '';
    final isAnonymous = session.isAnonymousKeypair;
    final providerLabel = session.maybeWhen(
      keypair: (_, _, _) => l10n.authAccountProviderAnonymous,
      oauth: (_, _, p, _, _) => p == AuthProvider.apple
          ? l10n.authAccountProviderApple
          : l10n.authAccountProviderGoogle,
      orElse: () => l10n.authAccountProviderAnonymous,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KubbTokens.space5,
            KubbTokens.space4,
            KubbTokens.space5,
            KubbTokens.space2,
          ),
          child: Text(
            l10n.authAccountSectionLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: tokens.fgMuted,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space3),
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          ),
          child: Column(
            children: [
              _IdentityRow(
                nickname: nickname,
                providerLabel: providerLabel,
              ),
              if (isAnonymous)
                _NavRow(
                  icon: Icons.lock_outline,
                  label: l10n.authAccountLinkLabel,
                  sub: l10n.authAccountLinkSub,
                  onTap: () => GoRouter.of(context).push<void>(
                    AuthRoutes.accountLink,
                  ),
                ),
              _NavRow(
                icon: Icons.inbox_outlined,
                label: 'Postfach',
                sub: 'Nachrichten und Bestätigungs-Anfragen',
                onTap: () =>
                    GoRouter.of(context).push<void>(AuthRoutes.inbox),
              ),
              _NavRow(
                icon: Icons.emoji_events_outlined,
                label: l10n.achievementsScreenTitle,
                sub: l10n.achievementsEmptyBody,
                onTap: () => GoRouter.of(context)
                    .push<void>('/profile/achievements'),
              ),
              _NavRow(
                icon: Icons.logout,
                label: l10n.authAccountSignOutLabel,
                sub: l10n.authAccountSignOutSub(providerLabel),
                onTap: () async {
                  await ref
                      .read(authControllerProvider.notifier)
                      .signOut();
                },
              ),
              _NavRow(
                icon: Icons.delete_outline,
                label: l10n.authAccountDeleteLabel,
                sub: l10n.authAccountDeleteSub,
                tone: _NavTone.danger,
                isLast: true,
                onTap: () => GoRouter.of(context).push<void>(
                  AuthRoutes.deleteAccount,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.nickname, required this.providerLabel});

  final String nickname;
  final String providerLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial = nickname.isEmpty ? '?' : nickname[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: KubbTokens.meadow600,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KubbTokens.space2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: KubbTokens.meadow100,
                    borderRadius:
                        BorderRadius.circular(KubbTokens.radiusPill),
                  ),
                  child: Text(
                    providerLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: KubbTokens.meadow800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _NavTone { normal, danger }

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
    this.tone = _NavTone.normal,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final _NavTone tone;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final labelColor = tone == _NavTone.danger ? KubbTokens.miss : tokens.fg;
    final iconColor =
        tone == _NavTone.danger ? KubbTokens.miss : tokens.fgMuted;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(vertical: KubbTokens.space3),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: tokens.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.bgSunken,
                borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: tokens.fgMuted),
          ],
        ),
      ),
    );
  }
}
