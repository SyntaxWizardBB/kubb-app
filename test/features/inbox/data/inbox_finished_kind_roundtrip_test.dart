import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/data/inbox_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../_helpers/sqlite_open.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Stubs the `.from().select().filter().order()` chain `InboxRepository.list`
/// uses, resolving the final await to a fixed list of rows. Every chain method
/// returns `this`; only `then` resolves the future.
class _FakeFilterBuilder extends Mock
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakeFilterBuilder(this._rows);
  final List<Map<String, dynamic>> _rows;

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) =>
      this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> filter(
    String column,
    String operator,
    Object? value,
  ) =>
      this;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) {
    return Future<List<Map<String, dynamic>>>.value(_rows)
        .then(onValue, onError: onError);
  }
}

/// N1/C2: round-trip through the cache write path. `refreshFromRemote` decodes
/// the remote `tournament_finished` row (fromWire) and re-encodes it into the
/// drift cache via `_kindToWire`; reading the raw cache row back proves the
/// wire kind survives unchanged ('tournament_finished'), and `loadFromCache`
/// proves it maps back to the typed kind.
void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late _MockSupabaseClient client;
  late InboxRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    client = _MockSupabaseClient();
    repo = InboxRepository(client: client, dao: db.inboxMessagesDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('tournament_finished survives the remote -> cache -> typed round-trip',
      () async {
    final row = <String, dynamic>{
      'id': 'fin-rt-1',
      'kind': 'tournament_finished',
      'subject': 'Turnier beendet',
      'body': 'Turnier "ProbeCup" ist beendet. Danke fürs Mitspielen! '
          '— Spielzeit 30 min',
      'sent_at': '2026-06-06T10:00:00Z',
      'action_payload': <String, dynamic>{
        'tournament_id': 't-1',
        'phase': 'finished',
      },
    };

    final qb = _MockQueryBuilder();
    final builder = _FakeFilterBuilder([row]);
    when(() => client.from('user_inbox_messages')).thenAnswer((_) => qb);
    when(qb.select).thenAnswer((_) => builder);

    final fetched = await repo.refreshFromRemote('user-1');
    expect(fetched.single.kind, InboxMessageKind.tournamentFinished);

    // Raw cache row: the persisted wire kind is exactly 'tournament_finished'
    // (this is what _kindToWire produced) — proving the round-trip stability.
    final cached = await db.inboxMessagesDao.listByUser('user-1');
    expect(cached.single.kind, 'tournament_finished');
    final cachedBody =
        jsonDecode(cached.single.bodyJson) as Map<String, dynamic>;
    expect(cachedBody['body'], contains('Spielzeit 30 min'));

    // And it hydrates back to the typed kind through the cache read path.
    final hydrated = await repo.loadFromCache('user-1');
    expect(hydrated.single.kind, InboxMessageKind.tournamentFinished);
  });
}
