import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Two-button destructive confirm. Returns `true` only when the danger button
/// is tapped. `null` and `false` both mean cancelled.
Future<bool> showDangerConfirm({
  required BuildContext context,
  required String title,
  required String body,
}) async {
  final l = AppLocalizations.of(context);
  final tokens = Theme.of(context).extension<KubbTokens>()!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.confirmCancel),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: tokens.danger),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.confirmDelete),
        ),
      ],
    ),
  );
  return result ?? false;
}
