import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Globale BottomNav-Leiste fuer authentifizierte Top-Level-Sektionen.
///
/// Wird vom `StatefulShellRoute.indexedStack`-Wrapper in `router.dart`
/// gemountet. Drei feste Tabs, Home bewusst mittig: Training, Home,
/// Tournaments. Profil ist kein Tab mehr — es haengt am AppBar-Avatar des
/// Home-Screens (`PlayerHubSheet` → `/profile`). Inbox bleibt ebenfalls
/// draussen und landet als AppBar-Bell (W2-T7).
class KubbBottomNav extends StatelessWidget {
  const KubbBottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  /// Aktueller Tab-Index passend zu `navigationShell.currentIndex`.
  final int currentIndex;

  /// Wird mit dem Ziel-Index aufgerufen. Der Caller ruft normalerweise
  /// `navigationShell.goBranch(index, initialLocation: index == current)`
  /// auf, damit ein erneuter Tap denselben Tab-Stack auf den Root reduziert.
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: tokens.bgRaised,
        selectedItemColor: tokens.primary,
        unselectedItemColor: tokens.fgMuted,
        showUnselectedLabels: true,
        currentIndex: currentIndex,
        onTap: onTap,
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const KubbIcon(KubbIcons.target),
            activeIcon: KubbIcon(KubbIcons.target, color: tokens.primary),
            label: l.homeFabLabel,
          ),
          BottomNavigationBarItem(
            icon: const KubbIcon(LucideIcons.home),
            activeIcon: KubbIcon(LucideIcons.home, color: tokens.primary),
            label: l.homeAppTitle,
          ),
          BottomNavigationBarItem(
            icon: const KubbIcon(KubbIcons.trophy),
            activeIcon: KubbIcon(KubbIcons.trophy, color: tokens.primary),
            label: l.tournamentListEyebrow,
          ),
        ],
      ),
    );
  }
}
