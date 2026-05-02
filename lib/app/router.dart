import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const _OnboardingPlaceholder(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const _HomePlaceholder(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const _ProfilePlaceholder(),
    ),
    GoRoute(
      path: '/training/sniper/config',
      builder: (context, state) => const _SniperConfigPlaceholder(),
    ),
    GoRoute(
      path: '/training/sniper/session/:id',
      builder: (context, state) =>
          _SniperSessionPlaceholder(id: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(
      path: '/training/summary/:id',
      builder: (context, state) =>
          _SummaryPlaceholder(id: state.pathParameters['id'] ?? ''),
    ),
  ],
);

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final label = detail == null ? title : '$title — $detail';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('Placeholder — $label')),
    );
  }
}

class _OnboardingPlaceholder extends StatelessWidget {
  const _OnboardingPlaceholder();
  @override
  Widget build(BuildContext context) => const _Placeholder(title: 'Onboarding');
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();
  @override
  Widget build(BuildContext context) => const _Placeholder(title: 'Home');
}

class _ProfilePlaceholder extends StatelessWidget {
  const _ProfilePlaceholder();
  @override
  Widget build(BuildContext context) => const _Placeholder(title: 'Profile');
}

class _SniperConfigPlaceholder extends StatelessWidget {
  const _SniperConfigPlaceholder();
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Sniper Config');
}

class _SniperSessionPlaceholder extends StatelessWidget {
  const _SniperSessionPlaceholder({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) =>
      _Placeholder(title: 'Sniper Session', detail: id);
}

class _SummaryPlaceholder extends StatelessWidget {
  const _SummaryPlaceholder({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) =>
      _Placeholder(title: 'Summary', detail: id);
}
