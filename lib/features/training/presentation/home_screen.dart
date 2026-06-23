import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_drawer.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/core/ui/widgets/kubb_mode_card.dart';
import 'package:kubb_app/core/ui/widgets/kubb_skeleton.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/pitch_call_banner.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_app/features/training/presentation/widgets/crash_recovery_dialog.dart';
import 'package:kubb_app/features/training/presentation/widgets/home_greeting.dart';
import 'package:kubb_app/features/training/presentation/widgets/news_card.dart';
import 'package:kubb_app/features/training/presentation/widgets/recent_section.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

const _newsUrl = 'https://kubbtour.ch';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final profile = ref.watch(displayProfileProvider);
    final recentAsync = ref.watch(recentActivityProvider);
    final recent = recentAsync.maybeWhen(
      data: (items) => items,
      orElse: () => const <RecentSessionView>[],
    );
    // Skeleton greift nur fuer den allerersten Load (kein data verfuegbar).
    final showRecentSkeleton = recentAsync.isLoading && !recentAsync.hasValue;
    // P4-C: organizer tile gate. Fail-closed — loading and error states
    // both resolve to false so the tile never flashes for non-organizers.
    final organizerVisible = ref.watch(organizerTileVisibleProvider).maybeWhen(
          data: (visible) => visible,
          orElse: () => false,
        );
    ref.listen(crashRecoveryProvider, (_, next) {
      next.whenData((session) {
        if (session == null) return;
        if (ref.read(crashRecoveryShownProvider)) return;
        ref.read(crashRecoveryShownProvider.notifier).mark(true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(CrashRecoveryDialog.show(context, session));
        });
      });
    });

    final greeting = profile == null
        ? l.homeGreetingFallback
        : l.homeGreeting(profile.displayName);

    return Scaffold(
      backgroundColor: tokens.bg,
      drawer: const KubbDrawer(),
      appBar: KubbAppBar.slots(
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            icon: const KubbIcon(LucideIcons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          l.homeAppTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
          KubbTokens.space4, KubbTokens.space6, KubbTokens.space4, 96,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeGreeting(eyebrow: l.homeEyebrow, greeting: greeting),
            const SizedBox(height: KubbTokens.space5),
            // Spec §4: the green "Dein Platz" match tile. Cross-tournament
            // (no tournamentId) — the banner folds the caller's most urgent
            // open match across all registered tournaments and renders
            // nothing when there is none (fail-closed, no placeholder). It
            // replaces both the old "Match-Modus / In Vorbereitung"
            // placeholder and the "Laufendes Match" card.
            const PitchCallBanner(),
            KubbModeCard(
              title: l.teamListTabMine,
              subtitle: l.teamListEmpty,
              icon: KubbIcons.players,
              accentTone: KubbChipTone.sniperMeadow,
              onTap: () => unawaited(context.push('/teams')),
            ),
            // P4-C (ADR-0032 §4): organizer tile — server-gated via the
            // `organizer_team_caller_is_organizer` RPC. Fail-closed:
            // loading/error hide the tile (incl. its spacer, so the layout
            // stays tight).
            if (organizerVisible) ...[
              const SizedBox(height: KubbTokens.space3),
              KubbModeCard(
                title: l.organizerTileTitle,
                subtitle: l.organizerTileSubtitle,
                icon: LucideIcons.shield,
                accentTone: KubbChipTone.tournamentWood,
                onTap: () =>
                    unawaited(context.push(TournamentRoutes.dashboard)),
              ),
            ],
            const SizedBox(height: KubbTokens.space3),
            NewsCard(
              eyebrow: l.homeNewsEyebrow,
              title: l.homeNewsTitle,
              subtitle: l.homeNewsSubtitle,
              onTap: _openNews,
            ),
            if (showRecentSkeleton) ...[
              const SizedBox(height: KubbTokens.space5),
              _RecentSkeleton(title: l.homeRecentTitle),
            ] else if (recent.isNotEmpty) ...[
              const SizedBox(height: KubbTokens.space5),
              RecentSection(title: l.homeRecentTitle, items: recent.take(3).toList()),
            ] else ...[
              const SizedBox(height: KubbTokens.space5),
              // Erst-Nutzer-Pfad: keine Sessions → Vignette + CTA, oeffnet
              // dieselbe TrainingSheet wie der FAB. Adressiert AUDIT §4.2
              // und R18-F-14 (Mängel #1: spartanische Empty-States).
              KubbEmptyState(
                title: l.emptySessionsTitle,
                body: l.emptySessionsBody,
                cta: KubbButton(
                  variant: KubbButtonVariant.primary,
                  // FAB + TrainingSheet wurden entfernt (P7); der Trainings-
                  // einstieg lebt jetzt im Training-Tab. Der CTA wechselt
                  // dorthin statt das alte Bottom-Sheet zu öffnen.
                  onPressed: () => context.go('/training'),
                  child: Text(l.emptySessionsCta),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openNews() async {
    await launchUrl(Uri.parse(_newsUrl), mode: LaunchMode.externalApplication);
  }
}

/// AUDIT §4.3 — drei Skeleton-Zeilen waehrend `recentSessionsProvider` laedt.
class _RecentSkeleton extends StatelessWidget {
  const _RecentSkeleton({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: t.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Container(
          key: const Key('home.recent.skeleton'),
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space3,
            vertical: KubbTokens.space2,
          ),
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                KubbSkeleton.row(
                  key: ValueKey('home.recent.skeleton.row.$i'),
                  columns: 3,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
