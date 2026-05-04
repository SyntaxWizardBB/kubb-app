import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/disclaimer_block.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// 4-slide onboarding tour per design brief #9 (M5-T12, template
/// `OnboardingTour.jsx`). The reminder slide is only shown for
/// anonymous keypair sessions so OAuth users don't see the disclaimer
/// twice.
class OnboardingTour extends ConsumerStatefulWidget {
  const OnboardingTour({super.key});

  @override
  ConsumerState<OnboardingTour> createState() => _OnboardingTourState();
}

class _OnboardingTourState extends ConsumerState<OnboardingTour> {
  final _controller = PageController();
  int _index = 0;
  bool _animating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next(int total) async {
    if (_animating) return;
    if (_index >= total - 1) {
      _finish();
      return;
    }
    _animating = true;
    try {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } finally {
      if (mounted) _animating = false;
    }
  }

  Future<void> _back() async {
    if (_animating || _index == 0) return;
    _animating = true;
    try {
      await _controller.previousPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } finally {
      if (mounted) _animating = false;
    }
  }

  void _skip() {
    _finish();
  }

  void _finish() {
    GoRouter.of(context).go('/');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(authControllerProvider).maybeWhen(
          data: (s) => s,
          orElse: () => const AuthSession.signedOut(),
        );
    final isAnonymous = session.isAnonymousKeypair;

    final slides = <Widget>[
      _SlideWelcome(session: session),
      const _SlideModes(),
      const _SlideSoon(),
      if (isAnonymous) const _SlideReminder(),
    ];
    final total = slides.length;
    final isLast = _index >= total - 1;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              total: total,
              current: _index,
              showSkip: !isLast,
              onBack: _index == 0 ? null : _back,
              onSkip: _skip,
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: slides,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KubbTokens.space5,
                KubbTokens.space3,
                KubbTokens.space5,
                KubbTokens.space5,
              ),
              child: _PrimaryButton(
                label: isLast ? l10n.authOnboardingDone : l10n.authOnboardingNext,
                onPressed: () => _next(total),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.current,
    required this.showSkip,
    required this.onBack,
    required this.onSkip,
  });

  final int total;
  final int current;
  final bool showSkip;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space2,
        KubbTokens.space2,
        KubbTokens.space2,
        KubbTokens.space2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: KubbTokens.touchMin,
            height: KubbTokens.touchMin,
            child: onBack != null
                ? IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: l10n.authCommonBack,
                  )
                : null,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < total; i++) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == current ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i <= current
                          ? tokens.primary
                          : KubbTokens.stone200,
                      borderRadius:
                          BorderRadius.circular(KubbTokens.radiusPill),
                    ),
                  ),
                  if (i < total - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: showSkip
                ? Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: tokens.fgMuted,
                      ),
                      child: Text(
                        l10n.authOnboardingSkip,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _SlideWelcome extends StatelessWidget {
  const _SlideWelcome({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
      child: Column(
        children: [
          const SizedBox(height: KubbTokens.space5),
          Container(
            width: 200,
            height: 140,
            decoration: BoxDecoration(
              color: KubbTokens.meadow100,
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.sports_score,
              size: 80,
              color: KubbTokens.meadow700,
            ),
          ),
          const SizedBox(height: KubbTokens.space4),
          Text(
            l10n.authOnboardingWelcomeTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          Text(
            l10n.authOnboardingWelcomeBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: tokens.fgMuted,
            ),
          ),
          const SizedBox(height: KubbTokens.space4),
          _AccountBadge(session: session),
        ],
      ),
    );
  }
}

class _AccountBadge extends StatelessWidget {
  const _AccountBadge({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, icon) = session.maybeWhen(
      keypair: (_, _, _) => (l10n.authOnboardingBadgeAnon, Icons.lock_outline),
      oauth: (_, _, p, _, _) => p == AuthProvider.apple
          ? (l10n.authOnboardingBadgeApple, Icons.apple)
          : (l10n.authOnboardingBadgeGoogle, Icons.account_circle_outlined),
      orElse: () => (l10n.authOnboardingBadgeAnon, Icons.lock_outline),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: KubbTokens.meadow100,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: KubbTokens.meadow700),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KubbTokens.meadow800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideModes extends StatelessWidget {
  const _SlideModes();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    final modes = <_ModeRowData>[
      _ModeRowData(
        name: l10n.authOnboardingModeSniperName,
        sub: l10n.authOnboardingModeSniperSub,
        icon: Icons.gps_fixed,
        soon: false,
      ),
      _ModeRowData(
        name: l10n.authOnboardingModeFinisseurName,
        sub: l10n.authOnboardingModeFinisseurSub,
        icon: Icons.workspace_premium,
        soon: false,
      ),
      _ModeRowData(
        name: l10n.authOnboardingMode4mName,
        sub: l10n.authOnboardingMode4mSub,
        icon: Icons.local_fire_department,
        soon: true,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KubbTokens.space5),
          Text(
            l10n.authOnboardingModesTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space4),
          for (final m in modes) ...[
            _ModeRow(data: m),
            const SizedBox(height: KubbTokens.space2),
          ],
        ],
      ),
    );
  }
}

class _ModeRowData {
  const _ModeRowData({
    required this.name,
    required this.sub,
    required this.icon,
    required this.soon,
  });
  final String name;
  final String sub;
  final IconData icon;
  final bool soon;
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.data});

  final _ModeRowData data;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line, width: 1.5),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: KubbTokens.meadow100,
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
            alignment: Alignment.center,
            child: Icon(data.icon, color: KubbTokens.meadow700, size: 22),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        data.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tokens.fg,
                        ),
                      ),
                    ),
                    if (data.soon) ...[
                      const SizedBox(width: KubbTokens.space2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: KubbTokens.wood100,
                          borderRadius:
                              BorderRadius.circular(KubbTokens.radiusPill),
                        ),
                        child: Text(
                          l10n.authOnboardingSoonPill,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: KubbTokens.wood700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  data.sub,
                  style: TextStyle(fontSize: 13, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideSoon extends StatelessWidget {
  const _SlideSoon();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
      child: Column(
        children: [
          const SizedBox(height: KubbTokens.space5),
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: KubbTokens.meadow100,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.emoji_events_outlined,
              size: 60,
              color: KubbTokens.meadow600,
            ),
          ),
          const SizedBox(height: KubbTokens.space4),
          Text(
            l10n.authOnboardingSoonTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _SoonChip(label: l10n.authOnboardingSoonTournaments),
              _SoonChip(label: l10n.authOnboardingSoonFriendMatch),
            ],
          ),
          const SizedBox(height: KubbTokens.space3),
          Text(
            l10n.authOnboardingSoonBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: tokens.fgMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoonChip extends StatelessWidget {
  const _SoonChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: KubbTokens.meadow100,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: KubbTokens.meadow800,
        ),
      ),
    );
  }
}

class _SlideReminder extends StatelessWidget {
  const _SlideReminder();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: KubbTokens.space4),
          Text(
            l10n.authOnboardingReminderTitle,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space3),
          const DisclaimerBlock(),
          const SizedBox(height: KubbTokens.space3),
          Text(
            l10n.authOnboardingReminderQuestion,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(
            l10n.authOnboardingReminderBody,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: tokens.fgMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      width: double.infinity,
      height: KubbTokens.touchComfortable,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
