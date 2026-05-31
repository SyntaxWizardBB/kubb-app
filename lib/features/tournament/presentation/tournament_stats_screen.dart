import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Placeholder for the tournament statistics screen (P1 Tournament-Hub).
///
/// The hub links here so the entry point exists in the nav; the real
/// stats surface (standings history, placements, win rate) is a later
/// task. Until then the screen shows a "coming soon" empty state.
class TournamentStatsScreen extends StatelessWidget {
  const TournamentStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentListEyebrow,
        title: l.tournamentHubStatsTitle,
      ),
      body: Padding(
        padding: const EdgeInsets.all(KubbTokens.space5),
        child: KubbEmptyState(
          title: l.tournamentStatsComingSoonTitle,
          body: l.tournamentStatsComingSoonBody,
        ),
      ),
    );
  }
}
