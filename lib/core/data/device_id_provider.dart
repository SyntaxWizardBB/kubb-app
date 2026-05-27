import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Storage key under which the stable per-installation device id lives in
/// `flutter_secure_storage`. Single point of truth so audits stay simple.
const String _kDeviceIdStorageKey = 'kubb_device_id';

/// Provider for the [FlutterSecureStorage] instance used by the
/// device-id helper. Tests override this with a fake.
final deviceIdSecureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
});

/// In-memory fallback for environments where the secure-storage platform
/// channel is unavailable (e.g. unit tests, headless CI). Lives at module
/// scope so the same device id is returned for the lifetime of the
/// isolate even when the secure-storage write throws.
String? _inMemoryDeviceId;

/// Stable per-installation device id used as the `lamportDeviceId` in
/// score-submission outbox rows and as the tie-break key in
/// `LamportTimestamp`. Persists across app restarts via
/// `flutter_secure_storage`; falls back to a process-lifetime `uuid.v4`
/// when the platform channel is not available (unit tests on the Dart
/// VM, headless CI, etc.).
final deviceIdProvider = FutureProvider<String>((ref) async {
  final storage = ref.watch(deviceIdSecureStorageProvider);
  try {
    final stored = await storage.read(key: _kDeviceIdStorageKey);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final generated = const Uuid().v4();
    await storage.write(key: _kDeviceIdStorageKey, value: generated);
    return generated;
  } on Object {
    // Secure storage unavailable (e.g. unit-test isolate). Cache an
    // in-memory uuid so callers within the same isolate keep observing
    // a stable id without flapping the lamport tie-break key.
    return _inMemoryDeviceId ??= const Uuid().v4();
  }
});
