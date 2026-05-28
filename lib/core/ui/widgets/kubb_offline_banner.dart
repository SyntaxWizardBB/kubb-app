import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_chip.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Reactive online/offline state for the app shell. Seeds the stream with
/// the current snapshot so the banner renders correctly on the first
/// frame and re-emits on every connectivity transition.
final kubbOfflineBannerOnlineProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield service.isOnline;
  yield* service.onlineStream;
});

/// Wall-clock seam exposed to the banner. Overridden in tests so the
/// "letzte Sync vor n min" string can be asserted deterministically
/// without relying on a real clock.
final kubbOfflineBannerClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Tracks the wall-clock time of the most recent successful outbox
/// flush (i.e. the flusher transitioned `flushing → idle` without an
/// error). Surfaces as the "letzte Sync vor n min" suffix on the
/// offline pill per AUDIT §4.4.
///
/// Hydrated by [LastSyncedAtNotifier] which subscribes to
/// [outboxFlushStatusProvider]. The notifier is constructed eagerly so
/// the timestamp is captured even when no consumer is mounted (e.g.
/// the banner is collapsed while online).
final lastSyncedAtProvider =
    NotifierProvider<LastSyncedAtNotifier, DateTime?>(
      LastSyncedAtNotifier.new,
    );

/// Notifier behind [lastSyncedAtProvider]. Exposed (instead of
/// file-private) so the riverpod codegen sees a concrete class for the
/// generic. Subscribes to [outboxFlushStatusProvider] inside [build] so
/// the listener is bound to the notifier lifecycle.
class LastSyncedAtNotifier extends Notifier<DateTime?> {
  OutboxFlushStatus? _previous;

  @override
  DateTime? build() {
    ref.listen<AsyncValue<OutboxFlushStatus>>(
      outboxFlushStatusProvider,
      (previous, next) {
        final nextStatus = next.maybeWhen(
          data: (s) => s,
          orElse: () => null,
        );
        _onStatus(_previous, nextStatus);
        if (nextStatus != null) {
          _previous = nextStatus;
        }
      },
      fireImmediately: true,
    );
    return null;
  }

  /// Records a sync timestamp on a `flushing → idle` transition. Any
  /// other transition leaves the timestamp untouched so an offline
  /// blip mid-flush does not overwrite the last known sync.
  void _onStatus(OutboxFlushStatus? previous, OutboxFlushStatus? next) {
    if (previous == OutboxFlushStatus.flushing &&
        next == OutboxFlushStatus.idle) {
      final clock = ref.read(kubbOfflineBannerClockProvider);
      state = clock();
    }
  }
}

/// AUDIT §4.4 — sticky status pill mounted at the top of the app shell.
///
/// Consolidates the two predecessor widgets (`OfflineBanner`,
/// `OutboxStatusBanner`) so the user only ever sees a single strip.
/// State priority (highest first):
///   1. **Syncing** — outbox flusher is draining queued rows. Renders
///      a blue `info` pill with `offlineBannerSyncing`.
///   2. **Offline** — device reports no connectivity. Renders a yellow
///      `heli` pill, optionally suffixed with the elapsed minutes
///      since the last successful sync (`offlineBannerSyncedAgo`).
///   3. **Online + idle** — pill is collapsed (zero size).
///
/// The realtime-channel banner from Sprint-A-W3-T5 is intentionally
/// not consumed here — that surface stays standalone per the W3-T3
/// scope.
class KubbOfflineBanner extends ConsumerStatefulWidget {
  const KubbOfflineBanner({super.key});

  /// Vertical padding applied around the chip when the banner is
  /// visible. Matches the audit's "kleine gelbe Pille top" spacing.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: KubbTokens.space4,
    vertical: KubbTokens.space2,
  );

  @override
  ConsumerState<KubbOfflineBanner> createState() => _KubbOfflineBannerState();
}

class _KubbOfflineBannerState extends ConsumerState<KubbOfflineBanner> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Re-render once a minute so the "letzte Sync vor n min" label
    // advances even when no provider event fires. We do not rely on
    // sub-minute precision — Timer drift is fine.
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final online = ref.watch(kubbOfflineBannerOnlineProvider).maybeWhen(
      data: (value) => value,
      orElse: () => ref.read(connectivityServiceProvider).isOnline,
    );
    final status = ref.watch(outboxFlushStatusProvider).maybeWhen(
      data: (s) => s,
      orElse: () => OutboxFlushStatus.idle,
    );
    final lastSyncedAt = ref.watch(lastSyncedAtProvider);
    final now = ref.read(kubbOfflineBannerClockProvider).call();

    final pill = _resolvePill(
      l10n: l10n,
      online: online,
      status: status,
      lastSyncedAt: lastSyncedAt,
      now: now,
    );
    if (pill == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: KubbOfflineBanner.padding,
          child: Align(child: pill),
        ),
      ),
    );
  }

  KubbChip? _resolvePill({
    required AppLocalizations l10n,
    required bool online,
    required OutboxFlushStatus status,
    required DateTime? lastSyncedAt,
    required DateTime now,
  }) {
    // Syncing has priority — surfaces the work even if the connectivity
    // probe is mid-transition.
    if (online && status == OutboxFlushStatus.flushing) {
      return KubbChip(
        tone: KubbChipTone.info,
        label: l10n.offlineBannerSyncing,
      );
    }
    if (!online) {
      final label = lastSyncedAt == null
          ? l10n.offlineBannerOffline
          : l10n.offlineBannerSyncedAgo(_minutesSince(lastSyncedAt, now));
      return KubbChip(
        tone: KubbChipTone.heli,
        label: label,
      );
    }
    return null;
  }

  int _minutesSince(DateTime then, DateTime now) {
    final delta = now.difference(then).inMinutes;
    return delta < 0 ? 0 : delta;
  }
}
