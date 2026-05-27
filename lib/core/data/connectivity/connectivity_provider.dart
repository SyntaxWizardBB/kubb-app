import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_service.dart';

/// DI seam for the [ConnectivityService].
///
/// Override this provider in tests to inject a [FakeConnectivityService].
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = RealConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});
