# OAuth-an-Keypair-Konto verknüpfen — Task-Breakdown

Atomare Tasks, gebucketet nach Unit. Units sind disjoint-by-file — kein File taucht in zwei Units auf, damit parallel gebaut werden kann. Senior-Level: max 100 LOC / 3 Files / 1h pro Task.

Reihenfolge: `migration-sql` und `native-config` haben keine Abhängigkeiten und starten zuerst. `edge-ts` hängt am Migrations-RPC-Vertrag (Contract steht im Plan, kann parallel gegen den Contract gebaut werden). `client-dart` hängt am Edge-Function-Wire-Contract (steht ebenfalls im Plan). `docs` ist unabhängig.

---

## Unit: migration-sql

### TASK-M01: Reconcile-Migration — Unique-Index + RPC

- **Type**: data
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: —
- **Files**: `supabase/migrations/20261325000000_oauth_reconcile.sql`

**Goal**: Eine Migration, die den partiellen Unique-Index `user_credentials_user_kind_idx` und die Service-Role-only RPC `reconcile_link_oauth` anlegt.

**Acceptance**:
- Given die Migration läuft gegen die bestehende Schema-Baseline, When sie angewandt wird, Then existiert `user_credentials_user_kind_idx ON user_credentials (user_id, kind) WHERE kind <> 'keypair'` und ein zweiter `oauth_google`-Insert für dieselbe user_id schlägt mit 23505 fehl.
- Given `reconcile_link_oauth(p_keypair_user_id, p_kind, p_oauth_subject, p_forked_user_id)`, When mit `p_kind` ausserhalb `{oauth_google, oauth_apple}` gerufen, Then `RAISE ERRCODE='22023'`.
- Given ein bereits an einen anderen Nutzer gebundenes `oauth_subject`, When die RPC gerufen wird, Then `RAISE 'OAUTH_SUBJECT_IN_USE' ERRCODE='23505'` und kein Delete.
- Given erfolgreicher Insert mit `p_forked_user_id <> p_keypair_user_id`, When die RPC läuft, Then ist die Credential gegen `p_keypair_user_id` geschrieben und die geforkte `auth.users`-Zeile in derselben TX gelöscht.
- Given die GRANTs, When geprüft, Then ist `EXECUTE` nur `service_role` gewährt (`REVOKE ALL FROM PUBLIC`).

**Notes**: Kein neues Column — `oauth_subject` und Shape-/Unique-Constraints existieren in `20260504000001`. `SECURITY DEFINER`, `SET search_path = public, auth`. Migration-Timestamp muss nach `20261320000000` sortieren.

---

## Unit: edge-ts

### TASK-E01: oauth-reconcile — Shared-Helpers + Request-Validierung

- **Type**: security
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: —
- **Files**: `supabase/functions/_shared/jwt.ts`, `supabase/functions/oauth-reconcile/index.ts`, `supabase/config.toml`

**Goal**: Function-Skelett, `[functions.oauth-reconcile] verify_jwt=false`, `resolveJwtSecret`-Helper extrahiert, und die volle Request-Validierung (Methode, JSON, Felder, provider, base64, Längen).

**Acceptance**:
- Given `verify_jwt=false` in `config.toml`, When die Function deployed, Then ist sie ohne Bearer aufrufbar.
- Given `resolveJwtSecret` im Shared-Modul, When es läuft, Then probiert es `SUPABASE_JWT_SECRET`, dann `SUPABASE_INTERNAL_JWT_SECRET`, dann `SUPABASE_JWKS` (gleiche Logik wie `keypair-verify`).
- Given fehlende Felder / falscher provider / falsche base64-Länge, When gepostet, Then 400 mit `missing_field` / `invalid_provider` / `invalid_base64` / `invalid_public_key_length` / `invalid_signature_length`; GET -> 405.

**Notes**: `_shared/` existiert noch nicht — frisch anlegen. `keypair-verify` darf auf den Helper umgestellt werden, muss aber nicht (kein Bonus-Refactor ohne Scope).

