import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Polling cadence for the outbox pending stream. The flusher emits row
/// changes via the drift DAO, but the DAO does not expose a reactive
/// `watch()` for [ScoreSubmissionOutboxDao.pending], so we re-read every
/// 2 s to keep the match-detail markers (TASK-M4.3-T11) in sync without
/// pulling in a stream extension just for this UI surface.
const Duration kOutboxPendingPollInterval = Duration(seconds: 2);

/// Reactive view of un-acknowledged outbox rows for a single match.
///
/// Surfaces both pending (no `acknowledgedAt`, no `lastErrorCode`) and
/// errored rows (`lastErrorCode` set) so the match-detail screen can
/// render the pending-indicator and the `STALE_CONSENSUS_ROUND`
/// conflict banner from one source of truth. Polls every
/// [kOutboxPendingPollInterval]; the timer is bound to the autoDispose
/// lifecycle of the provider.
//
// ignore: specify_nonobvious_property_types
final outboxPendingProvider = StreamProvider.autoDispose
    .family<List<OutboxRow>, TournamentMatchId>((ref, matchId) {
  final dao = ref.watch(scoreSubmissionOutboxDaoProvider);
  final controller = StreamController<List<OutboxRow>>();

  Future<void> emit() async {
    try {
      final rows = await dao.pending();
      final filtered = <OutboxRow>[
        for (final r in rows)
          if (r.matchId == matchId.value) _fromDriftRow(r),
      ];
      if (!controller.isClosed) controller.add(filtered);
    } on Object catch (e, s) {
      if (!controller.isClosed) controller.addError(e, s);
    }
  }

  unawaited(emit());
  final timer =
      Timer.periodic(kOutboxPendingPollInterval, (_) => unawaited(emit()));

  ref.onDispose(() {
    timer.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});

/// Drift-row → port-row mapping. Kept local so the provider does not
/// re-import the flusher's private mapper. Only the fields consumed by
/// the UI markers are populated.
OutboxRow _fromDriftRow(ScoreSubmissionOutboxRow row) {
  return OutboxRow(
    id: row.id.toString(),
    matchId: TournamentMatchId(row.matchId),
    consensusRound: row.consensusRound,
    setIndex: row.setIndex,
    submitterUserId: UserId(row.submitterUserId),
    // The marker UI does not need the score payload; supply a sentinel
    // so the [OutboxRow] contract stays satisfied without decoding the
    // JSON column here.
    score: SetScore(
      basekubbsKnockedByA: 0,
      basekubbsKnockedByB: 0,
      winner: SetWinner.teamA,
    ),
    lamportCounter: row.lamportCounter,
    lamportDeviceId: row.lamportDeviceId,
    queuedAt: row.queuedAt,
    attemptCount: row.retryCount,
    lastErrorCode: row.lastErrorCode,
    acknowledgedAt: row.acknowledgedAt,
  );
}
