import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: KubbTheme.light(),
          home: Scaffold(appBar: child as PreferredSizeWidget),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders eyebrow and title together', (tester) async {
    await pump(
      tester,
      const KubbAppBar(
        eyebrow: 'Account',
        title: 'Profil',
      ),
    );

    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('shows custom action in the right slot', (tester) async {
    await pump(
      tester,
      KubbAppBar(
        title: 'Home',
        actions: [
          IconButton(
            key: const ValueKey('settings-btn'),
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
    );

    expect(find.byKey(const ValueKey('settings-btn')), findsOneWidget);
  });

  testWidgets('renders multiple actions in a row', (tester) async {
    await pump(
      tester,
      KubbAppBar(
        title: 'Home',
        actions: [
          IconButton(
            key: const ValueKey('action-a'),
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          IconButton(
            key: const ValueKey('action-b'),
            icon: const Icon(Icons.notifications),
            onPressed: () {},
          ),
        ],
      ),
    );

    expect(find.byKey(const ValueKey('action-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('action-b')), findsOneWidget);
  });

  testWidgets('exposes preferred size with status-bar padding', (tester) async {
    const bar = KubbAppBar(title: 'X');
    expect(bar.preferredSize.height, greaterThanOrEqualTo(64));
  });

  testWidgets('slot constructor renders leading, eyebrow, title and trailing',
      (tester) async {
    await pump(
      tester,
      KubbAppBar.slots(
        automaticallyImplyLeading: false,
        leading: const Icon(
          Icons.menu,
          key: ValueKey('slot-leading'),
        ),
        eyebrow: const Text(
          'STATS',
          key: ValueKey('slot-eyebrow'),
        ),
        title: const Text(
          'Statistik',
          key: ValueKey('slot-title'),
        ),
        trailing: IconButton(
          key: const ValueKey('slot-trailing'),
          icon: const Icon(Icons.filter_alt),
          onPressed: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('slot-leading')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-eyebrow')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('slot-trailing')), findsOneWidget);
  });

  testWidgets('slot constructor without eyebrow only renders title',
      (tester) async {
    await pump(
      tester,
      const KubbAppBar.slots(
        automaticallyImplyLeading: false,
        title: Text('Profil', key: ValueKey('slot-title-only')),
      ),
    );

    expect(find.byKey(const ValueKey('slot-title-only')), findsOneWidget);
    expect(find.text('STATS'), findsNothing);
  });

  testWidgets('trailing wins over the actions list', (tester) async {
    await pump(
      tester,
      const KubbAppBar(
        title: 'X',
        actions: [Icon(Icons.notifications, key: ValueKey('list-action'))],
        trailing: Icon(Icons.search, key: ValueKey('new-trailing')),
      ),
    );

    expect(find.byKey(const ValueKey('new-trailing')), findsOneWidget);
    expect(find.byKey(const ValueKey('list-action')), findsNothing);
  });
}
