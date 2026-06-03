import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// KO bracket screen for one tournament. Reads
/// [tournamentBracketProvider] and renders the read-only
/// [BracketCanvas]. Shows an empty-state while the tournament is still
/// in the group phase (server returns no KO rows, bracket is empty).
///
/// Editing happens in dedicated screens (seeding T11, override T-existing)
/// so this screen passes `editable: false` to the canvas.
class TournamentBracketScreen extends ConsumerWidget {
  const TournamentBracketScreen({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final id = TournamentId(tournamentId);
    // Keep the bracket polling alive while this screen is mounted so
    // newly advanced winners surface without manual reloads (M1 spec).
    ref.watch(tournamentBracketPollingProvider(id));
    final async = ref.watch(tournamentBracketProvider(id));

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: AppBar(
        backgroundColor: tokens.bg,
        elevation: 0,
        leading: BackButton(
          onPressed: () => context.go(
            '${TournamentRoutes.detail}/$tournamentId',
          ),
        ),
        title: Text(l.tournamentBracketTitle),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              '${l.tournamentBracketLoadError}: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (bracket) {
          if (_isEmpty(bracket)) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(KubbTokens.space5),
                child: Text(
                  l.tournamentBracketEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.fgMuted),
                ),
              ),
            );
          }
          return BracketCanvas(
            bracket: bracket,
            editable: false,
            tournamentId: id,
          );
        },
      ),
    );
  }

  /// A bracket counts as empty when the server returned no KO rounds
  /// (tournament still in group phase) or every round is pairing-less.
  ///
  /// Exhaustive over all three sealed [Bracket] subtypes — the inverse of the
  /// `hasBracket` switch in `tournament_detail_screen.dart`: a
  /// [ConsolationBracket] (Modell B, ADR-0028) counts as non-empty once either
  /// its main tree or any consolation round has been materialised, and a
  /// [DoubleEliminationBracket] once its WB has rounds.
  bool _isEmpty(Bracket bracket) {
    bool roundsEmpty(List<BracketRound> rounds) =>
        rounds.isEmpty || rounds.every((r) => r.pairings.isEmpty);
    return switch (bracket) {
      SingleEliminationBracket(:final rounds) => roundsEmpty(rounds),
      DoubleEliminationBracket(:final wbRounds) => roundsEmpty(wbRounds),
      ConsolationBracket(:final mainRounds, :final rounds) =>
        roundsEmpty(mainRounds) && roundsEmpty(rounds),
    };
  }
}
