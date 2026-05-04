import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/presentation/widgets/finisseur_inputs.dart';
import 'package:kubb_app/features/training/presentation/widgets/pip_progress.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class FinisseurStickScreen extends ConsumerWidget {
  const FinisseurStickScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final state = ref.watch(activeFinisseurProvider).value;
    final settings = ref.watch(appSettingsProvider).value;

    if (state == null || settings == null) {
      return Scaffold(
        backgroundColor: tokens.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final stick = state.current;
    final remField = state.remainingFieldBeforeCurrent;
    final remBase = state.remainingBaseBeforeCurrent;
    final fieldDownIfApplied = state.fieldDownPrior + stick.fieldHits;
    final baseDownIfApplied = state.baseDownPrior + (stick.eightMHit ? 1 : 0);
    final allDown = fieldDownIfApplied >= state.field &&
        baseDownIfApplied >= state.base;
    final kingPossible = (allDown || state.isLastStick) &&
        !stick.heli &&
        settings.kingThrowTracking;
    final longDubbiePossible =
        remField > 0 && remBase > 0 && settings.longDubbieTracking;

    Future<void> next() async {
      final notifier = ref.read(activeFinisseurProvider.notifier);
      final wasLast = await notifier.advance();
      if (!context.mounted) return;
      if (wasLast) {
        await notifier.complete();
        if (!context.mounted) return;
        context.go('/training/summary/$sessionId');
      }
    }

    final inFieldPhase = remField > 0;
    final inBasePhase = remField == 0 && remBase > 0;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.finisseurStickEyebrow(state.field, state.base),
        title: l.finisseurStickTitle(state.currentIndex + 1),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4,
          KubbTokens.space2,
          KubbTokens.space4,
          KubbTokens.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PipProgress(
              sticks: state.sticks,
              currentIndex: state.currentIndex,
            ),
            const SizedBox(height: KubbTokens.space3),
            _RemainingBlock(
              field: remField,
              base: remBase,
              labels: l,
            ),
            if (inFieldPhase) ...[
              const SizedBox(height: KubbTokens.space4),
              FinisseurFieldChips(
                max: remField,
                value: stick.fieldHits,
                disabled: stick.heli,
                onChanged: (n) => ref
                    .read(activeFinisseurProvider.notifier)
                    .updateCurrentStick(stick.copyWith(fieldHits: n)),
              ),
              const SizedBox(height: KubbTokens.space3),
              FinisseurToggleGrid(
                stick: stick,
                longDubbiePossible: longDubbiePossible,
                kingPossible: kingPossible,
                heliVisible: settings.heliTracking,
                maxFieldHits: remField,
                onUpdate: (s) => ref
                    .read(activeFinisseurProvider.notifier)
                    .updateCurrentStick(s),
              ),
            ] else if (inBasePhase) ...[
              const SizedBox(height: KubbTokens.space4),
              FinisseurBasePhasePad(
                stick: stick,
                heliVisible: settings.heliTracking,
                onCommit: (patch) async {
                  ref
                      .read(activeFinisseurProvider.notifier)
                      .updateCurrentStick(patch);
                  await next();
                },
              ),
            ],
            if (settings.penaltyKubbTracking &&
                !stick.heli &&
                state.currentIndex == 0 &&
                state.base > 0) ...[
              const SizedBox(height: KubbTokens.space4),
              FinisseurPenaltyBlock(
                base: state.base,
                stick: stick,
                onUpdate: (s) => ref
                    .read(activeFinisseurProvider.notifier)
                    .updateCurrentStick(s),
              ),
            ],
            if (stick.king != null && !stick.heli) ...[
              const SizedBox(height: KubbTokens.space3),
              FinisseurKingDetail(
                king: stick.king!,
                onUpdate: (k) => ref
                    .read(activeFinisseurProvider.notifier)
                    .updateCurrentStick(stick.copyWith(king: k)),
              ),
            ],
            if (!inBasePhase) ...[
              const SizedBox(height: KubbTokens.space6),
              SizedBox(
                height: KubbTokens.touchComfortable,
                child: FilledButton(
                  onPressed: next,
                  child: Text(
                    state.isLastStick
                        ? l.finisseurStickFinish
                        : l.finisseurStickNextStock(state.currentIndex + 2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemainingBlock extends StatelessWidget {
  const _RemainingBlock({
    required this.field,
    required this.base,
    required this.labels,
  });

  final int field;
  final int base;
  final AppLocalizations labels;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: KubbTokens.space3,
        horizontal: KubbTokens.space4,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Cell(
              label: labels.finisseurStickRemainingField,
              value: '$field',
              color: tokens.primary,
            ),
          ),
          Container(width: 1, height: 36, color: tokens.line),
          Expanded(
            child: _Cell(
              label: labels.finisseurStickRemainingBase,
              value: '$base',
              color: KubbTokens.wood500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.88,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
