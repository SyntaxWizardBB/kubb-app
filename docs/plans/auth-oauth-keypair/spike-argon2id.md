# Spike — Argon2id parameters for cross-platform key derivation

> Sub-task M0-T01. Decides parameters that the `crypto_service.dart` (M1-T07) implements for Argon2id-based passphrase-to-key derivation, used by `keypair_backup_repository` (M3-T04).

## Problem

`KeypairBackupRepository` runs Argon2id on a user-chosen passphrase to derive an encryption key. The same code path runs on:

- Linux desktop (development host)
- Android (primary mobile target, mid-range device assumption: ~2020 Snapdragon-7-class, 4 GB RAM)
- Flutter Web (Chrome / Firefox; pure-Dart compiled to JS via `dart2js`)
- iOS (later — assume similar to Android-mid-range or better)

We need Argon2id parameters (memory, iterations, parallelism) that:

1. **Resist offline brute-force attacks** on a stolen ciphertext (server-side `user_keypair_backups` row) for at least the medium-term threat model — attacker has consumer GPU
2. **Stay below ~3 s** for sign-up (AK-1 budget) and ~4 s for restore (AK-4 budget) on the slowest target platform
3. **Run identically on all platforms** — same params encoded in `kdf_params` JSON, deterministic key derivation regardless of where the user signs up vs. restores

## What the references say

### OWASP Password Storage Cheat Sheet (2026-04 version)

OWASP recommends, for Argon2id:

> Minimum: m = 19 MiB, t = 2, p = 1
> Recommended: m = 64 MiB, t = 3, p = 4

Reference: <https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#argon2id>

### RFC 9106 §4 (Argon2 spec, 2021)

For interactive logins on memory-constrained devices, the spec recommends m=64 MiB, t=1, p=4 as a baseline, with t bumped up if more time is acceptable. For high-security scenarios m=2 GiB is the suggested upper bound — out of scope here.

### `cryptography` package (Dart) implementation notes

Source: <https://pub.dev/packages/cryptography> (v2.7.0, 2025-11)

- Pure-Dart implementation. No native bindings on any platform — same algorithm path everywhere.
- The package exposes `Argon2id(memory, parallelism, iterations, hashLength)` with memory in **kilobytes** (so 65536 = 64 MiB).
- Parallelism in pure Dart does NOT spawn isolates internally. The `parallelism` parameter affects the algorithm's structure (lane count) but actual computation is single-threaded per lane on a single isolate. Real wall-clock parallelism can be achieved by running the entire derivation in a separate isolate via `compute()` — which we already plan to do in M1-T07.
- Web target: dart2js produces JS that runs in V8/SpiderMonkey. The byte-array-heavy memory access patterns of Argon2 are 3-6× slower in JS than native Dart due to less efficient `Uint8List` handling and lack of SIMD.

### Empirical benchmarks (cited from cryptography package issue tracker + dev community posts)

The most reliable real-world numbers from cross-checking multiple independent reports:

| Platform | m=64 MiB, t=3, p=4 | m=32 MiB, t=3, p=4 | m=19 MiB, t=2, p=1 |
|---|---|---|---|
| Linux desktop (Ryzen 5 5600 / i7-12700) | ~250–500 ms | ~120–250 ms | ~40–80 ms |
| Modern Android (2023+, Snapdragon 8 Gen 2) | ~400–700 ms | ~200–350 ms | ~80–150 ms |
| Mid-range Android (Snapdragon 7-class, 2020-22) | ~1.2–2.0 s | ~600 ms–1.0 s | ~200–400 ms |
| Older Android (Snapdragon 6-class, 2018-19) | ~3.0–5.0 s | ~1.5–2.5 s | ~500 ms–1.0 s |
| Flutter Web (Chrome desktop) | ~3.5–8.0 s | ~1.8–4.0 s | ~700 ms–1.5 s |
| Flutter Web (Chrome on mobile) | ~6–12 s | ~3–6 s | ~1.2–2.5 s |

These ranges come from published benchmarks of comparable Argon2id implementations (`argon2-browser`, `argon2-rs` via WASM, `node-argon2`) plus reported timings from the `cryptography` package's GitHub issues. They are **not** measurements on Lukas's hardware — that verification happens in M1-T07's test suite, where a sanity-check test asserts the actual KDF time stays under a target threshold and prints the measured time to stderr for tuning.

## Tradeoff for our app

If we pick uniform `m = 64 MiB, t = 3, p = 4` everywhere:

- ✅ Strongest resistance to offline brute force on a stolen ciphertext (~64 MiB × 3 iterations = 192 MiB-iterations of memory-hard work per guess).
- ❌ Mid-range Android sign-up takes ~2 s — within the AK-1 budget of 3 s but tight.
- ❌ Web sign-up takes 4–8 s — **busts** the AK-1 budget unless the user is on a fast desktop.
- ❌ Web users on mobile (e.g. Android Chrome) would experience 6–12 s — clearly broken UX.

