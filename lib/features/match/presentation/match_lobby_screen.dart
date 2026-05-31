import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/core/ui/widgets/kubb_status_chip.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_routes.dart';
import 'package:kubb_app/features/match/presentation/widgets/match_stage_indicator.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Pre-game lobby. Shows the team rosters and the invitation status of
/// each in-app participant. Auto-redirects to the active screen once
/// every invite has been accepted (status flips to `active`).
///
/// Polling is kept alive by reading [matchPollingProvider] for its side
/// effect — its value isn't otherwise consumed here.
///
/// Sprint B / W5-T2: aligned with the mobile-kit `MatchScreen.jsx`
/// lobby tab. Uses [KubbAppBar] (eyebrow `Match · Lobby`), the inset-card
/// pattern with eyebrow section-headers for the "Mitspieler" block, and
/// [KubbButton] primary / ghost variants for the action row.
///
/// W5.1 / BH-B-01: the accept/cancel buttons set `_busy` while their RPC
/// is in flight so a rapid double-tap can't fire the mutation twice.
class MatchLobbyScreen extends ConsumerStatefulWidget {
  const MatchLobbyScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<MatchLobbyScreen> createState() => _MatchLobbyScreenState();
}

class _MatchLobbyScreenState extends ConsumerState<MatchLobbyScreen> {
  /// In-flight guard for accept / cancel. Set before the RPC fires and
  /// cleared in `finally`; the action handlers bail out when already
  /// busy so a double-tap is a no-op.
  bool _busy = false;

  String get matchId => widget.matchId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    ref.watch(matchPollingProvider(matchId));
    final detailAsync = ref.watch(matchDetailProvider(matchId));
    final myUserId = ref.watch(currentUserIdProvider);

