# Feature — Authentication: OAuth + anonymous keypair

> Erzeugt von `/agents/product-owner` am 2026-05-04. Input: Feature-Beschreibung von `/feature` + ADR-0010 (kanonische Auth-Spec) + ADR-0003 (Rollen) + ADR-0009 (Hosting-Kontext) + ADR-0002 (Bounded Contexts).

## Bounded Context

**`auth/`** — pragmatischer Context per ADR-0002, eigener `lib/features/auth/`-Ordner mit `data/`, `application/`, `presentation/` (Owner-Entscheidung Variante A). Touch auf:
- `lib/features/player/` — lokales Profile bleibt Source-of-Truth solange offline; Cloud-Profile wird additiv angelegt
- `lib/core/data/` — drift v4-Migration für `cached_auth_session`-Tabelle
- `lib/core/ui/settings/` — bestehender SettingsScreen bekommt Account-Sektion mit Logout

## User Stories

| #  | Story | Priorität | AK |
|----|-------|-----------|-----|
| US-1 | Als neuer Spieler:in möchte ich mich beim ersten App-Start ohne E-Mail registrieren können, damit ich sofort spielen kann ohne externe Konten zu verknüpfen. | **MUST** | AK-1 |
| US-2 | Als neue Spieler:in möchte ich mich mit Google oder Apple anmelden können, damit ich mit einem Tap einsteigen kann ohne mir eine Passphrase zu merken. | **MUST** | AK-2 |
| US-3 | Als anonyme Spieler:in möchte ich beim Account-Anlegen ein verschlüsseltes Backup mit einer Passphrase auf dem Server hinterlegen, damit ich meinen Account auf einem neuen Gerät wiederherstellen kann. | **MUST** | AK-3 |
| US-4 | Als anonyme Spieler:in möchte ich auf einem neuen Gerät meinen Nickname und meine Passphrase eingeben können, damit mein bestehender Account dort entsperrt wird. | **MUST** | AK-4 |
| US-5 | Als anonyme Spieler:in möchte ich später meinen Account mit Google oder Apple verknüpfen können, damit ich keine Passphrase mehr verwalten muss und bei Geräte-Wechsel kein Risiko trage. | **MUST** | AK-5 |
| US-6 | Als angemeldete Spieler:in möchte ich im Settings-Screen einen Logout-Button finden, damit ich meine Session beenden kann. | **MUST** | AK-6 |
| US-7 | Als angemeldete Spieler:in möchte ich, dass die App auch offline startet und meinen Login-Status aus der gecachten Session erkennt, damit ich Trainingsmodi ohne Netz nutzen kann (sofern ich mich vorher mindestens einmal online angemeldet habe). | **MUST** | AK-7 |
| US-8 | Als neue Spieler:in muss ich beim allerersten App-Start zwingend einen Account erstellen oder mich anmelden, damit es kein lokales-only-Profil gibt das später nicht in die Cloud passt. | **MUST** | AK-8 |
| US-9 | Als App soll ich die Session automatisch erneuern, solange ein gültiger Refresh-Token verfügbar ist, damit der Spieler:in nicht alle Stunde neu eingeben muss. | **MUST** (implizit) | AK-9 |
| US-10 | Als anonyme Spieler:in möchte ich eine Warnung sehen wenn ich mein Backup nicht eingerichtet habe, damit ich verstehe dass ein Geräte-Verlust den Account vernichtet. | SHOULD | AK-10 |
| US-11 | Als anonyme Spieler:in möchte ich meinen Private-Key als QR-Code exportieren können, damit ich ein eigenes Backup ausserhalb des Servers anlegen kann. | COULD | — |
| US-12 | Als anonyme Spieler:in möchte ich meine Passphrase ändern können, damit ich auf Verdacht eines Lecks reagieren kann. | SHOULD | AK-12 |
| US-13 | Als Spieler:in möchte ich meinen Account löschen können (lokal und in der Cloud), damit ich mein Recht auf Vergessenwerden ausüben kann. | **MUST** | AK-13 |
| US-14 | Als angemeldete Spieler:in möchte ich, dass mein OAuth-Token nie im Klartext auf der Festplatte liegt, damit ein anderer App-Prozess ihn nicht abgreifen kann. | **MUST** (NFR-Wrapper) | AK-14 |
| US-15 | Als angemeldete Spieler:in möchte ich beim Start-Bildschirm sofort sehen, ob ich anonym oder via OAuth angemeldet bin, damit ich weiss welche Account-Aktionen verfügbar sind. | SHOULD | AK-15 |
| US-16 | Als zukünftige Organisator:in möchte ich daran erinnert werden, dass ich für Tournament-Erstellung OAuth brauche, damit ich nicht mit einem anonymen Account in eine Sackgasse laufe. | COULD | — |
| US-17 | Als App-Entwickler möchte ich Auth-Events (Login-Versuch, Erfolg, Fehler, Logout) im internen Logger haben, damit ich Probleme nachvollziehen kann ohne externe Telemetrie. | SHOULD (implizit) | AK-17 |
| US-18 | Als App soll ich beim Verlust der Server-Verbindung den Login-Versuch nicht endlos blockieren, damit der Spieler:in eine klare Fehlermeldung bekommt und es später erneut versuchen kann. | **MUST** (implizit) | AK-18 |
| US-19 | Als neue anonyme Spieler:in möchte ich vor dem Erstellen meines Accounts klar gewarnt werden, dass die Passphrase nicht wiederherstellbar ist und in einem Password-Manager gesichert gehört, damit ich die Tragweite verstehe und nicht später überrascht bin. | **MUST** | AK-19 |
| US-20 | Als frisch angemeldete Spieler:in möchte ich nach dem ersten Sign-In durch einen kurzen Onboarding-Flow geführt werden, damit ich die Kern-Features der App kennenlerne ohne sie selbst entdecken zu müssen. | **MUST** | AK-20 |

