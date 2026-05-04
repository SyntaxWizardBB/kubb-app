import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/training/application/active_finisseur_notifier.dart';
import 'package:kubb_app/features/training/presentation/widgets/kubb_stack_preview.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

const int _totalMax = 10;
const int _baseHardMax = 5;

class FinisseurConfigScreen extends ConsumerStatefulWidget {
  const FinisseurConfigScreen({super.key});

  @override
  ConsumerState<FinisseurConfigScreen> createState() =>
      _FinisseurConfigScreenState();
}

class _FinisseurConfigScreenState
    extends ConsumerState<FinisseurConfigScreen> {
  int _field = 7;
  int _base = 3;

  int get _maxBase =>
      (_totalMax - _field).clamp(0, _baseHardMax);

  void _setField(int v) {
    final next = v.clamp(0, _totalMax);
    setState(() {
      _field = next;
      final maxBase = (_totalMax - next).clamp(0, _baseHardMax);
      if (_base > maxBase) _base = maxBase;
    });
  }

  void _setBase(int v) =>
      setState(() => _base = v.clamp(0, _maxBase));

  Future<void> _start(Player profile) async {
    await ref.read(activeFinisseurProvider.notifier).startSession(
          playerId: profile.id,
          field: _field,
          base: _base,
        );
    if (!mounted) return;
    final id = ref.read(activeFinisseurProvider).value?.sessionId;
    if (id != null) context.go('/training/finisseur/session/$id');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider).value;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.finisseurConfigEyebrow,
        title: l.finisseurConfigTitle,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          color: tokens.fg,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go('/'),
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
            KubbStackPreview(
              field: _field,
              base: _base,
              subtitle: l.finisseurConfigPreviewSubtitle(_field, _base),
            ),
            const SizedBox(height: KubbTokens.space4),
            _Stepper(
              label: l.finisseurConfigFieldLabel,
              value: _field,
              min: 0,
              max: _totalMax,
              onChanged: _setField,
            ),
            const SizedBox(height: KubbTokens.space4),
            _Stepper(
              label: l.finisseurConfigBaseLabel(_maxBase),
              value: _base,
              min: 0,
              max: _maxBase,
              onChanged: _setBase,
              accent: true,
            ),
            const SizedBox(height: KubbTokens.space2),
            Text(
              l.finisseurConfigConstraint(_field + _base),
              style: TextStyle(
                fontSize: 11,
                color: tokens.fgMuted,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: KubbTokens.space8),
            SizedBox(
              height: KubbTokens.touchComfortable,
              child: FilledButton(
                onPressed: profile == null ? null : () => _start(profile),
                child: Text(l.finisseurConfigStartButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.accent = false,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final ringColor = accent ? KubbTokens.wood400 : tokens.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            Text(
              '$min–$max',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: tokens.fgSubtle,
              ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space2),
        Row(
          children: [
            _StepBtn(
              icon: LucideIcons.minus,
              onPressed:
                  value > min ? () => onChanged(value - 1) : null,
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: tokens.bgRaised,
                  borderRadius:
                      BorderRadius.circular(KubbTokens.radiusXl),
                  border: Border.all(color: ringColor, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            _StepBtn(
              icon: LucideIcons.plus,
              onPressed:
                  value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return SizedBox(
      width: 64,
      height: 64,
      child: Material(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(KubbTokens.radiusXl),
              border: Border.all(color: tokens.line, width: 2),
            ),
            child: Icon(
              icon,
              color: onPressed == null ? tokens.fgSubtle : tokens.fg,
            ),
          ),
        ),
      ),
    );
  }
}
