import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_statistics_repository.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Bottom-sheet picker that selects one participant (player or team) for the
/// head-to-head comparison from [tournamentStatParticipantsProvider]. Returns
/// the chosen [TournamentStatParticipant], or null when dismissed.
///
/// Mirrors the search-based add flows (debounced text field, result list of
/// avatar-initials tiles). The directory RPC already restricts results to
/// participants of finalized tournaments, so the empty query lists the most
/// active participants.
class TournamentStatsParticipantPicker extends ConsumerStatefulWidget {
  const TournamentStatsParticipantPicker({super.key});

  static Future<TournamentStatParticipant?> show(BuildContext context) {
    return showModalBottomSheet<TournamentStatParticipant>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TournamentStatsParticipantPicker(),
    );
  }

  @override
  ConsumerState<TournamentStatsParticipantPicker> createState() =>
      _TournamentStatsParticipantPickerState();
}

class _TournamentStatsParticipantPickerState
    extends ConsumerState<TournamentStatsParticipantPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = raw.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final async = ref.watch(tournamentStatParticipantsProvider(_query));

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: tokens.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(KubbTokens.radiusXl),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: KubbTokens.space3),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.line,
                  borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(KubbTokens.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tournamentStatsPickerTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
                    const SizedBox(height: KubbTokens.space3),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onChanged,
                      decoration: InputDecoration(
                        hintText: l.tournamentStatsPickerSearchHint,
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: tokens.bgSunken,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(KubbTokens.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(KubbTokens.space5),
                      child: Text(
                        l.tournamentStatsDuelError,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: KubbTokens.miss),
                      ),
                    ),
                  ),
                  data: (rows) => rows.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(KubbTokens.space5),
                            child: Text(
                              l.tournamentStatsPickerEmpty,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: tokens.fgMuted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: rows.length,
                          itemBuilder: (context, i) => _ParticipantRow(
                            row: rows[i],
                            teamBadge: l.tournamentStatsPickerTeamBadge,
                            onTap: () => Navigator.of(context).pop(rows[i]),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.row,
    required this.teamBadge,
    required this.onTap,
  });

  final TournamentStatParticipant row;
  final String teamBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial = row.displayName.isEmpty
        ? '?'
        : row.displayName.characters.first.toUpperCase();
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: KubbTokens.touchMin),
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space4,
          vertical: KubbTokens.space2,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor:
                  row.isTeam ? KubbTokens.wood100 : KubbTokens.meadow100,
              child: row.isTeam
                  ? Icon(Icons.groups, size: 18, color: tokens.fg)
                  : Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: tokens.fg,
                      ),
                    ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Text(
                row.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: tokens.fg),
              ),
            ),
            if (row.isTeam) ...[
              const SizedBox(width: KubbTokens.space2),
              Text(
                teamBadge,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: tokens.fgMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
