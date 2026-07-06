import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/name_availability_hint.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/auth/application/nickname_availability_provider.dart';
import 'package:kubb_app/features/auth/data/cloud_profile_repository.dart';

/// M2 onboarding: a signed-in user with no `user_profiles` row (typically a
/// fresh OAuth login) picks a unique nickname before entering the app. Same
/// nickname UX as the anonymous signup (live availability, 3-30, [A-Za-z0-9_-])
/// but WITHOUT the passphrase/keypair steps. The router forces this route
/// until a profile exists; on success it invalidates the profile provider and
/// the redirect lets the user through.
class OnboardingProfileScreen extends ConsumerStatefulWidget {
  const OnboardingProfileScreen({super.key});

  @override
  ConsumerState<OnboardingProfileScreen> createState() =>
      _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState
    extends ConsumerState<OnboardingProfileScreen> {
  final _controller = TextEditingController();
  String _nickname = '';
  bool _busy = false;

  static final _charset = RegExp(r'^[A-Za-z0-9_-]+$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _formatValid =>
      _nickname.length >= 3 &&
      _nickname.length <= 30 &&
      _charset.hasMatch(_nickname);

  Future<void> _submit() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref
          .read(cloudProfileRepositoryProvider)
          .createProfileForCurrentUser(nickname: _nickname);
      ref.invalidate(cloudProfileProvider);
      if (mounted) router.go('/');
    } on DuplicateNicknameException {
      messenger.showSnackBar(
          const SnackBar(content: Text('Dieser Name ist schon vergeben.')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final availability = _formatValid
        ? ref.watch(nicknameAvailabilityProvider(_nickname))
        : const AsyncValue<NicknameAvailability>.data(NicknameAvailability.idle);
    final isChecking = _formatValid && availability.isLoading;
    final isTaken = availability.maybeWhen(
      data: (v) => v == NicknameAvailability.taken,
      orElse: () => false,
    );
    final canSubmit = _formatValid && !isTaken && !isChecking && !_busy;

    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: const KubbAppBar(
        eyebrow: 'Willkommen',
        title: 'Profil einrichten',
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KubbTokens.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: KubbTokens.meadow500,
                  child: Text(
                    _nickname.isEmpty ? '?' : _nickname.characters.first.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: KubbTokens.space4),
              Text('Wähle deinen Spielernamen',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: tokens.fg)),
              const SizedBox(height: KubbTokens.space2),
              Text(
                'So erscheinst du in Turnieren und Ranglisten. '
                'Der Name ist eindeutig und lässt sich später ändern.',
                style: TextStyle(color: tokens.fgMuted),
              ),
              const SizedBox(height: KubbTokens.space4),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 30,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_-]')),
                ],
                onChanged: (v) => setState(() => _nickname = v.trim()),
                onSubmitted: (_) => canSubmit ? unawaited(_submit()) : null,
                decoration: InputDecoration(
                  labelText: 'Spielername',
                  hintText: 'z. B. kubb_king',
                  filled: true,
                  fillColor: tokens.bgRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KubbTokens.radiusLg),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              NameAvailabilityHint(
                isTaken: isTaken,
                isChecking: isChecking,
                takenLabel: 'Dieser Name ist schon vergeben.',
                checkingLabel: 'Prüfe Verfügbarkeit …',
              ),
              if (_nickname.isNotEmpty && !_formatValid)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text(
                    '3–30 Zeichen: Buchstaben, Zahlen, _ und -.',
                    style: TextStyle(fontSize: 12, color: tokens.fgMuted),
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: canSubmit ? () => unawaited(_submit()) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: KubbTokens.meadow500,
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Weiter'),
              ),
              const SizedBox(height: KubbTokens.space2),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        ref.read(authControllerProvider.notifier).signOut()),
                child: const Text('Abmelden'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
