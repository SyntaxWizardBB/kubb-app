import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// App-shell status strip for the score-submission outbox.
///
/// Subscribes to `outboxFlushStatusProvider` and renders a sticky banner
/// while the flusher is actively draining queued rows or sat on a
/// terminal conflict. `idle` and `paused` collapse the widget to zero
/// height — the `OfflineBanner` already covers the connectivity-paused
/// path and we don't want two strips stacking on top of each other.
///
/// This widget closes R17-F-15 (dead-letter on the outbox status
/// stream): TASK-W1-T1 wired the producer end of
/// [OutboxFlusher.statusStream] but no UI surface ever subscribed.
class OutboxStatusBanner extends ConsumerWidget {
  const OutboxStatusBanner({super.key});

  static const double height = 28;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(outboxFlushStatusProvider).maybeWhen(
          data: (s) => s,
          orElse: () => OutboxFlushStatus.idle,
        );
    final (label, bg, fg) = switch (status) {
      OutboxFlushStatus.flushing => (
          l10n.outboxStatusFlushing,
          KubbTokens.wood100,
          KubbTokens.wood800,
        ),
      OutboxFlushStatus.error => (
          l10n.outboxStatusError,
          const Color(0xFFFBE4E0),
          KubbTokens.miss,
        ),
      OutboxFlushStatus.idle => (null, null, null),
      OutboxFlushStatus.paused => (null, null, null),
    };
    if (label == null || bg == null || fg == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
