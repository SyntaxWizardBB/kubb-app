import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/admin/admin_shell.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  const user = AdminUser(
    initials: 'MB',
    name: 'Marc B.',
    role: 'Turnierleiter · BKC',
  );

  Future<AdminSection?> pumpShell(
    WidgetTester tester, {
    AdminSection section = AdminSection.overview,
    Map<AdminSection, int> badges = const <AdminSection, int>{},
  }) async {
    AdminSection? tapped;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdminShell(
          section: section,
          onSelect: (s) => tapped = s,
          badges: badges,
          user: user,
          child: const Center(child: Text('content')),
        ),
      ),
    );
    return tapped;
  }

  testWidgets('lists every section once, in sidebar order', (tester) async {
    await pumpShell(tester);
    final l = await AppLocalizations.delegate.load(const Locale('de'));
    for (final section in AdminSection.values) {
      expect(find.text(section.label(l)), findsOneWidget);
    }
    expect(find.text('01'), findsOneWidget);
    expect(find.text('06'), findsOneWidget);
  });

  testWidgets('the rail keeps the design width and hands over the rest',
      (tester) async {
    await pumpShell(tester);
    expect(
      tester.getSize(find.byType(AdminShell)).width,
      1440,
    );
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('shows a badge only where a count was given', (tester) async {
    await pumpShell(
      tester,
      badges: const {
        AdminSection.disputes: 2,
        AdminSection.registrations: 0,
      },
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('0'), findsNothing,
        reason: 'an empty queue is not worth a badge');
  });

  testWidgets('reports the tapped section to the caller', (tester) async {
    AdminSection? tapped;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdminShell(
          section: AdminSection.overview,
          onSelect: (s) => tapped = s,
          user: user,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    final l = await AppLocalizations.delegate.load(const Locale('de'));
    await tester.tap(find.text(l.adminNavDisputes));
    await tester.pump();
    expect(tapped, AdminSection.disputes);
  });

  testWidgets('marks the active entry for assistive tech', (tester) async {
    await pumpShell(tester, section: AdminSection.teams);
    final l = await AppLocalizations.delegate.load(const Locale('de'));
    expect(
      tester.getSemantics(find.text(l.adminNavTeams)),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.text(l.adminNavOverview)),
      isSemantics(isSelected: false),
    );
  });
}
