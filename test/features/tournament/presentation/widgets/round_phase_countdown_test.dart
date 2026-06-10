// Widget tests for the round-phase countdown (Phase-A Block A4, ADR-0031).
//
// Covers the four states (call/pause countdown, running match clock, the
// completed (non-held) match clock, and awaiting-results hold), the hold
// freeze, the published->call->running transition, and the schedule == null
// fallback to the plain started_at clock.
// Time is injected deterministically via a controllable clock + a
// ManualCountdownTicker — no real timers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/match_countdown.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/round_phase_countdown.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Counts how often the expiry haptic fired (silences the platform channel).
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

final _start = DateTime.utc(2026, 6, 1, 12);
const _tid = TournamentId('11111111-1111-1111-1111-111111111111');

/// Builds a schedule row for [status] with the given timing anchors. Defaults
/// place [startsAt] at [_start] and a 90s match window.
TournamentRoundScheduleRef _schedule({
  required RoundStatus status,
  DateTime? startsAt,
  int matchSeconds = 90,
  int breakSeconds = 120,
  int? tiebreakAfterSeconds,
  DateTime? pausedAt,
  int pausedAccumSeconds = 0,
}) {
  final starts = startsAt ?? _start;
  return TournamentRoundScheduleRef(
    tournamentId: _tid,
    stageNodeId: null,
    roundNumber: 1,
    phase: 'group',
    status: status,
    publishedAt: starts.subtract(Duration(seconds: breakSeconds)),
    startsAt: starts,
    endsAt: starts.add(Duration(seconds: matchSeconds)),
    breakSeconds: breakSeconds,
    matchSeconds: matchSeconds,
    tiebreakAfterSeconds: tiebreakAfterSeconds,
    pausedAt: pausedAt,
    pausedAccumSeconds: pausedAccumSeconds,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required TournamentRoundScheduleRef? schedule,
  required DateTime startedAt,
  required int durationSeconds,
  required _Clock clock,
  required ManualCountdownTicker ticker,
  required CountdownHaptics haptics,
  int? tiebreakAfterSeconds,
  Duration serverOffset = Duration.zero,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: KubbTheme.light(),
      home: Scaffold(
        body: RoundPhaseCountdown(
          schedule: schedule,
          startedAt: startedAt,
          durationSeconds: durationSeconds,
          tiebreakAfterSeconds: tiebreakAfterSeconds,
          serverOffset: serverOffset,
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
  group('call / pause countdown (published / call)', () {
    testWidgets('published shows "Nächste Runde in mm:ss" until starts_at',
        (tester) async {
      // Round starts 120s from now; clock sits at start - 120s.
      final clock = _Clock(_start.subtract(const Duration(seconds: 120)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule: _schedule(status: RoundStatus.published, startsAt: _start),
        startedAt: _start,
        durationSeconds: 90,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      expect(find.byKey(const ValueKey('round-call-countdown')), findsOneWidget);
      expect(find.text('Nächste Runde in 02:00'), findsOneWidget);
      // No match clock yet.
      expect(find.byType(MatchCountdown), findsNothing);

      // Tick down 80s.
      clock.value = _start.subtract(const Duration(seconds: 40));
      ticker.fire();
      await tester.pump();
      expect(find.text('Nächste Runde in 00:40'), findsOneWidget);
    });

    testWidgets('call counts down toward starts_at', (tester) async {
      final clock = _Clock(_start.subtract(const Duration(seconds: 90)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule: _schedule(status: RoundStatus.call, startsAt: _start),
        startedAt: _start,
        durationSeconds: 90,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      expect(find.text('Nächste Runde in 01:30'), findsOneWidget);
    });

    testWidgets(
        'transition: once starts_at is reached the running match clock appears',
        (tester) async {
      final clock = _Clock(_start.subtract(const Duration(seconds: 30)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule: _schedule(status: RoundStatus.call, startsAt: _start),
        startedAt: _start,
        durationSeconds: 90,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      expect(find.byKey(const ValueKey('round-call-countdown')), findsOneWidget);

      // starts_at reached -> running clock takes over (full 90s remaining).
      clock.value = _start;
      ticker.fire();
      await tester.pump();
      expect(find.byKey(const ValueKey('round-call-countdown')), findsNothing);
      expect(find.byType(MatchCountdown), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
    });
  });

  group('running', () {
    testWidgets('running delegates to the live match clock', (tester) async {
      final clock = _Clock(_start.add(const Duration(seconds: 30)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule: _schedule(status: RoundStatus.running, startsAt: _start),
        startedAt: _start,
        durationSeconds: 90,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      expect(find.byType(MatchCountdown), findsOneWidget);
      // 90 - 30 = 60s remaining.
      expect(find.text('01:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('round-call-countdown')), findsNothing);
      expect(find.byKey(const ValueKey('round-hold')), findsNothing);

      // The running clock ticks down.
      clock.value = _start.add(const Duration(seconds: 60));
      ticker.fire();
      await tester.pump();
      expect(find.text('00:30'), findsOneWidget);
    });
  });

  group('completed', () {
    testWidgets(
        'completed renders the (non-held) match clock — no call/hold view',
        (tester) async {
      // The fifth RoundStatus wire value. Its switch arm in the widget renders
      // the plain match clock (the detail screen drops the clock once the match
      // itself is terminal), so it must look exactly like the running arm: a
      // MatchCountdown, never the call countdown or the hold banner.
      final clock = _Clock(_start.add(const Duration(seconds: 30)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule: _schedule(status: RoundStatus.completed, startsAt: _start),
        startedAt: _start,
        durationSeconds: 90,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      expect(find.byType(MatchCountdown), findsOneWidget);
      expect(find.byKey(const ValueKey('round-call-countdown')), findsNothing);
      expect(find.byKey(const ValueKey('round-hold')), findsNothing);
      // 90 - 30 = 60s remaining, counting like a normal (non-held) clock.
      expect(find.text('01:00'), findsOneWidget);
    });
  });

  group('awaiting results / tiebreak hold', () {
    testWidgets('awaitingResults shows a frozen clock + hold text',
        (tester) async {
      // Clock is past the match end (90s); held.
      final clock = _Clock(_start.add(const Duration(seconds: 95)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule:
            _schedule(status: RoundStatus.awaitingResults, startsAt: _start),
        startedAt: _start,
        durationSeconds: 90,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      expect(find.byKey(const ValueKey('round-hold')), findsOneWidget);
      expect(find.text('Zeit angehalten — Resultat eintragen'), findsOneWidget);
    });

    testWidgets('tiebreak hold shows the tiebreak text once crossed',
        (tester) async {
      // Clock is past the tiebreak point (60s in, held at 95s).
      final clock = _Clock(_start.add(const Duration(seconds: 95)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule: _schedule(
          status: RoundStatus.awaitingResults,
          startsAt: _start,
          tiebreakAfterSeconds: 60,
        ),
        startedAt: _start,
        durationSeconds: 90,
        tiebreakAfterSeconds: 60,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      expect(find.byKey(const ValueKey('round-hold')), findsOneWidget);
      expect(find.text('Tiebreak'), findsOneWidget);
    });

    testWidgets(
        'hold with a tiebreak config but before the tiebreak point shows the '
        'plain hold text, not "Tiebreak"', (tester) async {
      // The match is held (awaiting_results) early — before the tiebreak point
      // (60s). A configured tiebreak window alone must NOT read as a tiebreak;
      // it is a plain "result not entered yet" hold. (Reviewer finding 1.)
      final clock = _Clock(_start.add(const Duration(seconds: 30)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule: _schedule(
          status: RoundStatus.awaitingResults,
          startsAt: _start,
          tiebreakAfterSeconds: 60,
        ),
        startedAt: _start,
        durationSeconds: 90,
        tiebreakAfterSeconds: 60,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      expect(find.byKey(const ValueKey('round-hold')), findsOneWidget);
      expect(find.text('Zeit angehalten — Resultat eintragen'), findsOneWidget);
      expect(find.text('Tiebreak'), findsNothing);
    });

    testWidgets('hold clamps the clock at the match end across ticks',
        (tester) async {
      // DoD A4-8(d): "hold freezes the remaining time (repeated ticks don't
      // change mm:ss)". The intended freeze semantics are MatchTimer.onHold's
      // *end-clamp* (ADR-0031 §6 / match_timer.dart): a hold only begins once a
      // round reaches awaiting_results, i.e. AT/AFTER endsAt. So onHold freezes
      // the clock AT the match end — past the end the displayed time stays
      // pinned at 00:00 no matter how far the clock advances (it does NOT pin a
      // mid-run mm:ss; that case is MatchTimer.pausedAt, exercised in the domain
      // tests). This test asserts that end-clamp freeze across multiple ticks.
      final clock = _Clock(_start.add(const Duration(seconds: 90)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule:
            _schedule(status: RoundStatus.awaitingResults, startsAt: _start),
        startedAt: _start,
        durationSeconds: 90,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      // At the end: clock reads expired (00:00).
      expect(find.byKey(const ValueKey('match-countdown-expired')),
          findsOneWidget);

      // Advance far past the end repeatedly: remaining stays pinned at expired
      // (00:00) and the expiry haptic does not re-fire — the clamp holds.
      clock.value = _start.add(const Duration(seconds: 120));
      ticker.fire();
      await tester.pump();
      expect(find.byKey(const ValueKey('match-countdown-expired')),
          findsOneWidget);

      clock.value = _start.add(const Duration(seconds: 300));
      ticker.fire();
      await tester.pump();
      expect(find.byKey(const ValueKey('match-countdown-expired')),
          findsOneWidget);
      // No further haptic re-fire across the held ticks, no crash.
      expect(haptics.calls, 1);
    });
  });

  group('schedule == null fallback', () {
    testWidgets('falls back to the plain started_at clock (no pause/hold)',
        (tester) async {
      final clock = _Clock(_start.add(const Duration(seconds: 30)));
      final ticker = ManualCountdownTicker();
      final haptics = _SpyHaptics();
      await _pump(
        tester,
        schedule: null,
        startedAt: _start,
        durationSeconds: 90,
        clock: clock,
        ticker: ticker,
        haptics: haptics,
      );

      // Plain match clock: no call countdown, no hold banner.
      expect(find.byType(MatchCountdown), findsOneWidget);
      expect(find.byKey(const ValueKey('round-call-countdown')), findsNothing);
      expect(find.byKey(const ValueKey('round-hold')), findsNothing);
      // 90 - 30 = 60s remaining, counting normally.
      expect(find.text('01:00'), findsOneWidget);

      clock.value = _start.add(const Duration(seconds: 60));
      ticker.fire();
      await tester.pump();
      expect(find.text('00:30'), findsOneWidget);
    });
  });
}