### TASK-E02: oauth-reconcile — Proof A (Keypair-Challenge-Verify)

- **Type**: security
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: TASK-E01
- **Files**: `supabase/functions/oauth-reconcile/index.ts`

**Goal**: Challenge-Lookup + TTL + Ed25519-Verify über rohe Challenge-Bytes + `keypair_user_id`-Auflösung + Single-Use-Delete.

**Acceptance**:
- Given eine unbekannte Challenge, When gepostet, Then 401 `challenge_not_found`.
- Given eine Challenge älter als 60s, When gepostet, Then Zeile gelöscht + 410 `challenge_expired`.
- Given eine gültige Signatur über die rohen Challenge-Bytes, When verifiziert, Then `keypair_user_id` aus `user_credentials WHERE kind='keypair' AND public_key=b64` aufgelöst und die Challenge-Zeile gelöscht; ungültige Signatur -> 401 `signature_invalid`; keine Keypair-Credential -> 401 `no_account_for_public_key`.

**Notes**: 1:1 derselbe Pfad wie `keypair-verify` (hex-escaped bytea, `ed.verifyAsync`).

### TASK-E03: oauth-reconcile — Proof B (GoTrue-autoritativer Token-Read)

- **Type**: security
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: TASK-E01
- **Files**: `supabase/functions/oauth-reconcile/index.ts`

**Goal**: `GET ${SUPABASE_URL}/auth/v1/user` mit OAuth-Bearer + Service-Role-`apikey`, `forked_user_id` und `oauth_subject` aus der GoTrue-Antwort extrahieren.

**Acceptance**:
- Given ein ungültiger/abgelaufener OAuth-Token, When gegen `/auth/v1/user` gelesen, Then 401 `oauth_token_invalid`.
- Given eine GoTrue-Antwort ohne Identität, die zum Request-`provider` passt (mit non-null `id`), When geparst, Then 422 `oauth_provider_mismatch`.
- Given eine gültige Antwort, When geparst, Then kommt `oauth_subject` aus `identity.id` der passenden Identität, nie aus dem Request-Body, und nie aus `admin.getUser(token).identities`.

### TASK-E04: oauth-reconcile — Guards + Mutation + atomarer Re-Mint

- **Type**: security
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: TASK-E02, TASK-E03, TASK-M01
- **Files**: `supabase/functions/oauth-reconcile/index.ts`

**Goal**: Idempotenz-Kurzschluss, Kollisions-Guard, Daten-Guard, `reconcile_link_oauth`-Aufruf, HS256-Re-Mint, 200-Response.

**Acceptance**:
- Given `forked_user_id == keypair_user_id` oder eine schon für diese user_id existierende Credential, When gepostet, Then 200 `already_linked` ohne destruktive Wirkung.
- Given ein `oauth_subject`, das an eine **andere** user_id gebunden ist, When gepostet, Then 409 `oauth_subject_in_use`, kein Insert, kein Delete.
- Given ein geforkter Nutzer mit Zeilen in den Daten-Guard-Tabellen (`tournament_registrations`, Score-Submissions), When gepostet, Then 409 `forked_user_has_data`, kein Delete.
- Given beide Proofs passen und keine Guards greifen, When gepostet, Then `reconcile_link_oauth` schreibt die Credential + löscht den geforkten Nutzer, und die 200-Response enthält `access_token` (frischer HS256 mit `sub=keypair_user_id`, `app_metadata.providers=['keypair', provider]`), `user_id`, `nickname`, `expires_at`, `linked_provider`, `oauth_subject`, `forked_user_deleted`.

**Notes**: Mint-Block aus `keypair-verify:244-272` kopieren. Daten-Guard läuft als `EXISTS`-Lookup vor dem RPC-Aufruf; exakte Tabellenliste per Owner-Entscheidung (siehe ADR-0042 OD-4).

