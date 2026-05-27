import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Thin status strip layered above the screen content to surface the
/// Realtime channel health. Three visible states map to one colour each
/// (orange `connecting`, green `joined`, yellow `errored` after 60 s);
/// `joined` auto-hides after [joinedVisible] so the live signal does
/// not linger. Strings are inline constants until TASK-M4.1-T13
/// migrates them into the generated l10n.
class RealtimeStateBanner extends StatefulWidget {
  const RealtimeStateBanner({
    this.stateStream,
    this.tournamentId,
    super.key,
  }) : assert(
          stateStream != null || tournamentId != null,
          'RealtimeStateBanner requires stateStream or tournamentId',
        );

  /// Source of channel-state transitions. Typically the
  /// `RealtimeChannel.stateStream(key)` exposed by the adapter.
  final Stream<RealtimeChannelState>? stateStream;

  /// Convenience for screens: resolves stateStream from the
  /// realtimeChannelProvider for this tournament. Either this or
  /// [stateStream] must be supplied.
  final TournamentId? tournamentId;

  // Inline DE strings — replaced with `S.of(context).realtime*` in T13.
  static const String labelConnecting = 'verbinde…';
  static const String labelLive = 'live';
  static const String labelPolling = 'offline, Polling aktiv';

  /// `joined` indicator fades after this delay so the banner stays calm.
  static const Duration joinedVisible = Duration(milliseconds: 1500);

  /// Tolerance before an `errored` state escalates to the polling label.
  static const Duration erroredGrace = Duration(seconds: 60);

  @override
  State<RealtimeStateBanner> createState() => _RealtimeStateBannerState();
}

class _RealtimeStateBannerState extends State<RealtimeStateBanner> {
  StreamSubscription<RealtimeChannelState>? _sub;
  Timer? _joinedTimer;
  Timer? _erroredTimer;
  RealtimeChannelState? _state;
  bool _erroredEscalated = false;

  @override
  void initState() {
    super.initState();
    final stream = widget.stateStream;
    if (stream != null) _sub = stream.listen(_onState);
  }

  @override
  void didUpdateWidget(covariant RealtimeStateBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateStream != widget.stateStream) {
      unawaited(_sub?.cancel() ?? Future<void>.value());
      final stream = widget.stateStream;
      _sub = stream?.listen(_onState);
    }
  }

  void _onState(RealtimeChannelState next) {
    _joinedTimer?.cancel();
    if (next != RealtimeChannelState.errored) {
      _erroredTimer?.cancel();
      _erroredEscalated = false;
    }
    setState(() => _state = next);
    if (next == RealtimeChannelState.joined) {
      _joinedTimer = Timer(RealtimeStateBanner.joinedVisible, () {
        if (!mounted) return;
        setState(() => _state = null);
      });
    } else if (next == RealtimeChannelState.errored) {
      _erroredTimer ??= Timer(RealtimeStateBanner.erroredGrace, () {
        if (!mounted) return;
        setState(() => _erroredEscalated = true);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _joinedTimer?.cancel();
    _erroredTimer?.cancel();
    super.dispose();
  }

  ({String label, Color bg, Color fg})? _spec() => switch (_state) {
        RealtimeChannelState.connecting => (
            label: RealtimeStateBanner.labelConnecting,
            bg: KubbTokens.wood300,
            fg: KubbTokens.wood800,
          ),
        RealtimeChannelState.joined => (
            label: RealtimeStateBanner.labelLive,
            bg: const Color(0xFFB7DDB1),
            fg: const Color(0xFF1F4A1B),
          ),
        RealtimeChannelState.errored when _erroredEscalated => (
            label: RealtimeStateBanner.labelPolling,
            bg: KubbTokens.wood100,
            fg: KubbTokens.wood700,
          ),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final spec = _spec();
    if (spec == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space1,
      ),
      color: spec.bg,
      child: Text(
        spec.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: spec.fg,
        ),
      ),
    );
  }
}
