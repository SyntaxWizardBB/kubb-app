import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// App-wide navigation drawer, opened from the home AppBar hamburger.
///
/// Replaces the former `PlayerHubSheet` as the single jumping-off point for
/// everything that does not own a BottomNav tab: own profile, achievements,
/// inbox, settings, and the legal pages. "Freunde" intentionally lives in the
/// Training hub as a tile (P7) and is not duplicated here.
///
/// Visual language follows the design system (`docs/design`): a profile
/// header on the brand surface, then grouped rows in the same row idiom as the
/// rest of the app, with muted section labels separating the groups.
class KubbDrawer extends ConsumerWidget {
  const KubbDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final profile = ref.watch(displayProfileProvider);

    return Drawer(
      backgroundColor: tokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(displayName: profile?.displayName),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space3,
                ),
                children: [
                  const SizedBox(height: KubbTokens.space2),
                  _DrawerRow(
                    icon: LucideIcons.user,
                    label: 'Mein Profil',
                    sub: 'Stats, Avatar, Spielername',
                    onTap: () => _go(context, '/profile'),
                  ),
                  _DrawerRow(
                    icon: LucideIcons.archive,
                    label: 'Archiv',
                    sub: 'Archivierte Nachrichten ansehen und löschen',
                    onTap: () => _go(context, '/inbox/archive'),
                  ),
                  _DrawerRow(
                    icon: LucideIcons.settings,
                    label: 'Einstellungen',
                    sub: 'App, Daten und Konto',
                    onTap: () => _go(context, '/settings'),
                  ),
                  const _DrawerSectionLabel('Rechtliches'),
                  _DrawerRow(
                    icon: LucideIcons.shieldCheck,
                    label: 'Datenschutz',
                    sub: 'Datenschutzerklärung',
                    onTap: () => _go(context, '/legal/privacy'),
                  ),
                  _DrawerRow(
                    icon: LucideIcons.fileText,
                    label: 'Impressum',
                    sub: 'Rechtliche Angaben',
                    onTap: () => _go(context, '/legal/imprint'),
                  ),
                ],
              ),
            ),
            const _DrawerFooter(),
          ],
        ),
      ),
    );
  }

  /// Close the drawer, then push the destination. Closing first keeps the
  /// drawer off the back stack so a back-press returns to the previous
  /// screen rather than re-opening the panel.
  void _go(BuildContext context, String route) {
    Navigator.of(context).pop();
    unawaited(context.push<void>(route));
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.displayName});

  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    final name = (displayName == null || displayName!.isEmpty)
        ? 'Spieler'
        : displayName!;
    final initial = name[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space4,
        KubbTokens.space4,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: KubbTokens.meadow600,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'KUBB CLUB',
                  style: t.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.88,
                    color: tokens.fgMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: tokens.fg,
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

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space2,
        KubbTokens.space5,
        KubbTokens.space2,
        KubbTokens.space2,
      ),
      child: Text(
        text.toUpperCase(),
        style: t.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.88,
          color: tokens.fgMuted,
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: Material(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space3,
              vertical: KubbTokens.space3,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.bg,
                    borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: tokens.fg),
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
                          color: tokens.fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: tokens.fgMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space2,
        KubbTokens.space4,
        KubbTokens.space4,
      ),
      child: Text(
        'Kubb Club',
        style: t.labelSmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: tokens.fgSubtle,
        ),
      ),
    );
  }
}
