import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// P7 edit-after-publish entry point. Loads the tournament detail, rebuilds
/// a [TournamentConfigDraft] from it via [TournamentConfigDraft.fromDetail]
/// and opens the [TournamentSetupWizard] in EDIT mode pre-filled with the
/// current values. The wizard submits through
/// `TournamentActions.updateTournament`.
///
/// Authority (who may reach this screen) is enforced two ways: the detail
/// screen only surfaces the "Bearbeiten" action to the creator while the
/// tournament is pre-start, and the server `tournament_update` RPC re-checks
/// creator + status. If the row is missing / not readable the screen shows
/// a localized not-found message.
class TournamentEditScreen extends ConsumerWidget {
  const TournamentEditScreen({required this.tournamentId, super.key});

  final TournamentId tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final detailAsync = ref.watch(tournamentDetailProvider(tournamentId));
    return detailAsync.when(
      loading: () => Scaffold(
        backgroundColor: tokens.bg,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: tokens.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              e.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return Scaffold(
            backgroundColor: tokens.bg,
            body: Center(child: Text(l.tournamentDetailNotFound)),
          );
        }
        // Seed the wizard's config controller from the current tournament
        // via a nested ProviderScope override so the step widgets start
        // pre-filled (they read the draft in their own initState). The
        // wizard submits through updateTournament because of editId.
        final initial = TournamentConfigDraft.fromDetail(detail.tournament);
        return ProviderScope(
          overrides: [
            tournamentConfigControllerProvider.overrideWith(
              () => TournamentConfigController(initial),
            ),
          ],
          child: TournamentSetupWizard(editId: tournamentId),
        );
      },
    );
  }
}
