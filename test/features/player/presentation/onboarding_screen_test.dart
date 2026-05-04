import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/data/player_repository.dart';
import 'package:kubb_app/features/player/presentation/onboarding_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late PlayerRepository repo;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    repo = PlayerRepository(db.playerDao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder confirmButton() => find.widgetWithText(FilledButton, 'Weiter');

  bool isEnabled(WidgetTester tester) {
    final button = tester.widget<FilledButton>(confirmButton());
    return button.onPressed != null;
  }

  testWidgets('confirm button disabled when field is empty', (tester) async {
    await pump(tester);

    expect(confirmButton(), findsOneWidget);
    expect(isEnabled(tester), isFalse);
  });

  testWidgets('confirm button enabled when name is valid', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'Lukas');
    await tester.pump();

    expect(isEnabled(tester), isTrue);
  });

  testWidgets('avatar preview updates as the user types', (tester) async {
    await pump(tester);

    expect(find.byType(AvatarCircle), findsOneWidget);
    expect(find.text('?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Lukas');
    await tester.pump();

    expect(find.text('L'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Marc Brosius');
    await tester.pump();

    expect(find.text('MB'), findsOneWidget);
  });

  testWidgets('pressing the keyboard go-action submits the form',
      (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'Lukas');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    final created = await repo.currentOrNull();
    expect(created?.name, 'Lukas');
  });

  testWidgets('text field uses the go input-action so the keyboard submits',
      (tester) async {
    await pump(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textInputAction, TextInputAction.go);
  });

  testWidgets('confirm button disabled with whitespace-only name',
      (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();

    expect(isEnabled(tester), isFalse);
  });

  testWidgets('A4: shows snackbar and re-enables button when create() throws',
      (tester) async {
    final failing = _ThrowingPlayerRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerRepositoryProvider.overrideWithValue(failing)],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Lukas');
    await tester.pump();
    expect(isEnabled(tester), isTrue);

    await tester.tap(confirmButton());
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Profil konnte nicht erstellt werden — bitte erneut versuchen.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(isEnabled(tester), isTrue);
  });
}

class _ThrowingPlayerRepository implements PlayerRepository {
  _ThrowingPlayerRepository();

  @override
  Future<Player> create({required String name}) async {
    throw StateError('forced create() failure');
  }

  @override
  Future<Player?> currentOrNull() async => null;

  @override
  Stream<Player?> watchCurrent() => const Stream<Player?>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
