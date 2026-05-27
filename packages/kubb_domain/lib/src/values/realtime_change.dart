import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Kind of row-level change observed on a Realtime channel. Mirrors the
/// Postgres CDC vocabulary (`INSERT`, `UPDATE`, `DELETE`).
enum RealtimeEventType {
  insert,
  update,
  delete,
}

/// Connection state of one Realtime channel as exposed by
/// `RealtimeChannel.stateStream`. The UI surfaces this so a thin banner
/// can show "reconnecting…" or "offline, polling active" without leaking
/// transport details into widgets.
enum RealtimeChannelState {
  connecting,
  joined,
  closed,
  errored,
}

const _mapEq = MapEquality<String, Object?>();

/// One row-level change event delivered by a `RealtimeChannel`.
///
/// Wire payloads from Supabase (or any adapter) are normalised into this
/// value type before they cross the port. `newRow` is empty for delete
/// events and `oldRow` is empty for insert events; both are populated for
/// updates.
@immutable
class RealtimeChange {
  const RealtimeChange({
    required this.eventType,
    required this.table,
    required this.rowId,
    required this.newRow,
    required this.oldRow,
    required this.receivedAt,
  });

  final RealtimeEventType eventType;
  final String table;
  final String rowId;
  final Map<String, Object?> newRow;
  final Map<String, Object?> oldRow;
  final DateTime receivedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealtimeChange &&
          other.eventType == eventType &&
          other.table == table &&
          other.rowId == rowId &&
          _mapEq.equals(other.newRow, newRow) &&
          _mapEq.equals(other.oldRow, oldRow) &&
          other.receivedAt == receivedAt;

  @override
  int get hashCode => Object.hash(
        eventType,
        table,
        rowId,
        _mapEq.hash(newRow),
        _mapEq.hash(oldRow),
        receivedAt,
      );
}
