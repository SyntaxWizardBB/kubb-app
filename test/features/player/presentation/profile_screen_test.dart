import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/player/data/player_repository.dart';
import 'package:kubb_app/features/player/presentation/profile_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de');
  });

  Future<void> pump(
    WidgetTester tester, {
    required AsyncValue<Player?> profile,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) async* {
            if (profile is AsyncData<Player?>) {
              yield profile.value;
            }
          }),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders player name when profile is loaded', (tester) async {
    final player = Player(
      id: 'p1',
      name: 'Lukas',
      deviceId: 'd1',
      createdAt: DateTime.utc(2026, 5, 2),
    );
    await pump(tester, profile: AsyncData(player));
    await tester.pumpAndSettle();

    expect(find.text('Lukas'), findsOneWidget);
    expect(find.text('Geräte-ID'), findsOneWidget);
    expect(find.text('Mitglied seit'), findsOneWidget);
    expect(find.text('d1'), findsOneWidget);
  });

  testWidgets('shows loading indicator while profile is loading',
      (tester) async {
    await pump(tester, profile: const AsyncLoading<Player?>());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows fallback when profile is null', (tester) async {
    await pump(tester, profile: const AsyncData<Player?>(null));
    await tester.pumpAndSettle();

    expect(find.text('Kein Profil'), findsOneWidget);
  });

  testWidgets('renders avatar with first initial', (tester) async {
    final player = Player(
      id: 'p1',
      name: 'Lukas Brosi',
      deviceId: 'd1',
      createdAt: DateTime.utc(2026, 5, 2),
    );
    await pump(tester, profile: AsyncData(player));
    await tester.pumpAndSettle();

    expect(find.byType(AvatarCircle), findsOneWidget);
    expect(find.text('LB'), findsOneWidget);
  });

  testWidgets('edit button toggles edit mode and Save is enabled with text',
      (tester) async {
    final player = Player(
      id: 'p1',
      name: 'Lukas',
      deviceId: 'd1',
      createdAt: DateTime.utc(2026, 5, 2),
    );
    await pump(tester, profile: AsyncData(player));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bearbeiten'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Speichern'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Speichern'),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets('save persists name change via repo and exits edit mode',
      (tester) async {
    final player = Player(
      id: 'p1',
      name: 'Lukas',
      deviceId: 'd1',
      createdAt: DateTime.utc(2026, 5, 2),
    );
    final fake = _FakePlayerRepository(player);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerRepositoryProvider.overrideWithValue(fake),
          currentProfileProvider.overrideWith((ref) => fake.watchCurrent()),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bearbeiten'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bea');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    expect(fake.updates, hasLength(1));
    expect(fake.updates.single.name, 'Bea');
    expect(find.widgetWithText(OutlinedButton, 'Bearbeiten'), findsOneWidget);
  });
}

class _UpdateCall {
  _UpdateCall(this.id, this.name, this.avatarColor);
  final String id;
  final String name;
  final String? avatarColor;
}

class _FakePlayerRepository implements PlayerRepository {
  _FakePlayerRepository(Player initial) : _current = initial {
    _controller.add(initial);
  }

  Player _current;
  final updates = <_UpdateCall>[];
  final _controller = StreamController<Player?>.broadcast();

  @override
  Future<Player?> currentOrNull() async => _current;

  @override
  Future<Player> create({required String name}) async => _current;

  @override
  Stream<Player?> watchCurrent() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<Player> update({
    required String id,
    required String name,
    String? avatarColor,
  }) async {
    updates.add(_UpdateCall(id, name, avatarColor));
    _current = Player(
      id: _current.id,
      name: name,
      deviceId: _current.deviceId,
      avatarColor: avatarColor,
      createdAt: _current.createdAt,
    );
    _controller.add(_current);
    return _current;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
