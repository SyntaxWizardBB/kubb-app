import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/presentation/edit_profile_screen.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

import '../../../fixtures/auth/fake_cloud_profile_repository.dart';

class _SignedOutAuthController extends AuthController {
  @override
  Future<AuthSession> build() async => const AuthSession.signedOut();
}

class _KeypairAuthController extends AuthController {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.keypair(userId: 'u1', displayName: 'wiese-marc');
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FakeCloudProfileRepository repo,
    DisplayProfile? profile,
    AuthController Function()? authControllerFactory,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (_, _) => const EditProfileScreen(),
        ),
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          displayProfileProvider.overrideWithValue(profile),
          cloudProfileRepositoryProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith(
            authControllerFactory ?? _KeypairAuthController.new,
          ),
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
  }

  const seedProfile = DisplayProfile(
    userId: 'u1',
    displayName: 'wiese-marc',
    avatarColor: '#3a7c2e',
  );

  testWidgets('editing nickname mid-text keeps cursor stable', (tester) async {
    final repo = FakeCloudProfileRepository();
    await pump(tester, repo: repo, profile: seedProfile);

    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    // Place cursor in the middle of "wiese-marc" (between "wiese-" and
    // "marc"). updateEditingValue is the same path the platform IME
    // uses on a real device.
    final state = tester.state<EditableTextState>(find.byType(EditableText))
      ..updateEditingValue(
        const TextEditingValue(
          text: 'wiese-marc',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
    await tester.pump();

    // Insert "X" at the cursor position.
    state.updateEditingValue(
      const TextEditingValue(
        text: 'wiese-Xmarc',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    await tester.pump();

    final controller = state.widget.controller;
    expect(controller.text, 'wiese-Xmarc');
    expect(controller.selection.baseOffset, 7);
    expect(controller.selection.extentOffset, 7);
  });

  testWidgets('controller is disposed when widget unmounts', (tester) async {
    final repo = FakeCloudProfileRepository();
    await pump(tester, repo: repo, profile: seedProfile);

    // Replace the whole tree — the State#dispose path runs.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // No FlutterError should have been queued from a leaked listener.
    final errors = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousHandler);

    await tester.pump();
    expect(errors, isEmpty);
  });

  testWidgets('save button enables when nickname changes from initial',
      (tester) async {
    final repo = FakeCloudProfileRepository();
    await pump(tester, repo: repo, profile: seedProfile);

    final saveButton = find.byType(ElevatedButton);
    expect(saveButton, findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(saveButton).onPressed,
      isNull,
      reason: 'unchanged form must not allow save',
    );

    // Edit the nickname.
    tester.state<EditableTextState>(find.byType(EditableText))
        .updateEditingValue(
      const TextEditingValue(
        text: 'wiese-marc-2',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<ElevatedButton>(saveButton).onPressed,
      isNotNull,
      reason: 'dirty + valid form must allow save',
    );
  });

  testWidgets('a taken nickname blocks save and shows the name-taken banner '
      '(BUG-2)', (tester) async {
    final repo = FakeCloudProfileRepository()..takenNicknames.add('wiese-other');
    await pump(tester, repo: repo, profile: seedProfile);

    final saveButton = find.byType(ElevatedButton);

    // Change the nickname to one that is taken by another user.
    tester.state<EditableTextState>(find.byType(EditableText))
        .updateEditingValue(
      const TextEditingValue(
        text: 'wiese-other',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
    await tester.pump();
    // Let the 350 ms debounce fire and the availability future resolve.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(EditProfileScreen)),
    );
    expect(find.text(l10n.nicknameTakenError), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(saveButton).onPressed,
      isNull,
      reason: 'save must be blocked while the nickname is taken',
    );
  });

  testWidgets('save fails gracefully when session is signed out mid-flow',
      (tester) async {
    final repo = FakeCloudProfileRepository();
    await pump(
      tester,
      repo: repo,
      profile: seedProfile,
      authControllerFactory: _SignedOutAuthController.new,
    );

    // Make the form dirty + valid so save becomes tappable.
    tester.state<EditableTextState>(find.byType(EditableText))
        .updateEditingValue(
      const TextEditingValue(
        text: 'wiese-marc-2',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pump();

    final saveButton = find.byType(ElevatedButton);
    expect(
      tester.widget<ElevatedButton>(saveButton).onPressed,
      isNotNull,
    );

    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // RPC must not have been hit — the guard short-circuits before it.
    expect(repo.updateCount, 0);

    // Error banner is rendered with the static l10n message.
    final l10n = AppLocalizations.of(
      tester.element(find.byType(EditProfileScreen)),
    );
    expect(find.text(l10n.authEditProfileError), findsOneWidget);
  });
}
