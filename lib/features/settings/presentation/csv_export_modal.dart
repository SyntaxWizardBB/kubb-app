import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/settings/application/csv_export_notifier.dart';
import 'package:kubb_app/features/settings/application/csv_export_state.dart';
import 'package:kubb_app/features/settings/data/csv_export_filter.dart';
import 'package:kubb_app/features/settings/data/csv_share_service.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

class CsvExportModal extends ConsumerWidget {
  const CsvExportModal({super.key});

  static Future<void> show(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const CsvExportModal(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<KubbTokens>()!;
    final l = AppLocalizations.of(context);
    final async = ref.watch(csvExportProvider);
    final notifier = ref.read(csvExportProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgRaised,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(KubbTokens.radiusXl)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KubbTokens.space4,
            KubbTokens.space2,
            KubbTokens.space4,
            KubbTokens.space5,
          ),
          child: async.when(
            loading: () => const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(KubbTokens.space4),
              child: Text(e.toString(), style: TextStyle(color: tokens.danger)),
            ),
            data: (state) => _Body(
              state: state,
              tokens: tokens,
              l: l,
              onRangeChanged: (r) => notifier.setFilter(state.filter.copyWith(range: r)),
              onSniperChanged: (v) =>
                  notifier.setFilter(state.filter.copyWith(includeSniper: v)),
              onFinisseurChanged: (v) =>
                  notifier.setFilter(state.filter.copyWith(includeFinisseur: v)),
              onDownload: () async {
                final messenger = ScaffoldMessenger.of(context);
                final result = await notifier.trigger();
                if (!context.mounted) return;
                Navigator.of(context).pop();
                if (result?.kind == ShareKind.savedToFile && result?.path != null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l.csvExportSavedTo(result!.path!))),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.tokens,
    required this.l,
    required this.onRangeChanged,
    required this.onSniperChanged,
    required this.onFinisseurChanged,
    required this.onDownload,
  });

  final CsvExportState state;
  final KubbTokens tokens;
  final AppLocalizations l;
  final ValueChanged<ExportRange> onRangeChanged;
  final ValueChanged<bool> onSniperChanged;
  final ValueChanged<bool> onFinisseurChanged;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final filter = state.filter;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: KubbTokens.space3),
            decoration: BoxDecoration(
              color: tokens.line,
              borderRadius: BorderRadius.circular(KubbTokens.radiusPill),
            ),
          ),
        ),
        Text(l.csvExportTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: KubbTokens.space3),
        Text(l.csvExportRangeLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: tokens.fgMuted)),
        const SizedBox(height: KubbTokens.space2),
        Wrap(
          spacing: KubbTokens.space2,
          children: [
            for (final range in ExportRange.values)
              ChoiceChip(
                label: Text(_rangeLabel(range)),
                selected: filter.range == range,
                onSelected: (_) => onRangeChanged(range),
              ),
          ],
        ),
        const SizedBox(height: KubbTokens.space4),
        Text(l.csvExportModesLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: tokens.fgMuted)),
        const SizedBox(height: KubbTokens.space2),
        CheckboxListTile(
          title: Text(l.csvExportModeSniper),
          value: filter.includeSniper,
          onChanged: (v) => onSniperChanged(v ?? false),
        ),
        CheckboxListTile(
          title: Text(l.csvExportModeFinisseur),
          value: filter.includeFinisseur,
          onChanged: (v) => onFinisseurChanged(v ?? false),
        ),
        const SizedBox(height: KubbTokens.space3),
        Text(l.csvExportCount(state.count),
            style: TextStyle(color: tokens.fgMuted)),
        const SizedBox(height: KubbTokens.space3),
        FilledButton.icon(
          onPressed: state.canExport ? onDownload : null,
          icon: const Icon(LucideIcons.download),
          label: Text(l.csvExportDownload),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ),
        if (!state.canExport)
          Padding(
            padding: const EdgeInsets.only(top: KubbTokens.space2),
            child: Text(l.csvExportEmpty,
                style: TextStyle(color: tokens.fgMuted, fontSize: 12)),
          ),
      ],
    );
  }

  String _rangeLabel(ExportRange r) {
    switch (r) {
      case ExportRange.all:
        return l.csvExportRangeAll;
      case ExportRange.last30Days:
        return l.csvExportRange30;
      case ExportRange.last90Days:
        return l.csvExportRange90;
      case ExportRange.lastYear:
        return l.csvExportRangeYear;
    }
  }
}
