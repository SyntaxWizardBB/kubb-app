import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/stage_tiebreak_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  group('StageTiebreakRepository.fetchMethods', () {
    test('maps each stage node to its configured KO tiebreak method', () async {
      final repo = StageTiebreakRepository.withSelect((tid) async {
        expect(tid, 't-1');
        return <dynamic>[
          <String, dynamic>{
            'node_id': 'cup',
            'config': <String, Object?>{
              'ko_tiebreak_method': 'mighty_finisher_shootout',
            },
          },
          <String, dynamic>{
            'node_id': 'side',
            'config': <String, Object?>{
              'ko_tiebreak_method': 'classic_kingtoss_removal',
            },
          },
        ];
      });

      final map = await repo.fetchMethods(const TournamentId('t-1'));
      expect(map['cup'], KoTiebreakMethod.mightyFinisherShootout);
      expect(map['side'], KoTiebreakMethod.classicKingtossRemoval);
    });

    test('omits nodes without a method and tolerates malformed rows', () async {
      final repo = StageTiebreakRepository.withSelect((_) async => <dynamic>[
            // No ko_tiebreak_method → omitted.
            <String, dynamic>{
              'node_id': 'groups',
              'config': <String, Object?>{'groupCount': 2},
            },
            // Unknown wire value → omitted (tolerant).
            <String, dynamic>{
              'node_id': 'bad',
              'config': <String, Object?>{'ko_tiebreak_method': 'nope'},
            },
            // Missing node_id / non-map config → skipped, no throw.
            <String, dynamic>{'node_id': null, 'config': null},
          ]);

      final map = await repo.fetchMethods(const TournamentId('t-2'));
      expect(map, isEmpty);
    });
  });
}
