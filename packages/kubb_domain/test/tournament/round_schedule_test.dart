// ADR-0031 Block A3c — domain tests for the round-schedule value object and
// the two new TournamentRemote port methods (fetchServerNow /
// watchRoundSchedule) against a pure-Dart stub.
//
// The explicit `null` arguments below contrast the classic path against a
// stage row / a non-paused row — that is intentional.
// ignore_for_file: avoid_redundant_argument_values
import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

TournamentRoundScheduleRef _ref({
  String? stageNodeId,
  RoundStatus status = RoundStatus.published,
  int? tiebreakAfterSeconds = 120,
  DateTime? pausedAt,
  int pausedAccumSeconds = 0,
}) {
  final published = DateTime.utc(2026, 6, 1, 12);
  return TournamentRoundScheduleRef(
    tournamentId: const TournamentId('t1'),
    stageNodeId: stageNodeId,
    roundNumber: 1,
    phase: 'group',
    status: status,
    publishedAt: published,
    startsAt: published.add(const Duration(seconds: 300)),
    endsAt: published.add(const Duration(seconds: 2100)),
    breakSeconds: 300,
    matchSeconds: 1800,
    tiebreakAfterSeconds: tiebreakAfterSeconds,
    pausedAt: pausedAt,
    pausedAccumSeconds: pausedAccumSeconds,
  );
}

/// Pure-Dart stub of the port — only the two new timed-runner methods are
/// implemented; everything else throws via noSuchMethod (never called here).
class _StubRemote implements TournamentRemote {
  _StubRemote(this.serverNow, this.scheduleStream);

  final DateTime serverNow;
  final Stream<TournamentRoundScheduleRef> scheduleStream;

  @override
  Future<DateTime> fetchServerNow() async => serverNow;

  @override
  Stream<TournamentRoundScheduleRef> watchRoundSchedule(
    TournamentId tournamentId,
  ) =>
      scheduleStream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not exercised by this contract test');
}

void main() {
  group('RoundStatus', () {
    test('has exactly the five server CHECK values', () {
      // Mirrors the CHECK (status IN (...)) of
      // 20261251000000_tournament_round_schedule.sql.
      expect(RoundStatus.values, hasLength(5));
      expect(RoundStatus.values, <RoundStatus>[
        RoundStatus.published,
        RoundStatus.call,
        RoundStatus.running,
        RoundStatus.awaitingResults,
        RoundStatus.completed,
      ]);
    });
  });

  group('TournamentRoundScheduleRef', () {
    test('value equality holds for identical content', () {
      expect(_ref(), equals(_ref()));
      expect(_ref().hashCode, equals(_ref().hashCode));
    });

    test('null stageNodeId (classic path) is distinct from a stage row', () {
      expect(_ref(stageNodeId: null), isNot(equals(_ref(stageNodeId: 'n1'))));
      expect(_ref(stageNodeId: 'n1'), equals(_ref(stageNodeId: 'n1')));
    });

    test('differing status breaks equality', () {
      expect(
        _ref(status: RoundStatus.running),
        isNot(equals(_ref(status: RoundStatus.awaitingResults))),
      );
    });

    test('pause anchors participate in equality', () {
      final paused = DateTime.utc(2026, 6, 1, 12, 10);
      expect(
        _ref(pausedAt: paused, pausedAccumSeconds: 42),
        equals(_ref(pausedAt: paused, pausedAccumSeconds: 42)),
      );
      expect(
        _ref(pausedAt: paused),
        isNot(equals(_ref(pausedAt: null))),
      );
    });

    test('nullable tiebreakAfterSeconds is carried', () {
      expect(_ref(tiebreakAfterSeconds: null).tiebreakAfterSeconds, isNull);
      expect(_ref(tiebreakAfterSeconds: 90).tiebreakAfterSeconds, 90);
    });
  });

  group('TournamentRemote timed-runner contract (stub)', () {
    test('fetchServerNow returns the stubbed server instant', () async {
      final now = DateTime.utc(2026, 6, 1, 12, 34, 56);
      final remote = _StubRemote(now, const Stream.empty());
      expect(await remote.fetchServerNow(), now);
    });

    test('watchRoundSchedule relays the schedule events', () async {
      final emitted = _ref(status: RoundStatus.running);
      final remote = _StubRemote(
        DateTime.utc(2026),
        Stream<TournamentRoundScheduleRef>.fromIterable([emitted]),
      );
      final received =
          await remote.watchRoundSchedule(const TournamentId('t1')).toList();
      expect(received, [emitted]);
    });
  });
}
