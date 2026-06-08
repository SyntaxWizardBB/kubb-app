import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_score_draft_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// One persisted draft entry per set within the score-input form.
///
/// Wraps the same trio the in-form `_SetDraft` carries (basekubbs per
/// team plus the explicit king toggle). Persisted via [SetScore] in the
/// drift DAO; on rehydration [king] is restored from the resolved
/// winner because the DAO schema does not encode "no king yet".
///
/// Sprint A W3-T2 extends the in-memory draft with an explicit
/// [kingOutcome] so the submit-pipeline can wire the new tri-state
/// (Team A / Team B / None) to the server. The legacy [king] field is
/// kept for the existing rehydration path and basekubb-fallback logic
/// — the controller derives [kingOutcome] from [king] when the caller
/// does not pass one explicitly.
@immutable
class ScoreDraftSet {
  const ScoreDraftSet({
    this.basekubbsA = 0,
    this.basekubbsB = 0,
    this.king,
    this.kingOutcome = const KingMissed(),
  });

  final int basekubbsA;
  final int basekubbsB;
  final SetWinner? king;

  /// R11-F-01: explicit king-outcome for this set. Defaults to
  /// [KingMissed] so existing callers that only set [king] keep the
  /// historical implicit behaviour; the match-detail screen upgrades
  /// this to [KingHitBy] / [KingTimedOut] based on the tri-toggle.
  final KingOutcome kingOutcome;
}

/// State of the per-match draft controller. [hydratedForRound] tracks
/// which consensus round the [sets] were loaded for so the screen can
/// skip pre-fill once it has happened.
@immutable
class ScoreDraftState {
  const ScoreDraftState({this.hydratedForRound, this.sets = _defaultSets});

  final int? hydratedForRound;
  final List<ScoreDraftSet> sets;

  static const List<ScoreDraftSet> _defaultSets = <ScoreDraftSet>[
    ScoreDraftSet(),
  ];
}

/// Per-match score-input controller backed by `tournament_score_drafts`.
///
/// Hydrates the form on entry (DSCORE-20), upserts every edit so the
/// draft survives app-kill (DSCORE-19), and drops the row when the
/// caller acknowledges a successful submit (DSCORE-21).
class ScoreDraftController extends Notifier<ScoreDraftState> {
  ScoreDraftController(this._matchId);

  final TournamentMatchId _matchId;

  @override
  ScoreDraftState build() => const ScoreDraftState();

  /// Loads the persisted draft for `consensusRound` if the controller
  /// has not seen this round yet. Idempotent so the screen can call it
  /// on every build without thrashing the DAO.
  Future<void> init(int consensusRound) async {
    if (state.hydratedForRound == consensusRound) return;
    final loaded = await ref
        .read(tournamentScoreDraftDaoProvider)
        .load(_matchId, consensusRound);
    state = ScoreDraftState(
      hydratedForRound: consensusRound,
      sets: loaded == null
          ? const <ScoreDraftSet>[ScoreDraftSet()]
          : <ScoreDraftSet>[
              for (final s in loaded)
                ScoreDraftSet(
                  basekubbsA: s.basekubbsKnockedByA,
                  basekubbsB: s.basekubbsKnockedByB,
                  // M2b (D2): the tri-toggle's 'Keiner' selection is
                  // SetWinner.none on the wire but `null` (no king) in the
                  // form. Restore it as null so the toggle re-renders the
                  // prior selection; teamA/teamB map straight through.
                  king: s.winner == SetWinner.none ? null : s.winner,
                  // M2b (D2): restore the explicit king-outcome (incl. the
                  // KingTimedOut / KingHitBy / finisher-resolved variants)
                  // instead of defaulting to KingMissed, so a king /
                  // finisher selection survives a screen-switch / reload.
                  kingOutcome: s.kingOutcome,
                ),
            ],
    );
  }

  /// Replaces the in-memory draft and persists it. The DAO row keys on
  /// `(matchId, consensusRound)` so an upsert is sufficient. Callers
  /// invoke this for set edits, add-set and remove-set actions alike.
  Future<void> setSets(int consensusRound, List<ScoreDraftSet> next) async {
    state = ScoreDraftState(hydratedForRound: consensusRound, sets: next);
    final payload = <SetScore>[
      for (final d in next)
        SetScore(
          basekubbsKnockedByA: d.basekubbsA,
          basekubbsKnockedByB: d.basekubbsB,
          // M2b (D1): persist the explicit tri-toggle state. A king-less
          // set is the canonical SetWinner.none — the legacy
          // `basekubbsA >= basekubbsB` fallback forced an A/B winner and
          // erased the 'Keiner' / timed-out distinction, which the KO
          // finisher and the EKC 0:0 short-circuit both depend on.
          winner: d.king ?? SetWinner.none,
          // M2b (D1): persist the king-outcome alongside the score so the
          // selection (incl. KingTimedOut / KingHitBy / finisher result)
          // round-trips through the DAO.
          kingOutcome: d.kingOutcome,
        ),
    ];
    await ref
        .read(tournamentScoreDraftDaoProvider)
        .save(_matchId, consensusRound, payload);
  }

  /// Drops the persisted draft. Pass [consensusRound] after a successful
  /// submit to wipe only that round's row (DSCORE-21). Omit it to wipe
  /// every round for this match — used by terminal-status GC (DSCORE-22).
  Future<void> clear({int? consensusRound}) async {
    // M2b (D3): leave [hydratedForRound] null so the NEXT init(round)
    // genuinely reloads from the DAO. Previously this set
    // hydratedForRound == consensusRound, which made a subsequent
    // init(consensusRound) early-return the now-stale in-memory sets
    // instead of reading the freshly-deleted (empty) row.
    state = const ScoreDraftState();
    await ref
        .read(tournamentScoreDraftDaoProvider)
        .clear(_matchId, consensusRound: consensusRound);
  }
}

/// Family keyed by [TournamentMatchId] so two open match detail screens
/// (e.g. via deep-link race) don't cross-contaminate their drafts.
// ignore: specify_nonobvious_property_types
final scoreDraftControllerProvider = NotifierProvider.family<
    ScoreDraftController, ScoreDraftState, TournamentMatchId>(
  ScoreDraftController.new,
);
