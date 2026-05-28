import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Sprint-B / W6-T2 — Skeleton-Screen fuer Achievements / Badges.
///
/// Quelle: `docs/design/AUDIT.md` §4.6 ("Achievements / Badges — 12–15
/// Badges mit hoelzernen Glyphs + Gold-Akzent"). Die finalen Brand-
/// Glyphs liefert der Designer in einem spaeteren Sprint; bis dahin
/// rendert dieser Screen Lucide-Stellvertreter als Vignette analog zu
/// `lib/core/ui/icons.dart` (Heli/King/Cup-Substitutes).
///
/// Layout:
/// - [KubbAppBar.slots] mit eyebrow "Profil" + title "Erfolge".
/// - [SingleChildScrollView] mit zwei Sektionen:
///   1. **Erspielt** — bereits freigeschaltete Badges (aktuell leer im
///      Mock-State; sobald T1-Domain-Modell + Achievement-Provider
///      existieren werden hier echte Daten gemappt).
///   2. **Noch offen** — Liste aller noch nicht freigeschalteten
///      Badges; je Badge eine Inset-Card mit Glyph-Vignette (48 dp),
///      Title, Description und [KubbChip] mit Trigger-Beschreibung.
/// - Falls beide Sektionen leer waeren: zentrierter [KubbEmptyState]
///   mit CTA "Sniper starten".
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, this.earned, this.locked});

  /// Override fuer bereits erspielte Badges. `null` = Default-Mock
  /// (leer). Wird genutzt vom Widget-Test, um den "earned + locked"-
  /// Renderpfad zu pruefen.
  final List<AchievementBadge>? earned;

  /// Override fuer noch offene Badges. `null` = Default-Mock (5
  /// Placeholder, alle gesperrt) — siehe [_defaultLockedBadges].
  final List<AchievementBadge>? locked;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    final earnedBadges = earned ?? const <AchievementBadge>[];
    final lockedBadges = locked ?? _defaultLockedBadges(l);
    final isEmpty = earnedBadges.isEmpty && lockedBadges.isEmpty;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar.slots(
        eyebrow: Text(
          l.achievementsScreenEyebrow.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted,
              ),
        ),
        title: Text(
          l.achievementsScreenTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.36,
                color: tokens.fg,
              ),
        ),
      ),
      body: SafeArea(
        child: isEmpty
            ? _EmptyBody(l: l)
            : _ListBody(
                earned: earnedBadges,
                locked: lockedBadges,
                l: l,
                tokens: tokens,
              ),
      ),
    );
  }
}

/// Default-Liste mit 5 Placeholder-Badges (alle "Noch offen"). Wird
/// vom Designer-Output abgeloest, sobald die finalen Brand-SVGs
/// landen (siehe AUDIT §4.6).
List<AchievementBadge> _defaultLockedBadges(AppLocalizations l) {
  return [
    AchievementBadge(
      id: 'first-hit',
      title: l.achievementsBadgeFirstHitTitle,
      description: l.achievementsBadgeFirstHitDesc,
      glyph: LucideIcons.target,
      trigger: l.achievementsBadgeFirstHitTitle,
    ),
    AchievementBadge(
      id: 'hundred-hits',
      title: l.achievementsBadgeHundredHitsTitle,
      description: l.achievementsBadgeHundredHitsDesc,
      glyph: LucideIcons.award,
      trigger: l.achievementsBadgeHundredHitsTitle,
    ),
    AchievementBadge(
      id: 'streak',
      title: l.achievementsBadgeStreakTitle,
      description: l.achievementsBadgeStreakDesc,
      glyph: LucideIcons.flame,
      trigger: l.achievementsBadgeStreakTitle,
    ),
    AchievementBadge(
      id: 'heli',
      title: l.achievementsBadgeHeliTitle,
      description: l.achievementsBadgeHeliDesc,
      glyph: LucideIcons.wind,
      trigger: l.achievementsBadgeHeliTitle,
    ),
    AchievementBadge(
      id: 'king',
      title: l.achievementsBadgeKingTitle,
      description: l.achievementsBadgeKingDesc,
      glyph: LucideIcons.crown,
      trigger: l.achievementsBadgeKingTitle,
    ),
  ];
}

