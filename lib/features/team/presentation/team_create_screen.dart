import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/features/team/application/team_membership_controller.dart';
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
  final _logoController = TextEditingController();
  final _countryController = TextEditingController();
  LeagueMembership _league = LeagueMembership.b;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _logoController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _nameController.text.trim().isNotEmpty && !_busy;

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result =
          await ref.read(teamMembershipControllerProvider.notifier).create(
                displayName: _nameController.text.trim(),
                leagueMembership: _league,
                logoUrl: _logoController.text.trim().isEmpty
                    ? null
                    : _logoController.text.trim(),
                country: _countryController.text.trim().isEmpty
                    ? null
                    : _countryController.text.trim(),
              );
      if (!mounted) return;
      switch (result) {
        case TeamActionSuccess<TeamId>(:final value):
          context.go('/teams/${value.value}');
        case TeamActionFailure<TeamId>():
          messenger.showSnackBar(SnackBar(
            content: Text(l.teamCreateErrorGeneric),
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
      appBar: KubbAppBar(
        eyebrow: l.teamListTitle,
        title: l.teamCreateTitle,
      ),
      body: Padding(
        padding: const EdgeInsets.all(KubbTokens.space4),
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
              decoration: InputDecoration(labelText: l.teamCreateLeagueLabel),
              items: const [
                DropdownMenuItem(value: LeagueMembership.a, child: Text('A')),
                DropdownMenuItem(value: LeagueMembership.b, child: Text('B')),
                DropdownMenuItem(value: LeagueMembership.c, child: Text('C')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _league = v);
              },
            ),
            const SizedBox(height: KubbTokens.space3),
            TextField(
              controller: _logoController,
              decoration: InputDecoration(labelText: l.teamCreateLogoUrlLabel),
              keyboardType: TextInputType.url,
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
            const Spacer(),
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
