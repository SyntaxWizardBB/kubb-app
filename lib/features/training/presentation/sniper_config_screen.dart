import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

const _targetPresets = <int?>[null, 25, 50, 100, 200];

class SniperConfigScreen extends ConsumerStatefulWidget {
  const SniperConfigScreen({super.key});

  @override
  ConsumerState<SniperConfigScreen> createState() => _SniperConfigScreenState();
}

class _SniperConfigScreenState extends ConsumerState<SniperConfigScreen> {
  double _distance = 8;
  int? _throwTarget;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(int? v) =>
      setState(() { _throwTarget = v; _customCtrl.clear(); });

  void _onCustomChanged(String raw) {
    final t = raw.trim();
    if (t.isEmpty) { setState(() => _throwTarget = null); return; }
    final n = int.tryParse(t);
    if (n == null || n < 1 || n > 999) return;
    setState(() => _throwTarget = n);
  }

  Future<void> _start(DisplayProfile profile) async {
    await ref.read(activeSessionProvider.notifier).startSession(
          playerId: profile.userId,
          distance: _distance,
          throwTarget: _throwTarget,
        );
    if (!mounted) return;
    final id = ref.read(activeSessionProvider).value?.sessionId;
    if (id != null) context.go('/training/sniper/session/$id');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final profile = ref.watch(displayProfileProvider);
    final isCustom = !_targetPresets.contains(_throwTarget);

    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: KubbAppBar(
        eyebrow: l.sniperConfigEyebrow,
        title: l.sniperConfigTitle,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          color: tokens.fg,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go('/training'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KubbTokens.space4, KubbTokens.space4, KubbTokens.space4, KubbTokens.space8,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Header(label: l.sniperConfigDistanceLabel, value: '${_distance.toStringAsFixed(1)} m'),
          Slider(min: 4, max: 8, divisions: 8, value: _distance,
              onChanged: (v) => setState(() => _distance = v)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (final n in const [4, 5, 6, 7, 8])
                Text('$n.0', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 11,
                  color: _distance.round() == n ? tokens.fg : tokens.fgMuted,
                )),
            ]),
          ),
          const SizedBox(height: KubbTokens.space6),
          _Header(label: l.sniperConfigTargetLabel,
              value: _throwTarget?.toString() ?? l.sniperConfigTargetNone),
          const SizedBox(height: KubbTokens.space2),
          Wrap(spacing: KubbTokens.space2, children: [
            for (final p in _targetPresets)
              ChoiceChip(
                label: Text(p?.toString() ?? '∞'),
                selected: !isCustom && _throwTarget == p,
                onSelected: (_) => _selectPreset(p),
              ),
          ]),
          const SizedBox(height: KubbTokens.space3),
          TextField(
            controller: _customCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: l.sniperConfigTargetCustomHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: _onCustomChanged,
          ),
          const SizedBox(height: KubbTokens.space8),
          SizedBox(
            height: KubbTokens.touchComfortable,
            child: FilledButton(
              onPressed: profile == null ? null : () => _start(profile),
              child: Text(l.sniperConfigStartButton),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label, required this.value});
  final String label; final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tokens.fgMuted)),
      Text(value, style: TextStyle(
        fontSize: 22, fontWeight: FontWeight.w700, color: tokens.fg,
        fontFeatures: const [FontFeature.tabularFigures()],
      )),
    ]);
  }
}
