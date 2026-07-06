import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/auth/application/impersonation_controller.dart';

/// Persistent, unmissable bar shown on EVERY screen while an admin is acting
/// as another user (M1 §2.2). Mounted once in the app shell
/// (`app.dart` builder). Renders nothing when not impersonating.
class ImpersonationBanner extends ConsumerWidget {
  const ImpersonationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imp = ref.watch(impersonationProvider);
    if (imp == null) return const SizedBox.shrink();

    return Material(
      color: KubbTokens.miss,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KubbTokens.space3,
            vertical: KubbTokens.space2,
          ),
          child: Row(
            children: [
              const Icon(Icons.supervised_user_circle,
                  color: Colors.white, size: 20),
              const SizedBox(width: KubbTokens.space2),
              Expanded(
                child: Text(
                  'Du agierst als ${imp.targetNickname}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    unawaited(ref.read(impersonationProvider.notifier).stop()),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Beenden',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
