import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/training/application/cloud_training_provider.dart';
import 'package:kubb_app/features/training/data/cloud_training_repository.dart';

/// Read-only profile of a friend, reached by tapping their entry in the
/// friends list (P2). Shows their identity and the full training statistics
/// they have shared (sniper + finisseur breakdowns), plus a placeholder for
/// the upcoming tournament statistics. The training data is gated server-side:
/// the `training_sessions` friend-read RLS policy only returns rows when an
/// accepted friendship exists, so a non-friend simply sees the empty state.
class FriendProfileScreen extends ConsumerWidget {
  const FriendProfileScreen({
    required this.userId,
    this.nickname,
    super.key,
  });

  final String userId;
  final String? nickname;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final name = (nickname == null || nickname!.isEmpty) ? 'Spieler' : nickname!;
    final async = ref.watch(playerTrainingSessionsProvider(userId));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(title: name),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(playerTrainingSessionsProvider(userId)),
        child: ListView(
          padding: const EdgeInsets.all(KubbTokens.space4),
          children: [
            _ProfileHeader(name: name),
            const SizedBox(height: KubbTokens.space5),
            async.when(
              data: (sessions) => _StatsBody(sessions: sessions),
              loading: () => const Padding(
                padding: EdgeInsets.all(KubbTokens.space5),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                'Statistik konnte nicht geladen werden:\n$e',
                style: const TextStyle(fontSize: 13, color: KubbTokens.miss),
              ),
            ),
            const SizedBox(height: KubbTokens.space6),
            const _SectionLabel('TURNIERSTATISTIK'),
            const SizedBox(height: KubbTokens.space3),
            const KubbEmptyState(
              title: 'Turnierstatistik kommt bald',
              body: 'Sobald die Turnierauswertung steht, siehst du hier die '
                  'Platzierungen und Siegquoten dieses Spielers.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: KubbTokens.meadow600,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            name[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: KubbTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: tokens.fg,
                ),
              ),
              Text(
                'Freund',
                style: TextStyle(fontSize: 13, color: tokens.fgMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full training-stats body: an overview line, then a sniper and a finisseur
/// block (each shown only when the friend has shared sessions of that mode),
/// each with its own metric tiles and a recent-session list.
class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.sessions});

  final List<CloudTrainingSession> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const KubbEmptyState(
        title: 'Noch keine geteilten Trainings',
        body: 'Sobald dieser Spieler eine Trainingssession abschließt, '
            'erscheint die Statistik hier.',
      );
    }

    final sniper = sessions.where((s) => s.isSniper).toList(growable: false);
    final finisseur =
        sessions.where((s) => s.isFinisseur).toList(growable: false);
    final stats = TrainingStats.from(sessions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('ÜBERSICHT'),
        const SizedBox(height: KubbTokens.space3),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Sessions',
                value: '${stats.totalSessions}',
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: _StatTile(
                label: 'Zuletzt',
                value: stats.lastPlayedAt == null
                    ? '–'
                    : DateFormat('dd.MM.yy')
                        .format(stats.lastPlayedAt!.toLocal()),
              ),
            ),
          ],
        ),
        if (sniper.isNotEmpty) ...[
          const SizedBox(height: KubbTokens.space6),
          const _SectionLabel('SNIPER'),
          const SizedBox(height: KubbTokens.space3),
          _SniperBlock(sniper: sniper),
        ],
        if (finisseur.isNotEmpty) ...[
          const SizedBox(height: KubbTokens.space6),
          const _SectionLabel('FINISSEUR'),
          const SizedBox(height: KubbTokens.space3),
          _FinisseurBlock(finisseur: finisseur),
        ],
      ],
    );
  }
}

class _SniperBlock extends StatelessWidget {
  const _SniperBlock({required this.sniper});

  final List<CloudTrainingSession> sniper;

  @override
  Widget build(BuildContext context) {
    final rated = sniper.where((s) => s.hitRate != null).toList();
    final avg = rated.isEmpty
        ? null
        : (rated.map((s) => s.hitRate!).reduce((a, b) => a + b) / rated.length)
            .round();
    final best = rated.isEmpty
        ? null
        : rated.map((s) => s.hitRate!).reduce((a, b) => a > b ? a : b);
    final totalThrows =
        sniper.fold<int>(0, (a, s) => a + (s.throws ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(label: 'Sessions', value: '${sniper.length}'),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: _StatTile(
                label: 'Ø Quote',
                value: avg == null ? '–' : '$avg%',
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: _StatTile(
                label: 'Bester',
                value: best == null ? '–' : '$best%',
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: _StatTile(label: 'Würfe', value: '$totalThrows'),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space3),
        for (final s in sniper.take(5)) ...[
          _SessionRow(session: s),
          const SizedBox(height: KubbTokens.space2),
        ],
      ],
    );
  }
}

class _FinisseurBlock extends StatelessWidget {
  const _FinisseurBlock({required this.finisseur});

  final List<CloudTrainingSession> finisseur;

  @override
  Widget build(BuildContext context) {
    final wins = finisseur.where((s) => s.win ?? false).length;
    final winRate = ((wins / finisseur.length) * 100).round();
    final withSticks = finisseur.where((s) => s.sticksUsed != null).toList();
    final avgSticks = withSticks.isEmpty
        ? null
        : (withSticks.map((s) => s.sticksUsed!).reduce((a, b) => a + b) /
                withSticks.length)
            .toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child:
                  _StatTile(label: 'Sessions', value: '${finisseur.length}'),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: _StatTile(label: 'Siegquote', value: '$winRate%'),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: _StatTile(
                label: 'Ø Stöcke',
                value: avgSticks ?? '–',
              ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space3),
        for (final s in finisseur.take(5)) ...[
          _SessionRow(session: s),
          const SizedBox(height: KubbTokens.space2),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.88,
        color: tokens.fgMuted,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space4,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: tokens.fgMuted),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final CloudTrainingSession session;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final fmt = DateFormat('dd.MM.yy');
    final String tag;
    final String detail;
    if (session.isFinisseur) {
      tag = 'Finisseur';
      // Show the configuration the friend played (field/base kubbs, e.g. 5/3)
      // alongside the outcome so the type of finisseur is visible.
      final config = (session.fieldTarget != null && session.baseTarget != null)
          ? '${session.fieldTarget}/${session.baseTarget} · '
          : '';
      detail = '$config${(session.win ?? false) ? 'Gewonnen' : 'Verloren'}';
    } else {
      tag = 'Sniper';
      final dist = session.distanceM == null
          ? ''
          : '${session.distanceM!.toStringAsFixed(1)} m · ';
      detail = '$dist${session.hitRate ?? 0}% · ${session.throws ?? 0} Würfe';
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space3,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
          Text(
            fmt.format(session.completedAt.toLocal()),
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: tokens.fgMuted,
            ),
          ),
        ],
      ),
    );
  }
}
