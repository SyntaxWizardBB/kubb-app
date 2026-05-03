import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

class FinisseurFieldChips extends StatelessWidget {
  const FinisseurFieldChips({
    required this.max,
    required this.value,
    required this.disabled,
    required this.onChanged,
    super.key,
  });

  final int max;
  final int value;
  final bool disabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l.finisseurStickFieldHeader.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted,
              ),
            ),
            Text(
              l.finisseurStickFieldRange(max),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: tokens.fgSubtle,
              ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space2),
        if (max == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
            child: Text(
              l.finisseurStickFieldEmpty,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: tokens.fgMuted,
              ),
            ),
          )
        else
          Wrap(
            spacing: KubbTokens.space2,
            runSpacing: KubbTokens.space2,
            children: List<Widget>.generate(
              max + 1,
              (n) => _BigChip(
                label: '$n',
                selected: value == n && !disabled,
                onTap: disabled ? null : () => onChanged(n),
              ),
            ),
          ),
      ],
    );
  }
}

class _BigChip extends StatelessWidget {
  const _BigChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final bg = selected ? KubbTokens.stone900 : tokens.bgRaised;
    final fg = selected
        ? KubbTokens.chalk50
        : (onTap == null ? tokens.fgSubtle : tokens.fg);
    return SizedBox(
      width: 60,
      height: 60,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
              border: selected
                  ? null
                  : Border.all(color: tokens.line, width: 2),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinisseurToggleGrid extends StatelessWidget {
  const FinisseurToggleGrid({
    required this.stick,
    required this.eightMPossible,
    required this.kingPossible,
    required this.onUpdate,
    super.key,
  });

  final StickResult stick;
  final bool eightMPossible;
  final bool kingPossible;
  final ValueChanged<StickResult> onUpdate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final toggles = <Widget>[];

    if (eightMPossible) {
      toggles.add(_Toggle(
        label: l.finisseurStick8mLabel,
        sub: l.finisseurStick8mSub,
        on: stick.eightMHit && !stick.heli,
        disabled: stick.heli,
        onTap: () => onUpdate(stick.copyWith(eightMHit: !stick.eightMHit)),
      ));
    }
    toggles.add(_Toggle(
      label: l.finisseurStickHeliLabel,
      sub: l.finisseurStickHeliSub,
      on: stick.heli,
      tone: _ToggleTone.heli,
      onTap: () => onUpdate(
        stick.heli
            ? stick.copyWith(heli: false)
            : const StickResult(heli: true),
      ),
    ));
    if (kingPossible) {
      final king = stick.king;
      final sub = king == null
          ? l.finisseurStickKingSubDefault
          : '${_kingPositionLabel(king.position, l)} · '
              '${king.hit ? l.finisseurStickKingHit : l.finisseurStickKingMiss}';
      toggles.add(_Toggle(
        label: l.finisseurStickKingLabel,
        sub: sub,
        on: king != null,
        tone: _ToggleTone.king,
        onTap: () => onUpdate(
          king == null
              ? stick.copyWith(king: const KingResult(hit: true))
              : stick.copyWith(clearKing: true),
        ),
      ));
    }
    if (toggles.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: KubbTokens.space2,
      runSpacing: KubbTokens.space2,
      children: [
        for (final t in toggles)
          SizedBox(
            width: (MediaQuery.of(context).size.width -
                    KubbTokens.space4 * 2 -
                    KubbTokens.space2) /
                2,
            child: t,
          ),
      ],
    );
  }
}

enum _ToggleTone { neutral, heli, king }

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.sub,
    required this.on,
    required this.onTap,
    this.tone = _ToggleTone.neutral,
    this.disabled = false,
  });

  final String label;
  final String sub;
  final bool on;
  final VoidCallback onTap;
  final _ToggleTone tone;
  final bool disabled;

  Color _onColor(KubbTokens tokens) {
    switch (tone) {
      case _ToggleTone.heli:
        return KubbTokens.wood300;
      case _ToggleTone.king:
        return KubbTokens.wood400;
      case _ToggleTone.neutral:
        return tokens.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final bg = on ? _onColor(tokens) : tokens.bgRaised;
    final fg = on ? KubbTokens.stone900 : tokens.fg;
    return Opacity(
      opacity: disabled ? 0.35 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
          onTap: disabled ? null : onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KubbTokens.radiusXl),
              border: on ? null : Border.all(color: tokens.line, width: 2),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space3,
                  vertical: KubbTokens.space2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 11,
                        color: fg.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinisseurPenaltyBlock extends StatelessWidget {
  const FinisseurPenaltyBlock({
    required this.base,
    required this.stick,
    required this.onUpdate,
    super.key,
  });

  final int base;
  final StickResult stick;
  final ValueChanged<StickResult> onUpdate;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final sum = stick.penalty1 + stick.penalty2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l.finisseurStickPenaltyHeader.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted,
              ),
            ),
            Text(
              l.finisseurStickPenaltyMeta(sum, base),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: tokens.fgSubtle,
              ),
            ),
          ],
        ),
        const SizedBox(height: KubbTokens.space2),
        _PenaltyRow(
          label: l.finisseurStickPenaltyFirst,
          sub: l.finisseurStickPenaltyFirstSub,
          value: stick.penalty1,
          max: (base - stick.penalty2).clamp(0, base),
          onChanged: (v) => onUpdate(stick.copyWith(penalty1: v)),
        ),
        const SizedBox(height: KubbTokens.space2),
        _PenaltyRow(
          label: l.finisseurStickPenaltySecond,
          sub: l.finisseurStickPenaltySecondSub,
          value: stick.penalty2,
          max: (base - stick.penalty1).clamp(0, base),
          onChanged: (v) => onUpdate(stick.copyWith(penalty2: v)),
        ),
      ],
    );
  }
}

