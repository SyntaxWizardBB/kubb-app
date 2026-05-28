import 'package:meta/meta.dart';

/// Rarity tier of a badge. Drives visual treatment (frame, glow) once
/// the designer hands over the SVG glyphs; for the foundation pass this
/// is just a categorical label used for grouping/sorting in the UI.
enum BadgeRarity {
  /// Awarded for a low-difficulty milestone (e.g. "100 hits total").
  common,

  /// Awarded for a meaningful grind (e.g. "1000 hits", "10x hit streak").
  rare,

  /// Awarded for top-end achievements (e.g. "Top 100 ELO", "Konstanz-King").
  epic,
}

/// Catalog entry describing a single achievement.
///
/// `Badge` is a pure value object: definitions live in
/// [`badge_catalog.dart`](badge_catalog.dart) and are immutable at runtime.
/// The actual unlock state per user is tracked by [BadgeUnlock] rows.
///
/// `assetKey` is the lookup key for the glyph asset; the SVGs themselves
/// land in Sprint C once the designer ships them. Until then the asset
/// path is a placeholder (`badges/<id>.svg`) so the UI can wire its
/// loader against a stable identifier.
@immutable
class Badge {
  const Badge({
    required this.id,
    required this.displayName,
    required this.description,
    required this.rarity,
    required this.assetKey,
  });

  /// Stable identifier used as PK in the achievements store and as the
  /// link between catalog entry and unlock row. Must be `snake_case`.
  final String id;

  /// Short label rendered in the badge inventory (German, no emojis).
  final String displayName;

  /// One-sentence explanation shown on the badge detail sheet.
  final String description;

  /// Visual tier.
  final BadgeRarity rarity;

  /// Relative asset path (placeholder until designer delivers SVGs).
  final String assetKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Badge &&
          other.id == id &&
          other.displayName == displayName &&
          other.description == description &&
          other.rarity == rarity &&
          other.assetKey == assetKey;

  @override
  int get hashCode =>
      Object.hash(id, displayName, description, rarity, assetKey);

  @override
  String toString() => 'Badge($id)';
}

/// Recorded fact that a user has earned a badge. Persisted (Sprint C)
/// per `(userId, badgeId)` — re-earning is a no-op.
///
/// `sourceSessionId` is optional because not every badge is bound to a
/// training/match session (e.g. "Saisonteilnehmer" comes from a season
/// aggregate, not a single session).
@immutable
class BadgeUnlock {
  const BadgeUnlock({
    required this.userId,
    required this.badgeId,
    required this.unlockedAt,
    this.sourceSessionId,
  });

  final String userId;
  final String badgeId;
  final DateTime unlockedAt;
  final String? sourceSessionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BadgeUnlock &&
          other.userId == userId &&
          other.badgeId == badgeId &&
          other.unlockedAt == unlockedAt &&
          other.sourceSessionId == sourceSessionId;

  @override
  int get hashCode =>
      Object.hash(userId, badgeId, unlockedAt, sourceSessionId);

  @override
  String toString() =>
      'BadgeUnlock(user=$userId, badge=$badgeId, at=$unlockedAt)';
}
