import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_app/features/training/data/finisseur_repository.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class SummaryData {
  const SummaryData({
    required this.session,
    required this.hits,
    required this.misses,
    required this.helis,
    this.finisseurSticks = const <FinisseurStickEvent>[],
  });

  final Session session;
  final int hits;
  final int misses;
  final int helis;
  final List<FinisseurStickEvent> finisseurSticks;

  bool get isFinisseur => session.mode == 'finisseur';
}

// Family inference matches existing repo style; explicit type would shadow
// the public API surface here.
// ignore: specify_nonobvious_property_types
final summarySessionProvider =
    FutureProvider.family<SummaryData, String>((ref, sessionId) async {
  final db = ref.watch(appDatabaseProvider);
  final session = await db.sessionDao.getById(sessionId);
  if (session == null) throw StateError('Session not found: $sessionId');
  if (session.mode == 'finisseur') {
    return SummaryData(
      session: session,
      hits: 0,
      misses: 0,
      helis: 0,
      finisseurSticks:
          await db.finisseurStickEventDao.forSession(sessionId),
    );
  }
  return SummaryData(
    session: session,
    hits: await db.sessionEventDao.countByKind(sessionId, 'hit'),
    misses: await db.sessionEventDao.countByKind(sessionId, 'miss'),
    helis: await db.sessionEventDao.countByKind(sessionId, 'heli'),
  );
});

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final async = ref.watch(summarySessionProvider(sessionId));
    final settings = ref.watch(appSettingsProvider).value ?? const AppSettings();

    final isFinisseur = async.value?.isFinisseur ?? false;
    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: KubbAppBar(
        eyebrow: isFinisseur ? l.finisseurConfigEyebrow : l.summaryEyebrow,
        title: l.summaryTitle,
        automaticallyImplyLeading: false,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (d) => d.isFinisseur
            ? _FinisseurBody(data: d, settings: settings, l: l, tokens: tokens)
            : _SniperBody(data: d, settings: settings, l: l, tokens: tokens),
      ),
    );
  }
}

class _SniperBody extends ConsumerWidget {
  const _SniperBody({
    required this.data,
    required this.settings,
    required this.l,
    required this.tokens,
  });

  final SummaryData data;
  final AppSettings settings;
  final AppLocalizations l;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Heli counts as a miss in the denominator regardless of the setting —
    // matches stats and recent-list semantics.
    final relevant = data.hits + data.misses + data.helis;
    final rate = relevant == 0
        ? '—'
        : '${(100 * data.hits / relevant).round()} %';
    final dur = _fmtDuration(
      (data.session.completedAt ?? DateTime.now().toUtc())
          .difference(data.session.startedAt),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4, KubbTokens.space4, KubbTokens.space4, KubbTokens.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Verdict(rate: rate, label: l.summaryHitRateLabel, tokens: tokens),
          const SizedBox(height: KubbTokens.space6),
          _Row(label: l.summaryHits, value: '${data.hits}', tokens: tokens),
          _Row(label: l.summaryMisses, value: '${data.misses}', tokens: tokens),
          if (settings.heliTracking && data.helis > 0)
            _Row(label: l.summaryHelis, value: '${data.helis}', tokens: tokens),
          _Row(
            label: l.summaryDistance,
            value: '${data.session.distanceMeters.toStringAsFixed(1)} m',
            tokens: tokens,
          ),
          _Row(label: l.summaryDuration, value: dur, tokens: tokens),
          const SizedBox(height: KubbTokens.space8),
          _Actions(
            session: data.session,
            l: l,
            tokens: tokens,
            onRestart: () => _restartSniper(context, ref, data.session),
          ),
        ],
      ),
    );
  }

  Future<void> _restartSniper(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final profile = ref.read(displayProfileProvider);
    if (profile == null) return;
    final notifier = ref.read(activeSessionProvider.notifier);
    await notifier.startSession(
      playerId: profile.userId,
      distance: session.distanceMeters,
      throwTarget: session.throwTarget,
    );
    final id = ref.read(activeSessionProvider).value?.sessionId;
    if (!context.mounted || id == null) return;
    context.go('/training/sniper/session/$id');
  }
}

class _FinisseurBody extends ConsumerWidget {
  const _FinisseurBody({
    required this.data,
    required this.settings,
    required this.l,
    required this.tokens,
  });

