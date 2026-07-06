# Spec — Auth-Umbau: Admin-Dashboard, offenes Onboarding, Passwort-Login

**Status:** Verbindliche Implementierungs-Spezifikation & Quality-Gate (Draft zur Owner-Review).
**Geltung:** `lib/features/auth/`, `lib/features/player/`, neuer Kontext `lib/features/admin/`,
Auth-Migrationen, `config.toml`. Baut auf ADR-0010 (Keypair-Auth) und ADR-0042
(OAuth↔Keypair-Reconcile) auf.
**Owner-Entscheide (2026-07-06):** Admin-Dashboard **in der App**; Umfang = User-Liste+Suche,
Rechte vergeben/entziehen, Sperren/Löschen, Inbox-Nachricht, **Impersonation**; Passwort-Login
**GoTrue-nativ**; Passwort **Pflicht für neue Anon-Konten**.

> **MUSS** = harte Anforderung. `Datei:Zeile` sind Anker aus dem Ist-Stand (main, Scout 2026-07-06).
> **Training-Kontext (`lib/features/training/`) ist tabu** (CLAUDE.md) — dieser Umbau berührt ihn nicht.

---

## 0. Ist-Zustand (verifiziert — die drei Auslöser)

1. **Turnier-FAB hängt an Vereins-Rolle, NICHT an `can_found_clubs`.**
   `tournament_hub_screen.dart:38` → `canPublishTournamentProvider`
   (`organizer_team_providers.dart:33`) → RPC `organizer_team_caller_can_publish`
   (`20260901000016:360`): TRUE nur bei aktiver Mitgliedschaft mit Rolle
   ∈ {owner,admin,organizer}. Wer `can_found_clubs` hat, aber **noch keinen Verein**, sieht
   **keinen FAB**. Server `tournament_create` (`20261201000032:81`) prüft nur `auth.uid()` —
   das echte Gate ist rein Client-seitig.
2. **OAuth-Neulinge landen profillos auf Home** — kein Namens-Schritt, **keine `user_profiles`-Zeile**,
   `nickname = null`. Nur `keypair_register` legt Profile an (`20261001000003:84`); kein
   `auth.users`-Trigger. Deshalb ist der Einzelturnier-Gruppenname für OAuth-User heute unmöglich.
3. **Namensänderung + Eindeutigkeit existieren bereits vollständig** — `nickname citext UNIQUE`
   (`20260504000001:91`), Änderungs-RPC `fn_profile_update_with_hash` (`20260504000006`),
   Verfügbarkeits-RPC `profile_nickname_available` (`20261244000000`), Edit-UI
   `edit_profile_screen.dart`, Live-Check `nickname_availability_provider.dart`.
   → **Wird wiederverwendet, nicht neu gebaut.** OAuth-User erben es, sobald sie ein Profil haben.
4. **Admin gibt es fürs Frontend nicht** — nur service-role-`admin_*`-RPCs
   (`20260504000011`, unerreichbar aus der App) + ungenutzter `league_admin`-JWT-Claim.
5. **Passwort-Auth: null.** `user_credentials.kind` ∈ {oauth_google,oauth_apple,keypair}
   (`20260504000001:20`); GoTrue-E-Mail-Signup deaktiviert (`config.toml [auth.email] enable_signup=false`).

---

## 1. Kontomodell (Fundament aller Milestones)

Ein Konto = **eine** `auth.users`-Zeile + ein `user_profiles`-Row. Daran hängen **mehrere
Credentials** parallel (`user_credentials.kind`):

| kind | Zweck | Status |
|---|---|---|
| `keypair` | Passphrase-Recovery + Geräte-Wechsel (Ed25519) | existiert |
| `oauth_google`/`oauth_apple` | Social-Login | existiert |
| **`password`** *(neu, Kind erweitern)* | Alltags-Login via GoTrue (synthetische Adresse) | **M3** |

**MUSS-Invarianten:**
- Nickname bleibt der **einzige** menschliche Identifier und ist **unique (citext)**. Er ist der
  Anzeigename **und** — bei Einzelturnieren — der **Gruppenname** des Einzelteilnehmers (§M2.4).
