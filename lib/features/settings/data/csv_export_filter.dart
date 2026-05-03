enum ExportRange { all, last30Days, last90Days, lastYear }

class CsvExportFilter {
  const CsvExportFilter({
    this.includeSniper = true,
    this.includeFinisseur = true,
    this.range = ExportRange.all,
  });

  final bool includeSniper;
  final bool includeFinisseur;
  final ExportRange range;

  bool get isEmpty => !includeSniper && !includeFinisseur;

  CsvExportFilter copyWith({
    bool? includeSniper,
    bool? includeFinisseur,
    ExportRange? range,
  }) =>
      CsvExportFilter(
        includeSniper: includeSniper ?? this.includeSniper,
        includeFinisseur: includeFinisseur ?? this.includeFinisseur,
        range: range ?? this.range,
      );

  DateTime? cutoff(DateTime now) {
    switch (range) {
      case ExportRange.all:
        return null;
      case ExportRange.last30Days:
        return now.subtract(const Duration(days: 30));
      case ExportRange.last90Days:
        return now.subtract(const Duration(days: 90));
      case ExportRange.lastYear:
        return now.subtract(const Duration(days: 365));
    }
  }
}
