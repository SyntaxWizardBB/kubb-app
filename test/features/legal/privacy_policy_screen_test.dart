import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/legal/presentation/privacy_policy_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

const _fakePolicy = '''
# Datenschutzerklärung

Diese Erklärung informiert über die Verarbeitung personenbezogener Daten.

## 1. Verantwortlicher

> Owner-Eskalation: Adresse hier ergänzen.

## 2. Erhobene Daten

Profil, Trainings-Sessions, Matches.

## 3. Zweck der Verarbeitung

Bereitstellung der App.

## 4. Rechtsgrundlage

Art. 6 Abs. 1 lit. b DSGVO.

## 5. Datenfluss

Supabase EU-Region.

## 6. Speicherdauer

Bis zur Account-Löschung.

## 7. Betroffenenrechte

Auskunft, Berichtigung, Löschung.

## 8. Cookies und Tracking

Keine in der App.

## 9. Kontakt für Datenschutzfragen

> Owner-Eskalation: Kontakt hier ergänzen.
''';

Future<void> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/legal/privacy',
    routes: [
      GoRoute(
        path: '/legal/privacy',
        builder: (_, _) => const PrivacyPolicyScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    PrivacyPolicyScreen.loaderOverride = () async => _fakePolicy;
  });

  testWidgets('rendert Headings und Absätze aus Fake-Asset', (tester) async {
    PrivacyPolicyScreen.loaderOverride = () async => _fakePolicy;

    await _pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Datenschutzerklärung'), findsWidgets);
    expect(find.text('1. Verantwortlicher'), findsOneWidget);
    expect(find.text('2. Erhobene Daten'), findsOneWidget);
    expect(find.text('9. Kontakt für Datenschutzfragen'), findsOneWidget);
    expect(
      find.textContaining('Owner-Eskalation'),
      findsWidgets,
    );
  });

  testWidgets('zeigt Fallback-Text wenn Asset fehlt', (tester) async {
    PrivacyPolicyScreen.loaderOverride =
        () async => throw Exception('asset missing');

    await _pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('nicht verfügbar'),
      findsOneWidget,
    );
  });
}