- Neue Anon-Konten tragen ab M3 **immer** ein `password`-Credential **und** einen `keypair`-Backup.
- OAuth-Konten tragen `oauth_*` (+ optional später verlinkter keypair via ADR-0042) — **kein** Passwort.
- `user_credentials.kind`-CHECK additiv um `'password'` erweitern; Shape-Constraint anpassen
  (Password-Zeile hält weder `public_key` noch `oauth_subject`).

---

## 2. M1 — Rechte-Modell + Admin-Dashboard (in der App)

### 2.1 Server (MUSS)
- **Flag** `user_profiles.is_admin boolean NOT NULL DEFAULT false` (additive Migration). Erstes
  Setzen: einmalig manuell via SQL für den Owner (dokumentierter Bootstrap, kein UI-Henne-Ei).
- **Autoritäts-Helfer** `public.caller_is_admin()` (SECURITY DEFINER, STABLE): liest
  `is_admin` des `auth.uid()`. Basis für alle Admin-RPC-Gates **und** RLS.
- **Admin-RPCs** (SECURITY DEFINER, Gate `caller_is_admin()` → sonst 42501, GRANT `authenticated`):
  - `admin_list_users(p_query text, p_limit int, p_offset int)` → Liste (user_id, nickname,
    auth-kinds aus `user_credentials`, created_at, is_admin, can_found_clubs,
    gesperrt-Flag). Suche case-insensitiv auf nickname.
  - `admin_set_capability(p_user_id uuid, p_capability text, p_value boolean)` mit
    `p_capability ∈ ('can_found_clubs','is_admin')`. **MUSS** jede Änderung in
    `admin_audit_events` schreiben (actor, target, capability, old→new, at).
  - `admin_set_account_status(p_user_id uuid, p_status text)` mit `('active','suspended')`
    — Sperre setzt `user_profiles.suspended_at`; ein gesperrter User besteht kein Auth-Gate
    (§2.4). **Kein** Self-Suspend (Gate: `p_user_id <> auth.uid()`).
  - `admin_delete_account(p_user_id uuid)` — delegiert an bestehendes `admin_purge_account`
    (`20260504000011:134`), aber caller-gated statt service-role; audit-pflichtig; **kein Self-Delete**.
  - `admin_send_inbox(p_user_id, p_subject, p_body)` — dünner Wrapper um `admin_inbox_send`
    (`20260504000011:170`), caller-gated; audit-pflichtig.
- **`admin_audit_events`**-Tabelle (append-only, RLS: nur Admins lesen). Jede Admin-Mutation MUSS
  eine Zeile schreiben.
- **Bestehende `admin_*`-RPCs bleiben service-role** — die neuen `admin_*` sind die
  caller-gated Frontend-Fassade; keine bestehende Grant lockern.

### 2.2 Impersonation (MUSS — mit Schutzmaßnahmen)
Der Admin kann als Ziel-User agieren. Umsetzung sicher:
- **Edge Function `admin-impersonate`** (`verify_jwt = true`, im Body service-role-gate via
  `caller_is_admin()`-Check gegen die DB): mintet mit `_shared/jwt.ts` ein **kurzlebiges**
  (≤15 min, **kein** langes TTL) HS256-Token für `p_target_user_id`, mit Zusatz-Claim
  `impersonator_id = <admin>`. Ohne Refresh-Token (läuft bewusst ab).
- **MUSS Audit:** jede Ausstellung schreibt `admin_audit_events` (kind=`impersonation_start`,
  actor, target).
- **MUSS UI-Banner:** solange die Session ein `impersonator_id`-Claim trägt, zeigt **jeder** Screen
  ein persistentes, auffälliges Banner **„Du agierst als &lt;Nickname&gt; — [Beenden]"**; „Beenden"
  stellt die Admin-Session wieder her (Admin-Token vor dem Wechsel sichern).
- **Reichweite (D1 entschieden): VOLLE Session.** Der Admin agiert uneingeschränkt als Ziel-User —
  inkl. **sicherheitsrelevanter** Aktionen (Passwort setzen/ändern, Profil ändern, an-/abmelden,
  Punkte eintragen). Es gibt keine Aktions-Einschränkung; das Banner + der Audit-Log sind die
  Sicherung.
