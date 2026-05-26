import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/tournament/bracket_layout.dart';

import '../_support/tournament_generators.dart';

bool _overlap(BoxRect a, BoxRect b) {
  return a.x < b.right &&
      b.x < a.right &&
      a.y < b.bottom &&
      b.y < a.bottom;
}

void main() {
  group('BracketLayout.compute', () {
    Glados<List<String>>(any.participantIds(max: 64))
        .test('every box has width > 0 and height >= touchMin', (ids) {
      final layout =
          BracketLayout.compute(Bracket.singleElimination(ids));
      expect(layout.rects, isNotEmpty);
      for (final rect in layout.rects.values) {
        expect(rect.width, greaterThan(0));
        expect(rect.height, greaterThanOrEqualTo(touchMin));
      }
    });

    Glados<List<String>>(any.participantIds(max: 64))
        .test('no two boxes overlap', (ids) {
      final layout =
          BracketLayout.compute(Bracket.singleElimination(ids));
      final entries = layout.rects.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          expect(
            _overlap(entries[i].value, entries[j].value),
            isFalse,
            reason: '${entries[i].key} overlaps ${entries[j].key}',
          );
        }
      }
    });

    Glados<List<String>>(any.participantIds(max: 64))
        .test('is deterministic across repeated invocations', (ids) {
      final bracket = Bracket.singleElimination(ids);
      final a = BracketLayout.compute(bracket);
      final b = BracketLayout.compute(bracket);
      expect(a.rects, equals(b.rects));
    });

    test('third-place box sits in its own side-branch right of the final',
        () {
      final bracket = Bracket.singleElimination(
        List<String>.generate(8, (i) => 'p$i'),
        withThirdPlace: true,
      );
      final layout = BracketLayout.compute(bracket);
      final third = layout.rects['third-place'];
      expect(third, isNotNull, reason: 'third-place box must be present');
      expect(third!.phase, BracketPhase.thirdPlace);
      final finals = layout.rects.entries
          .where((e) => e.value.phase == BracketPhase.final_)
          .toList();
      expect(finals, hasLength(1));
      expect(third.x, greaterThan(finals.single.value.x));
    });

    test('BYE slots remain flagged as isBye in the layout output', () {
      final bracket =
          Bracket.singleElimination(List<String>.generate(5, (i) => 'p$i'))
              as SingleEliminationBracket;
      final byeIndices = <int>[
        for (var i = 0; i < bracket.rounds.first.pairings.length; i++)
          if (bracket.rounds.first.pairings[i].$1.isBye ||
              bracket.rounds.first.pairings[i].$2.isBye)
            i,
      ];
      expect(byeIndices, isNotEmpty);
      final layout = BracketLayout.compute(bracket);
      for (final i in byeIndices) {
        final rect = layout.rects['r1-m$i'];
        expect(rect, isNotNull, reason: 'missing layout box for r1-m$i');
        expect(rect!.isBye, isTrue);
      }
    });
  });
}
