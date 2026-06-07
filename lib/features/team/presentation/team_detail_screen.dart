import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/avatar_circle.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/settings/presentation/confirm_dialog.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_membership_controller.dart';
import 'package:kubb_app/features/team/application/team_providers.dart';
import 'package:kubb_app/features/team/presentation/team_add_player_screen.dart';
import 'package:kubb_app/features/team/presentation/widgets/team_member_card.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Single-team overview: header (logo, name, league), pool list with
/// [TeamMemberCard] rows for members and guests, plus the membership
/// actions. Reads the jsonb payload of `team_get` via
/// `teamDetailProvider` (T10) and dispatches mutations through
/// `teamMembershipControllerProvider`.
class TeamDetailScreen extends ConsumerWidget {
  const TeamDetailScreen({required this.teamId, super.key});
  final TeamId teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    // Keep the team detail fresh across devices: a CDC subscription while this
    // screen is mounted invalidates the detail when another member changes the
    // membership server-side (ADR-0029 §(e) C3-T2).
    ref.watch(teamDetailCdcProvider(teamId));
    final detailAsync = ref.watch(teamDetailProvider(teamId));
    final myUserId = ref.watch(currentUserIdProvider);
    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: KubbAppBar(
        eyebrow: 'Team',
        title: detailAsync.maybeWhen(
          data: (d) => (d['display_name'] as String?) ?? 'Team',
          orElse: () => 'Team',
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Padding(
                padding: const EdgeInsets.all(KubbTokens.space5),
                child: Text('$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: KubbTokens.miss)))),
        data: (data) => _Body(data: data, myUserId: myUserId, teamId: teamId),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(
      {required this.data, required this.myUserId, required this.teamId});
  final Map<String, dynamic> data;
  final String? myUserId;
  final TeamId teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final name = (data['display_name'] as String?) ?? '';
    final league = (data['league_membership'] as String?) ?? '';
    final logoUrl = data['logo_url'] as String?;
    final pool = (data['pool'] as List? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final guests = (data['guests'] as List? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    final dissolved = data['dissolved_at'] != null;
    final isMember =
        myUserId != null && pool.any((m) => m['user_id'] == myUserId);
    // Caller's own role in this pool. Guests see no admin options — only that
    // they belong and a "Verlassen" action. Default to admin for any
    // non-guest membership (role column defaults to 'admin').
    String? myRole;
    if (myUserId != null) {
      for (final m in pool) {
        if (m['user_id'] == myUserId) {
          myRole = m['role'] as String?;
          break;
        }
      }
    }
    final isAdmin = isMember && myRole != 'guest';
    final ctrl = ref.read(teamMembershipControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(KubbTokens.space4, KubbTokens.space2,
          KubbTokens.space4, KubbTokens.space12),
      children: [
        _Header(name: name, league: league, logoUrl: logoUrl),
        const SizedBox(height: KubbTokens.space5),
        Text('POOL',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.88,
                color: tokens.fgMuted)),
        const SizedBox(height: KubbTokens.space2),
        if (pool.isEmpty && guests.isEmpty)
          Text('Noch leer.',
              style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
        for (final m in pool) ...[
          TeamMemberCard(
            displayName: (m['display_name'] as String?) ??
                (m['user_id'] as String?) ??
                '?',
            roleLabel:
                (m['role'] as String?) == 'guest' ? 'Gast' : 'Admin',
            onTap: !isAdmin || dissolved
                ? null
                : () => _memberActions(
                      context,
                      ctrl,
                      teamId,
                      userId: UserId(m['user_id'] as String),
                      displayName: (m['display_name'] as String?) ?? 'Spieler',
                      role: (m['role'] as String?) ?? 'admin',
                    ),
          ),
          const SizedBox(height: KubbTokens.space2),
        ],
        for (final g in guests) ...[
          TeamMemberCard(
            displayName: (g['display_name'] as String?) ?? '?',
            roleLabel: 'Gast',
            onTap: !isAdmin || dissolved
                ? null
                : () => _confirmRemove(context, 'Gast entfernen',
                    () => ctrl.removeGuest(
                        teamId, TeamGuestPlayerId(g['guest_id'] as String))),
          ),
          const SizedBox(height: KubbTokens.space2),
        ],
        if (isMember && !dissolved) ...[
          const SizedBox(height: KubbTokens.space5),
          _Actions(teamId: teamId, ctrl: ctrl, isAdmin: isAdmin),
        ],
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context, String title,
      Future<void> Function() op) async {
    final ok = await showDangerConfirm(
        context: context,
        title: title,
        body: 'Dieser Eintrag wird aus dem Pool entfernt.');
    if (!ok || !context.mounted) return;
    await _safe(context, op);
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.name, required this.league, required this.logoUrl});
  final String name;
  final String league;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initials =
        name.isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    final fallback =
        AvatarCircle(initials: initials, color: tokens.primary, size: 56);
    return Row(children: [
      if (logoUrl != null && logoUrl!.isNotEmpty)
        ClipOval(
            child: Image.network(logoUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback))
      else
        fallback,
      const SizedBox(width: KubbTokens.space3),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: tokens.fg)),
        Text('Liga $league',
            style: TextStyle(fontSize: 13, color: tokens.fgMuted)),
      ])),
    ]);
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.teamId,
    required this.ctrl,
    required this.isAdmin,
  });
  final TeamId teamId;
  final TeamMembershipController ctrl;

  /// Admins see the full management surface; guests only get "Verlassen".
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, VoidCallback onTap, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: KubbTokens.space2),
        child: SizedBox(
            height: KubbTokens.touchComfortable,
            child: FilledButton(
                style: color == null
                    ? null
                    : FilledButton.styleFrom(backgroundColor: color),
                onPressed: onTap,
                child: Text(label))));

    final leaveBtn = btn(
        'Verlassen',
        () => _confirm(
            context,
            'Team verlassen',
            'Du verlässt den Pool. Diese Aktion ist endgültig.',
            () async {
              await ctrl.leave(teamId);
              if (!context.mounted) return;
              context.go('/teams');
            }),
        color: KubbTokens.miss);

    // Guests: nothing to administer — only leave.
    if (!isAdmin) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [leaveBtn],
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      btn(
          'Team bearbeiten',
          () => unawaited(context.push('/teams/${teamId.value}/edit'))),
      btn(
          'Mitglied einladen',
          () => unawaited(context.push('/teams/${teamId.value}/add',
              extra: TeamAddRole.member))),
      btn(
          'Gast hinzufügen',
          () => unawaited(context.push('/teams/${teamId.value}/add',
              extra: TeamAddRole.guest))),
      leaveBtn,
      btn(
          'Auflösen',
          () => _confirm(
              context,
              'Team auflösen',
              'Das Team wird aufgelöst. Alle Mitglieder verlieren den Zugriff.',
              () => ctrl.dissolve(teamId)),
          color: KubbTokens.miss),
    ]);
  }
}

