import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/account_deletion_controller.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/presentation/delete_account_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubDeletionController extends AccountDeletionController {
  @override
  AccountDeletionState build() => const AccountDeletionState.idle();

  @override
  Future<void> delete({String? nickname}) async {}
}

class _StubAuthController extends AuthController {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.keypair(userId: 'u1', displayName: 'Lukas');
}

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionControllerProvider.overrideWith(
            _StubDeletionController.new,
          ),
          authControllerProvider.overrideWith(_StubAuthController.new),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const DeleteAccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The ack checkbox renders Icon(Icons.check) only when checked.
  bool isAckChecked() => find.byIcon(Icons.check).evaluate().isNotEmpty;

  testWidgets(
    'ack checkbox resets when navigating warning -> confirm -> warning -> '
    'confirm',
    (tester) async {
      await pump(tester);

      // Page 1 -> Page 2
      await tester.tap(find.text('Weiter zur Bestätigung'));
      await tester.pumpAndSettle();
      expect(find.text('Endgültig bestätigen'), findsOneWidget);
      expect(isAckChecked(), isFalse);

      // Tick the acknowledge checkbox
      await tester.tap(find.text(
        'Ich verstehe, dass alle Daten dauerhaft gelöscht werden.',
      ));
      await tester.pumpAndSettle();
      expect(isAckChecked(), isTrue);

      // Page 2 -> Page 1 via the AppBar arrow_back
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Konto löschen?'), findsOneWidget);

      // Page 1 -> Page 2 again
      await tester.tap(find.text('Weiter zur Bestätigung'));
      await tester.pumpAndSettle();
      expect(find.text('Endgültig bestätigen'), findsOneWidget);

      // Checkbox must have been reset
      expect(isAckChecked(), isFalse);
    },
  );
}
