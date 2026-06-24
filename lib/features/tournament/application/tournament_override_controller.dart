import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Draft state for the organizer override flow. Mirrors the per-set
/// shape used by the regular score-entry surface, plus the mandatory
/// reason. The reason caps at [TournamentOverrideController.reasonMax]
/// characters per spec DSCORE-55.
class TournamentOverrideDraft {
  const TournamentOverrideDraft({
    required this.sets,
    required this.reason,
    this.submitting = false,
  });

  const TournamentOverrideDraft.initial()
      : sets = const <TournamentOverrideSetDraft>[
          TournamentOverrideSetDraft(),
        ],
        reason = '',
        submitting = false;

  final List<TournamentOverrideSetDraft> sets;
  final String reason;
  final bool submitting;

  TournamentOverrideDraft copyWith({
    List<TournamentOverrideSetDraft>? sets,
    String? reason,
    bool? submitting,
  }) {
    return TournamentOverrideDraft(
      sets: sets ?? this.sets,
      reason: reason ?? this.reason,
      submitting: submitting ?? this.submitting,
    );
  }
}

/// One row in the override draft. `king == null` means time-out / kein
/// Königsstoss — the screen still requires the winner to be derivable.
class TournamentOverrideSetDraft {
  const TournamentOverrideSetDraft({
    this.basekubbsA = 0,
    this.basekubbsB = 0,
    this.king,
  });

  final int basekubbsA;
  final int basekubbsB;
  final SetWinner? king;
}

class TournamentOverrideController
    extends Notifier<TournamentOverrideDraft> {
  /// Spec DSCORE-55: free-text reason, capped to keep audit storage
  /// predictable.
  static const int reasonMax = 500;

  @override
  TournamentOverrideDraft build() =>
      const TournamentOverrideDraft.initial();

  void setReason(String value) {
    if (value.length > reasonMax) {
      state = state.copyWith(reason: value.substring(0, reasonMax));
      return;
    }
    state = state.copyWith(reason: value);
  }

  void updateSet(int index, TournamentOverrideSetDraft draft) {
    if (index < 0 || index >= state.sets.length) return;
    final next = List<TournamentOverrideSetDraft>.of(state.sets);
    next[index] = draft;
    state = state.copyWith(sets: next);
  }

  void addSet({required int maxSets}) {
    if (state.sets.length >= maxSets) return;
    state = state.copyWith(
      sets: <TournamentOverrideSetDraft>[
        ...state.sets,
        const TournamentOverrideSetDraft(),
      ],
    );
  }

  void removeSet() {
    if (state.sets.length <= 1) return;
    state = state.copyWith(
      sets: state.sets.sublist(0, state.sets.length - 1),
    );
  }

  /// Builds the domain `SetScore` list from the current draft. When the
  /// king toggle is unset, the higher basekubb count breaks the tie —
  /// matches the regular score-entry screen.
  List<SetScore> toSetScores() => <SetScore>[
        for (final d in state.sets)
          SetScore(
            basekubbsKnockedByA: d.basekubbsA,
            basekubbsKnockedByB: d.basekubbsB,
            winner: d.king ??
                (d.basekubbsA >= d.basekubbsB
                    ? SetWinner.teamA
                    : SetWinner.teamB),
          ),
      ];

  /// `true` when one side reaches [setsToWin] sets — the override is
  /// only meaningful for a decisive series.
  bool isScoreDecisive(int setsToWin) {
    final ekc = computeEkc(toSetScores());
    return ekc.setsWonA >= setsToWin || ekc.setsWonB >= setsToWin;
  }

  bool isReasonValid() {
    final trimmed = state.reason.trim();
    return trimmed.isNotEmpty && trimmed.length <= reasonMax;
  }

  Future<void> submit(TournamentMatchId matchId, {required int setsToWin}) async {
    if (state.submitting) return;
    if (!isReasonValid() || !isScoreDecisive(setsToWin)) {
      throw StateError('override draft is not ready to submit');
    }
    state = state.copyWith(submitting: true);
    try {
      await ref.read(tournamentActionsProvider).organizerOverride(
            matchId: matchId,
            finalSetScores: toSetScores(),
            reason: state.reason.trim(),
          );
    } finally {
      if (ref.mounted) {
        state = state.copyWith(submitting: false);
      }
    }
  }

  /// Reason-free organizer score entry (cockpit-spec §5). Reuses the same
  /// organizer-authoritative write path as [submit] — the override RPC accepts
  /// an empty reason and the audit trail records who/when/what either way — but
  /// drops the [isReasonValid] precondition so the organizer can set the result
  /// for any (also non-disputed) match without a justification. The score must
  /// still be decisive.
  Future<void> submitDirect(
    TournamentMatchId matchId, {
    required int setsToWin,
  }) async {
    if (state.submitting) return;
    if (!isScoreDecisive(setsToWin)) {
      throw StateError('direct score draft is not ready to submit');
    }
    state = state.copyWith(submitting: true);
    try {
      await ref.read(tournamentActionsProvider).organizerOverride(
            matchId: matchId,
            finalSetScores: toSetScores(),
            reason: state.reason.trim(),
          );
    } finally {
      if (ref.mounted) {
        state = state.copyWith(submitting: false);
      }
    }
  }
}

/// Auto-disposed so re-entering the override surface starts from a
/// clean draft.
// ignore: specify_nonobvious_property_types
final tournamentOverrideControllerProvider =
    NotifierProvider.autoDispose<TournamentOverrideController,
        TournamentOverrideDraft>(TournamentOverrideController.new);
