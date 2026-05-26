// Tests target the expected T13 widget API. Compile stays red until
// the TeamMemberCard widget lands — see task brief.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/team/data/team_models.dart';
import 'package:kubb_app/features/team/presentation/widgets/team_member_card.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

TeamMembershipWire _member() => TeamMembershipWire(
      membershipId: 'mem-1',
      userId: 'u-1',
      joinedAt: DateTime.utc(2026, 5, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required String role,
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TeamMemberCard(
          member: _member(),
          role: role,
          onTap: onTap,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows "Gast" badge when role is guest', (tester) async {
    await _pump(tester, role: 'guest');
    expect(find.text('Gast'), findsOneWidget);
  });

  testWidgets('shows "Mitglied" badge when role is member', (tester) async {
    await _pump(tester, role: 'member');
    expect(find.text('Mitglied'), findsOneWidget);
  });

  testWidgets('tapping the card fires the onTap callback', (tester) async {
    var taps = 0;
    await _pump(tester, role: 'member', onTap: () => taps += 1);

    await tester.tap(find.byType(TeamMemberCard));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
