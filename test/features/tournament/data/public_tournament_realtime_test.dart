import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_realtime.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Tests fuer den anon-Realtime-Pfad (W3-T5 / Sprint-A T6-Followup).
///
/// Verifiziert drei Eigenschaften, die der Migration
/// `20260601000031_public_tournament_realtime.sql` versprochen werden:
///
///   1. Decoder akzeptiert die kuratierten `match_status`- und
///      `proposal_created`-Payloads (positive Pfade).
///   2. `assertPayloadColumnsWhitelisted` ist eine echte Privacy-
///      Bremse — der Decoder feuert auf `created_by`, `user_id`,
///      `submitter_user_id`, `email`, `nickname`.
///   3. Ein Fake-Subscriber zieht denselben Whitelist-Pfad, den der
///      `SupabasePublicTournamentRealtime`-Adapter im Debug-Mode auch
///      durchschiebt — Acceptance "Kein PII im Topic-Payload" aus dem
///      Worker-Briefing.

class _FakeRealtime implements PublicTournamentRealtime {
  _FakeRealtime();

  final Map<String, StreamController<PublicTournamentEvent>> _topics =
      <String, StreamController<PublicTournamentEvent>>{};

  @override
  Stream<PublicTournamentEvent> watch(TournamentId tournamentId) {
    final topic = publicTournamentRealtimeTopic(tournamentId);
    final controller = _topics.putIfAbsent(
      topic,
      StreamController<PublicTournamentEvent>.broadcast,
    );
    return controller.stream;
  }

  void push(TournamentId tournamentId, Map<String, dynamic> payload) {
    // Spiegel des Adapter-Debug-Pfads: pruefe Whitelist, decoder, emit.
    assertPayloadColumnsWhitelisted(payload);
    final event = PublicTournamentEvent.fromPayload(payload);
    if (event == null) return;
    final topic = publicTournamentRealtimeTopic(tournamentId);
    _topics[topic]?.add(event);
  }
}

Map<String, dynamic> _matchStatusPayload({
  String matchId = 'm-1',
  String tournamentId = 't-1',
  String status = 'finalized',
  String? previousStatus = 'awaiting_results',
}) {
  return <String, dynamic>{
    'event_type': 'match_status',
    'match_id': matchId,
    'tournament_id': tournamentId,
    'round_number': 1,
    'match_number_in_round': 2,
    'status': status,
    'previous_status': previousStatus,
    'consensus_round': 1,
    'participant_a_id': 'p-a',
    'participant_b_id': 'p-b',
    'winner_participant_id': 'p-a',
    'final_score_a': 6,
    'final_score_b': 4,
    'phase': 'group',
    'bracket_position': null,
    'started_at': '2026-05-29T10:00:00.000Z',
    'completed_at': '2026-05-29T10:20:00.000Z',
    'emitted_at': '2026-05-29T10:20:01.000Z',
  };
}

Map<String, dynamic> _proposalPayload({
  String matchId = 'm-1',
  String tournamentId = 't-1',
}) {
  return <String, dynamic>{
    'event_type': 'proposal_created',
    'match_id': matchId,
    'tournament_id': tournamentId,
    'consensus_round': 1,
    'set_number': 2,
    'emitted_at': '2026-05-29T10:21:00.000Z',
  };
}

