import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/achievements/data/achievements_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Static catalog handle. A `Provider` (not a top-level const) so call
/// sites can override it in tests / story-mode without reaching into
/// the [BadgeCatalog] symbol.
final badgeCatalogProvider = Provider<List<Badge>>((ref) {
  return BadgeCatalog.all;
});

/// Live list of unlocks for the given user, sourced from the
/// repository's broadcast stream. Used by the achievements screen.
///
/// ADR-0029 transport decision (P8): badge unlocks are computed and
/// persisted locally (drift) from the user's own activity — there is no
/// cross-device fan-out, so this stays **drift-only** and is intentionally
/// NOT promoted to a Broadcast/CDC realtime channel. Should achievements
/// ever gain a server-authored, cross-device unlock path, the transport
/// rule applies (Broadcast for derived fan-out events).
// Riverpod's family-provider type names are not part of the public API,
// so we suppress the lint here and rely on the generic args for inference.
// ignore: specify_nonobvious_property_types
final unlockedBadgesProvider =
    StreamProvider.family<List<BadgeUnlock>, UserId>((ref, user) {
  return ref.watch(achievementsRepositoryProvider).watchUnlocksFor(user);
});
