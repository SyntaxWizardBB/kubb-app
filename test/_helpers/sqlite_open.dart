import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:sqlite3/open.dart';

bool _registered = false;

/// Registers a Linux-specific SQLite resolver so tests can run with the
/// system `libsqlite3.so.0` instead of the package-bundled binary.
/// No-op on other platforms or when called more than once.
///
/// Resolution cascade exists because NixOS does not provide FHS-standard
/// library paths (`/usr/lib/...`), so a bare `libsqlite3.so.0` lookup fails.
/// The override tries, in order: an explicit env override, the standard
/// loader name (works on Debian/Ubuntu/CI), and finally a Nix-store glob.
void registerLinuxSqliteOverride() {
  if (_registered || !Platform.isLinux) {
    return;
  }
  open.overrideFor(OperatingSystem.linux, _resolveLinuxSqlite);
  _registered = true;
}

DynamicLibrary _resolveLinuxSqlite() {
  final attempts = <String>[];

  // 1. Explicit escape hatch for CI / unusual distros.
  final envPath = Platform.environment['KUBB_TEST_SQLITE_PATH'];
  if (envPath != null && envPath.isNotEmpty) {
    attempts.add(envPath);
    if (File(envPath).existsSync()) {
      return DynamicLibrary.open(envPath);
    }
  }

  // 2. Bare loader name — resolves via ld.so on FHS-compliant Linux.
  // Cannot pre-check existence (no filesystem path), so attempt and recover
  // via the linker's failure path if the library is not on the search path.
  const bareName = 'libsqlite3.so.0';
  attempts.add(bareName);
  final bareLib = _openBare(bareName);
  if (bareLib != null) return bareLib;

  // 3. NixOS: scan /nix/store for a sqlite package and grab its libsqlite3.so.0.
  final nixPath = _findInNixStore();
  if (nixPath != null) {
    attempts.add(nixPath);
    return DynamicLibrary.open(nixPath);
  }

  throw StateError(
    'Could not locate libsqlite3.so.0 for tests. Tried: '
    '${attempts.join(', ')}. '
    'Set KUBB_TEST_SQLITE_PATH to an absolute path to override.',
  );
}

DynamicLibrary? _openBare(String name) {
  try {
    return DynamicLibrary.open(name);
    // dart:ffi surfaces linker failures as platform-specific Errors that we
    // intentionally swallow so the resolution cascade can continue.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null;
  }
}

/// Locates `libsqlite3.so.0` inside the local Nix store by scanning the
/// top-level store entries for a `sqlite-*` directory containing the lib.
String? _findInNixStore() {
  final store = Directory('/nix/store');
  if (!store.existsSync()) return null;
  try {
    final entries = store.listSync(followLinks: false);
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final name = entry.path.split('/').last;
      // Match `<hash>-sqlite-<version>` (skip src/doc/autoconf variants).
      if (!name.contains('-sqlite-')) continue;
      if (name.contains('-sqlite-src-') ||
          name.contains('-sqlite-doc-') ||
          name.contains('-sqlite-autoconf-')) {
        continue;
      }
      final candidate = '${entry.path}/lib/libsqlite3.so.0';
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

/// Builds an in-memory `AppDatabase` with `foreign_keys` enabled so tests
/// can rely on cascade and restrict actions just like production builds.
Future<AppDatabase> openTestDatabase() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customStatement('PRAGMA foreign_keys = ON');
  return db;
}
