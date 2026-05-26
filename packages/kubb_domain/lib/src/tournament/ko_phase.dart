import 'package:meta/meta.dart';

/// Seeding source for the KO bracket (ADR-0017 §4).
enum SeedingMode { auto, manual }

/// Stub for `KoPhaseConfig`. Full implementation in TASK-M2.1-T7.
/// Defaults and validation rules pinned by ADR-0017 §4 / OD-M2-05.
@immutable
final class KoPhaseConfig {
  KoPhaseConfig({
    required this.qualifierCount,
    required this.participantCount,
    this.withThirdPlacePlayoff = false,
    this.seedingMode = SeedingMode.auto,
  }) {
    if (qualifierCount < 2) {
      throw ArgumentError.value(qualifierCount, 'qualifierCount', '>= 2 (U2)');
    }
    if (qualifierCount > participantCount) {
      throw ArgumentError.value(
        qualifierCount,
        'qualifierCount',
        '<= participantCount',
      );
    }
  }

  final int qualifierCount;
  final int participantCount;
  final bool withThirdPlacePlayoff;
  final SeedingMode seedingMode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoPhaseConfig &&
          other.qualifierCount == qualifierCount &&
          other.participantCount == participantCount &&
          other.withThirdPlacePlayoff == withThirdPlacePlayoff &&
          other.seedingMode == seedingMode;

  @override
  int get hashCode => Object.hash(
        qualifierCount,
        participantCount,
        withThirdPlacePlayoff,
        seedingMode,
      );
}