## Akzeptanzkriterien (Given/When/Then)

### AK-1 (US-1) — Anonyme Registrierung beim ersten Start

- **Given** die App wird zum ersten Mal gestartet und es gibt keine bestehende Session
- **When** die Spieler:in den Pfad "Ohne Konto starten" wählt, einen Nickname und eine Passphrase eingibt und auf "Account erstellen" tippt
- **Then** wird lokal ein Ed25519-Keypair generiert, der Private-Key in `flutter_secure_storage` abgelegt, ein `auth.users`-Eintrag mit zugehörigem `user_credentials`-Eintrag (kind=`keypair`) auf dem Server angelegt, ein `user_profiles`-Eintrag mit dem gewählten Nickname erstellt
- **And** der `authControllerProvider` exposed `AsyncValue.data(AuthSession.keypair(userId, nickname))`
- **And** der Vorgang dauert auf einem Mittelklasse-Mobilgerät < 3 s (inkl. Argon2id für die Backup-Verschlüsselung in AK-3)

### AK-2 (US-2) — OAuth-Anmeldung mit Google oder Apple

- **Given** die App wird gestartet und die Spieler:in ist nicht angemeldet
- **When** sie "Mit Google anmelden" tippt und im OAuth-Browser-Tab den Google-Account bestätigt
- **Then** wird über Supabase Auth ein Session-JWT ausgestellt, ein `auth.users`-Eintrag und ein `user_credentials`-Eintrag (kind=`oauth_google`, oauth_subject=`google-sub`) angelegt, ein `user_profiles`-Eintrag mit dem lokalen Nickname (falls vorhanden) oder einem Fallback aus dem OAuth-Profil erstellt
- **And** der `authControllerProvider` exposed `AsyncValue.data(AuthSession.oauth(userId, provider: OAuthProvider.google))`
- **And** der Deep-Link-Callback (Mobile: `kubbapp://auth/callback`) bzw. die Web-Callback-Route (`/auth/callback`) wird ohne Re-Mount des Root-Widgets verarbeitet

### AK-3 (US-3) — Verschlüsseltes Backup beim Anlegen