---

## Unit: native-config

### TASK-N01: Android-Intent-Filter für kubbapp-Scheme

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: /agents/coder (frontend instruction)
- **Dependencies**: —
- **Files**: `android/app/src/main/AndroidManifest.xml`

**Goal**: Zweites `<intent-filter>` in der bestehenden `.MainActivity` für `kubbapp://auth/callback`.

**Acceptance**:
- Given die App ist installiert, When ein Browser `kubbapp://auth/callback?code=...` öffnet, Then routet Android die URI in die bestehende `singleTop`-Activity (VIEW + BROWSABLE + DEFAULT, `scheme=kubbapp host=auth`, `autoVerify=false`).
- Given der bestehende LAUNCHER-Filter, When geprüft, Then bleibt er unverändert.

### TASK-N02: iOS-URL-Scheme (geschrieben, geparkt)

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: /agents/coder (frontend instruction)
- **Dependencies**: —
- **Files**: `ios/Runner/Info.plist`

**Goal**: `CFBundleURLTypes` mit dem `kubbapp`-Scheme in einer neu erstellten `Info.plist`.

**Acceptance**:
- Given die `Info.plist`, When geprüft, Then enthält sie ein `CFBundleURLTypes`-Dict mit `CFBundleURLName=app.kubb.auth` und `CFBundleURLSchemes=['kubbapp']`.
- Given ADR-0015 (Android first), When committet, Then ist im Plan/ADR vermerkt, dass der iOS-Runner vor jedem iOS-Build volles Scaffolding (`AppDelegate.swift`, `pbxproj`) braucht — dieser Task scaffoldet den Runner nicht, nur die Plist.

**Notes**: iOS bleibt unbaubar bis zum Runner-Scaffolding. Dieser Task ist Vorbereitung, kein iOS-Enablement.

---

## Unit: client-dart

### TASK-C01: Geteilte Redirect-Konstante

- **Type**: frontend
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: —
- **Files**: `lib/features/auth/data/auth_redirect.dart`, `lib/features/auth/data/supabase_auth_adapter_impl.dart`

**Goal**: `const kAuthCallback = 'kubbapp://auth/callback'` und beide Inline-Literale (impl:61, :209) darauf umstellen.

**Acceptance**:
- Given `kAuthCallback`, When `grep` über `lib/` läuft, Then existiert kein Inline-`'kubbapp://auth/callback'`-Literal mehr ausser in der Konstante.
- Given `flutter analyze`, When ausgeführt, Then clean.

### TASK-C02: Adapter — reconcile-Methode + linkOAuth-Branching

- **Type**: data
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: TASK-C01
- **Files**: `lib/features/auth/data/supabase_auth_adapter.dart`, `lib/features/auth/data/supabase_auth_adapter_impl.dart`

**Goal**: `reconcileOAuthForKeypairUser(...)` (abstract + impl, anon-Key-Pin auf `functions.invoke`, typisierte `ReconcileException`), und `linkOAuthToCurrentUser` branscht auf Session-Kind (Keypair -> nur `signInWithOAuth`; echte GoTrue-Session -> bestehendes `linkIdentity`).

**Acceptance**:
- Given eine Keypair-Session, When `linkOAuthToCurrentUser` gerufen, Then wird `signInWithOAuth(provider, redirectTo: kAuthCallback)` gestartet und `linkIdentity` **nicht** gerufen.
- Given eine echte anonymous/oauth GoTrue-Session, When `linkOAuthToCurrentUser` gerufen, Then bleibt der `linkIdentity`-Pfad unverändert.
- Given `reconcileOAuthForKeypairUser`, When die Edge-Function non-2xx liefert, Then `throw ReconcileException(code)` mit dem Server-Fehlercode; bei 200 `recoverSession` mit dem zurückgegebenen Keypair-Token (nicht dem OAuth-Bearer).
- Given der invoke, When geprüft, Then ist der Authorization-Header auf den anon-Key gepinnt (verifiziert für `functions.invoke`, nicht den RPC-Builder).

