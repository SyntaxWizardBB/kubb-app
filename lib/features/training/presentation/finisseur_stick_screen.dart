import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/presentation/widgets/abort_dialog.dart';
import 'package:kubb_app/features/training/presentation/widgets/finisseur_inputs.dart';
import 'package:kubb_app/features/training/presentation/widgets/pip_progress.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
    final longDubbiePossible =
        remField > 0 && remBase > 0 && settings.longDubbieTracking;

    Future<void> next() async {
      final notifier = ref.read(activeFinisseurProvider.notifier);
      final outcome = await notifier.advance();
      if (!context.mounted) return;
      switch (outcome) {
        case FinisseurAdvanceOutcome.done:
          await notifier.complete();
          if (!context.mounted) return;
          context.go('/training/summary/$sessionId');
        case FinisseurAdvanceOutcome.needsContinueDecision:
        case FinisseurAdvanceOutcome.carryOn:
          // UI will rebuild from the new state. Continue-decision shows the
          // dialog block; carryOn just renders the next stick.
          break;
      }
    }

    final phase = state.phase;
    final inFieldPhase = phase == FinisseurPhase.field;
    final inBasePhase = phase == FinisseurPhase.base;
    final inKingPhase = phase == FinisseurPhase.king;
    final awaitingContinue = phase == FinisseurPhase.awaitingContinueDecision;
    final hasProgress = state.currentIndex > 0 || !stick.isUntouched;

    Future<void> handleBack() async {
      final notifier = ref.read(activeFinisseurProvider.notifier);
      // Past the first stick: back means "undo the last commit", no confirm.
      if (state.currentIndex > 0) {
        await notifier.rollbackLastStick();
        return;
      }
      // First stick, untouched: nothing to lose, discard quietly.
      if (!hasProgress) {
        await notifier.abortAndDelete();
        if (!context.mounted) return;
        context.go('/training');
        return;
      }
      // First stick with edits: ask before throwing them away.
      final discard = await FinisseurAbortConfirm.show(context);
      if (!discard) return;
      await notifier.abortAndDelete();
      if (!context.mounted) return;
      context.go('/training');
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await handleBack();
      },
      child: Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: KubbAppBar(
        eyebrow: l.finisseurStickEyebrow(state.field, state.base),
        title: l.finisseurStickTitle(state.currentIndex + 1),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          color: tokens.fg,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: handleBack,
        ),
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
            _PhaseProgress(state: state),
            const SizedBox(height: KubbTokens.space3),
            _RemainingBlock(
              field: remField,
              base: remBase,
              labels: l,
            ),
            if (awaitingContinue) ...[
              const SizedBox(height: KubbTokens.space5),
              _ContinueDecisionBlock(
                onContinue: () async {
                  await ref
                      .read(activeFinisseurProvider.notifier)
                      .continueBeyondStocks();
                },
                onGiveUp: () async {
                  await ref.read(activeFinisseurProvider.notifier).giveUp();
                  if (!context.mounted) return;
                  context.go('/training/summary/$sessionId');
                },
              ),
            ] else if (inFieldPhase) ...[
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
                // King is its own phase now — never offered in field phase.
                kingPossible: false,
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
                onHit: () async {
                  ref
                      .read(activeFinisseurProvider.notifier)
                      .updateCurrentStick(
                        stick.copyWith(eightMHit: true),
                      );
                  await next();
                },
                onMiss: () async {
                  ref
                      .read(activeFinisseurProvider.notifier)
                      .updateCurrentStick(
                        stick.copyWith(eightMHit: false),
                      );
                  await next();
                },
                onHeli: () async {
                  ref
                      .read(activeFinisseurProvider.notifier)
                      .updateCurrentStick(stick.copyWith(
                        heli: true,
                        fieldHits: 0,
                        eightMHit: false,
                        clearKing: true,
                      ));
                  await next();
                },
              ),
            ] else if (inKingPhase) ...[
              const SizedBox(height: KubbTokens.space4),
              FinisseurKingDetail(
                king: stick.king ?? const KingResult(hit: true),
                onUpdate: (k) => ref
                    .read(activeFinisseurProvider.notifier)
                    .updateCurrentStick(stick.copyWith(king: k)),
              ),
            ],
            if (settings.penaltyKubbTracking &&
                !stick.heli &&
                state.currentIndex == 0 &&
                state.base > 0 &&
                inFieldPhase) ...[
              const SizedBox(height: KubbTokens.space4),
              FinisseurPenaltyBlock(
                base: state.base,
                stick: stick,
                onUpdate: (s) => ref
                    .read(activeFinisseurProvider.notifier)
                    .updateCurrentStick(s),
              ),
            ],
            if (!awaitingContinue && (inFieldPhase || inKingPhase)) ...[
              const SizedBox(height: KubbTokens.space6),
              SizedBox(
                height: KubbTokens.touchComfortable,
                child: FilledButton(
                  onPressed: next,
                  child: Text(
                    inKingPhase
                        ? l.finisseurStickFinishStick
                        : (state.isLastStick
                            ? l.finisseurStickFinish
                            : l.finisseurStickNextStock(
                                state.currentIndex + 2,
                              )),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}

/// Visualises stick progress. Up to six pips render as the original PipProgress
/// row; once the player has chosen to continue past stick 6, we swap to a
/// compact "Verlängerung Stock N" badge so the row does not get squashed.
class _PhaseProgress extends StatelessWidget {
  const _PhaseProgress({required this.state});

  final ActiveFinisseurState state;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    if (!state.continuedBeyondSticks &&
        state.sticks.length <= ActiveFinisseurState.totalSticks) {
      return PipProgress(
        sticks: state.sticks,
        currentIndex: state.currentIndex,
      );
    }
    final extra = state.currentIndex - ActiveFinisseurState.totalSticks + 1;
    final base = state.sticks.take(ActiveFinisseurState.totalSticks).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PipProgress(sticks: base, currentIndex: ActiveFinisseurState.totalSticks),
        const SizedBox(height: KubbTokens.space2),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space3,
            vertical: KubbTokens.space1,
          ),
          decoration: BoxDecoration(
            color: tokens.bgRaised,
            borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          ),
          child: Text(
            'Verlängerung · Stock $extra',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tokens.fgMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueDecisionBlock extends StatelessWidget {
  const _ContinueDecisionBlock({
    required this.onContinue,
    required this.onGiveUp,
  });

  final Future<void> Function() onContinue;
  final Future<void> Function() onGiveUp;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space4),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
        border: Border.all(color: KubbTokens.wood400, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.continueDecisionTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(
            l.continueDecisionBody,
            style: TextStyle(fontSize: 14, color: tokens.fgMuted),
          ),
          const SizedBox(height: KubbTokens.space4),
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: FilledButton(
              onPressed: onContinue,
              child: Text(l.continueDecisionContinue),
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: tokens.danger),
              onPressed: onGiveUp,
              child: Text(l.continueDecisionGiveUp),
            ),
          ),
        ],
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
