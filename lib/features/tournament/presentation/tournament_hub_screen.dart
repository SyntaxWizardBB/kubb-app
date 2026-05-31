import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_drawer.dart';
import 'package:kubb_app/core/ui/widgets/kubb_mode_card.dart';
import 'package:kubb_app/features/club/application/club_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Landing screen for the Tournaments tab (BottomNav branch 2).
///
/// Home-style overview with [KubbModeCard] tiles: the caller's
/// registrations, the public discovery list, a create-tournament entry
/// (gated on club role via `canPublishTournamentProvider`) and a stats
/// placeholder.
/// All targets live in the tournament branch, so a `context.push` keeps
/// them on this tab's stack (back returns here, the BottomNav stays put).
class TournamentHubScreen extends ConsumerWidget {
  const TournamentHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    // P5: publishing is gated on club role — owner/admin/organizer of any
    // club — rather than the old global is_organizer flag.
    final canPublish = ref.watch(canPublishTournamentProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );

    return Scaffold(
      backgroundColor: tokens.bg,
      drawer: const KubbDrawer(),
      // Create entry point for club owners/admins/organizers — the FAB that
      // used to live on the tournament list now sits on the hub overview.
      floatingActionButton: canPublish
          ? FloatingActionButton.extended(
              onPressed: () =>
                  unawaited(context.push(TournamentRoutes.newTournament)),
              icon: const Icon(LucideIcons.plus),
              label: Text(l.tournamentListNewButton),
            )
          : null,
      appBar: KubbAppBar.slots(
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            icon: const KubbIcon(LucideIcons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        eyebrow: Text(
          l.tournamentListEyebrow.toUpperCase(),
          style: t.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: tokens.fgMuted,
          ),
        ),
        title: Text(
          l.tournamentListTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.36,
            color: tokens.fg,
          ),
        ),
        trailing: const InboxBellAction(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space5,
          KubbTokens.space4,
          KubbTokens.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KubbModeCard(
              title: l.tournamentHubRegisteredTitle,
              subtitle: l.tournamentHubRegisteredSubtitle,
              icon: LucideIcons.clipboardCheck,
              accentTone: KubbChipTone.sniperMeadow,
              onTap: () =>
                  unawaited(context.push(TournamentRoutes.registrations)),
            ),
            const SizedBox(height: KubbTokens.space3),
            KubbModeCard(
              title: l.tournamentListTabPublic,
              subtitle: l.tournamentHubBrowseSubtitle,
              icon: KubbIcons.trophy,
              accentTone: KubbChipTone.tournamentWood,
              onTap: () => unawaited(context.push(TournamentRoutes.list)),
            ),
            const SizedBox(height: KubbTokens.space3),
            KubbModeCard(
              title: l.tournamentHubStatsTitle,
              subtitle: l.tournamentHubStatsSubtitle,
              icon: KubbIcons.stat,
              accentTone: KubbChipTone.neutral,
              onTap: () => unawaited(context.push(TournamentRoutes.stats)),
            ),
          ],
        ),
      ),
    );
  }
}
