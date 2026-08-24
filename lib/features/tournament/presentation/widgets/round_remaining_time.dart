import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Live remaining-time readout. Captures the server-computed
/// [remainingSeconds] baseline and decrements it once per second via a PURE
/// UI ticker (ADR-0029: rendering only, no server fetch). When [frozen]
/// (tournament-wide pause active, or the round is not running) the value is
/// shown without ticking.
class RoundRemainingTime extends StatefulWidget {
  const RoundRemainingTime({
    required this.remainingSeconds,
    required this.frozen,
    required this.serverOffset,
    this.ticker,
    super.key,
  });

  final int? remainingSeconds;
  final bool frozen;
  final Duration serverOffset;
  final Stream<void>? ticker;

  @override
  State<RoundRemainingTime> createState() => _RoundRemainingTimeState();
}

class _RoundRemainingTimeState extends State<RoundRemainingTime> {
  late int? _remaining;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _remaining = widget.remainingSeconds;
    _maybeSubscribe();
  }

  @override
  void didUpdateWidget(RoundRemainingTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A fresh fetch (new baseline) re-anchors the countdown.
    if (oldWidget.remainingSeconds != widget.remainingSeconds) {
      _remaining = widget.remainingSeconds;
    }
    if (oldWidget.frozen != widget.frozen) {
      _maybeSubscribe();
    }
  }

  void _maybeSubscribe() {
    unawaited(_sub?.cancel());
    _sub = null;
    if (widget.frozen || _remaining == null) return;
    // Pure 1-second UI render ticker — the ONLY timer this feature may run
    // (ADR-0029 / DoD-14). It performs no server discovery; it just decrements
    // the already-fetched baseline so the readout counts down between fetches.
    final stream =
        widget.ticker ?? Stream<void>.periodic(const Duration(seconds: 1));
    _sub = stream.listen((_) {
      if (!mounted) return;
      setState(() {
        final current = _remaining;
        if (current != null) _remaining = current - 1;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final remaining = _remaining;
    final String text;
    if (remaining == null) {
      text = l.organizerScheduleStatusNone;
    } else if (remaining <= 0) {
      text = l.organizerDashboardExpired;
    } else {
      text = l.organizerDashboardRemaining(_format(remaining));
    }
    final expired = remaining != null && remaining <= 0;
    return Row(
      children: [
        KubbIcon.lucide(
          LucideIcons.timer,
          size: 14,
          color: expired ? KubbTokens.miss : tokens.fgMuted,
        ),
        const SizedBox(width: KubbTokens.space1),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: expired ? KubbTokens.miss : tokens.fg,
          ),
        ),
      ],
    );
  }

  String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
