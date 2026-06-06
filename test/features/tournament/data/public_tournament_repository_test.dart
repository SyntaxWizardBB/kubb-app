import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_models.dart';
import 'package:kubb_app/features/tournament/data/public_tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Tests fuer den anon-Spectator-Read-Pfad nach ADR-0026 Strategie A.
///
/// Der echte [SupabasePublicTournamentRepository] geht ueber
/// `SupabaseClient.rpc(...)`. Wir testen die Vertrags-Oberflaeche
/// (Methodensignaturen, Decoder-Verhalten, Null-Pfade) ueber einen
/// Spy-Adapter, der dieselbe abstrakte Klasse implementiert und die
/// gespeicherten RPC-Argumente sowie die Envelopes asserten laesst.
///
/// Die Envelope-Form spiegelt die `public_tournament_get`-RPC aus
/// Migration 20260901000001 (kein `user_id`, kein `created_by`, kein
/// `set_score_proposals`).

class _SpyPublicRepo implements PublicTournamentRepository {
  _SpyPublicRepo({this.detailEnvelope, this.matchEnvelope});

  Map<String, dynamic>? detailEnvelope;
  Map<String, dynamic>? matchEnvelope;

  TournamentId? lastDetailIdArg;
  TournamentMatchId? lastMatchIdArg;

  @override
  Future<PublicTournamentDetail?> getPublicTournamentDetail(
      TournamentId id) async {
    lastDetailIdArg = id;
    final env = detailEnvelope;
    if (env == null) return null;
    return publicTournamentDetailFromEnvelope(env);
  }

  @override
  Future<PublicMatchDetail?> getPublicMatchDetail(
      TournamentMatchId id) async {
    lastMatchIdArg = id;
    final env = matchEnvelope;
    if (env == null) return null;
    return publicMatchDetailFromRow(env);
  }
}

Map<String, dynamic> _publicEnvelope({
  String tid = 't-1',
  String status = 'live',
  List<Map<String, dynamic>>? matches,
  List<Map<String, dynamic>>? roster,
  int participantCount = 2,
}) {
  return <String, dynamic>{
    'tournament': <String, dynamic>{
      'tournament_id': tid,
      'display_name': 'Live Cup',
      'team_size': 1,
      'format': 'round_robin',
      'status': status,
      'match_format_config': <String, dynamic>{'format': 'best_of_1'},
      'started_at': '2026-05-28T10:00:00.000Z',
      'completed_at': null,
    },
    'matches': matches ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'match_id': 'm-1',
            'tournament_id': tid,
            'round_number': 1,
            'match_number_in_round': 1,
            'participant_a_id': 'p-a',
            'participant_b_id': 'p-b',
            'status': 'finalized',
            'consensus_round': 1,
            'started_at': '2026-05-28T10:05:00.000Z',
            'completed_at': '2026-05-28T10:20:00.000Z',
            'winner_participant_id': 'p-a',
            'final_score_a': 6,
            'final_score_b': 2,
            'phase': 'group',
            'bracket_position': null,
          },
        ],
    'roster': roster ??
        <Map<String, dynamic>>[
          <String, dynamic>{
            'slot_id': 's-1',
            'participant_id': 'p-a',
            'slot_index': 1,
            'display_name': 'Alice',
          },
          <String, dynamic>{
            'slot_id': 's-2',
            'participant_id': 'p-b',
            'slot_index': 1,
            'display_name': 'Bob',
          },
        ],
    'participant_count': participantCount,
  };
}

