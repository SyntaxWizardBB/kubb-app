import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-facing toggle for the public tournament screen (M4.2-T11).
///
/// NOTE (ADR-0029 P2): the public spectator screen currently renders from the
/// anon Broadcast path (`publicTournamentEventsProvider`) directly. The
/// `publicTournamentPollingProvider` fallback (gated to a 10s failure-mode poll
/// via `realtimePollingFallbackProvider`) and this toggle are scaffolding that
/// is NOT yet wired into the screen — a documented follow-up. When wired,
/// `false` (default) keeps the cheap gated-poll path and `true` additionally
/// subscribes to the realtime list channel. Persisted only for the lifetime of
/// the screen.
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
