import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/settings/app_settings_modal.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_app/features/training/presentation/widgets/home_greeting.dart';
import 'package:kubb_app/features/training/presentation/widgets/news_card.dart';
import 'package:kubb_app/features/training/presentation/widgets/recent_section.dart';
import 'package:kubb_app/features/training/presentation/widgets/tournier_card.dart';
import 'package:kubb_app/features/training/presentation/widgets/training_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

const _newsUrl = 'https://kubbtour.ch';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider);
    final recent = ref.watch(recentSessionsProvider).maybeWhen(
          data: (items) => items,
          orElse: () => const <RecentSessionView>[],
        );

    final greeting = profile.maybeWhen(
      data: (p) => p == null ? l.homeGreetingFallback : l.homeGreeting(p.name),
      orElse: () => l.homeGreetingFallback,
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        title: l.homeAppTitle,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: l.settingsTitle,
          icon: const KubbIcon(LucideIcons.menu),
          onPressed: () => AppSettingsModal.show(context),
        ),
        actions: IconButton(
          tooltip: l.profileTitle,
          icon: const KubbIcon(KubbIcons.profile),
          onPressed: () => context.go('/profile'),
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
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.homeTournierTapToast)),
              ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TrainingSheet.show(context),
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        icon: KubbIcon(LucideIcons.plus, color: tokens.onPrimary),
        label: Text(l.homeFabLabel),
      ),
    );
  }

  Future<void> _openNews() async {
    await launchUrl(Uri.parse(_newsUrl), mode: LaunchMode.externalApplication);
  }
}
