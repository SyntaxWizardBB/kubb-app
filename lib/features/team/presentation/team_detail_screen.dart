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
    final detailAsync = ref.watch(teamDetailProvider(teamId));
    final myUserId = ref.watch(currentUserIdProvider);
    return Scaffold(
      backgroundColor: tokens.bg,
      // TODO(sprintB-followup): migrate to KubbAppBar
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
            displayName: (m['user_id'] as String?) ?? '?',
            roleLabel: 'Mitglied',
            onTap: !isMember || dissolved
                ? null
                : () => _confirmRemove(context, 'Mitglied entfernen',
                    () => ctrl.removeMember(
                        teamId, UserId(m['user_id'] as String))),
          ),
          const SizedBox(height: KubbTokens.space2),
        ],
        for (final g in guests) ...[
          TeamMemberCard(
            displayName: (g['display_name'] as String?) ?? '?',
            roleLabel: 'Gast',
            onTap: !isMember || dissolved
                ? null
                : () => _confirmRemove(context, 'Gast entfernen',
                    () => ctrl.removeGuest(
                        teamId, TeamGuestPlayerId(g['guest_id'] as String))),
          ),
          const SizedBox(height: KubbTokens.space2),
        ],
        if (isMember && !dissolved) ...[
          const SizedBox(height: KubbTokens.space5),
          _Actions(teamId: teamId, ctrl: ctrl),
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
  const _Actions({required this.teamId, required this.ctrl});
  final TeamId teamId;
  final TeamMembershipController ctrl;

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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      btn(
          'Mitglied einladen',
          () => _prompt(context, 'Mitglied einladen', 'User-ID (UUID)',
              (v) => ctrl.invite(teamId, UserId(v)))),
      btn(
          'Gast hinzufügen',
          () => _prompt(context, 'Gast hinzufügen', 'Anzeigename',
              (v) => ctrl.addGuest(teamId, v))),
      btn(
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
          color: KubbTokens.miss),
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

Future<void> _prompt(BuildContext context, String title, String hint,
    Future<void> Function(String) op) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim())),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
  controller.dispose();
  if (value == null || value.isEmpty || !context.mounted) return;
  await _safe(context, () => op(value));
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
