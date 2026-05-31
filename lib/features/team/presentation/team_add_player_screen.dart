import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:kubb_app/features/team/application/team_membership_controller.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Whether the add flow invites a full member (admin role) or adds a
/// guest-role player directly.
enum TeamAddRole { member, guest }

/// Search-based "add player to team" screen. Players come from the same
/// directory search as the friends feature (`friendSearchProvider` →
/// `friend_search_by_username`) — no free-text names. Selecting a player
/// either sends a member invitation (admin role) or adds them directly as a
/// guest, depending on [role].
class TeamAddPlayerScreen extends ConsumerStatefulWidget {
  const TeamAddPlayerScreen({
    required this.teamId,
    required this.role,
    super.key,
  });

  final TeamId teamId;
  final TeamAddRole role;

  @override
  ConsumerState<TeamAddPlayerScreen> createState() =>
      _TeamAddPlayerScreenState();
}

class _TeamAddPlayerScreenState extends ConsumerState<TeamAddPlayerScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _query = '';
  Timer? _debounce;
  bool _busy = false;

  bool get _isGuest => widget.role == TeamAddRole.guest;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim().toLowerCase());
    });
  }

  Future<void> _select(FriendCandidate c) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = _isGuest
          ? await ref
              .read(teamMembershipControllerProvider.notifier)
              .addGuestMember(widget.teamId, UserId(c.userId))
          : await ref
              .read(teamMembershipControllerProvider.notifier)
              .invite(widget.teamId, UserId(c.userId));
      if (!mounted) return;
      switch (result) {
        case TeamActionSuccess<Object>():
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isGuest
                ? '${c.nickname} als Gast hinzugefügt'
                : 'Einladung an ${c.nickname} gesendet'),
          ));
          context.pop();
        case TeamActionFailure<Object>(:final error):
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_errorMessage(error)),
            backgroundColor: KubbTokens.miss,
          ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(TeamActionError e) {
    if (e is TeamActionExceptionError) {
      final inner = e.error;
      if (inner is TeamInvitationDuplicateException) {
        return 'Für diesen Spieler läuft bereits eine Einladung.';
      }
      if (inner is TeamOperationException) {
        switch (inner.code) {
          case 'ALREADY_MEMBER':
            return 'Spieler ist bereits im Team.';
          case 'INVALID_ROLE':
            return 'Ungültige Rolle.';
        }
      }
      if (inner is TeamPermissionException) {
        return 'Nur Admins dürfen Spieler hinzufügen.';
      }
    }
    return _isGuest ? 'Hinzufügen fehlgeschlagen.' : 'Einladung fehlgeschlagen.';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final results = ref.watch(friendSearchProvider(_query));

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: KubbAppBar(
        eyebrow: 'Team',
        title: _isGuest ? 'Gast hinzufügen' : 'Mitglied einladen',
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KubbTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: KubbTokens.space3),
            TextField(
              controller: _queryCtrl,
              autocorrect: false,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Spielername suchen…',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KubbTokens.radiusMd),
                  borderSide: BorderSide(color: tokens.lineStrong),
                ),
              ),
            ),
            const SizedBox(height: KubbTokens.space2),
            Text(
              _isGuest
                  ? 'Gäste können ausgewählt werden, aber das Team nicht verwalten oder anmelden.'
                  : 'Mitglieder erhalten Admin-Rechte und müssen die Einladung annehmen.',
              style: TextStyle(fontSize: 12, color: tokens.fgMuted),
            ),
            const SizedBox(height: KubbTokens.space3),
            Expanded(
              child: _query.length < 2
                  ? Center(
                      child: Text('Mindestens 2 Zeichen eingeben.',
                          style:
                              TextStyle(fontSize: 14, color: tokens.fgMuted)),
                    )
                  : results.when(
                      data: (list) {
                        if (list.isEmpty) {
                          return Center(
                            child: Text('Niemand gefunden für „$_query".',
                                style: TextStyle(
                                    fontSize: 14, color: tokens.fgMuted)),
                          );
                        }
                        return ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: KubbTokens.space2),
                          itemBuilder: (context, i) => _CandidateRow(
                            candidate: list[i],
                            actionLabel: _isGuest ? 'Als Gast' : 'Einladen',
                            enabled: !_busy,
                            onSelect: () => _select(list[i]),
                          ),
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Text('Fehler: $e',
                            style: const TextStyle(color: KubbTokens.miss)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.actionLabel,
    required this.enabled,
    required this.onSelect,
  });

  final FriendCandidate candidate;
  final String actionLabel;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final initial =
        candidate.nickname.isEmpty ? '?' : candidate.nickname[0].toUpperCase();
    return Container(
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
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: KubbTokens.space3),
          Expanded(
            child: Text(candidate.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: tokens.fg)),
          ),
          FilledButton(
            onPressed: enabled ? onSelect : null,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
