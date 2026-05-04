import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

enum AbortChoice { save, discard, cancel }

class AbortDialog extends StatelessWidget {
  const AbortDialog._({required this.hasThrows});

  final bool hasThrows;

  static Future<AbortChoice?> show(
    BuildContext context, {
    required bool hasThrows,
  }) {
    return showDialog<AbortChoice>(
      context: context,
      builder: (_) => AbortDialog._(hasThrows: hasThrows),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l.abortDialogTitle),
      content: Text(l.abortDialogContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(AbortChoice.cancel),
          child: Text(l.abortDialogCancel),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: tokens.danger),
          onPressed: () => Navigator.of(context).pop(AbortChoice.discard),
          child: Text(l.abortDialogDiscard),
        ),
        if (hasThrows)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(AbortChoice.save),
            child: Text(l.abortDialogSave),
          ),
      ],
    );
  }
}

/// Two-button confirm shown when the user backs out of a finisseur session
/// after at least one stick has been recorded. Stays minimal — there is no
/// save path because finisseur stats are only useful when complete.
class FinisseurAbortConfirm {
  const FinisseurAbortConfirm._();

  static Future<bool> show(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final confirmed = await showDialog<bool>(
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
    return confirmed ?? false;
  }
}
