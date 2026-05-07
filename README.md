# kubb_app

Kubb tournament & training management

## Running with Supabase

The app requires a Supabase URL and anon key, passed at build time via
`--dart-define`. There is no `.env` file — the values are baked into the
binary so you can switch environments by rebuilding.

### Local Supabase (Docker)

```bash
supabase start
# → copy "API URL" and "anon key" from the output
```

### Run on Android emulator

The Android emulator reaches the host machine via `10.0.2.2`, so the
Supabase URL printed by `supabase start` (typically `http://127.0.0.1:54321`)
must be rewritten to `http://10.0.2.2:54321`:

```bash
flutter run -d emulator-5554 \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Cleartext HTTP to `10.0.2.2`, `localhost`, and `127.0.0.1` is whitelisted
in `android/app/src/main/res/xml/network_security_config.xml`. Real-device
testing on a LAN IP requires extending that file.

### Run on a real Android device

Use the host's LAN IP and add it to `network_security_config.xml`:

```bash
flutter run -d <device-id> \
  --dart-define=SUPABASE_URL=http://192.168.x.y:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

### Run against a remote Supabase (Hetzner, hosted)

Use the public HTTPS URL — no manifest changes needed:

```bash
flutter run -d <device-id> \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
