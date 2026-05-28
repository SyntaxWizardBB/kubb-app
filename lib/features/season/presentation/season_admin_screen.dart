import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/season/application/season_admin_controller.dart';
import 'package:kubb_app/features/season/data/season_repository.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Liga-Admin CRUD-Screen für Saisonen (TASK-M5.3-T11). Listet sichtbare
/// Saisonen als Tiles (Name + Status-Pill + Date-Range), Tap öffnet
/// einen Bottom-Sheet zum Status-Wechsel und zur Turnier-Zuordnung,
/// FAB öffnet das Create-Sheet (Name, Liga, Start, Ende).
class SeasonAdminScreen extends ConsumerWidget {
  const SeasonAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(seasonAdminControllerProvider);
    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: const KubbAppBar(title: 'Saisonen verwalten'),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateSheet(context, ref),
        child: const Icon(LucideIcons.plus),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e.toString(),
              style: const TextStyle(color: KubbTokens.miss))),
        data: (rows) => rows.isEmpty
            ? Center(
                child: Text('Keine Saisonen angelegt.',
                    style: TextStyle(color: tokens.fgMuted)))
            : ListView.separated(
                padding: const EdgeInsets.all(KubbTokens.space4),
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: KubbTokens.space3),
                itemBuilder: (_, i) => _SeasonTile(
                    season: rows[i],
                    onTap: () => _showDetailSheet(context, ref, rows[i])),
              ),
      ),
    );
  }
}

Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final league = TextEditingController();
  DateTime? start;
  DateTime? end;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (innerCtx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(KubbTokens.space4, KubbTokens.space4,
            KubbTokens.space4,
            MediaQuery.of(innerCtx).viewInsets.bottom + KubbTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Neue Saison',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: KubbTokens.space3),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: league,
                decoration:
                    const InputDecoration(labelText: 'Liga (UUID, optional)')),
            const SizedBox(height: KubbTokens.space2),
            _DateRow(
                label: 'Start',
                value: start,
                onPicked: (d) => setSheet(() => start = d)),
            _DateRow(
                label: 'Ende',
                value: end,
                onPicked: (d) => setSheet(() => end = d)),
            const SizedBox(height: KubbTokens.space3),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                await ref
                    .read(seasonAdminControllerProvider.notifier)
                    .createSeason(
                      name: name.text.trim(),
                      leagueId: league.text.trim().isEmpty
                          ? null
                          : league.text.trim(),
                      startsAt: start,
                      endsAt: end,
                    );
                if (innerCtx.mounted) Navigator.of(innerCtx).pop();
              },
              child: const Text('Anlegen'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showDetailSheet(
    BuildContext context, WidgetRef ref, Season season) async {
  final tournamentId = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => Padding(
      padding: EdgeInsets.fromLTRB(KubbTokens.space4, KubbTokens.space4,
          KubbTokens.space4,
          MediaQuery.of(sheetCtx).viewInsets.bottom + KubbTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(season.name,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: KubbTokens.space3),
          Wrap(
            spacing: KubbTokens.space2,
            children: [
              for (final s in const ['draft', 'open', 'closed'])
                ChoiceChip(
                  label: Text(s),
                  selected: season.status == s,
                  onSelected: (_) async {
                    await ref
                        .read(seasonAdminControllerProvider.notifier)
                        .updateStatus(season.id, s);
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  },
                ),
            ],
          ),
          const SizedBox(height: KubbTokens.space4),
          TextField(
              controller: tournamentId,
              decoration: const InputDecoration(
                  labelText: 'Turnier zuordnen (UUID)')),
          const SizedBox(height: KubbTokens.space2),
          OutlinedButton(
            onPressed: () async {
              final tid = tournamentId.text.trim();
              if (tid.isEmpty) return;
              await ref
                  .read(seasonAdminControllerProvider.notifier)
                  .assignTournament(season.id, tid);
              if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
            },
            child: const Text('Zuordnen'),
          ),
        ],
      ),
    ),
  );
}

class _SeasonTile extends StatelessWidget {
  const _SeasonTile({required this.season, required this.onTap});
  final Season season;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    String fmt(DateTime d) => d.toIso8601String().substring(0, 10);
    final range = [
      if (season.startsAt != null) fmt(season.startsAt!),
      if (season.endsAt != null) fmt(season.endsAt!),
    ].join(' – ');
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space4),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(season.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  if (range.isNotEmpty)
                    Text(range,
                        style:
                            TextStyle(color: tokens.fgMuted, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space2,
                  vertical: KubbTokens.space1),
              decoration: BoxDecoration(
                  color: tokens.bgSunken,
                  borderRadius:
                      BorderRadius.circular(KubbTokens.radiusPill)),
              child: Text(season.status,
                  style: TextStyle(color: tokens.fg, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow(
      {required this.label, required this.value, required this.onPicked});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? '—' : value!.toIso8601String().substring(0, 10);
    return Row(children: [
      Expanded(child: Text('$label: $text')),
      TextButton(
        onPressed: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 5),
            initialDate: value ?? now,
          );
          if (picked != null) onPicked(picked);
        },
        child: const Text('Wählen'),
      ),
    ]);
  }
}
