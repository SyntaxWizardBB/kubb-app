import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_provider.dart';

/// Bridges the connectivity service's online stream into Riverpod so widgets
/// can rebuild on online/offline transitions. Seeded with the current
/// snapshot so the banner renders correctly on the first frame.
final _onlineStateProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield service.isOnline;
  yield* service.onlineStream;
});

/// Reactive pending-count for the score-submission outbox. Re-watched
/// whenever the [_onlineStateProvider] changes so the banner picks up
/// newly-acknowledged rows after a flush pass.
final _pendingSubmissionsProvider = FutureProvider<int>((ref) async {
  ref.watch(_onlineStateProvider);
  final dao = ref.watch(scoreSubmissionOutboxDaoProvider);
  final rows = await dao.pending();
  return rows.length;
});

/// Sticky 36 px top strip that surfaces the device's offline state to the
/// user. Hidden when the connectivity service reports online. Implements
/// TASK-M4.3-T12 of the M4 realtime/offline plan.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  static const double height = 36;
  static const Color _background = Color(0xFFFFF3B0);
  static const Color _foreground = Color(0xFF5C4A00);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(_onlineStateProvider).maybeWhen(
      data: (value) => value,
      orElse: () => ref.read(connectivityServiceProvider).isOnline,
    );
    if (online) return const SizedBox.shrink();

    final pending = ref.watch(_pendingSubmissionsProvider).maybeWhen(
      data: (count) => count,
      orElse: () => 0,
    );
    final label = pending == 0
        ? 'Offline'
        : 'Offline — $pending Submissions ausstehend';

    return Material(
      color: _background,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: _foreground,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
