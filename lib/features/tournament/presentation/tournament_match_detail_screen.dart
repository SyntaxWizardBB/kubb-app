import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_status_chip.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/outbox_pending_provider.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/server_clock_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_score_draft_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_shootout_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/participant_name.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/pitch_call_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_state_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/realtime_status_banner.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/round_phase_countdown.dart';
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

  /// M2b (F1): the KO finisher side resolved for a king-less set, keyed by
  /// the set's index. A KO set with no king (the tri-toggle 'Keiner') is
  /// non-decisive until the finisher is resolved; this map carries the
  /// chosen side so [_setScores] / [_validate] can plumb it through the
  /// canonical pipeline. Cleared per set whenever the king toggle changes.
  final Map<int, SetWinner> _finisherWinners = <int, SetWinner>{};

  /// B1 fallback default per DSCORE-15. The live value is read from the
  /// tournament config (`basekubbs_per_side`) via [_maxBasekubbsFor].
  static const int _defaultMaxBasekubbs = 5;

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
    // M2b (F1): only a king-toggle change invalidates a previously
    // resolved finisher for this set — the user changed their mind about
    // whether the king fell, so the finisher must be re-resolved. A pure
    // base-kubb stepper bump leaves the resolved finisher intact so the
    // submit button does not silently re-block (review finding).
    final prevKing = i < _drafts.length ? _drafts[i].king : null;
    if (v.king != prevKing) {
      _finisherWinners.remove(i);
    }
    final next = List<ScoreDraftSet>.of(_drafts);
    next[i] = ScoreDraftSet(
      basekubbsA: v.basekubbsA,
      basekubbsB: v.basekubbsB,
      king: v.king,
      kingOutcome: _kingOutcomeFor(v.king, match, finisher: null),
    );
    unawaited(_draftController.setSets(consensusRound, next));
  }

  /// Maps the tri-toggle's [SetWinner?] selection into the domain
  /// [KingOutcome]. Sprint A W3-T2 / R11-F-01:
  ///   * Team A / Team B → [KingHitBy] with the matching participant id
  ///     (the toggle implies the king fell and was scored by that side).
  ///   * `null` (the "Keiner" option) → [KingTimedOut]; the EKC pipeline
  ///     then short-circuits the set to a 0:0 contribution.
  ///
  /// M2b (F4): when the set is king-less but a KO finisher has been
  /// resolved ([finisher] non-null), the decisive winner is the finisher
  /// side. We carry it as [KingHitBy] of that side's participant so the
  /// set scores as a real win (not a stale [KingTimedOut] that would zero
  /// the set) and never via an auto kubb-majority guess.
  KingOutcome _kingOutcomeFor(
    SetWinner? king,
    TournamentMatchRef match, {
    required SetWinner? finisher,
  }) {
    final effective = king ?? finisher;
    return switch (effective) {
      SetWinner.teamA when match.participantA != null =>
        KingHitBy(match.participantA!),
      SetWinner.teamB when match.participantB != null =>
        KingHitBy(match.participantB!),
      null => const KingTimedOut(),
      _ => const KingMissed(),
    };
  }

  /// B1: the per-side base-kubb cap, read from the tournament config
  /// (`basekubbs_per_side`) rather than a hard-coded 5. Falls back to
  /// [_defaultMaxBasekubbs] when the detail header has not loaded or the
  /// key is absent (older RPC revisions / the test fake).
  int _maxBasekubbsFor(AsyncValue<TournamentDetail?> detailAsync) {
    return detailAsync.maybeWhen<int>(
      data: (d) {
        final cfg = d?.tournament.matchFormatConfig ?? const <String, Object?>{};
        return (cfg['basekubbs_per_side'] as num?)?.toInt() ??
            _defaultMaxBasekubbs;
      },
      orElse: () => _defaultMaxBasekubbs,
    );
  }

  /// M2b (F2/F3): the configured KO tiebreak / finisher method, read from
  /// the detail header's `setup` map. Defaults to the classic king-toss
  /// removal (a simple two-way choice) when absent.
  KoTiebreakMethod _koTiebreakMethod(
      AsyncValue<TournamentDetail?> detailAsync) {
    return detailAsync.maybeWhen<KoTiebreakMethod>(
      data: (d) {
        final wire = d?.tournament.setup['ko_tiebreak_method'];
        return wire is String
            ? KoTiebreakMethod.fromWire(wire)
            : KoTiebreakMethod.classicKingtossRemoval;
      },
      orElse: () => KoTiebreakMethod.classicKingtossRemoval,
    );
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

  /// B2 / F1: validate the draft against the config-derived [maxBasekubbs]
  /// and the KO finisher requirement. A king-side set must equal the
  /// configured base-kubb max; a king-less KO set must have its finisher
  /// resolved before submit is allowed.
  String? _validate(
    AppLocalizations l,
    List<ScoreDraftSet> drafts, {
    required int maxBasekubbs,
    required MatchPhase phase,
  }) {
    for (var i = 0; i < drafts.length; i++) {
      final d = drafts[i];
      // A resolved KO finisher makes the set decisive even at 0:0 kubbs, so
      // it is not "empty" — the decisive side comes from the finisher.
      final finisherResolved =
          phase == MatchPhase.ko && _finisherWinners[i] != null;
      if (d.king == null &&
          d.basekubbsA == 0 &&
          d.basekubbsB == 0 &&
          !finisherResolved) {
        return l.tournamentMatchValidationEmpty(i + 1);
      }
      if (d.king == SetWinner.teamA && d.basekubbsA != maxBasekubbs) {
        return l.tournamentMatchValidationKingNeedsMax(i + 1);
      }
      if (d.king == SetWinner.teamB && d.basekubbsB != maxBasekubbs) {
        return l.tournamentMatchValidationKingNeedsMax(i + 1);
      }
      // F1: a KO set with no king ('Keiner') is non-decisive until the
      // finisher is resolved. Block submit and prompt the user instead of
      // silently leaving the set as SetWinner.none.
      if (phase == MatchPhase.ko &&
          d.king == null &&
          _finisherWinners[i] == null) {
        return l.tournamentMatchFinisherNeeded(i + 1);
      }
    }
    return null;
  }

  /// M2a: build the [SetScore] list from the draft using the CANONICAL
  /// phase-/scoring-dependent winner derivation
  /// ([resolveSetWinnerForSide]), identical to the server.
  ///
  /// The old naive fallback (`d.king ?? (kubbsA >= kubbsB ? A : B)`)
  /// FORCED a winner by kubb-majority whenever no king was selected. In
  /// the group phase that fabricated an A/B winner the other side never
  /// agreed on, so two identical real inputs were scored as disagreement
  /// and the match ran to `disputed`. Now: king fell -> that side;
  /// group + classic -> none; group + EKC -> by kubbs (draw allowed);
  /// KO -> none (the decisive winner is the M2b finisher prompt, never an
  /// auto kubb-majority fallback here).
  List<SetScore> _setScores(
    List<ScoreDraftSet> drafts,
    SetScoring scoring,
    MatchPhase phase,
    TournamentMatchRef match,
  ) =>
      <SetScore>[
        for (var i = 0; i < drafts.length; i++)
          () {
            final d = drafts[i];
            // F1/F4: in the KO phase a king-less set's decisive winner is
            // the resolved finisher side (never a kubb-majority guess).
            // The finisher side is fed as `kingSide` into the SAME
            // canonical derivation as M2a, so the winner originates from
            // the finisher prompt.
            final finisher =
                phase == MatchPhase.ko && d.king == null ? _finisherWinners[i] : null;
            return SetScore(
              basekubbsKnockedByA: d.basekubbsA,
              basekubbsKnockedByB: d.basekubbsB,
              winner: resolveSetWinnerForSide(
                kingSide: d.king ?? finisher,
                basekubbsA: d.basekubbsA,
                basekubbsB: d.basekubbsB,
                phase: phase,
                scoring: scoring,
              ),
              // R11-F-01 / F4: forward the tri-toggle outcome — upgraded to
              // the finisher-resolved [KingHitBy] for a KO set so the EKC
              // tally credits the decisive winner instead of zeroing the
              // set via a stale [KingTimedOut].
              kingOutcome: finisher != null
                  ? _kingOutcomeFor(null, match, finisher: finisher)
                  : d.kingOutcome,
            );
          }(),
      ];

  /// M2a: the canonical scoring mode for this tournament, read from the
  /// detail header. Defaults to EKC (the historical wire default) when
  /// the header has not loaded yet — only matters for the live preview,
  /// since submit is gated behind a loaded screen.
  SetScoring _scoringMode() {
    final detail = ref
        .read(tournamentDetailProvider(TournamentId(widget.tournamentId)))
        .maybeWhen(
          data: (d) => d?.tournament.scoring,
          orElse: () => null,
        );
    return detail == TournamentScoring.classic
        ? SetScoring.classic
        : SetScoring.ekc;
  }

  Future<void> _submit(TournamentMatchRef match) async {
    final l = AppLocalizations.of(context);
    final drafts = _drafts;
    final detailAsync =
        ref.read(tournamentDetailProvider(TournamentId(widget.tournamentId)));
    if (_submitting ||
        _validate(
              l,
              drafts,
              maxBasekubbs: _maxBasekubbsFor(detailAsync),
              phase: match.phase,
            ) !=
            null) {
      return;
    }
    setState(() => _submitting = true);
    final prevConsensus = match.consensusRound;
    try {
      await ref.read(tournamentActionsProvider).proposeSetScores(
            matchId: match.matchId,
            consensusRound: prevConsensus,
            setScores: _setScores(drafts, _scoringMode(), match.phase, match),
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

  /// M2b (F1/F4): records the finisher winner for a king-less KO set and
  /// re-persists the draft so the resolved king-outcome (a [KingHitBy] of
  /// the chosen side) survives a reload. The chosen side then flows into
  /// the canonical submit pipeline as the set's decisive winner.
  void _resolveFinisher(
    int i,
    SetWinner side,
    int consensusRound,
    TournamentMatchRef match,
  ) {
    setState(() => _finisherWinners[i] = side);
    if (i >= _drafts.length) return;
    final next = List<ScoreDraftSet>.of(_drafts);
    final d = next[i];
    next[i] = ScoreDraftSet(
      basekubbsA: d.basekubbsA,
      basekubbsB: d.basekubbsB,
      // The set stays king-less in the toggle (the king never fell — the
      // finisher decided it); only the persisted king-outcome is upgraded.
      king: d.king,
      kingOutcome: _kingOutcomeFor(null, match, finisher: side),
    );
    unawaited(_draftController.setSets(consensusRound, next));
  }

  /// M2b (F3): for the mighty-finisher-shoot-out method, delegate to the
  /// EXISTING shoot-out infrastructure when an open group exists for this
  /// tournament rather than reimplementing report/confirm. Navigates to
  /// the shoot-out screen; its result resolves the tie server-side.
  Future<void> _openShootout(TournamentMatchRef match) async {
    final pending = await ref
        .read(pendingShootoutsProvider(match.tournamentId).future);
    if (!mounted) return;
    if (pending.isEmpty) return;
    unawaited(context.push<void>(
      TournamentRoutes.shootout(
        widget.tournamentId,
        pending.first.startRank,
      ),
    ));
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
      // TODO(sprintB-followup): migrate to KubbAppBar
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
          // Player-facing "TournierStart" surface: when the caller has an
          // open match in this tournament, point them at their pitch.
          PitchCallBanner(tournamentId: tid),
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

    // W3-T1: organizer-only Forfeit-Action. Visible while the
    // tournament is live, the match has two participants and is not yet
    // in a terminal state. The sheet itself drives the validation; the
    // server re-checks the role / status gate.
    final detailAsync =
        ref.watch(tournamentDetailProvider(TournamentId(widget.tournamentId)));
    // B1/F2: config-derived per-side base-kubb cap + KO finisher method.
    final maxBasekubbs = _maxBasekubbsFor(detailAsync);
    final koMethod = _koTiebreakMethod(detailAsync);
    final validationMessage = _validate(
      l,
      drafts,
      maxBasekubbs: maxBasekubbs,
      phase: match.phase,
    );
    final ekc =
        computeEkc(_setScores(drafts, _scoringMode(), match.phase, match));
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
    // T1: the organizer (creator) needs a direct way to enter / correct a
    // result without being a participant. Same gate as forfeit; routes to the
    // organizer-override screen (server re-checks role + status).
    final canOrganizerOverride = canForfeit;

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

    // M1: resolve both sides' real display names once via the central
    // [ParticipantName] helper and feed them into the set-input stepper /
    // king toggle and the live-score preview, so no surface renders the
    // generic 'Team A'/'Team B' anymore.
    final aName = ParticipantName.resolve(
      l,
      displayName: match.participantADisplayName,
    );
    final bName = ParticipantName.resolve(
      l,
      displayName: match.participantBDisplayName,
    );

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        _Header(
          match: match,
          tournamentId: TournamentId(widget.tournamentId),
          showPending: hasPending,
        ),
        const SizedBox(height: KubbTokens.space3),
        // Live match clock (spec "TournierStart"): only while the match is
        // running (it carries a started_at and is not in a terminal state)
        // and the tournament exposes a round time limit. Crossing expiry
        // vibrates once and flips to the result-entry CTA.
        if (!readOnly && match.startedAt != null)
          Consumer(builder: (context, ref, _) {
            final cfg = detailAsync.maybeWhen<Map<String, Object?>>(
              data: (d) => d?.tournament.matchFormatConfig ?? const {},
              orElse: () => const {},
            );
            final duration = _roundTimeSeconds(cfg);
            if (duration <= 0) return const SizedBox.shrink();

            // ADR-0031 §Uhr / Block A3c: feed the clock from the server skew
            // offset and the matching tournament_round_schedule row. While
            // the offset is loading, or the schedule has no row for this
            // round (running legacy tournaments — OE-5/A4 fallback), the
            // clock degrades to the plain started_at uhr (zero offset, no
            // pause/hold) — no regression for existing tournaments.
            final tid = TournamentId(widget.tournamentId);
            final offset = ref
                .watch(serverClockOffsetProvider)
                .maybeWhen<Duration>(
                  data: (d) => d,
                  orElse: () => Duration.zero,
                );
            final schedule = ref
                .watch(tournamentRoundScheduleProvider(tid))
                .maybeWhen<TournamentRoundScheduleRef?>(
                  data: (rows) => rows[(
                    roundNumber: match.roundNumber,
                    stageNodeId: null,
                  )],
                  orElse: () => null,
                );
            // RoundPhaseCountdown (Block A4) renders the right clock for the
            // round phase off the schedule status: call/pause countdown,
            // running match clock, or held clock (awaiting_results / tiebreak;
            // ADR-0031 §6). With schedule == null it falls back to the plain
            // started_at clock (running legacy tournaments — OE-5).
            return Padding(
              padding: const EdgeInsets.only(bottom: KubbTokens.space3),
              child: RoundPhaseCountdown(
                schedule: schedule,
                startedAt: match.startedAt!,
                durationSeconds: duration,
                tiebreakAfterSeconds: _tiebreakAfterSeconds(cfg),
                serverOffset: offset,
              ),
            );
          }),
        if (hasStaleConflict && !readOnly)
          ScoreConflictBanner(onReenter: () {
            unawaited(_draftController.clear(
                consensusRound: match.consensusRound));
          }),
        ScoreConsensusBanner(attempt: match.consensusRound),
        for (var i = 0; i < drafts.length; i++) ...[
          TournamentSetInput(
            setNumber: i + 1,
            participantAName: aName,
            participantBName: bName,
            basekubbsA: drafts[i].basekubbsA,
            basekubbsB: drafts[i].basekubbsB,
            king: drafts[i].king,
            maxBasekubbs: maxBasekubbs,
            enabled: !readOnly,
            onChanged: (v) => _update(i, match.consensusRound, v, match),
          ),
          // F1: a KO set that ended without a king ('Keiner') needs the
          // configured finisher resolved before it can be a decisive win.
          if (!readOnly &&
              match.phase == MatchPhase.ko &&
              drafts[i].king == null)
            _KoFinisherPrompt(
              setIndex: i,
              match: match,
              method: koMethod,
              resolved: _finisherWinners[i],
              onResolved: (side) =>
                  _resolveFinisher(i, side, match.consensusRound, match),
              onOpenShootout: () => _openShootout(match),
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
        _LivePreview(ekc: ekc, participantAName: aName, participantBName: bName),
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
        if (canOrganizerOverride) ...[
          const SizedBox(height: KubbTokens.space3),
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () => context.push<void>(TournamentRoutes.override(
                      widget.tournamentId, match.matchId.value)),
              icon: const Icon(LucideIcons.clipboardEdit),
              label: Text(l.tournamentOverrideEntryAction),
            ),
          ),
        ],
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

/// Pulls the match round time limit (seconds) out of the tournament's
/// `matchFormatConfig`. Accepts both `round_time_seconds` (the create-RPC
/// shape, see `tournament_config_draft.toMatchFormatConfig`) and the
/// `time_limit_seconds` alias used by `MatchFormatSpec`. Returns 0 when
/// neither key is present or positive.
int _roundTimeSeconds(Map<String, Object?> cfg) {
  final raw = cfg['round_time_seconds'] ?? cfg['time_limit_seconds'];
  final value = (raw as num?)?.toInt() ?? 0;
  return value > 0 ? value : 0;
}

/// Pulls the tiebreak trigger offset (seconds) from `matchFormatConfig`,
/// or null when tiebreak is disabled / absent.
int? _tiebreakAfterSeconds(Map<String, Object?> cfg) {
  if (cfg['tiebreak_enabled'] == false) return null;
  return (cfg['tiebreak_after_seconds'] as num?)?.toInt();
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final isBye = match.participantB == null;
    // M1: both sides resolve through the single [ParticipantName] helper
    // (server-projected display name, localized "Unbekannt" fallback,
    // never 'A'/'B' or a raw UUID). BYE is handled below via the dedicated
    // header label.
    final aLabel = ParticipantName.resolve(
      l,
      displayName: match.participantADisplayName,
    );
    final bLabel = ParticipantName.resolve(
      l,
      displayName: match.participantBDisplayName,
    );
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.tournamentMatchHeaderRound(
                    match.roundNumber, match.matchNumberInRound),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: tokens.fgMuted,
                    letterSpacing: 0.5),
              ),
            ),
            // W3-T4 (Mängel #1): status chip with the central
            // semantic-tone mapping. Previously the detail header was
            // status-blind; the user had to read the body to know
            // whether the match was live, awaiting results or already
            // disputed.
            KubbStatusChip.tournamentMatch(status: match.status, l: l),
          ],
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
  const _LivePreview({
    required this.ekc,
    required this.participantAName,
    required this.participantBName,
  });
  final MatchEkcScore ekc;

  /// M1: the real resolved display names of the two sides, so the
  /// preliminary leader is named with the actual participant instead of
  /// the generic 'Team A'/'Team B'. The EKC computation (computeEkc /
  /// matchWinner) is untouched — only the rendered label changes.
  final String participantAName;
  final String participantBName;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final w = ekc.matchWinner;
    final score = l.tournamentMatchLivePreviewScore(ekc.setsWonA, ekc.setsWonB);
    final line = w == null
        ? '$score — ${l.tournamentMatchLivePreviewUndecided}'
        : '$score — ${l.tournamentMatchLivePreviewLeader(w == SetWinner.teamA ? participantAName : participantBName)}';
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

/// M2b (F1-F3): the KO finisher prompt rendered under a king-less set in
/// the knockout phase. Asks "Wer hat den Finisher gewonnen?" and lets the
/// user pick the winning side using the REAL participant names.
///
/// * [KoTiebreakMethod.classicKingtossRemoval] -> a plain two-way choice
///   whose result becomes the set's decisive [SetWinner].
/// * [KoTiebreakMethod.mightyFinisherShootout] -> the same two-way choice
///   PLUS a shortcut into the existing shoot-out infrastructure
///   (the shoot-out screen) when an open group exists; the shoot-out
///   resolves the tie server-side. No report/confirm logic is duplicated
///   here.
class _KoFinisherPrompt extends StatelessWidget {
  const _KoFinisherPrompt({
    required this.setIndex,
    required this.match,
    required this.method,
    required this.resolved,
    required this.onResolved,
    required this.onOpenShootout,
  });

  final int setIndex;
  final TournamentMatchRef match;
  final KoTiebreakMethod method;
  final SetWinner? resolved;
  final ValueChanged<SetWinner> onResolved;
  final VoidCallback onOpenShootout;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    // M1: route both sides through the central [ParticipantName] helper
    // instead of a local copy of the trim/Unbekannt fallback.
    final aName = ParticipantName.resolve(
      l,
      displayName: match.participantADisplayName,
    );
    final bName = ParticipantName.resolve(
      l,
      displayName: match.participantBDisplayName,
    );
    final isShootout = method == KoTiebreakMethod.mightyFinisherShootout;

    return Container(
      margin: const EdgeInsets.only(top: KubbTokens.space2),
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: KubbTokens.wood400, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(LucideIcons.flag, size: 18, color: KubbTokens.wood400),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Surface which set is being resolved so the prompt is
                  // unambiguous when several KO sets are stacked.
                  Text(
                    l.tournamentMatchFinisherSetLabel(setIndex + 1),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tokens.fgMuted),
                  ),
                  Text(
                    l.tournamentMatchFinisherPrompt,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tokens.fg),
                  ),
                ]),
          ),
        ]),
        const SizedBox(height: KubbTokens.space2),
        Row(children: [
          Expanded(
            child: KubbButton(
              variant: resolved == SetWinner.teamA
                  ? KubbButtonVariant.primary
                  : KubbButtonVariant.secondary,
              onPressed: () => onResolved(SetWinner.teamA),
              child: Text(aName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: KubbTokens.space2),
          Expanded(
            child: KubbButton(
              variant: resolved == SetWinner.teamB
                  ? KubbButtonVariant.primary
                  : KubbButtonVariant.secondary,
              onPressed: () => onResolved(SetWinner.teamB),
              child: Text(bName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        if (isShootout) ...[
          const SizedBox(height: KubbTokens.space2),
          Text(
            l.tournamentMatchFinisherShootoutPending,
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          ),
          const SizedBox(height: KubbTokens.space2),
          KubbButton(
            variant: KubbButtonVariant.secondary,
            onPressed: onOpenShootout,
            child: Text(l.tournamentMatchFinisherShootoutOpenAction),
          ),
        ],
      ]),
    );
  }
}