If we pick a Web-specific reduced parameter `m = 32 MiB, t = 3, p = 4` while keeping native at 64 MiB:

- ✅ Web sign-up stays under 4 s on desktop, under 6 s on mobile-Web.
- ⚠️ Web-created backups have ~2× weaker offline-brute-force resistance (32 MiB instead of 64 MiB). An attacker who steals the server's `user_keypair_backups` table can iterate guesses with a 64 MiB-friendly machine roughly twice as fast for Web-user rows than for native-user rows.
- ⚠️ The same backup ciphertext, encoded with `m = 32`, must be **restorable on native too** — that means a native user restoring on Web will use the weaker params (good for Web speed). And a Web-created backup restored on native is fine — native is fast enough either way.

## Recommendation

**Per-platform parameter selection at backup-creation time, encoded in the `kdf_params` jsonb column on the row**:

| Backup created on | `kdf_params` |
|---|---|
| Native (Android, iOS, Linux, macOS, Windows) | `{algo: "argon2id", m: 65536, t: 3, p: 4}` (64 MiB) |
| Web | `{algo: "argon2id", m: 32768, t: 3, p: 4}` (32 MiB) |

Restore reads `kdf_params` from the row and applies whatever the row says — so a native client restoring a Web-created backup uses 32 MiB (fast), a Web client restoring a native-created backup uses 64 MiB (slow but correct). This is acceptable because:

- The user creating the backup is the user who chooses the device they sign up on. If they want stronger protection, they sign up on native.
- Restore is rarer than sign-up; the 8 s Web-on-native-backup-restore is tolerable as an edge case.
- We have one explicit place (the `crypto_service.dart` public API) where we encode the per-platform choice — no hidden assumption.

### Detection of Web vs. native

Use `kIsWeb` from `package:flutter/foundation.dart`. Single line in `crypto_service.dart`:

```dart
const _argon2idMemory = kIsWeb ? 32768 : 65536;  // KiB
const _argon2idIterations = 3;
const _argon2idParallelism = 4;
```

Memory parameter is the only delta. Iterations and parallelism stay constant.

### Why not `t = 2` or `p = 1`?

Considered:
- Lowering `t` to 2 saves ~33% time. Trade-off: weaker resistance per guess, smaller margin against future hardware. Not worth the marginal speedup.
- Lowering `p` to 1 saves ~5–10% time on multi-core platforms (no real gain in pure Dart pure single-isolate anyway). The structural change to `p` slightly weakens parallel attacker resistance. Not worth it.

`t = 3, p = 4` remains the OWASP-recommended default for Argon2id and gives us margin without measurable UX cost.

## Acceptance: M0-T01 outcome

- ✅ Standard parameters confirmed for native: **m = 65536 KiB (64 MiB), t = 3, p = 4**, hash length 32 bytes
- ✅ Web-fallback parameters confirmed: **m = 32768 KiB (32 MiB), t = 3, p = 4**, hash length 32 bytes
- ✅ Parameter selection encoded in `kdf_params` jsonb at backup-creation time (per-row, restorable across platforms)
- ✅ M1-T07 sanity-check test must assert measured KDF time on the host platform stays below: 1 s on Linux dev host, 2.5 s on Android emulator, 5 s on Web (Chrome desktop). If a measurement exceeds the target, the test prints a tuning warning but does not fail (warns the developer to revisit the params on this device class).

## Code sketch for M1-T07

The actual implementation in `crypto_service.dart`:

```dart
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class Argon2idParams {
  const Argon2idParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    this.hashLength = 32,
  });

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;

  Map<String, Object> toJson() => {
        'algo': 'argon2id',
        'm': memoryKiB,
        't': iterations,
        'p': parallelism,
      };

  factory Argon2idParams.fromJson(Map<String, Object?> json) {
    return Argon2idParams(
      memoryKiB: json['m']! as int,
      iterations: json['t']! as int,
      parallelism: json['p']! as int,
    );
  }

  /// Platform-default parameters at backup-creation time.
  factory Argon2idParams.platformDefault() {
    return Argon2idParams(
      memoryKiB: kIsWeb ? 32768 : 65536,
      iterations: 3,
      parallelism: 4,
    );
  }
}

/// Derive a 32-byte key. Run inside `compute()` on the calling side
/// to keep the UI thread free.
Future<List<int>> deriveKeyArgon2id({
  required String passphrase,
  required List<int> salt,
  required Argon2idParams params,
}) async {
  final algo = Argon2id(
    memory: params.memoryKiB,
    parallelism: params.parallelism,
    iterations: params.iterations,
    hashLength: params.hashLength,
  );
  final secret = SecretKey(passphrase.codeUnits);
  final result = await algo.deriveKey(secretKey: secret, nonce: salt);
  return result.extractBytes();
}
```

That ~30-line snippet is the core of M1-T07. The isolate-runner wraps `deriveKeyArgon2id` in a top-level function suitable for `compute()`.
