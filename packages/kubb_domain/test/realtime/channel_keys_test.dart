import 'package:kubb_domain/src/realtime/channel_keys.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';
import 'package:kubb_domain/src/values/ids.dart';
import 'package:test/test.dart';

void main() {
  group('channel_keys golden strings', () {
    test('inboxRealtimeChannelKey', () {
      expect(
        inboxRealtimeChannelKey(const UserId('u1')),
        equals('user_inbox_messages:user_id=u1'),
      );
    });

    test('teamRealtimeChannelKey', () {
      expect(
        teamRealtimeChannelKey(const TeamId('tm1')),
        equals('team_memberships:team_id=tm1'),
      );
    });

    test('matchRealtimeChannelKey (public.matches, id-scoped)', () {
      expect(
        matchRealtimeChannelKey(const MatchId('m1')),
        equals('matches:id=m1'),
      );
    });

    test('myTeamsRealtimeChannelKey', () {
      expect(
        myTeamsRealtimeChannelKey(const UserId('u1')),
        equals('team_memberships:user_id=u1'),
      );
    });

    test('myTournamentsRealtimeChannelKey', () {
      expect(
        myTournamentsRealtimeChannelKey(const UserId('u1')),
        equals('tournament_participants:user_id=u1'),
      );
    });

    test('friendsRealtimeChannelKey', () {
      expect(
        friendsRealtimeChannelKey(const UserId('u1')),
        equals('friend_edges:owner_user_id=u1'),
      );
    });

    test('tournamentRealtimeChannelKey', () {
      expect(
        tournamentRealtimeChannelKey(const TournamentId('t1')),
        equals('tournament_matches:tournament_id=t1'),
      );
    });

    test('tournamentBroadcastTopic', () {
      expect(
        tournamentBroadcastTopic(const TournamentId('t1')),
        equals('public_tournament_events:t1'),
      );
    });

    test('publicTournamentRealtimeTopic deprecated alias delegates', () {
      // Intentionally exercises the deprecated alias to pin its delegation
      // to tournamentBroadcastTopic until P0b removes the call-sites.
      // ignore: deprecated_member_use_from_same_package
      final aliased = publicTournamentRealtimeTopic(const TournamentId('t1'));
      expect(
        aliased,
        equals(tournamentBroadcastTopic(const TournamentId('t1'))),
      );
    });
  });

  group('cross-test: builder == _keyFor form == fakeRealtimeChannelKey', () {
    test('tournamentRealtimeChannelKey round-trips all three forms', () {
      const id = TournamentId('t1');

      final builder = tournamentRealtimeChannelKey(id);

      // _keyFor form from lib/core/data/realtime/supabase_realtime_channel.dart
      // (`'$table:$column=$value'`).
      const table = 'tournament_matches';
      const column = 'tournament_id';
      final keyForForm = '$table:$column=${id.value}';

      final fakeForm = fakeRealtimeChannelKey(
        table: table,
        filterColumn: column,
        filterValue: id.value,
      );

      expect(builder, equals(keyForForm));
      expect(builder, equals(fakeForm));
      expect(keyForForm, equals(fakeForm));
    });
  });
}
