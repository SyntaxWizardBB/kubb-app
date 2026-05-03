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
