import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/core/ui/widgets/name_availability_hint.dart';
import 'package:kubb_app/features/club/application/club_membership_controller.dart';
import 'package:kubb_app/features/club/application/club_name_availability_provider.dart';
import 'package:kubb_app/features/club/data/club_repository.dart';
import 'package:kubb_app/features/club/presentation/club_routes.dart';
import 'package:kubb_app/features/team/application/team_name_availability_provider.dart'
    show NameAvailability;
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Club founding form. The capability to found clubs is granted at sign-up via
/// the early-access organizer code (P7) and checked server-side in
/// `club_create` — so this screen only asks for a name.
class ClubCreateScreen extends ConsumerStatefulWidget {
  const ClubCreateScreen({super.key});

  @override
  ConsumerState<ClubCreateScreen> createState() => _ClubCreateScreenState();
}

class _ClubCreateScreenState extends ConsumerState<ClubCreateScreen> {
  final _nameController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      !_busy &&
      // Block while the name is taken (BUG-2). The server stays the final
      // arbiter on a race.
      ref.watch(clubNameAvailabilityProvider(_nameController.text.trim()))
          .maybeWhen(
            data: (a) => a != NameAvailability.taken,
            orElse: () => true,
          );

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result =
          await ref.read(clubMembershipControllerProvider.notifier).create(
                displayName: _nameController.text.trim(),
              );
      if (!mounted) return;
      switch (result) {
        case ClubActionSuccess<ClubId>(:final value):
          context.pushReplacement(ClubRoutes.detailFor(value.value));
        case ClubActionFailure<ClubId>(:final error):
          final notAllowed = error is ClubActionExceptionError &&
              error.error is ClubPermissionException;
          final isDuplicate = error is ClubActionExceptionError &&
              error.error is ClubDuplicateNameException;
          messenger.showSnackBar(SnackBar(
            content: Text(
              isDuplicate
                  ? AppLocalizations.of(context).clubNameTakenError
                  : notAllowed
                      ? 'Dein Zugang erlaubt kein Vereingründen.'
                      : 'Verein konnte nicht gegründet werden — bitte erneut '
                          'versuchen.',
            ),
            backgroundColor: KubbTokens.miss,
          ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(eyebrow: 'Verein', title: 'Verein gründen'),
      body: ListView(
        padding: const EdgeInsets.all(KubbTokens.space4),
        children: [
          Text(
            'Gib deinem Verein einen Namen. Mitglieder kannst du danach '
            'einladen.',
            style: TextStyle(color: tokens.fgMuted, fontSize: 14),
          ),
          const SizedBox(height: KubbTokens.space5),
          Text(
            'VEREINSNAME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.88,
              color: tokens.fgMuted,
            ),
          ),
          const SizedBox(height: KubbTokens.space2),
          TextField(
            controller: _nameController,
            maxLength: 80,
            decoration: const InputDecoration(
              hintText: 'z. B. Wiesen Kubbler',
              border: OutlineInputBorder(),
            ),
          ),
          Builder(builder: (context) {
            final avail = ref.watch(
              clubNameAvailabilityProvider(_nameController.text.trim()),
            );
            return NameAvailabilityHint(
              isTaken: avail.maybeWhen(
                data: (a) => a == NameAvailability.taken,
                orElse: () => false,
              ),
              isChecking:
                  avail.isLoading && _nameController.text.trim().isNotEmpty,
              takenLabel: AppLocalizations.of(context).clubNameTakenError,
              checkingLabel: AppLocalizations.of(context).nameCheckingHint,
            );
          }),
          const SizedBox(height: KubbTokens.space4),
          KubbButton(
            variant: KubbButtonVariant.primary,
            isLoading: _busy,
            onPressed: _canSubmit ? _submit : null,
            child: const Text('Verein gründen'),
          ),
        ],
      ),
    );
  }
}
