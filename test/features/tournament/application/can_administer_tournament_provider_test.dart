// ADR-0031 Phase B, Block B1c — canAdministerTournamentProvider (K4 gate).
// Updated for the gate split (ADR-0032 P2-C, migration 20261281000000):
//
// Access = Creator OR active club role in {owner, admin, referee} — the
// client mirror of `tournament_caller_can_administer`. Mirrors
// canManageTournamentClubProvider but ADDS `referee` and ORs in the
// per-tournament creator check. Resolves false when signed-out, while the
// club read is loading, and on error. The server stays the security boundary.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_models.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _userId = 'user-1';
const _clubId = 'club-1';

OrganizerTeamDetail _clubWith(List<String> rolesForUser1) {
  return OrganizerTeamDetail(
    club: OrganizerTeamWire(
      id: _clubId,
      displayName: 'Club 1',
      createdAt: DateTime.utc(2026),
    ),
    members: <OrganizerTeamMemberWire>[
      OrganizerTeamMemberWire(
        membershipId: 'm-1',
        userId: _userId,
        roles: rolesForUser1,
        joinedAt: DateTime.utc(2026),
      ),
    ],
  );
}

/// Builds a container where the signed-in user is [userId] and the club read
/// for `_clubId` resolves to [club] (or stays loading / errors).
ProviderContainer _container({
  required String? userId,
  OrganizerTeamDetail? club,
  bool loading = false,
  bool error = false,
}) {
  return ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(userId),
      organizerTeamDetailProvider.overrideWith((ref, clubId) async {
        if (loading) {
          // Never completes — keeps the FutureProvider in AsyncLoading.
          return Completer<OrganizerTeamDetail>().future;
        }
        if (error) {
          throw StateError('club read failed');
        }
        return club ?? _clubWith(const <String>[]);
      }),
    ],
  );
}

/// Reads the gate once, after letting any async club read settle.
///
/// The gate Provider watches `organizerTeamDetailProvider` (a FutureProvider). We must
/// keep that future provider subscribed and await it so it transitions out of
/// AsyncLoading before we read the gate — a bare `read` would start the future
/// and observe it still loading. `loading` tests skip the await on purpose.
Future<bool> _read(
  ProviderContainer c, {
  String? clubId = _clubId,
  String? createdBy,
  bool awaitClub = true,
}) async {
  if (clubId != null && awaitClub) {
    final sub = c.listen(
      organizerTeamDetailProvider(OrganizerTeamId(clubId)),
      (_, _) {},
    );
    addTearDown(sub.close);
    try {
      await c.read(organizerTeamDetailProvider(OrganizerTeamId(clubId)).future);
    } on Object {
      // Error path: the gate must resolve false on a failed club read.
    }
  }
  return c.read(
    canAdministerTournamentProvider((clubId: clubId, createdBy: createdBy)),
  );
}

void main() {
  test('creator -> true (even with no club / no role)', () async {
    final c = _container(userId: _userId, club: _clubWith(const <String>[]));
    addTearDown(c.dispose);
    expect(await _read(c, clubId: null, createdBy: _userId), isTrue);
  });

  test('club referee (non-creator) -> true (the K4 addition)', () async {
    final c = _container(userId: _userId, club: _clubWith(const ['referee']));
    addTearDown(c.dispose);
    // Explicit non-creator: authority comes from the referee role alone.
    expect(await _read(c, createdBy: 'someone-else'), isTrue);
  });

  test('club owner -> true', () async {
    final c = _container(userId: _userId, club: _clubWith(const ['owner']));
    addTearDown(c.dispose);
    expect(await _read(c), isTrue);
  });

  test('club admin -> true', () async {
    final c = _container(userId: _userId, club: _clubWith(const ['admin']));
    addTearDown(c.dispose);
    expect(await _read(c), isTrue);
  });

  test('legacy organizer role -> false (gate split removed it)', () async {
    // The organizer role was consolidated away (P1) and dropped from the
    // administer predicate (P2-C); a stale row must not grant access.
    final c = _container(userId: _userId, club: _clubWith(const ['organizer']));
    addTearDown(c.dispose);
    expect(await _read(c, createdBy: 'someone-else'), isFalse);
  });

  test('plain member -> false', () async {
    final c = _container(userId: _userId, club: _clubWith(const ['member']));
    addTearDown(c.dispose);
    expect(await _read(c, createdBy: 'someone-else'), isFalse);
  });

  test('signed out -> false', () async {
    final c = _container(userId: null, club: _clubWith(const ['owner']));
    addTearDown(c.dispose);
    // Even creator-by-id is irrelevant when there is no authenticated user.
    expect(await _read(c, createdBy: 'whoever'), isFalse);
  });

  test('club read loading -> false', () async {
    final c = _container(userId: _userId, loading: true);
    addTearDown(c.dispose);
    // awaitClub:false — the override never completes; the gate must read the
    // club provider's AsyncLoading state and resolve false.
    expect(
      await _read(c, createdBy: 'someone-else', awaitClub: false),
      isFalse,
    );
  });

  test('club read error -> false', () async {
    final c = _container(userId: _userId, error: true);
    addTearDown(c.dispose);
    expect(await _read(c, createdBy: 'someone-else'), isFalse);
  });
}