- **MUSS Grenzen:** ein Admin darf **keinen anderen Admin** impersonaten
  (`target.is_admin = false` erzwingen). Start und Ende der Impersonation werden in
  `admin_audit_events` protokolliert.

### 2.3 Client (MUSS)
- Neuer Kontext `lib/features/admin/` (presentation/application/data), Design-System-konform
  (`KubbTokens`, `KubbAppBar`, `KubbButton`, geteilte List-Widgets).
- **Sichtbarkeit:** Einstieg (Drawer-Eintrag „Admin") **nur** wenn `is_admin` (neuer
  `isAdminProvider`, gespeist aus dem Profil/JWT). Route `/admin` + `/admin/user/:id`.
- **User-Liste** mit Suchfeld (debounced), pro Zeile: Namen, Auth-Arten, Rechte-Toggles
  (`can_found_clubs`, `is_admin`), Aktionen (Sperren/Löschen mit Bestätigungs-Dialog,
  Nachricht senden, **Impersonate**).
- Alle Mutationen über die M1-RPCs; optimistisches UI mit Fehler-Rückabwicklung.

### 2.4 Auth-Gate für gesperrte Konten (MUSS)
- `suspended_at IS NOT NULL` → Login/Token-Mint (keypair-verify, password, oauth-reconcile) **MUSS**
  ablehnen (klare Meldung „Konto gesperrt"), und ein bereits eingeloggter gesperrter User wird beim
  nächsten Wire-Resign ausgeloggt.

### 2.5 Akzeptanzkriterien
- **A1** Nicht-Admin: kein Admin-Drawer, `admin_*`-RPC → 42501.
- **A2** Admin togglet `can_found_clubs` eines Users → in `admin_audit_events` genau eine Zeile;
  der User sieht danach ohne App-Neustart (Inbox-Invalidierung) die Veranstalter-Fähigkeit.
- **A3** Impersonation: Token ≤15 min, `impersonator_id`-Claim gesetzt, Banner auf jedem Screen,
  „Beenden" stellt Admin wieder her; Ziel = anderer Admin → RPC lehnt ab.
- **A4** Gesperrter User kann sich nicht (neu) einloggen; laufende Session endet beim Resign.

---

## 3. M2 — Onboarding vereinheitlichen + FAB-Fix

### 3.1 OAuth-Profil-Setup (MUSS)
- **Router-Redirect „braucht Profil":** ist die Session authentifiziert, aber **kein
  `user_profiles`-Row** vorhanden (bzw. `nickname IS NULL`), leitet der Router **jede** Route
  auf einen neuen `/onboarding/profile`-Screen um (analog zum bestehenden
  `session.isAuthenticated`-Redirect `router.dart:204`). Kein Zugriff auf die App ohne Profil.
- **Screen `/onboarding/profile`**: exakt der **Nickname-Sub-Step aus
  `anonymous_signup_flow.dart` (`_Step.nickname`)** wiederverwendet (Live-Verfügbarkeits-Check +
  Avatar-Farbe) — **ohne** Passphrase/Mnemonic-Steps. Speichern legt das Profil an:
  neuer RPC `profile_create_for_current_user(p_nickname, p_avatar_color)` (SECURITY DEFINER,
  `auth.uid()`-Gate, unique-Check, füllt `user_profiles`, `can_found_clubs = false`).
- **Nickname änderbar/unique:** bereits vorhanden (`fn_profile_update_with_hash` +
  `edit_profile_screen`) — für OAuth-User nach der Anlage sofort nutzbar, **kein Neubau**.

### 3.2 FAB/`tournament_create` auf `can_found_clubs` erweitern (MUSS)
- **Client:** Der Turnier-FAB (`tournament_hub_screen.dart:38`) MUSS sichtbar sein bei
  `organizer_team_caller_can_publish` **ODER** `can_found_clubs`. Sauberste Umsetzung: neuer
  RPC/Provider `caller_can_create_tournament` = `can_found_clubs OR organizer_team_caller_can_publish`;
  FAB und Home-Kachel hängen daran.
- **Server (Defence-in-depth, MUSS):** `tournament_create` (`20261201000032`) re-based —
  der bisher fehlende Berechtigungs-Check wird nachgezogen: **erstellen darf nur, wer
  `can_found_clubs` hat ODER Veranstalter-Rolle**. (Heute darf serverseitig jeder — das ist ein
  stiller Bug, den wir hier schließen.) Der optionale `club_id`-Pfad-Check bleibt unverändert.

### 3.3 Passwort-Pflicht im Anon-Setup (MUSS, greift technisch in M3)
Der `anonymous_signup_flow.dart` bekommt vor dem Passphrase-Backup einen **Passwort-Step**
(§M3). Reihenfolge neu: **Nickname → Passwort → Passphrase-Backup → Ack/Register → Success**.

### 3.4 Einzelturnier-Gruppenname (MUSS)
- Im Einzelturnier ist der **Account-Nickname** der Gruppen-/Teilnehmername. Da OAuth-User nun
  garantiert ein Profil haben (§3.1) und `tournament_get`/Ranglisten bereits
  `COALESCE(nickname, team)` projizieren (Fix aus `20261332000000`), ist dies mit dem Profil-Zwang
  **automatisch erfüllt** — **MUSS** per Akzeptanztest abgesichert werden (kein UUID/leerer Name
  mehr im Einzel).

### 3.5 Akzeptanzkriterien
- **B1** Frischer Google-Login → landet auf `/onboarding/profile`, **nicht** auf Home; nach
  Namenswahl existiert `user_profiles` und die App ist erreichbar.
- **B2** User mit `can_found_clubs` **ohne Verein** sieht den „+ Neues Turnier"-FAB und kann ein
  (club-loses) Turnier anlegen; ein User ohne beides sieht ihn nicht und `tournament_create` → 42501.
- **B3** Einzelturnier: der Einzelteilnehmer erscheint überall mit seinem Nickname als Gruppenname.

---

## 4. M3 — Username + Passwort (GoTrue-nativ)

### 4.1 Prinzip
Passwort-Login läuft über **GoTrue E-Mail+Passwort** mit **synthetischer Adresse**
`&lt;nickname-slug&gt;@login.kubbclub.ch` (kein echtes Postfach). GoTrue liefert Hashing,
Rate-Limits, Refresh-Token-Rotation gratis.

### 4.2 Config/Server (MUSS)
- `config.toml [auth.email] enable_signup = true`, **`enable_confirmations = false`**,
  `double_confirm_changes = false` — Bestätigungs-Mails MÜSSEN aus bleiben (synthetische Adresse).
  Auf prod dieselbe Einstellung setzen.
- **Domain-Reservierung:** die Login-Domain gehört ausschließlich diesem Kunstgriff; Nutzer geben
  **nie** eine E-Mail ein, nur ihren Nickname → die App bildet die Adresse deterministisch.
- **`user_credentials.kind` um `'password'` erweitern** (additive Migration; Shape-Constraint).
- **Adresse an `user_id` gebunden (D3 entschieden):** die synthetische GoTrue-Adresse ist
  `&lt;user_id&gt;@login.kubbclub.ch` — **unveränderlich**, damit ein Nickname-Rename den
  Passwort-Login **nicht** berührt (kein `auth.users.email`-Update bei jedem Rename). Der
  Nutzer gibt beim Login den **Nickname** ein; die App schlägt daraus `user_id` nach (neuer
  RPC `password_login_email_for_nickname(p_nickname)` → gibt die synthetische Adresse zurück,
  ohne Existenz-/Passwort-Info zu leaken) und ruft `signInWithPassword` mit der Adresse.

### 4.3 Client (MUSS)
- **Setup:** neuer Passwort-Step im `anonymous_signup_flow` (Mindestlänge, Bestätigungsfeld,
  Stärke-Hinweis). Registrierung = `signUp(email: synthetic, password)` **oder** (bei bereits
  anonymer Session) `updateUser(email, password)`, danach `keypair_register` wie bisher.
- **Login-Screen:** `sign_in_screen.dart` bekommt neben „Mit Google" / „Gast" / „Wiederherstellen"
  einen **Nickname+Passwort-Login** → `signInWithPassword(email: synthetic(nickname), password)`.
- **Passwort ändern/setzen** in `edit_profile_screen`/Settings via `updateUser(password:)`.
- **Bestehende Konten** (ohne Passwort, vor M3 angelegt) MÜSSEN weiter per Passphrase funktionieren
  und können in den Einstellungen **nachträglich** ein Passwort setzen (kein Zwangs-Backfill).

### 4.4 Akzeptanzkriterien
- **C1** Neues Anon-Konto: Setup erzwingt Passwort; danach Logout → Login mit Nickname+Passwort
  gelingt; Passphrase-Restore gelingt weiterhin.
- **C2** Falsches Passwort → klare Fehlermeldung; GoTrue-Rate-Limit greift.
- **C3** Nickname-Rename lässt den Passwort-Login weiter funktionieren (gemäß D3-Entscheid).
- **C4** Alt-Konto ohne Passwort: Passphrase-Login unverändert; Passwort in Settings nachrüstbar.

---

## 5. M4 — Early-Access-Gate entfernen (NACH M1)

- **Voraussetzung:** M1 (Admin) steht — sonst gibt es keinen Weg, Rechte zu vergeben.
- **Client:** `early_access_entry_screen.dart` aus dem Flow nehmen; `sign_in_screen` wird der
  Einstieg. Anon-Setup ruft `keypair_register` **ohne** Code.
- **Server (MUSS, additive Migration):** `keypair_register` re-based — der
  `validate_early_access_code`-Zwang (`20261001000003:67`) entfällt; `can_found_clubs` startet
  **immer** `false` (Veranstalter-Recht kommt künftig nur vom Admin). Die Code-Funktionen
  (`early_access_*`, `validate_early_access_code`) dürfen als tote, aber harmlose Artefakte bleiben
  oder in einer eigenen Migration entfernt werden (nicht kritisch).
- **Registrierung ist danach offen** — jeder kann ein Konto anlegen; erhöhte Rechte vergibt der Admin.
- **Akzeptanz D1:** Ohne Code neues Konto anlegbar; neuer User hat `can_found_clubs=false` und keinen
  FAB, bis ein Admin das Recht vergibt.

---

## 6. Reihenfolge & Guardrails

**Empfohlene Reihenfolge:** M1 → M2 → M3 → M4 (M4 erst wenn M1 live ist; M3 vor M4 unkritisch,
aber der Passwort-Step im Setup gehört gebaut, bevor der Code-Step entfernt wird).

**Guardrails (jeder Umsetzungs-Block):** nur additive Migrationen, kein `supabase db reset`;
Proben in BEGIN/ROLLBACK; bei `CREATE OR REPLACE` jüngsten Body re-basen (Stale-Body-Diff);
Training-Kontext tabu; UI nur über Design-System + bestehende Bausteine; Nickname-Uniqueness/
-Änderung **wiederverwenden**, nicht neu bauen; ein Commit pro Block; unabhängig verifizieren
(git-Scope, analyze, Tests), Push nur auf Ansage.

---

## 7. Offene Entscheidungen (vor/spätestens bei der Umsetzung klären)

- **D1 — Impersonation-Reichweite:** ✅ **ENTSCHIEDEN — volle Session** inkl. Passwort/Security
  (§2.2). Alles im Namen des Users; Banner + Audit sichern ab.
- **D3 — Synthetische Login-Adresse:** ✅ **ENTSCHIEDEN — an `user_id`** gebunden (rename-fest, §4.2).
- **D5 — Offene Registrierung + Missbrauch:** ✅ **ENTSCHIEDEN — CAPTCHA vorerst zurückgestellt.**
  Erste Verteidigung = Supabase-Rate-Limits. Cloudflare Turnstile (Auth → Attack Protection) bleibt
  der bereitliegende Schalter für den öffentlichen/breiten Launch oder bei Missbrauch (~1–2 h Client).
- **D2 — Admin-Bootstrap:** Owner-`is_admin` einmalig per SQL (dokumentiert) — bestätigt?
- **D4 — Passwort-Pflicht rückwirkend?** Spec: **nein** (Alt-Konten optional nachrüsten). Bestätigen.
- **D6 — OAuth-Neu-User-Fork (ADR-0042):** Der `before-user-created`-Hook, der die zweite
  `auth.users`-Zeile verhindert, ist noch ungebaut. In M2 mitziehen oder separat? (Empfehlung:
  separat, ADR-0042 hat einen eigenen Plan.)
