import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/season/data/season_repository.dart';

/// Liga-Admin write-surface for the season feature. Holds the
/// `listSeasons` result as the canonical state so the screen can render
/// loading / error / data uniformly without juggling a separate
/// FutureProvider. Every action reloads the list on success so the tile
/// list stays consistent with the DB after status changes or new
/// assignments.
class SeasonAdminController extends Notifier<AsyncValue<List<Season>>> {
  @override
  AsyncValue<List<Season>> build() {
    // Kick off the first load eagerly; the loading placeholder is the
    // synchronous return value so the screen can render immediately.
    unawaited(_load());
    return const AsyncValue<List<Season>>.loading();
  }

  Future<void> refresh() => _load();

  Future<void> createSeason({
    required String name,
    String? leagueId,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    await _guard(() => _repo.createSeason(
          name: name,
          leagueId: leagueId,
          startsAt: startsAt,
          endsAt: endsAt,
        ));
  }

  Future<void> updateStatus(String id, String status) async {
    await _guard(() => _repo.updateStatus(id, status));
  }

  Future<void> assignTournament(
    String seasonId,
    String tournamentId, {
    double tournamentFactor = 1.0,
    double leagueFactor = 1.0,
  }) async {
    await _guard(() => _repo.assignTournament(
          seasonId,
          tournamentId,
          tournamentFactor: tournamentFactor,
          leagueFactor: leagueFactor,
        ));
  }

  SeasonRepository get _repo => ref.read(seasonRepositoryProvider);

  Future<void> _load() async {
    state = const AsyncValue<List<Season>>.loading();
    state = await AsyncValue.guard(_repo.listSeasons);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } on Object catch (e, st) {
      state = AsyncValue<List<Season>>.error(e, st);
    }
  }
}

final seasonAdminControllerProvider =
    NotifierProvider<SeasonAdminController, AsyncValue<List<Season>>>(
  SeasonAdminController.new,
);
