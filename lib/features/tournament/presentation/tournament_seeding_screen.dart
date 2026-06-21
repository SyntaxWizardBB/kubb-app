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
                title: l.tournamentSetupInfoSeedingSortTitle,
                message: l.tournamentSetupInfoSeedingSortBody,
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          Text(l.tournamentSeedingDragHint,
              style: const TextStyle(fontSize: 13)),
          if (err != null) ...[
            const SizedBox(height: KubbTokens.space3),
            // CF6 (K19): the manual-seeding gate surfaces as a typed
            // SeedingRequiredException; show the localized German hint
            // instead of the raw server message. Other errors fall back to
            // their string form.
            _errorBanner(
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
              onReorder: busy ? (_, _) {} : notifier.reorder,
              itemBuilder: (context, i) {
                final id = state.order[i];
                final label = displayNames.containsKey(id.value)
                    ? (displayNames[id.value]!.isNotEmpty
                        ? displayNames[id.value]!
                        : l.tournamentParticipantUnknown)
                    : _nameFor(id);
                return Card(
                  key: ValueKey(id.value),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    title: Text(label, overflow: TextOverflow.ellipsis),
                    subtitle:
                        Text(l.tournamentSeedingPositionLabel(i + 1)),
                    trailing: const Icon(Icons.drag_handle),
                  ),
                );
              },
            ),
          ),
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
            InfoIconButton(
              title: l.tournamentSetupInfoSeedingEloTitle,
              message: l.tournamentSetupInfoSeedingEloBody,
            ),
          ]),
          const SizedBox(height: KubbTokens.space2),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    busy || !state.isDirty ? null : notifier.restoreAuto,
                child: Text(l.tournamentSeedingResetButton),
              ),
            ),
            InfoIconButton(
              title: l.tournamentSetupInfoSeedingRestoreTitle,
              message: l.tournamentSetupInfoSeedingRestoreBody,
            ),
            const SizedBox(width: KubbTokens.space1),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : () => unawaited(notifier.save()),
                child: Text(l.tournamentSeedingSaveButton),
              ),
            ),
            InfoIconButton(
              title: l.tournamentSetupInfoSeedingSaveTitle,
              message: l.tournamentSetupInfoSeedingSaveBody,
            ),
          ]),
          const SizedBox(height: KubbTokens.space2),
          Row(children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () {
                        _startRequested = true;
                        unawaited(notifier.startKoPhase());
                      },
                child: Text(l.tournamentSeedingStartKoButton),
              ),
            ),
            InfoIconButton(
              title: l.tournamentSetupInfoSeedingStartKoTitle,
              message: l.tournamentSetupInfoSeedingStartKoBody,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _errorBanner(String title, String message) => Container(
        padding: const EdgeInsets.all(KubbTokens.space3),
        decoration: BoxDecoration(
          color: KubbTokens.miss.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KubbTokens.miss),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: KubbTokens.miss, fontWeight: FontWeight.w700)),
            const SizedBox(height: KubbTokens.space1),
            Text(message, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

/// File-private flag separating "save" from "save + start KO" so the
/// post-action navigation only fires after the latter — keeps the
/// controller's state schema aligned with the spec exactly.
bool _startRequested = false;
