import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_drawer.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/core/ui/widgets/kubb_mode_card.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
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
            // H1: "Live Turniere" — the caller's own running tournaments.
            // Tapping routes by count: 1 -> straight into the H3 live view,
            // many -> a picker bottom-sheet, none -> an empty-state hint.
            KubbModeCard(
              title: l.tournamentHubLiveTitle,
              subtitle: l.tournamentHubLiveSubtitle,
              icon: LucideIcons.radio,
              accentTone: KubbChipTone.sniperMeadow,
              onTap: () => unawaited(_onLiveTap(context, ref)),
            ),
            const SizedBox(height: KubbTokens.space3),
            // H1: "Künftige Turniere" — discovery list, now date-filtered
            // (event_starts_at >= today OR undated; live excluded).
            KubbModeCard(
              title: l.tournamentHubUpcomingTitle,
              subtitle: l.tournamentHubUpcomingSubtitle,
              icon: KubbIcons.trophy,
              accentTone: KubbChipTone.tournamentWood,
              onTap: () => unawaited(context.push(TournamentRoutes.list)),
            ),
            const SizedBox(height: KubbTokens.space3),
            // P8: past (finalized) tournaments.
            KubbModeCard(
              title: l.tournamentHubPastTitle,
              subtitle: l.tournamentHubPastSubtitle,
              icon: LucideIcons.history,
              accentTone: KubbChipTone.finisseurInk,
              onTap: () =>
                  unawaited(context.push(TournamentRoutes.pastTournaments)),
            ),
            const SizedBox(height: KubbTokens.space3),
            // P8-Hub-B2: all-time tournament leaderboard.
            KubbModeCard(
              title: l.tournamentHubRankingTitle,
              subtitle: l.tournamentHubRankingSubtitle,
              icon: LucideIcons.listOrdered,
              accentTone: KubbChipTone.sniperMeadow,
              onTap: () => unawaited(context.push(TournamentRoutes.ranking)),
            ),
            const SizedBox(height: KubbTokens.space3),
            // ELO_RATINGS §7: global tournament-ELO best-list over players.
            KubbModeCard(
              title: l.eloLeaderboardHubTitle,
              subtitle: l.eloLeaderboardHubSubtitle,
              icon: LucideIcons.trophy,
              accentTone: KubbChipTone.tournamentWood,
              onTap: () =>
                  unawaited(context.push(TournamentRoutes.eloLeaderboard)),
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

  /// H1 "Live Turniere" routing: resolve the caller's live tournaments and
  /// branch by count — 1 -> push the H3 live view directly; many -> show a
  /// picker that pushes the chosen one; none -> open the empty-state hint.
  /// The H3 3-tab view itself is never duplicated; it is only reached via
  /// [TournamentRoutes.live].
  Future<void> _onLiveTap(BuildContext context, WidgetRef ref) async {
    final live = await ref.read(myLiveTournamentsProvider.future);
    if (!context.mounted) return;
    if (live.length == 1) {
      await context.push(TournamentRoutes.live(live.first.tournamentId.value));
      return;
    }
    if (live.isEmpty) {
      await _showLiveEmpty(context);
      return;
    }
    await _showLivePicker(context, live);
  }

  /// Bottom-sheet picker listing the caller's live tournaments; each row
  /// pushes that tournament's H3 live view.
  Future<void> _showLivePicker(
    BuildContext context,
    List<TournamentSummaryRef> live,
  ) async {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.bgRaised,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: KubbTokens.space3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KubbTokens.space4,
                    KubbTokens.space2,
                    KubbTokens.space4,
                    KubbTokens.space3,
                  ),
                  child: Text(
                    l.tournamentHubLivePickerTitle,
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tokens.fg,
                        ),
                  ),
                ),
                for (final t in live)
                  ListTile(
                    leading: const KubbIcon(LucideIcons.radio),
                    title: Text(t.displayName),
                    minVerticalPadding: KubbTokens.space3,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(
                        context.push(
                          TournamentRoutes.live(t.tournamentId.value),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Empty-state hint shown when the caller has no live tournament.
  Future<void> _showLiveEmpty(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.bgRaised,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KubbTokens.space4),
          child: KubbEmptyState(
            title: l.tournamentHubLiveEmptyTitle,
            body: l.tournamentHubLiveEmptyBody,
          ),
        ),
      ),
    );
  }
}
