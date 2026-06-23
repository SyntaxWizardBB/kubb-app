// W1-T15 (Spec §2, ADR-0041) — RealtimeCriticality mapping per channel-key.
//
// The criticality tier is a declarative property of the concern/channel-key,
// not an ad-hoc decision at the call-site: the per-tournament match feed
// (active score, live standings, match status/clock) is `critical` — fresh
// data wins over battery. Registration, check-in lists, friends, my-teams,
// my-tournaments and the inbox are `normal` (standard CDC + 30 s fallback).

import 'package:kubb_domain/src/ports/realtime_channel.dart';
import 'package:kubb_domain/src/realtime/channel_keys.dart';
import 'package:kubb_domain/src/values/ids.dart';
import 'package:test/test.dart';

void main() {
  group('criticalityFor', () {
    test('per-tournament match feed is critical', () {
      expect(
        criticalityFor(tournamentRealtimeChannelKey(const TournamentId('t1'))),
        RealtimeCriticality.critical,
      );
    });

    test('my-tournaments (registration/check-in) is normal', () {
      expect(
        criticalityFor(myTournamentsRealtimeChannelKey(const UserId('u1'))),
        RealtimeCriticality.normal,
      );
    });

    test('my-teams is normal', () {
      expect(
        criticalityFor(myTeamsRealtimeChannelKey(const UserId('u1'))),
        RealtimeCriticality.normal,
      );
    });

    test('friends is normal', () {
      expect(
        criticalityFor(friendsRealtimeChannelKey(const UserId('u1'))),
        RealtimeCriticality.normal,
      );
    });

    test('inbox is normal', () {
      expect(
        criticalityFor(inboxRealtimeChannelKey(const UserId('u1'))),
        RealtimeCriticality.normal,
      );
    });

    test('team membership feed is normal', () {
      expect(
        criticalityFor(teamRealtimeChannelKey(const TeamId('tm1'))),
        RealtimeCriticality.normal,
      );
    });

    test('an unknown key defaults to normal (battery wins by default)', () {
      expect(
        criticalityFor('some_other_table:id=x'),
        RealtimeCriticality.normal,
      );
    });
  });
}
