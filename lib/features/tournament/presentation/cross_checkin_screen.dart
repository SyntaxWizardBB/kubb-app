import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_detail_screen.dart'
    show ParticipantCheckinToggle;
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Cross-tournament check-in search (spec §7 / §9.6). One screen for the
/// helper at the gate: search a team or player by name, see which tournament
/// they registered for, and check them in — across every tournament the
/// organizer runs at once.
///
/// The hit scope (caller-administered, public, check-in phase) is enforced by
/// the `tournament_search_checkin_targets` RPC, so this screen does no
/// client-side filtering. Checking a hit in goes through the existing
/// `tournament_checkin_participant` RPC ([TournamentActions.checkinTarget]).
class CrossCheckinScreen extends ConsumerStatefulWidget {
  const CrossCheckinScreen({super.key});

  @override
  ConsumerState<CrossCheckinScreen> createState() => _CrossCheckinScreenState();
}

class _CrossCheckinScreenState extends ConsumerState<CrossCheckinScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: l.crossCheckinEyebrow,
        title: l.crossCheckinTitle,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(KubbTokens.space4),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.crossCheckinSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: _query.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(KubbTokens.space5),
                      child: KubbEmptyState(
                        title: l.crossCheckinTitle,
                        body: l.crossCheckinPrompt,
                      ),
                    ),
                  )
                : _Results(query: _query),
          ),
        ],
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final hitsAsync = ref.watch(checkinSearchProvider(query));

    return hitsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Text(
            l.crossCheckinError,
            textAlign: TextAlign.center,
            style: const TextStyle(color: KubbTokens.miss),
          ),
        ),
      ),
      data: (hits) {
        if (hits.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(KubbTokens.space5),
              child: Text(
                l.crossCheckinNoResults,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: tokens.fgMuted),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
          itemCount: hits.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: KubbTokens.space2),
          itemBuilder: (_, i) => _HitRow(hit: hits[i]),
        );
      },
    );
  }
}

class _HitRow extends ConsumerWidget {
  const _HitRow({required this.hit});

  final CheckinSearchHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space3,
        vertical: KubbTokens.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hit.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg,
                  ),
                ),
                Text(
                  hit.tournamentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                ),
              ],
            ),
          ),
          ParticipantCheckinToggle(
            isCheckedIn: hit.isCheckedIn,
            onCheckin: () => _checkin(ref),
            // Cross-checkin is a one-way action: an already-present hit just
            // renders the green "Anwesend" state. Undo stays on the per-
            // tournament cockpit detail, not in the gate search.
            onUndoCheckin: () {},
          ),
        ],
      ),
    );
  }

  void _checkin(WidgetRef ref) {
    unawaited(
      ref.read(tournamentActionsProvider).checkinTarget(hit).then(
        (_) {
          // Re-run the search so the row flips to the checked-in state.
          ref.invalidate(checkinSearchProvider);
        },
        onError: (Object _) {},
      ),
    );
  }
}

/// Hits for one cross-checkin `query` from the server-scoped
/// `tournament_search_checkin_targets` RPC. Family-keyed on the query so each
/// keystroke's result is cached and disposed independently.
// ignore: specify_nonobvious_property_types
final checkinSearchProvider =
    FutureProvider.family<List<CheckinSearchHit>, String>((ref, query) {
  return ref.read(tournamentActionsProvider).searchCheckinTargets(query);
});
