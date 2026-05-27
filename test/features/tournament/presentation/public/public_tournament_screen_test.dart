// Widget tests for TASK-M4.2-T13 (Public-Tournament-Screen).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/presentation/public/public_tournament_screen.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Counting [RealtimeChannel] used to assert subscribe/close lifecycle.
/// Tracks an in-memory reference count per channel key — the same
/// contract the Supabase adapter exposes (`referenceCount`) and the only
/// thing the Wave-6 toggle-test needs to verify ON → OFF.
class _CountingChannel implements RealtimeChannel {
  final Map<String, int> _refs = {};
  final Map<String, StreamController<RealtimeChange>> _ctrls = {};

  int referenceCount(String channelKey) => _refs[channelKey] ?? 0;

  @override
  Stream<RealtimeChange> subscribe({
    required String table,
    required String filterColumn,
    required String filterValue,
  }) {
    final key = '$table:$filterColumn=$filterValue';
    _refs[key] = (_refs[key] ?? 0) + 1;
    final ctrl = _ctrls.putIfAbsent(
      key,
      StreamController<RealtimeChange>.broadcast,
    );
    return ctrl.stream;
  }

  @override
  Future<void> close(String channelKey) async {
    final next = (_refs[channelKey] ?? 0) - 1;
    if (next <= 0) {
      _refs.remove(channelKey);
      await _ctrls.remove(channelKey)?.close();
    } else {
      _refs[channelKey] = next;
    }
  }

  @override
  Stream<RealtimeChannelState> stateStream(String channelKey) =>
      const Stream<RealtimeChannelState>.empty();
}

Future<void> _pump(
  WidgetTester tester, {
  required PublicTournamentView view,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publicTournamentViewProvider('t-1').overrideWith((_) => view),
      ],
      child: const MaterialApp(
        home: PublicTournamentScreen(tournamentId: 't-1'),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('public=true → drei Tabs sichtbar', (tester) async {
    await _pump(
      tester,
      view: const PublicTournamentView(isPublic: true, name: 'Sommer 2026'),
    );
    expect(find.byKey(const ValueKey('public-tab-schedule')), findsOneWidget);
    expect(find.byKey(const ValueKey('public-tab-standings')), findsOneWidget);
    expect(find.byKey(const ValueKey('public-tab-bracket')), findsOneWidget);
  });

  testWidgets('public=false → "nicht öffentlich"-Subview, keine Tabs',
      (tester) async {
    await _pump(
      tester,
      view: const PublicTournamentView(isPublic: false, name: ''),
    );
    expect(find.byKey(const ValueKey('public-not-public')), findsOneWidget);
    expect(find.byKey(const ValueKey('public-tab-schedule')), findsNothing);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('Live-Toggle ON→OFF → keine Realtime-Subscription mehr aktiv',
      (tester) async {
    final channel = _CountingChannel();
    const key = 'tournament_matches:tournament_id=t-1';
    await _pump(
      tester,
      view: PublicTournamentView(
        isPublic: true,
        name: 'Sommer 2026',
        channel: channel,
      ),
    );
    expect(channel.referenceCount(key), equals(0));
    await tester.tap(find.byKey(const ValueKey('public-live-toggle')));
    await tester.pump();
    expect(channel.referenceCount(key), equals(1));
    await tester.tap(find.byKey(const ValueKey('public-live-toggle')));
    await tester.pump();
    expect(channel.referenceCount(key), equals(0));
  });

  testWidgets('Read-only: keine Eingabe-Widgets im Render-Tree',
      (tester) async {
    await _pump(
      tester,
      view: const PublicTournamentView(isPublic: true, name: 'Sommer 2026'),
    );
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    expect(
      find.widgetWithText(FilledButton, 'Speichern').evaluate().isEmpty,
      isTrue,
    );
  });
}
