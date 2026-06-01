# P6 — Tournament-Registrierung: Bug-Suche Runde 2 (Konsolidierung)

**Datum:** 2026-06-01
**Ausgangslage:** Die RPCs (`tournament_register_single`, `tournament_register_team`) bestehen direkte DB-Proben (psql / PostgREST über Kong mit echtem authenticated JWT → `200 {"participant_id": ...}`). Trotzdem schlägt die Anmeldung in der laufenden App fehl. Vier Spezialisten haben die Layer `fresh_migration_chain`, `client_flow`, `auth` und `rpc_contract` untersucht. Drei davon schließen die eigene Schicht als Ursache aus; alle drei zeigen auf dieselben zwei Achsen: **(1) leere/zurückgesetzte lokale DB** und **(2) ein echter Client-Routing-Bug bei Team-Turnieren**.

---

## Rang 1 — ENVIRONMENTAL: Lokale DB wurde zurückgesetzt → leer (Daten-Verlust, nicht Code)

**Wahrscheinlichste Ursache für „Anmeldung tut nichts / schlägt fehl" im Solo-Fall.**

**Evidenz:**
- Der `auth`-Layer beobachtete den Reset live: Counts fielen von 2 Usern / 5 Turnieren auf 0/0; `supabase_db_kubb-app-local` hatte einen frischen `StartedAt`, während alle anderen Container „Up 5 hours" waren.
- Bestätigung in dieser Konsolidierung: `docker ps` zeigt `supabase_db_kubb-app-local … Up 2 minutes (healthy)` (erneut neu gestartet), `supabase_auth` + `supabase_realtime` „Up About a minute" — der Rest „Up 5 hours".
- DB-Inhalt aktuell: `public.tournaments = 0`, `auth.users = 1` (nur der Probe-User).
- Folge: Jede Turnier-Liste ist leer, und jeder `tournament_register_single`/`_team`-Aufruf gegen eine zuvor gesehene Turnier-ID liefert **P0002 „tournament not found"** (live reproduziert). Das sieht exakt aus wie „Registrierung schlägt fehl", ist aber Datenverlust durch den Reset — keine psql-`set_config`-Probe gegen eine frische ID kann das je reproduzieren, weil die Probe ihre eigene Turnier-ID seedet.

**Fix (Umgebung, kein Code):**
1. Sicherstellen, dass die App auf diesen Stack zeigt und der Stack steht: `supabase status` (im `KubbProj/`-Verzeichnis).
2. Daten neu seeden — die App erwartet existierende Turniere. Über die App ein Turnier anlegen+publishen, oder Seed-SQL/`supabase db reset` mit Seed ausführen. Danach gegen eine **frisch erzeugte** Turnier-ID anmelden.
3. Prüf-Kommando für den Daten-Zustand:
   ```bash
   docker exec supabase_db_kubb-app-local psql -U postgres -c \
     "select count(*) from public.tournaments; select count(*) from auth.users;"
   ```
   Liefert `0` Turniere → Symptom erklärt; neu seeden.

---

## Rang 2 — CODE-BUG: Team-Turniere navigieren auf eine nicht existierende Route (harter Dead-End)

**Sichere Ursache für „nichts passiert / kaputter Screen", sobald ein User mit Team ein Team-Turnier (teamSize > 1) anmelden will.**

**Evidenz:**
- `tournament_registration_screen.dart:217-218` ruft `context.pushReplacement('/tournament/${tournamentId.value}/register/team')`.
- In `router.dart` existiert nur `path: '/tournament/:id/register'` (`router.dart:459`) — **kein** `/register/team`. `RegisterTeamScreen` wird außerhalb seiner eigenen Datei nirgends referenziert (toter Code).
- `errorBuilder` in `router.dart`: **0 Treffer** (`grep -c errorBuilder router.dart` → 0). Ohne Error-Builder zeigt GoRouter seine Default-Fehlerseite / leeren Screen.

**Fix:**
- Die Route `'/tournament/:id/register/team'` in `router.dart` neben `:id/register` registrieren und auf `RegisterTeamScreen` mappen. Anschließend prüfen, dass `RegisterTeamScreen` die gleichen Params (tournamentId, team) erhält wie der Dead-End-Push erwartet.
- Zusätzlich einen `errorBuilder` in `router.dart` ergänzen, damit künftige Routing-Fehler nicht stumm als leerer Screen erscheinen.

---

## Rang 3 — CODE/UX: Status-Fenster `published` bietet „Anmelden", RPC lehnt ab

