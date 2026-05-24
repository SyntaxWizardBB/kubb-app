import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/match/data/match_config_draft.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/data/match_repository.dart';

/// Caller's match list (any status). Returns empty when the session is
/// signed out so the UI never blocks on the RPC for that case.
final activeMatchesProvider =
    FutureProvider<List<MatchSummary>>((ref) async {
  if (!ref.watch(isAuthenticatedProvider)) {
    return const <MatchSummary>[];
  }
  return ref.read(matchRepositoryProvider).listForCaller();
});

/// Full match detail keyed by match id. Null if the caller is not
/// allowed to read the match (server returns no row).
//
// Riverpod's family-provider type names are not part of the public API,
// so we suppress the lint here and rely on the generic args for inference.
// ignore: specify_nonobvious_property_types
final matchDetailProvider =
    FutureProvider.family<MatchDetail?, String>((ref, matchId) async {
  return ref.read(matchRepositoryProvider).detail(matchId);
});

/// Side-effect provider: when a screen `watch`es it, a periodic timer
/// starts refreshing [matchDetailProvider] for the given match id every
/// second. The timer stops invalidating once the match reaches a
/// terminal status (`finalized` / `voided`); the provider itself is
/// disposed automatically when nobody listens, which cancels the timer.
//
// Riverpod's family-provider type names are not part of the public API,
// so we suppress the lint here and rely on the generic args for inference.
// ignore: specify_nonobvious_property_types
final matchPollingProvider =
    Provider.family<void, String>((ref, matchId) {
  final timer = Timer.periodic(const Duration(seconds: 1), (_) {
    final asyncDetail = ref.read(matchDetailProvider(matchId));
    final status = asyncDetail.maybeWhen<MatchStatus?>(
      data: (detail) => detail?.match.status,
      orElse: () => null,
    );
    // Stop polling once the match reaches a terminal state. We still
    // leave the timer running (it will be cancelled by onDispose) so
    // the listener teardown path stays simple.
    if (status == MatchStatus.finalized ||
        status == MatchStatus.voided) {
      return;
    }
    ref.invalidate(matchDetailProvider(matchId));
  });
  ref.onDispose(timer.cancel);
});

/// Imperative action surface so screen widgets do not need to repeat
/// invalidate-after-write boilerplate at every call site.
final matchActionsProvider = Provider<MatchActions>((ref) {
  return MatchActions(ref);
});

class MatchActions {
  MatchActions(this._ref);
  final Ref _ref;

  Future<String> createMatch(MatchConfigDraft draft) async {
    final callerId = _ref.read(currentUserIdProvider);
    if (callerId == null) {
      throw StateError('Cannot create a match without an authenticated user');
    }
    final matchId = await _ref
        .read(matchRepositoryProvider)
        .create(draft, callerUserId: callerId);
    _ref.invalidate(activeMatchesProvider);
    return matchId;
  }

  Future<void> acceptInvite(String matchId) async {
    await _ref
        .read(matchRepositoryProvider)
        .respondToInvite(matchId, accept: true);
    _ref
      ..invalidate(matchDetailProvider(matchId))
      ..invalidate(activeMatchesProvider);
  }

  Future<void> declineInvite(String matchId) async {
    await _ref
        .read(matchRepositoryProvider)
        .respondToInvite(matchId, accept: false);
    _ref
      ..invalidate(matchDetailProvider(matchId))
      ..invalidate(activeMatchesProvider);
  }

  Future<void> finishPlay(String matchId) async {
    await _ref.read(matchRepositoryProvider).finishPlay(matchId);
    _ref
      ..invalidate(matchDetailProvider(matchId))
      ..invalidate(activeMatchesProvider);
  }

  Future<MatchProposeResultResponse> proposeResult(
    String matchId, {
    required String? winnerTeamId,
    required int scoreA,
    required int scoreB,
  }) async {
    final response = await _ref.read(matchRepositoryProvider).proposeResult(
          matchId,
          winnerTeamId: winnerTeamId,
          scoreA: scoreA,
          scoreB: scoreB,
        );
    _ref
      ..invalidate(matchDetailProvider(matchId))
      ..invalidate(activeMatchesProvider);
    return response;
  }

  Future<void> cancelMatch(String matchId) async {
    await _ref.read(matchRepositoryProvider).cancel(matchId);
    _ref
      ..invalidate(matchDetailProvider(matchId))
      ..invalidate(activeMatchesProvider);
  }
}