- **Given** der Schritt aus AK-1 läuft und der Private-Key wurde generiert
- **When** der Argon2id-KDF mit (memory=64 MiB, iterations=3, parallelism=4, salt=16 Byte zufällig) auf der gewählten Passphrase läuft
- **Then** wird der Private-Key mit XChaCha20-Poly1305 (nonce=24 Byte zufällig) verschlüsselt und ein Eintrag in `user_keypair_backups` mit `nickname_hash`, `ciphertext`, `kdf_salt`, `kdf_params (jsonb)` angelegt
- **And** weder die Passphrase noch der Klartext-Key verlassen das Gerät; der Server kennt nur den Ciphertext
- **And** der Vorgang ist Teil von AK-1; das Argon2id-Budget zählt mit zur 3-s-Schwelle

### AK-4 (US-4) — Restore auf neuem Gerät

- **Given** ein Backup existiert auf dem Server unter `nickname_hash = sha256(nickname || server_salt)`
- **When** die Spieler:in auf dem neuen Gerät "Konto wiederherstellen" wählt, Nickname und Passphrase eingibt
- **Then** lädt der Client den `ciphertext` und die `kdf_params` vom Server, leitet den Schlüssel mit Argon2id aus der Passphrase ab, entschlüsselt den Private-Key, schreibt ihn in `flutter_secure_storage` und meldet einen erfolgreichen Login-Status
- **And** bei falscher Passphrase wird eine deutliche Fehlermeldung "Passphrase passt nicht — Account nicht entsperrt" gezeigt; **kein** Hinweis darauf ob der Nickname gefunden wurde (kein Enumeration-Vektor)
- **And** drei aufeinanderfolgende Fehlversuche pro `nickname_hash` lösen ein clientseitiges Cool-Down von 30 s aus

### AK-5 (US-5) — Account-Upgrade anonym → OAuth

- **Given** die Spieler:in ist mit Keypair-Account angemeldet (`AuthSession.keypair`)
- **When** sie in den Settings "Mit Google verknüpfen" wählt und den OAuth-Flow erfolgreich durchläuft
- **Then** wird ein zusätzlicher `user_credentials`-Eintrag (kind=`oauth_google`) zur **gleichen** `user_id` angelegt, der bestehende Keypair-Eintrag bleibt erhalten
- **And** die Session läuft ab jetzt als `AuthSession.oauth(userId, provider, fallbackKeypair: true)`; bei OAuth-Verlust ist Login mit dem Keypair weiterhin möglich
- **And** das User-Profile bleibt unverändert (gleiche `user_id`, gleicher Nickname); keine doppelten Einträge

### AK-6 (US-6) — Logout im Settings-Screen

- **Given** die Spieler:in ist angemeldet (egal welcher Pfad)
- **When** sie im Settings-Screen unter Account "Abmelden" tippt und im Bestätigungs-Dialog mit "Abmelden" bestätigt
- **Then** wird die Server-Session ungültig gemacht (Supabase `signOut`), der lokale `cached_auth_session`-Eintrag wird gelöscht, der `authControllerProvider` exposed `AsyncValue.data(AuthSession.signedOut())`
- **And** das lokale Profile (Nickname, Avatar in `player/`) **bleibt** erhalten
- **And** der bei Keypair-Account in `flutter_secure_storage` abgelegte Private-Key **bleibt** erhalten — Logout ≠ Account-Löschung
- **And** die Spieler:in landet auf dem Sign-In-Screen

### AK-7 (US-7) — Offline-Start mit gecachter Session

- **Given** die Spieler:in war zuletzt angemeldet, der Cached-Session-Eintrag in der drift-DB ist gültig (JWT noch nicht abgelaufen oder Refresh-Token vorhanden), und die `userId` + `displayName` aus der Cache-Tabelle sind verfügbar
- **When** die App ohne Netzwerkverbindung startet
- **Then** lädt der `authControllerProvider` aus der Cache-Tabelle, exposed `AsyncValue.data(AuthSession.<kind>(userId, displayName, ...))` und der Bootstrap blockiert nicht auf einem Server-Call
- **And** Trainingsmodi (Sniper, Finisseur) sind sofort erreichbar; Sessions werden mit der `userId` aus der gecachten Session gespeichert
- **And** Cloud-only-Features (z.B. zukünftige Tournaments) zeigen einen "Offline"-Banner statt Endlos-Loader
- **And** beim ersten App-Start (kein Cached-Session-Eintrag) wird der Sign-In-Screen gezeigt — die App ist ohne mindestens-einmal-online-Anmeldung nicht nutzbar

