import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Modal that lets the organizer hand-rank the participants the server
/// could not order during `tournament_start_ko_phase` (OD-M3-05). Shown
/// after a [TieResolutionRequiredException] surfaces from the start RPC.
///
/// Submit calls `resolveCrossPoolTie` with the chosen order and then
/// retries `startKoPhase`. On a clean retry the dialog closes itself and
/// pushes the bracket route; cancellation closes without any RPC calls
/// (KO stays uninitialised on the server).
class CrossPoolTieDialog extends ConsumerStatefulWidget {
  const CrossPoolTieDialog({
    required this.tournamentId,
    required this.config,
    required this.conflictingParticipants,
    super.key,
  });

  final TournamentId tournamentId;
  final KoPhaseConfig config;
  final List<TournamentParticipantId> conflictingParticipants;

  /// Convenience launcher. Returns `true` when the retry succeeded and
  /// the dialog navigated away, `null` on cancel, `false` on retry
  /// failure (dialog stays open while the user reorders again).
  static Future<bool?> show({
    required BuildContext context,
    required TournamentId tournamentId,
    required KoPhaseConfig config,
    required List<TournamentParticipantId> conflictingParticipants,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CrossPoolTieDialog(
        tournamentId: tournamentId,
        config: config,
        conflictingParticipants: conflictingParticipants,
      ),
    );
  }

  @override
  ConsumerState<CrossPoolTieDialog> createState() =>
      _CrossPoolTieDialogState();
}

class _CrossPoolTieDialogState extends ConsumerState<CrossPoolTieDialog> {
  late List<TournamentParticipantId> _order;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _order = List<TournamentParticipantId>.of(widget.conflictingParticipants);
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_busy || oldIndex == newIndex) return;
    setState(() {
      final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
      final item = _order.removeAt(oldIndex);
      _order.insert(adjusted, item);
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final remote = ref.read(tournamentRemoteProvider);
    try {
      await remote.resolveCrossPoolTie(widget.tournamentId, _order);
      await remote.startKoPhase(widget.tournamentId, widget.config);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      // Push bracket after the dialog frame settles to avoid a router
      // call against an already-popping route.
      context.go(TournamentRoutes.bracket(widget.tournamentId.value));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return AlertDialog(
      title: const Text('Tiebreaker auflösen'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Die Tiebreaker-Kette konnte diese Teilnehmer nicht '
              'eindeutig sortieren. Bitte manuell ordnen — die '
              'oberste Position erhält das beste Seeding.',
              style: TextStyle(fontSize: 13, color: tokens.fgMuted),
            ),
            const SizedBox(height: KubbTokens.space3),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _order.length,
                onReorder: _reorder,
                itemBuilder: (context, i) {
                  final id = _order[i];
                  return Card(
                    key: ValueKey(id.value),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      title:
                          Text(id.value, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.drag_handle),
                    ),
                  );
                },
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: KubbTokens.space3),
              Text(
                _error.toString(),
                style: const TextStyle(
                  color: KubbTokens.miss,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Reihenfolge übernehmen'),
        ),
      ],
    );
  }
}
