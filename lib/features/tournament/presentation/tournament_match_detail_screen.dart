import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/outbox_pending_provider.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_score_draft_controller.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_state_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_status_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/score_consensus_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/score_pending_indicator.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_forfeit_sheet.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_set_input.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Critical M1 screen: per-set score entry for one tournament match.
///
/// Layout decision (DSCORE flow + handoff §7.1): every active set is
/// rendered as an always-visible card stacked vertically inside a
/// ListView. Accordions and PageView were rejected because the spec
/// requires one-handed input under 30s and either pattern adds taps
/// or hides the live match score.
class TournamentMatchDetailScreen extends ConsumerStatefulWidget {
  const TournamentMatchDetailScreen({
    required this.tournamentId,
    required this.matchId,
    super.key,
  });

  final String tournamentId;
  final String matchId;

  @override
  ConsumerState<TournamentMatchDetailScreen> createState() =>
      _TournamentMatchDetailScreenState();
}

class _TournamentMatchDetailScreenState
    extends ConsumerState<TournamentMatchDetailScreen> {
  bool _submitting = false;

  /// Spec default per DSCORE-15. Wizard-configurable; threaded through
  /// `TournamentMatchRef` once the detail RPC exposes it.
  static const int _maxBasekubbs = 5;

  /// Best-of-3 default; max-set cap from `matchFormatConfig` is wired
  /// through once the wizard surfaces it.
  static const int _maxSets = 3;

  TournamentMatchId get _matchId => TournamentMatchId(widget.matchId);

  ScoreDraftController get _draftController =>
      ref.read(scoreDraftControllerProvider(_matchId).notifier);

  List<ScoreDraftSet> get _drafts =>
      ref.read(scoreDraftControllerProvider(_matchId)).sets;

  void _ensureDraftForRound(TournamentMatchRef m) {
    // TODO(W1-T2-followup): clear on finished — DSCORE-22 GC hook.
    unawaited(_draftController.init(m.consensusRound));
  }

  void _update(int i, int consensusRound, TournamentSetInputValue v,
      TournamentMatchRef match) {
    final next = List<ScoreDraftSet>.of(_drafts);
    next[i] = ScoreDraftSet(
      basekubbsA: v.basekubbsA,
      basekubbsB: v.basekubbsB,
      king: v.king,
      kingOutcome: _kingOutcomeFor(v.king, match),
    );
    unawaited(_draftController.setSets(consensusRound, next));
  }

  /// Maps the tri-toggle's [SetWinner?] selection into the domain
  /// [KingOutcome]. Sprint A W3-T2 / R11-F-01:
  ///   * Team A / Team B → [KingHitBy] with the matching participant id
  ///     (the toggle implies the king fell and was scored by that side).
  ///   * `null` (the "Keiner" option) → [KingTimedOut]; the EKC pipeline
  ///     then short-circuits the set to a 0:0 contribution.
  KingOutcome _kingOutcomeFor(SetWinner? king, TournamentMatchRef match) {
    return switch (king) {
      SetWinner.teamA when match.participantA != null =>
        KingHitBy(match.participantA!),
      SetWinner.teamB when match.participantB != null =>
        KingHitBy(match.participantB!),
      null => const KingTimedOut(),
      _ => const KingMissed(),
    };
  }

  void _addSet(int consensusRound) {
    if (_drafts.length >= _maxSets) return;
    unawaited(_draftController.setSets(
        consensusRound, <ScoreDraftSet>[..._drafts, const ScoreDraftSet()]));
  }

  void _removeSet(int consensusRound) {
    if (_drafts.length <= 1) return;
    unawaited(_draftController.setSets(
        consensusRound, _drafts.sublist(0, _drafts.length - 1)));
  }

  String? _validate(AppLocalizations l, List<ScoreDraftSet> drafts) {
    for (var i = 0; i < drafts.length; i++) {
      final d = drafts[i];
      if (d.king == null && d.basekubbsA == 0 && d.basekubbsB == 0) {
        return l.tournamentMatchValidationEmpty(i + 1);
      }
      if (d.king == SetWinner.teamA && d.basekubbsA != _maxBasekubbs) {
        return l.tournamentMatchValidationKingNeedsMax(i + 1);
      }
      if (d.king == SetWinner.teamB && d.basekubbsB != _maxBasekubbs) {
        return l.tournamentMatchValidationKingNeedsMax(i + 1);
      }
    }
    return null;
  }

  List<SetScore> _setScores(List<ScoreDraftSet> drafts) => <SetScore>[
        for (final d in drafts)
          SetScore(
            basekubbsKnockedByA: d.basekubbsA,
            basekubbsKnockedByB: d.basekubbsB,
            winner: d.king ??
                (d.basekubbsA >= d.basekubbsB
                    ? SetWinner.teamA
                    : SetWinner.teamB),
            // R11-F-01: forward the tri-toggle's outcome into the score
            // payload so the EKC tally and the wire RPC see the
            // explicit `KingTimedOut` path instead of relying on the
            // legacy `winner`-only shape.
            kingOutcome: d.kingOutcome,
          ),
      ];

  Future<void> _submit(TournamentMatchRef match) async {
    final l = AppLocalizations.of(context);
    final drafts = _drafts;
    if (_submitting || _validate(l, drafts) != null) return;
    setState(() => _submitting = true);
    final prevConsensus = match.consensusRound;
    try {
      await ref.read(tournamentActionsProvider).proposeSetScores(
            matchId: match.matchId,
            consensusRound: prevConsensus,
            setScores: _setScores(drafts),
          );
      // DSCORE-21: drop the draft for the round we just submitted. The
      // outbox queues the propose RPC so this counts as "acknowledged".
      await _draftController.clear(consensusRound: prevConsensus);
      if (!mounted) return;
      final next = await ref
          .read(tournamentMatchDetailProvider(match.matchId).future);
      if (!mounted || next == null) return;
      final messenger = ScaffoldMessenger.of(context);
      if (next.status == TournamentMatchStatus.finalized ||
          next.status == TournamentMatchStatus.overridden) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.tournamentMatchFinalizedToast)));
        context.go(TournamentRoutes.standings(widget.tournamentId));
        return;
      }
      if (next.status == TournamentMatchStatus.disputed) {
        // R10-F-13 / MUSS-Fix #2: route the user to the conflict
        // screen instead of bouncing back to the match list. The
        // SnackBar stays as a secondary cue.
        messenger.showSnackBar(SnackBar(
            content: Text(l.tournamentMatchDisputedToast),
            backgroundColor: KubbTokens.miss));
        context.go(TournamentRoutes.conflict(
            widget.tournamentId, match.matchId.value));
        return;
      }
      if (next.consensusRound > prevConsensus) {
        await _draftController.init(next.consensusRound);
        if (mounted) {
          unawaited(context.push<void>(TournamentRoutes.conflict(
              widget.tournamentId, match.matchId.value)));
        } else {
          messenger.showSnackBar(SnackBar(
            content: Text(l.tournamentMatchDisagreementToast(
                next.consensusRound, ScoreConsensusBanner.maxAttempts)),
            backgroundColor: KubbTokens.wood400,
          ));
        }
      }
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${l.tournamentMatchSubmitError}: $e'),
        backgroundColor: KubbTokens.miss,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final id = TournamentMatchId(widget.matchId);
    final tid = TournamentId(widget.tournamentId);
    // M4.1-T12: subscribe to the realtime stream first. Each event
    // invalidates [tournamentMatchDetailProvider] inside the realtime
    // provider, so the read path below stays the single source of UI
    // truth. Polling activates only when the channel falls back
    // (M4.1-T10).
    ref.watch(tournamentMatchDetailRealtimeProvider(id));
    final fallbackActive = ref
        .watch(realtimeFallbackProvider(tid))
        .maybeWhen(data: (v) => v, orElse: () => false);
    if (fallbackActive) {
      ref.watch(tournamentMatchPollingProvider(id));
    }
    // R10-F-13 / MUSS-Fix #2: when the match flips to `disputed`
    // (e.g. via the realtime stream while the user is still on this
    // screen), actively push the conflict screen. The submit-path
    // routes explicitly above; this listener covers externally-driven
    // status changes that arrive after submit completed or for the
    // other team's device.
    ref.listen<AsyncValue<TournamentMatchRef?>>(
      tournamentMatchDetailProvider(id),
      (prev, next) {
        final prevStatus = prev?.maybeWhen<TournamentMatchStatus?>(
          data: (m) => m?.status,
          orElse: () => null,
        );
        final nextStatus = next.maybeWhen<TournamentMatchStatus?>(
          data: (m) => m?.status,
          orElse: () => null,
        );
        if (prevStatus != null &&
            prevStatus != TournamentMatchStatus.disputed &&
            nextStatus == TournamentMatchStatus.disputed) {
          context.go(TournamentRoutes.conflict(
              widget.tournamentId, widget.matchId));
        }
      },
    );
    final detailAsync = ref.watch(tournamentMatchDetailProvider(id));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(
          onPressed: () =>
              context.go(TournamentRoutes.matchesFor(widget.tournamentId)),
        ),
        title: Text(l.tournamentMatchDetailTitle),
      ),
      body: Column(
        children: [
          RealtimeStateBanner(tournamentId: tid),
          RealtimeStatusBanner(tournamentId: tid),
          Expanded(
            child: detailAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  _ErrorBody(message: '${l.tournamentMatchLoadError}: $e'),
              data: (match) {
                if (match == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                _ensureDraftForRound(match);
                return _renderBody(context, match, l, tokens);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderBody(BuildContext context, TournamentMatchRef match,
      AppLocalizations l, KubbTokens tokens) {
    final readOnly = match.status == TournamentMatchStatus.finalized ||
        match.status == TournamentMatchStatus.overridden ||
        match.status == TournamentMatchStatus.voided;
    final drafts =
        ref.watch(scoreDraftControllerProvider(_matchId)).sets;
    final validationMessage = _validate(l, drafts);
    final ekc = computeEkc(_setScores(drafts));

    // W3-T1: organizer-only Forfeit-Action. Visible while the
    // tournament is live, the match has two participants and is not yet
    // in a terminal state. The sheet itself drives the validation; the
    // server re-checks the role / status gate.
    final detailAsync =
        ref.watch(tournamentDetailProvider(TournamentId(widget.tournamentId)));
    final callerUserId = ref.watch(currentUserIdProvider);
    final isCreator = detailAsync
            .maybeWhen<bool>(
              data: (d) => d?.isCallerCreator(callerUserId) ?? false,
              orElse: () => false,
            );
    final tournamentLive = detailAsync.maybeWhen<bool>(
      data: (d) => d?.tournament.status == TournamentStatus.live,
      orElse: () => false,
    );
    final canForfeit = isCreator &&
        tournamentLive &&
        !readOnly &&
        match.participantA != null &&
        match.participantB != null;

    // TASK-M4.3-T11: drive pending / conflict markers off the outbox.
    final outboxAsync = ref.watch(outboxPendingProvider(match.matchId));
    final outboxRows = outboxAsync.maybeWhen(
      data: (rows) => rows,
      orElse: () => const <OutboxRow>[],
    );
    final hasPending = outboxRows.any((r) =>
        r.acknowledgedAt == null && r.lastErrorCode == null);
    final hasStaleConflict = outboxRows.any(
        (r) => r.lastErrorCode == 'STALE_CONSENSUS_ROUND');

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        _Header(
          match: match,
          tournamentId: TournamentId(widget.tournamentId),
          showPending: hasPending,
        ),
        const SizedBox(height: KubbTokens.space3),
        if (hasStaleConflict && !readOnly)
          ScoreConflictBanner(onReenter: () {
            unawaited(_draftController.clear(
                consensusRound: match.consensusRound));
          }),
        ScoreConsensusBanner(attempt: match.consensusRound),
        for (var i = 0; i < drafts.length; i++) ...[
          TournamentSetInput(
            setNumber: i + 1,
            basekubbsA: drafts[i].basekubbsA,
            basekubbsB: drafts[i].basekubbsB,
            king: drafts[i].king,
            maxBasekubbs: _maxBasekubbs,
            enabled: !readOnly,
            onChanged: (v) => _update(i, match.consensusRound, v, match),
          ),
          const SizedBox(height: KubbTokens.space3),
        ],
        if (!readOnly) ...[
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: drafts.length <= 1
                    ? null
                    : () => _removeSet(match.consensusRound),
                icon: const Icon(LucideIcons.minus),
                label: Text(l.tournamentMatchRemoveSet),
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: drafts.length >= _maxSets
                    ? null
                    : () => _addSet(match.consensusRound),
                icon: const Icon(LucideIcons.plus),
                label: Text(l.tournamentMatchAddSet),
              ),
            ),
          ]),
          const SizedBox(height: KubbTokens.space4),
        ],
        _LivePreview(ekc: ekc),
        const SizedBox(height: KubbTokens.space4),
        if (validationMessage != null && !readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: KubbTokens.space3),
            child: Text(validationMessage,
                style: const TextStyle(
                    fontSize: 12,
                    color: KubbTokens.miss,
                    fontWeight: FontWeight.w600)),
          ),
        if (!readOnly)
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: FilledButton(
              onPressed: _submitting || validationMessage != null
                  ? null
                  : () => _submit(match),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l.tournamentMatchSubmitButton),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: KubbTokens.space2),
            child: Text(l.tournamentMatchReadOnlyNotice,
                style: TextStyle(color: tokens.fgMuted, fontSize: 13)),
          ),
        if (canForfeit) ...[
          const SizedBox(height: KubbTokens.space3),
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () => _openForfeitSheet(match),
              icon: const Icon(LucideIcons.userX),
              label: Text(l.tournamentForfeitAction),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openForfeitSheet(TournamentMatchRef match) async {
    final ok = await TournamentForfeitSheet.show(
      context,
      matchId: match.matchId,
    );
    if (ok == true && mounted) {
      // The action provider already invalidates the detail provider;
      // pop back to the match list so the organizer sees the finalised
      // status reflected immediately.
      context.go(TournamentRoutes.matchesFor(widget.tournamentId));
    }
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss)),
        ),
      );
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.match,
    required this.tournamentId,
    this.showPending = false,
  });
  final TournamentMatchRef match;
  final TournamentId tournamentId;
  final bool showPending;

  /// W3-T4 / R10-F-06: prefer the server-projected display name. The
  /// `tournament_match_get` RPC now emits
  /// `participant_{a,b}_display_name` per
  /// `20260601000003_tournament_get_with_display_names`; the old UUID
  /// substring fallback (`ba9c12…`) is gone. When the display_name is
  /// genuinely absent (e.g. a row from before the migration landed, or
  /// a participant with no nickname/team name), the localized
  /// `tournamentParticipantUnknown` label is used so the header never
  /// shows raw ids.
  String _participantLabel(
    AppLocalizations l,
    TournamentParticipantId? pid,
    String? displayName,
  ) {
    if (pid == null) return '?';
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return l.tournamentParticipantUnknown;
    return name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final isBye = match.participantB == null;
    final aLabel = _participantLabel(
        l, match.participantA, match.participantADisplayName);
    final bLabel = _participantLabel(
        l, match.participantB, match.participantBDisplayName);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          l.tournamentMatchHeaderRound(
              match.roundNumber, match.matchNumberInRound),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tokens.fgMuted,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          isBye
              ? l.tournamentMatchByeHeader
              : l.tournamentMatchVersusHeader(aLabel, bLabel),
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: tokens.fg),
        ),
        if (showPending) const ScorePendingIndicator(),
      ]),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.ekc});
  final MatchEkcScore ekc;
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final w = ekc.matchWinner;
    final score = l.tournamentMatchLivePreviewScore(ekc.setsWonA, ekc.setsWonB);
    final line = w == null
        ? '$score — ${l.tournamentMatchLivePreviewUndecided}'
        : '$score — ${w == SetWinner.teamA ? l.tournamentMatchKingByA : l.tournamentMatchKingByB}';
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: tokens.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.tournamentMatchLivePreviewLabel,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.fgMuted)),
        const SizedBox(height: KubbTokens.space2),
        Text(line,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: tokens.fg)),
      ]),
    );
  }
}