### AK-8 (US-8) — Auth-Pflicht beim Erst-Start; kein lokales Profil

- **Given** ein frisches App-Install ohne `cached_auth_session`-Eintrag und ohne Verbindung zu einer existierenden Account-Identität
- **When** die App startet
- **Then** wird der Sign-In-Screen (AK-2-Eingangspunkt) erzwungen — kein "Später"-Bypass, keine lokale Nickname-Eingabe ohne Account
- **And** die drift-DB enthält **keine** `players`-Tabelle mehr (entfällt in v4-Migration); Trainings-`sessions` haben statt `playerId` eine `userId`-Spalte (Text/UUID, referenziert `auth.users.id` der Cloud, ohne lokale FK)
- **And** wer keine Verbindung hat und sich noch nie angemeldet hat, kann die App nicht nutzen — der Sign-In-Screen zeigt eine Hinweismeldung "Verbindung erforderlich für ersten Start"

### AK-9 (US-9) — Automatischer Token-Refresh

- **Given** die Spieler:in ist angemeldet, das JWT läuft in < 5 min ab, ein Refresh-Token ist vorhanden
- **When** ein Hintergrund-Timer im `authControllerProvider` zuschlägt (oder ein Server-Call mit 401 zurückkommt)
- **Then** wird der Refresh-Flow ausgeführt, das neue JWT in der Cache-Tabelle gespeichert, die Session-State bleibt unverändert
- **And** bei Refresh-Fehler (Refresh-Token abgelaufen oder ungültig) wird die Session lokal als abgelaufen markiert, der nächste UI-Aufruf zeigt den Sign-In-Screen mit Hinweis "Bitte neu anmelden"

### AK-10 (US-10) — Backup-Hinweis für anonyme Accounts

- **Given** die Spieler:in hat einen anonymen Account und kein Backup eingerichtet (oder das Backup ist > 90 Tage alt)
- **When** sie den Settings-Screen öffnet
- **Then** zeigt eine Warnung "Kein Backup eingerichtet — bei Geräteverlust ist dein Account weg" mit einem Button "Backup einrichten"

### AK-12 (US-12) — Passphrase ändern

- **Given** die Spieler:in ist mit Keypair-Account angemeldet und kennt die alte Passphrase
- **When** sie unter Settings → Account → "Passphrase ändern" die alte und die neue Passphrase eingibt
- **Then** wird der Private-Key mit der neuen Passphrase neu verschlüsselt, der `user_keypair_backups`-Eintrag wird per UPDATE überschrieben (gleiche `user_id`, neuer `kdf_salt`, neuer `ciphertext`)
- **And** die alte Passphrase ist ab sofort ungültig für Restore-Operationen

### AK-13 (US-13) — Account löschen

- **Given** die Spieler:in ist angemeldet
- **When** sie unter Settings → Account → "Konto löschen" zwei Bestätigungs-Dialoge durchläuft (Tippen-Schutz)
- **Then** werden alle Server-Daten zu dieser `user_id` gelöscht (`user_profiles`, `user_credentials`, `user_keypair_backups`, `auth.users`)
- **And** lokale Daten werden gelöscht (cached session, Private-Key in Secure-Storage); das lokale Profile (Nickname, Avatar) **bleibt** auf Wunsch erhalten oder wird gelöscht — Spieler:in wählt im Dialog
- **And** die Spieler:in landet auf dem Sign-In-Screen, der Vorgang ist nicht rückgängig machbar

### AK-14 (US-14) — Token-Speicherung sicher