**Verwirrende Fehlermeldung (kein Stillschweigen), nur über Legacy-`published`-Zeilen erreichbar.**

**Evidenz:**
- `tournament_detail_screen.dart:388-389` zeigt „Anmelden" sowohl für `registrationOpen` als auch für `published`.
- Live raised `tournament_register_single` für jeden Status `<> 'registration_open'` ERRCODE 22023 „registration is not open".
- Auf dieser DB springt `tournament_publish` direkt auf `registration_open`, das Fenster ist also nur über Legacy-`published`-Daten erreichbar. Fehler wird per roter Snackbar (`tournament_registration_screen.dart:137-138`) angezeigt — nicht verschluckt.

**Fix:**
- Den „Anmelden"-Button im Detail-`_Actions` ausschließlich für `status == registrationOpen` aktivieren (das `published`-Oder entfernen), konsistent mit dem List-Tile-Gate (`tournament_list_screen.dart:101`).

---

## Rang 4 — LATENT: Migrations-Ledger-Drift (zum Zeitpunkt der Suche; jetzt reconciliert)

**War zum Untersuchungszeitpunkt ein latentes Risiko, ist durch den Reset reconciliert — keine Laufzeit-Ursache.**

**Evidenz:**
- Drei Layer fanden: `schema_migrations` hatte **91** Zeilen (max `20261201000032`), während Disk **93** Files hat; fehlend waren genau die registrierungs-kritischen `20261201000040_tournament_open_registration_model` und `20261201000050_tournament_reregister`. Die Funktions-Bodies enthielten die `…40/…50`-Logik trotzdem (out-of-band per `CREATE OR REPLACE` appliziert).
- `fresh_migration_chain` bewies: Ein sauberer Replay aller 93 Files in einer Shadow-DB läuft **fehlerfrei** durch; die letzte Definition (`…50` reactivate-or-insert) gewinnt, Unique-Index `tournament_participants_unique_user (tournament_id, user_id)` und `GRANT EXECUTE … TO authenticated` werden korrekt erzeugt.
- Konsolidierung jetzt: Nach dem Reset zeigt das Ledger **93** Zeilen, max `20261201000050` — Drift ist behoben.

**Fix:**
- Bereits reconciliert. Künftig: nach manuellen `CREATE OR REPLACE`-Hotfixes immer `supabase db reset` (oder Ledger-Eintrag) nachziehen, damit Disk und Ledger synchron bleiben.

---

## Ausgeschlossene Layer (mit Beweis)

- **`rpc_contract`**: RPC-Namen, Params, Return-Shapes, Roster-JSON-Keys und Status-Wire-Mapping (`confirmed→approved` etc.) stimmen statisch und live überein. `tournament_register_single` liefert unter echtem JWT `{"participant_id": …}`, korrekt geparst bei `tournament_repository.dart:331`. `auth.uid()` non-null.
- **`auth`**: Volle Auth-Kette end-to-end bewiesen. Edge-Runtime up, `keypair-verify` antwortet; `SUPABASE_INTERNAL_JWT_SECRET`-SHA256 == `GOTRUE_JWT_SECRET` → HS256-Token valide signiert; PostgREST akzeptiert, `auth.uid()` non-null für Anon-Bootstrap und keypair-JWT.
- **`fresh_migration_chain`**: Sauberer 93-File-Replay fehlerfrei; SQL-Layer in beiden Pfaden (Reset und live) gesund.

### Latente Inkonsistenzen (flaggen, lokal nicht fatal)
- Edge-Funktion setzt `iss = http://kong:8000/auth/v1`, gotrue-Tokens nutzen `http://127.0.0.1:54321/auth/v1`. PostgREST validiert lokal `iss` nicht → ok; ein strikteres Gateway würde das keypair-JWT ablehnen.
- gotrue gibt inzwischen **ES256**-Tokens aus, keypair-verify mintet **HS256**. Beide lokal akzeptiert; bei Umstellung auf asymmetric-only Verifikation würde das Edge-HS256-Token mit 401 fehlschlagen → `auth.uid()` null. Beobachten.
- Auth-Token ohne Refresh-Token (`supabase_auth_adapter_impl.dart:139-189`): Läuft der selbst-signierte Access-Token ab, hängt das SDK den **stale Bearer** an → PGRST303 vor RPC-Ausführung. Recovery hängt an lebendiger `keypair-verify`-Edge-Runtime. Aktuell up, daher nicht die Ursache — aber der häufigste reale Trigger laut Memory („tote Edge-Runtime → Anmelden geht nicht").
