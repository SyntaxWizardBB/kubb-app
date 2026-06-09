import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_statistics_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_stats_participant_picker.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// "Duell" tab of the statistics hub: pick two participants and show their
/// head-to-head record across all finalized tournaments
/// (`tournament_head_to_head`), including a KO split and side-A win rate.
class TournamentStatsDuelTab extends ConsumerStatefulWidget {
  const TournamentStatsDuelTab({super.key});

  @override
  ConsumerState<TournamentStatsDuelTab> createState() =>
      _TournamentStatsDuelTabState();
}

class _TournamentStatsDuelTabState
    extends ConsumerState<TournamentStatsDuelTab> {
  TournamentStatParticipant? _a;
  TournamentStatParticipant? _b;

  Future<void> _pick(bool sideA) async {
    final picked = await TournamentStatsParticipantPicker.show(context);
    if (picked == null || !mounted) return;
    setState(() {
      if (sideA) {
        _a = picked;
      } else {
        _b = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final a = _a;
    final b = _b;

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        Row(
          children: [
            Expanded(
              child: _SideSlot(
                participant: _a,
                placeholder: l.tournamentStatsDuelPickA,
                onTap: () => unawaited(_pick(true)),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
              child: Text(
                'vs',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.fgMuted,
                ),
              ),
            ),
            Expanded(
              child: _SideSlot(
                participant: _b,
                placeholder: l.tournamentStatsDuelPickB,
                onTap: () => unawaited(_pick(false)),
              ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space5),
        // Show the hint until two *distinct* participants are picked.
        if (a == null || b == null || a.participantId == b.participantId)
          Padding(
            padding: const EdgeInsets.only(top: KubbTokens.space6),
            child: Text(
              l.tournamentStatsDuelHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.fgMuted, height: 1.4),
            ),
          )
        else
          _DuelResult(a: a, b: b),
      ],
    );
  }
}

/// Tappable slot showing the chosen side or a placeholder.
class _SideSlot extends StatelessWidget {
  const _SideSlot({
    required this.participant,
    required this.placeholder,
    required this.onTap,
  });

  final TournamentStatParticipant? participant;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final p = participant;
    return Material(
      color: tokens.bgRaised,
      borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: Container(
          height: 96,
          padding: const EdgeInsets.all(KubbTokens.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
            border: Border.all(
              color: p == null ? tokens.line : tokens.primary,
              width: p == null ? 0.5 : 1.2,
            ),
          ),
          child: Center(
            child: p == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline, color: tokens.fgSubtle),
                      const SizedBox(height: KubbTokens.space2),
                      Text(
                        placeholder,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: p.isTeam
                            ? KubbTokens.wood100
                            : KubbTokens.meadow100,
                        child: p.isTeam
                            ? Icon(Icons.groups, size: 20, color: tokens.fg)
                            : Text(
                                p.displayName.isEmpty
                                    ? '?'
                                    : p.displayName.characters.first
                                        .toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: tokens.fg,
                                ),
                              ),
                      ),
                      const SizedBox(height: KubbTokens.space2),
                      Text(
                        p.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.fg,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Watches the head-to-head provider for the chosen pair and renders the
/// record once loaded.
class _DuelResult extends ConsumerWidget {
  const _DuelResult({required this.a, required this.b});

  final TournamentStatParticipant a;
  final TournamentStatParticipant b;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final args = HeadToHeadArgs(a: a.participantId, b: b.participantId);
    final async = ref.watch(tournamentHeadToHeadProvider(args));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: KubbTokens.space8),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: KubbTokens.space6),
        child: Text(
          l.tournamentStatsDuelError,
          textAlign: TextAlign.center,
          style: const TextStyle(color: KubbTokens.miss),
        ),
      ),
      data: (h2h) {
        if (h2h.totalMatches == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: KubbTokens.space6),
            child: Text(
              l.tournamentStatsDuelEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.fgMuted, height: 1.4),
            ),
          );
        }
        final winPct = (h2h.aWinRate * 100).round();
        return Column(
          children: [
            // Win tally: A wins — draws — B wins.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _BigCount(
                  value: '${h2h.aWins}',
                  label: a.displayName,
                  color: tokens.primary,
                ),
                _BigCount(
                  value: '${h2h.draws}',
                  label: l.tournamentStatsDuelDraws,
                  color: tokens.fgMuted,
                ),
                _BigCount(
                  value: '${h2h.bWins}',
                  label: b.displayName,
                  color: tokens.accent,
                  alignEnd: true,
                ),
              ],
            ),
            const SizedBox(height: KubbTokens.space5),
            _StatRow(
              label: l.tournamentStatsDuelTotal,
              value: '${h2h.totalMatches}',
            ),
            _StatRow(
              label: l.tournamentStatsDuelKo,
              value: '${h2h.koMatches} '
                  '(${h2h.koAWins}:${h2h.koBWins})',
            ),
            _StatRow(
              label: l.tournamentStatsDuelWinRate,
              value: '$winPct%',
            ),
          ],
        );
      },
    );
  }
}

class _BigCount extends StatelessWidget {
  const _BigCount({
    required this.value,
    required this.label,
    required this.color,
    this.alignEnd = false,
  });

  final String value;
  final String label;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Expanded(
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: tokens.fgMuted)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, color: tokens.fg),
          ),
        ],
      ),
    );
  }
}
