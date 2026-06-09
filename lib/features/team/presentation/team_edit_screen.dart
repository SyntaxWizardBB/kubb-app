import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/name_availability_hint.dart';
import 'package:kubb_app/features/team/application/team_detail_provider.dart';
import 'package:kubb_app/features/team/application/team_membership_controller.dart';
import 'package:kubb_app/features/team/application/team_name_availability_provider.dart';
import 'package:kubb_app/features/team/application/team_providers.dart';
import 'package:kubb_app/features/team/data/team_repository.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Edit a team's name/country and — inside the Oct–Feb transfer window — its
/// league. The window is decided by the SERVER clock (`team_league_window_open`)
/// so faking the device time does nothing; the league control is simply
/// disabled when the window is closed, and the server rejects out-of-window
/// changes anyway (`LEAGUE_LOCKED`).
class TeamEditScreen extends ConsumerStatefulWidget {
  const TeamEditScreen({required this.teamId, super.key});
  final TeamId teamId;

  @override
  ConsumerState<TeamEditScreen> createState() => _TeamEditScreenState();
}

class _TeamEditScreenState extends ConsumerState<TeamEditScreen> {
  final _nameCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  LeagueMembership? _league;
  LeagueMembership? _initialLeague;
  bool _seeded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Rebuild on name edits so the live availability check + submit gate track
    // the field (BUG-2).
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl
      ..removeListener(_onNameChanged)
      ..dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  void _seed(Map<String, dynamic> data) {
    if (_seeded) return;
    _nameCtrl.text = (data['display_name'] as String?) ?? '';
    _countryCtrl.text = (data['country'] as String?) ?? '';
    final wire = data['league_membership'] as String?;
    if (wire != null) {
      _initialLeague = LeagueMembership.fromWire(wire);
      _league = _initialLeague;
    }
    _seeded = true;
  }

  Future<void> _save(bool windowOpen) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final ctrl = ref.read(teamMembershipControllerProvider.notifier);
      // Name / country first.
      final upd = await ctrl.updateTeam(
        widget.teamId,
        displayName: _nameCtrl.text.trim(),
        country: _countryCtrl.text.trim().isEmpty
            ? null
            : _countryCtrl.text.trim().toUpperCase(),
      );
      if (!mounted) return;
      if (upd is TeamActionFailure<bool>) {
        final isDuplicate = upd.error is TeamActionExceptionError &&
            (upd.error as TeamActionExceptionError).error
                is TeamDuplicateNameException;
        messenger.showSnackBar(SnackBar(
            content: Text(isDuplicate
                ? AppLocalizations.of(context).teamNameTakenError
                : 'Speichern fehlgeschlagen.'),
            backgroundColor: KubbTokens.miss));
        return;
      }
      // League only when changed (and the window is open).
      if (_league != null && _league != _initialLeague) {
        final res = await ctrl.setLeague(widget.teamId, _league!);
        if (!mounted) return;
        if (res is TeamActionFailure<bool>) {
          messenger.showSnackBar(SnackBar(
              content: Text(windowOpen
                  ? 'Liga konnte nicht geändert werden.'
                  : 'Die Liga kann nur zwischen Oktober und Februar geändert werden.'),
              backgroundColor: KubbTokens.miss));
          return;
        }
      }
      messenger
          .showSnackBar(const SnackBar(content: Text('Team gespeichert')));
      context.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final detail = ref.watch(teamDetailProvider(widget.teamId));
    final windowOpen = ref.watch(leagueWindowOpenProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(eyebrow: 'Team', title: 'Team bearbeiten'),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(KubbTokens.space5),
            child: Text('$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: KubbTokens.miss)),
          ),
        ),
        data: (data) {
          _seed(data);
          return SingleChildScrollView(
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
                  controller: _nameCtrl,
                  maxLength: 60,
                  decoration: const InputDecoration(
                      labelText: 'Team-Name', counterText: ''),
                ),
                Builder(builder: (context) {
                  final avail = ref.watch(teamNameAvailabilityProvider(
                    TeamNameQuery(
                      _nameCtrl.text.trim(),
                      excludeTeamId: widget.teamId,
                    ),
                  ));
                  return NameAvailabilityHint(
                    isTaken: avail.maybeWhen(
                      data: (a) => a == NameAvailability.taken,
                      orElse: () => false,
                    ),
                    isChecking:
                        avail.isLoading && _nameCtrl.text.trim().isNotEmpty,
                    takenLabel: AppLocalizations.of(context).teamNameTakenError,
                    checkingLabel: AppLocalizations.of(context).nameCheckingHint,
                  );
                }),
                const SizedBox(height: KubbTokens.space3),
                DropdownButtonFormField<LeagueMembership>(
                  initialValue: _league,
                  decoration: InputDecoration(
                    labelText: 'Liga',
                    helperText: windowOpen
                        ? 'Änderbar bis Ende Februar.'
                        : 'Liga ist fixiert (nur Okt.–Feb. änderbar).',
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: LeagueMembership.a, child: Text('A')),
                    DropdownMenuItem(
                        value: LeagueMembership.b, child: Text('B')),
                    DropdownMenuItem(
                        value: LeagueMembership.c, child: Text('C')),
                  ],
                  onChanged: windowOpen
                      ? (v) => setState(() => _league = v)
                      : null,
                ),
                const SizedBox(height: KubbTokens.space3),
                TextField(
                  controller: _countryCtrl,
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      labelText: 'Land (2 Zeichen, optional)',
                      counterText: ''),
                ),
                const SizedBox(height: KubbTokens.space5),
                SizedBox(
                  height: KubbTokens.touchComfortable,
                  child: FilledButton(
                    onPressed: _busy ||
                            _nameCtrl.text.trim().isEmpty ||
                            ref
                                    .watch(teamNameAvailabilityProvider(
                                      TeamNameQuery(
                                        _nameCtrl.text.trim(),
                                        excludeTeamId: widget.teamId,
                                      ),
                                    ))
                                    .maybeWhen(
                                      data: (a) =>
                                          a == NameAvailability.taken,
                                      orElse: () => false,
                                    )
                        ? null
                        : () => _save(windowOpen),
                    child: const Text('Speichern'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
