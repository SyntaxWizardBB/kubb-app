import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/features/auth/presentation/auth_routes.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int unread,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            appBar: AppBar(
              title: const Text('host'),
              actions: const [InboxBellAction()],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
        GoRoute(
          path: AuthRoutes.inbox,
          builder: (_, _) =>
              const Scaffold(body: Text('inbox-stub', key: Key('inbox-stub'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inboxUnreadCountProvider.overrideWithValue(unread),
        ],
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders bell icon without badge when unread is 0',
      (tester) async {
    await pump(tester, unread: 0);

    expect(find.byIcon(LucideIcons.bell), findsOneWidget);
    // No digit/badge label when count == 0.
    expect(find.text('0'), findsNothing);
    expect(find.text('9+'), findsNothing);
  });

  testWidgets('shows numeric badge for unread == 5', (tester) async {
    await pump(tester, unread: 5);

    expect(find.byIcon(LucideIcons.bell), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('shows 9+ overflow badge for unread == 42', (tester) async {
    await pump(tester, unread: 42);

    expect(find.byIcon(LucideIcons.bell), findsOneWidget);
    expect(find.text('9+'), findsOneWidget);
    expect(find.text('42'), findsNothing);
  });

  testWidgets('shows 9+ overflow badge for unread == 10 (boundary)',
      (tester) async {
    await pump(tester, unread: 10);

    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('shows 9 (no plus) for unread == 9 (boundary)', (tester) async {
    await pump(tester, unread: 9);

    expect(find.text('9'), findsOneWidget);
    expect(find.text('9+'), findsNothing);
  });

  testWidgets('tap navigates to inbox route', (tester) async {
    await pump(tester, unread: 3);

    expect(find.byKey(const Key('inbox-stub')), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.bell));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inbox-stub')), findsOneWidget);
  });

  testWidgets('hit-target meets touch-min (48dp)', (tester) async {
    await pump(tester, unread: 0);

    final size = tester.getSize(find.byType(InboxBellAction));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
