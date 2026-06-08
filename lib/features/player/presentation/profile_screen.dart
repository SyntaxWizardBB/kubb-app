import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/club/application/club_providers.dart';
import 'package:kubb_app/features/club/data/club_models.dart';
import 'package:kubb_app/features/club/presentation/club_routes.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/player/application/player_ratings_provider.dart';
import 'package:kubb_app/features/player/presentation/avatar_color.dart';
import 'package:kubb_app/features/player/presentation/player_elo_summary.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Read-only profile surface. Edit-mode lives in `EditProfileScreen` —
/// the button at the bottom navigates there.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final profile = ref.watch(displayProfileProvider);
    final session = ref.watch(authControllerProvider).maybeWhen(
          data: (s) => s,
          orElse: () => const AuthSession.signedOut(),
        );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar.slots(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: tokens.fg,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
        eyebrow: Text(
          l.authEditProfileEyebrow.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted,
              ),
        ),
        title: Text(
          l.profileTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.36,
                color: tokens.fg,
              ),
        ),
      ),
      body: SafeArea(
        child: profile == null
            ? Center(child: Text(l.profileNotLoaded))
            : _Body(profile: profile, session: session, tokens: tokens, l: l),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.profile,
    required this.session,
    required this.tokens,
    required this.l,
  });

  final DisplayProfile profile;
  final AuthSession session;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final color = AvatarColorHelper.resolve(
      profile.avatarColor,
      seed: profile.userId,
    );
    final initials = AvatarColorHelper.initialsFor(profile.displayName);
    final providerLabel = session.maybeWhen(
      keypair: (_, _, _) => l.authAccountProviderAnonymous,
      oauth: (_, _, p, _, _) => p == AuthProvider.apple
          ? l.authAccountProviderApple
          : l.authAccountProviderGoogle,
      orElse: () => l.authAccountProviderAnonymous,
    );

    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space6,
        vertical: KubbTokens.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AvatarCircle(initials: initials, color: color)),
          const SizedBox(height: KubbTokens.space6),
          Center(
            child: Text(
              profile.displayName,
              style: textTheme.displaySmall?.copyWith(color: tokens.fg),
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          Center(child: _ProviderBadge(label: providerLabel)),
          const SizedBox(height: KubbTokens.space8),
          _EloSection(userId: profile.userId),
          const _ClubsSection(),
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: OutlinedButton(
              onPressed: () =>
                  GoRouter.of(context).push<void>(AuthRoutes.editProfile),
              child: Text(l.profileEditButton),
            ),
          ),
        ],
      ),
    );
  }
}

/// ELO ratings of the current user. The personal ELO only appears when the
/// server (RLS) returns a `personal` row — on the own profile that is always
/// the owner case. Renders nothing while loading/erroring so the profile stays
/// clean.
class _EloSection extends ConsumerWidget {
  const _EloSection({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(playerRatingsProvider(userId)).maybeWhen(
          data: (ratings) => Padding(
            padding: const EdgeInsets.only(bottom: KubbTokens.space8),
            child: PlayerEloSummary(ratings: ratings),
          ),
          orElse: () => const SizedBox.shrink(),
        );
  }
}

/// Shows the player's club memberships (P5). Tapping a club opens its detail.
/// Renders nothing while loading/empty so the profile stays clean for players
/// who are not in a club.
class _ClubsSection extends ConsumerWidget {
  const _ClubsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final clubs = ref.watch(clubListProvider).maybeWhen(
          data: (c) => c,
          orElse: () => const <ClubWire>[],
        );
    if (clubs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'MEINE VEREINE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Wrap(
          spacing: KubbTokens.space2,
          runSpacing: KubbTokens.space2,
          children: [
            for (final club in clubs)
              ActionChip(
                label: Text(club.displayName),
                onPressed: () => context.push(ClubRoutes.detailFor(club.id)),
              ),
          ],
        ),
        const SizedBox(height: KubbTokens.space8),
      ],
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space1,
      ),
      decoration: BoxDecoration(
        color: KubbTokens.meadow100,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: KubbTokens.meadow800,
        ),
      ),
    );
  }
}
