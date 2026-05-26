import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';

/// Lists every team the calling user is an active pool member of.
/// Backed by the `team_list_for_caller` RPC, which the server scopes
/// to memberships with `removed_at IS NULL` so dissolved or left teams
/// drop out automatically.
///
/// The `team_membership_controller` invalidates this provider after
/// every successful mutation (create / accept-invite / leave /
/// dissolve) so the list view refetches without manual refresh.
final teamListProvider = FutureProvider<List<TeamWire>>((ref) async {
  return ref.read(teamRepositoryProvider).listMyTeams();
});
