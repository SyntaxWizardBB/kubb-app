import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_mode_card.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/player/presentation/player_hub_sheet.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_app/features/training/presentation/widgets/crash_recovery_dialog.dart';
import 'package:kubb_app/features/training/presentation/widgets/home_greeting.dart';
import 'package:kubb_app/features/training/presentation/widgets/news_card.dart';
import 'package:kubb_app/features/training/presentation/widgets/recent_section.dart';
import 'package:kubb_app/features/training/presentation/widgets/tournier_card.dart';
import 'package:kubb_app/features/training/presentation/widgets/training_sheet.dart';
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
    final recent = ref.watch(recentSessionsProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <RecentSessionView>[],
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
      appBar: KubbAppBar.slots(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: l.settingsTitle,
          icon: const KubbIcon(LucideIcons.menu),
          onPressed: () => context.push('/settings'),
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
        trailing: IconButton(
          tooltip: l.profileTitle,
          icon: const KubbIcon(KubbIcons.players),
          onPressed: () => PlayerHubSheet.show(context),
        ),
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
            TournierCard(
              eyebrow: l.homeTournierEyebrow,
              title: l.homeTournierTitle,
              subtitle: l.homeTournierComingSoon,
              onTap: () => context.push(TournamentRoutes.list),
            ),
            const SizedBox(height: KubbTokens.space3),
            KubbModeCard(
              title: l.teamListTabMine,
              subtitle: l.teamListEmpty,
              icon: KubbIcons.players,
              accentTone: KubbChipTone.sniperMeadow,
              onTap: () => unawaited(context.push('/teams')),
            ),
            const SizedBox(height: KubbTokens.space3),
            NewsCard(
              eyebrow: l.homeNewsEyebrow,
              title: l.homeNewsTitle,
              subtitle: l.homeNewsSubtitle,
              onTap: _openNews,
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: KubbTokens.space5),
              RecentSection(title: l.homeRecentTitle, items: recent.take(3).toList()),
            ],
          ],
        ),
      ),
      // Smoke-Migration auf KubbButton (W2-T4 Sprint B). Andere Konsumenten
      // werden im Sweep-Follow-up migriert.
      floatingActionButton: KubbButton(
        variant: KubbButtonVariant.primary,
        size: KubbButtonSize.large,
        onPressed: () => TrainingSheet.show(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KubbIcon(LucideIcons.plus),
            const SizedBox(width: KubbTokens.space2),
            Text(l.homeFabLabel),
          ],
        ),
      ),
    );
  }

  Future<void> _openNews() async {
    await launchUrl(Uri.parse(_newsUrl), mode: LaunchMode.externalApplication);
  }
}
