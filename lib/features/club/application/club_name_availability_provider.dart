import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/club/data/club_repository.dart';
import 'package:kubb_app/features/team/application/team_name_availability_provider.dart'
    show NameAvailability;

/// Debounced availability check for a club name (BUG-2). Returns
/// [NameAvailability.idle] for blank input without a network call. A club
/// rename feature does not exist yet, so there is no exclude-id query — this
/// only serves club CREATE. Uses a 350 ms debounce, not polling.
// ignore: specify_nonobvious_property_types
final clubNameAvailabilityProvider =
    FutureProvider.autoDispose.family<NameAvailability, String>(
  (ref, raw) async {
    final name = raw.trim();
    if (name.isEmpty) return NameAvailability.idle;

    final completer = Completer<void>();
    final timer = Timer(const Duration(milliseconds: 350), completer.complete);
    ref.onDispose(() {
      timer.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;

    final available =
        await ref.read(clubRepositoryProvider).isNameAvailable(name);
    return available ? NameAvailability.available : NameAvailability.taken;
  },
);
