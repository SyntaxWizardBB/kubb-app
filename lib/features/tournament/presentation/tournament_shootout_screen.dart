import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_shootout_providers.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// P6 shoot-out report/confirm screen (docs/P6_SHOOTOUT_TIEBREAK.md, D2b).
///
/// Reuses the match-consensus two-sided pattern: the involved teams agree on
/// the shoot-out winner ordering (best first) and confirm it mutually. The
/// first side reports an ordering (`tournament_report_shootout_winners`); a
/// different involved side confirms the exact same ordering
/// (`tournament_confirm_shootout`), which resolves the group.
///
/// Entry point is the shoot-out inbox message; the matching open group is
/// selected from [pendingShootoutsProvider] by [startRank] (the inbox payload
/// carries `tournament_id` + `start_rank`).
class TournamentShootoutScreen extends ConsumerStatefulWidget {
  const TournamentShootoutScreen({
    required this.tournamentId,
    required this.startRank,
    super.key,
  });

  final String tournamentId;

  /// Zero-based start rank of the tie group, used to pick the matching open
  /// shoot-out from the caller's pending list.
  final int startRank;

  @override
  ConsumerState<TournamentShootoutScreen> createState() =>
      _TournamentShootoutScreenState();
}

class _TournamentShootoutScreenState
    extends ConsumerState<TournamentShootoutScreen> {
  /// Working order of participant ids (best first). Initialised from the
  /// loaded shoot-out and mutated by the reorder controls.
  List<TournamentParticipantId>? _order;

  /// Shoot-out id the current [_order] was initialised for — guards against
  /// re-initialising on every rebuild while still resetting if the loaded
  /// group changes.
  String? _orderForShootout;

  bool _busy = false;

  TournamentId get _tid => TournamentId(widget.tournamentId);

  void _ensureOrder(PendingShootout shootout) {
    if (_orderForShootout == shootout.shootoutId && _order != null) return;
    // Seed from a reported ordering when present so the confirming side sees
    // exactly what was reported; otherwise from the stored tied order.
    final seed = shootout.orderedWinners.isNotEmpty
        ? shootout.orderedWinners
        : shootout.tiedParticipantIds;
    _order = List<TournamentParticipantId>.of(seed);
    _orderForShootout = shootout.shootoutId;
  }

  void _move(int index, int delta) {
    final order = _order;
    if (order == null) return;
    final target = index + delta;
    if (target < 0 || target >= order.length) return;
    setState(() {
      final item = order.removeAt(index);
      order.insert(target, item);
    });
  }

  /// True when [_order] is a full permutation of the group's tied set — the
  /// [ShootoutResult] invariant the server also enforces. Reorder-only UI can
  /// never break it, but the guard keeps report/confirm honest.
  bool _isValidPermutation(PendingShootout shootout) {
    final order = _order;
    if (order == null) return false;
    final tied = shootout.tiedParticipantIds;
    if (order.length != tied.length) return false;
    final orderSet = order.toSet();
    if (orderSet.length != order.length) return false;
    return orderSet.containsAll(tied);
  }

  Future<void> _report(PendingShootout shootout) async {
    if (!_isValidPermutation(shootout)) return;
    await _run(
      () => ref.read(tournamentShootoutActionsProvider).reportWinners(
            tournamentId: _tid,
            shootoutId: shootout.shootoutId,
            orderedWinners: _order!,
          ),
      successText: AppLocalizations.of(context).shootoutReportedSnack,
    );
  }

  Future<void> _confirm(PendingShootout shootout) async {
    // Confirmation must send EXACTLY the ordering that was reported. The
    // reported group seeds [_order] from `orderedWinners` and reordering is
    // locked in the reported state (see [_ShootoutBody]), so [_order] still
    // carries the reported permutation. The equality guard is a belt-and-
    // suspenders check before we hit the server's ORDER_MISMATCH gate.
    if (!_isValidPermutation(shootout)) return;
    if (!_sameOrder(_order!, shootout.orderedWinners)) return;
    await _run(
      () => ref.read(tournamentShootoutActionsProvider).confirm(
            tournamentId: _tid,
            shootoutId: shootout.shootoutId,
            orderedWinners: _order!,
          ),
      successText: AppLocalizations.of(context).shootoutConfirmedSnack,
    );
  }

  /// True when both lists carry the same ids in the same positions.
  bool _sameOrder(
    List<TournamentParticipantId> a,
    List<TournamentParticipantId> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String successText,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successText)));
      // Resolved (or re-reported) groups drop out of / change in the pending
      // list; pop back to the entry surface.
      if (context.canPop()) context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(AppLocalizations.of(context), '$e')),
          backgroundColor: KubbTokens.miss,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Maps known D2a server error tokens to readable German messages, mirroring
  /// the match-consensus flow. Unknown errors fall back to the generic string.
  String _friendlyError(AppLocalizations l, String raw) {
    if (raw.contains('ORDER_MISMATCH')) return l.shootoutErrorOrderMismatch;
    if (raw.contains('INVALID_ORDER')) return l.shootoutErrorInvalidOrder;
    if (raw.contains('ALREADY_RESOLVED')) return l.shootoutErrorAlreadyResolved;
    if (raw.contains('NOT_REPORTED')) return l.shootoutErrorNotReported;
    // The self-confirm guard is itself a NOT_AUTHORISED variant; check it first.
    if (raw.contains('reporter cannot self-confirm')) {
      return l.shootoutErrorSelfConfirm;
    }
    if (raw.contains('NOT_AUTHORISED')) return l.shootoutErrorNotAuthorised;
    return l.shootoutError(raw);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final async = ref.watch(pendingShootoutsProvider(_tid));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(title: l.shootoutTitle, eyebrow: l.shootoutEyebrow),
      body: async.when(
        data: (shootouts) {
          PendingShootout? shootout;
          for (final s in shootouts) {
            if (s.startRank == widget.startRank) {
              shootout = s;
              break;
            }
          }
          if (shootout == null) {
            return KubbEmptyState(
              title: l.shootoutEmptyTitle,
              body: l.shootoutEmptyBody,
            );
          }
          _ensureOrder(shootout);
          return _ShootoutBody(
            shootout: shootout,
            order: _order!,
            busy: _busy,
            onMove: _move,
            onReport: () => _report(shootout!),
            onConfirm: () => _confirm(shootout!),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              l.shootoutLoadError('$e'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: KubbTokens.miss),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShootoutBody extends StatelessWidget {
  const _ShootoutBody({
    required this.shootout,
    required this.order,
    required this.busy,
    required this.onMove,
    required this.onReport,
    required this.onConfirm,
  });

  final PendingShootout shootout;
  final List<TournamentParticipantId> order;
  final bool busy;
  final void Function(int index, int delta) onMove;
  final VoidCallback onReport;
  final VoidCallback onConfirm;

  String _nameFor(TournamentParticipantId id, AppLocalizations l) {
    for (final p in shootout.tiedParticipants) {
      if (p.participantId == id) {
        return p.displayName ?? l.tournamentParticipantUnknown;
      }
    }
    return l.tournamentParticipantUnknown;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final reported = shootout.status == ShootoutStatus.reported;

    return ListView(
      padding: const EdgeInsets.all(KubbTokens.space4),
      children: [
        Text(
          l.shootoutIntro,
          style: TextStyle(fontSize: 14, height: 1.5, color: tokens.fg),
        ),
        if (reported) ...[
          const SizedBox(height: KubbTokens.space4),
          Container(
            padding: const EdgeInsets.all(KubbTokens.space3),
            decoration: BoxDecoration(
              color: tokens.bgRaised,
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 18, color: tokens.fgMuted),
                const SizedBox(width: KubbTokens.space2),
                Expanded(
                  child: Text(
                    l.shootoutReportedBanner,
                    style: TextStyle(fontSize: 13, color: tokens.fgMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: KubbTokens.space5),
        Text(
          l.shootoutParticipantsHeader,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: tokens.fg,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          // In the reported state the order is fixed to what was reported, so
          // the confirming side reads instead of reorders.
          reported ? l.shootoutOrderHintReadonly : l.shootoutOrderHint,
          style: TextStyle(fontSize: 12, color: tokens.fgMuted),
        ),
        const SizedBox(height: KubbTokens.space3),
        for (var i = 0; i < order.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: KubbTokens.space2),
            child: _OrderRow(
              rankLabel: l.shootoutRankLabel(i + 1),
              name: _nameFor(order[i], l),
              // Lock reordering once a side has reported: confirmation must
              // send the exact reported permutation (AC11).
              canMoveUp: i > 0 && !busy && !reported,
              canMoveDown: i < order.length - 1 && !busy && !reported,
              onMoveUp: () => onMove(i, -1),
              onMoveDown: () => onMove(i, 1),
            ),
          ),
        const SizedBox(height: KubbTokens.space6),
        SizedBox(
          width: double.infinity,
          child: KubbButton(
            variant: KubbButtonVariant.primary,
            size: KubbButtonSize.large,
            isLoading: busy,
            onPressed: busy ? null : (reported ? onConfirm : onReport),
            child: Text(
              reported ? l.shootoutConfirmAction : l.shootoutReportAction,
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.rankLabel,
    required this.name,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final String rankLabel;
  final String name;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              rankLabel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: tokens.fgMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.fg,
              ),
            ),
          ),
          IconButton(
            tooltip: l.shootoutMoveUp,
            iconSize: 22,
            constraints: const BoxConstraints(
              minWidth: KubbTokens.touchMin,
              minHeight: KubbTokens.touchMin,
            ),
            icon: const Icon(LucideIcons.chevronUp),
            color: tokens.fg,
            onPressed: canMoveUp ? onMoveUp : null,
          ),
          IconButton(
            tooltip: l.shootoutMoveDown,
            iconSize: 22,
            constraints: const BoxConstraints(
              minWidth: KubbTokens.touchMin,
              minHeight: KubbTokens.touchMin,
            ),
            icon: const Icon(LucideIcons.chevronDown),
            color: tokens.fg,
            onPressed: canMoveDown ? onMoveDown : null,
          ),
        ],
      ),
    );
  }
}
