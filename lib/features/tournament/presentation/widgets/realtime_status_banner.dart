import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Tournament-scoped status strip that surfaces the polling-fallback
/// decision computed by [realtimeFallbackProvider]. The fallback boolean
/// already drives the data layer (matches refetch on a polling cadence
/// when the channel is unhealthy) but the user never saw the decision —
/// a textbook dead-letter on the realtime status stream (R16-F-01).
///
/// The widget is paired with the existing low-level `RealtimeStateBanner`
/// (which animates raw channel transitions); this one renders only when
/// the fallback decision has flipped to "polling" so the user knows that
/// updates may arrive with a small delay.
class RealtimeStatusBanner extends ConsumerWidget {
  const RealtimeStatusBanner({required this.tournamentId, super.key});

  final TournamentId tournamentId;

  static const double height = 28;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(realtimeFallbackProvider(tournamentId));
    final polling = async.maybeWhen(data: (v) => v, orElse: () => false);
    if (!polling) return const SizedBox.shrink();

    return Material(
      color: KubbTokens.wood100,
      child: SizedBox(
        height: height,
        child: Center(
          child: Text(
            l10n.realtimeStatusPolling,
            style: const TextStyle(
              color: KubbTokens.wood800,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
