import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_seeding_controller.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Seeding editor for the qualified KO participants.
///
/// Hosts a `ReorderableListView` over the auto-seeded order
/// (`tournamentStandingsProvider`) and three actions: persist the order
/// (`setSeeding`), revert to baseline, and commit the KO phase
/// (`startKoPhase` — repository swallows ERRCODE 40001 idempotently, so
/// a clean completion always navigates to the bracket).
class TournamentSeedingScreen extends ConsumerWidget {
  const TournamentSeedingScreen({required this.tournamentId, super.key});

  final String tournamentId;

  /// Route registered in a later wave; co-located with the only caller.
  static String bracketRoute(String id) => '/tournament/$id/bracket';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final id = TournamentId(tournamentId);
    final standingsAsync = ref.watch(tournamentStandingsProvider(id));
    final detailAsync = ref.watch(tournamentDetailProvider(id));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(title: l.tournamentSeedingTitle),
      body: standingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (standings) => detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(e.toString())),
          data: (detail) {
            final nameMap = <String, String>{
              for (final p in detail?.participants ?? <TournamentParticipant>[])
                if (p.displayName != null) p.participantId: p.displayName!,
            };
            final auto = <TournamentParticipantId>[
              for (final s in standings)
                TournamentParticipantId(s.participantId),
            ];
            // `seed` is idempotent — schedule post-frame to avoid
            // mutating provider state during a widget build.
            final config = _config(auto.length);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(tournamentSeedingControllerProvider(id).notifier)
                  .seed(auto: auto, config: config);
            });
            if (auto.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(KubbTokens.space5),
                  child: Text(
                    l.tournamentSeedingEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.fgMuted, fontSize: 14),
                  ),
                ),
              );
            }
            return _Editor(
              tournamentId: id,
              displayNames: nameMap,
              l: l,
              tokens: tokens,
            );
          },
        ),
      ),
    );
  }

  // Until the wizard exposes a persisted KoPhaseConfig (later wave),
  // default to "all qualified → KO" with the ADR-0017 defaults.
  KoPhaseConfig _config(int participantCount) {
    final n = participantCount < 2 ? 2 : participantCount;
    return KoPhaseConfig(qualifierCount: n, participantCount: n);
  }
}

class _Editor extends ConsumerWidget {
  const _Editor({
    required this.tournamentId,
    required this.displayNames,
    required this.l,
    required this.tokens,
  });

  final TournamentId tournamentId;

  /// participantId → display name, built from `TournamentDetail.participants`.
  final Map<String, String> displayNames;

  final AppLocalizations l;
  final KubbTokens tokens;

