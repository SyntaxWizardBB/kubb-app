import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/passphrase_change_controller.dart';
import 'package:kubb_app/features/auth/presentation/passphrase_change_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubPassphraseChangeController extends PassphraseChangeController {
  @override
  PassphraseChangeState build() => const PassphraseChangeState.idle();

  @override
  Future<void> change({
    required String nickname,
    required String oldPassphrase,
    required String newPassphrase,
  }) async {}
}

class _StubAuthController extends AuthController {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.keypair(userId: 'u1', displayName: 'wiese-marc');
}

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          passphraseChangeControllerProvider.overrideWith(
            _StubPassphraseChangeController.new,
          ),
          authControllerProvider.overrideWith(_StubAuthController.new),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const PassphraseChangeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The three PassphraseInput instances render in order: old, new, confirm.
  Finder oldField() => find.byType(TextField).at(0);
  Finder newField() => find.byType(TextField).at(1);
  Finder confirmField() => find.byType(TextField).at(2);

  // The submit button is the first ElevatedButton on the screen.
  ElevatedButton submitButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);

  testWidgets('submit disabled when old empty', (tester) async {
    await pump(tester);

    expect(submitButton(tester).onPressed, isNull);

    // Fill new (>= 12 chars) and matching confirm, leave old empty.
    await tester.enterText(newField(), 'abcdefghijkl');
    await tester.pumpAndSettle();
    await tester.enterText(confirmField(), 'abcdefghijkl');
    await tester.pumpAndSettle();

    expect(
      submitButton(tester).onPressed,
      isNull,
      reason: 'old empty must keep submit disabled',
    );
  });

  testWidgets('submit disabled when new < 12 chars', (tester) async {
    await pump(tester);

    await tester.enterText(oldField(), 'altpass');
    await tester.pumpAndSettle();
    await tester.enterText(newField(), 'abcdefghijk'); // 11 chars
    await tester.pumpAndSettle();
    await tester.enterText(confirmField(), 'abcdefghijk');
    await tester.pumpAndSettle();

    expect(
      submitButton(tester).onPressed,
      isNull,
      reason: 'new < 12 chars must keep submit disabled',
    );
  });

  testWidgets('submit disabled when confirm does not match new', (tester) async {
    await pump(tester);

    await tester.enterText(oldField(), 'altpass');
    await tester.pumpAndSettle();
    await tester.enterText(newField(), 'abcdefghijkl');
    await tester.pumpAndSettle();
    await tester.enterText(confirmField(), 'xyzdefghijkl');
    await tester.pumpAndSettle();

    expect(
      submitButton(tester).onPressed,
      isNull,
      reason: 'mismatch between new and confirm must keep submit disabled',
    );
  });

  testWidgets('submit enabled when all three conditions met', (tester) async {
    await pump(tester);

    await tester.enterText(oldField(), 'a');
    await tester.pumpAndSettle();
    await tester.enterText(newField(), 'abcdefghijkl');
    await tester.pumpAndSettle();
    await tester.enterText(confirmField(), 'abcdefghijkl');
    await tester.pumpAndSettle();

    expect(
      submitButton(tester).onPressed,
      isNotNull,
      reason: 'old non-empty + new >= 12 + confirm matches must enable submit',
    );
  });

  testWidgets('confirm shows mismatch error after divergent input',
      (tester) async {
    await pump(tester);

    await tester.enterText(newField(), 'abcdefghijkl');
    await tester.pumpAndSettle();
    await tester.enterText(confirmField(), 'xyzdefghijkl');
    await tester.pumpAndSettle();

    expect(find.text('Stimmt nicht überein.'), findsOneWidget);
  });
}
