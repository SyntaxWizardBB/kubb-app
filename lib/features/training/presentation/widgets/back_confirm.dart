import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// "Discard the running session?" confirm shown when the back gesture would
/// throw away in-flight throws. Uses the same wording as the finisseur
/// abort confirm so the experience stays consistent across modes.
class SessionBackConfirm {
  const SessionBackConfirm._();

  static Future<bool> show(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.finisseurAbortConfirmTitle),
        content: Text(l.finisseurAbortConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.finisseurAbortConfirmStay),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: tokens.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.finisseurAbortConfirmDiscard),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
