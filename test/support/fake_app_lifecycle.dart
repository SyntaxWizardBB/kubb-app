import 'package:flutter/widgets.dart' show AppLifecycleState;

/// Test-only driver that feeds [AppLifecycleState] transitions into a sink
/// (typically `RealtimeLifecycleController.onLifecycleState`).
///
/// Pure test support — it holds no production code path and is imported only
/// from tests. Combine with `fake_async` to advance the controller's debounce
/// in virtual time. Records the sequence it drove so assertions can replay it.
class FakeAppLifecycle {
  FakeAppLifecycle(this._sink);

  final void Function(AppLifecycleState state) _sink;

  /// Every state this fake has driven, in order.
  final List<AppLifecycleState> driven = <AppLifecycleState>[];

  AppLifecycleState? _current;

  /// The most recently driven state, or null before the first transition.
  AppLifecycleState? get current => _current;

  void resumed() => _drive(AppLifecycleState.resumed);

  void inactive() => _drive(AppLifecycleState.inactive);

  void paused() => _drive(AppLifecycleState.paused);

  void detached() => _drive(AppLifecycleState.detached);

  /// Drives an arbitrary [state] (e.g. `hidden`).
  void drive(AppLifecycleState state) => _drive(state);

  void _drive(AppLifecycleState state) {
    _current = state;
    driven.add(state);
    _sink(state);
  }
}
