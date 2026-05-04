import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/finisseur_stick_event_dao.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/core/data/dao/session_event_dao.dart';
import 'package:kubb_app/features/settings/data/csv_export_filter.dart';
import 'package:kubb_app/features/settings/data/export_row.dart';

const _modeFinisseur = 'finisseur';
const _modeSniper = 'sniper';
const _kindHit = 'hit';
const _kindMiss = 'miss';
const _kindHeli = 'heli';

/// Aggregates completed sessions into [ExportRow]s for CSV export. Reads from
/// the session, session-event and finisseur-stick-event DAOs.
class CsvExportRepository {
  CsvExportRepository({
    required SessionDao sessionDao,
    required SessionEventDao eventDao,
    required FinisseurStickEventDao stickDao,
  })  : _sessions = sessionDao,
        _events = eventDao,
        _sticks = stickDao;

  final SessionDao _sessions;
  final SessionEventDao _events;
  final FinisseurStickEventDao _sticks;

  Future<List<ExportRow>> load({
    required String playerId,
    required CsvExportFilter filter,
    DateTime? now,
  }) async {
    final sessions = await _filteredSessions(
      playerId: playerId,
      filter: filter,
      now: now ?? DateTime.now().toUtc(),
    );
    final out = <ExportRow>[];
    for (final s in sessions) {
      out.add(
        s.mode == _modeFinisseur
            ? await _finisseurRow(s)
            : await _sniperRow(s),
      );
    }
    return out;
  }

  Future<int> count({
    required String playerId,
    required CsvExportFilter filter,
    DateTime? now,
  }) async {
    final rows = await _filteredSessions(
      playerId: playerId,
      filter: filter,
      now: now ?? DateTime.now().toUtc(),
    );
    return rows.length;
  }

  Future<List<Session>> _filteredSessions({
    required String playerId,
    required CsvExportFilter filter,
    required DateTime now,
  }) async {
    if (filter.isEmpty) return const [];
    final all = await _sessions.allCompletedForUser(playerId);
    final cutoff = filter.cutoff(now);
    return all.where((s) {
      if (s.mode == _modeFinisseur && !filter.includeFinisseur) return false;
      if (s.mode != _modeFinisseur && !filter.includeSniper) return false;
      final ts = s.completedAt ?? s.startedAt;
      if (cutoff != null && ts.isBefore(cutoff)) return false;
      return true;
    }).toList();
  }

  Future<ExportRow> _sniperRow(Session s) async {
    final events = await _events.forSession(s.id);
    var hits = 0;
    var misses = 0;
    var helis = 0;
    for (final e in events) {
      if (e.correctedAt != null) continue;
      switch (e.kind) {
        case _kindHit:
          hits++;
        case _kindMiss:
          misses++;
        case _kindHeli:
          helis++;
      }
    }
    return ExportRow(
      sessionId: s.id,
      mode: _modeSniper,
      startedAt: s.startedAt,
      completedAt: s.completedAt,
      distanceM: s.distanceMeters,
      throwTarget: s.throwTarget,
      hits: hits,
      misses: misses,
      helis: helis,
    );
  }

  Future<ExportRow> _finisseurRow(Session s) async {
    final sticks = await _sticks.forSession(s.id);
    var hits = 0;
    var misses = 0;
    var helis = 0;
    bool? kingHit;
    for (final st in sticks) {
      hits += st.fieldKubbsHit + (st.eightMHit ? 1 : 0);
      if (st.heliThrow) {
        helis++;
        misses++;
      } else if (!st.eightMHit && st.fieldKubbsHit == 0 && st.kingHit == null) {
        misses++;
      }
      if (st.kingHit != null) kingHit = st.kingHit;
    }
    final field = s.finField ?? 0;
    final base = s.finBase ?? 0;
    final success = kingHit == true;
    return ExportRow(
      sessionId: s.id,
      mode: _modeFinisseur,
      startedAt: s.startedAt,
      completedAt: s.completedAt,
      hits: hits,
      misses: misses,
      helis: helis,
      finField: field,
      finBase: base,
      sticksUsed: sticks.length,
      success: success,
      kingHit: kingHit,
    );
  }
}

final csvExportRepositoryProvider = Provider<CsvExportRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CsvExportRepository(
    sessionDao: db.sessionDao,
    eventDao: db.sessionEventDao,
    stickDao: db.finisseurStickEventDao,
  );
});
