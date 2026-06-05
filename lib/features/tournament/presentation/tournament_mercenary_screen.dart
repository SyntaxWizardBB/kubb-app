import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Mercenary market ("Söldnermarkt") reached from the hub.
///
/// P8: Coming-Soon placeholder only — no list or data logic yet. It
/// renders the shared [KubbEmptyState] with a friendly German teaser.
class TournamentMercenaryScreen extends StatelessWidget {
  const TournamentMercenaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.tournamentMercenaryEyebrow,
        title: l.tournamentMercenaryTitle,
        actions: const [InboxBellAction()],
      ),
      body: KubbEmptyState(
        title: l.tournamentMercenaryComingSoonTitle,
        body: l.tournamentMercenaryComingSoonBody,
      ),
    );
  }
}
