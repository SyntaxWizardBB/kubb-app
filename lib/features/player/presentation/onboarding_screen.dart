import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:logging/logging.dart';

final _log = Logger('OnboardingScreen');

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isValid => _controller.text.trim().isNotEmpty && !_submitting;

  Future<void> _confirm() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(playerRepositoryProvider).create(name: name);
      // Router redirect picks up the drift stream emission and navigates.
    } on Object catch (e, st) {
      _log.warning('failed to create profile', e, st);
      if (!mounted) return;
      setState(() => _submitting = false);
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.onboardingCreateError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space6,
            vertical: KubbTokens.space8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                l.onboardingGreeting,
                style: textTheme.titleMedium?.copyWith(color: tokens.fgMuted),
              ),
              const SizedBox(height: KubbTokens.space2),
              Text(
                l.onboardingTitle,
                style: textTheme.headlineMedium?.copyWith(color: tokens.fg),
              ),
              const SizedBox(height: KubbTokens.space6),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l.onboardingHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_isValid) unawaited(_confirm());
                },
              ),
              const SizedBox(height: KubbTokens.space6),
              SizedBox(
                height: KubbTokens.touchComfortable,
                child: FilledButton(
                  onPressed: _isValid ? _confirm : null,
                  child: Text(l.onboardingConfirm),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