    // Status-driven navigation. Listen so we don't redirect during build.
    // The "active" status is treated as "all invites accepted, time to
    // enter the result" — we route straight to the result screen and
    // skip the no-op active intermediate that used to sit between
    // them. Server-side `match_propose_result` auto-transitions
    // active → awaiting_results on first proposal.
    //
    // Only react to actual status transitions — polling invalidates the
    // provider every second, so listening to every emission would loop
    // `context.go` forever once the match goes active.
    ref.listen<AsyncValue<MatchDetail?>>(
      matchDetailProvider(matchId),
      (prev, next) {
        final prevStatus = prev?.value?.match.status;
        final nextStatus = next.value?.match.status;
        if (nextStatus == null || nextStatus == prevStatus) return;
        if (nextStatus == MatchStatus.active ||
            nextStatus == MatchStatus.awaitingResults) {
          context.go('${MatchRoutes.result}/$matchId');
        } else if (nextStatus == MatchStatus.finalized ||
            nextStatus == MatchStatus.voided) {
          context.go('${MatchRoutes.finished}/$matchId');
        }
      },
    );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: 'Match · Lobby',
        title: 'Lobby',
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          color: tokens.fg,
          iconSize: 24,
          splashRadius: 24,
          constraints: const BoxConstraints.tightFor(
            width: KubbTokens.touchMin,
            height: KubbTokens.touchMin,
          ),
          onPressed: () => context.go('/training'),
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text(
              'Match konnte nicht geladen werden:\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: KubbTokens.miss),
            ),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // W5.1-A: stage indicator directly below the AppBar.
          return Column(
            children: [
              MatchStageIndicator(status: detail.match.status),
              Expanded(
                child: _LobbyBody(
                  detail: detail,
                  myUserId: myUserId,
                  busy: _busy,
                  onCancel: _busy ? null : _runCancel,
                  onAccept: _busy ? null : _runAccept,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runCancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(matchActionsProvider).cancelMatch(matchId);
      if (!mounted) return;
      context.go('/training');
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Abbrechen fehlgeschlagen: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAccept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(matchActionsProvider).acceptInvite(matchId);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Annehmen fehlgeschlagen: $e'),
          backgroundColor: KubbTokens.miss,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _LobbyBody extends StatelessWidget {
  const _LobbyBody({
    required this.detail,
    required this.myUserId,
    required this.busy,
    required this.onCancel,
    required this.onAccept,
  });

  final MatchDetail detail;
  final String? myUserId;

  /// True while an accept/cancel RPC is in flight. Used to disable both
  /// CTAs so a double-tap can't enqueue two requests.
  final bool busy;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    // Server tags the creator on `match_get`; the cancel RPC enforces
    // the same rule. The button is a UX hint, not a security boundary.
    final canCancel = detail.isCallerCreator(myUserId) &&
        detail.match.status == MatchStatus.pendingInvites;

    // The "Bereit" CTA only makes sense while the caller still has a
    // pending invitation row of their own. Once accepted, the lobby is
    // a watch-state until the server flips the match to `active`.
    MatchParticipant? myParticipant;
    if (myUserId != null) {
      for (final p in detail.participants) {
        if (p.userId == myUserId) {
          myParticipant = p;
          break;
        }
      }
    }
    final canAccept = myParticipant != null &&
        myParticipant.invitationStatus == MatchInvitationStatus.pending &&
        detail.match.status == MatchStatus.pendingInvites;

    final teamA = detail.participants.where((p) => p.teamId == 'A').toList();
    final teamB = detail.participants.where((p) => p.teamId == 'B').toList();

    final teamADisplay = _teamDisplayName(detail, 'A', teamA);
    final teamBDisplay = _teamDisplayName(detail, 'B', teamB);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KubbTokens.space4,
        KubbTokens.space2,
        KubbTokens.space4,
        KubbTokens.space6,
      ),
      children: [
        Row(
          children: [
            _MetaChip(text: _formatLabel(detail.match.format)),
            const Spacer(),
            // W3-T4: central status mapping — distinguishes live (hit),
            // awaiting (heli) and finalized (info) tones instead of the
            // old meadow-everything pill.
            KubbStatusChip.match(status: detail.match.status, l: l),
          ],
        ),
        const SizedBox(height: KubbTokens.space4),
        // Sprint B / W5.1-B (BH-C-02): three new sections from the mobile
        // kit Lobby tab (`MatchScreen.jsx` L48-87): Hero with side-vs-side
        // panels, H2H history, match setup summary. The existing
        // "Mitspieler" roster stays underneath as it is the canonical
        // invitation-status view.
        _LobbyHero(
          detail: detail,
          teamAName: teamADisplay,
          teamBName: teamBDisplay,
          myUserId: myUserId,
        ),
        const SizedBox(height: KubbTokens.space5),
        const _SectionHeader(text: 'Direkter Vergleich'),
        const SizedBox(height: KubbTokens.space2),
        _H2HList(
          teamAName: teamADisplay,
          teamBName: teamBDisplay,
          // Backend H2H aggregate isn't wired yet — render the empty
          // state per task spec (W5-T1 match-live-screen-spec.md L192).
          entries: const <_H2HEntry>[],
        ),
        const SizedBox(height: KubbTokens.space5),
        const _SectionHeader(text: 'Match-Setup'),
        const SizedBox(height: KubbTokens.space2),
        _MatchSetup(detail: detail),
        const SizedBox(height: KubbTokens.space5),
        // Section header in the eyebrow style (`docs/design/quality-gates/
        // mobile-kit-overview.md` §Section-Header). Matches the section
        // labels used inside MatchScreen.jsx → Lobby ("Direkter Vergleich",
        // "Match-Setup").
        const _SectionHeader(text: 'Mitspieler'),
        const SizedBox(height: KubbTokens.space2),
        // Inset card pattern: bgRaised surface, 14dp radius, single-px
        // line border to mirror the mobile-kit `h2hList` / `setupList`
        // surfaces.
        _InsetCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TeamPanel(
                  title: 'Team A',
                  accent: KubbTokens.meadow600,
                  participants: teamA,
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(
                  vertical: KubbTokens.space2,
                ),
                color: tokens.line,
              ),
              Expanded(
                child: _TeamPanel(
                  title: 'Team B',
                  accent: KubbTokens.wood400,
                  participants: teamB,
                ),
              ),
            ],
          ),
        ),
        if (detail.match.status == MatchStatus.pendingInvites) ...[
          const SizedBox(height: KubbTokens.space4),
          Container(
            padding: const EdgeInsets.all(KubbTokens.space3),
            decoration: BoxDecoration(
              color: tokens.bgSunken,
              borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.clock, size: 16),
                const SizedBox(width: KubbTokens.space2),
                Expanded(
                  child: Text(
                    'Warten auf Annahme aller Einladungen…',
                    style: TextStyle(fontSize: 13, color: tokens.fgMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (canAccept || canCancel) ...[
          const SizedBox(height: KubbTokens.space5),
          if (canAccept)
            KubbButton(
              variant: KubbButtonVariant.primary,
              // Disabled while a request is in flight so the user can't
              // submit twice (BH-B-01).
              onPressed: busy ? null : onAccept,
              isLoading: busy,
              child: const Text('Bereit'),
            ),
          if (canAccept && canCancel)
            const SizedBox(height: KubbTokens.space2),
          if (canCancel)
            KubbButton(
              variant: KubbButtonVariant.ghost,
              onPressed: busy ? null : onCancel,
              child: const Text('Match abbrechen'),
            ),
        ],
      ],
    );
  }

  String _formatLabel(MatchFormat f) => 'BO${f.n}';

  /// Resolve a display name for a team: prefer the team row's
  /// `displayName`, otherwise concatenate the participants' nicknames,
  /// otherwise fall back to `Team A` / `Team B`.
  String _teamDisplayName(
    MatchDetail detail,
    String teamId,
    List<MatchParticipant> roster,
  ) {
    for (final t in detail.teams) {
      if (t.teamId == teamId && t.displayName != null &&
          t.displayName!.isNotEmpty) {
        return t.displayName!;
      }
    }
    final names = <String>[
      for (final p in roster)
        if (p.nickname != null && p.nickname!.isNotEmpty) p.nickname!,
    ];
    if (names.isEmpty) return 'Team $teamId';
    return names.join(' & ');
  }
}

/// Inset card surface (`bgRaised` + hairline border, 14dp radius) —
/// canonical pattern from `docs/design/quality-gates/mobile-kit-overview.md`
/// §Inset-Card.
class _InsetCard extends StatelessWidget {
  const _InsetCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.line),
      ),
      padding: const EdgeInsets.all(KubbTokens.space3),
      child: child,
    );
  }
}

