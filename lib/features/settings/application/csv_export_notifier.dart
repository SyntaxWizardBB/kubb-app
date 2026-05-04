import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/settings/application/csv_export_state.dart';
import 'package:kubb_app/features/settings/data/csv_export_filter.dart';
import 'package:kubb_app/features/settings/data/csv_export_repository.dart';
import 'package:kubb_app/features/settings/data/csv_exporter.dart';
import 'package:kubb_app/features/settings/data/csv_share_service.dart';

class CsvExportNotifier extends AsyncNotifier<CsvExportState> {
  @override
  Future<CsvExportState> build() async {
    final count = await _count(const CsvExportFilter());
    return CsvExportState(count: count);
  }

  Future<void> setFilter(CsvExportFilter filter) async {
    final prev = state.value ?? const CsvExportState();
    state = AsyncData(prev.copyWith(filter: filter));
    final count = await _count(filter);
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(cur.copyWith(count: count));
  }

  Future<ShareResult?> trigger() async {
    final prev = state.value;
    if (prev == null || !prev.canExport) return null;
    state = AsyncData(prev.copyWith(busy: true));
    try {
      final playerId = await _requirePlayerId();
      final repo = ref.read(csvExportRepositoryProvider);
      final rows = await repo.load(playerId: playerId, filter: prev.filter);
      final csv = CsvExporter().generate(rows);
      final share = ref.read(csvShareServiceProvider);
      final ts = DateTime.now().toUtc();
      final stamp = ts.toIso8601String().split('T').first;
      final result = await share.share(csv, filename: 'kubb-sessions-$stamp.csv');
      state = AsyncData(prev.copyWith(busy: false));
      return result;
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<int> _count(CsvExportFilter filter) async {
    final playerId = await _requirePlayerId();
    final repo = ref.read(csvExportRepositoryProvider);
    return repo.count(playerId: playerId, filter: filter);
  }

  Future<String> _requirePlayerId() async {
    final profile = ref.read(displayProfileProvider);
    if (profile == null) {
      throw StateError('csv export requires an active profile');
    }
    return profile.userId;
  }
}

final csvExportProvider =
    AsyncNotifierProvider<CsvExportNotifier, CsvExportState>(
  CsvExportNotifier.new,
);
