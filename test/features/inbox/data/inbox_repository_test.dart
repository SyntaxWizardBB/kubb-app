import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/data/inbox_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../_helpers/sqlite_open.dart';

/// Hydrate-on-open verification: when the drift cache has rows for the
/// user, [InboxRepository.loadFromCache] and [InboxRepository.watchForUser]
/// must satisfy the inbox screen without ever hitting Supabase.
///
/// The Supabase client is wired through a Mock that fails the test on
/// any access — the assertion is structural, not just behavioural.
class _MockSupabaseClient extends Mock implements SupabaseClient {}

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

  Future<void> seedFive(String userId) async {
    final t0 = DateTime.utc(2026, 5, 28, 9);
    final companions = List.generate(5, (i) {
      return InboxMessagesCompanion(
        id: Value('msg-$i'),
        userId: Value(userId),
        kind: const Value('notice'),
        bodyJson: Value(jsonEncode(<String, dynamic>{
          'subject': 'Subject $i',
          'body': 'Body $i',
        })),
        createdAt:
            Value(t0.add(Duration(minutes: i)).millisecondsSinceEpoch),
      );
    });
    await db.inboxMessagesDao.upsertMany(companions);
  }

  test('loadFromCache() rehydrates five messages without touching Supabase',
      () async {
    await seedFive('user-1');

    final hydrated = await repo.loadFromCache('user-1');

    expect(hydrated, hasLength(5));
    // Newest-first ordering mirrors the production read.
    expect(hydrated.map((m) => m.id), [
      'msg-4',
      'msg-3',
      'msg-2',
      'msg-1',
      'msg-0',
    ]);
    expect(hydrated.first.subject, 'Subject 4');
    expect(hydrated.first.body, 'Body 4');
    expect(hydrated.first.kind, InboxMessageKind.notice);
    // No call may have hit the Supabase client during the hydrate.
    verifyZeroInteractions(client);
  });

  test(
      'watchForUser() emits the cached snapshot immediately without '
      'a Supabase call', () async {
    await seedFive('user-1');

    final first = await repo.watchForUser('user-1').first;
    expect(first.map((m) => m.id), [
      'msg-4',
      'msg-3',
      'msg-2',
      'msg-1',
      'msg-0',
    ]);
    verifyZeroInteractions(client);
  });

  test('watchForUser() ignores cached rows owned by a different user',
      () async {
    await seedFive('user-1');
    await db.inboxMessagesDao.upsertMany([
      InboxMessagesCompanion(
        id: const Value('foreign'),
        userId: const Value('user-2'),
        kind: const Value('notice'),
        bodyJson: Value(jsonEncode(<String, dynamic>{
          'subject': 'other',
          'body': 'other',
        })),
        createdAt: Value(
          DateTime.utc(2099).millisecondsSinceEpoch,
        ),
      ),
    ]);

    final first = await repo.watchForUser('user-1').first;
    expect(first.any((m) => m.id == 'foreign'), isFalse);
    expect(first, hasLength(5));
  });

  test('loadFromCache() decodes action_payload and reply_payload roundtrips',
      () async {
    await db.inboxMessagesDao.upsertMany([
      InboxMessagesCompanion(
        id: const Value('msg-x'),
        userId: const Value('user-1'),
        kind: const Value('verification_request'),
        bodyJson: Value(jsonEncode(<String, dynamic>{
          'subject': 'Verify',
          'body': 'Please confirm',
          'action_payload': <String, dynamic>{
            'kind': 'friend_request',
            'from_user_id': 'friend-1',
          },
          'reply_payload': <String, dynamic>{'answer': 'accept'},
        })),
        createdAt: Value(
          DateTime.utc(2026, 5, 28).millisecondsSinceEpoch,
        ),
        readAt: Value(
          DateTime.utc(2026, 5, 28, 10).millisecondsSinceEpoch,
        ),
        repliedAt: Value(
          DateTime.utc(2026, 5, 28, 11).millisecondsSinceEpoch,
        ),
      ),
    ]);

    final hydrated = await repo.loadFromCache('user-1');
    expect(hydrated, hasLength(1));
    final msg = hydrated.single;
    expect(msg.kind, InboxMessageKind.verificationRequest);
    expect(msg.subject, 'Verify');
    expect(msg.actionPayload?['kind'], 'friend_request');
    expect(msg.actionPayload?['from_user_id'], 'friend-1');
    expect(msg.replyPayload?['answer'], 'accept');
    expect(msg.readAt, isNotNull);
    expect(msg.repliedAt, isNotNull);
    expect(msg.isUnread, isFalse);
  });

  test(
      'C4: cached shoot-out row routes to tournamentShootout, not notice '
      '(action_payload disambiguation through the cache path)', () async {
    // Shoot-out rows ship on the generic 'tournament_round' wire kind and are
    // tagged via action_payload['kind'] == 'shootout'. The offline-first cache
    // path must pass the payload to fromWire, otherwise the CTA never renders.
    await db.inboxMessagesDao.upsertMany([
      InboxMessagesCompanion(
        id: const Value('shootout-1'),
        userId: const Value('user-1'),
        kind: const Value('tournament_round'),
        bodyJson: Value(jsonEncode(<String, dynamic>{
          'subject': 'Shoot-Out nötig',
          'body': 'Tragt den Sieger ein.',
          'action_payload': <String, dynamic>{
            'tournament_id': 't-1',
            'kind': 'shootout',
            'start_rank': 2,
          },
        })),
        createdAt: Value(DateTime.utc(2026, 5, 28, 10).millisecondsSinceEpoch),
      ),
    ]);

    final hydrated = await repo.loadFromCache('user-1');
    expect(hydrated, hasLength(1));
    expect(hydrated.single.kind, InboxMessageKind.tournamentShootout);
    expect(hydrated.single.actionPayload?['start_rank'], 2);
  });

  test(
      'N1/C2: cached tournament_finished row hydrates to tournamentFinished '
      'with the round-time body intact (cache round-trip)', () async {
    // The server (and _kindToWire) emit the distinct 'tournament_finished'
    // wire kind. The offline-first cache path must map it back to the typed
    // kind and preserve the configured round time the server put in the body.
    await db.inboxMessagesDao.upsertMany([
      InboxMessagesCompanion(
        id: const Value('finished-1'),
        userId: const Value('user-1'),
        kind: const Value('tournament_finished'),
        bodyJson: Value(jsonEncode(<String, dynamic>{
          'subject': 'Turnier beendet',
          'body': 'Turnier "ProbeCup" ist beendet. Danke fürs Mitspielen! '
              '— Spielzeit 30 min',
          'action_payload': <String, dynamic>{
            'tournament_id': 't-1',
            'phase': 'finished',
          },
        })),
        createdAt: Value(DateTime.utc(2026, 6, 6, 10).millisecondsSinceEpoch),
      ),
    ]);

    final hydrated = await repo.loadFromCache('user-1');
    expect(hydrated, hasLength(1));
    expect(hydrated.single.kind, InboxMessageKind.tournamentFinished);
    expect(hydrated.single.body, contains('Spielzeit 30 min'));
    expect(hydrated.single.actionPayload?['phase'], 'finished');
  });
}
