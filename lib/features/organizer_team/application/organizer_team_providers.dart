import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_models.dart';
import 'package:kubb_app/features/organizer_team/data/organizer_team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// The signed-in user's clubs, newest first. Empty when signed out.
final organizerTeamListProvider = FutureProvider<List<OrganizerTeamWire>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const <OrganizerTeamWire>[];
  return ref.read(organizerTeamRepositoryProvider).listMyClubs();
});

/// Full detail (header + members) for one club. Family key = club id.
// ignore: specify_nonobvious_property_types
final organizerTeamDetailProvider =
    FutureProvider.family<OrganizerTeamDetail, OrganizerTeamId>((ref, clubId) async {
  return ref.read(organizerTeamRepositoryProvider).getClub(clubId);
});

/// Pending join requests for a club (manager-only RPC). Family key = club id.
// ignore: specify_nonobvious_property_types
final organizerTeamJoinRequestsProvider =
    FutureProvider.family<List<OrganizerTeamJoinRequestWire>, OrganizerTeamId>(
        (ref, clubId) async {
  return ref.read(organizerTeamRepositoryProvider).listJoinRequests(clubId);
});

/// True when the signed-in user holds a role in {owner, admin} in any club
/// — the capability that gates tournament publishing (P5). False when
/// signed out. Server-delegating on purpose: the role check lives in the
/// `organizer_team_caller_can_publish` RPC, never hardcoded client-side.
final canPublishTournamentProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  return ref.read(organizerTeamRepositoryProvider).callerCanPublish();
});

/// Gates the home screen "Veranstalter" tile (P4-C, ADR-0032 §4). True when
/// the caller may act as an organizer — `can_found_clubs` on the profile OR
/// an active club membership with a role in {owner, admin, referee}. False
/// when signed out. Server-delegating on purpose: the check lives in the
/// `organizer_team_caller_is_organizer` RPC. Consumers must treat loading/error as
/// NOT visible (fail-closed); a plain one-shot Future read, no polling.
final organizerTileVisibleProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  return ref.read(organizerTeamRepositoryProvider).callerIsOrganizer();
});

/// Public club search for the join flow (by name). Empty for short queries.
// ignore: specify_nonobvious_property_types
final organizerTeamSearchProvider =
    FutureProvider.family<List<OrganizerTeamWire>, String>((ref, query) async {
  if (query.trim().length < 2) return const <OrganizerTeamWire>[];
  return ref.read(organizerTeamRepositoryProvider).searchClubs(query.trim());
});
