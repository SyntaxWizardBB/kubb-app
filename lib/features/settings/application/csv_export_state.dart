import 'package:kubb_app/features/settings/data/csv_export_filter.dart';

class CsvExportState {
  const CsvExportState({
    this.filter = const CsvExportFilter(),
    this.count = 0,
    this.busy = false,
  });

  final CsvExportFilter filter;
  final int count;
  final bool busy;

  bool get canExport => count > 0 && !busy;

  CsvExportState copyWith({
    CsvExportFilter? filter,
    int? count,
    bool? busy,
  }) =>
      CsvExportState(
        filter: filter ?? this.filter,
        count: count ?? this.count,
        busy: busy ?? this.busy,
      );
}
