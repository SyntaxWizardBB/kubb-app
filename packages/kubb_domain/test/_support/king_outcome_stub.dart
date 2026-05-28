// Temporary stub specifying the `KingOutcome` sealed class API that
// W2-T3 will ship in `packages/kubb_domain/lib/src/tournament/king_outcome.dart`.
// Delete this file when the real implementation lands and switch the
// test imports to `package:kubb_domain/kubb_domain.dart`.
import 'package:kubb_domain/kubb_domain.dart';
import 'package:meta/meta.dart';

/// What happened to the King in one EKC set. Three variants:
/// - [KingHitBy]: the king fell, scored by a known participant.
/// - [KingMissed]: the king is still standing, set ended on a regular win.
/// - [KingTimedOut]: the set timer ran out without a king-hit; the set
///   does not credit any king-points to either team.
@immutable
sealed class KingOutcome {
  const KingOutcome();
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
  bool operator ==(Object other) => identical(this, other) || other is KingMissed;

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
