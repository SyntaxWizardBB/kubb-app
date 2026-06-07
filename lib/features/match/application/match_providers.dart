import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/achievements/application/badge_unlock_listener.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/match/data/match_config_draft.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/data/match_repository.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider, realtimePollingFallbackProvider;
import 'package:kubb_domain/kubb_domain.dart';
import 'package:logging/logging.dart';

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

/// Polling cadence used ONLY while the realtime fallback is active
/// (channel ≥60 s errored or kill-switch on). The standalone match detail
/// polls at 30 s per ADR-0029 §(c) FC-6 — never the old 1 s loop.
const Duration _matchFallbackPollInterval = Duration(seconds: 30);

/// Standalone-1v1 match-detail CDC (ADR-0029 §(e) C5-T1 / Phase P7):
/// replaces the retired 1 s match-detail poller. A match screen watches this
/// while mounted so a round-result/status change made on another device shows
/// up without any periodic poll.
///
/// The per-match channel is `matches:id=<mid>` (the standalone `public.matches`
/// table, disjoint from `tournament_matches`) over the app-wide
/// [realtimeChannelProvider] singleton. On every row-level change it
/// invalidates [matchDetailProvider] for that match. Emits no data; it only
/// drives the invalidation.
///
/// TERMINAL-STOP: once the match reaches a terminal status
/// (`finalized` / `voided`, read from [matchDetailProvider]) neither the CDC
/// listener nor the fallback invalidate any further — exactly what the old
/// poller's no-op preserved.
///
/// Fallback: when [realtimePollingFallbackProvider] reports the channel
/// unhealthy for this key, a single 30 s re-arming timer takes over. It is
/// gated strictly on that boolean — there is no unconditional `Timer.periodic`.
//
// Riverpod's family-provider type names are not part of the public API, so the
// lint stays suppressed.
// ignore: specify_nonobvious_property_types
final matchCdcProvider =
    StreamProvider.autoDispose.family<void, String>((ref, matchId) {
  // Channel-key derived exclusively via the kubb_domain builder.
  final channelKey = matchRealtimeChannelKey(MatchId(matchId));

  // Terminal-stop guard: suppress invalidation once the match is
  // finalized/voided, mirroring the retired poller's no-op.
  bool isTerminal() {
    final status = ref.read(matchDetailProvider(matchId)).maybeWhen(
          data: (detail) => detail?.match.status,
          orElse: () => null,
        );
    return status == MatchStatus.finalized || status == MatchStatus.voided;
  }

  void invalidateDetail() {
    if (isTerminal()) return;
    ref.invalidate(matchDetailProvider(matchId));
  }

  // CDC path: one row-level change → one detail invalidation (unless terminal).
  final channel = ref.watch(realtimeChannelProvider);
  final cdcSub = channel
      .subscribe(
        table: 'matches',
        filterColumn: 'id',
        filterValue: matchId,
      )
      .listen((_) => invalidateDetail());

  // Fallback path: gated, self-rearming one-shot Timer (NOT Timer.periodic).
  Timer? fallbackTimer;
  void armFallback() {
    fallbackTimer = Timer(_matchFallbackPollInterval, () {
      invalidateDetail();
      armFallback();
    });
  }

  final fallbackSub = ref.listen<AsyncValue<bool>>(
    realtimePollingFallbackProvider(channelKey),
    (_, next) {
      final polling = next.maybeWhen(data: (v) => v, orElse: () => false);
      if (polling) {
        if (fallbackTimer == null) armFallback();
      } else {
        fallbackTimer?.cancel();
        fallbackTimer = null;
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    fallbackTimer?.cancel();
    fallbackSub.close();
    unawaited(cdcSub.cancel());
    unawaited(channel.close(channelKey));
  });

  return const Stream<void>.empty();
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
    if (response.status == MatchStatus.finalized) {
      await _fireBadgeEvaluation(matchId);
    }
    return response;
  }

  /// Best-effort match-finalize hook. The caller's lifetime match
  /// aggregates are derived from the list-for-caller view that the
  /// matches screen already keeps fresh; failures are logged only so
  /// the propose-result RPC never blocks on the badge pipeline.
  Future<void> _fireBadgeEvaluation(String matchId) async {
    try {
      final summaries =
          await _ref.read(matchRepositoryProvider).listForCaller();
      final myUserId = _ref.read(currentUserIdProvider);
      var matchesPlayed = 0;
      var matchesWon = 0;
      for (final m in summaries) {
        if (m.status != MatchStatus.finalized) continue;
        matchesPlayed++;
        if (m.callerOutcome == 'won') matchesWon++;
      }
      final context = BadgeTriggerContext(
        matchesPlayed: matchesPlayed,
        matchesWon: matchesWon,
      );
      // No-op when signed out — the listener guards against it too, but
      // skipping here saves the repository round-trip.
      if (myUserId == null) return;
      await _ref.read(badgeUnlockListenerProvider).evaluateAfterMatch(
            BadgeMatchSummary(
              sourceMatchId: matchId,
              context: context,
            ),
          );
    } on Object catch (e, st) {
      _log.warning('badge evaluation failed after match finalize', e, st);
    }
  }

  static final Logger _log = Logger('MatchActions');

  Future<void> cancelMatch(String matchId) async {
    await _ref.read(matchRepositoryProvider).cancel(matchId);
    _ref
      ..invalidate(matchDetailProvider(matchId))
      ..invalidate(activeMatchesProvider);
  }
}
