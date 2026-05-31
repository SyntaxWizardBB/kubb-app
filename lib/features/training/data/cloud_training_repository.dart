import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Aggregated, server-stored view of one completed training session (P2).
/// Mirrors `public.training_sessions`. Sniper rows carry [hitRate] / [throws];
/// finisseur rows carry [win] / [sticksUsed] / [fieldTarget] / [baseTarget].
class CloudTrainingSession {
  const CloudTrainingSession({
    required this.id,
    required this.userId,
    required this.mode,
    required this.startedAt,
    required this.completedAt,
    this.distanceM,
    this.hitRate,
    this.throws,
    this.win,
    this.sticksUsed,
    this.fieldTarget,
    this.baseTarget,
  });

  factory CloudTrainingSession.fromRow(Map<String, dynamic> row) {
    DateTime ts(Object? v) => DateTime.parse(v! as String).toUtc();
    double? asDouble(Object? v) => v == null ? null : (v as num).toDouble();
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    return CloudTrainingSession(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      mode: row['mode'] as String,
      distanceM: asDouble(row['distance_m']),
      hitRate: asInt(row['hit_rate']),
      throws: asInt(row['throws']),
      win: row['win'] as bool?,
      sticksUsed: asInt(row['sticks_used']),
      fieldTarget: asInt(row['field_target']),
      baseTarget: asInt(row['base_target']),
      startedAt: ts(row['started_at']),
      completedAt: ts(row['completed_at']),
    );
  }

  final String id;
  final String userId;
  final String mode; // 'sniper' | 'finisseur'
  final double? distanceM;
  final int? hitRate;
  final int? throws;
  final bool? win;
  final int? sticksUsed;
  final int? fieldTarget;
  final int? baseTarget;
  final DateTime startedAt;
  final DateTime completedAt;

  bool get isSniper => mode == 'sniper';
  bool get isFinisseur => mode == 'finisseur';

  Map<String, dynamic> toRow() => <String, dynamic>{
        'id': id,
        'user_id': userId,
        'mode': mode,
        'distance_m': distanceM,
        'hit_rate': hitRate,
        'throws': throws,
        'win': win,
        'sticks_used': sticksUsed,
        'field_target': fieldTarget,
        'base_target': baseTarget,
        'started_at': startedAt.toUtc().toIso8601String(),
        'completed_at': completedAt.toUtc().toIso8601String(),
      };
}

/// CRUD against `public.training_sessions`. RLS scopes reads to the owner and
/// their accepted friends, and writes to the owner — the client never threads
/// the user id through guard checks itself.
class CloudTrainingRepository {
  CloudTrainingRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// Insert-or-update one aggregated session (keyed on [CloudTrainingSession.id],
  /// the same UUID as the local drift row, so re-uploads are idempotent).
  Future<void> upsert(CloudTrainingSession session) async {
    await _client.from('training_sessions').upsert(session.toRow());
  }

  /// All sessions for [userId], newest first. Returns the caller's own rows or
  /// a friend's rows; RLS rejects everyone else with an empty result.
  Future<List<CloudTrainingSession>> listForUser(String userId) async {
    final rows = await _client
        .from('training_sessions')
        .select()
        .eq('user_id', userId)
        .order('completed_at', ascending: false);
    return rows.map(CloudTrainingSession.fromRow).toList(growable: false);
  }

  /// Hard-deletes one of the caller's own sessions (owner RLS).
  Future<void> delete(String id) async {
    await _client.from('training_sessions').delete().eq('id', id);
  }

  /// Hard-deletes ALL of one user's cloud sessions (owner RLS scopes this to
  /// the caller's own rows). Used by the "reset training sessions" action so
  /// the server copies are wiped alongside the local drift rows.
  Future<void> deleteAllForUser(String userId) async {
    await _client.from('training_sessions').delete().eq('user_id', userId);
  }
}

final cloudTrainingRepositoryProvider =
    Provider<CloudTrainingRepository>((ref) {
  return CloudTrainingRepository(client: Supabase.instance.client);
});
