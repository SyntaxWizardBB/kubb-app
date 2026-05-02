# Feature — Sniper-Training MVP

## Bounded Context

- **`training/`** (primär) — pragmatisch: Riverpod direkt zu drift, kein Domain-Package (per ADR-0002)
- **`player/`** (minimal CRUD) — anonymes lokales Profil (Name, DeviceId), keine Cloud-Verknüpfung in F1
- **`core/`** — drift-Setup, Theme aus ADR-0008, App-Settings-Persistenz

Cloud-Sync, Auth (ADR-0003), Live-Scoring (ADR-0007), Sync-Adapter (ADR-0005) sind in F1 explizit **nicht** involviert. Alles offline-lokal.

## User Stories

| # | Story | Priorität | Akzeptanzkriterien |
|---|-------|-----------|-------------------|
| US-1 | Als Trainierende:r möchte ich eine Sniper-Session starten und vorher Distanz (4–8 m, 0.5er-Schritte) sowie optional eine Ziel-Wurfzahl konfigurieren, damit ich gezielt eine Match-Distanz oder strukturierte Einheit üben kann. | MUST | siehe AC-1 |
| US-2 | Als Trainierende:r möchte ich während der Session pro Wurf mit einem Tap Hit, Miss oder Heli zählen — mit Korrektur-Möglichkeit über einen Minus-Tap pro Counter — damit ich im Trainings-Flow bleibe und Tippfehler korrigieren kann. | MUST | siehe AC-2 |
| US-3 | Als Trainierende:r möchte ich eine laufende Session entweder regulär beenden (mit Summary) oder aktiv abbrechen (mit Speichern/Verwerfen-Dialog), damit ich am Ende immer eine bewusste Entscheidung über die Session-Daten habe. | MUST | siehe AC-3 |
| US-4 | Als Trainierende:r möchte ich, dass eine durch App-Crash oder Force-Close unterbrochene Session beim nächsten App-Start als wiederherstellbar erkannt wird — mit den Optionen Fortsetzen / Speichern / Verwerfen — damit lange Trainings-Einheiten nicht verloren gehen. | MUST | siehe AC-4 |
| US-5 | Als Trainierende:r möchte ich beim ersten App-Start meinen Namen angeben, damit Sessions an mein Profil gebunden werden, und ich später diesen Namen in einem einfachen Profil-Screen einsehen kann. | MUST | siehe AC-5 |
| US-6 | Als Trainierende:r möchte ich auf dem HomeScreen einen prominenten FAB "Training" sehen, der ein Bottom-Sheet mit Modus-Auswahl öffnet, damit der Haupt-Aktionspfad sofort sichtbar ist. | MUST | siehe AC-6 |
| US-7 | Als Trainierende:r möchte ich auf dem HomeScreen meine letzten 3 Sessions sehen, plus eine Coming-Soon-Karte für den Tournier-Modus und einen Link zu kubbtour.ch, damit der Bildschirm informativ und vorausschauend wirkt. | MUST | siehe AC-7 |
| US-8 | Als Trainierende:r möchte ich App-Settings über ein Hamburger-Menü erreichen — Theme (Light/Dark/HighContrast), Heli-Tracking on/off, Vibration on/off — damit ich die App an meine Trainings-Bedingungen (Sonnenlicht, leise üben, ohne Heli) anpassen kann. | MUST | siehe AC-8 |
| US-9 | Als Trainierende:r möchte ich während der Session optional die Counter ausblenden ("Eye-Toggle"), damit ich blind trainieren kann und mich nicht von der Anzeige unter Druck setze. | SHOULD | siehe AC-9 |
| US-10 | Als Trainierende:r möchte ich nach Session-Ende einen SummaryScreen sehen mit Total/Hits/Misses/Trefferrate und den Optionen Speichern / Verwerfen / Neu starten, damit ich die Performance reviewe und entscheide. | MUST | siehe AC-10 |

## Akzeptanzkriterien (Given/When/Then)

### AC-1 — Sniper-Session konfigurieren und starten

- **Given** I am on the home screen with a player profile already created
- **When** I tap the FAB "Training" and select "Sniper-Training" from the sheet
- **Then** a configuration step opens (initial distance default 8.0 m, no throw target)
- **And** I can move a slider in 0.5 m steps within the inclusive range 4.0–8.0
- **And** I can optionally set a throw target (any positive integer ≤ 999, default empty)
- **And** confirming the configuration persists a new active session record in drift with status `active`, distance, optional target, profile id, and starts the session screen