  final SummaryData data;
  final AppSettings settings;
  final AppLocalizations l;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sticks = data.finisseurSticks;
    final field = data.session.finField ?? 0;
    final base = data.session.finBase ?? 0;
    final fieldDown = sticks.fold<int>(0, (a, s) => a + s.fieldKubbsHit);
    final baseDown = sticks.fold<int>(0, (a, s) => a + (s.eightMHit ? 1 : 0));
    final kingHit = sticks.any((s) => s.kingHit ?? false);
    final allKubbsDown = fieldDown >= field && baseDown >= base;
    // Every persisted stick counts toward the budget — including
    // all-zero ones, which represent "stick thrown, missed everything"
    // (same logic as a miss in Sniper mode).
    final sticksUsed = sticks.length;
    final withinRegulation =
        sticksUsed <= ActiveFinisseurState.totalSticks;
    // King-tracking off: success = all kubbs down. King-tracking on: also
    // need the king. Either way, going past 6 sticks always marks the
    // session as a loss.
    final baseSuccess = settings.kingThrowTracking
        ? allKubbsDown && kingHit
        : allKubbsDown;
    final success = baseSuccess && withinRegulation;
    final overSticks = sticksUsed > ActiveFinisseurState.totalSticks;
    final penalties = sticks.fold<int>(
      0,
      (a, s) => a + s.penaltyHits1 + s.penaltyHits2,
    );
    final helis = sticks.where((s) => s.heliThrow).length;
    final longDubbies = sticks
        .where((s) => s.fieldKubbsHit > 0 && s.eightMHit)
        .length;
    final dur = _fmtDuration(
      (data.session.completedAt ?? DateTime.now().toUtc())
          .difference(data.session.startedAt),
    );
    final kingStick = sticks.firstWhere(
      (s) => s.kingHit != null,
      orElse: () => sticks.isEmpty
          ? FinisseurStickEvent(
              id: '',
              sessionId: data.session.id,
              stickIndex: -1,
              fieldKubbsHit: 0,
              eightMHit: false,
              heliThrow: false,
              penaltyHits1: 0,
              penaltyHits2: 0,
              createdAt: DateTime.now().toUtc(),
            )
          : sticks.first,
    );
    final kingValue = kingStick.kingHit == null
        ? l.finisseurSummaryKingNone
        : (kingStick.kingHit!
            ? l.finisseurSummaryKingHit(kingStick.kingPosition ?? '')
            : l.finisseurSummaryKingMiss);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4, KubbTokens.space4, KubbTokens.space4, KubbTokens.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FinisseurVerdict(
            success: success,
            sticksUsed: sticksUsed,
            overSticks: overSticks,
            duration: dur,
            tokens: tokens,
            l: l,
          ),
          const SizedBox(height: KubbTokens.space6),
          if (settings.kingThrowTracking)
            _Row(
              label: l.finisseurSummaryKingRow,
              value: kingValue,
              tokens: tokens,
            ),
          if (settings.penaltyKubbTracking)
            _Row(
              label: l.finisseurSummaryPenalties,
              value: '$penalties',
              tokens: tokens,
            ),
          if (settings.longDubbieTracking)
            _Row(
              label: l.finisseurStickLongDubbieLabel,
              value: '$longDubbies',
              tokens: tokens,
            ),
          if (settings.heliTracking && helis > 0)
            _Row(
              label: l.finisseurSummaryHeli,
              value: '$helis',
              tokens: tokens,
            ),
          _Row(
            label: l.finisseurSummaryModeLabel,
            value: '$field/$base',
            tokens: tokens,
          ),
          _Row(label: l.summaryDuration, value: dur, tokens: tokens),
          const SizedBox(height: KubbTokens.space8),
          _Actions(
            session: data.session,
            l: l,
            tokens: tokens,
            onRestart: () => _restartFinisseur(context, ref, data.session),
          ),
        ],
      ),
    );
  }

  Future<void> _restartFinisseur(
    BuildContext context,
    WidgetRef ref,
    Session session,
  ) async {
    final profile = ref.read(displayProfileProvider);
    if (profile == null) return;
    final notifier = ref.read(activeFinisseurProvider.notifier);
    await notifier.startSession(
      playerId: profile.userId,
      field: session.finField ?? 7,
      base: session.finBase ?? 3,
    );
    final id = ref.read(activeFinisseurProvider).value?.sessionId;
    if (!context.mounted || id == null) return;
    context.go('/training/finisseur/session/$id');
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.session,
    required this.l,
    required this.tokens,
    required this.onRestart,
  });
  final Session session;
  final AppLocalizations l;
  final KubbTokens tokens;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: Text(l.summarySave),
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        SizedBox(
          height: KubbTokens.touchComfortable,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: tokens.danger),
            onPressed: () => _discard(context, ref),
            child: Text(l.summaryDiscard),
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        TextButton(
          onPressed: onRestart,
          child: Text(l.summaryRestart),
        ),
      ],
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    if (session.mode == 'finisseur') {
      await ref
          .read(finisseurRepositoryProvider)
          .discard(sessionId: session.id);
    } else {
      await ref
          .read(trainingRepositoryProvider)
          .discard(sessionId: session.id);
    }
    if (!context.mounted) return;
    context.go('/');
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.rate, required this.label, required this.tokens});
  final String rate;
  final String label;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            rate,
            style: TextStyle(
              fontSize: 84,
              fontWeight: FontWeight.w800,
              height: 0.95,
              letterSpacing: -3.4,
              color: tokens.fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: tokens.fgMuted,
            ),
          ),
        ],
      );
}

class _FinisseurVerdict extends StatelessWidget {
  const _FinisseurVerdict({
    required this.success,
    required this.sticksUsed,
    required this.overSticks,
    required this.duration,
    required this.tokens,
    required this.l,
  });

  final bool success;
  final int sticksUsed;
  final bool overSticks;
  final String duration;
  final KubbTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final tag = success ? l.finisseurSummarySuccess : l.finisseurSummaryFail;
    // Past regulation: show absolute count, not "X / 6". Stays clear that
    // the player went into extended play.
    final headline = overSticks
        ? '$sticksUsed'
        : l.finisseurSummarySticksUsed(sticksUsed);
    final subtitle = overSticks
        ? l.finisseurSummaryOverstickSubtitle(duration)
        : l.finisseurSummarySticksUsedSubtitle(duration);
    return Column(
      children: [
        Text(
          tag.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: success ? tokens.primary : tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          headline,
          style: TextStyle(
            fontSize: 84,
            fontWeight: FontWeight.w800,
            height: 0.95,
            letterSpacing: -3.4,
            color: tokens.fg,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: tokens.fgMuted),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.tokens});
  final String label;
  final String value;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: KubbTokens.space3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: KubbTokens.space3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 14, color: tokens.fgMuted),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: KubbTokens.space4),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
}

String _fmtDuration(Duration d) {
  final s = d.inSeconds.abs();
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}
