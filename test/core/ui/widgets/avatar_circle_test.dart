import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('renders the initials text', (tester) async {
    await pump(
      tester,
      const AvatarCircle(initials: 'LB', color: Colors.green),
    );

    expect(find.text('LB'), findsOneWidget);
  });

  testWidgets('uses the requested size', (tester) async {
    await pump(
      tester,
      const AvatarCircle(initials: 'L', color: Colors.green, size: 64),
    );

    final container = tester.widget<Container>(
      find.byType(Container).first,
    );
    expect(container.constraints?.maxWidth, 64);
    expect(container.constraints?.maxHeight, 64);
  });
}
