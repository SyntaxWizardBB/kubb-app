import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-facing toggle for the public tournament screen (M4.2-T11).
///
/// `false` (default) keeps the public view on the cheap 10s polling
/// path via `publicTournamentPollingProvider`; flipping to `true`
/// additionally subscribes to `tournamentMatchListRealtimeProvider`
/// so spectators see consensus-round bumps and finalisations without
/// the polling lag. Persisted only for the lifetime of the screen —
/// the next session re-opens in the polling default per spec.
///
/// Implemented as a [Notifier] rather than the legacy `StateProvider`
/// because Riverpod 3.x drops the latter from `flutter_riverpod`.
class PublicLiveMode extends Notifier<bool> {
  @override
  bool build() => false;

  // Positional bool reads naturally at the call site (Switch.onChanged).
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void set(bool value) => state = value;
}

final publicLiveModeProvider =
    NotifierProvider<PublicLiveMode, bool>(PublicLiveMode.new);
