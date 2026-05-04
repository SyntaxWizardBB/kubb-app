import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/stats/application/stats_filter_notifier.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/features/stats/data/stats_repository.dart';

/// Recomputes whenever the active filter, current profile, heli-tracking
/// setting or the underlying repository changes.
final statsAggregateProvider = FutureProvider<StatsAggregate>((ref) async {
  final profile = ref.watch(currentProfileProvider).value;
  if (profile == null) return StatsAggregate.empty();

  final filter = ref.watch(statsFilterProvider);
  final heli = ref.watch(appSettingsProvider).value?.heliTracking ?? true;
  final repo = ref.watch(statsRepositoryProvider);

  return repo.computeAggregate(
    playerId: profile.id,
    filter: filter,
    heliTracking: heli,
  );
});

/// Finisseur-only aggregate. Recomputes when the current profile or the
/// underlying repository changes. Filter pills are sniper-specific so this
/// one does not subscribe to them.
final finisseurStatsAggregateProvider =
    FutureProvider<FinisseurStatsAggregate>((ref) async {
  final profile = ref.watch(currentProfileProvider).value;
  if (profile == null) return FinisseurStatsAggregate.empty();
  final repo = ref.watch(statsRepositoryProvider);
  return repo.computeFinisseurAggregate(playerId: profile.id);
});