  String _nameFor(TournamentParticipantId id) {
    final name = displayNames[id.value];
    if (name != null && name.isNotEmpty) return name;
    final v = id.value;
    return v.length <= 8 ? v : v.substring(0, 8);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tournamentSeedingControllerProvider(tournamentId));
    final notifier =
        ref.read(tournamentSeedingControllerProvider(tournamentId).notifier);
    final busy = state.action.isLoading;
    final err = state.action.hasError ? state.action.error : null;
    // Listener fires after the action AsyncValue transitions from
    // loading→data — both regular success and the 40001 idempotent path
    // land here. We gate on a file-private flag so plain saves don't
    // navigate.
    ref.listen<AsyncValue<void>>(
      tournamentSeedingControllerProvider(tournamentId)
          .select((s) => s.action),
      (prev, next) {
        if (prev?.isLoading == true &&
            next is AsyncData<void> &&
            _startRequested) {
          _startRequested = false;
          context.go(TournamentSeedingScreen.bracketRoute(tournamentId.value));
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.all(KubbTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.tournamentSeedingEyebrow,
                  style: TextStyle(
                    color: tokens.fgMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              InfoIconButton(
                title: l.tournamentSeedingInfoTitle,
                message: l.tournamentSeedingInfoBody,
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(l.tournamentSeedingDragHint,
              style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
          if (err != null) ...[
            const SizedBox(height: KubbTokens.space3),
            // CF6 (K19): the manual-seeding gate surfaces as a typed
            // SeedingRequiredException; show the localized German hint
            // instead of the raw server message. Other errors fall back to
            // their string form.
            _errorBanner(
              tokens,
              l.tournamentSeedingErrorTitle,
              err is SeedingRequiredException
                  ? l.tournamentSeedingRequiredError
                  : err.toString(),
            ),
          ],
          const SizedBox(height: KubbTokens.space3),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: state.order.length,
              buildDefaultDragHandles: false,
              onReorder: busy ? (_, _) {} : notifier.reorder,
              itemBuilder: (context, i) {
                final id = state.order[i];
                final label = displayNames.containsKey(id.value)
                    ? (displayNames[id.value]!.isNotEmpty
                        ? displayNames[id.value]!
                        : l.tournamentParticipantUnknown)
                    : _nameFor(id);
                return _SeedRow(
                  key: ValueKey(id.value),
                  index: i,
                  label: label,
                  positionLabel: l.tournamentSeedingPositionLabel(i + 1),
                  tokens: tokens,
                );
              },
            ),
          ),
          if (state.isDirty) ...[
            const SizedBox(height: KubbTokens.space2),
            Text(
              l.tournamentSeedingDirtyHint,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.accentHover,
              ),
            ),
          ],
          const SizedBox(height: KubbTokens.space3),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    busy ? null : () => unawaited(notifier.autoseedFromElo()),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(l.tournamentSeedingAutoSeedButton),
              ),
            ),
            const SizedBox(width: KubbTokens.space2),
            Expanded(
              child: OutlinedButton(
                onPressed:
                    busy || !state.isDirty ? null : notifier.restoreAuto,
                child: Text(l.tournamentSeedingResetButton),
              ),
            ),
          ]),
          const SizedBox(height: KubbTokens.space2),
          FilledButton.tonal(
            onPressed: busy || !state.isDirty
                ? null
                : () => unawaited(notifier.save()),
            child: Text(l.tournamentSeedingSaveButton),
          ),
          const SizedBox(height: KubbTokens.space3),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(KubbTokens.touchComfortable),
            ),
            onPressed:
                busy ? null : () => unawaited(_confirmAndStartKo(context, ref)),
            child: Text(l.tournamentSeedingStartKoButton),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndStartKo(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.tournamentSeedingStartKoConfirmTitle),
        content: Text(l.tournamentSeedingStartKoConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.confirmCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.tournamentSeedingStartKoConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _startRequested = true;
    await ref
        .read(tournamentSeedingControllerProvider(tournamentId).notifier)
        .startKoPhase();
  }

  Widget _errorBanner(KubbTokens tokens, String title, String message) =>
      Container(
        padding: const EdgeInsets.all(KubbTokens.space3),
        decoration: BoxDecoration(
          color: tokens.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
          border: Border.all(color: tokens.danger),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: tokens.danger, fontWeight: FontWeight.w700)),
            const SizedBox(height: KubbTokens.space1),
            Text(message, style: TextStyle(fontSize: 12, color: tokens.fg)),
          ],
        ),
      );
}

/// One participant in the seeding list. Token-styled to match the wizard's
/// `_InviteCandidateRow`: bordered raised container, meadow avatar with the
/// 1-based seed position, name, and a drag handle.
class _SeedRow extends StatelessWidget {
  const _SeedRow({
    required this.index,
    required this.label,
    required this.positionLabel,
    required this.tokens,
    super.key,
  });

  final int index;
  final String label;
  final String positionLabel;
  final KubbTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KubbTokens.space2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KubbTokens.space3,
          vertical: KubbTokens.space2,
        ),
        decoration: BoxDecoration(
          color: tokens.bgRaised,
          border: Border.all(color: tokens.line),
          borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: KubbTokens.meadow600,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: tokens.onPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: KubbTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tokens.fg,
                    ),
                  ),
                  Text(
                    positionLabel,
                    style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                  ),
                ],
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, color: tokens.fgSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

/// File-private flag separating "save" from "save + start KO" so the
/// post-action navigation only fires after the latter — keeps the
/// controller's state schema aligned with the spec exactly.
bool _startRequested = false;