class _PenaltyRow extends StatelessWidget {
  const _PenaltyRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String sub;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tokens.fg,
                    ),
                  ),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: tokens.fgMuted),
                  ),
                ],
              ),
              Text(
                '$value / $max',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          if (max == 0)
            Text(
              '—',
              style: TextStyle(fontSize: 11, color: tokens.fgMuted),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List<Widget>.generate(
                max + 1,
                (n) => _NumChip(
                  n: n,
                  selected: n == value,
                  onTap: () => onChanged(n),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumChip extends StatelessWidget {
  const _NumChip({
    required this.n,
    required this.selected,
    required this.onTap,
  });
  final int n;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final bg = selected ? tokens.danger : tokens.bg;
    final fg = selected ? tokens.onDanger : tokens.fg;
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        child: InkWell(
          borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
              border: selected
                  ? null
                  : Border.all(color: tokens.lineStrong, width: 1.5),
            ),
            child: Center(
              child: Text(
                '$n',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinisseurKingDetail extends StatelessWidget {
  const FinisseurKingDetail({
    required this.king,
    required this.onUpdate,
    super.key,
  });

  final KingResult king;
  final ValueChanged<KingResult> onUpdate;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(KubbTokens.space3),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
        border: Border.all(color: KubbTokens.wood400, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KingRow(
            label: l.finisseurStickKingPosition,
            options: [
              (l.finisseurStickKingOben, KingPosition.oben),
              (l.finisseurStickKingUnten, KingPosition.unten),
            ],
            selected: king.position,
            onTap: (p) => onUpdate(king.copyWith(position: p)),
          ),
          const SizedBox(height: KubbTokens.space2),
          _KingRow(
            label: l.finisseurStickKingOutcome,
            options: [
              (l.finisseurStickKingHit, true),
              (l.finisseurStickKingMiss, false),
            ],
            selected: king.hit,
            onTap: (h) => onUpdate(king.copyWith(hit: h)),
          ),
        ],
      ),
    );
  }
}

class _KingRow<T> extends StatelessWidget {
  const _KingRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final List<(String, T)> options;
  final T selected;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Row(
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
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.bgSunken,
            borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (label, val) in options)
                  _SegBtn(
                    label: label,
                    selected: val == selected,
                    onTap: () => onTap(val),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SegBtn extends StatelessWidget {
  const _SegBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final bg = selected ? KubbTokens.stone900 : Colors.transparent;
    final fg = selected ? KubbTokens.chalk50 : tokens.fg;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KubbTokens.space3,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _kingPositionLabel(KingPosition p, AppLocalizations l) {
  switch (p) {
    case KingPosition.oben:
      return l.finisseurStickKingOben;
    case KingPosition.unten:
      return l.finisseurStickKingUnten;
  }
}