### AC-2 — Würfe zählen mit Tap

- **Given** I am in an active Sniper session
- **When** I tap "Hit +"
- **Then** the hit counter increments by 1
- **And** if vibration is enabled in settings, `HapticFeedback.lightImpact()` fires
- **And** an event row of type `hit` is appended to the session in drift
- **And** the UI reflects the new counter value within 100 ms
- **When** I tap "Hit −"
- **Then** the hit counter decrements by 1, but never below 0
- **And** the most recent `hit` event for this session is marked deleted (soft delete with `corrected_at`) — counters always reflect non-deleted events
- **Same behavior for Miss and Heli (when Heli-Tracking is on)**

### AC-3 — Session beenden oder abbrechen

- **Given** I am in an active Sniper session with at least 1 throw recorded
- **When** I tap "Session beenden"
- **Then** the session screen transitions to the SummaryScreen (see AC-10) without further confirmation
- **When** I tap "Abbrechen" instead
- **Then** a dialog appears with options "Speichern" and "Verwerfen" and a "Zurück"-cancel
- **And** "Speichern" marks the session `completed` in drift and shows the SummaryScreen
- **And** "Verwerfen" deletes the session row and all its event rows from drift (hard delete — owner decision Q-2) and returns to home
- **Given** I am in a session with 0 throws recorded
- **When** I tap "Abbrechen"
- **Then** the dialog only offers "Verwerfen" and "Zurück" (no point in saving an empty session)

### AC-4 — Crash-Recovery beim App-Start

- **Given** the app was force-killed or crashed during an active session
- **When** I open the app
- **Then** a recovery dialog appears immediately after the home screen mounts (or after the first-run profile flow if applicable)
- **And** the dialog shows the active session's metadata (distance, throw count so far, started-at time)
- **And** offers three buttons: "Fortsetzen" (resumes session screen), "Speichern als beendet" (marks completed, shows Summary), "Verwerfen" (discards)
- **And** while the dialog is open, the FAB and other home actions are inaccessible (modal blocking)

### AC-5 — Spieler-Profil anlegen und ansehen

- **Given** the app is opened for the first time and no player profile exists in drift
- **When** the app finishes initial loading
- **Then** an onboarding screen appears asking for the player's name
- **And** the input field rejects empty or whitespace-only names (button disabled)
- **And** confirming creates a profile row in drift with `name`, generated `deviceId` (UUIDv7), `createdAt`
- **And** the user is then routed to the home screen
- **Given** a profile already exists
- **When** I tap the profile icon on the home screen
- **Then** a ProfileScreen opens showing the saved name (no edit in F1)

### AC-6 — HomeScreen mit FAB und Modus-Sheet

- **Given** I am on the home screen
- **When** I tap the FAB labeled "Training"
- **Then** a bottom sheet slides up showing at least "Sniper-Training" as a tappable option
- **And** the sheet uses the design from `docs/design/ui_kits/app/HomeScreen.jsx` (`TrainingSheet` component)
- **And** the FAB is at Material 3 position (24 px from right and bottom edges, sized per token `--bk-touch-comfortable`)
- **When** I select "Sniper-Training"
- **Then** the configuration step from AC-1 opens
- **When** I select "Finisseur" (still shown as a placeholder option)
- **Then** a snackbar/toast "In Vorbereitung" appears, no navigation happens

### AC-7 — HomeScreen-Inhalt: Recent + Tournier + News

- **Given** I am on the home screen with at least 1 completed session
- **Then** a "Zuletzt"-section shows up to 3 most recent **completed** sessions, newest first
- **And** each row shows: type tag ("Sniper"), key metric (Trefferrate as percentage), sub-line (distance · throws · relative time)
- **Given** there are no completed sessions yet
- **Then** the "Zuletzt"-section is hidden entirely (no empty-state row in F1)
- **And** the Tournier-card is always visible, labeled "Tournier · In Vorbereitung", and tapping it shows a toast "In Vorbereitung" (no navigation)
- **And** the News-card is always visible with text "Saison 2026 — kubbtour.ch", tapping it opens the URL in the system browser via `url_launcher` (per owner Q-5 final decision)

### AC-8 — App-Settings via Hamburger-Menü

