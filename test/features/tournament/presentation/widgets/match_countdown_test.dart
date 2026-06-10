// Widget tests for the live match countdown (STAGE B, spec "TournierStart").

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/match_countdown.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Counts how often the expiry haptic fired.
class _SpyHaptics implements CountdownHaptics {
  int calls = 0;
  @override
  void onExpire() => calls++;
}

/// A controllable clock the widget reads via its `now` callback.
class _Clock {
  _Clock(this.value);
  DateTime value;
  DateTime now() => value;
}

Future<void> _pump(
  WidgetTester tester, {
  required DateTime startedAt,
  required int durationSeconds,
  required _Clock clock,
  required ManualCountdownTicker ticker,
  required CountdownHaptics haptics,
  int? tiebreakAfterSeconds,
  Duration serverOffset = Duration.zero,
  DateTime? pausedAt,
  int pausedAccumSeconds = 0,
  bool onHold = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: KubbTheme.light(),
      home: Scaffold(
        body: MatchCountdown(
          startedAt: startedAt,
          durationSeconds: durationSeconds,
          tiebreakAfterSeconds: tiebreakAfterSeconds,
          serverOffset: serverOffset,
          pausedAt: pausedAt,
          pausedAccumSeconds: pausedAccumSeconds,
          onHold: onHold,
          ticker: ticker,
          haptics: haptics,
          now: clock.now,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final start = DateTime.utc(2026, 6, 1, 12);

  testWidgets('renders remaining mm:ss and counts down on each tick',
      (tester) async {
    final clock = _Clock(start);
    final ticker = ManualCountdownTicker();
    final haptics = _SpyHaptics();
    await _pump(
      tester,
      startedAt: start,
      durationSeconds: 90, // 01:30
      clock: clock,
      ticker: ticker,
      haptics: haptics,
    );

    expect(find.text('01:30'), findsOneWidget);

    // Advance the controllable clock and fire a tick.
    clock.value = start.add(const Duration(seconds: 31));
    ticker.fire();
    await tester.pump();
    expect(find.text('00:59'), findsOneWidget);
    expect(haptics.calls, 0);
  });

  testWidgets('fires haptic once and flips to result-entry CTA at expiry',
      (tester) async {
    final clock = _Clock(start);
    final ticker = ManualCountdownTicker();
    final haptics = _SpyHaptics();
    await _pump(
      tester,
      startedAt: start,
      durationSeconds: 60,
      clock: clock,
      ticker: ticker,
      haptics: haptics,
    );

    expect(find.byKey(const ValueKey('match-countdown-remaining')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('match-countdown-expired')), findsNothing);
    expect(haptics.calls, 0);

    // Cross the expiry boundary.
    clock.value = start.add(const Duration(seconds: 60));
    ticker.fire();
    await tester.pump();

    expect(find.byKey(const ValueKey('match-countdown-expired')),
        findsOneWidget);
    expect(find.text('Zeit abgelaufen — Resultat eintragen'), findsOneWidget);
    expect(haptics.calls, 1);

    // Further ticks past expiry must NOT re-fire the haptic.
    clock.value = start.add(const Duration(seconds: 75));
    ticker.fire();
    await tester.pump();
    expect(haptics.calls, 1);
  });

  testWidgets('KO match with tiebreak shows the Mighty-Finisher CTA at expiry',
      (tester) async {
    final clock = _Clock(start);
    final ticker = ManualCountdownTicker();
    final haptics = _SpyHaptics();
    await _pump(
      tester,
      startedAt: start,
      durationSeconds: 60,
      tiebreakAfterSeconds: 40,
      clock: clock,
      ticker: ticker,
      haptics: haptics,
    );

    clock.value = start.add(const Duration(seconds: 61));
    ticker.fire();
    await tester.pump();

    expect(
      find.text('Zeit abgelaufen — Tiebreak / Mighty-Finisher melden'),
      findsOneWidget,
    );
    expect(haptics.calls, 1);
  });

  testWidgets('fires haptic immediately when mounted already expired',
      (tester) async {
    final clock = _Clock(start.add(const Duration(seconds: 120)));
    final ticker = ManualCountdownTicker();
    final haptics = _SpyHaptics();
    await _pump(
      tester,
      startedAt: start,
      durationSeconds: 60,
      clock: clock,
      ticker: ticker,
      haptics: haptics,
    );

    expect(find.byKey(const ValueKey('match-countdown-expired')),
        findsOneWidget);
    expect(haptics.calls, 1);
  });

  // A3c (ADR-0031 §Uhr): the server skew offset is added to the local clock,
  // so the remaining time is computed against `now + serverOffset`.
  testWidgets('serverOffset shifts the remaining time', (tester) async {
    // Local clock is at the start, but the server is 20s ahead — the match
    // has effectively been running 20s, so 01:30 - 20s = 01:10 remaining.
    final clock = _Clock(start);
    final ticker = ManualCountdownTicker();
    final haptics = _SpyHaptics();
    await _pump(
      tester,
      startedAt: start,
      durationSeconds: 90, // 01:30
      serverOffset: const Duration(seconds: 20),
      clock: clock,
      ticker: ticker,
      haptics: haptics,
    );

    expect(find.text('01:10'), findsOneWidget);
    // Without the offset the same inputs would read 01:30.
    expect(find.text('01:30'), findsNothing);
  });

  // A3c: a set pausedAt freezes `remaining` — advancing the clock past it
  // does not reduce the displayed time.
  testWidgets('pausedAt freezes the remaining time', (tester) async {
    final clock = _Clock(start.add(const Duration(seconds: 30)));
    final ticker = ManualCountdownTicker();
    final haptics = _SpyHaptics();
    // Paused 30s in: elapsed is pinned at 30s -> 90 - 30 = 60s remaining.
    await _pump(
      tester,
      startedAt: start,
      durationSeconds: 90,
      pausedAt: start.add(const Duration(seconds: 30)),
      clock: clock,
      ticker: ticker,
      haptics: haptics,
    );

    expect(find.text('01:00'), findsOneWidget);

    // Advance the clock 40s further; while paused the remaining time stays
    // frozen at 01:00 (the live pause slice cancels the clock advance).
    clock.value = start.add(const Duration(seconds: 70));
    ticker.fire();
    await tester.pump();
    expect(find.text('01:00'), findsOneWidget);
    // Not expired and no haptic while frozen.
    expect(find.byKey(const ValueKey('match-countdown-expired')), findsNothing);
    expect(haptics.calls, 0);
  });
}