/// Eyebrow-style section header — see `docs/design/quality-gates/
/// mobile-kit-overview.md` §Section-Header.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.88,
          color: tokens.fgMuted,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KubbTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.bgSunken,
        borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tokens.fg,
        ),
      ),
    );
  }
}

class _TeamPanel extends StatelessWidget {
  const _TeamPanel({
    required this.title,
    required this.accent,
    required this.participants,
  });

  final String title;
  final Color accent;
  final List<MatchParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 14, color: accent),
              const SizedBox(width: KubbTokens.space2),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: KubbTokens.space2),
          for (final p in participants) ...[
            _ParticipantRow(participant: p),
            const SizedBox(height: KubbTokens.space2),
          ],
          if (participants.isEmpty)
            Text(
              '–',
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});
  final MatchParticipant participant;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final name = _displayName(participant);
    final (icon, color) = _statusIcon(participant);

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: KubbTokens.space2),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tokens.fg,
            ),
          ),
        ),
      ],
    );
  }

  String _displayName(MatchParticipant p) => p.nickname ?? '…';

  (IconData, Color) _statusIcon(MatchParticipant p) {
    switch (p.invitationStatus) {
      case MatchInvitationStatus.accepted:
        return (LucideIcons.check, KubbTokens.meadow600);
      case MatchInvitationStatus.pending:
        return (LucideIcons.clock, KubbTokens.wood400);
      case MatchInvitationStatus.declined:
        return (LucideIcons.x, KubbTokens.miss);
      case MatchInvitationStatus.left:
        return (LucideIcons.userMinus, KubbTokens.miss);
    }
  }
}

// =====================================================================
// Sprint B / W5.1-B (BH-C-02): three Lobby sections from `MatchScreen.jsx`
// L48-87. Hero (side-vs-VS-vs-side) → H2H history → match setup summary.
// All values are mockup-friendly placeholders until the corresponding
// backend fields (ELO, recent-form, H2H aggregate, court name) land.
// =====================================================================

/// Side-vs-VS-Col-vs-Side hero block. Mirrors `m.lobbyHero` in the kit:
/// two `Side`-panels (avatar 48dp + name + ELO + 4-pill W/L form-row)
/// flanking a center column with a "vs." display, kickoff time and
/// court meta-line.
class _LobbyHero extends StatelessWidget {
  const _LobbyHero({
    required this.detail,
    required this.teamAName,
    required this.teamBName,
    required this.myUserId,
  });

  final MatchDetail detail;
  final String teamAName;
  final String teamBName;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final teamA = detail.participants.where((p) => p.teamId == 'A').toList();
    final teamB = detail.participants.where((p) => p.teamId == 'B').toList();
    final iAmInA = myUserId != null &&
        teamA.any((p) => p.userId == myUserId);
    final kickoff = _formatTime(detail.match.startedAt);

