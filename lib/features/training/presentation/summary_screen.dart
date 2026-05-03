import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class SummaryData {
  const SummaryData({
    required this.session,
    required this.hits,
    required this.misses,
    required this.helis,
  });

  final Session session;
  final int hits;
  final int misses;
  final int helis;
}

// Family inference matches existing repo style; explicit type would shadow
// the public API surface here.
// ignore: specify_nonobvious_property_types
final summarySessionProvider =
    FutureProvider.family<SummaryData, String>((ref, sessionId) async {
  final db = ref.watch(appDatabaseProvider);
  final session = await db.sessionDao.getById(sessionId);
  if (session == null) throw StateError('Session not found: $sessionId');
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

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.summaryEyebrow,
        title: l.summaryTitle,
        automaticallyImplyLeading: false,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (d) => _Body(data: d, settings: settings, l: l, tokens: tokens),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
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
    final relevant = data.hits + data.misses;
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
          if (settings.heliTracking)
            _Row(label: l.summaryHelis, value: '${data.helis}', tokens: tokens),
          _Row(
            label: l.summaryDistance,
            value: '${data.session.distanceMeters.toStringAsFixed(1)} m',
            tokens: tokens,
          ),
          _Row(label: l.summaryDuration, value: dur, tokens: tokens),
          const SizedBox(height: KubbTokens.space8),
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
              onPressed: () async {
                await ref
                    .read(trainingRepositoryProvider)
                    .discard(sessionId: data.session.id);
                if (!context.mounted) return;
                context.go('/');
              },
              child: Text(l.summaryDiscard),
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          TextButton(
            onPressed: () => _restart(context, ref),
            child: Text(l.summaryRestart),
          ),
        ],
      ),
    );
  }

  Future<void> _restart(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(currentProfileProvider).value;
    if (profile == null) return;
    final notifier = ref.read(activeSessionProvider.notifier);
    await notifier.startSession(
      playerId: profile.id,
      distance: data.session.distanceMeters,
      throwTarget: data.session.throwTarget,
    );
    final id = ref.read(activeSessionProvider).value?.sessionId;
    if (!context.mounted || id == null) return;
    context.go('/training/sniper/session/$id');
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
