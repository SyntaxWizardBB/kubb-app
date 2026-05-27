import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/tournament/application/public_live_mode_provider.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_polling_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Public spectator view of one tournament (M4.2-T11 stub).
///
/// Wave-Merge (M4.2-T8) replaces the body; this stub only wires the
/// live-mode toggle so the polling / realtime providers can be
/// exercised end-to-end. When the switch is OFF the screen invalidates
/// [tournamentMatchListProvider] every 10s via
/// [publicTournamentPollingProvider]; flipping it ON additionally
/// watches [tournamentMatchListRealtimeProvider] for CDC events.
class PublicTournamentScreen extends ConsumerWidget {
  const PublicTournamentScreen({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = TournamentId(tournamentId);
    final live = ref.watch(publicLiveModeProvider);

    if (live) {
      ref.watch(tournamentMatchListRealtimeProvider(id));
    } else {
      ref.watch(publicTournamentPollingProvider(id));
    }

    final async = ref.watch(tournamentMatchListProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Public tournament'),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Live-Modus'),
              Switch(
                value: live,
                onChanged: (v) =>
                    ref.read(publicLiveModeProvider.notifier).set(v),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Variante: ${live ? "realtime" : "polling (10s)"}'),
            const SizedBox(height: 16),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Fehler: $e')),
                data: (matches) => Text('${matches.length} Matches'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