### TASK-C03: AuthDeepLinkService

- **Type**: data
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: TASK-C01
- **Files**: `lib/features/auth/data/auth_deep_link_service.dart`, `lib/main.dart`

**Goal**: `AppLinks()`-Instanziierung, `uriLinkStream` + `getInitialLink()`, Disambiguierung (in-flight Upgrade -> `completeLink`, sonst `getSessionFromUrl`), Wiring in `main.dart` nach `Supabase.initialize`.

**Acceptance**:
- Given ein `kubbapp://auth/callback` während eines in-flight Upgrades, When empfangen, Then geht die URI an `AccountUpgradeController.completeLink`, nicht an `getSessionFromUrl`.
- Given ein Cold-OAuth-Sign-in-Callback (kein Upgrade in flight), When empfangen, Then ruft der Service `getSessionFromUrl` und `onAuthStateChange` feuert.
- Given Cold-Start durch den Callback, When die App startet, Then liefert `getInitialLink()` die URI.
- Given `main.dart`, When geprüft, Then lebt die Service-Referenz für die App-Lebenszeit (wie `realtimeAdapter`).

### TASK-C04: AccountUpgradeController als State-Machine

- **Type**: frontend
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: TASK-C02
- **Files**: `lib/features/auth/application/account_upgrade_controller.dart`

**Goal**: Neuer `AccountUpgradeState` (`launching`/`awaitingCallback`/`reconciling`/`done`/`failed(code, provider)`), `linkOAuth` mit Seed-Precheck und ohne Premature-`done()`, `completeLink(uri)` mit Challenge-Sign + Reconcile + Post-Reconcile-Session, Callback-Timeout.

**Acceptance**:
- Given keine Keypair-Session oder kein ladbarer Seed, When `linkOAuth`, Then `failed('not_keypair')` bzw. `failed('keypair_seed_missing')` ohne OAuth-Start.
- Given gestarteter OAuth-Flow, When `linkOAuth` zurückkehrt, Then Status `awaitingCallback`, **nicht** `done`.
- Given `completeLink` mit erfolgreichem Reconcile, When abgeschlossen, Then `OAuthSession(hasKeypairFallback: true)` mit unveränderter user_id in den `authController` geschoben, `telemetry.accountUpgrade` gefeuert, Status `done`.
- Given ein Reconcile-Fehler, When `completeLink` fängt, Then `failed(code)` mit dem typisierten Server-Code.
- Given kein Callback innerhalb 3 min, When der Timeout feuert, Then `failed('callback_timeout')`.

### TASK-C05: Clobber-Suppression im AuthController

- **Type**: data
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (data instruction)
- **Dependencies**: TASK-C04
- **Files**: `lib/features/auth/application/auth_controller.dart`

**Goal**: `_onAdapterState` gaten, sodass während eines in-flight Upgrades eine Nicht-Keypair-Emission für eine unerwartete user_id verworfen wird (kein Persist in den Drift-Cache), bis der Reconcile den Keypair-Token re-mintet.

**Acceptance**:
- Given ein in-flight Upgrade (Status `awaitingCallback`/`reconciling`), When eine geforkte `OAuthSession` mit fremder user_id emittiert, Then wird sie nicht in `_persistSession` geschrieben und nicht als `state` gesetzt.
- Given die App wird mitten im Flow gekillt, When sie cold neustartet, Then hält der Drift-Cache weiter die Keypair-user_id.
- Given kein Upgrade in flight, When eine reguläre OAuth-Session emittiert, Then bleibt das bestehende Verhalten unverändert.

**Notes**: Umsetzung über ein „upgrade in flight"-Flag (Provider, vom Controller gesetzt) plus optional Generation-Bump. Der bestehende `isAnonymousDowngrade`-Guard (Zeile 332-337) bleibt.

### TASK-C06: Account-Link-Screen — code-spezifische Banner + Spinner