/// Member action sheet: toggle the admin/guest role or remove the member.
/// Admins manage the team and can register it for tournaments; guests can
/// only be selected into a roster.
Future<void> _memberActions(
  BuildContext context,
  TeamMembershipController ctrl,
  TeamId teamId, {
  required UserId userId,
  required String displayName,
  required String role,
}) async {
  final isGuest = role == 'guest';
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(displayName,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(isGuest ? 'Rolle: Gast' : 'Rolle: Admin'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(isGuest ? 'Zu Admin machen' : 'Zu Gast machen'),
            subtitle: Text(isGuest
                ? 'Darf das Team verwalten und an Turniere anmelden'
                : 'Kann nur ausgewählt werden — nicht verwalten/anmelden'),
            onTap: () => Navigator.of(ctx).pop('role'),
          ),
          ListTile(
            leading: const Icon(Icons.person_remove, color: KubbTokens.miss),
            title: const Text('Aus Team entfernen'),
            onTap: () => Navigator.of(ctx).pop('remove'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'role') {
    await _safe(
      context,
      () => ctrl.setMemberRole(teamId, userId, isGuest ? 'admin' : 'guest'),
    );
  } else if (action == 'remove') {
    final ok = await showDangerConfirm(
        context: context,
        title: 'Mitglied entfernen',
        body: 'Dieser Spieler wird aus dem Pool entfernt.');
    if (!ok || !context.mounted) return;
    await _safe(context, () => ctrl.removeMember(teamId, userId));
  }
}

Future<void> _confirm(BuildContext context, String title, String body,
    Future<void> Function() op) async {
  final ok = await showDangerConfirm(context: context, title: title, body: body);
  if (!ok || !context.mounted) return;
  await _safe(context, op);
}

Future<void> _safe(BuildContext context, Future<void> Function() op) async {
  try {
    await op();
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: KubbTokens.miss));
  }
}
