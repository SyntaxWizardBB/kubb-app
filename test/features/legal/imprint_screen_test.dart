import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/legal/presentation/imprint_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

const _fakeImprint = '''
# Impressum

Angaben gemäß Informationspflichten.

## 1. Verantwortlich für den Inhalt

> Owner-Eskalation: Adresse hier ergänzen.

## 2. Kontakt

> Owner-Eskalation: Kontakt hier ergänzen.

## 3. Rechtliche Hinweise

Inhalte werden mit Sorgfalt erstellt.

## 4. Vereinsangaben

> Owner-Eskalation: Vereinsname und UID hier ergänzen.
''';

Future<void> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/legal/imprint',
    routes: [
      GoRoute(
        path: '/legal/imprint',
        builder: (_, _) => const ImprintScreen(),
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
    ImprintScreen.loaderOverride = () async => _fakeImprint;
  });

  testWidgets('rendert alle vier Sektionen aus Fake-Asset', (tester) async {
    ImprintScreen.loaderOverride = () async => _fakeImprint;

    await _pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Impressum'), findsWidgets);
    expect(find.text('1. Verantwortlich für den Inhalt'), findsOneWidget);
    expect(find.text('2. Kontakt'), findsOneWidget);
    expect(find.text('3. Rechtliche Hinweise'), findsOneWidget);
    expect(find.text('4. Vereinsangaben'), findsOneWidget);
    expect(find.textContaining('Owner-Eskalation'), findsWidgets);
  });

  testWidgets('zeigt Fallback-Text wenn Asset fehlt', (tester) async {
    ImprintScreen.loaderOverride =
        () async => throw Exception('asset missing');

    await _pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('nicht verfügbar'),
      findsOneWidget,
    );
  });
}
