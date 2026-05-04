import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/restore_controller.dart';
import 'package:kubb_app/features/auth/presentation/restore_flow.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class _StubRestoreController extends RestoreController {
  _StubRestoreController(this._initial);
  final RestoreState _initial;

  @override
  RestoreState build() => _initial;

  // `state` is provided by the Notifier base class — a setter would
  // shadow it, so we expose the mutation as an explicit method.
  // ignore: use_setters_to_change_properties
  void emit(RestoreState next) => state = next;
}

void main() {
  Future<_StubRestoreController> pump(
    WidgetTester tester, {
    required RestoreState initial,
    String initialLocation = '/sign-in/restore',
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stub = _StubRestoreController(initial);
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/sign-in/restore',
          builder: (_, _) => const RestoreFlow(),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Placeholder()),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restoreControllerProvider.overrideWith(() => stub),
        ],
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    return stub;
  }

  Future<void> advanceToStep2(WidgetTester tester) async {
    // Step 1: type a valid nickname and press Continue.
    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'abc');
    await tester.pump();

    final continueButton = find.byType(ElevatedButton);
    expect(continueButton, findsOneWidget);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
  }

  testWidgets('cooldown badge is disposed when widget unmounts',
      (tester) async {
    final until = DateTime.now().toUtc().add(const Duration(seconds: 30));
    await pump(tester, initial: RestoreState.cooldown(until: until));
    await advanceToStep2(tester);

    // Badge title is unique to the cooldown state.
    expect(find.text('Zu viele Versuche'), findsOneWidget);

    // Replace the whole tree — the badge State#dispose path runs and
    // must cancel its periodic Timer. If it does not, the next pumps
    // would surface a "Timer is still active" assertion.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Zu viele Versuche'), findsNothing);
  });

  testWidgets('cooldown badge counts down each second', (tester) async {
    // The badge reads `widget.until.difference(DateTime.now())` on
    // every periodic tick. The Timer fires under fakeAsync, but
    // DateTime.now() stays on the real wall clock — so we anchor
    // `until` to a fixed offset and rely on the real clock advancing
    // a few seconds between pumps via `runAsync`.
    final start = DateTime.now().toUtc();
    final until = start.add(const Duration(seconds: 30));
    await pump(tester, initial: RestoreState.cooldown(until: until));
    await advanceToStep2(tester);

    // First tick happens in initState — should read close to 30.
    expect(
      find.textContaining(RegExp('Bitte warte (28|29|30) Sekunden')),
      findsOneWidget,
    );

    // Real time must elapse for the wall clock to advance. We sleep
    // for ~1.5s of real time, then trigger one more periodic tick.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump(const Duration(seconds: 1));

    final element = tester.element(find.byType(RestoreFlow));
    final l10n = AppLocalizations.of(element);
    final visible = find
        .descendant(
          of: find.byType(RestoreFlow),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .toList();
    final cooldownLine = visible.firstWhere(
      (s) => s.startsWith('Bitte warte'),
      orElse: () => '',
    );
    expect(cooldownLine, isNotEmpty);

    // Extract the seconds count and assert it is strictly less than 30
    // — i.e. the timer fired and the value ticked down at least once.
    final match = RegExp(r'(\d+)').firstMatch(cooldownLine);
    expect(match, isNotNull);
    final seconds = int.parse(match!.group(1)!);
    expect(seconds, lessThan(30));
    expect(
      seconds,
      greaterThanOrEqualTo(20),
      reason: 'sanity: should have ticked only a couple of seconds',
    );

    // Compare against the localized template just so a future ARB
    // rename surfaces here, not silently in production.
    expect(l10n.authRestoreCooldownMessage(seconds), cooldownLine);

    // Drain the remaining ticks so the test ends with no live timer.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });

  testWidgets('navigates back to / when restore done', (tester) async {
    final stub =
        await pump(tester, initial: const RestoreState.idle());
    await advanceToStep2(tester);

    // Sanity check: passphrase input is on screen, Placeholder is not.
    expect(find.byType(Placeholder), findsNothing);

    stub.emit(const RestoreState.done(userId: 'u1'));
    await tester.pumpAndSettle();

    // The ref.listen on the passphrase step calls go('/'), which
    // mounts the Placeholder route.
    expect(find.byType(Placeholder), findsOneWidget);
  });

  testWidgets('continue button enables only for valid nickname',
      (tester) async {
    await pump(tester, initial: const RestoreState.idle());

    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    ElevatedButton button() =>
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));

    expect(button().onPressed, isNull, reason: 'empty input must be blocked');

    await tester.enterText(field, 'ab');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'two chars are too short');

    await tester.enterText(field, 'abc');
    await tester.pump();
    expect(button().onPressed, isNotNull, reason: 'three valid chars enable');

    await tester.enterText(field, 'ab cd');
    await tester.pump();
    expect(
      button().onPressed,
      isNull,
      reason: 'whitespace is rejected by the alphanumeric pattern',
    );
  });
}