- **Given** die App läuft auf einem realen Gerät
- **When** ein Auth-Token (JWT, Refresh-Token, OAuth-Token, Private-Key) gespeichert wird
- **Then** liegt es in `flutter_secure_storage` (Android Keystore, iOS Keychain, Linux Secret Service, Windows Credential Vault)
- **And** auf Web-Plattform wird der Token nur in-memory gehalten oder mit einer User-eingegebenen Passphrase verschlüsselt im LocalStorage abgelegt — nie als Klartext
- **And** drift-Tabelle `cached_auth_session` enthält **keine** Klartext-Tokens, nur die `user_id`, `kind`, `expires_at`, `refresh_after`

### AK-15 (US-15) — Account-Status sichtbar

- **Given** die Spieler:in ist angemeldet
- **When** sie den Home-Screen öffnet
- **Then** zeigt die AppBar bzw. Settings-Sektion ein Badge: "Anonym" (mit Schloss-Symbol) oder "Google" / "Apple" (mit Provider-Logo)

### AK-17 (US-17) — Internes Logging

- **Given** ein Auth-Event tritt auf (Sign-In-Versuch, Erfolg, Fehler, Refresh, Logout)
- **When** der Event-Handler durchläuft
- **Then** wird via `package:logging` ein Eintrag mit Level (`INFO` / `WARNING` / `SEVERE`) und einem strukturierten Message-Feld geschrieben (kein PII — keine E-Mails, keine Tokens, nur `userId` Prefix und Event-Typ)

### AK-18 (US-18) — Server-Verbindungsfehler-Handling

- **Given** der Server ist unerreichbar (Timeout, DNS-Fehler, 5xx)
- **When** die Spieler:in einen Login-Versuch startet
- **Then** wird nach max. 10 s der Versuch abgebrochen, eine Fehlermeldung "Server nicht erreichbar — bitte später erneut versuchen" angezeigt, der Sign-In-Screen bleibt sichtbar mit Retry-Button
- **And** beim Restore-Flow gilt das Gleiche; **kein** Endlos-Spinner

### AK-19 (US-19) — Disclaimer beim anonymen Account-Anlegen

- **Given** die Spieler:in hat im Sign-In-Screen "Ohne Konto starten" gewählt und einen Nickname eingegeben
- **When** sie den Schritt "Passphrase eingeben" erreicht
- **Then** wird vor dem Eingabefeld ein nicht-überspringbarer Hinweis-Block angezeigt mit drei Punkten:
  1. **Diese Passphrase kann nicht zurückgesetzt werden.** Wer sie vergisst, verliert seinen Account dauerhaft.
  2. **Wir empfehlen dringend, die Passphrase in einem Password-Manager zu speichern** (z.B. 1Password, Bitwarden, KeePassXC).
  3. **Die App-Betreiber haften nicht** für verlorene Accounts. Bei Sorge: lieber den OAuth-Pfad (Google/Apple) wählen.
- **And** die Spieler:in muss eine explizite Checkbox **"Ich habe die Risiken verstanden und werde meine Passphrase sichern"** anhaken bevor der "Account erstellen"-Button aktiv wird
- **And** der Hinweis-Block ist via Screen-Reader lesbar und bleibt während der gesamten Passphrase-Eingabe sichtbar (nicht nur als Modal das verschwindet)

### AK-20 (US-20) — Onboarding-Flow nach erstem Sign-In

- **Given** die Spieler:in hat sich erfolgreich angemeldet (egal welcher Pfad) und es ist ihr **erster** Login auf diesem Gerät (kein `onboarding_completed=true` im AppSettings-Eintrag)
- **When** der Sign-In-Flow abgeschlossen ist
- **Then** wird ein Onboarding-Screen-Stapel gezeigt mit:
  1. Willkommen + Account-Status (Anonym vs OAuth, mit visueller Unterscheidung)
  2. Kurze Vorstellung der drei Trainingsmodi (Sniper, Finisseur, künftig 4m-Linie)
  3. Hinweis auf Tournament-/Friend-Match-Funktionen ("kommen bald")
  4. Bei anonymen Accounts: zusätzlicher Reminder-Slide "Hast du deine Passphrase im Password-Manager gespeichert?"