    return _InsetCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _HeroSide(
              initials: _initials(teamAName),
              name: teamAName,
              elo: _eloFor(teamA),
              form: const <String>['W', 'W', 'L', 'W'],
              isMe: iAmInA,
            ),
          ),
          SizedBox(
            width: 88,
            child: Column(
              children: [
                Text(
                  'vs.',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: tokens.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kickoff,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.fgMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _courtLabel(detail),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.fgSubtle,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _HeroSide(
              initials: _initials(teamBName),
              name: teamBName,
              elo: _eloFor(teamB),
              form: const <String>['W', 'L', 'W', 'W'],
              isMe: !iAmInA && myUserId != null &&
                  teamB.any((p) => p.userId == myUserId),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name
        .split(RegExp(r'[\s&]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return name.substring(0, 1).toUpperCase();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _courtLabel(MatchDetail detail) {
    final raw = detail.match.settings['court'];
    if (raw is String && raw.isNotEmpty) return raw;
    // Mock placeholder per spec L191 (data "—" until match-domain
    // exposes the field).
    return 'Court —';
  }

  /// ELO is not yet on `MatchParticipant`; return a mock for now so the
  /// design stays truthful instead of showing 0. Spec L191 explicitly
  /// allows mockup data here.
  int? _eloFor(List<MatchParticipant> roster) => roster.isEmpty ? null : 1200;
}

class _HeroSide extends StatelessWidget {
  const _HeroSide({
    required this.initials,
    required this.name,
    required this.elo,
    required this.form,
    required this.isMe,
  });

  final String initials;
  final String name;
  final int? elo;
  final List<String> form;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final accent = isMe ? KubbTokens.meadow600 : KubbTokens.stone900;
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: const TextStyle(
              color: KubbTokens.chalk0,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: tokens.fg,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          elo == null ? '— ELO' : '$elo ELO',
          style: TextStyle(
            fontSize: 11,
            color: tokens.fgMuted,
          ),
        ),
        const SizedBox(height: KubbTokens.space2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in form) ...[
              _FormPill(label: f),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ],
    );
  }
}

class _FormPill extends StatelessWidget {
  const _FormPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final isWin = label == 'W';
    final bg = isWin ? KubbTokens.meadow500 : KubbTokens.stone200;
    final fg = isWin ? KubbTokens.chalk0 : KubbTokens.stone500;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// Head-to-head history list. When [entries] is empty, the section
/// renders a compact empty state (no vignette) per spec L192.
class _H2HList extends StatelessWidget {
  const _H2HList({
    required this.teamAName,
    required this.teamBName,
    required this.entries,
  });

  final String teamAName;
  final String teamBName;
  final List<_H2HEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _InsetCard(
        child: KubbEmptyState(
          vignette: SizedBox.shrink(),
          title: 'Noch keine direkten Vergleiche',
          body: 'Sobald ihr ein Match gespielt habt, erscheint hier '
              'die Bilanz.',
        ),
      );
    }
    return _InsetCard(
      child: Column(
        children: [
          for (var i = 0; i < entries.length && i < 3; i++)
            _H2HRow(
              entry: entries[i],
              teamAName: teamAName,
              teamBName: teamBName,
              showDivider: i < entries.length - 1 && i < 2,
            ),
        ],
      ),
    );
  }
}

class _H2HEntry {
  const _H2HEntry({
    required this.date,
    required this.score,
    required this.won,
  });
  final String date;
  final String score;
  final bool won;
}

class _H2HRow extends StatelessWidget {
  const _H2HRow({
    required this.entry,
    required this.teamAName,
    required this.teamBName,
    required this.showDivider,
  });

  final _H2HEntry entry;
  final String teamAName;
  final String teamBName;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final tagBg = entry.won ? KubbTokens.meadow100 : KubbTokens.stone100;
    final tagFg = entry.won ? KubbTokens.meadow700 : tokens.fgMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  entry.date,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tokens.fgMuted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '$teamAName vs. $teamBName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.fg,
                  ),
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
              Text(
                entry.score,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: tokens.fg,
                ),
              ),
              const SizedBox(width: KubbTokens.space2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KubbTokens.space2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: tagBg,
                  borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
                ),
                child: Text(
                  entry.won ? 'Sieg' : 'N',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: tagFg,
                  ),
                ),
              ),
            ],
          ),
          if (showDivider)
            Padding(
              padding: const EdgeInsets.only(top: KubbTokens.space2),
              child: Divider(height: 1, color: tokens.line),
            ),
        ],
      ),
    );
  }
}

/// Match-Setup summary card. Each row is `label` (muted, left) → `value`
/// (fg, right). The `tone="ok"` row uses meadow-700 to mirror the kit.
class _MatchSetup extends StatelessWidget {
  const _MatchSetup({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final s = detail.match.settings;
    final heli = s['heli_tracking'] == true || s['heli'] == true;
    final penalty = s['penalty_variant'] as String? ?? 'schwedisch';
    final court = s['court'] as String? ?? 'Court —';
    final format = 'Best of ${detail.match.format.n} · 6 Stöcke';
    return _InsetCard(
      child: Column(
        children: [
          _SetupRow(label: 'Format', value: format),
          _SetupRow(
            label: 'Heli-Tracking',
            value: heli ? 'ja' : 'nein',
            okTone: heli,
          ),
          _SetupRow(label: 'Strafkubb', value: penalty),
          _SetupRow(label: 'Court', value: court, isLast: true),
        ],
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.label,
    required this.value,
    this.okTone = false,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool okTone;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: KubbTokens.space2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.fgMuted,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: okTone ? KubbTokens.meadow700 : tokens.fg,
                ),
              ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: tokens.line),
      ],
    );
  }
}
