import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/club/data/club_models.dart';
import 'package:kubb_app/features/club/data/club_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// The signed-in user's clubs, newest first. Empty when signed out.
final clubListProvider = FutureProvider<List<ClubWire>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const <ClubWire>[];
  return ref.read(clubRepositoryProvider).listMyClubs();
});

/// Full detail (header + members) for one club. Family key = club id.
// ignore: specify_nonobvious_property_types
final clubDetailProvider =
    FutureProvider.family<ClubDetail, ClubId>((ref, clubId) async {
  return ref.read(clubRepositoryProvider).getClub(clubId);
});

/// Pending join requests for a club (manager-only RPC). Family key = club id.
// ignore: specify_nonobvious_property_types
final clubJoinRequestsProvider =
    FutureProvider.family<List<ClubJoinRequestWire>, ClubId>(
        (ref, clubId) async {
  return ref.read(clubRepositoryProvider).listJoinRequests(clubId);
});

/// True when the signed-in user is owner/admin/organizer of any club — the
/// capability that gates tournament publishing (P5). False when signed out.
final canPublishTournamentProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  return ref.read(clubRepositoryProvider).callerCanPublish();
});

/// Public club search for the join flow (by name). Empty for short queries.
// ignore: specify_nonobvious_property_types
final clubSearchProvider =
    FutureProvider.family<List<ClubWire>, String>((ref, query) async {
  if (query.trim().length < 2) return const <ClubWire>[];
  return ref.read(clubRepositoryProvider).searchClubs(query.trim());
});
