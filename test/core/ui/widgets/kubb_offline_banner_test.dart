import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_service.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/core/ui/widgets/kubb_offline_banner.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Test seam for [outboxFlushStatusProvider] — a hand-rolled controller
/// is simpler than spinning up a full [OutboxFlusherImpl] just to assert
/// the banner's three states. We override the stream provider with the
/// emitted statuses from this controller.
class _StatusController {
  final StreamController<OutboxFlushStatus> _controller =
      StreamController<OutboxFlushStatus>.broadcast();

  Stream<OutboxFlushStatus> get stream => _controller.stream;

  void emit(OutboxFlushStatus status) => _controller.add(status);

  Future<void> dispose() => _controller.close();
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FakeConnectivityService connectivity,
    required _StatusController status,
    DateTime Function()? clock,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityServiceProvider.overrideWithValue(connectivity),
          outboxFlushStatusProvider.overrideWith((ref) => status.stream),
          if (clock != null)
            kubbOfflineBannerClockProvider.overrideWithValue(clock),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const Scaffold(
            body: Column(children: [KubbOfflineBanner()]),
          ),
        ),
      ),
    );
    // Allow the stream provider to deliver its seeded value and the
    // connectivity stream to settle.
    await tester.pumpAndSettle();
  }

  testWidgets(
    'online + idle outbox → banner is collapsed (no chip)',
    (tester) async {
      final connectivity = FakeConnectivityService();
      final status = _StatusController();
      addTearDown(status.dispose);
      addTearDown(connectivity.dispose);

      await pump(tester, connectivity: connectivity, status: status);
      status.emit(OutboxFlushStatus.idle);
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byType(KubbChip), findsNothing);
      // The SizedBox.shrink fallback collapses the strip to zero size.
      final size = tester.getSize(find.byType(KubbOfflineBanner));
      expect(size.height, 0);
    },
  );

  testWidgets(
    'offline → renders heli pill with offline label (no last sync yet)',
    (tester) async {
      final connectivity = FakeConnectivityService(initialOnline: false);
      final status = _StatusController();
      addTearDown(status.dispose);
      addTearDown(connectivity.dispose);

      await pump(tester, connectivity: connectivity, status: status);
      status.emit(OutboxFlushStatus.paused);
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Offline'), findsOneWidget);
      final chip = tester.widget<KubbChip>(find.byType(KubbChip));
      expect(chip.tone, KubbChipTone.heli);
    },
  );

  testWidgets(
    'offline after a successful sync → pill shows minutes since last sync',
    (tester) async {
      final connectivity = FakeConnectivityService();
      final status = _StatusController();
      addTearDown(status.dispose);
      addTearDown(connectivity.dispose);

      var clockTick = DateTime.utc(2026, 1, 1, 12);
      DateTime nowFn() => clockTick;

      await pump(
        tester,
        connectivity: connectivity,
        status: status,
        clock: nowFn,
      );
      // Drive `flushing → idle` so the last-sync timestamp is stamped.
      status.emit(OutboxFlushStatus.flushing);
      await tester.pump(const Duration(milliseconds: 10));
      status.emit(OutboxFlushStatus.idle);
      await tester.pump(const Duration(milliseconds: 10));

      // Advance the clock by 2 min and flip offline.
      clockTick = clockTick.add(const Duration(minutes: 2));
      connectivity.emit(online: false);
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Offline · letzte Sync vor 2 min'), findsOneWidget);
      final chip = tester.widget<KubbChip>(find.byType(KubbChip));
      expect(chip.tone, KubbChipTone.heli);
    },
  );

  testWidgets(
    'online + outbox flushing → renders info pill with sync-läuft label',
    (tester) async {
      final connectivity = FakeConnectivityService();
      final status = _StatusController();
      addTearDown(status.dispose);
      addTearDown(connectivity.dispose);

      await pump(tester, connectivity: connectivity, status: status);
      status.emit(OutboxFlushStatus.flushing);
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Sync läuft …'), findsOneWidget);
      final chip = tester.widget<KubbChip>(find.byType(KubbChip));
      expect(chip.tone, KubbChipTone.info);
    },
  );

  testWidgets(
    'connectivity toggle online → offline flips the banner from hidden to heli pill',
    (tester) async {
      final connectivity = FakeConnectivityService();
      final status = _StatusController();
      addTearDown(status.dispose);
      addTearDown(connectivity.dispose);

      await pump(tester, connectivity: connectivity, status: status);
      status.emit(OutboxFlushStatus.idle);
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byType(KubbChip), findsNothing);

      connectivity.emit(online: false);
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byType(KubbChip), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
    },
  );
}
