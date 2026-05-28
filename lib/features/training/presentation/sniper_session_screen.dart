import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/icons.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_counter.dart';
import 'package:kubb_app/core/ui/widgets/kubb_tap_pad.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_app/features/training/application/active_session_state.dart';
import 'package:kubb_app/features/training/presentation/widgets/abort_dialog.dart';
import 'package:kubb_app/features/training/presentation/widgets/back_confirm.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SniperSessionScreen extends ConsumerWidget {
  const SniperSessionScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final session = ref.watch(activeSessionProvider).value;
    final settings = ref.watch(appSettingsProvider).value ?? const AppSettings();

    if (session == null) {
      return Scaffold(
        backgroundColor: tokens.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    Future<void> handleBack() async {
      final hasThrows = session.hits + session.misses + session.helis > 0;
      if (hasThrows) {
        final discard = await SessionBackConfirm.show(context);
        if (!discard) return;
      }
      await ref.read(activeSessionProvider.notifier).abortAndDelete();
      if (!context.mounted) return;
      context.go('/training/sniper/config');
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await handleBack();
      },
      child: Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
      appBar: KubbAppBar(
        eyebrow: l.sniperConfigEyebrow,
        title: '${session.distance.toStringAsFixed(1)} m',
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          color: tokens.fg,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: handleBack,
        ),
        actions: IconButton(
          tooltip: l.sniperConfigEyebrow,
          icon: KubbIcon(
            settings.sniperEyeToggleHidden ? LucideIcons.eyeOff : LucideIcons.eye,
          ),
          onPressed: () => ref
              .read(appSettingsProvider.notifier)
              .setEyeHidden(value: !settings.sniperEyeToggleHidden),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: KubbTokens.space3),
            _CounterStrip(session: session, settings: settings, l: l),
            if (session.throwTarget != null)
              _Remaining(session: session, heli: settings.heliTracking, l: l),
            if (settings.sniperEyeToggleHidden) _BlindHint(l: l, tokens: tokens),
            const SizedBox(height: KubbTokens.space4),
            Expanded(child: _PadGrid(ref: ref, settings: settings, l: l)),
            TextButton(
              onPressed: () async {
                await ref.read(activeSessionProvider.notifier).complete();
                if (!context.mounted) return;
                context.go('/training/summary/$sessionId');
              },
              child: Text(l.sniperEndButton),
            ),
            TextButton(
              onPressed: () => _onAbort(context, ref, session),
              child: Text(
                l.sniperAbortButton,
                style: TextStyle(color: tokens.fgMuted),
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _onAbort(
    BuildContext context,
    WidgetRef ref,
    ActiveSessionState s,
  ) async {
    final hasThrows = s.hits + s.misses + s.helis > 0;
    final choice = await AbortDialog.show(context, hasThrows: hasThrows);
    if (choice == null || choice == AbortChoice.cancel) return;
    final notifier = ref.read(activeSessionProvider.notifier);
    if (choice == AbortChoice.save) {
      await notifier.complete();
      if (!context.mounted) return;
      context.go('/training/summary/$sessionId');
    } else {
      await notifier.abortAndDelete();
      if (!context.mounted) return;
      context.go('/');
    }
  }
}

void _haptic({required bool enabled}) {
  if (enabled) unawaited(HapticFeedback.lightImpact());
}

void _tap(VoidCallback haptic, Future<void> Function() action) {
  haptic();
  unawaited(action());
}

class _CounterStrip extends StatelessWidget {
  const _CounterStrip({
    required this.session,
    required this.settings,
    required this.l,
  });
  final ActiveSessionState session;
  final AppSettings settings;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final masked = settings.sniperEyeToggleHidden;
    return Row(
      children: [
        Expanded(
          child: KubbCounter(
            label: l.sniperCounterHit,
            value: session.hits,
            tone: KubbCounterTone.hit,
            masked: masked,
          ),
        ),
        Expanded(
          child: KubbCounter(
            label: l.sniperCounterMiss,
            value: session.misses,
            tone: KubbCounterTone.miss,
            masked: masked,
          ),
        ),
        if (settings.heliTracking)
          Expanded(
            child: KubbCounter(
              label: l.sniperCounterHeli,
              value: session.helis,
              tone: KubbCounterTone.heli,
              masked: masked,
              muted: session.helis == 0,
            ),
          ),
      ],
    );
  }
}

class _Remaining extends StatelessWidget {
  const _Remaining({required this.session, required this.heli, required this.l});
  final ActiveSessionState session;
  final bool heli;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final used = session.hits + session.misses + (heli ? session.helis : 0);
    final remaining = (session.throwTarget! - used).clamp(0, 1 << 31);
    return Padding(
      padding: const EdgeInsets.only(top: KubbTokens.space3),
      child: Text(
        l.sniperRemaining(remaining),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: tokens.fgMuted),
      ),
    );
  }
}

class _BlindHint extends StatelessWidget {
  const _BlindHint({required this.l, required this.tokens});
  final AppLocalizations l;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: KubbTokens.space2),
        child: Text(
          l.sniperBlindHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: tokens.fgMuted),
        ),
      );
}

class _PadGrid extends StatelessWidget {
  const _PadGrid({required this.ref, required this.settings, required this.l});
  final WidgetRef ref;
  final AppSettings settings;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(activeSessionProvider.notifier);
    final v = settings.vibration;
    void haptic() => _haptic(enabled: v);
    final pads = <Widget>[
      KubbTapPad(
        label: l.sniperCounterHit,
        sign: '+',
        tone: KubbTapPadTone.hit,
        onTap: () => _tap(haptic, notifier.recordHit),
      ),
      KubbTapPad(
        label: l.sniperCounterHit,
        sign: '−',
        tone: KubbTapPadTone.ghost,
        onTap: () => _tap(haptic, () => notifier.undoLast('hit')),
      ),
      KubbTapPad(
        label: l.sniperCounterMiss,
        sign: '+',
        tone: KubbTapPadTone.miss,
        onTap: () => _tap(haptic, notifier.recordMiss),
      ),
      KubbTapPad(
        label: l.sniperCounterMiss,
        sign: '−',
        tone: KubbTapPadTone.ghost,
        onTap: () => _tap(haptic, () => notifier.undoLast('miss')),
      ),
      if (settings.heliTracking) ...[
        KubbTapPad(
          label: l.sniperCounterHeli,
          sign: '+',
          tone: KubbTapPadTone.heli,
          onTap: () => _tap(haptic, notifier.recordHeli),
        ),
        KubbTapPad(
          label: l.sniperCounterHeli,
          sign: '−',
          tone: KubbTapPadTone.ghost,
          onTap: () => _tap(haptic, () => notifier.undoLast('heli')),
        ),
      ],
    ];
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: KubbTokens.space2,
      crossAxisSpacing: KubbTokens.space2,
      childAspectRatio: 2.2,
      children: pads,
    );
  }
}
