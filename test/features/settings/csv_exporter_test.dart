import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/settings/data/csv_exporter.dart';
import 'package:kubb_app/features/settings/data/export_row.dart';

void main() {
  group('CsvExporter', () {
    final exporter = CsvExporter();

    test('emits header row with all 15 columns', () {
      final csv = exporter.generate([]);
      final header = csv.split('\n').first;
      expect(header.split(',').length, 15);
      expect(header, startsWith('session_id,mode,started_at'));
    });

    test('renders sniper row with empty finisseur cells', () {
      final row = ExportRow(
        sessionId: 'sess-1',
        mode: 'sniper',
        startedAt: DateTime.utc(2026, 5, 1, 10),
        completedAt: DateTime.utc(2026, 5, 1, 10, 5),
        distanceM: 8,
        throwTarget: 36,
        hits: 23,
        misses: 13,
        helis: 1,
      );
      final csv = exporter.generate([row]);
      final lines = csv.split('\n');
      expect(lines[1], contains('sess-1,sniper,'));
      expect(lines[1], contains('8.0,36,23,13,1,,,,,'));
    });

    test('renders finisseur row with sticks_used and outcome', () {
      final row = ExportRow(
        sessionId: 'sess-2',
        mode: 'finisseur',
        startedAt: DateTime.utc(2026, 5, 3),
        completedAt: DateTime.utc(2026, 5, 2, 0, 4, 30),
        hits: 4,
        misses: 1,
        helis: 0,
        finField: 7,
        finBase: 3,
        sticksUsed: 5,
        success: true,
        kingHit: true,
      );
      final csv = exporter.generate([row]);
      final cells = csv.split('\n')[1].split(',');
      expect(cells[1], 'finisseur');
      expect(cells[10], '7');
      expect(cells[11], '3');
      expect(cells[12], '5');
      expect(cells[13], 'true');
      expect(cells[14], 'true');
    });

    test('quotes cells containing commas and double-quotes', () {
      final row = ExportRow(
        sessionId: 'a,b',
        mode: 'sniper',
        startedAt: DateTime.utc(2026, 5, 2),
        hits: 0,
        misses: 0,
        helis: 0,
      );
      final csv = exporter.generate([row]);
      final firstCell = csv.split('\n')[1].split(',').take(2).join(',');
      expect(firstCell, '"a,b"');
    });

    test('emits empty string for null duration', () {
      final row = ExportRow(
        sessionId: 'x',
        mode: 'sniper',
        startedAt: DateTime.utc(2026, 5, 2),
        hits: 0,
        misses: 0,
        helis: 0,
      );
      final csv = exporter.generate([row]);
      final cells = csv.split('\n')[1].split(',');
      expect(cells[3], ''); // completed_at empty
      expect(cells[4], ''); // duration empty
    });
  });
}
