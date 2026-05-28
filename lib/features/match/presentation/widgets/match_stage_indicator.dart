import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/match/data/match_models.dart';

/// Read-only stage indicator that mirrors the Mobile-Kit `stageTabs`
/// pattern from `docs/design/ui_kits/app/MatchScreen.jsx` (Z. 25-31,
/// styles Z. 285-287). Three pills — **Lobby / Live / Ergebnis** —
/// sit inside a `bgSunken` container with `radius 999`, `padding 3`,
/// `gap 4`. The active pill is filled with `stone-900` on `chalk-50`;
/// the others stay transparent with `fgMuted` text.
///
/// The widget is purely presentational — no `onTap`. The active pill
/// is derived from [MatchStatus]:
///
///   - `pendingInvites`   → **Lobby** active
///   - `active`           → **Live**  active
///   - `awaitingResults`  → **Ergebnis** active (per W5-T1-Spec §Layout)
///   - `finalized`        → **Ergebnis** active
///   - `voided`           → **Ergebnis** active
///
/// Sprint B / W5.1-A. Refs BH-A-01 + BH-C-01 — placed by all four
/// match screens (Lobby / Result / AwaitOthers / Finished) directly
/// below the `KubbAppBar`.
class MatchStageIndicator extends StatelessWidget {
  const MatchStageIndicator({required this.status, super.key});

  final MatchStatus status;

  static _Stage _activeStageFor(MatchStatus status) {
    switch (status) {
      case MatchStatus.pendingInvites:
        return _Stage.lobby;
      case MatchStatus.active:
        return _Stage.live;
      case MatchStatus.awaitingResults:
      case MatchStatus.finalized:
      case MatchStatus.voided:
        return _Stage.ergebnis;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final active = _activeStageFor(status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space1,
        KubbTokens.space4,
        KubbTokens.space3,
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: tokens.bgSunken,
          borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
        ),
        child: Row(
          children: [
            _StagePill(
              label: 'Lobby',
              isActive: active == _Stage.lobby,
            ),
            const SizedBox(width: 4),
            _StagePill(
              label: 'Live',
              isActive: active == _Stage.live,
            ),
            const SizedBox(width: 4),
            _StagePill(
              label: 'Ergebnis',
              isActive: active == _Stage.ergebnis,
            ),
          ],
        ),
      ),
    );
  }
}

enum _Stage { lobby, live, ergebnis }

class _StagePill extends StatelessWidget {
  const _StagePill({required this.label, required this.isActive});

  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Expanded(
      child: Semantics(
        container: true,
        selected: isActive,
        label: label,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? KubbTokens.stone900 : Colors.transparent,
            borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isActive ? KubbTokens.chalk50 : tokens.fgMuted,
            ),
          ),
        ),
      ),
    );
  }
}
