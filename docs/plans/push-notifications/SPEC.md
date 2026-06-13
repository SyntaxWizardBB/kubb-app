# Spec — Push-Benachrichtigungen (FCM, „one write, two wakes")

Quelle der Wahrheit für die Agent-Pipeline. Branch `feat/push-notifications`
(ab `main`). Stand 2026-06-12. Architektur-Grundlage: ADR-0029 §6 (Push-Seam,
bewusst „designed-for now, built later" — jetzt wird gebaut) und der
Messaging-Framework-Plan `docs/plans/realtime-messaging/messaging-framework-plan.md`.

## Owner-Entscheide (verbindlich, 2026-06-12)

1. **Plattformen:** Android + iOS zusammen. iOS wird code-seitig vollständig
   vorbereitet (Bundle-ID `ch.kubbclub.app`, Entitlements, Plist), aber
   Build/Test braucht macOS — erster echter iOS-Push erst mit einem Mac-Build.
   Android wird lokal end-to-end getestet.
2. **Delivery-Mechanismus: HYBRID** (State of the Art beim Transactional-
   Outbox-Pattern): Database-Webhook (pg_net) feuert pro `push_outbox`-INSERT
   sofort die Edge Function (Latenz <1s) **plus** pg_cron-Sweeper (~30s) für
   pending/failed-Zeilen mit Backoff (Supabase-Webhooks sind best effort ohne
   Retries — der Sweeper ist das Zuverlässigkeits-Netz). Beide Pfade rufen
   dieselbe idempotente Edge Function; `delivered_at` wird atomar geclaimt,
   Doppelzustellung ausgeschlossen.
3. **Kuratierung: ALLE Inbox-Kinds pushen** („one write, two wakes" — volle
   Parität zur Inbox). Nutzer-seitige Filter sind ein späteres Feature.
4. **Package/Bundle-ID:** `ch.kubbclub.app` (reverse-Domain der eigenen Domain
   kubbclub.ch; unveränderlich nach Play-Store-Publish). Rename ist erfolgt.

## Bereits vorhanden (nicht neu bauen!)

- **Inbox-Spine:** jedes durable Event schreibt `public.user_inbox_messages`
  (Kinds: notice, verification_request, system, team_*, club_*,
  tournament_started/round/shootout/finished/invitation, …). CDC-Publication
  aktiv (`20261231000000`).
- **Push-Seam:** `20261233000000_inbox_push_seam.sql` — `tg_inbox_push_seam()`
  AFTER INSERT auf user_inbox_messages, sendet PII-freien Realtime-Nudge
  (`id, kind, subject, sent_at` auf privates Topic `user_push:<user_id>`);
  der `push_outbox`-Enqueue ist dort ein markierter **No-op (TODO push phase)**.
- **`push_outbox`-Stub-Tabelle** (id, user_id, payload, created_at,
  delivered_at; RLS an, keine Client-Policies — service-role only).
- **Lifecycle-Invariante:** Foreground = genau 1 WebSocket; paused/detached =
  0 Sockets/Timer; Push ist der EINZIGE Background-Wake
  (`lib/app/realtime_lifecycle_controller.dart`).
- **pg_cron aktiv** (`20261270000000_enable_pg_cron.sql`). pg_net NICHT aktiv.
- **Edge-Runtime aktiv**, Muster-Function `supabase/functions/keypair-verify/`
  (config.toml §functions).
- **Firebase Android-Konfiguration FERTIG** (2026-06-12): Projekt
  `kubbclubapp` (project_number 106001380567), App `ch.kubbclub.app`
  registriert; `android/app/google-services.json` liegt im Repo (Client-Config,
  kein Secret); google-services-Gradle-Plugin 4.4.4 in
  `android/settings.gradle.kts` (apply false) + `android/app/build.gradle.kts`
  (applied). BoM/firebase-analytics bewusst NICHT nativ ergänzt — FlutterFire
  (P3) bringt native SDKs selbst mit.

## Externe Voraussetzungen (User-Beistellung)

- ✅ Firebase-Projekt + Android-App (`google-services.json` im Repo).
- ⏳ **Service-Account-Key (JSON)** des Firebase-Projekts → wird Supabase-
  Secret für die Edge Function (FCM HTTP v1 OAuth). Ohne ihn ist P2 nur
  logik-testbar, nicht gegen echtes FCM.
- ⏳ iOS: Apple-Developer-Account + APNs-Auth-Key (.p8) in Firebase
  hinterlegen + `GoogleService-Info.plist`; erst für echten iOS-Push nötig.

## Bau-Blöcke (je Block: 4-Rollen-Pipeline + unabhängige Verifikation + 1 Commit)

### P1 — Server: Token-Registry + Outbox scharf (Migrationsband ab 20261290000000)

> Band-Hinweis: `20261274`–`20261284` sind durch den parallelen Branch
> `feat/permissions-organizer-teams` (ADR-0032 Organizer-Teams/Rollen) belegt;
> Push startet daher sicher bei `20261290000000`.

- `public.user_device_tokens(id uuid pk, user_id uuid NOT NULL fk auth.users
  ON DELETE CASCADE, platform text CHECK (platform IN ('android','ios')),
  token text NOT NULL, created_at, last_seen_at, UNIQUE(token))` + Index auf
  user_id. RLS: owner-only SELECT/DELETE; Schreibweg über RPC.
- RPCs (SECURITY DEFINER, auth.uid()-Gate, GRANT authenticated):
  `push_register_device_token(p_platform, p_token)` (Upsert: gleicher Token →
  user_id/last_seen_at aktualisieren — Gerätewechsel zwischen Accounts deckt
  das ab) und `push_unregister_device_token(p_token)` (nur eigener Token).
- `push_outbox` erweitern (additiv): `inbox_message_id uuid`, `status text
  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','delivered','failed',
  'dead'))`, `attempts int NOT NULL DEFAULT 0`, `next_attempt_at timestamptz
  NOT NULL DEFAULT now()`, `last_error text`. Index auf
  (status, next_attempt_at).
- `tg_inbox_push_seam()` **CREATE OR REPLACE, echten Body re-basen
  (20261233000000)**: den No-op-Block durch den Enqueue ersetzen —
  `INSERT INTO push_outbox(user_id, inbox_message_id, payload)` mit dem
  SELBEN PII-freien Payload wie der Nudge (id, kind, subject, sent_at).
  Idempotent über UNIQUE(inbox_message_id). Alles andere byte-genau.
- Verifikation rein psql (BEGIN/ROLLBACK): Inbox-Insert → genau 1 Outbox-Zeile
  pending mit PII-freiem Payload; Token-RPCs (Gate, Upsert-Semantik, Unregister
  fremder Token verboten); kein Firebase nötig.

### P2 — Delivery: Edge Function + Hybrid-Trigger (Band fortlaufend)

- Edge Function `supabase/functions/push-deliver/`: claimt offene Zeilen
  (`UPDATE … SET status='delivered' … WHERE status='pending' AND
  next_attempt_at <= now() … FOR UPDATE SKIP LOCKED`-Muster via service-role),
  Tokens je user nachschlagen, **FCM HTTP v1** (`projects/kubbclubapp/
  messages:send`, OAuth2 via Service-Account-Secret `FCM_SERVICE_ACCOUNT`),
  Erfolg → delivered_at; Fehler → attempts+1, Backoff (next_attempt_at =
  now() + LEAST(2^attempts, 60) min), nach N=8 → status 'dead';
  UNREGISTERED/INVALID_ARGUMENT-Token → aus user_device_tokens löschen.
  Payload an FCM: data-only `{inbox_message_id, kind}` + notification
  {title=subject} — KEIN body/PII.
- `CREATE EXTENSION pg_net` + AFTER-INSERT-Trigger auf push_outbox →
  `net.http_post` an die Edge Function (Webhook-Pfad, Sofort-Zustellung).
- pg_cron-Job (~30s) ruft dieselbe Function als Sweeper (pending+failed).
- Verifikation: ohne FCM-Key → Logikpfad mit Fake-Endpoint; mit Key →
  echter Versand (P4).

### P3 — Flutter: Empfang + Token-Lifecycle

- `firebase_core` + `firebase_messaging` (pubspec; Achtung bekanntes
  pub-get-Thema file_selector — Lösung dokumentieren statt umgehen).
- Init in `lib/app/` (Firebase.initializeApp vor runApp-Teilen, die es
  brauchen); Android 13+ Runtime-Permission `POST_NOTIFICATIONS`
  (firebase_messaging requestPermission deckt das ab — kein extra Paket).
- Token-Lifecycle: bei Login + onTokenRefresh → `push_register_device_token`;
  bei Logout → unregister. Provider-basiert, kein Polling.
- Foreground-Verhalten: KEINE System-Notification, wenn App offen (Inbox/CDC
  übernimmt — Nudge existiert schon); Background/terminated: System-
  Notification aus der FCM-notification, Tap → App öffnen, Lifecycle-resume
  reconnectet Inbox-CDC, `refreshFromRemote` lädt (exakt ADR-0029 §6.2 (4)).
- iOS code-seitig: Plist, Push-Entitlement, Background-Mode remote-notification
  (Build/Test erst auf macOS).
- AndroidManifest: `POST_NOTIFICATIONS`-Permission deklarieren; default
  notification channel meta-data.

### P4 — E2E lokal (Android)

Inbox-Insert (psql) → Outbox → Webhook/Sweeper → Edge Function → echtes FCM →
Emulator/Gerät (Background + Foreground + Tap-Navigation). Abnahme-Checkliste
in diesem Doc abhaken.

## Guardrails (für alle Pipeline-Briefs)

Nur additive Migrationen, kein `supabase db reset`; Proben in BEGIN/ROLLBACK;
bei CREATE OR REPLACE jüngsten Body re-basen (Stale-Body-Diff); keine fremden
Dateien; kein git add -A; Training-Kontext tabu; UI-Texte de via ARB; Tests
mit --no-pub; Commit/Push nur durch den Orchestrator.
