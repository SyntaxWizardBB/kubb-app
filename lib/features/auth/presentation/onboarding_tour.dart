import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/auth/presentation/auth_widgets/auth_primary_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Volatile flag that records whether the onboarding tour has run in
/// this app process. Setting it on completion gives the router a hook
/// to skip the tour on subsequent visits. Persistence is intentionally
/// deferred — once a `sharedPreferencesProvider` (or equivalent
/// key/value store) lands in the bootstrap layer, [OnboardingDone]
/// should be swapped for a notifier that reads/writes `onboarding_done`
/// from disk.
class OnboardingDone extends Notifier<bool> {
  @override
  bool build() => false;

  void markDone() => state = true;
}

final onboardingDoneProvider =
    NotifierProvider<OnboardingDone, bool>(OnboardingDone.new);

/// 4-slide onboarding tour per AUDIT §2.4. Each slide combines a
/// K+Crown vignette with the verbatim title/body strings the audit
/// laid out for sniper / finisseur / tournaments / social. The tour
/// ends on the Sign-In hub.
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

  void _skip() => _finish();

  void _finish() {
    ref.read(onboardingDoneProvider.notifier).markDone();
    GoRouter.of(context).go(AuthRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l10n = AppLocalizations.of(context);

    final slides = <_SlideData>[
      _SlideData(
        title: l10n.onboardingSlide1Title,
        body: l10n.onboardingSlide1Body,
        glyph: Icons.gps_fixed,
      ),
      _SlideData(
        title: l10n.onboardingSlide2Title,
        body: l10n.onboardingSlide2Body,
        glyph: Icons.workspace_premium,
      ),
      _SlideData(
        title: l10n.onboardingSlide3Title,
        body: l10n.onboardingSlide3Body,
        glyph: Icons.emoji_events_outlined,
      ),
      _SlideData(
        title: l10n.onboardingSlide4Title,
        body: l10n.onboardingSlide4Body,
        glyph: Icons.groups_outlined,
      ),
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
              onSkip: _skip,
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: total,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _Slide(data: slides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KubbTokens.space5,
                KubbTokens.space3,
                KubbTokens.space5,
                KubbTokens.space5,
              ),
              child: AuthPrimaryButton(
                label: isLast ? l10n.onboardingDone : l10n.onboardingNext,
                onPressed: () => _next(total),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideData {
  const _SlideData({
    required this.title,
    required this.body,
    required this.glyph,
  });
  final String title;
  final String body;
  final IconData glyph;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.current,
    required this.onSkip,
  });

  final int total;
  final int current;
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
          const SizedBox(width: 90),
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
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: tokens.fgMuted,
                ),
                child: Text(
                  l10n.onboardingSkip,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.data});

  final _SlideData data;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Vignette(glyph: data.glyph),
          const SizedBox(height: KubbTokens.space6),
          Text(
            data.title,
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
            data.body,
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

/// K+Crown vignette per design brief — a meadow-tinted disc with the
/// mode glyph and a small wood-coloured crown accent sitting on top.
class _Vignette extends StatelessWidget {
  const _Vignette({required this.glyph});

  final IconData glyph;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: const BoxDecoration(
              color: KubbTokens.meadow100,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              glyph,
              size: 72,
              color: KubbTokens.meadow700,
            ),
          ),
          const Positioned(
            top: -4,
            child: Icon(
              Icons.workspace_premium,
              size: 32,
              color: KubbTokens.wood400,
            ),
          ),
        ],
      ),
    );
  }
}
