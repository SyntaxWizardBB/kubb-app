import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/achievements/presentation/achievements_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// W6-T2 — Widget-Tests fuer den Achievements-Skeleton.
///
/// Deckt zwei Zustaende ab:
/// 1. Default-Mock: keine erspielten Badges + 5 Placeholder-Locked-Cards.
/// 2. Empty-State: weder erspielt noch offen — KubbEmptyState + CTA.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders eyebrow + title + five placeholder badges by default',
      (tester) async {
    await pump(tester, const AchievementsScreen());

    expect(find.text('PROFIL'), findsOneWidget);
    expect(find.text('Erfolge'), findsOneWidget);
    expect(find.text('NOCH OFFEN'), findsOneWidget);
    // "Erspielt"-Sektion wird im Default-Mock NICHT gerendert
    // (kein earned-Badge).
    expect(find.text('ERSPIELT'), findsNothing);

    // Alle fuenf Placeholder-Cards rendern mit ihrer ValueKey.
    for (final id in const [
      'first-hit',
      'hundred-hits',
      'streak',
      'heli',
      'king',
    ]) {
      expect(
        find.byKey(ValueKey('achievements.badge.$id')),
        findsOneWidget,
        reason: 'Badge $id should be present',
      );
    }
  });

  testWidgets('renders KubbEmptyState when both sections are empty',
      (tester) async {
    await pump(
      tester,
      const AchievementsScreen(
        earned: <AchievementBadge>[],
        locked: <AchievementBadge>[],
      ),
    );

    expect(find.text('Noch keine Erfolge'), findsOneWidget);
    expect(find.text('Sniper starten'), findsOneWidget);
    // Keine Section-Header im Empty-Zustand.
    expect(find.text('NOCH OFFEN'), findsNothing);
    expect(find.text('ERSPIELT'), findsNothing);
  });

  testWidgets('renders earned + locked sections when both are provided',
      (tester) async {
    const earned = [
      AchievementBadge(
        id: 'demo-earned',
        title: 'Demo-Erfolg',
        description: 'Test-Badge',
        glyph: LucideIcons.award,
        earnedLabel: 'Erspielt am 01.05.2026',
      ),
    ];
    const locked = [
      AchievementBadge(
        id: 'demo-locked',
        title: 'Noch nicht',
        description: 'Test-Lock',
        glyph: LucideIcons.target,
        trigger: '100 Treffer',
      ),
    ];

    await pump(
      tester,
      const AchievementsScreen(earned: earned, locked: locked),
    );

    expect(find.text('ERSPIELT'), findsOneWidget);
    expect(find.text('NOCH OFFEN'), findsOneWidget);
    expect(find.text('Demo-Erfolg'), findsOneWidget);
    expect(find.text('Noch nicht'), findsOneWidget);
    expect(find.text('Erspielt am 01.05.2026'), findsOneWidget);
    expect(find.text('Bei 100 Treffer freigeschaltet'), findsOneWidget);
  });
}