- **Given** I am on the home screen
- **When** I tap the hamburger icon (top-left)
- **Then** the AppSettingsModal opens (per `docs/design/ui_kits/app/AppSettingsModal.jsx`)
- **And** shows four toggle/select rows: Sprache (read-only "Deutsch"), Theme (segmented Light/Dark/HighContrast), Heli-Tracking (toggle), Vibration (toggle)
- **When** I change Theme to Dark
- **Then** the entire app re-renders in dark theme immediately
- **And** the new value is persisted in drift settings table
- **And** persists across app restarts
- **When** I toggle Heli-Tracking off
- **Then** future Sniper sessions show only Hit + Miss (4 pads, no Heli column)
- **And** existing sessions in the Recent-List + SummaryScreen filter out Heli data (hit-rate computed as `hit / (hit+miss)`, Heli row hidden)
- **And** the underlying Heli event rows in drift are NOT deleted (audit-preserved); the filter is purely a display decision (per owner Q-9)
- **And** the AppSettings-Modal cannot be opened while a session is active — the hamburger icon is disabled in the Sniper screen (per owner Q-9)
- **When** I toggle Vibration off
- **Then** subsequent taps in any session do not call `HapticFeedback`

### AC-9 — Eye-Toggle (Blind-Training)

- **Given** I am in an active Sniper session with the eye-icon visible in the AppBar
- **When** I tap the eye-icon
- **Then** the counter values (Hit / Miss / Heli if active) are replaced with "—" placeholders
- **And** an info banner shows "Trefferzahl verdeckt — du wirfst blind."
- **And** the tap pads continue to function (events still recorded)
- **And** the throw-target countdown ("noch X Würfe") remains visible (it does not reveal hit count)
- **And** the eye-toggle state is **sticky** — persisted in `app_settings` (per owner Q-10), so the next Sniper session starts in the same blind/visible mode
- **When** I tap the eye-icon again
- **Then** the counters reappear with the current values, and the persisted state flips back to visible

### AC-10 — SummaryScreen am Session-Ende

- **Given** I just ended a session via "Session beenden" or "Abbrechen → Speichern"
- **When** the SummaryScreen renders
- **Then** it shows: total throws, hits, misses, helis (only if Heli-Tracking was on), hit rate (% rounded to whole number), session duration (mm:ss)
- **And** three actions are available: "Speichern" (default — confirms the already-completed status, returns to home), "Verwerfen" (marks the just-completed session as discarded, returns to home), "Neu starten" (creates a new session with the same distance/target config and opens the session screen)
- **And** layout follows `docs/design/ui_kits/app/SummaryScreen.jsx`

## Implizite Anforderungen (vom Owner nicht explizit erwähnt, aber notwendig)

- **drift-Schema-Migration v1**: Neue DB, drei Tabellen mindestens — `players`, `sessions`, `session_events` (plus `app_settings` als simpler Key-Value-Store).
- **Settings-Persistenz**: Theme, Heli-Tracking, Vibration werden zwischen Restart bewahrt → drift-Table `app_settings`.
- **Routing**: go_router-Setup mit Routen Home / Sniper-Setup / Sniper-Session / Summary / Profile / Onboarding.
- **AppLifecycle-Listener**: zur Crash-Recovery-Erkennung (oder: prüfe beim Start ob `sessions` mit `status='active'` existiert).
- **Empty-State im Onboarding**: Validation-Message wenn Name leer.
- **Recent-List Sortierung**: by `completed_at DESC`, limit 3, nur `status='completed'`.
- **Theme-Wechsel re-renders alle Screens**: `MaterialApp.themeMode` + Riverpod-Provider für die Wahl.
- **HighContrast-Theme**: eigenes ThemeData (nicht ThemeMode-System eingebaut), zusätzlich zur Light/Dark-Logik.
- **System-Browser-Open**: für News-Karte (`url_launcher` package).
- **i18n-Vorbereitung**: alle User-facing Strings über `AppLocalizations.of(context).xxx`, auch wenn nur `de.arb` existiert.

## Nicht-funktionale Anforderungen

- **Offline-Fähigkeit**: 100% offline. Keine Netzwerk-Calls in F1 (außer dem `url_launcher` für die News-Karte, aber das ist ein OS-Handover).
- **Sprache**: Deutsch (de) only. Alle Strings über `AppLocalizations`.
- **Performance**: Tap-Response < 100 ms (1-Tap-UX hartes Goal). Counter darf nicht "lag" haben.
- **Accessibility**:
  - Touch-Targets ≥ 48 dp (per `--bk-touch-min`); primäre Action-Pads ≥ 64 dp (`--bk-touch-comfortable`)
  - Kontrast WCAG AA für alle Text/Background-Kombinationen (Light, Dark, HighContrast)
  - Semantische Labels für Screen-Reader auf Buttons (`aria-label`-Äquivalent in Flutter via `Semantics`)
