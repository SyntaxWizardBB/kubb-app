import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Draft state for the seeding editor. `order` is the working copy the
/// `ReorderableListView` mutates, `autoOrder` is the immutable baseline
/// the "Auto wiederherstellen" button reverts to, and [config] feeds the
/// `startKoPhase` RPC call once the organizer commits.
///
/// [action] tracks the in-flight async lifecycle for the save / start
/// buttons so the screen can disable controls and surface errors without
/// the controller leaking try/catch plumbing into widget code.
class SeedingState {
  const SeedingState({
    required this.order,
    required this.autoOrder,
    required this.config,
    required this.action,
  });

  /// Empty placeholder used before [TournamentSeedingController.seed]
  /// has been called from the screen.
  const SeedingState.empty()
      : order = const <TournamentParticipantId>[],
        autoOrder = const <TournamentParticipantId>[],
        config = null,
        action = const AsyncValue<void>.data(null);

  final List<TournamentParticipantId> order;
  final List<TournamentParticipantId> autoOrder;
  final KoPhaseConfig? config;
  final AsyncValue<void> action;

  bool get isDirty {
    if (order.length != autoOrder.length) return true;
    for (var i = 0; i < order.length; i++) {
      if (order[i] != autoOrder[i]) return true;
    }
    return false;
  }

  SeedingState copyWith({
    List<TournamentParticipantId>? order,
    List<TournamentParticipantId>? autoOrder,
    KoPhaseConfig? config,
    AsyncValue<void>? action,
  }) {
    return SeedingState(
      order: order ?? this.order,
      autoOrder: autoOrder ?? this.autoOrder,
      config: config ?? this.config,
      action: action ?? this.action,
    );
  }
}

/// Per-tournament seeding editor. The provider is created via
/// `NotifierProvider.family` keyed by [TournamentId] so each tournament
/// gets its own working order while sharing the controller class.
class TournamentSeedingController extends Notifier<SeedingState> {
  TournamentSeedingController(this._tournamentId);

  final TournamentId _tournamentId;

  @override
  SeedingState build() => const SeedingState.empty();

  /// Primes the working order from the auto-seeded standings list.
  /// Idempotent: re-calling with the same [auto] no-ops so list re-fetches
  /// don't blow away manual reorders. [config] is passed through to
  /// [startKoPhase] verbatim.
  void seed({
    required List<TournamentParticipantId> auto,
    required KoPhaseConfig config,
  }) {
    final same = state.autoOrder.length == auto.length &&
        () {
          for (var i = 0; i < auto.length; i++) {
            if (state.autoOrder[i] != auto[i]) return false;
          }
          return true;
        }();
    if (same && state.config == config) return;
    state = SeedingState(
      order: List<TournamentParticipantId>.unmodifiable(auto),
      autoOrder: List<TournamentParticipantId>.unmodifiable(auto),
      config: config,
      action: const AsyncValue<void>.data(null),
    );
  }

  /// Drag-reorder hook for the `ReorderableListView`. Mirrors the
  /// idiomatic index-fixup Flutter ships in its samples (target index
  /// shifts left by one when dragging downwards because the item slot
  /// itself disappears).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final next = List<TournamentParticipantId>.of(state.order);
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (oldIndex < 0 || oldIndex >= next.length) return;
    if (adjusted < 0 || adjusted >= next.length) return;
    final item = next.removeAt(oldIndex);
    next.insert(adjusted, item);
    state = state.copyWith(order: next);
  }

  /// Reverts the working list back to the auto-seeded baseline.
  void restoreAuto() {
    state = state.copyWith(
      order: List<TournamentParticipantId>.of(state.autoOrder),
    );
  }

  /// Persists the current order via the `tournament_set_seeding` RPC.
  Future<void> save() async {
    if (state.action.isLoading) return;
    state = state.copyWith(action: const AsyncValue<void>.loading());
    final seeds = <TournamentParticipantId, int>{
      for (var i = 0; i < state.order.length; i++) state.order[i]: i + 1,
    };
    state = state.copyWith(
      action: await AsyncValue.guard(() async {
        await ref.read(tournamentRemoteProvider).setSeeding(
              tournamentId: _tournamentId,
              seeds: seeds,
            );
      }),
    );
  }

  /// Saves the current order (if dirty) and then triggers
  /// `tournament_start_ko_phase`. The repository swallows ERRCODE 40001
  /// so the caller treats the idempotent path as a regular success and
  /// navigates to the bracket without a special branch.
  Future<void> startKoPhase() async {
    if (state.action.isLoading) return;
    final config = state.config;
    if (config == null) {
      state = state.copyWith(
        action: AsyncValue<void>.error(
          StateError('KO config not loaded — call seed() first.'),
          StackTrace.current,
        ),
      );
      return;
    }
    state = state.copyWith(action: const AsyncValue<void>.loading());
    state = state.copyWith(
      action: await AsyncValue.guard(() async {
        final remote = ref.read(tournamentRemoteProvider);
        if (state.isDirty) {
          final seeds = <TournamentParticipantId, int>{
            for (var i = 0; i < state.order.length; i++)
              state.order[i]: i + 1,
          };
          await remote.setSeeding(
            tournamentId: _tournamentId,
            seeds: seeds,
          );
        }
        await remote.startKoPhase(_tournamentId, config);
      }),
    );
  }
}

/// One controller per [TournamentId]. Not auto-disposed — re-entering
/// the editor for the same tournament should preserve the working order
/// the organizer was tweaking.
// ignore: specify_nonobvious_property_types
final tournamentSeedingControllerProvider = NotifierProvider.family<
    TournamentSeedingController, SeedingState, TournamentId>(
  TournamentSeedingController.new,
);