void main() {
  group('publicTournamentDetailFromEnvelope', () {
    test('decodes header, matches, roster and participant_count', () {
      final detail = publicTournamentDetailFromEnvelope(_publicEnvelope());
      expect(detail.tournament.tournamentId.value, 't-1');
      expect(detail.tournament.displayName, 'Live Cup');
      expect(detail.tournament.format, TournamentFormat.roundRobin);
      expect(detail.tournament.status, TournamentStatus.live);
      expect(detail.tournament.teamSize, 1);
      expect(detail.matches, hasLength(1));
      expect(detail.matches.first.matchId.value, 'm-1');
      expect(detail.matches.first.finalScoreA, 6);
      expect(detail.matches.first.status, TournamentMatchStatus.finalized);
      expect(detail.roster, hasLength(2));
      expect(detail.roster.first.displayName, 'Alice');
      expect(detail.participantCount, 2);
    });

    test('displayNameFor resolves participant ids via roster', () {
      final detail = publicTournamentDetailFromEnvelope(_publicEnvelope());
      expect(
          detail.displayNameFor(const TournamentParticipantId('p-a')), 'Alice');
      expect(
          detail.displayNameFor(const TournamentParticipantId('p-b')), 'Bob');
      expect(detail.displayNameFor(null), isNull);
      expect(
          detail.displayNameFor(const TournamentParticipantId('unknown')),
          isNull);
    });

    test('decodes single-participant roster entries with slot_id null', () {
      // CF3 / K08: singles have no roster slot, so public_tournament_get
      // projects slot_id = NULL. The decoder must tolerate the null slot_id
      // and surface the player's nickname instead of crashing the whole
      // spectator screen.
      final env = _publicEnvelope(
        roster: const <Map<String, dynamic>>[
          <String, dynamic>{
            'slot_id': null,
            'participant_id': 'p-a',
            'slot_index': 0,
            'display_name': 'SingleAlice',
          },
        ],
        participantCount: 1,
      );
      final detail = publicTournamentDetailFromEnvelope(env);
      expect(detail.roster, hasLength(1));
      expect(detail.roster.first.slotId, isNull);
      expect(detail.roster.first.displayName, 'SingleAlice');
      expect(
        detail.displayNameFor(const TournamentParticipantId('p-a')),
        'SingleAlice',
      );
    });

    test('tolerates empty matches and roster arrays', () {
      final env = _publicEnvelope(
        matches: const <Map<String, dynamic>>[],
        roster: const <Map<String, dynamic>>[],
        participantCount: 0,
      );
      final detail = publicTournamentDetailFromEnvelope(env);
      expect(detail.matches, isEmpty);
      expect(detail.roster, isEmpty);
      expect(detail.participantCount, 0);
    });
  });

  group('publicMatchDetailFromRow', () {
    test('decodes a finalized match envelope', () {
      final row = <String, dynamic>{
        'match_id': 'm-9',
        'tournament_id': 't-9',
        'round_number': 2,
        'match_number_in_round': 3,
        'participant_a_id': 'p-a',
        'participant_b_id': 'p-b',
        'status': 'finalized',
        'consensus_round': 1,
        'started_at': '2026-05-28T11:00:00.000Z',
        'completed_at': '2026-05-28T11:30:00.000Z',
        'winner_participant_id': 'p-b',
        'final_score_a': 4,
        'final_score_b': 6,
        'phase': 'ko',
        'bracket_position': 2,
      };
      final m = publicMatchDetailFromRow(row);
      expect(m.matchId.value, 'm-9');
      expect(m.roundNumber, 2);
      expect(m.matchNumberInRound, 3);
      expect(m.winnerParticipant?.value, 'p-b');
      expect(m.finalScoreA, 4);
      expect(m.finalScoreB, 6);
      expect(m.phase, 'ko');
      expect(m.bracketPosition, 2);
    });

    test('handles BYE (participantB null) and unfinished score', () {
      final row = <String, dynamic>{
        'match_id': 'm-bye',
        'tournament_id': 't-9',
        'round_number': 1,
        'match_number_in_round': 4,
        'participant_a_id': 'p-a',
        'participant_b_id': null,
        'status': 'scheduled',
        'consensus_round': 1,
        'started_at': null,
        'completed_at': null,
        'winner_participant_id': null,
        'final_score_a': null,
        'final_score_b': null,
        'phase': 'group',
        'bracket_position': null,
      };
      final m = publicMatchDetailFromRow(row);
      expect(m.participantB, isNull);
      expect(m.finalScoreA, isNull);
      expect(m.bracketPosition, isNull);
      expect(m.status, TournamentMatchStatus.scheduled);
    });
  });

  group('PublicTournamentRepository contract', () {
    test('getPublicTournamentDetail passes the tournament id through', () async {
      final spy = _SpyPublicRepo(detailEnvelope: _publicEnvelope(tid: 't-7'));
      final out = await spy
          .getPublicTournamentDetail(const TournamentId('t-7'));
      expect(spy.lastDetailIdArg?.value, 't-7');
      expect(out, isNotNull);
      expect(out!.tournament.tournamentId.value, 't-7');
    });

    test('getPublicTournamentDetail returns null for an empty envelope', () async {
      final spy = _SpyPublicRepo();
      final out = await spy
          .getPublicTournamentDetail(const TournamentId('t-private'));
      expect(spy.lastDetailIdArg?.value, 't-private');
      expect(out, isNull);
    });

    test('getPublicMatchDetail passes the match id through', () async {
      final spy = _SpyPublicRepo(matchEnvelope: <String, dynamic>{
        'match_id': 'm-X',
        'tournament_id': 't-1',
        'round_number': 1,
        'match_number_in_round': 1,
        'participant_a_id': 'p-a',
        'participant_b_id': 'p-b',
        'status': 'scheduled',
        'consensus_round': 1,
        'started_at': null,
        'completed_at': null,
        'winner_participant_id': null,
        'final_score_a': null,
        'final_score_b': null,
        'phase': 'group',
        'bracket_position': null,
      });
      final out =
          await spy.getPublicMatchDetail(const TournamentMatchId('m-X'));
      expect(spy.lastMatchIdArg?.value, 'm-X');
      expect(out, isNotNull);
      expect(out!.matchId.value, 'm-X');
    });

    test('getPublicMatchDetail returns null when RPC has no row', () async {
      final spy = _SpyPublicRepo();
      final out =
          await spy.getPublicMatchDetail(const TournamentMatchId('m-gone'));
      expect(out, isNull);
    });
  });

  group('privacy: public envelope never carries user-bound ids', () {
    test('decoded models expose no user_id / created_by / proposals', () {
      final detail = publicTournamentDetailFromEnvelope(_publicEnvelope());
      // Static-Typ-Garantie ist die eigentliche Aussage — der Decoder
      // kennt diese Felder gar nicht. Wir asserten zusaetzlich, dass
      // typische Privacy-Spalten nicht versehentlich ueber den
      // matchFormatConfig durchsickern.
      expect(detail.tournament.matchFormatConfig.containsKey('user_id'),
          isFalse);
      expect(detail.tournament.matchFormatConfig.containsKey('created_by'),
          isFalse);
    });
  });
}
