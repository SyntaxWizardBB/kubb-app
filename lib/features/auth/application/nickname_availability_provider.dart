import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';

/// Result of a live nickname availability check (BUG-2).
enum NicknameAvailability {
  /// Input too short / not yet a candidate — no check performed.
  idle,

  /// The name is free to use.
  available,

  /// Another user already owns this name.
  taken,
}

/// Debounced availability check for a profile nickname. Keyed by the raw
/// (trimmed) nickname; returns [NicknameAvailability.idle] for blank/too-short
/// input without hitting the network. Excludes the caller's own current name
/// server-side, so re-saving an unchanged nickname reads as available.
///
/// Uses a `FutureProvider.family` with a 350 ms debounce instead of any
/// timer-based polling — consistent with the codebase's no-polling rule.
// ignore: specify_nonobvious_property_types
final nicknameAvailabilityProvider =
    FutureProvider.autoDispose.family<NicknameAvailability, String>(
  (ref, raw) async {
    final nickname = raw.trim();
    // The server enforces 3..30; below that there is nothing to check.
    if (nickname.length < 3) return NicknameAvailability.idle;

    // Debounce: cancel superseded keystrokes before issuing the RPC.
    final completer = Completer<void>();
    final timer = Timer(const Duration(milliseconds: 350), completer.complete);
    ref.onDispose(() {
      timer.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;

    final available =
        await ref.read(cloudProfileRepositoryProvider).isNicknameAvailable(
              nickname,
            );
    return available
        ? NicknameAvailability.available
        : NicknameAvailability.taken;
  },
);
