import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _StubRemote implements TournamentRemote {
  _StubRemote(this._brackets);

  final Map<String, Bracket> _brackets;
  final List<String> calls = <String>[];

  @override
  Future<Bracket> getBracket(TournamentId tournamentId) async {
    calls.add(tournamentId.value);
    return _brackets[tournamentId.value] ??
        Bracket.singleElimination(const <String>['p1', 'p2']);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container(TournamentRemote remote) {
  return ProviderContainer(
    overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
  );
}

void main() {
  group('tournamentBracketProvider', () {
    test('exposes Bracket value after fetch', () async {
      final bracket =
          Bracket.singleElimination(const <String>['a', 'b', 'c', 'd']);
      final remote = _StubRemote(<String, Bracket>{'t-1': bracket});
      final c = _container(remote);
      addTearDown(c.dispose);

      final result = await c
          .read(tournamentBracketProvider(const TournamentId('t-1')).future);

      expect(result, equals(bracket));
      expect(remote.calls, <String>['t-1']);
    });

    test('family fires anew when tournamentId changes', () async {
      final b1 = Bracket.singleElimination(const <String>['a', 'b']);
      final b2 = Bracket.singleElimination(const <String>['x', 'y', 'z', 'w']);
      final remote = _StubRemote(<String, Bracket>{'t-1': b1, 't-2': b2});
      final c = _container(remote);
      addTearDown(c.dispose);

      final r1 = await c
          .read(tournamentBracketProvider(const TournamentId('t-1')).future);
      final r2 = await c
          .read(tournamentBracketProvider(const TournamentId('t-2')).future);

      expect(r1, equals(b1));
      expect(r2, equals(b2));
      expect(remote.calls, <String>['t-1', 't-2']);
    });
  });
}
