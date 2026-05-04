import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Small pill in the top bar showing the active account flavour:
/// keypair, Google or Apple. Hidden while signed-out or still on the
/// pre-attach anonymous session — a status badge there would imply a
/// usable account that does not yet exist.
class AccountStatusBadge extends ConsumerWidget {
  const AccountStatusBadge({super.key, this.compact = true});

  /// Compact uses smaller padding and a tight label — meant for the
  /// app bar. Set false for in-page usage (e.g. profile screen).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).maybeWhen(
          data: (s) => s,
          orElse: () => const AuthSession.signedOut(),
        );
    final l10n = AppLocalizations.of(context);
    final descriptor = session.maybeWhen<_BadgeDescriptor?>(
      keypair: (_, _, _) =>
          _BadgeDescriptor(l10n.authBadgeAnonShort, Icons.lock_outline),
      oauth: (_, _, p, _, _) => p == AuthProvider.apple
          ? _BadgeDescriptor(l10n.authBadgeAppleShort, Icons.apple)
          : _BadgeDescriptor(
              l10n.authBadgeGoogleShort,
              Icons.account_circle_outlined,
            ),
      orElse: () => null,
    );
    if (descriptor == null) {
      return const SizedBox.shrink();
    }
    final label = descriptor.label;
    final icon = descriptor.icon;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(
            horizontal: KubbTokens.space3,
            vertical: KubbTokens.space2,
          );
    final iconSize = compact ? 14.0 : 16.0;
    final fontSize = compact ? 12.0 : 13.0;
    return Semantics(
      label: l10n.authBadgeStatusSemantic(label),
      container: true,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: KubbTokens.meadow100,
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: KubbTokens.meadow700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: KubbTokens.meadow800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeDescriptor {
  const _BadgeDescriptor(this.label, this.icon);
  final String label;
  final IconData icon;
}
