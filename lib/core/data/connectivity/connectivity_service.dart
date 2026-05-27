import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstraction over the platform connectivity check.
///
/// Exposes a broadcast stream of the current online state and a synchronous
/// snapshot for callers that need a one-off lookup.
abstract class ConnectivityService {
  /// Emits `true` whenever at least one network interface is available and
  /// `false` when the device transitions to no connectivity.
  Stream<bool> get onlineStream;

  /// Last observed online state.
  bool get isOnline;
}

/// Production implementation backed by `connectivity_plus`.
class RealConnectivityService implements ConnectivityService {
  RealConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen(_handleResults);
    unawaited(_bootstrap());
  }

  final Connectivity _connectivity;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  late final StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isOnline = true;

  Future<void> _bootstrap() async {
    final results = await _connectivity.checkConnectivity();
    _handleResults(results);
  }

  void _handleResults(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none) && results.isNotEmpty;
    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(online);
    }
  }

  @override
  Stream<bool> get onlineStream => _controller.stream;

  @override
  bool get isOnline => _isOnline;

  /// Releases the underlying subscription. Intended for `ref.onDispose`.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _controller.close();
  }
}

/// In-memory implementation for tests and previews.
class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({bool initialOnline = true}) : _isOnline = initialOnline;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _isOnline;

  /// Pushes a new online state to listeners.
  void emit({required bool online}) {
    _isOnline = online;
    _controller.add(online);
  }

  @override
  Stream<bool> get onlineStream => _controller.stream;

  @override
  bool get isOnline => _isOnline;

  Future<void> dispose() => _controller.close();
}