/// Daten-Holder fuer einen einzelnen Badge-Eintrag im Skeleton.
///
/// Sobald W6-T1 das Domain-Modell + den Achievement-Provider liefert,
/// wird dieser Typ entweder durch das Domain-Modell ersetzt oder als
/// Mapper-Output (Display-Layer) erhalten — die Felder decken den
/// Audit-Vorschlag (Title + Description + Trigger) ab.
@immutable
class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.glyph,
    this.trigger,
    this.earnedLabel,
  });

  final String id;
  final String title;
  final String description;

  /// Lucide-Glyph-Placeholder bis Designer-SVG kommt.
  final IconData glyph;

  /// Trigger-Text fuer die "Noch offen"-Sektion (z.B. "100 Treffer").
  /// `null` wenn der Badge bereits freigeschaltet ist.
  final String? trigger;

  /// Datum/Label fuer die "Erspielt"-Sektion (z.B. "Erspielt am
  /// 12.04.2026"). `null` solange der Badge nicht freigeschaltet ist.
  final String? earnedLabel;
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return KubbEmptyState(
      title: l.achievementsEmptyTitle,
      body: l.achievementsEmptyBody,
      cta: KubbButton(
        variant: KubbButtonVariant.primary,
        onPressed: () => context.push('/training/sniper/config'),
        child: Text(l.achievementsEmptyCta),
      ),
    );
  }
}

class _ListBody extends StatelessWidget {
  const _ListBody({
    required this.earned,
    required this.locked,
    required this.l,
    required this.tokens,
  });

  final List<AchievementBadge> earned;
  final List<AchievementBadge> locked;
  final AppLocalizations l;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space5,
        KubbTokens.space4,
        KubbTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (earned.isNotEmpty) ...[
            _SectionHeader(label: l.achievementsSectionEarned),
            const SizedBox(height: KubbTokens.space2),
            for (final badge in earned) ...[
              _BadgeCard(
                badge: badge,
                statusChip: KubbChip(
                  tone: KubbChipTone.hit,
                  icon: LucideIcons.check,
                  label: badge.earnedLabel ?? l.achievementsSectionEarned,
                ),
                glyphTone: _GlyphTone.earned,
              ),
              const SizedBox(height: KubbTokens.space3),
            ],
            const SizedBox(height: KubbTokens.space4),
          ],
          if (locked.isNotEmpty) ...[
            _SectionHeader(label: l.achievementsSectionOpen),
            const SizedBox(height: KubbTokens.space2),
            for (final badge in locked) ...[
              _BadgeCard(
                badge: badge,
                statusChip: KubbChip(
                  tone: KubbChipTone.neutral,
                  icon: LucideIcons.lock,
                  label: l.achievementsLockedChip(
                    badge.trigger ?? badge.title,
                  ),
                ),
                glyphTone: _GlyphTone.locked,
              ),
              const SizedBox(height: KubbTokens.space3),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space1),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: tokens.fgMuted,
            ),
      ),
    );
  }
}

/// Tone-Switch fuer die Glyph-Vignette in der Badge-Card.
enum _GlyphTone { earned, locked }

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({
    required this.badge,
    required this.statusChip,
    required this.glyphTone,
  });

  final AchievementBadge badge;
  final Widget statusChip;
  final _GlyphTone glyphTone;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    // Glyph-Vignette: 48 dp Container, Tint je nach Status. Sobald
    // Designer Brand-SVGs liefert wird der `Icon`-Slot durch ein
    // SvgPicture/CustomPainter ersetzt — die 48-dp-Aussenflaeche und
    // die Card-Komposition bleiben stabil.
    final glyphBg = glyphTone == _GlyphTone.earned
        ? KubbTokens.wood100
        : tokens.bgSunken;
    final glyphFg = glyphTone == _GlyphTone.earned
        ? KubbTokens.wood700
        : tokens.fgMuted;

    return Container(
      key: ValueKey('achievements.badge.${badge.id}'),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: glyphBg,
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
            alignment: Alignment.center,
            child: Icon(badge.glyph, size: 24, color: glyphFg),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.title,
                  style: textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: tokens.fgMuted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: KubbTokens.space2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: statusChip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