- **And** die Spieler:in kann jederzeit "Überspringen" tippen — der Flag `onboarding_completed=true` wird in beiden Fällen gesetzt
- **And** der Onboarding-Flow erscheint **nicht** wieder, auch nicht bei späterem Re-Login auf demselben Gerät
- **And** der Onboarding-Flow erscheint **nicht** bei Restore-Flow auf neuem Gerät, wenn der Server-Status der Spieler:in `onboarding_completed=true` enthält (sync via `user_profiles`)

## Implizite Anforderungen

- **Sign-In-Screen-Erstaufruf-Logik**: beim allerersten App-Start (kein `cached_auth_session`-Eintrag) wird der Sign-In-Screen direkt nach dem Splash gezeigt — **erzwungen, ohne "Später"-Bypass** (siehe Klärung 8 / Owner-Entscheidung).
- **Kein lokales-only-Profile**: die `players`-drift-Tabelle entfällt vollständig (drift v4 dropt sie). Profile-Daten leben ausschliesslich in Supabase `user_profiles`; lokal werden nur die für den Offline-UI-Betrieb nötigen Anzeige-Felder (`displayName`, `avatar_color`) als Spalten in `cached_auth_session` mitgeführt — als reiner Cache, nicht als Source-of-Truth. Bestehender F2-Code (`player_repository.dart`, `current_profile_provider.dart`, `onboarding_screen.dart`, `profile_screen.dart` Edit-Mode) wird in dieser Phase ersetzt; die Profil-Anzeige im Settings holt die Cloud-Felder über `cloud_profile_repository`.
- **Sessions verlieren lokale FK**: `sessions.player_id` (Text-FK auf `players.id`) wird in v4 zu `sessions.user_id` (Text/UUID, ohne FK — referenziert `auth.users.id` aus der Cloud). Bestehende Session-Daten in dev-DBs werden im Migration-Step gedroppt (App ist nicht live, keine produktiven Daten).
- **Session-Cache-Tabelle**: drift-Schema-Migration v4 mit Tabelle `cached_auth_session` (1 Zeile maximal — Single-Account-Constraint, siehe Klärung 5) — Felder: `id` (singleton), `user_id`, `kind`, `display_name`, `avatar_color` (nullable), `expires_at`, `refresh_after`, `created_at`, `updated_at`. **Keine** Tokens hier — nur Status-Metadaten + Anzeige-Cache.
- **Nickname-Validierung**: Nickname muss zwischen 3 und 30 Zeichen, alphanumerisch + Bindestrich + Unterstrich. Kollisionsbehandlung serverseitig per `user_profiles.nickname_unique`-Index.
- **Passphrase-Mindestanforderung**: 12 Zeichen, kein anderes Zwangsmuster (NIST-konform). UI zeigt Stärke-Indikator (zxcvbn-light), warnt aber nicht hart.
- **Deep-Link-Konfiguration**: Mobile-Build registriert URL-Scheme `kubbapp://`. Web-Build behandelt `/auth/callback` als reguläre Route. Beide ohne Routing-Glitches mit `go_router`.
- **OAuth-Provider-Setup**: Google- und Apple-Client-IDs müssen als Build-Konfiguration verfügbar sein (lokal aus `.env.local`, nicht im Repo). Für Tests/Stub: Mock-Provider mit deterministischen Responses. Apple-Pfad nur auf iOS-Build aktiv (siehe Klärung 3).
- **Onboarding-Reihenfolge**: Sign-In-Screen → Account-Anlegen-Flow (Anonym: Nickname → Disclaimer + Passphrase, oder OAuth: Provider-Wahl + Browser-Tab) → Backup-Erfolg-Bestätigung (nur Anonym) → **Onboarding-Tour** (siehe AK-20) → Home. Reihenfolge: Sign-In zuerst, Onboarding danach (Owner-Entscheidung).
- **Single-Account-Konstrukt**: nur eine aktive Session pro Geräteinstall. "Account wechseln" = Logout + neuer Sign-In; kein Switcher-Pattern (siehe Klärung 5).

## Nicht-funktionale Anforderungen

