import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// The sections of the organiser desktop surface. Order is the sidebar order
/// and drives the `01`..`06` numbering shown next to each entry.
enum AdminSection {
  overview,
  tournaments,
  registrations,
  schedule,
  disputes,
  teams;

  String label(AppLocalizations l) => switch (this) {
        AdminSection.overview => l.adminNavOverview,
        AdminSection.tournaments => l.organizerDashboardTabTournaments,
        AdminSection.registrations => l.adminNavRegistrations,
        AdminSection.schedule => l.adminNavSchedule,
        AdminSection.disputes => l.adminNavDisputes,
        AdminSection.teams => l.adminNavTeams,
      };
}

/// Who is signed in, as the rail shows them.
@immutable
class AdminUser {
  const AdminUser({
    required this.initials,
    required this.name,
    required this.role,
  });

  final String initials;
  final String name;
  final String role;
}

/// Desktop chrome for the organiser surface: a fixed sidebar plus a scrolling
/// content column. Sized to the design's 248 px rail.
///
/// The shell owns no data — [badges], [section] and [user] come from the
/// caller so the chrome stays testable without a provider container.
class AdminShell extends StatelessWidget {
  const AdminShell({
    required this.section,
    required this.onSelect,
    required this.child,
    required this.user,
    this.badges = const <AdminSection, int>{},
    super.key,
  });

  static const double railWidth = 248;

  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;
  final Map<AdminSection, int> badges;
  final AdminUser user;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return ColoredBox(
      color: tokens.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AdminRail(
            section: section,
            onSelect: onSelect,
            badges: badges,
            user: user,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AdminRail extends StatelessWidget {
  const _AdminRail({
    required this.section,
    required this.onSelect,
    required this.badges,
    required this.user,
  });

  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;
  final Map<AdminSection, int> badges;
  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: AdminShell.railWidth,
      color: KubbTokens.stone900,
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space3 + 2,
        22,
        KubbTokens.space3 + 2,
        KubbTokens.space3 + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RailBrand(),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KubbTokens.space3,
              0,
              KubbTokens.space3,
              KubbTokens.space2,
            ),
            child: Text(
              l.adminShellSeason,
              style: const TextStyle(
                fontSize: 10,
                height: 1.2,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                color: KubbTokens.stone400,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final (index, entry) in AdminSection.values.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _RailEntry(
                      index: index,
                      section: entry,
                      selected: entry == section,
                      badge: badges[entry],
                      onTap: () => onSelect(entry),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _RailUser(user: user),
        ],
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space1 + 2),
      child: Row(
        children: [
          // Placeholder mark: the design ships an SVG the app has no loader for.
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: KubbTokens.meadow500,
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.adminShellBrand,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.36,
                    color: KubbTokens.chalk50,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.adminShellBrandSub,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    letterSpacing: 1,
                    color: KubbTokens.stone300,
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

class _RailEntry extends StatelessWidget {
  const _RailEntry({
    required this.index,
    required this.section,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final int index;
  final AdminSection section;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final foreground = selected ? KubbTokens.chalk0 : KubbTokens.stone300;
    return Material(
      color: selected ? KubbTokens.meadow500 : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Semantics(
          selected: selected,
          button: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space3,
              vertical: 11,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: foreground.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(width: KubbTokens.space3),
                Expanded(
                  child: Text(
                    section.label(l),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                if (badge != null && badge! > 0) _RailBadge(
                  count: badge!,
                  selected: selected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0x40000000)
              : KubbTokens.miss,
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: KubbTokens.chalk0,
          ),
        ),
      );
}

class _RailUser extends StatelessWidget {
  const _RailUser({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(KubbTokens.space3 - 2),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: KubbTokens.meadow400,
                shape: BoxShape.circle,
              ),
              child: Text(
                user.initials,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: KubbTokens.stone900,
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space2 + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: KubbTokens.chalk50,
                    ),
                  ),
                  Text(
                    user.role,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.4,
                      letterSpacing: 0.6,
                      color: KubbTokens.stone300,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