- **Type**: frontend
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/coder (frontend instruction)
- **Dependencies**: TASK-C04
- **Files**: `lib/features/auth/presentation/account_link_screen.dart`, `lib/l10n/app_de.arb`, `lib/l10n/generated/`

**Goal**: festes Error-Banner durch Switch auf `failed.code` ersetzen, Spinner für `launching|awaitingCallback|reconciling`, neue ARB-Strings (Schweizer Schriftdeutsch).

**Acceptance**:
- Given ein `failed(code)`, When gerendert, Then zeigt der Screen ein code-spezifisches Banner (`oauth_subject_in_use`, `forked_user_has_data`, `oauth_token_invalid`/`oauth_provider_mismatch`, `challenge_*`, `callback_timeout`, `keypair_seed_missing`, plus generischer Fallback).
- Given `launching|awaitingCallback|reconciling`, When gerendert, Then ein Spinner.
- Given neue ARB-Werte, When geprüft, Then echte `ä/ö/ü`, kein `ß`, und `lib/l10n/generated/` ist im selben Commit aktualisiert (`flutter gen-l10n`).

### TASK-C07: Account-Section — Link-Zeile für Keypair entgaten

- **Type**: frontend
- **Size**: S
- **Bounded Context**: auth
- **Agent**: /agents/coder (frontend instruction)
- **Dependencies**: —
- **Files**: `lib/features/auth/presentation/account_section.dart`

**Goal**: Link-Zeile auch für `KeypairSession` und für eine `OAuthSession` zeigen, der der andere Provider fehlt (ADR-0010 §Multi-credential users).

**Acceptance**:
- Given eine `KeypairSession`, When die Account-Section rendert, Then ist die „Konto verknüpfen"-Zeile sichtbar.
- Given eine `OAuthSession` mit Keypair-Fallback, When gerendert, Then ist die Verknüpfen-Zeile sichtbar; given beide Provider vorhanden, Then nicht.

### TASK-C08: Tests — Reconcile-Adapter + Clobber + Controller

- **Type**: tests
- **Size**: M
- **Bounded Context**: auth
- **Agent**: /agents/tester
- **Dependencies**: TASK-C04, TASK-C05
- **Files**: `test/features/auth/account_upgrade_controller_test.dart`, `test/features/auth/auth_controller_clobber_test.dart`

**Goal**: Unit-/Widget-Tests für die State-Machine-Übergänge, die typisierten Fehler-Mappings und die Clobber-Suppression inkl. Kill-mid-Flow.

**Acceptance**:
- Given die State-Machine, When `linkOAuth` ohne Seed läuft, Then `failed('keypair_seed_missing')` und kein OAuth-Start (Fake-Adapter prüft das).
- Given ein in-flight Upgrade und eine geforkte OAuth-Emission, When der AuthController sie verarbeitet, Then bleibt der Cache auf der Keypair-user_id (Kill-mid-Flow-Test grün).
- Given ein 409-Reconcile-Fehler, When `completeLink` fängt, Then `failed('oauth_subject_in_use')`.

---

## Unit: docs

### TASK-D01: ADR-0010 amend-Marker setzen

- **Type**: docs
- **Size**: S
- **Bounded Context**: core
- **Agent**: /agents/coder (docs instruction)
- **Dependencies**: —
- **Files**: `docs/adr/0010-identity-and-auth.md`

**Goal**: In ADR-0010 einen Hinweis ergänzen, dass ADR-0042 den Account-Upgrade-Pfad konkretisiert (serverseitiger Reconcile statt client-`linkIdentity`).

**Acceptance**:
- Given ADR-0010, When gelesen, Then verweist der Account-Upgrade-Abschnitt auf ADR-0042 für die Keypair->OAuth-Mechanik.
- Given die Änderung, When `isItHuman` läuft, Then keine roten Flaggen, Schweizer Schriftdeutsch wo deutsch.
