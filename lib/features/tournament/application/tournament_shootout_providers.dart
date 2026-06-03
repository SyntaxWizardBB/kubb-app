import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Open shoot-out tie groups of the family tournament for the caller (status
/// `pending`/`reported`). Backed by [TournamentRemote.listPendingShootouts],
/// which reads the RLS-gated `tournament_shootouts` table. The report/confirm
/// actions invalidate this so the list refreshes after a mutation.
// ignore: specify_nonobvious_property_types
final pendingShootoutsProvider =
    FutureProvider.family<List<PendingShootout>, TournamentId>(
  (ref, tournamentId) async {
    return ref.read(tournamentRemoteProvider).listPendingShootouts(tournamentId);
  },
);

/// Imperative action surface for shoot-out report/confirm, mirroring the
/// `TournamentActions` pattern: keeps the invalidate-after-write plumbing out
/// of the widget layer.
final tournamentShootoutActionsProvider =
    Provider<TournamentShootoutActions>((ref) {
  return TournamentShootoutActions(ref);
});

/// Thin facade over the shoot-out methods of [TournamentRemote]. Each
/// mutation invalidates the pending-shootouts provider (and the tournament
/// detail) so an open group flips state / drops out immediately.
class TournamentShootoutActions {
  TournamentShootoutActions(this._ref);
  final Ref _ref;

  /// Reports [orderedWinners] for [shootoutId]. [orderedWinners] must already
  /// be a full permutation of the tied set — the caller validates this and the
  /// server enforces it (`INVALID_ORDER`).
  Future<void> reportWinners({
    required TournamentId tournamentId,
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) async {
    await _ref.read(tournamentRemoteProvider).reportShootoutWinners(
          shootoutId: shootoutId,
          orderedWinners: orderedWinners,
        );
    _invalidate(tournamentId);
  }

  /// Confirms [orderedWinners] for [shootoutId]. The ordering must match the
  /// previously reported one exactly (server raises `ORDER_MISMATCH`).
  Future<void> confirm({
    required TournamentId tournamentId,
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) async {
    await _ref.read(tournamentRemoteProvider).confirmShootout(
          shootoutId: shootoutId,
          orderedWinners: orderedWinners,
        );
    _invalidate(tournamentId);
  }

  void _invalidate(TournamentId tournamentId) {
    _ref
      ..invalidate(pendingShootoutsProvider(tournamentId))
      ..invalidate(tournamentDetailProvider(tournamentId));
  }
}