- **Persistenz-Robustheit**: jeder Tap muss unmittelbar in drift landen (kein Batched-Write), damit Crash-Recovery alle Würfe enthält.
- **Theme-Konsistenz**: alle Screens nutzen ausschließlich `KubbTokens` aus dem `ThemeExtension`; keine Inline-Hex-Codes.
- **Plattform-Targets F1**: Android Phone primär, Linux Desktop als Dev-Target, Web bleibt als Read-only-Sicht möglich (per ADR-0005, aber kein expliziter Test in F1).

## MVP-Scope (nur MUST)

US-1 bis US-8 und US-10. SHOULD-Story US-9 (Eye-Toggle) wird in derselben Iteration mitgebaut, da der Aufwand klein ist und das Feature im Design vorgesehen ist — aber sie ist nicht der Schicksals-Kipppunkt für eine erfolgreiche F1-Abnahme.

## Nice-to-have (SHOULD/COULD)

- US-9 (Eye-Toggle) — siehe oben, wird vermutlich mitgebaut
- "Confirm before reset" beim Hit−/Miss−/Heli− wenn der Counter bei 0 wäre? (Eher nicht — Counter clamped einfach bei 0)
- Animation beim Counter-Increment (z.B. kleines Pulse) — Polish, nicht F1

## WON'T (für F1 explizit ausgeschlossen)

- Finisseur-Modus (kommt als F4)
- Match/Tournament-Modus (kommt als M2-M3)
- Stats-Screen mit Charts und Trends (kommt als F3)
- CSV-Export (kommt als F5)
- Cloud-Sync via Supabase (offline-only F1)
- Andere Sprachen als Deutsch
- Push-Notifications
- Avatar-Bilder im Profil
- Profil-Edit (nur View in F1)
- Sound-Feedback (nur Vibration)
- Mehrere Profile (nur 1 Profil pro Device in F1)

## Geklärte Fragen (Owner-Decisions 2026-05-02)

| # | Frage | Owner-Entscheidung |
|---|-------|--------------------|
| Q-1 | Profil-Onboarding-Position | Beim ersten App-Start als Onboarding-Route, Home erst danach zugänglich |
| Q-2 | "Verwerfen" einer Trainings-Session | **Hard delete** — Session-Row + Event-Rows aus drift komplett raus |
| Q-3 | SummaryScreen "Neu starten" | Quick-Restart mit gleicher Config |
| Q-4 | Tournier-Karte Tap-Verhalten | Toast "In Vorbereitung" beim Tap |
| Q-5 | News-Karte: WebView vs Browser | **System-Browser via `url_launcher`** (Owner-Revision 2026-05-02) — konsistente Erfahrung über alle Plattformen, kein Linux-Sonderfall, kleineres Bundle |
| Q-6 | High-Contrast-Theme als Mode | Separater Mode (3-way Choice: Light / Dark / HighContrast). HighContrast = pure white background + pure black text + heavy borders, für direkte Sonneneinstrahlung. Manuell wählbar, nicht system-pref-bound in F1. |
| Q-7 | Recent-List-Filter | Nur `status='completed'` |
| Q-8 | Heli-Tracking Default beim ersten Start | On |
| Q-9 | Settings während aktiver Session + Heli-Filter-Semantik | (a) AppSettings-Modal kann während aktiver Session NICHT geöffnet werden (Hamburger disabled). (b) Wenn `heliTracking=off`: Heli-Events bleiben in drift erhalten (audit), aber UI filtert sie aus allen Statistik-Anzeigen (SummaryScreen, Recent-List). Hit-Rate berechnet aus `hit / (hit+miss)` ohne Heli. |
| Q-10 | Eye-Toggle Sticky vs Reset | **Sticky** — persistiert in `app_settings`, bleibt zwischen Sessions |

---

**Pfad der erzeugten Datei:** `docs/plans/sniper-training-mvp/po-output.md`

**3-Zeilen-Zusammenfassung:**
F1 ist ein gut umrissenes Trainings-Feature mit 8 MUST + 1 SHOULD User Stories — Sniper-Counter im Zentrum, plus minimales Profil und HomeScreen-Gerüst. Architektonisch pragmatisch im `training/` + `player/` Bounded Context, kein Hexagonal nötig. 10 offene Fragen mit pragmatischen Defaults vorgeschlagen — bei Owner-Rückfrage abklärbar, sonst werden die Defaults im Architect-Step übernommen.
