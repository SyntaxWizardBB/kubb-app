import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/social/presentation/social_routes.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Bottom-sheet hub triggered from the home-screen player icon. Replaces
/// the direct navigation to ProfileScreen with a single jumping-off
/// point for everything player-shaped: own profile, social graph
/// (friends + groups, both upcoming), and the in-app inbox.
///
/// Friends + Groups are stub entries on purpose — the data model + flows
/// for those land alongside the upcoming Match / Tournament features
/// (see ADR notes in the conversation that introduced this hub).
class PlayerHubSheet extends StatelessWidget {
  const PlayerHubSheet({super.key});

  /// Imperative helper so callers do not need to remember the showSheet
  /// boilerplate.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).extension<KubbTokens>()!.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const PlayerHubSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space3,
          KubbTokens.space4,
          KubbTokens.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: KubbTokens.space4),
            Text(
              'Spieler',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: tokens.fg,
              ),
            ),
            const SizedBox(height: KubbTokens.space4),

            _HubRow(
              icon: LucideIcons.user,
              label: 'Mein Profil',
              sub: 'Stats, Avatar, Spielername',
              onTap: () {
                Navigator.of(context).pop();
                context.go('/profile');
              },
            ),
            _HubRow(
              icon: LucideIcons.users,
              label: 'Freunde',
              sub: 'Mitspieler suchen und hinzufügen',
              onTap: () {
                Navigator.of(context).pop();
                unawaited(context.push<void>(SocialRoutes.friends));
              },
            ),
            _HubRow(
              icon: Icons.groups_outlined,
              label: 'Gruppen',
              sub: 'Stamm-Teams und Vereins-Listen',
              onTap: () {
                Navigator.of(context).pop();
                unawaited(context.push<void>(SocialRoutes.groups));
              },
            ),
            _HubRow(
              icon: LucideIcons.inbox,
              label: 'Postfach',
              sub: 'Nachrichten und Einladungen',
              isLast: true,
              onTap: () {
                Navigator.of(context).pop();
                unawaited(context.push<void>(AuthRoutes.inbox));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HubRow extends StatelessWidget {
  const _HubRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final disabled = onTap == null;
    final labelColor = disabled ? tokens.fgMuted : tokens.fg;

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: KubbTokens.space3,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.bgRaised,
                    borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: labelColor),
                ),
                const SizedBox(width: KubbTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
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
                if (!disabled)
                  Icon(Icons.chevron_right, color: tokens.fgMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
