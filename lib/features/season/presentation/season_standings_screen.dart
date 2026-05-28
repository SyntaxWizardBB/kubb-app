import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/season/application/season_standings_provider.dart';
import 'package:kubb_app/features/season/presentation/widgets/standings_row.dart';

/// Saison-Tabelle (TASK-M5.3-T12). Lists the cross-tournament standings
/// sorted per OD-M5-06 A. `ListView.builder` keeps rendering lazy so
/// R-M5.3-1 (200-row smoke target) holds.
class SeasonStandingsScreen extends ConsumerStatefulWidget {
  const SeasonStandingsScreen({required this.seasonId, super.key});

  final String seasonId;

  @override
  ConsumerState<SeasonStandingsScreen> createState() =>
      _SeasonStandingsScreenState();
}

class _SeasonStandingsScreenState
    extends ConsumerState<SeasonStandingsScreen> {
  String? _leagueFilter;

  Future<void> _refresh() async {
    ref.invalidate(seasonStandingsProvider(widget.seasonId));
    await ref.read(seasonStandingsProvider(widget.seasonId).future);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(seasonStandingsProvider(widget.seasonId));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(title: 'Saison-Tabelle'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text('Tabelle konnte nicht geladen werden: $e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: KubbTokens.miss)),
          ),
        ),
        data: (standings) {
          final filtered = _leagueFilter == null
              ? standings.rows
              : standings.rows
                  .where((r) => r.leagueId == _leagueFilter)
                  .toList(growable: false);
          return Column(
            children: [
              if (standings.leagueIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KubbTokens.space4,
                    KubbTokens.space2,
                    KubbTokens.space4,
                    KubbTokens.space2,
                  ),
                  child: DropdownButtonFormField<String?>(
                    initialValue: _leagueFilter,
                    decoration: const InputDecoration(
                        labelText: 'Liga-Filter', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(
                          child: Text('Alle Ligen')),
                      for (final id in standings.leagueIds)
                        DropdownMenuItem<String?>(
                          value: id,
                          child: Text(id.length <= 8 ? id : id.substring(0, 8)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _leagueFilter = v),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: filtered.isEmpty
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.all(KubbTokens.space6),
                            child: Text('Noch keine Punkte vergeben.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: tokens.fgMuted)),
                          ),
                        ])
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, i) => StandingsRow(
                              rank: i + 1, row: filtered[i]),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