void main() {
  group('publicTournamentRealtimeTopic', () {
    test('uses the SQL-side namespace `public_tournament_events:<id>`', () {
      expect(
        publicTournamentRealtimeTopic(const TournamentId('abc-123')),
        'public_tournament_events:abc-123',
      );
    });
  });

  group('PublicTournamentEvent.fromPayload', () {
    test('decodes a match_status payload', () {
      final event = PublicTournamentEvent.fromPayload(_matchStatusPayload());
      expect(event, isNotNull);
      expect(event!.type, PublicTournamentEventType.matchStatus);
      expect(event.tournamentId.value, 't-1');
      expect(event.matchId.value, 'm-1');
      expect(event.status, 'finalized');
      expect(event.previousStatus, 'awaiting_results');
      expect(event.consensusRound, 1);
    });

    test('decodes a proposal_created payload', () {
      final event = PublicTournamentEvent.fromPayload(_proposalPayload());
      expect(event, isNotNull);
      expect(event!.type, PublicTournamentEventType.proposalCreated);
      expect(event.consensusRound, 1);
      expect(event.setNumber, 2);
    });

    test('returns null on unknown event_type', () {
      final event = PublicTournamentEvent.fromPayload(<String, dynamic>{
        'event_type': 'made_up',
        'match_id': 'm-1',
        'tournament_id': 't-1',
      });
      expect(event, isNull);
    });

    test('returns null when required ids missing', () {
      final event = PublicTournamentEvent.fromPayload(<String, dynamic>{
        'event_type': 'match_status',
      });
      expect(event, isNull);
    });
  });

  group('assertPayloadColumnsWhitelisted (Privacy-Anker)', () {
    test('accepts a strictly whitelisted match_status payload', () {
      expect(
        () => assertPayloadColumnsWhitelisted(_matchStatusPayload()),
        returnsNormally,
      );
    });

    test('accepts a strictly whitelisted proposal_created payload', () {
      expect(
        () => assertPayloadColumnsWhitelisted(_proposalPayload()),
        returnsNormally,
      );
    });

    test('throws when forbidden columns leak (created_by)', () {
      final payload = _matchStatusPayload()
        ..['created_by'] = 'leaked-user-id';
      expect(
        () => assertPayloadColumnsWhitelisted(payload),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('created_by'),
        )),
      );
    });

    test('throws when forbidden columns leak (submitter_user_id)', () {
      final payload = _proposalPayload()
        ..['submitter_user_id'] = 'leaked-user-id';
      expect(
        () => assertPayloadColumnsWhitelisted(payload),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('submitter_user_id'),
        )),
      );
    });

    test('throws when forbidden columns leak (user_id, email, nickname)', () {
      for (final forbidden in const ['user_id', 'email', 'nickname']) {
        final payload = _matchStatusPayload()..[forbidden] = 'leak';
        expect(
          () => assertPayloadColumnsWhitelisted(payload),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(forbidden),
          )),
          reason: '$forbidden must be rejected',
        );
      }
    });

    test('throws on any non-whitelisted column (drift detection)', () {
      final payload = _matchStatusPayload()..['some_new_column'] = 'x';
      expect(
        () => assertPayloadColumnsWhitelisted(payload),
        throwsA(isA<StateError>()),
        reason:
            'unbekannte Keys muessen den Trigger-Patcher zur Whitelist-Pflege zwingen',
      );
    });
  });

  group('fake subscriber pipeline (end-to-end Privacy-Pruefung)', () {
    test('delivers decoded events through the watch() stream', () async {
      final fake = _FakeRealtime();
      const tid = TournamentId('t-1');
      final seen = <PublicTournamentEvent>[];
      final sub = fake.watch(tid).listen(seen.add);
      // Subscribe-Microtask einhaengen, dann emit.
      await Future<void>.delayed(Duration.zero);
      fake
        ..push(tid, _matchStatusPayload())
        ..push(tid, _proposalPayload());
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen, hasLength(2));
      expect(seen[0].type, PublicTournamentEventType.matchStatus);
      expect(seen[1].type, PublicTournamentEventType.proposalCreated);
    });

    test('a leaky push blows up before reaching subscribers', () async {
      final fake = _FakeRealtime();
      const tid = TournamentId('t-1');
      final seen = <PublicTournamentEvent>[];
      final sub = fake.watch(tid).listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      expect(
        () => fake.push(tid, _matchStatusPayload()
          ..['created_by'] = 'should-not-be-here'),
        throwsA(isA<StateError>()),
      );
      // Kein Event erreicht den Subscriber.
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      await sub.cancel();
    });
  });
}
