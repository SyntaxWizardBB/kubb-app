import 'dart:async';

import 'package:kubb_domain/src/values/ids.dart';
import 'package:meta/meta.dart';

/// Logical timestamp for ordering match events across devices when wall-clock
/// time cannot be trusted.
///
/// Ordering rule:
///   1. Compare counter; higher counter wins.
///   2. On equal counter, compare deviceId.value lexicographically as a
///      stable tie-break.
///
/// The clock advances on every local emission and on every observed remote
/// event so that the local counter is always greater than any seen value.
@immutable
final class LamportTimestamp implements Comparable<LamportTimestamp> {
  const LamportTimestamp({required this.counter, required this.deviceId});

  final int counter;
  final DeviceId deviceId;

  @override
  int compareTo(LamportTimestamp other) {
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return deviceId.value.compareTo(other.deviceId.value);
  }

  bool operator <(LamportTimestamp other) => compareTo(other) < 0;
  bool operator >(LamportTimestamp other) => compareTo(other) > 0;
  bool operator <=(LamportTimestamp other) => compareTo(other) <= 0;
  bool operator >=(LamportTimestamp other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LamportTimestamp &&
          other.counter == counter &&
          other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(counter, deviceId);

  @override
  String toString() => 'L($counter@${deviceId.value})';
}

class LamportClock {
  LamportClock({required this.deviceId, int initialCounter = 0})
      : _counter = initialCounter;

  final DeviceId deviceId;
  int _counter;
  StreamSubscription<int>? _serverSubscription;

  int get counter => _counter;

  LamportTimestamp tick() {
    _counter += 1;
    return LamportTimestamp(counter: _counter, deviceId: deviceId);
  }

  LamportTimestamp observe(LamportTimestamp remote) {
    if (remote.counter >= _counter) {
      _counter = remote.counter + 1;
    } else {
      _counter += 1;
    }
    return LamportTimestamp(counter: _counter, deviceId: deviceId);
  }

  /// Hydrates this clock from the maximum lamport counter seen in the local
  /// outbox for a given `(matchId, deviceId)` pair.
  ///
  /// After hydration, the next [tick] must return a counter strictly greater
  /// than [outboxMax]. The `matchId` and `deviceId` parameters are passed so
  /// callers can document the scoping intent; lookup of the maximum value
  /// itself happens upstream (DAO query) and is provided here as
  /// [outboxMax]. The internal counter is lifted to
  /// `max(currentCounter, outboxMax)` so a subsequent [tick] emits a strictly
  /// greater value.
  void hydrateFromOutbox(
    MatchId matchId,
    DeviceId deviceId,
    int outboxMax,
  ) {
    if (outboxMax > _counter) {
      _counter = outboxMax;
    }
  }

  /// Subscribes to a server-side stream of observed lamport counters and
  /// advances this clock whenever a higher value is seen.
  ///
  /// On every emitted value `serverMax`, sets the internal counter to
  /// `max(currentCounter, serverMax)`. A subsequent [tick] therefore returns
  /// a counter strictly greater than any value observed on the stream so far.
  /// Calling this method again cancels the previous subscription.
  void observeFromStream(Stream<int> serverMax) {
    unawaited(_serverSubscription?.cancel());
    _serverSubscription = serverMax.listen((value) {
      if (value > _counter) {
        _counter = value;
      }
    });
  }

  /// Cancels any active server-counter subscription. Safe to call multiple
  /// times.
  Future<void> dispose() async {
    await _serverSubscription?.cancel();
    _serverSubscription = null;
  }
}
