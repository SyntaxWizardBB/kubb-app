import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  group('KoPhaseConfig', () {
    test('it throws ArgumentError when qualifierCount = 1 (U2: need final)',
        () {
      expect(
        () => KoPhaseConfig(qualifierCount: 1, participantCount: 8),
        throwsArgumentError,
      );
    });

    test('it throws ArgumentError when qualifierCount = 0', () {
      expect(
        () => KoPhaseConfig(qualifierCount: 0, participantCount: 8),
        throwsArgumentError,
      );
    });

    Glados2(any.intInRange(2, 65), any.intInRange(2, 65))
        .test('it throws when qualifierCount > participantCount', (q, p) {
      if (q <= p) return;
      expect(
        () => KoPhaseConfig(qualifierCount: q, participantCount: p),
        throwsArgumentError,
      );
    });

    Glados2(any.intInRange(2, 65), any.intInRange(2, 65))
        .test('it constructs and applies defaults for valid ranges', (a, b) {
      final p = a > b ? a : b;
      final q = a > b ? b : a;
      final cfg = KoPhaseConfig(qualifierCount: q, participantCount: p);
      expect(cfg.qualifierCount, q);
      expect(cfg.participantCount, p);
      expect(cfg.withThirdPlacePlayoff, isFalse);
      expect(cfg.seedingMode, SeedingMode.auto);
    });

    test('it implements value equality on all fields', () {
      final a = KoPhaseConfig(
        qualifierCount: 4,
        participantCount: 8,
        withThirdPlacePlayoff: true,
        seedingMode: SeedingMode.manual,
      );
      final b = KoPhaseConfig(
        qualifierCount: 4,
        participantCount: 8,
        withThirdPlacePlayoff: true,
        seedingMode: SeedingMode.manual,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('it distinguishes instances that differ in any field', () {
      final base = KoPhaseConfig(qualifierCount: 4, participantCount: 8);
      expect(
        base == KoPhaseConfig(qualifierCount: 4, participantCount: 9),
        isFalse,
      );
      expect(
        base ==
            KoPhaseConfig(
              qualifierCount: 4,
              participantCount: 8,
              withThirdPlacePlayoff: true,
            ),
        isFalse,
      );
    });
  });
}
