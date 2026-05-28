import 'package:kubb_domain/src/values/ids.dart';
import 'package:meta/meta.dart';

/// What happened to the King in one EKC set. Three variants:
/// - [KingHitBy]: the king fell, scored by a known participant.
/// - [KingMissed]: the king is still standing, set ended on a regular win.
/// - [KingTimedOut]: the set timer ran out without a king-hit; the set
///   does not credit any king-points to either team and per R11-F-01 the
///   whole set contributes 0:0 to the EKC tally.
@immutable
sealed class KingOutcome {
  const KingOutcome();

  /// Backward-compat constructor used by call sites that still carry the
  /// legacy `kingHitBy: ParticipantId?` shape (UI + server wire are
  /// migrated in Wave 3). `null` is mapped to [KingMissed]; a non-null
  /// id is mapped to [KingHitBy]. The [KingTimedOut] variant cannot be
  /// expressed in the legacy form and must be set explicitly.
  factory KingOutcome.fromLegacy(TournamentParticipantId? kingHitBy) {
    return kingHitBy == null
        ? const KingMissed()
        : KingHitBy(kingHitBy);
  }

  /// Projection back to the legacy nullable-participant shape. Returns
  /// the scoring participant for [KingHitBy] and `null` for [KingMissed]
  /// or [KingTimedOut]. UI call sites that still read `kingHitBy` go
  /// through this getter until Wave 3 migrates them to a tri-toggle.
  TournamentParticipantId? get legacyKingHitBy => switch (this) {
        KingHitBy(:final participantId) => participantId,
        KingMissed() => null,
        KingTimedOut() => null,
      };
}

@immutable
final class KingHitBy extends KingOutcome {
  const KingHitBy(this.participantId);

  final TournamentParticipantId participantId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KingHitBy && other.participantId == participantId;

  @override
  int get hashCode => participantId.hashCode;
}

@immutable
final class KingMissed extends KingOutcome {
  const KingMissed();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KingMissed;

  @override
  int get hashCode => (KingMissed).hashCode;
}

@immutable
final class KingTimedOut extends KingOutcome {
  const KingTimedOut();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KingTimedOut;

  @override
  int get hashCode => (KingTimedOut).hashCode;
}
