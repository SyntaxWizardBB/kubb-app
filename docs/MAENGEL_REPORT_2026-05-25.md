# Mängel-Report — 2026-05-25

Manueller Walk-through der Tournament/Team-Flows auf zwei Emulatoren.
Owner-Feedback nach erster Live-Testsession des Sprint-2/Sprint-3-Stands
(`origin/main` bei `f6e35ef`).

## Schweregrad-Skala

- **P0** — Blockiert die Funktion komplett, App unbrauchbar in dem Flow.
- **P1** — Funktioniert teilweise, aber wesentliche Lücke; UX kaputt.
- **P2** — Feature fehlt oder ist nicht spec-konform; Workaround möglich.
- **P3** — Polish, Konsistenz, Look-and-Feel.

---

## 1. UI/UX — fehlender roter Faden (P3)

**Beobachtung:** Die App fühlt sich grafisch unfertig an: zu wenig
Farbe, zu wenig Hierarchie, kein durchgängiger Style zwischen den
Feature-Bereichen. Komponenten-Bibliothek (`KubbTokens`, Buttons,
Cards) existiert, wird aber nicht überall ausgereizt.

**Was fehlt:**
- Visuelle Differenzierung der Bereiche (Match / Tournament / Team /
  Season) durch konsistente Akzentfarben oder Icon-Sets.
- Klare Status-Visuals — Chips wirken alle gleich.
- Empty-States mit Bild/Illustration statt nur Text.

**Empfehlung:** Eine UI/UX-Iteration mit fokussiertem Brief (Style-Tile
+ Komponenten-Audit). Existierender Design-Brief unter
`docs/plans/auth-oauth-keypair/design-brief.md` zeigt das Pattern — für
Tournament/Team/Season fehlt das Pendant.

---

## 2. Teams ↔ Gruppen: Duplikation + Liga-UI (P2)

**Beobachtung:** Die Flows "Team erstellen" und "Gruppe erstellen"
führen praktisch zum selben Ergebnis. Das verwirrt und bläht die UI auf.

**Konkrete Punkte:**
1. **"Gruppen erstellen" entfernen** — das ist redundant zu "Team
   erstellen". Single Source of Truth ist das Team.
2. **Liga-Feld:** zeigt aktuell `(optional)` an, aber das Feld lässt
   sich gar nicht befüllen / hat keinen Input. Entweder die
   Beschriftung weg, oder echte Eingabe + sinnvolle Auswahl
   einbauen.
3. **Liga-Klassen:** hinter das Liga-Feld einen kurzen Beschrieb
   ("Profis / Semi-Profis / Spaß-Spieler" o.ä.) als Hilfetext oder
   Tooltip. Idealerweise als enum-Selector statt Freitext.
4. **Keyboard-Overflow:** wenn die Software-Tastatur erscheint, läuft
   das Form unten über den Rand. Form muss in einen `Scrollable` und
   mit `viewInsets.bottom` gepuffert werden.

**Code-Hinweise:**
- Team-Create-Screen: `lib/features/team/presentation/` — relevantes
  Form-Widget identifizieren und `SingleChildScrollView` + `padding:
  EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom)`
  einziehen.
- "Gruppen erstellen": Route + Screen entfernen, Aufrufer auf
  Team-Create umlenken.

---

## 3. Team anlegen schlägt still fehl (P0)

**Beobachtung:** Aus dem Team-Create-Screen führt das Absenden zu
keinem sichtbaren Ergebnis — kein Erfolg, kein Fehler, kein
Toast/SnackBar. Vermutlich DB-Seitig ein Problem, aber die UI
schluckt den Fehler.

**Reproduktion fehlt:** kein Stack-Trace, kein RPC-Log.

