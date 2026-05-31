import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Per-team detail payload. Mirrors the `team_get` RPC return-shape:
/// a `jsonb` envelope with team header, active pool members and active
/// guest players. The raw map is intentionally surfaced so the UI
/// (T13) can choose how to project Header + Pool + Guests without
/// forcing an intermediate DTO at this stage.
///
/// Family-keyed by [TeamId] so multiple detail screens (or the team
/// list pre-fetch) can coexist without sharing cache entries. The
/// `team_membership_controller` invalidates `teamDetailProvider(id)`
/// after every mutation targeting that team.
// autoDispose: the detail payload is a one-shot `team_get` snapshot with no
// realtime channel, so a second device never learns about changes the first
// made. Disposing when the screen closes means re-opening (or pull-to-refresh)
// always refetches the current server state instead of a stale cached map.
// ignore: specify_nonobvious_property_types
final teamDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, TeamId>(
  (ref, teamId) async {
    return ref.read(teamRepositoryProvider).getTeam(teamId);
  },
);
