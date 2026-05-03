import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders brand icon as Icon widget', (tester) async {
    await pump(tester, const KubbIcon(KubbIcons.heli));

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, KubbIcons.heli);
  });

  testWidgets('lucide factory honours custom size', (tester) async {
    await pump(tester, KubbIcon.lucide(LucideIcons.menu, size: 32));

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, LucideIcons.menu);
    expect(icon.size, 32);
  });

  testWidgets('falls back to tokens.fg when no color given', (tester) async {
    await pump(tester, const KubbIcon(KubbIcons.target));

    final icon = tester.widget<Icon>(find.byType(Icon));
    final BuildContext ctx = tester.element(find.byType(Icon));
    final tokens = Theme.of(ctx).extension<KubbTokens>();
    expect(icon.color, tokens?.fg);
  });
}