**Diagnose-Schritte:**
1. Im Team-Create-Submit-Handler einen `debugPrint`/`Telemetry`-Call
   einziehen, der die Exception der RPC mitloggt (Vorbild:
   `match_result_screen.dart::_submit`'s catch-Block).
2. Lokales Postgres-Log prüfen (`supabase logs db` oder Studio-Logs).
3. Schauen, ob `team_create` in [supabase/migrations/20260615000002_team_rpcs_a.sql](supabase/migrations/20260615000002_team_rpcs_a.sql)
   alle erwarteten Parameter hat und ob der Client-Aufruf in
   [lib/features/team/data/team_repository.dart](lib/features/team/data/team_repository.dart)
   die Parameter-Namen genau matched (klassischer
   `p_status` vs. `p_status_filter`-Fehler).

**Akzeptanzkriterium:**
- Submit erzeugt entweder einen Team-Eintrag *oder* eine sichtbare
  Fehlermeldung. Nie still schlucken.

---

## 4. Teilnehmer-Anzahl — Numpad-Eingabe (P2)

**Beobachtung:** Beim Tournier-Setup werden `min_participants` /
`max_participants` (vermutlich aktuell als Slider oder Stepper)
nicht direkt als Zahl per Numpad eingegeben.

**Erwartung:** Numerischer Input mit `TextInputType.number` und
Validation (siehe Migration: `min >= 2`,
`max in [min, 200]`, jeweils smallint).

**Code-Stelle:** `lib/features/tournament/presentation/tournament_setup_wizard.dart`
(bzw. der Wizard-Step für Capacity).

Gleiche Anforderung für **`max_sets`** und **`sets_to_win`** im
Match-Format-Step — siehe Punkt 6.

---

## 5. KO-Phase als Pflicht (P1)

**Beobachtung:** Spec-konform muss jedes Tournier mindestens eine
KO-Phase haben — "ohne ist es kein Tournier".

**Aktueller Stand:** Server akzeptiert Formate ohne KO
(`round_robin`, `swiss`, `schoch`) — das sollten **nur** Vorrunden
sein, gefolgt von Pflicht-KO.

**Was zu tun ist:**
1. UI: Wizard erzwingt eine KO-Konfiguration; reine Vorrunden ohne
   KO sind nicht wählbar.
2. Server (Migration 20260525000002): das `p_format`-Whitelist soll
   nur noch die `*_then_ko`-Varianten zulassen (oder die
   reinen Formate intern auf "+KO" mappen, falls Owner das so will).
3. Tiebreaker-Order auf KO-Phase ausgerichtet defaulten.

---

## 6. Schweizer-System (Schoch) — UI-Erklärung + Numpad (P1)

**Beobachtungen:**
- **Round-Robin vs. Schweizer-System:** "round robin" ist Jeder-gegen-
  Jeden in beliebiger Reihenfolge — das ist *nicht* das Schweizer
  System. Letzteres ist in der Spec verlangt mit Buchholz / Sonneborn-
  Berger / Median-Buchholz / etc.
- **Implementierung:** Server hat `pair_round_swiss` (Migration
  20260801000001) und `tournament_pool_standings` (jetzt frisch
  ergänzt) — aber im Setup-Wizard fehlt der zugehörige Wizard-Step,
  und die UI erklärt das System nicht.
- **Spec-Quelle:** [docs/specs/tournament-mode-spec.md](docs/specs/tournament-mode-spec.md) (sofern dort die
  Buchholz-Formeln stehen) als Referenz für Tiebreaker-Reihenfolge.
- **Numpad-Eingabe für `max_sets` / `sets_to_win`:** beide derzeit
  vermutlich als Stepper. Auf direkte Zahleneingabe umstellen.

---

## 7. Tournierformat-Kacheln mit Erklärung (P2)

**Beobachtung:** Beim Format-Picker (Single-Elim / Round-Robin /
Schweizer / Schoch / ...) wird nur der Name gezeigt — wer nicht aus
der Turnier-Szene kommt, weiß nicht was die Wahl bewirkt.

**Erwartung:** Jede Kachel enthält neben dem Titel ein 1–2-Zeilen-
Erklärung:
- *Single-Elimination* — KO-Baum, ein Verlust = raus.
- *Round-Robin* — Jeder spielt gegen jeden, danach KO.
- *Schweizer System* — N Runden mit Pairing nach Punktstand; Buchholz
  als Tiebreaker.
- *Schoch* — Variante des Schweizer Systems mit modifizierten
  Pairing-Regeln.
- ...

Texte aus [docs/specs/tournament-mode-spec.md](docs/specs/tournament-mode-spec.md) übernehmen für
Konsistenz.

---

## 8. Doppel-KO als Option (P2)

**Beobachtung:** Spec sieht Doppel-Elimination als Option vor — User
soll im KO-Step einen Switch "Doppel-KO" haben.

**Was fehlt:**
- UI: Checkbox/Switch in `wizard_ko_config_step.dart`.
- Datenmodell: `match_format_config.ko.bracket_type ∈
  {single_elimination, double_elimination}`.
- Server: `_fn_compute_ko_bracket` (Migration 20260601000014) muss
  Doppel-KO unterstützen — aktuell vermutlich nur single. Großer
  Brocken (Loser-Bracket, Grand-Final-Logik).

**Priorität:** P2 — nice-to-have, kann nach P0/P1-Fixes kommen.

---

## 9. `authentication required` beim Tournier-Create (P0)

**Beobachtung:** Tournier anlegen wirft Postgres-Fehler
`authentication required` (ERRCODE 42501).

**Analyse:**
- Server-Code in [supabase/migrations/20260525000002_tournament_lifecycle_rpcs.sql:40-43](supabase/migrations/20260525000002_tournament_lifecycle_rpcs.sql#L40-L43)
  wirft den Fehler exakt dann, wenn `auth.uid()` `NULL` ist —
  also wenn die JWT-Session beim Server fehlt.
- **Es gibt aktuell *kein* Organizer-/Admin-Berechtigungssystem.**
  Jeder authentifizierte User darf Tourniere erstellen. Die
  RLS-Policies + RPC-Checks sind ausschließlich "eingeloggt /
  nicht eingeloggt".
- Heißt: Du hast **keine fehlende Berechtigung**, sondern deine
  **Session ist nicht beim Server angekommen**.

**Wahrscheinliche Ursachen (in Reihenfolge zu prüfen):**
1. JWT-Token expired und Refresh schlug fehl — UI zeigt aber noch
   eingeloggten Zustand.
2. Anonymer (Keypair-)Account-Pfad: das Token wird beim Anonymous-
   Signup zwar erstellt, aber bei späteren Requests nicht
   mitgeschickt — möglicher Riverpod/SupabaseClient-Init-Bug.
3. Race zwischen Login-Flow und Tournament-Create-Tap: User klickt
   schneller als das Bootstrap die Session aus
   `cached_auth_session` lädt.

**Fix-Schritte:**
1. Im Tournament-Repository-Submit den Caller-User aus
   `Supabase.instance.client.auth.currentSession` loggen, bevor
   die RPC abgeht — dann sieht man sofort ob Session da ist.
2. Wenn `currentSession == null`, in der UI explizit "Bitte erneut
   anmelden" zeigen statt die RPC blind zu starten.
3. Im Auth-Telemetry-Flow nach `refreshFailure`-Events suchen
   (Pattern: `AuthEvent.refreshFailure`).

**Sekundär — Owner-Wunsch nach Admin-Rollen:**
Wenn nur bestimmte User Tourniere erstellen dürfen sollen, ist das
ein neues Feature und braucht:
1. Tabelle `public.user_roles` mit `(user_id, role text)` und Enum-
   Check `role IN ('admin','organizer','user')`.
2. RLS-Policies + RPC-Checks: `tournament_create` prüft
   `EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_caller AND
   role IN ('admin','organizer'))`.
3. Admin-Rolle vergeben: per Supabase-Studio direkt in die Tabelle
   schreiben, ODER ein `admin_grant_role(p_target uuid, p_role
   text)`-RPC, das selbst nur von Admins aufrufbar ist (Bootstrap-
   Admin per Migration setzen).
4. UI: Tournament-Create-Button nur sichtbar bei rolle ≠ `user`;
   sonst nur "Tournier suchen".

→ Entscheidung Owner: behalten wir "jeder darf Tourniere erstellen"
   oder kommt das Rollen-System? Falls letzteres, wird das eine
   eigene Sprint-Geschichte mit eigenem Plan.

---

## Zusammenfassung & Vorschlag Reihenfolge

| # | Mangel | Priorität | Aufwand |
|---|---|---|---|
| 9 | Session-Bug beim Tournier-Create | **P0** | S–M |
| 3 | Team-Create still failing | **P0** | S |
| 5 | KO-Phase erzwingen | **P1** | M |
| 6 | Schweizer System UI + Numpad | **P1** | M |
| 2 | Teams ↔ Gruppen entwirren | **P2** | M |
| 4 | Numpad für Teilnehmer-Anzahl | **P2** | S |
| 7 | Format-Kacheln mit Erklärung | **P2** | S |
| 8 | Doppel-KO Option | **P2** | L |
| 1 | UI/UX-Iteration | **P3** | L |

**Empfehlung:** P0-Bugs (3, 9) zuerst — sonst kann Owner gar nicht
sinnvoll weitertesten. Dann P1 (5, 6) als Spec-Compliance. P2 und P3
parallel mit der UI/UX-Iteration bündeln.

---

## Offene Fragen an den Owner

1. **Admin-Rollen-System einführen?** (siehe Punkt 9, Sekundär)
2. **Doppel-KO als MVP-Feature** oder Backlog für später?
3. **"Liga"-Feld bei Teams:** Freitext oder feste Enum-Werte
   (Profi/Semi/Spaß)?
4. **`round_robin` ohne KO** komplett abschaffen, oder als
   Liga/Stadt-Meisterschafts-Variante behalten?
