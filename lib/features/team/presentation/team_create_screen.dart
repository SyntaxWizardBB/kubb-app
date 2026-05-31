import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/team/application/team_membership_controller.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Lightweight create form for new teams (M3.1-T12). Liga-Vorwahl ist
/// per ADR-0018 auf {A, B, C} beschränkt; Default B matcht das DB-CHECK
/// `league_membership IN ('A','B','C') DEFAULT 'B'`.
class TeamCreateScreen extends ConsumerStatefulWidget {
  const TeamCreateScreen({super.key});

  @override
  ConsumerState<TeamCreateScreen> createState() => _TeamCreateScreenState();
}

class _TeamCreateScreenState extends ConsumerState<TeamCreateScreen> {
  final _nameController = TextEditingController();
  final _countryController = TextEditingController();
  // League is mandatory now — no pre-selected default; the user must pick one.
  LeagueMembership? _league;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Guard with `mounted`: a trailing text/IME change can fire this listener
    // during teardown (e.g. cancelling via back while typing), and an
    // unguarded setState after dispose throws.
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty && _league != null && !_busy;

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result =
          await ref.read(teamMembershipControllerProvider.notifier).create(
                displayName: _nameController.text.trim(),
                leagueMembership: _league!,
                country: _countryController.text.trim().isEmpty
                    ? null
                    : _countryController.text.trim(),
              );
      if (!mounted) return;
      switch (result) {
        case TeamActionSuccess<TeamId>(:final value):
          // Replace the create form with the new team's detail so the back
          // stack stays home → /teams → /teams/:id and the user can return
          // to the main screen.
          context.pushReplacement('/teams/${value.value}');
        case TeamActionFailure<TeamId>(:final error):
          // A permission error (SQLSTATE 42501) means the RPC ran without a
          // valid session — almost always "not signed in" rather than a true
          // server failure. Surface that distinctly so the user knows to
          // re-authenticate instead of blindly retrying.
          final isAuth = error is TeamActionExceptionError &&
              error.error is TeamPermissionException;
          messenger.showSnackBar(SnackBar(
            content: Text(
              isAuth ? l.teamCreateErrorAuth : l.teamCreateErrorGeneric,
            ),
            backgroundColor: KubbTokens.miss,
          ));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      resizeToAvoidBottomInset: true,
      // TODO(sprintB-followup): add InboxBellAction
      appBar: KubbAppBar(
        eyebrow: l.teamListTitle,
        title: l.teamCreateTitle,
      ),
      // Mängel #2.4: Form muss in einen Scrollable und mit viewInsets.bottom
      // gepuffert werden, damit der Submit-Button beim Erscheinen der
      // Software-Tastatur nicht hinter dem Keyboard verschwindet.
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: KubbTokens.space4,
          right: KubbTokens.space4,
          top: KubbTokens.space4,
          bottom: MediaQuery.viewInsetsOf(context).bottom + KubbTokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: l.teamCreateNameLabel,
                counterText: '',
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
            DropdownButtonFormField<LeagueMembership>(
              initialValue: _league,
              decoration: InputDecoration(
                labelText: l.teamCreateLeagueLabel,
                hintText: 'Liga wählen',
              ),
              items: const [
                DropdownMenuItem(value: LeagueMembership.a, child: Text('A')),
                DropdownMenuItem(value: LeagueMembership.b, child: Text('B')),
                DropdownMenuItem(value: LeagueMembership.c, child: Text('C')),
              ],
              onChanged: (v) => setState(() => _league = v),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: KubbTokens.space2,
                left: KubbTokens.space2,
              ),
              child: Text(
                l.teamCreateLeagueHelper,
                style: TextStyle(fontSize: 12, color: tokens.fgMuted),
              ),
            ),
            const SizedBox(height: KubbTokens.space3),
            TextField(
              controller: _countryController,
              maxLength: 2,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l.teamCreateCountryLabel,
                counterText: '',
              ),
            ),
            const SizedBox(height: KubbTokens.space5),
            SizedBox(
              height: KubbTokens.touchComfortable,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                child: Text(
                  l.teamCreateSubmitButton,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
