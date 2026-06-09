import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Result of a live team-name availability check (BUG-2).
enum NameAvailability { idle, available, taken }

/// Query for the debounced team-name check: the raw name plus an optional
/// team id to exclude (the team being renamed, so its own name is allowed).
@immutable
class TeamNameQuery {
  const TeamNameQuery(this.name, {this.excludeTeamId});
  final String name;
  final TeamId? excludeTeamId;

  @override
  bool operator ==(Object other) =>
      other is TeamNameQuery &&
      other.name == name &&
      other.excludeTeamId?.value == excludeTeamId?.value;

  @override
  int get hashCode => Object.hash(name, excludeTeamId?.value);
}

/// Debounced availability check for a team name. Returns [NameAvailability.idle]
/// for blank input without a network call. Uses a 350 ms debounce instead of
/// any timer-based polling.
// ignore: specify_nonobvious_property_types
final teamNameAvailabilityProvider =
    FutureProvider.autoDispose.family<NameAvailability, TeamNameQuery>(
  (ref, query) async {
    final name = query.name.trim();
    if (name.isEmpty) return NameAvailability.idle;

    final completer = Completer<void>();
    final timer = Timer(const Duration(milliseconds: 350), completer.complete);
    ref.onDispose(() {
      timer.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;

    final available = await ref.read(teamRepositoryProvider).isNameAvailable(
          name,
          excludeTeamId: query.excludeTeamId,
        );
    return available ? NameAvailability.available : NameAvailability.taken;
  },
);