### Performance
- Bootstrap (Cold-Start bis Home-Screen) bei gecachter Session: < 1.5 s auf Mittelklasse-Mobilgerät
- OAuth-Roundtrip (Tap "Mit Google" bis Home): < 5 s bei guter Netzverbindung
- Anonymer Account-Anlegen (inkl. Argon2id + Backup-Upload): < 3 s auf Mittelklasse-Mobilgerät
- Restore-Flow (Eingabe bis Home): < 4 s
- Token-Refresh im Hintergrund: nicht spürbar (kein UI-Block)

### Security
- Private-Key, JWT, Refresh-Token, OAuth-Token: ausschliesslich in `flutter_secure_storage` (siehe AK-14)
- Passphrase: nie loggen, nie als String ausserhalb der KDF-Berechnung halten, sofort nach Use überschreiben
- Argon2id-Parameter: memory=64 MiB, iterations=3, parallelism=4 — getestet auf Mid-Range-Android (API 28, 4 GB RAM)
- Server-API: alle Auth-Calls über HTTPS; lokale Dev-Supabase mit selbst-signiertem Cert + bekannte Ausnahme im Code
- RLS-Policies (per ADR-0010): `user_credentials` nur vom Owner lesbar; `user_keypair_backups` nur per `nickname_hash` lookup-bar (Ciphertext sinnlos ohne Passphrase)
- Keine PII im Logger (kein E-Mail-String, kein OAuth-Subject, kein Klartext-Nickname — nur `userId` Prefix, max. 8 Zeichen)
- Enumeration-Schutz: Restore-Flow gibt keine Information ob Nickname gefunden wurde (siehe AK-4)

### Usability
- 1-Tap OAuth: nicht mehr als ein Tap zwischen "Mit Google" und Browser-Tab
- Passphrase-Eingabe mit Show/Hide-Toggle
- Klare Fehlermeldungen ohne Tech-Jargon ("Passphrase passt nicht" statt "Argon2id KDF mismatch")
- Pflicht-Bestätigungen vor irreversiblen Aktionen (Logout: 1 Bestätigung, Account-Löschen: 2 Bestätigungen)
- Backup-Setup ist Pflicht beim Anonym-Anlegen — nicht überspringbar (sonst Story US-10 wird sofort relevant)

### Accessibility (WCAG AA)
- Alle Buttons ≥ 48 dp Touch-Target
- Kontrast Normtext ≥ 4.5:1, grosse Schrift ≥ 3:1 (siehe `rules/designer.md`)
- Sign-In-Screen mit Screen-Reader navigierbar, semantische Labels für alle Interaktiven
- Passphrase-Stärke-Indikator nicht nur per Farbe (rot/gelb/grün), sondern auch per Text und Form

### i18n
- Alle User-facing-Strings über `AppLocalizations` (`lib/l10n/app_de.arb` + generated)
- Phase 1 nur `de`, aber Strings in ARB ausgelegt für spätere `en`/`fr`/`it`-Erweiterung
- Provider-Namen ("Google", "Apple") bleiben unübersetzt (Eigennamen)

### Offline-Tauglichkeit
- App startet ohne Netz mit gecachter Session (siehe AK-7)
- Trainingsmodi (Sniper, Finisseur) ohne Netz nutzbar wie bisher
- Sign-In-Versuche ohne Netz: klare Fehlermeldung statt Endlos-Spinner (siehe AK-18)
- Token-Refresh-Versuche im Hintergrund offline: silent-fail, Retry beim nächsten Online-Tick

## MVP-Scope (nur MUST)

US-1, US-2, US-3, US-4, US-5, US-6, US-7, US-8, US-9, US-13, US-14, US-18, US-19, US-20 — also vollständige Auth-Funktionalität für beide Pfade inkl. Restore, Upgrade, Logout, Account-Löschen, Token-Sicherheit, Verbindungsfehler-Handling, Disclaimer beim Anonym-Anlegen und Onboarding-Tour nach erstem Sign-In.

## Nice-to-have (SHOULD/COULD)

