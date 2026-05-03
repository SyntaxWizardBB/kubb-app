import 'package:kubb_app/features/settings/data/export_row.dart';

const _columns = <String>[
  'session_id',
  'mode',
  'started_at',
  'completed_at',
  'duration_seconds',
  'distance_m',
  'throw_target',
  'hits',
  'misses',
  'helis',
  'fin_field',
  'fin_base',
  'sticks_used',
  'success',
  'king_hit',
];

/// Pure-Dart CSV writer for training session exports. Comma-separated, LF
/// line endings, RFC-4180 quoting where needed (commas, quotes, newlines).
class CsvExporter {
  String generate(List<ExportRow> rows) {
    final buf = StringBuffer()..writeln(_columns.join(','));
    for (final row in rows) {
      buf.writeln(_renderRow(row));
    }
    return buf.toString();
  }

  String _renderRow(ExportRow r) {
    final cells = <String?>[
      r.sessionId,
      r.mode,
      r.startedAt.toIso8601String(),
      r.completedAt?.toIso8601String(),
      r.durationSeconds?.toString(),
      r.distanceM?.toString(),
      r.throwTarget?.toString(),
      r.hits.toString(),
      r.misses.toString(),
      r.helis.toString(),
      r.finField?.toString(),
      r.finBase?.toString(),
      r.sticksUsed?.toString(),
      _boolCell(r.success),
      _boolCell(r.kingHit),
    ];
    return cells.map(_escape).join(',');
  }

  String? _boolCell(bool? v) => v == null ? null : (v ? 'true' : 'false');

  String _escape(String? value) {
    if (value == null) return '';
    final needsQuote = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuote) return value;
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
