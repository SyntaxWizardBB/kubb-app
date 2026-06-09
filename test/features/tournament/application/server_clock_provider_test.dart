// ADR-0031 Block A3c — serverClockOffsetProvider tests.
//
// The provider does a SINGLE app_server_now() sync and exposes the skew
// offset = serverNow - DateTime.now().toUtc(); it must NOT poll
// (no Timer.periodic, ADR-0029). serverCorrectedNow(offset) is the pure
// helper the 1s UI ticker uses.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/server_clock_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Stub remote whose [fetchServerNow] returns a controllable instant and
/// counts its calls (to assert a single, non-polling sync).
class _StubRemote implements TournamentRemote {
  _StubRemote(this.serverNow);

  final DateTime serverNow;
  int fetchServerNowCalls = 0;

  @override
  Future<DateTime> fetchServerNow() async {
    fetchServerNowCalls++;
    return serverNow;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not exercised by this test');
}

ProviderContainer _container(TournamentRemote remote) {
  final c = ProviderContainer(
    overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('serverClockOffsetProvider', () {
    test('offset ~= serverNow - local now, computed from one RPC', () async {
      // Server is ~5 minutes ahead of the local clock.
      final serverNow = DateTime.now().toUtc().add(const Duration(minutes: 5));
      final remote = _StubRemote(serverNow);
      final c = _container(remote);

      final offset = await c.read(serverClockOffsetProvider.future);

      // The captured local now sits between the two reads, so the offset is
      // close to 5 min (allow a generous tolerance for execution time).
      expect(offset.inSeconds, closeTo(const Duration(minutes: 5).inSeconds, 5));
      // Single sync — no polling.
      expect(remote.fetchServerNowCalls, 1);
    });

    test('a behind-server clock yields a negative offset', () async {
      final serverNow =
          DateTime.now().toUtc().subtract(const Duration(seconds: 30));
      final remote = _StubRemote(serverNow);
      final c = _container(remote);

      final offset = await c.read(serverClockOffsetProvider.future);
      expect(offset.isNegative, isTrue);
      expect(offset.inSeconds, closeTo(-30, 5));
    });

    test('serverCorrectedNow adds the offset to the live UTC clock', () {
      const offset = Duration(seconds: 90);
      final before = DateTime.now().toUtc().add(offset);
      final corrected = serverCorrectedNow(offset);
      final after = DateTime.now().toUtc().add(offset);
      // corrected lies within the [before, after] bracket around the call.
      expect(corrected.isBefore(before.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(corrected.isAfter(after.add(const Duration(seconds: 1))), isFalse);
    });

    test('the provider source contains no Timer.periodic poll', () {
      // Guard against re-introducing a per-second poll (ADR-0029): the
      // provider must stay a one-shot FutureProvider.
      final src = File(
        'lib/features/tournament/application/server_clock_provider.dart',
      ).readAsStringSync();
      expect(src.contains('Timer.periodic'), isFalse);
      expect(src.contains('FutureProvider<Duration>'), isTrue);
    });
  });
}