- US-10 (Backup-Warnung) — SHOULD, leicht ergänzbar in einem Sub-Task
- US-12 (Passphrase ändern) — SHOULD, eigener kleiner Sub-Task
- US-15 (Account-Status-Badge) — SHOULD, UI-Polish
- US-17 (internes Logging) — SHOULD, eigener Sub-Task der über alle Auth-Events geht
- US-11 (QR-Export Private-Key) — COULD, Power-User-Feature, Phase-2
- US-16 (Organizer-Hinweis) — COULD, kommt mit Tournament-Feature ohnehin

## Klärungen (Owner-Entscheidungen — 2026-05-04)

Alle initial offenen Fragen sind beantwortet:

1. **Onboarding-Reihenfolge**: **Sign-In zuerst, Onboarding-Tour danach.** Onboarding-Flow läuft erst nach erfolgreichem ersten Sign-In auf einem Gerät. Sign-In-Screen muss bei Anonym-Pfad den Disclaimer aus AK-19 zeigen. → siehe US-20 (AK-20) und US-19 (AK-19).
2. **OAuth-Integration-Pfad**: **Supabase-SDK nativ** (alles über `supabase_flutter`'s OAuth-Methoden, kein direktes `google_sign_in`/`sign_in_with_apple` für Phase 1). Weniger Code, eine Code-Quelle für alle Auth-Flows.
3. **Apple-Sign-In**: **nur auf iOS-Build aktiv.** Auf Android wird der Apple-Button gar nicht angezeigt. Auf iOS sind Google + Apple beide sichtbar.
4. **Account-Löschen**: **Hard-Delete** (kompletter Cascade über alle Tabellen, siehe AK-13). Keine Soft-Delete-Logik in v1.
5. **Mehrere Accounts auf einem Gerät**: **Single-Account.** Kein Switcher. "Account wechseln" = Logout + neuer Sign-In. drift-Tabelle `cached_auth_session` hält maximal eine Zeile.
6. **Passphrase-Recovery**: **keine.** Wer Passphrase vergisst, verliert Account. UI muss prominent auf diesen Fakt hinweisen (AK-19) und OAuth-Upgrade (US-5) als Empfehlung im Settings sichtbar halten.
7. **Cooldown bei Restore-Fehlversuchen**: **clientseitig** (30 s nach 3 Fehlversuchen pro `nickname_hash`). Serverseitiges Rate-Limit kommt mit der Hetzner-Setup-Härtung als separater Owner-Task, nicht in diesem Feature.
8. **Lokales Profil vs Cloud-Profil — Owner-Entscheidung 2026-05-04 (Phase-2.2-Checkpoint)**: **Interpretation B — Auth wird Pflicht, kein lokales-only-Profil.** Die `players`-drift-Tabelle entfällt; Profile-Daten leben ausschliesslich in Supabase `user_profiles`. Die App ist beim ersten Start ohne Online-Verbindung nicht nutzbar (Sign-In erforderlich). Nach erstem Sign-In wird `cached_auth_session` mit `display_name` und `avatar_color` befüllt — damit ist Offline-Nutzung möglich. **Da die App noch nicht live ist, gibt es keinen Migrations-Pfad für bestehende Lukas-Dev-Daten** — Sessions in dev-DBs werden in der drift v4-Migration gedroppt. F2-Code (PlayerRepository, current_profile_provider, onboarding_screen, profile_screen Edit-Mode) wird im Rahmen dieses Features ersetzt.
9. **UI-Implementierungs-Workflow — Owner-Regel 2026-05-04 (Phase-2.2-Checkpoint)**: **Kein UI wird direkt implementiert.** Jeder UI-Task (Screen, Popup, Dialog, Widget unter `lib/**/presentation/` oder `lib/core/ui/`) wird im Sprint-Plan zwingend mit einem **vorgeschalteten Design-Template-Request-Schritt** versehen. Der Request enthält eine Beschreibung was designed werden muss, mit User-Story-Bezug, Constraints, abzudeckenden States. Owner produziert das Template via Claude Design (separater Cloud-Prozess). Implementierung startet **erst nach Eingang des Templates**. Empfehlung: alle UI-Templates der M5-Phase werden zu Beginn des Implementierungs-Loops als **gebündelter Batch-Request** ausgegeben, damit Owner sie in einer Claude-Design-Session produzieren kann.

## Offene Fragen

(keine)
