# Bug-Hunt-Sweep — Master-Report

> 20 Runden × 3 Hunter-Agents + Chef-Konsolidierung pro Runde.
> Audit-Ziel: aktueller `origin/main`-Stand auf saubere Funktion.
> Datum-Start: 2026-05-27

## Severity-Skala

- **P0** — App in dem Flow unbrauchbar (Crash, Daten-Verlust, Auth-Bug)
- **P1** — Funktioniert teilweise, UX-Lücke wesentlich
- **P2** — Feature fehlt oder nicht spec-konform, Workaround möglich
- **P3** — Polish, Konsistenz, Lint-Niveau

## Findings nach Runde

<!-- Runden 1-20 werden hier vom Chef-Agent angehängt -->

### Runde 1 — Auth-Flow

**Hunter-Output**: A=12 Findings, B=11 Findings, C=7 Findings → konsolidiert auf 17 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R1-F-01 | P0 | OAuth-Sign-In-Buttons sind UI-Stubs ohne Dispatch (Google/Apple klickbar, aber kein Adapter-Call) | R1-A-01, R1-B-01 | `ref.read(supabaseAuthAdapterProvider).signInWithOAuth(provider)` in `_onPickGoogle/_onPickApple` verdrahten, Errors als Banner; Stub-Kommentar entfernen, totes `_loading.anonymous`-Enum aufräumen |
| R1-F-02 | P0 | Session-Cache-Race blockiert RPCs (Root-Cause Mängel #9): Drift-Cache wird als Wahrheit angesehen, Wire-JWT ist `null` | R1-A-02, R1-C-01, R1-C-02, R1-C-07 | Bootstrap: nach `skip(1)` einen Wire-Re-Sign-Pfad triggern (Keypair: `signInWithChallenge`; OAuth: `getSession`-Refresh); zentrale Pre-Flight-Guard vor authentifizierten RPCs |
| R1-F-03 | P0 | Keypair-Session kein Refresh-Mechanismus — JWT läuft nach 1h stumm ab (ADR-0010-Verletzung) | R1-C-03 | Timer/Interceptor auf `expiresAt - 5min` der `KeypairSigningService.signInWithChallenge()` mit gespeichertem Privatkey neu auslöst; `autoRefreshToken: true` für OAuth-Pfad |
| R1-F-04 | P1 | Keine Berechtigungsmatrix / kein `user_roles`-System (ADR-0003 §Roles + Mängel #9 sekundär) | R1-C-04 | Eigene Sprint-Story: Tabelle `user_roles`, RPC-Guards, Riverpod-`rolesProvider`, Router-Gates; Owner-Entscheid ob Organizer-Force-OAuth jetzt oder später |
| R1-F-05 | P1 | Anonyme Supabase-Session ist vor `attachKeypair` schon wire-aktiv — RPCs könnten mit Anon-UID durchgehen | R1-C-05 | `attachKeypair` direkt nach `signInAnonymously` ohne suspending await-Lücke; zusätzlich Telemetry-Pause während Setup-Phase oder `setup_in_progress`-Flag |
| R1-F-06 | P1 | `print()`-Leak in `restore_controller`: Pubkey + Stacktrace landen in adb-logcat (PII-Smell, Production-Build) | R1-A-03, R1-B-03 | `print` durch `Logger('auth.restore').warning(...)`; Pubkey auf 8-Zeichen-Präfix kürzen; `// ignore: avoid_print` entfernen |
| R1-F-07 | P1 | Delete-Account-Screen ohne `ref.listen` auf Done/Error — User strandet auf Confirm-Dialog | R1-A-04 | `ref.listen<AccountDeletionState>` registrieren: `done` → `GoRouter.go(signIn)` + SnackBar, `failed` → Banner mit Retry |
| R1-F-08 | P1 | Anonymous-Signup Back-Button regeneriert Mnemonic — Phrase, die User schon abgeschrieben hat, ist weg | R1-A-05 | Back ab Mnemonic-Step entweder sperren wenn Ack-Checkbox aktiv, oder beim Zurückspringen die alte Phrase behalten (nur "Neue Phrase" regeneriert explizit) |
| R1-F-09 | P1 | Restore-Hinweistext sagt "12, 15 oder 18 Wörter", Validator akzeptiert 12-24 — Inkonsistenz | R1-A-06 | Hinweistext erweitern auf {12,15,18,21,24} ODER Validator strikt auf {12,15,18} reduzieren (passend zum eigenen Signup) |
| R1-F-10 | P1 | Sign-In-Offline-State hardcoded `false`, OAuth-Spinner endlos ohne Netz-Hinweis | R1-A-07 | `final offline = ref.watch(connectivityProvider)...`; OAuth-Buttons `onPressed: null` mit Tooltip, Banner aktiv |
| R1-F-11 | P1 | AuthController-Subscription-Race: bei `_subscribe()` kein `_sub?.cancel()` davor → potenzieller Doppel-Listener | R1-B-02 | In `_subscribe()` zuerst `_sub?.cancel()`/`_sub = null` (best-effort), dann neu listen; Single-Subscription-Invariante per Lock absichern |
| R1-F-12 | P1 | AccountDeletion: Keypair-Storage nur bei Erfolg geleert; bei Exception verwaister Privatkey lokal vs. gelöschter Server-Account | R1-B-04 | `keypair.clear()` in `try/finally`; nach RPC-Erfolg explizit `authController.signOut()` aufrufen statt auf Stream zu warten |
| R1-F-13 | P2 | AccountUpgrade signalisiert `done` direkt nach `linkIdentity()`-Aufruf, ohne auf tatsächlichen Wire-Link zu warten | R1-B-05 | `linking`-State halten, `ref.listen<AuthSession>` auf Kind-Wechsel zu `oauth_*` → erst dann `done`; Timeout 5min für `linking` |
| R1-F-14 | P2 | `SupabaseAuthAdapterImpl.dispose()` wird nie aufgerufen — Test/Hot-Restart-Leak | R1-B-06 | Im Provider `ref.onDispose(adapter.dispose)` registrieren |
| R1-F-15 | P2 | AccountLink-Screen verlässt sich auf statisches Success-Banner ohne Auto-Pop / Navigation | R1-A-08 | `ref.listen<AccountUpgradeState>` auf `done` → SnackBar + `context.pop()`; falls Link-Verifikation via R1-F-13 fixt, hier zusätzlich konsumieren |
| R1-F-16 | P2 | Router-Recovery bei `AsyncError` stumm — kein Logging, kein Telemetry-Event, kein User-Feedback | R1-A-09 | `auth.hasError`-Pfad: `Logger('AuthRouter').severe(...)` + `authTelemetry.refreshFailure(...)`; Sign-In-Screen optional Banner "Sitzung abgelaufen" zeigen |
| R1-F-17 | P2 | AuthController.signOut + AccountSetup-Failure-Pfade: Roh-Exceptions in UI, kein Cleanup bei Teilfehlern | R1-A-10, R1-A-11, R1-B-11 | `_classifyAuthError`-Helper analog `restore`-Pfad; einzelne Cleanup-Calls in eigenen try/catch; `error.toString()` durch stabile Reason-Codes ersetzen |

**No-Issue / Konsolidierungs-Notizen:**
- R1-A-12 (i18n-Lücke `'Mnemonic-Phrase'`), R1-B-09 (Doppel-Bip39-Check), R1-B-10 (Force-unwrap in `_sessionFromAdapter`), R1-B-07 (Timer-Cleanup-Edge bei Notifier-Re-Build), R1-B-08 (`anon_session.dart` Failure-Propagation), R1-C-06 (Anonymous-Downgrade-Heuristik) — als P3-Polish/Edge gesammelt, fließen in einen separaten "Cleanup-Sweep" am Ende der Bug-Hunt-Wave; nicht in obige Tabelle eskaliert, weil Einzel-Impact gering und Häufung erst beim Refactoring effizient adressierbar.
- Keine False-Positives identifiziert: alle Findings sind reproduzierbar oder spec-belegt.

**Zusammenfassung:** Drei P0-Findings dominieren die Runde — der OAuth-Button-Stub (R1-F-01) blockt jedes nicht-anonyme Sign-In, und die Session-Cache-Race-Kette (R1-F-02 + R1-F-03) ist die nachweisbare Root-Cause von Mängel #9 (`authentication required` beim Tournier-Create). Die fehlende Berechtigungsmatrix (R1-F-04) wartet auf Owner-Entscheid und ist eigene Sprint-Story. Auf P1-Ebene zeigen sich ein PII-Leak (R1-F-06), mehrere UX-Fallen in Signup/Restore/Delete und ein Subscription-Race im AuthController — alle einzeln klein, in Summe ein klares Signal dass der Auth-Surface vor M6-Release nochmal eine Härtungs-Runde braucht.

### Runde 2 — Onboarding + Profil-Setup + Avatar

**Hunter-Output**: A=13, B=13, C=7 → konsolidiert auf 14 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R2-F-01 | P0 | Avatar-Encoding-Mismatch — `#RRGGBB` vom Edit-Screen kollidiert mit `0xAARRGGBB` aus AvatarColorHelper, User-Farbe wird nach Save komplett ignoriert | R2-A-01, R2-B-01, R2-C-05 | Eine Palette (`AvatarColorHelper.palette`), ein Encoding (`encode()`), Reader-Parser akzeptiert beide Formate für Migration alter Daten |
| R2-F-02 | P0 | Edit-Profile-Save invalidiert AuthSession nicht — Erfolg-Banner sagt "gespeichert", UI zeigt aber bis Neustart alten Stand | R2-A-02, R2-B-03 | Nach `updateProfile` `authControllerProvider`-Refresh + Cached-Session-DB nachziehen; `_initialNick/_initialColor` lokal auf neue Werte ziehen damit `_dirty` korrekt resettet |
| R2-F-03 | P0 | Onboarding-Tour ist dead code — `onboarding_completed`-Flag wird gelesen aber weder vom Router als Gate genutzt noch von `_finish()` persistiert; OAuth-User sehen die Tour nie | R2-A-03, R2-C-02, R2-C-06 | Router-Redirect ergänzen (authenticated + `onboarding_completed==false` → `/onboarding-tour`); `_finish()` ruft `updateProfile(onboardingCompleted: true)` vor `GoRouter.go('/')` |
| R2-F-04 | P1 | Avatar-Server-Constraint fehlt — `user_profiles.avatar_color` akzeptiert beliebige Strings, kein CHECK + keine RPC-Validierung | R2-B-02 | `CHECK (avatar_color ~ '^(0x[0-9A-Fa-f]{8}|#[0-9A-Fa-f]{6})$')` auf Spalte plus Format-Prüfung in `fn_profile_update_with_hash` mit ERRCODE 22023 |
| R2-F-05 | P1 | Signup-Wizard hat keinen Avatar-Step — User landet mit aufgezwungener Hash-Default-Farbe, Edit-Profile-Picker bleibt versteckt | R2-A-04, R2-A-13 | Avatar-Step zwischen Nickname und Mnemonic einschieben ODER Success-Slide mit Direkt-Sprung "Profil personalisieren" zu EditProfileScreen |
| R2-F-06 | P1 | Nickname-Validierung verbietet Umlaute, Spaces, Akzente — "Müller", "Jean-Luc", "Léa" brechen am Regex `[A-Za-z0-9_-]+`; Edit ist strenger als OAuth-Bootstrap | R2-A-05, R2-B-05, R2-C-07 | Regex auf Unicode `^[\p{L}\p{N}_\- ]+$` erweitern + Trim, Validierungs-Regel zentral in `kubb_domain/` als `NicknameRules.validate`, Server-CHECK mit gleicher Logik |
| R2-F-07 | P1 | Spec-Lücke: Profil-Setup-Screen aus claude-design-handoff §6.1.3 (Heimatverein, Land, Avatar) existiert nicht — blockiert spätere Features (Verein, Liga, CH-Eligibility) | R2-C-01 | Eigenständige Onboarding-Spec schreiben mit Feldliste + Pflicht/Optional; Screen zwischen Account-Erstellung und Tour einziehen; ADR-0003 erweitern um `home_club`/`country` |
| R2-F-08 | P1 | Spec-Lücke: Privacy-Screen aus §6.1.4 fehlt — keine `profile_visibility`-Spalte, kein Push-Kategorie-Konzept, DSGVO-Privacy-by-Default verletzt sobald §6.6 öffentliches Profil baut | R2-C-03 | Proposed-ADR: `profile_visibility ∈ {public, friends_only, private}` Default `friends_only`, RLS-Policy nachziehen, `user_notification_prefs(user_id, category, enabled)` als separate Tabelle |
| R2-F-09 | P1 | Owner-Entscheid offen: Avatar Initial+Color vs. Upload — Spec §8 nennt "Spieler-Avatar mit Rang-Badge" mehrdeutig, aktueller Code ist Initial+Color, ADR fehlt | R2-C-04 | Proposed-ADR vorlegen: Initial+Color als MVP bestätigen (mit Spec-Update §6.1.3) ODER Upload-Feature explizit Post-M5 backloggen |
| R2-F-10 | P2 | Edit-Profile-Erfolg-Banner verschwindet nicht, Auto-Pop fehlt, `_dirty`-Reset fehlt — User tippt erneut auf Speichern, nichts passiert | R2-A-06 | Nach Erfolg `_initialNick`/`_initialColor` aktualisieren, Banner 2-3s Auto-Hide ODER direkt zurücknavigieren mit SnackBar auf ProfileScreen |
| R2-F-11 | P2 | Edit-Profile-Error ist generisch — `on Object catch (_)` schluckt alle Fehler ohne Logging, keine Differenzierung zwischen offline / Nickname vergeben / Server-Fehler | R2-A-08, R2-B-04 | `package:logging` Logger + `telemetry.profileUpdateFailed(reasonCode)`, separate Banner-Messages für ERRCODE-Werte (`23505` unique conflict, `42501` auth, Netzwerk) |
| R2-F-12 | P2 | `_NicknameStep` in Signup-Wizard verliert Eingabe bei Back-Navigation — `_nick` ist nacktes String-Feld ohne Controller, kein Sync mit Parent `_nickname` | R2-B-07 | `TextEditingController` einführen, `initialValue` aus Parent reichen, im `dispose()` aufräumen |
| R2-F-13 | P2 | Schema-Drift: `players.avatarColor` (drift, lokal) parallel zu `user_profiles.avatar_color` (Supabase) ohne dokumentierten Sync-Pfad — Tournament-Listen können andere Farbe als Profile zeigen | R2-B-12 | ADR-Notiz: `players` als Trainings-legacy klassifizieren und `avatarColor` daraus entfernen, immer aus Cloud-Profile auflösen; bei echter Trennung expliziten Sync-Hook bei Profile-Update |
| R2-F-14 | P3 | ProfileScreen Empty-State "Profil nicht geladen" ist Sackgasse — kein Retry, kein Sign-In-CTA, kein Loading-vs-Error-Differenzierung | R2-A-09 | Drei States bauen: Loading (Spinner), Error (Retry-Button), Signed-Out (Anmelden-CTA) statt ein einziger Fallback-String |

**No-Issue / Konsolidierungs-Notizen:**
- R2-A-07 (Skip-Slot-Layout-Shift), R2-A-10 (Palette-Token-Drift — Teil von R2-F-01), R2-A-11 (Color-Dot 38×38 unter 48dp Touch-Min), R2-A-12 (Save-Button-Spinner-Konsistenz), R2-B-06 (`userId`-Parameter ist Security-Theater), R2-B-08 (Telemetry sendet bei No-Op-Save), R2-B-09 (hardcoded deutsche Strings + Magic-Numbers im Signup), R2-B-10 (Palette-Drift — siehe R2-F-01), R2-B-11 (Doppel-Roundtrip in `ensureProfile`), R2-B-13 (Doppel-Submit-Race im Signup) — als P3-Polish gebündelt für den End-of-Sweep-Cleanup, nicht einzeln eskaliert weil entweder kosmetisch oder Subset eines konsolidierten Findings.
- R2-A-10 + R2-B-10 + R2-C-05 sind die drei Avatar-Palette-Drift-Findings und verschmelzen in den Fix-Plan für R2-F-01.
- R2-A-01 + R2-B-01 + R2-C-05 sind die drei Hits auf Encoding-Mismatch (vorhergesagt) — eine Quelle, ein Fix.

**Zusammenfassung:** Drei P0-Findings — die Avatar-Encoding-Kollision (R2-F-01) macht den Picker effektiv kaputt, der fehlende Provider-Refresh nach Save (R2-F-02) erzeugt das klassische "habe ich überhaupt gespeichert?"-Gefühl, und die Onboarding-Tour (R2-F-03) ist als Feature da, aber als Flow tot — OAuth-User sehen sie nie, der Abschluss wird nirgends persistiert. Sechs P1 mischen drei harte Bugs (fehlender Server-Constraint, Nickname-Regex bricht Schweizer Namen, kein Avatar-Step im Signup) mit drei Spec-Lücken die Owner-Eskalation brauchen (Profil-Setup-Felder, Privacy-Visibility, Avatar-Upload-vs-Color). Die P2/P3-Ebene ist klassische Polish-Schicht. Auffallend: alle drei Hunter haben das Encoding-Mismatch unabhängig gefunden — das ist der eindeutige Fix mit dem grössten Wirkungs-Hebel.

### Runde 3 — Home/Training-Übersicht + Bottom-Sheet

**Hunter-Output**: A=12, B=15, C=8 → konsolidiert auf 22 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R3-F-01 | P0 | Tournament-Tile lügt "in Vorbereitung" für ein M1-shipped Feature — Conversion-Killer | R3-A-01, R3-C-03, R3-C-08 | ARB-Werte korrigieren (`homeTournierTitle` → "Turniere", `homeTournierComingSoon` → Subtitle dynamisch aus offener-Turnier-Count oder statisch "Liste laufender und kommender Turniere"); toten `homeTournierTapToast` löschen, l10n neu generieren |
| R3-F-02 | P0 | Bottom-Nav-Split (Heim/Turniere/Liga/Training/Profil) fehlt komplett — Spec §5.2 fundamental verletzt | R3-C-01 | Eigene ADR + Sprint-Story: `StatefulShellRoute.indexedStack` mit 5 Branches einbauen, `HomeScreen` wird zu `HeimTab`, FAB-Trigger pro Tab kontextualisiert |
| R3-F-03 | P0 | Heim-Tab-Inhalt fehlt fast komplett — kein Next-Match, kein Upcoming-Tournament, kein Liga-Stand, keine Inbox | R3-C-02, R3-A-05 | Section-Reihenfolge festlegen: `NextMatchCard` (Provider auf laufende Registrations), `UpcomingTournamentsRail`, `LigaStandTeaser`, `InboxBadge`; Recent-Trainings nach Training-Tab verschieben |
| R3-F-04 | P0 | Race im ActiveSessionNotifier verliert Hits bei 1-Tap-Doppelklick (Sniper-Mode-Kerngoal) | R3-B-04 | Lock/Queue via `synchronized` ODER State aus `repo.eventsOf(...)` re-deriven statt aus `_bump` zu inkrementieren |
| R3-F-05 | P0 | Empty-State der Recent-Sessions fehlt — First-Time-User sieht leeren Home-Screen ohne Training-CTA | R3-A-03 | Empty-State-Widget mit Onboarding-CTA "Starte deine erste Session" rendern wenn `recent.isEmpty`, Modi kurz erklären (Sniper/Finisseur) |
| R3-F-06 | P0 | Doppelter Turnier-Einstieg + Bounded-Context-Vermischung: Sheet vermischt Training/Match/Turnier in einem Picker | R3-A-02, R3-C-05 | Mit R3-F-02 zusammen lösen: Heim-FAB = "Neues" (kontextlos), Training-Tab-FAB = nur Trainings-Modi (Sniper/Finisseur/4m); Turnier aus Sheet entfernen oder auf Setup-Wizard routen |
| R3-F-07 | P0 | `recent.maybeWhen` verschluckt Loading + Error stumm — User sieht keine DB-Fehler, Flackern auf langsamen Geräten | R3-A-04 | `when(loading: skeleton, error: errorBanner, data: list)` ausschreiben statt `maybeWhen` mit leerer-Liste-Fallback; Errors loggen |
| R3-F-08 | P1 | 4m-Linie-Trainingsmodus fehlt komplett — ADR-0002 nennt ihn als Phase-1-Modus | R3-C-04 | Eigene Feature-Story analog `docs/plans/finisseur-mode/`; Owner-Entscheid: Sniper-Preset mit `distance=4.0` ODER eigener Modus mit eigenem Score-Modell |
| R3-F-09 | P1 | Crash-Recovery-Dialog kann doppelt geöffnet werden + zerstörerisches "Verwerfen" ohne Confirm/Undo | R3-B-01, R3-A-09 | Im Callback nochmals prüfen ob Dialog bereits offen (`ModalRoute.of(context)?.isCurrent`); "Verwerfen" mit Confirm-Step + SnackBar-Undo (Pattern wie `AbortDialog`) |
| R3-F-10 | P1 | `startSession` Read-Modify-Write ohne Transaktion — paralleles Tap erzeugt stale Sessions | R3-B-08 | `_sessions.transaction { activeForUser → deleteById → insert }` wrappen, optional Unique-Partial-Index `(player_id) WHERE status='active'` |
| R3-F-11 | P1 | Hardcoded Match-Card-Strings "Match"/"Mehrspieler-Match (Bo1/3/5)" umgehen i18n | R3-A-06, R3-B-14 | ARB-Keys ergänzen `modeMatchTitle` und `modeMatchSubtitle`, Hardcoded-Werte ersetzen |
| R3-F-12 | P1 | Swallowed exceptions in `_resume`/`_save`/`_discard` + `launchUrl` ohne Fehlerbehandlung | R3-B-06, R3-B-07 | try/catch + Logger + SnackBar in allen drei CrashRecovery-Handlern; `launchUrl`-Rückgabewert prüfen, Fallback-SnackBar "Browser nicht verfügbar" |
| R3-F-13 | P1 | "Tournier"-Tippfehler durchgängig in Klassen-/Datei-/ARB-Namen statt korrektem "Turnier" | R3-A-12, R3-C-07 | Rename: `TournierCard` → `TournamentTeaserCard`, Datei `tournier_card.dart` → `tournament_teaser_card.dart`, ARB-Keys `homeTournier*` → `homeTournament*` |
| R3-F-14 | P2 | Visuelle Hierarchie priorisiert die falschen Features — Training (Phase-1-Kernprodukt) nur als kleiner FAB | R3-A-05 | Training-Quick-Start-Card direkt unter Greeting, News + externe Links nach unten; mit R3-F-03 zusammen umsetzen |
| R3-F-15 | P2 | "Saison 2026"-NewsCard ist statisches Marketing statt vorbereitende Coming-Soon-Saison-Sektion | R3-C-06 | Eigenes Widget `SeasonTeaserCard`: heute "Saison 2026 — kommt mit M5" zeigen, bei `seasonStandingsTitle != null` auf echte Saisontabelle springen |
| R3-F-16 | P2 | HomeScreen rebuildet komplett bei jedem recent-Stream-Tick — Greeting/TournierCard/NewsCards inklusive | R3-B-02, R3-B-03 | `RecentSection` zu eigenem `Consumer`-Widget extrahieren das den Provider lokal watcht; Card-Subtrees als const oder in eigenen Widgets isolieren |
| R3-F-17 | P2 | N+1-Query-Pattern in `recent_sessions_provider`: pro Session sequentielle Roundtrips für Events/Sticks | R3-B-13 | `Future.wait(...)` parallelisieren ODER Aggregat-Query im DAO (hitRate/win in einer Query liefern) |
| R3-F-18 | P2 | `context.go` vs `context.push` inkonsistent — Back-Verhalten unterscheidet sich je nach Einstieg | R3-A-08, R3-B-15 | Navigation-Konvention dokumentieren und durchsetzen: `context.push` für detail-Stack, `context.go` nur für Tab-Wechsel; `pop()` vor `go()` ist redundant |
| R3-F-19 | P2 | `undoLast` setzt DB-Roundtrip auch bei Counter=0 ab, schluckt stumm + `hitRate=0 %` bei 1 Heli-No-Tracking-Session | R3-B-05, R3-B-12 | Notifier: bei Counter=0 Early-Return ohne DB-Call ODER User-Feedback ("Nichts zum Rückgängig-Machen"); divisor-0-Pfad in UI als "—" statt "0 %" rendern |
| R3-F-20 | P3 | Doppelte Marken-Nennung: AppBar-Title "Brosi's Kubb" + Greeting-Eyebrow "BROSI'S KUBB" | R3-A-07 | Eyebrow auf Kontext-Hinweis umstellen ("Trainings-Übersicht", "Heute") statt App-Name zu wiederholen |
| R3-F-21 | P3 | NewsCard "Teams" als News-Widget mit hardcoded Empty-Subtitle ohne echte Team-Daten | R3-A-10 | Eigenes `TeamSummaryCard`-Widget mit echten Team-Daten ODER Teams in Tab/Settings verschieben (mit R3-F-02 lösen) |
| R3-F-22 | P3 | RecentSection ohne Keys + nicht-lazy Column + Provider ohne autoDispose + FAB-Tooltip fehlt | R3-B-09, R3-B-10, R3-B-11, R3-A-11 | `ValueKey(sessionId)` auf `_RecentRow`, `recentSessionsProvider.autoDispose`, FAB-`tooltip` + Semantik-Label; API-Contract von `RecentSection` dokumentieren |

**No-Issue / Konsolidierungs-Notizen:**
- R3-A-01, R3-C-03, R3-C-08 sind drei Hits auf dieselbe Tournament-Tile (Tippfehler + Lüge + toter ARB-Key) — ein konsolidierter Fix R3-F-01.
- R3-A-12 + R3-C-07 sind beide der "Tournier"-Tippfehler — Rename-Pass in R3-F-13.
- R3-A-06 + R3-B-14 sind dasselbe hardcoded Match-Card-Pattern — R3-F-11.
- R3-A-02 + R3-C-05 beschreiben dieselbe Bounded-Context-Vermischung im Sheet — R3-F-06.
- R3-A-05 wirkt sowohl in R3-F-03 (Heim-Tab-Inhalt) als auch separat in R3-F-14 (Hierarchie-Polish); referenziert in beiden, gefixt mit R3-F-03.
- R3-B-09 + R3-B-10 + R3-B-11 + R3-A-11 sind alle Polish-Punkte am RecentSection/FAB — als R3-F-22 gebündelt.
- R3-B-05 + R3-B-12 sind beide kleine Notifier/UI-Polish-Punkte (Undo-Edge, hitRate-Anzeige) — als R3-F-19 gebündelt.
- Keine False-Positives identifiziert.

**Zusammenfassung:** Sieben P0-Findings dominieren die Runde — die Tournament-Tile lügt dem User ein "in Vorbereitung" für ein live-funktionierendes Feature an (R3-F-01), die Spec-geforderte 5-Tab-Bottom-Navigation existiert gar nicht (R3-F-02), und der Heim-Tab zeigt drei der vier Spec-Kerninhalte schlicht nicht (R3-F-03). Dazu eine harte Race-Condition im Sniper-Mode (R3-F-04, verliert Hits bei schnellem Tap), ein fehlender Empty-State für First-Time-User (R3-F-05), Bounded-Context-Vermischung im Bottom-Sheet (R3-F-06) und ein stummer Loading/Error-Verschlucker (R3-F-07). Auf P1-Ebene fehlt der dritte ADR-deklarierte Trainings-Modus 4m-Linie komplett, der CrashRecovery-Dialog hat Doppel-Open-Race + zerstörerisches Discard ohne Confirm, und `startSession` ist nicht transaktional. Mehrfach-Hit über alle drei Hunter: die "Tournier"-Schreibweise und die "in Vorbereitung"-Lüge sind die offensichtlichsten Sofort-Fixes mit hoher Sichtbarkeit; der grosse Brocken bleibt der Bottom-Nav-Split (R3-F-02), der M4/M5 architekturell vorbereitet.



### Runde 4 — Sniper-Training

**Hunter-Output**: A=10, B=10, C=8 → konsolidiert auf 19 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R4-F-01 | P0 | Counter-Race bei Doppel-Tap — `_append`/`_withActive` cached state.value vor await, verliert Events | R4-A-01, R4-B-01, R3-B-04 (R3-F-04) | Sequenzielle Future-Chain/Mutex im ActiveSessionNotifier + Re-Read von `state.value` nach await; alternativ Counter via `countByKind`-Stream re-deriven |
| R4-F-02 | P0 | Doppel-Tap auf Start-Button kann zwei parallele Sessions erzeugen — zweite löscht erste per stale-cleanup | R4-A-03, R4-B-03 | `_isStarting`-Flag in `_SniperConfigScreenState`, FilledButton während Future disabeln; Start-Future idempotent |
| R4-F-03 | P0 | `startSession` ist nicht atomar — `activeForUser → deleteById → insert` ohne Transaktion → Multi-Session-Korruption | R4-B-02 | `_sessions.attachedDatabase.transaction { ... }` um den Block; partial Unique-Index `(player_id) WHERE status='active'` in `sessions.dart` |
| R4-F-04 | P0 | Hit-Rate-Berechnung verletzt Spec — `summary_screen.dart` zählt Heli als Miss, Spec Q-9-(b) sagt explizit "ohne Heli" | R4-C-01 | `relevant = hits + misses` in `summary_screen.dart:110` und `stats_repository.dart:69/79/138` angleichen; Tests aktualisieren; Owner-Confirm via ADR-Annotation |
| R4-F-05 | P1 | Keine Crash-Recovery/Resume im Sniper-Session-Screen — `resumeFromCrash` existiert verwaist, App-Kill = endloser Spinner | R4-A-04 | Im `SniperSessionScreen` bei `session==null && sessionId!=null` `resumeFromCrash(sessionId)` triggern; `AppLifecycleListener` für Pause-State |
| R4-F-06 | P1 | Heli-UI signalisiert nicht dass Helikopterwurf illegal ist — visuell gleichwertig zu Hit/Miss | R4-C-02 | Warn-Icon/Subtext am Heli-Counter ("Ungültig — wird nicht im Turnier gewertet"); `KubbTapPadTone.heli` in Warnfarbe; ARB-Key erweitern |
| R4-F-07 | P1 | Repository-Exceptions werden vom Notifier komplett geschluckt — `unawaited(action())` lässt Errors stumm verschwinden | R4-B-04 | try/catch um `_repo`-Calls, `state = AsyncError(e, st)` setzen; `ref.listen` im Screen → SnackBar/Dialog; mindestens Logger-Eintrag |
| R4-F-08 | P1 | Custom-Target ignoriert ungültige Eingabe (0, >999) still — Spieler startet mit altem Preset ohne Hinweis | R4-A-02 | Inline-ErrorText in `InputDecoration` bei Out-of-Range; Start-Button bei ungültiger Eingabe disabeln |
| R4-F-09 | P1 | Bei erreichtem `throwTarget` kein Auto-Stop/Hinweis — Counter zählt einfach weiter, Vergleichbarkeit weg | R4-A-06 | Bei `used == throwTarget`: Haptik-Pattern + Modal "Du hast dein Ziel erreicht — beenden?" mit Beenden/Weiter |
| R4-F-10 | P1 | Remaining zählt Heli zur Wurfzahl, Hit-Rate (nach Spec) nicht — semantischer Konflikt "was ist ein Wurf?" | R4-C-03, R4-B-08 | Mit R4-F-04 zusammen lösen: Owner-Entscheidung dokumentieren (Heli zählt-zur-Wurfzahl-ja-nein), `_Remaining`-Logik daran ausrichten; `heliTracking`-Toggle während aktiver Session disabeln |
| R4-F-11 | P1 | startSession liefert keinen Return-Wert — `_start` greift `sessionId` via `ref.read` direkt nach await ab (Race-anfällig) | R4-B-07 | `startSession` zu `Future<String>` umbauen (gibt sessionId zurück); `_start` nutzt Rückgabewert direkt; Else-Pfad SnackBar |
| R4-F-12 | P2 | Eye-Toggle im Session-Header ist globale Settings — wirkt unerwartet auch auf zukünftige Sessions | R4-A-05 | Entweder Session-lokaler State (`ActiveSessionState.masked`) oder einmaliger SnackBar-Hinweis "Wirkt für zukünftige Sessions" |
| R4-F-13 | P2 | Back-Button mit Würfen bietet nur Discard/Cancel, fehlende "Speichern und beenden"-Option (Asymmetrie zu Abort) | R4-A-09 | `handleBack` soll dasselbe 3-Wege-`AbortDialog` (cancel/save/discard) zeigen wie der Abort-Button |
| R4-F-14 | P2 | Slider-Skala zeigt nur ganze Meter — 0.5er-Schritte funktional vorhanden, aber affordance-mässig unsichtbar | R4-A-08, R4-C-04 | Tick-Labels auf `[4.0, 4.5, 5.0, …, 8.0]` ausweiten oder Half-Step-Striche; Snap-Indikator beim Drag |
| R4-F-15 | P2 | `_PadGrid` reicht WidgetRef per Konstruktor durch + keine selektiven `select()` — rebuildet alle 6 Pads pro Counter-Tick | R4-B-05 | `_PadGrid` zu `ConsumerWidget` machen, `notifier` per `ref.read` einmal cachen; Counter-Subwidgets mit `ref.watch(...select(...))` |
| R4-F-16 | P2 | ActiveSessionNotifier hat keinen Lifecycle-Hook — in-flight Writes nach Dispose schreiben in toten Notifier | R4-B-06 | `ref.onDispose(() { _cancelled = true; })` im build; nach jedem await `_cancelled`-Check vor `state =`-Write |
| R4-F-17 | P2 | Slider-Untergrenze 4m bzw. 5m-Basislinie nirgendwo erklärt — Domain-Kontext zur Spec fehlt | R4-C-06 | Slider-Tick-Annotation "4m (Strafkubb)" / "5m (Basislinie)" oder Onboarding-Subtext im SniperConfigScreen |
| R4-F-18 | P3 | Undo-Pad bei Counter=0 ist Silent-NoOp, End-Button als TextButton schwächer als Tap-Pads, leere Session ohne Confirm completed | R4-A-07, R4-C-07, R4-C-08 | Minus-Pads bei Count=0 disabeln (`muted`/null); End-Button als `FilledButton`/`OutlinedButton` mit `touchComfortable`; End-Handler `hasThrows`-Check spiegeln |
| R4-F-19 | P3 | `_bump` Default-Branch silent + KubbTapPad ohne Keys + Restart-Button silent bei profile==null + Strafkubb-Domain-Klarheit fehlt | R4-B-09, R4-B-10, R4-A-10, R4-C-05 | `kind` zu Enum heben (Compiler-Exhaustivität); `ValueKey('hit-plus')` etc. auf Pads; Restart bei profile==null → SnackBar/Redirect; Doku-Notiz "Strafkubb ist kein Sniper-Outcome" in `docs/plans/sniper-training-mvp/feature-plan.md` |

**No-Issue / Konsolidierungs-Notizen:**
- R4-A-01 + R4-B-01 bestätigen R3-B-04 (R3-F-04) — die Race ist im Sniper-Pfad reproduzierbar identisch; R4-F-01 erbt damit das Fix-Ticket aus Runde 3 und konkretisiert Optionen.
- R4-A-03 + R4-B-03 sind dasselbe Doppel-Start-Tap-Problem — ein Fix in R4-F-02.
- R4-C-03 + R4-B-08 beschreiben dieselbe "was ist ein Wurf"-Semantik-Unklarheit — gebündelt in R4-F-10 (hängt an der Spec-Klärung von R4-F-04).
- R4-A-08 + R4-C-04 sind dasselbe Slider-Label-Problem — R4-F-14.
- R4-A-07, R4-C-07, R4-C-08 sind drei UX-Polish-Punkte am Session-Ende-Flow — als R4-F-18 gebündelt.
- R4-B-09, R4-B-10, R4-A-10, R4-C-05 sind kleine Polish-/Domain-Doku-Punkte — als R4-F-19 zusammengefasst.
- Keine False-Positives identifiziert.

**Zusammenfassung:** Vier P0-Findings — die zentrale Counter-Race aus R3-F-04 wird in Sniper bestätigt (R4-F-01), zusätzlich kommt ein Doppel-Start-Tap-Vektor (R4-F-02), eine nicht-atomare `startSession`-Sequenz (R4-F-03) und eine harte Spec-Verletzung der Hit-Rate-Berechnung (R4-F-04, Heli zählt als Miss obwohl Owner-Entscheid Q-9-(b) explizit das Gegenteil sagt). Die sieben P1-Findings adressieren fehlende Crash-Recovery im Sniper-Screen, illegale-Wurf-Kommunikation, geschluckte Repository-Exceptions, Validation-Stille bei Custom-Target, fehlendes Auto-Stop bei `throwTarget`, semantische Konflikte "was ist ein Wurf" und einen race-anfälligen `_start`-Pfad. P2/P3 sind UX-Polish, Performance- und Domain-Doku-Lücken. Mehrfach-Hit-Muster: Race-Conditions (R4-F-01, R4-F-02, R4-F-03) und Heli-Semantik (R4-F-04, R4-F-06, R4-F-10) sind die zwei roten Fäden — Hotfix-Wave 1 = R4-F-01..04, danach Heli-Spec-Klärung als gebündeltes ADR.

### Runde 5 — Finisseur-Training

**Hunter-Output**: A=8, B=11, C=7 → konsolidiert auf 16 Findings.

> **Chef-Anmerkung zum R5-Briefing**: Die R5-C-Hunter-Annahme einer "7m / 3-Kubbs-in-Reihe / 3 Würfe pro Stick"-Definition entstammt einer fehlerhaften Briefing-Beschreibung des Chef-Inspektors. Die verbindliche Definition steht in ADR-0001 und `docs/plans/finisseur-mode/feature-plan.md`: Finisseur simuliert die Match-End-Situation am 8m-Wurf, 0–10 Feldkubbs + 0–5 Basekubbs, 6 Stöcke (Verlängerung möglich), König als finaler Wurf. R5-C-01, R5-C-02 und R5-C-03 sind damit keine App-Bugs, sondern P3-Documentation-Hinweise zur internen Spec-Klarheit (siehe R5-F-15).

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R5-F-01 | P0 | Race im Stick-Eingabe-Pfad — Tap → updateCurrentStick → advance() ohne Lock, kein UNIQUE auf (session_id, stick_index), Doppel-Insert möglich | R5-A-03, R5-B-01, R5-B-02, R5-B-03 | Re-Entrancy-Lock im `ActiveFinisseurNotifier.advance()` (Future-Mutex oder `state = AsyncLoading()` Guard); UNIQUE-Index auf `(session_id, stick_index)` als Migration; `recordStick` als `InsertMode.insertOrReplace`; BasePad-Buttons während Future disabeln |
| R5-F-02 | P0 | Doppel-Start-Tap erzeugt parallele Finisseur-Sessions, eine wird zur Geister-Session | R5-B-01 | UI-Inflight-Guard (`bool _starting` im ConfigScreen, FilledButton disabeln); Notifier `state = AsyncLoading()` vor `await _repo.startFinisseur`; Stale-Discard + Insert im Repository als `attachedDatabase.transaction` |
| R5-F-03 | P0 | Crash-Recovery deckt Finisseur-Sessions nicht ab — `crashRecoveryProvider` sieht nur Sniper, `loadActiveOrNull` ist toter Code | R5-A-02, R5-B-10 | `crashRecoveryProvider` auf beide Modi erweitern; `ActiveFinisseurNotifier.build()` rehydratisiert via `loadActiveOrNull` + `loadStickEvents`, fragt User per Dialog "Session fortsetzen?"; mindestens den stillen Stale-Delete in `startFinisseur` durch User-Confirm ersetzen |
| R5-F-04 | P0 | Rollback verliert committete Stick-Daten — Doc-Kommentar sagt "edits restored", Code setzt `restored[prev] = const StickResult()` | R5-B-06 | Stick-Daten aus altem State vor DB-Delete in `restored[prev]` als Patch beibehalten (oder DB-Row vor Delete lesen); `continuedBeyondSticks`-Flag nur halten wenn `prev >= totalSticks - 1`; Test für Rollback aus Verlängerungs-Stock |
| R5-F-05 | P0 | ConfigScreen erlaubt 0/0-Session ohne Guard — `_hasWon` triggert sofort, "Win"-Session mit 0 Stöcken landet in Stats | R5-A-01 | Start-Button disabled wenn `field + base <= 0`, oder mindestens `base >= 1` erzwingen (per Domäne braucht es einen Basekubb für den 8m-Wurf); Summary-Early-Return bei `sticks.isEmpty` |
| R5-F-06 | P1 | Strafkubb-Block nur auf Stock 1 + base>0 + !heli sichtbar — Stock-2..6-Strafkubbs gehen verloren, Cap `max: state.base` ignoriert remainingBase | R5-A-05, R5-B-08 | Bedingung lockern (penalty pro Stick erfassbar wenn `penaltyKubbTracking` und base/feld nicht clear); `max: base` durch `remainingBaseBeforeCurrent` ersetzen; `copyWith(heli: true, ...)` muss Penalty-Felder zurücksetzen |
| R5-F-07 | P1 | Verlängerung "Aufgeben" ohne Confirmation-Dialog — Misstap wirft 5 abgeschlossene Sticks weg, Asymmetrie zu handleBack | R5-A-04 | Confirm-Dialog vor `giveUp()`; Status-Semantik klären (completed vs. failed vs. aborted) und im Repository konsistent setzen |
| R5-F-08 | P1 | `advance()` nicht transaktional — DB-Insert + State-Wechsel + `markCompleted` können auseinanderlaufen, Crash zwischen Schritten = inkonsistenter Status | R5-B-04 | `recordStick` + Statusprüfung in `attachedDatabase.transaction`; `markCompleted` und `discard` mit try/catch + Re-Throw, damit UI-State nicht voreilig genullt wird |
| R5-F-09 | P1 | Repository-Fehler in `giveUp`/`complete`/`abortAndDelete` werden geschluckt — UI navigiert blind, Session bleibt "active" in DB | R5-B-05 | try/catch um `_repo`-Calls, Logger-Eintrag via `_log.severe`; bei Fehler `state = AsyncError(...)` für SnackBar; Routing erst nach erfolgreichem Future |
| R5-F-10 | P1 | Win-Check liest Settings live statt zur Session-Start-Zeit — Toggle mid-session ändert Win-Kondition retroaktiv | R5-B-09 | Settings beim `startSession` einfrieren (`FinisseurSettingsSnapshot` in `ActiveFinisseurState`); `_hasWon` und `_ensurePhase` nutzen Snapshot; Persistenz erweitern (Session-Tabelle bekommt `finKingTracking`, `finAllowContinue` etc.) |
| R5-F-11 | P1 | LongDubbie-Toggle nicht atomar — Spieler kann LongDubbie + Field=2 setzen, recordStick speichert (fieldHits:2, eightM:true) → Doppel-Zählung | R5-A-06 | LongDubbie-Toggle als atomare "set fieldHits:=1, eightM:=true" Operation; Field-Chips disablen wenn LongDubbie aktiv |
| R5-F-12 | P1 | PopScope onPopInvokedWithResult kann handleBack parallel zu laufendem advance() triggern — Doppel-Operation, Doppel-Routing | R5-B-11 | Lokales `_handlingBack`-Flag im Stateful-Wrapper, ignoriert Pop während async-Operationen; alternativ `canPop` dynamisch an Notifier-State binden |
| R5-F-13 | P2 | Dead Code `penalty1` wird weiterhin geschrieben — `StickResult.penalty1`, `recordStick` mit `penaltyHits1: Value(result.penalty1)`, `isUntouched`-Check, aber keine UI mehr | R5-B-07 | `penalty1` aus `StickResult` entfernen; `recordStick` lässt `penaltyHits1` weg (`Value.absent()`); Tabellen-Spalte für Audit-Zwecke behalten mit erklärendem Kommentar |
| R5-F-14 | P2 | Stepper-Swap-Logik unsichtbar — Field+ kann Base- ohne Hinweis dekrementieren, Spieler überrascht | R5-A-07 | Visuelle Animation auf Base-Counter beim Swap, oder Stepper sperren statt swappen mit deutlichem Constraint-Text |
| R5-F-15 | P3 | Spec-Doku-Lücke: keine dedizierte Finisseur-Spec in `docs/specs/`, Magic Numbers (`totalSticks=6`, `distanceMeters=8`, `_totalMax=10`, `_baseHardMax=5`) ohne Regelwerk-Verweis, UI erklärt Sniper-vs-Finisseur-Unterschied nicht | R5-C-03, R5-C-04, R5-C-05, R5-C-06, R5-C-07 | `docs/specs/finisseur-mode-spec.md` anlegen (Domain-Definition, Konfig-Parameter, Stock-Count-Regel, Distanz-Begründung, Strafkubb-Spezifikation, Verdict-Regeln); Ein-Zeilen-Doc-Kommentare an den Konstanten mit Verweis auf `docs/rules/README.md`; TrainingSheet-Mode-Picker Subtitle ergänzen |
| R5-F-16 | P3 | Summary firstWhere konstruiert Dummy-FinisseurStickEvent mit `stickIndex=-1` bei leerer Session — brüchig, nie testbar | R5-A-08 | Early-Return wenn `sticks.isEmpty`: dedizierte "Session ohne erfassten Wurf"-View statt Verdict-Rechnung; verschwindet ohnehin wenn R5-F-05 den 0/0-Pfad blockt |

**No-Issue / Konsolidierungs-Notizen:**
- R5-A-03 + R5-B-01 + R5-B-02 + R5-B-03 sind vier Hits auf denselben Race-Pattern aus dem Stick-Eingabe-Pfad (Doppel-Tap, fehlendes UNIQUE, fehlendes Lock) — als R5-F-01 gebündelt. Die Pattern-Klasse ist identisch zu R4-F-01/R3-F-04.
- R5-A-02 + R5-B-10 beschreiben dieselbe Crash-Recovery-Lücke aus zwei Winkeln (Provider deckt Finisseur nicht ab; Notifier.build() rehydratisiert nicht) — als R5-F-03 zusammengefasst.
- R5-A-05 + R5-B-08 sind beide der Penalty-Block-Stock-1-only-Bug, gleicher Code-Bereich, gleicher Fix — als R5-F-06 zusammengefasst.
- R5-C-01 und R5-C-02 sind Hunter-Annahmen auf Basis einer falschen Briefing-Beschreibung des Chef-Inspektors (siehe Chef-Anmerkung oben). Keine App-Bugs, keine Eskalation an Owner — die implementierte Modus-Definition ist die korrekte.
- R5-C-03 bis R5-C-07 (Stick-Count-6 hardcoded, Penalty-Tracking als Setting, Sniper-vs-Finisseur-Distanz-Unterscheidung, fehlende Regelwerk-Doc-Kommentare, fehlende Spec in `docs/specs/`) sind alle interne Documentation-/Domain-Klarheits-Hinweise — als R5-F-15 gebündelt, da kein direkter Funktionsdefekt vorliegt.
- Keine False-Positives auf App-Code-Ebene identifiziert.

**Zusammenfassung:** Fünf P0-Findings dominieren die Runde — der Stick-Eingabe-Pfad ist weder serialisiert noch idempotent (R5-F-01, gleiche Race-Pattern-Klasse wie R3-F-04/R4-F-01, vier Hunter-Treffer auf denselben Code), der Doppel-Start-Tap erzeugt parallele Sessions (R5-F-02), die Crash-Recovery deckt Finisseur komplett nicht ab und löscht stillschweigend stale-Sessions beim Restart (R5-F-03), der Rollback wirft Stick-Daten weg statt sie wie dokumentiert wiederherzustellen (R5-F-04), und der ConfigScreen erlaubt 0/0-Sessions ohne Sanity-Check (R5-F-05). Die sieben P1-Findings adressieren Penalty-Block-Stock-1-only mit unsynchronem Cap, fehlenden Confirm-Dialog beim Verlängerungs-Aufgeben, nicht-transaktionale advance()-Sequenz, geschluckte Repository-Fehler, live-gelesene Settings (Win-Kondition kann mid-session kippen), LongDubbie-Doppel-Zählung und einen PopScope-handleBack-Race. P2/P3 sind Dead Code (`penalty1`-Reliquie), unsichtbarer Stepper-Swap und die Spec-Doku-Lücke (R5-F-15, die fünf R5-C-Befunde gebündelt). Mehrfach-Hit-Muster: Race-Conditions und Daten-Persistenz-Lücken sind der rote Faden — Hotfix-Wave gleiche Architektur wie nach R4 (Mutex + UNIQUE-Constraint + transaktionale Schreibpfade), diesmal zusätzlich mit Crash-Recovery-Vereinheitlichung für beide Trainings-Modi.


### Runde 6 — Tournament-Setup-Wizard

**Hunter-Output**: A=17, B=10, C=12 → konsolidiert auf 18 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R6-F-01 | P0 | KO-Phase nicht erzwungen, Pure-KO-Format nicht selektierbar — `_FormatRow.enabled` nur für `roundRobin` und `swiss`, alle KO-Varianten sind als "Coming Soon" disabled; reine Vorrunden landen ohne KO in der DB | R6-A-02, R6-C-01, R6-C-02 | `enabled`-Whitelist in `_FormatRow` auf alle MUSS-Formate erweitern (FR-FMT-1..7), Server-Whitelist in Migration `20260525000002 p_format` parallel anpassen; alternativ `requiresKoConfig` für reine `roundRobin`/`swiss` als KO-Pflicht umlegen |
| R6-F-02 | P0 | Tiebreaker-Step + Liga-Punkte-Step existieren als Widget, sind aber im Wizard nicht verdrahtet — `_StepKind` kennt sie nicht, `WizardTiebreakerStep`/`WizardLeaguePointsStep` werden nirgends importiert; FR-CFG-13 + FR-POINTS-8 + FR-CFG-16 nicht erreichbar | R6-A-03, R6-A-04, R6-C-06 | `_StepKind.tiebreaker` und `_StepKind.leaguePoints` ergänzen, in `_visibleSteps` einhängen (Tiebreaker zwischen koConfig und summary, LeaguePoints nach league bei `leagueEligible: true`), `pointsMode`/`seasonId`-Felder im Draft anlegen; `controller.setTiebreakerOrder` ans Step-Widget binden |
| R6-F-03 | P0 | Numpad fehlt für min/max participants und sets_to_win/maxSets — `_NumberStepper` rendert nur Text, kein TextField; 16+ Taps zum Hochstellen, bei Max=200 wird es absurd | R6-A-01, R6-B-07, R6-C-03 | `_NumberStepper` um TextField-Variante erweitern oder zweites Widget `_NumberInput` mit `keyboardType: TextInputType.number` + `FilteringTextInputFormatter.digitsOnly`; Reuse-Pattern existiert in `_wizard_pool_config_step.dart:195-209` und `_wizard_ko_config_step.dart:145-148` |
| R6-F-04 | P0 | Summary-Step zeigt Format hartkodiert als `tournamentWizardFormatRoundRobin` — egal welcher Format-Wert im Draft steht; KO-, Pool-, Liga- und Tiebreaker-Konfig werden nicht im Summary angezeigt, User reviewt blind | R6-A-12, R6-B-06, R6-C-11 | `_humanFormatLabel(draft.format)` im Summary nutzen statt Hardcode; zusätzliche `_summaryRow`-Einträge für KO-Config (qualifierCount, withBronze, seedingMode), Pool-Config (groups, qualifiersPerGroup), Liga (eligible), Tiebreaker-Chain, Swiss-Rounds; bei `validate().issues` die Liste mit "zurück zum Step"-Affordance anzeigen |
| R6-F-05 | P0 | Format-Kacheln ohne Erklärung — nur Label + Coming-Soon-Chip, keine Subtitle, kein Helper-Text; "Schoch" ist Schweizer Sprachgebrauch, "Schweizer System" wird nicht abgegrenzt zu Round Robin | R6-A-05, R6-C-04, R6-C-10 | `_FormatRow` um `description`-Parameter erweitern, 1-2-Zeilen-Texte aus `tournament-mode-spec.md §3.8` übernehmen; in `SwissConfigSection` zusätzlich einen Info-Block (Buchholz/Sonneborn-Berger als Tiebreaker, ungefähre Match-Anzahl) oberhalb der Rundenzahl |
| R6-F-06 | P0 | Step-Back-Verlust: Format-Wechsel resettet KO-, Pool- und Liga-State im Draft nicht — Zombie-Konfig im Draft (roundRobin mit verbliebener `poolPhaseConfig`); zusätzlich postFrameCallbacks in KO-/Pool-Step pushen ohne `mounted`-Check | R6-A-07, R6-A-08, R6-B-03, R6-B-04, R6-B-09 | `controller.setFormat` cleart `koConfig`/`bracketSeedingMode`/`poolPhaseConfig`, wenn das neue Format sie nicht mehr verlangt; `_poolPhaseEnabled` aus `draft.poolPhaseConfig != null` ableiten statt eigener State; `addPostFrameCallback`-Bodies mit `if (!mounted) return;` einleiten |
| R6-F-07 | P0 | KO-Grössen-Quick-Picker fehlt — `WizardKoConfigStep` zeigt nur Free-Integer `qualifierCount`, Bracket-Size (4/8/16/32/64) wird via `_nextPow2` abgeleitet aber nicht direkt wählbar; mental load für Veranstalter | R6-A-09, R6-C-06 | Kachel-Auswahl "Achtelfinal / Viertelfinal / Halbfinal / Final" über dem qualifierCount-Feld; bei Tap setzt sie qualifierCount auf die jeweilige Power-of-Two, free-text-Feld bleibt für Zwischenwerte; max-Cap weiter an `maxParticipants` |
| R6-F-08 | P0 | Submit-Pipeline fragil — `_submit` liest Draft einmal früh, `on Object catch (e)` schluckt alles (auch `OutOfMemoryError`), `StateError` aus `TournamentActions.createTournament` landet als kryptische SnackBar; keine differenzierte Fehlerbehandlung, kein Logging | R6-B-01, R6-B-02 | Im `_submit` zweites `draft.validate()` direkt vor RPC-Call mit lokalisierter Fehlermeldung; `on PostgrestException`, `on TimeoutException`, `on StateError` separat catchen mit passenden l10n-Strings; `TournamentDraftInvalidException` aus Domain werfen statt `StateError`; final `on Object catch (e, st)` mit `developer.log`-Forward |
| R6-F-09 | P1 | Schweizer-Runden-Slider persistiert nicht — `_swissRounds` lebt nur als StatefulWidget-Member, `TournamentConfigDraft` kennt kein `swissRounds`-Feld, beim Submit verworfen; Slider ist Augenwischerei | R6-A-06 | `swissRounds` als optional-Feld im `TournamentConfigDraft`, `setSwissRounds`-Setter im Controller, beim Submit ans RPC weiterreichen; Server-Seite muss das Feld akzeptieren (Migration-Anpassung an `tournament_create`) |
| R6-F-10 | P1 | Doppel-KO als Coming-Soon-Sektion fehlt komplett — Domain-Enum `TournamentFormat` hat keine `doubleElimination`-Variante, KO-Step zeigt keinen Switch; FR-FMT-9 (KANN) und MÄNGEL #8 (UI-Vorbereitung) nicht abgedeckt | R6-A-10, R6-C-05 | Zweiter Switch "Doppel-Elimination" neben Bronze-Switch im `WizardKoConfigStep`, `enabled: false` + Coming-Soon-Pille; Domain-Backlog-Marker `match_format_config.ko.bracket_type ∈ {single_elimination, double_elimination}` dokumentieren |
| R6-F-11 | P1 | Validation-Drift zwischen `_stepValid` und `draft.validate()` — Wizard prüft beim Format-Step nur `setsToWinMin`, nicht `setsToWinMax`; Name-Step erlaubt Whitespace-only-Namen ≥3 Zeichen bis zum Summary; magic `9` im Stepper widerspricht `setsToWinMax=4` der Domain | R6-A-13, R6-A-17, R6-B-05, R6-B-07 | `_stepValid` per Step über `draft.validate().issues` mit Step-Prefix filtern (`name.*`, `participants.*`), `name.trim().isNotEmpty &&` length-bound im Wizard ergänzen; `TournamentConfigDraft.maxSetsHardMax = 2 * setsToWinMax - 1` als Konstante, Stepper-Max daraus ableiten |
| R6-F-12 | P1 | Helper-/Co-Veranstalter-Setup + Veranstalter-Identität (FR-CFG-17) fehlen im Wizard — keine Wahl "im eigenen Namen / im Namen eines Vereins", keine Co-Veranstalter-Einladung, keine Helper-Rollen | R6-C-07 | `_StepKind.organizerIdentity` zwischen name und participants mit Radio "eigener Name" / "im Namen von <Verein-Picker>"; Co-Veranstalter-Einladung als eigene Sektion im Detail-Screen (kann nach Create laufen), im Wizard mindestens Hinweis-Banner |
| R6-F-13 | P1 | KO-Config speichert `participantCount = maxParticipants` — bei realer Registrierung < max wird Bracket auf falscher Basis gerechnet | R6-A-11 | `participantCount` zur Tournament-Start-Zeit aus registrierten Teams ableiten, nicht beim Setup einfrieren; KO-Step speichert nur qualifierCount + Flags |
| R6-F-14 | P1 | Mehrere FR-CFG-MUSS-Felder im Wizard nicht abgefragt — Score-System (FR-CFG-6), Pitches (FR-CFG-9), BYE-/Forfeit-Score (FR-CFG-10/11), Anspielregel (FR-CFG-14), Anmeldefenster (FR-CFG-3), Sichtbarkeit (FR-CFG-4), Teamgrösse (FR-CFG-1) | R6-C-08 | "Erweitert"-Step oder Sektionsgruppen pro Themenblock einführen: Match-Format-Step (BYE/Forfeit/Anspiel), Registration-Step (Anmeldefenster + Sichtbarkeit + Teamgrösse); mit M3-Backlog abstimmen |
| R6-F-15 | P1 | Liga-Step ist Boolean-Switch statt Liga-Multi-Select — FR-CFG-15 verlangt "welche Ligen am Turnier teilnehmen dürfen", aktuell nur `leagueEligible: bool`; Shared-Tournament-Detection nicht möglich | R6-C-09 | `_LeagueStep` zu Multi-Select-Picker, `eligibleLeagues: Set<LeagueRef>` im Draft statt `bool`; Shared-Tournament automatisch erkennen bei `|set| > 1` |
| R6-F-16 | P2 | Performance — `ref.watch` auf ganzen Draft im Wizard-Build triggert Vollrebuild bei jedem Tastendruck im Name-Field und jedem Stepper-Klick; Scaffold + AppBar + ProgressBar + BottomBar bauen unnötig neu | R6-B-08 | BottomBar in eigenes ConsumerWidget mit `tournamentConfigControllerProvider.select((d) => _stepValid(d))`; Step-Body via `Consumer`-Builder pro Step nur relevante Felder selecten |
| R6-F-17 | P2 | Hartkodierte deutsche Strings statt l10n im Wizard — `'Pool-Phase'`, `'Wert zwischen 2 und $participants erforderlich.'`, `'Seeding-Quelle'`, `'Automatisch aus Gruppenphase'`, `_humanFormatLabel` komplett; verletzt Projekt-Convention | R6-C-12 | ARB-Keys ergänzen in `app_de.arb`, `flutter gen-l10n`, alle Stellen umstellen; `_humanFormatLabel` per `AppLocalizations.tournamentFormat<X>` lookup |
| R6-F-18 | P3 | Kein Wizard-Abbruch auf Step 0 — AppBar-Leading ist `null` bei `stepIndex==0`, kein Cancel-Action; Pop-Geste verwirft alles ohne Bestätigung; zusätzlich Domain-Helpers `_nextPow2`/`_prevPow2`/`_smartDefault` als private statics einer State-Klasse statt im Domain-Package | R6-A-16, R6-B-10 | "Abbrechen"-Action in der AppBar mit Confirm-Dialog bei unsaved changes; `_nextPow2`/`_prevPow2`/`_smartDefault` als Top-Level oder static auf `KoPhaseConfig` ins Domain-Package heben |

**No-Issue / Konsolidierungs-Notizen:**
- R6-A-02 + R6-C-01 + R6-C-02 sind drei Treffer auf denselben Format-Whitelist-Block in `_FormatRow.enabled` — gebündelt als R6-F-01. Die Spec-Konsequenz (KO-Pflicht + alle MUSS-Formate) zieht beide Punkte zusammen.
- R6-A-03 + R6-A-04 + R6-C-06 sind drei Treffer auf das Verdrahtungs-Loch der vorhandenen Step-Widgets (Tiebreaker, LeaguePoints, KO-Grösse-Picker) — als R6-F-02 zusammengefasst; KO-Grössen-Quick-Picker ist eigener Punkt R6-F-07, weil das Widget noch nicht existiert.
- R6-A-01 + R6-B-07 (magic `9` im Stepper) + R6-C-03 sind drei Treffer auf den `_NumberStepper`-ohne-TextField-Pfad — als R6-F-03 zusammengefasst; der magic-`9`-Aspekt überlappt mit R6-F-11 (Validation-Drift).
- R6-A-12 + R6-B-06 + R6-C-11 sind drei Treffer auf den hartkodierten Round-Robin-String im Summary — als R6-F-04 gebündelt.
- R6-A-05 + R6-C-04 + R6-C-10 sind drei Treffer auf fehlende Format-Erklärungen (Kacheln + Swiss-Sektion) — als R6-F-05 zusammengefasst.
- R6-A-07 + R6-A-08 + R6-B-03 + R6-B-04 + R6-B-09 sind fünf Treffer auf Step-Back-/Format-Wechsel-State-Inkonsistenzen — als R6-F-06 gebündelt. Pattern-Klasse identisch: lokaler StatefulWidget-State driftet vom Draft, Format-Wechsel räumt nicht auf, postFrameCallbacks ohne mounted-Check.
- R6-A-10 + R6-C-05 beschreiben dieselbe Doppel-KO-UI-Lücke — als R6-F-10 zusammengefasst.
- R6-A-13 + R6-A-17 + R6-B-05 + R6-B-07 sind vier Treffer auf Validation-Drift / magic numbers in den Stepper-Caps — als R6-F-11 gebündelt.
- R6-A-14, R6-A-15 wurden nicht in finale IDs überführt: R6-A-14 (didUpdateWidget fehlt im NameStep) ist ein theoretischer Pfad, der heute nicht getriggert wird (Controller wird nicht von aussen resettet); R6-A-15 (Display-vs-Effective-Inkonsistenz der Tiebreaker-Chain im SwissConfigSection) ist eine reine Cosmetic-Sache, die mit R6-F-02 (Tiebreaker-Step verdrahten) automatisch verschwindet — Owner-Sichtbarkeit reicht.
- Keine False-Positives auf App-Code-Ebene identifiziert.

**Zusammenfassung:** Acht P0-Findings dominieren die Runde — der Wizard erzwingt die KO-Phase nicht und blockiert alle KO-Format-Varianten als "Coming Soon" obwohl die Step-Widgets im Code existieren (R6-F-01), zwei dieser Widgets (Tiebreaker + LeaguePoints) sind komplett toter Code weil sie nirgends in `_StepKind`/`_visibleSteps` eingehängt sind (R6-F-02), Numpad-Eingabe fehlt für die Stepper trotz Reuse-Pattern im KO-/Pool-Step (R6-F-03), das Summary zeigt Format hartkodiert als "Round Robin" und lässt KO-/Pool-/Liga-/Tiebreaker-Konfig komplett weg (R6-F-04), Format-Kacheln und Swiss-Sektion bieten keine Erklärung (R6-F-05), Format-Wechsel resettet weder den Draft-State noch den lokalen Widget-State und die postFrameCallbacks pushen ohne mounted-Check (R6-F-06), der KO-Grössen-Quick-Picker fehlt komplett (R6-F-07), und die Submit-Pipeline ist mit `on Object catch (e)` + spätem Draft-Read fragil (R6-F-08). Auf P1-Ebene fehlen Doppel-KO-UI-Vorbereitung, ein Block an FR-CFG-MUSS-Feldern (Score-System, Pitches, BYE/Forfeit, Anspielregel, Anmeldefenster, Sichtbarkeit, Teamgrösse), die Liga-Multi-Select-Auswahl, der Veranstalter-Identitäts-Step, die Swiss-Rounds-Persistenz und die KO-`participantCount`-Korrektheit. Mehrfach-Hit-Muster: drei Hunter melden unabhängig dieselben fünf Spec-Lücken (KO-Pflicht, Numpad, Summary-Hardcode, fehlende Format-Erklärung, Tiebreaker-/LeaguePoints-Verdrahtung) — die Wizard-Implementierung hat die UI-Skelette aus M1 hinterlegt aber den Owner-Briefing nach MÄNGEL #4-#8 nicht eingearbeitet. M2-Polish-Wave braucht zwei Sub-Phasen: erst Verdrahtung der toten Step-Widgets + Format-Whitelist-Öffnung (R6-F-01, R6-F-02, R6-F-07), dann Spec-Konformitäts-Auffüllung (R6-F-12 bis R6-F-15) mit eigenem ADR für `eligibleLeagues` und `organizerIdentity` im Draft.


### Runde 7 — Tournament-Liste + Filter

**Hunter-Output**: A=11, B=10, C=9 → konsolidiert auf 15 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R7-F-01 | P0 | Provider-Duplikat `tournamentListProvider` — Screen watcht die family-Variante, `TournamentActions` invalidiert die no-arg-Variante; Lifecycle-Aktionen (create/publish/openRegistration/start/finalize/abort/register/withdraw/confirm/reject/override) machen die UI nicht stale-frei, der User wartet bis zum nächsten 5s-Polling-Tick | R7-A-07, R7-B-01 | No-arg-Provider aus `tournament_providers.dart` entfernen, alle `_ref.invalidate(tournamentListProvider)`-Calls in `TournamentActions` auf `_ref.invalidate(tournamentListProvider(null))` umstellen; Screen-Watch bleibt unverändert; doppel-Fetch pro Frame verschwindet als Nebeneffekt |
| R7-F-02 | P0 | Public-Tab ohne anon-Pfad — `listTournaments` setzt `auth.uid()` voraus, M4.2-RLS-Politik für public/finalized/live ist vom Client nicht erreichbar; nicht-eingeloggte Spectators bekommen Auth-Error statt Public-Liste | R7-C-03 | Anon-fähigen RPC-Pfad (oder direkten `tournaments`-Select mit Anon-RLS) im `TournamentRemote` ergänzen; `tournamentListProvider` schaltet auf den Anon-Pfad wenn `currentUserIdProvider == null`; Server-Migration für anon-readable Policy auf `published/registrationOpen/registrationClosed/live/finalized` |
| R7-F-03 | P0 | Mine-Tab leer für Anon ohne Login-CTA — Filter `myUserId != null && s.createdBy?.value == myUserId` ist pauschal false, User sieht `tournamentListEmptyMine` ("Keine Turniere") obwohl der echte Grund "nicht eingeloggt" ist | R7-A-01 | Anon-Branch im Mine-Tab: statt Empty-State Login-Prompt mit CTA `tournamentListAnonSignInPrompt` + Button zum Auth-Flow; ARB-Key ergänzen; `myUserId == null` als eigener `_Tab`-State-Zweig |
| R7-F-04 | P0 | Drei Spec-Sichten (Mine/Aktuelle/Public) kollabieren auf zwei Tabs — Public-Tab vermischt `registrationOpen`/`registrationClosed`/`live` ohne Subsicht, FR-PUB-2/§6.5 nicht erfüllt | R7-C-02, R7-A-04 | Dritten Tab "Aktuelle" einführen (oder Subfilter-Chips im Public-Tab): `Aktuelle` = `registrationOpen` + `registrationClosed`, `Public/Live` = `live` + `finalized` (jüngste); Mine bleibt unverändert |
| R7-F-05 | P0 | Polling-Race / Hintergrund-Polling — `tournamentListPollingProvider` invalidiert alle 5s, ohne AppLifecycleState-Awareness; läuft auch im Hintergrund-Tab, im Loading- und Error-State, kann während laufendem Fetch eine zweite Request anstossen | R7-A-06, R7-B-02, R7-B-04 | Polling pausieren wenn `WidgetsBinding.lifecycleState != resumed`; in-flight-Guard im Provider (skip wenn vorherige Future noch läuft); Errors aus invalidate-Triggern via `ref.listenSelf` an Logger; tick auf 10–15s anheben |
| R7-F-06 | P0 | Filter Liga/Region/Verein fehlen komplett — §6.5 verlangt Discovery-Filter, Screen hat nur Mine/Public-Tab; FR-PUB-2/FR-CFG-15-Discovery-Seite nicht umgesetzt | R7-C-01 | Filter-Sheet (Bottom-Sheet) mit Multi-Select für Liga, Region (Kanton), Verein; Filter-State in Riverpod-Notifier, an `listTournaments` als Optional-Argument durchreichen; Server-RPC akzeptiert die Filter-Liste; Empty-State zeigt aktive Filter mit "Filter zurücksetzen"-CTA |
| R7-F-07 | P0 | Bracket-Tap fehlt (FR-PUB-6) — Liste hat keinen Quick-Access zur Bracket-Visualisierung, jeder Tap auf Card geht stur in den Detail-Screen | R7-C-04 | Sekundäre Action auf der `TournamentCard` (z.B. Icon-Button "Bracket"), nur sichtbar wenn `status in {live, finalized}`; navigiert direkt auf `TournamentRoutes.bracket(t.tournamentId.value)`; alternativ Long-Press-Sheet mit "Detail / Bracket / Standings" |
| R7-F-08 | P0 | Status-Pills uniformiert — Card zeigt keine sichtbare Status-Pill in Liste, Spec verlangt klare Differenzierung von Draft/Published/RegistrationOpen/Live/Finalized | R7-C-05, R7-A-08 | `TournamentStatusPill` zwingend in `TournamentCard` einbinden (top-right der Card), 5 Farbcodes über `KubbTokens` (draft=neutral, published=info, registrationOpen=primary, live=success, finalized=muted); ARB-Strings für jeden Status |
| R7-F-09 | P1 | Numpad-/Pull-to-Refresh fehlt — ListView.separated ohne `RefreshIndicator`, einziger Refresh ist der 5s-Timer; nach Lifecycle-Action kein User-getriebener Refresh möglich | R7-A-02 | `RefreshIndicator` um beide `_Tab`-ListViews; `onRefresh: () async => ref.refresh(tournamentListProvider(null).future)`; Empty-State ebenfalls scrollbar machen (SingleChildScrollView + AlwaysScrollableScrollPhysics) damit Pull-Geste auch dort greift |
| R7-F-10 | P1 | Permission-Aware-Filter fehlt — Lukas-Helfer-Sicht (Helper sieht Tournaments wo er als `helper`/`co_organizer` eingetragen ist) hat keinen eigenen Tab oder Filter; Helper landet im "Mine"-Tab leer, weil `createdBy.value != myUserId` | R7-C-06 | `TournamentSummaryRef` um `myRole`-Feld erweitern (server-side aggregiert: `organizer/helper/co_organizer/registered/spectator`); Mine-Tab Filter auf `myRole in {organizer, co_organizer, helper}`; ggf. dedizierter "Mitwirkung"-Tab |
| R7-F-11 | P1 | Rohe Error-Messages — `Text(e.toString())` zeigt `PostgrestException`/`TypeError`-Strings statt lokalisierter Fehlermeldungen; keine Retry-Action im Error-State | R7-A-05, R7-B-07 | `ErrorView`-Widget mit l10n-Mapping (PostgrestException → `tournamentListErrorBackend`, TimeoutException → `tournamentListErrorTimeout`, sonst → `tournamentListErrorGeneric`); Retry-Button ruft `ref.refresh(tournamentListProvider(null))`; rohe Message als kollabierbares Debug-Detail nur in `kDebugMode` |
| R7-F-12 | P1 | Filter-Argument an Polling/List-Provider wird ignoriert — Screen ruft `tournamentListPollingProvider(null)` und `tournamentListProvider(null)` mit hardcoded `null`, Status-Filter ist nie aktiv obwohl die family-Signatur ihn vorsieht | R7-C-07 | Filter-State (siehe R7-F-06) durchreichen: `ref.watch(tournamentListProvider(filterState.statusFilter))` und identisch beim Polling-Provider; Tab-spezifischer Filter (Mine vs. Aktuelle vs. Public) als verschiedene family-Keys, damit Tab-Wechsel separate Caches nutzt |
| R7-F-13 | P2 | Hardcoded `limit=50` ohne Pagination — silent truncation ab 51 Tournaments, Liste wird nie länger | R7-B-09 | Pagination via `limit/offset` im RPC, `ScrollController.position.pixels >= maxScrollExtent - 200` triggert Nachlade-Request; `PagedListView` von `infinite_scroll_pagination` oder eigenes Lazy-Loading; Server-Migration für stable `cursor`-Pagination |
| R7-F-14 | P2 | Listen-Performance — ListView ohne ItemKeys (Card-State leakt zwischen Identitäten), beide Tabs rebuilden komplett bei jeder Polling-Invalidation, kein `select`-Narrowing | R7-B-05, R7-B-06, R7-A-03 | `ValueKey(t.tournamentId)` an jeder TournamentCard; `AutomaticKeepAliveClientMixin` an `_Tab` damit Scroll-Position bei Tab-Wechsel erhalten bleibt; Filter-Closure als top-level-Funktion (stable `==`); ggf. `tournamentListProvider(null).select((rows) => rows.where(filter).toList())` |
| R7-F-15 | P3 | Sekundär-Polish — Sort-Order nicht definiert (Server-Order), FAB-Overlap bei TextScaler>1.5, A11y-Semantics fehlen, Map-View (§6.5) nicht angelegt, TabController ohne Listener-Cleanup-Pattern, Mine-Filter teilweise dead code (RLS macht es serverseitig) | R7-A-09, R7-A-10, R7-A-11, R7-B-03, R7-B-08, R7-B-10, R7-C-08, R7-C-09 | Bündel-Polish-Commit: clientseitiges `sort` (createdAt desc oder status-priority), Bottom-Padding `space14` bei extremer Skalierung, `Semantics(header/liveRegion)` an Loading/Empty/Error, Map-View als M-zukünftiger Backlog-Punkt notieren, autoDispose+listener-Cleanup im TabController, Mine-Filter dokumentieren als "Redundanz für UI-Optimismus, RLS bleibt Truth Source" |

**No-Issue / Konsolidierungs-Notizen:**
- R7-A-07 + R7-B-01 sind derselbe Provider-Duplikat-Bug aus zwei Lens-Winkeln (User-Flow: stale Liste nach Write; Code-Smell: doppel-Fetch pro Frame) — als R7-F-01 gebündelt. Konsolidierung war in CLAUDE.md schon als M2-Seam vermerkt, jetzt aufgewertet zu P0 weil mehrere Lifecycle-Actions die UI breaken.
- R7-A-06 + R7-B-02 + R7-B-04 sind drei Treffer auf den Polling-Loop ohne Lifecycle-Awareness/in-flight-Guard/Error-Logging — als R7-F-05 gebündelt.
- R7-A-04 + R7-C-02 sind beide der Mine/Aktuelle/Public-Spec-Drift — als R7-F-04 zusammengefasst.
- R7-C-01 + R7-C-02 wurden auseinandergehalten: die §6.5-Filter (Liga/Region/Verein) sind ein eigenständiger Feature-Gap (R7-F-06), die Drei-Sichten-Drift ist eine Tab-Strukturfrage (R7-F-04).
- R7-A-08 + R7-C-05 sind derselbe Status-Pill-Defekt (uniformiert/fehlt in Card) — als R7-F-08 gebündelt.
- R7-A-05 + R7-B-07 sind beide rohe `e.toString()`-Ausgabe — als R7-F-11 zusammengefasst.
- R7-A-03 + R7-B-05 + R7-B-06 sind drei Treffer auf Listen-Performance (KeepAlive, Keys, Rebuilds) — als R7-F-14 gebündelt.
- R7-A-09, R7-A-10, R7-A-11, R7-B-03, R7-B-08, R7-B-10, R7-C-08, R7-C-09 sind Polish-/A11y-/Sekundär-Punkte ohne direkten User-Flow-Defekt — als R7-F-15 gebündelt.
- Keine False-Positives auf App-Code-Ebene identifiziert.

**Zusammenfassung:** Acht P0-Findings dominieren die Runde — das Provider-Duplikat `tournamentListProvider` (no-arg in `tournament_providers.dart`, family in `tournament_list_provider.dart`) führt dazu dass alle Lifecycle-Actions in `TournamentActions` die UI nicht stale-frei machen (R7-F-01), der Public-Tab ist für nicht-eingeloggte User unerreichbar weil `listTournaments` zwingend `auth.uid()` braucht und die M4.2-RLS-Policy für anon nie aktiv wird (R7-F-02), der Mine-Tab zeigt Anon-Nutzern irreführendes Empty-State statt Login-CTA (R7-F-03), drei Spec-Sichten kollabieren auf zwei Tabs (R7-F-04), das 5s-Polling läuft lifecycle-blind und race-anfällig (R7-F-05), die §6.5-Filter Liga/Region/Verein fehlen komplett (R7-F-06), der Bracket-Quick-Access nach FR-PUB-6 fehlt (R7-F-07), und die Status-Pills sind in der Card-Ansicht uniformiert/unsichtbar (R7-F-08). Auf P1-Ebene fehlen Pull-to-Refresh, der Permission-Aware-Filter für die Helper-Sicht, die lokalisierte Error-Behandlung und die Aktivierung des Status-Filter-Arguments. P2/P3 sind Listen-Performance (Keys, KeepAlive, Rebuild-Narrowing), Pagination ab 50+ Tournaments und ein Bündel Sekundär-Polish (Sort-Order, A11y, FAB-Overlap, Map-View-Backlog). Mehrfach-Hit-Muster: drei Hunter melden unabhängig dasselbe Provider-Duplikat (R7-F-01) und denselben Polling-Race (R7-F-05); der Public-Tab ohne anon-Pfad (R7-F-02) ist ein M4.2-Server/Client-Integrations-Loch und braucht parallel zur UI-Anpassung eine RLS-Policy-Erweiterung. Hotfix-Wave-Schnitt: R7-F-01 + R7-F-05 zuerst (reine Client-Aufräumung, kein Server-Touch), dann R7-F-02 mit Server-Migration und Anon-RPC, dann R7-F-03/04/06/07/08 als UI-Spec-Konformitäts-Wave mit ARB-Updates und TournamentCard-Refactor.

### Runde 8 — Tournament-Detail + Status-Aware-Actions

**Hunter-Output**: A=12, B=11, C=8 → konsolidiert auf 16 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R8-F-01 | P0 | Action-Buttons ohne Reentrancy-Schutz — Doppel-Tap auf publish/openReg/closeReg/start/finalize/abort/withdraw/approve/reject feuert parallele RPCs, `_safe` wrappt nur try/catch ohne Disable | R8-A-02, R8-B-01 | `_Actions` zu `ConsumerStatefulWidget` mit `bool _busy` (oder `AsyncActionGuard`-Helper), `mk(...).onPressed: _busy ? null : onTap`, Spinner im Button-Slot während Calls; gilt auch für `_participantRow` Approve/Reject |
| R8-F-02 | P0 | Keine Confirmation-Dialoge für destruktive Actions — `abortTournament` (terminal-status), `finalizeTournament` (irreversibel), `rejectRegistration`, `withdrawRegistration`, `closeRegistration` direkt one-tap-feuerbar | R8-A-01, R8-B-02 | `showDialog<bool>` vor `actions.abortTournament`/`rejectRegistration`/`withdrawRegistration`/`finalizeTournament`/`closeRegistration` mit Cancel/Confirm; ARB-Keys `tournamentDetailConfirm<Action>Title/Body/Confirm/Cancel`; Pattern aus `tournament_override_screen.dart` reuse; bei Abort zusätzlich Reason-Feld |
| R8-F-03 | P0 | Provider-Duplikat `tournamentListProvider` + fehlender Detail-Invalidate — `TournamentActions` invalidiert die no-arg-Variante (Listen-Screens nutzen family); zusätzlich invalidiert keine Action `tournamentDetailProvider(id)`, Detail-Screen zeigt nach Tap bis zu 5s alten Status | R8-B-03, R8-B-04, R7-F-01 | No-arg-Provider aus `tournament_providers.dart` entfernen, alle `_ref.invalidate(tournamentListProvider)`-Calls auf family umstellen; zusätzlich in allen Lifecycle-/Participant-Actions `_ref.invalidate(tournamentDetailProvider(id))` ergänzen; Participant-Actions um `TournamentId`-Parameter erweitern |
| R8-F-04 | P0 | Co-Veranstalter-/Helper-Rolle hat keine Sichtbarkeit — gesamte Permission-Logik hängt an `isCallerCreator(myUserId)`; eingeladene Co-Organizer und Helper sehen weder pending Anmeldungen noch Approve/Reject-Buttons noch Lifecycle-Transitions noch Live-Dashboard | R8-A-05, R8-A-06, R8-C-01, R8-C-06 | `TournamentDetail` um `callerRole` (creator/co_organizer/helper/player/spectator) erweitern, Server-seitig aus `tournament_organizer_roles`-Tabelle (FR-ADM-13) ableiten; UI: `canManage = role in {creator, co_organizer}` als Gate statt `isCreator`, `_participantRow.isOrganizer` umbenennen zu `canManageRegistration`; im live-Branch Matches-Button auf `isCreator \|\| me != null` öffnen |
| R8-F-05 | P0 | Public-Link / Spectator-Share-Surface fehlt komplett — `/public/tournament/:id`-Route ist im Router verdrahtet, aber kein Share-Button/QR/Copy-Link im Detail-Screen; M4.2-T5/T8 nicht erfüllt, Demo-Script Schritt 4 blockiert | R8-C-02 | Share-Button im Actions-Block ab `status >= published`: `Share.share('https://kubb.app/public/tournament/${id.value}')` über `share_plus` (bereits in `csv_share_service.dart` integriert); optionales QR-Modal mit `qr_flutter` als neue Dep (ADR-pflichtig); RLS-Server-Migration erlaubt anon SELECT auf `status != draft` |
| R8-F-06 | P0 | Spectator-Pfad ohne Auth zeigt Register-Button — bei `myUserId == null` rendert Detail-Screen im `registrationOpen`-Branch den "Anmelden"-Button, Tap führt zu MAENGEL #9-Auth-Crash (ERRCODE 42501) | R8-C-03 | `isSpectator = myUserId == null`; Actions-Block unterdrücken bis auf Bracket/Standings/Share; "Login zum Anmelden"-CTA mit Deep-Link-Return auf Detail-Screen analog Match-Detail-Pattern |
| R8-F-07 | P1 | Rohe Exception-Messages im SnackBar und Top-Level-Error — `_safe` rendert `Text('$e')` mit `PostgrestException`/`OverrideKoPairingException`-Strings; Stacktrace verloren, keine Retry-Action, keine i18n; Roster-/Pool-Card schluckt zusätzlich Netzwerk-/Auth-Fehler als "leer" | R8-A-03, R8-B-05, R8-B-09 | `_safe` mit Exception-Mapping auf l10n-Keys (`PostgrestException.code/hint` → ARB), Generic-Fallback + `developer.log(name: 'tournament', error: e, stackTrace: st)`; Roster-/Pool-Card prüft Phase-Token (`POOL_PHASE_NOT_STARTED`, `ROSTER_NOT_AVAILABLE`) → leer-Anzeige, alles andere → Error-Banner mit Retry; Top-Level-Detail-Fehler mit Retry-Button statt nur Text |
| R8-F-08 | P1 | Live-Dashboard-Button ungated für Veranstalter — im `draft`/`published`-Status sichtbar, öffnet leeres Grid; Code-Kommentar bekennt "discoverable from draft through finalized", widerspricht aber FR-LIVE-1 (Turniertag-Kontext) | R8-A-07, R8-C-04 | Gating auf `status in {registrationClosed, live, finalized}`; bei `finalized` als Read-only-Archiv-Label; alternativ disabled mit Tooltip "verfügbar ab Turnierstart" |
| R8-F-09 | P1 | Status-Action-Matrix unvollständig — `registrationOpen` zeigt nur closeReg ohne Anmeldungs-Management/Warteliste/Seeding/Check-In/Co-Org-Einladung; `registrationClosed` ohne Seeding-Button vor Start; non-creator sieht in draft/published/registrationClosed/finalized-non-final komplett leere Actions ohne Status-Hint | R8-A-05, R8-C-05 | Status-Matrix pro Phase ausbauen: draft/creator = Publish + Edit + Abort, published/creator = openReg + Edit + Abort, registrationOpen/creator = closeReg + Anmeldungs-Management + Co-Org-Einladung + Abort, registrationClosed/creator = Seeding-Tool + Check-In + Start + Abort, live/creator = Dashboard + Finalize + Abort, finalized = Standings + Bewertungs-Aggregat; non-creator pro Phase Status-Hint-Block ("Anmeldung beginnt bald", "Turnier wird vorbereitet") |
| R8-F-10 | P1 | Participant-Summary inkonsistent zur sichtbaren Liste — Header zählt alle `detail.participants` (inkl. withdrawn/rejected), Card filtert auf approved (+pending für Creator); User sieht "5 / 8" oben und 3 Namen unten | R8-A-08 | Summary an `visibleParts.length` angleichen, oder beide Werte separat ausgeben ("3 bestätigt · 5 angemeldet · max 8") mit `minParticipants` bei `registrationOpen` |
| R8-F-11 | P1 | Header-Info dünn — Status-Pill ohne Semantics-Label (R8-A-12), `minParticipants` fehlt, Format-Label nur im Stammdaten-Card statt im Header, Organizer-Name nirgends; Action-Stack im live-Status zeigt 4+ Filled-Buttons gleicher Wertigkeit ohne Primary/Secondary-Hierarchie | R8-A-04, R8-A-09, R8-A-12 | Header um Format-Label + minParticipants-Zeile + Organizer-Name erweitern, `TournamentStatusPill` mit `Semantics(label: 'Status: ${status.de}')` wrappen; `mk`-Helper differenziert in Primary/Outlined/TextButton, destruktive Actions in eigene "Gefahrenzone"-Sektion am Ende |
| R8-F-12 | P2 | Polling-Provider-Lifecycle fragil — `tournamentDetailPollingProvider` nur unter `fallbackActive` gewatcht, bei Realtime-Wechsel potentiell Doppel-Subscriber-Race; gleichzeitig kein Equality-Check vor Cache-Durchreichung, 5s-Tick triggert Vollrebuild auch bei No-Change; ExpansionTile im `_AuditTail` verliert Open-State pro Rebuild | R8-B-07, R8-B-10 | Polling unconditional watchen mit eigenem Active-Flag im Provider, oder Timer in `realtimeFallbackProvider` integrieren; `ref.refresh` statt `invalidate` mit `==`-Check; `_AuditTail` als `StatefulWidget` mit `PageStorageKey(id.value)` + `ExpansionTileController` |
| R8-F-13 | P2 | hasBracket-Switch nicht exhaustive + ArgumentError-Pfad schweigt — bei zukünftigen Bracket-Typen (Doppel-Elim, Schweizer M5) Compile-Bruch oder UnreachableError; `error: (_, _) => false` versteckt unerwartete Server-500er | R8-B-08 | Switch mit `_ => true` (oder explizitem Arm pro neue Variante) schliessen, `error`-Branch: `if (e is! ArgumentError) developer.log(...)`; mittelfristig Domain liefert `BracketState.empty/filled/notAvailable`-Tupel statt thrown ArgumentError an Provider-Boundary |
| R8-F-14 | P2 | Performance — `ref.read(tournamentActionsProvider)` pro `_participantRow` (64-Teilnehmer-Cap × 5s-Polling = 64 Reads/Tick), `_card`/`_row`/`_participantRow` allokieren bei jedem Rebuild neue Padding/TextStyle-Subtrees; ListView ohne RefreshIndicator | R8-A-10, R8-B-06 | `actions` einmal in `_Body.build` lesen und als Parameter durchreichen, `_participantRow` als `StatelessWidget`; `RefreshIndicator` um ListView mit `onRefresh: () => ref.refresh(tournamentDetailProvider(id))` |
| R8-F-15 | P2 | matchFormatConfig-Lookup ohne Type-Validation + Aborted-Branch Early-Return verschluckt Bracket/Standings/Audit — `cfg['sets_to_win']` mit `${cfg['x']}` interpoliert (Server-Typ-Drift rendert Müll); `aborted` returnt ohne Bracket/Standings/Audit-Surface anzubieten | R8-B-11, R8-C-07 | Pro Key `cfg['sets_to_win'] as int?` mit Fallback, mittelfristig typisierte Felder auf `Tournament.tournament`; `aborted` als Banner-oben statt Early-Return, darunter Read-only-Standings/Bracket-Buttons bei vorhandenen Daten |
| R8-F-16 | P3 | Sekundär-Polish — `tournamentDetailNotFound` ist Sackgasse ohne Zurück-Button (R8-A-11), Audit-Tail rendert nur Kind+ISO-Timestamp ohne Actor/Payload (FR-ADM-16 verlangt Actor, R8-C-08) | R8-A-11, R8-C-08 | Empty-Detail mit "Zurück zur Liste"-Button oder auto-pop; Audit-Row erweitern auf `${time} · ${actorLabel ?? 'system'} · ${kind}`, Tap öffnet Payload-Drawer, Actor aus participants-Liste auflösen mit Kurz-UUID-Fallback |

**No-Issue / Konsolidierungs-Notizen:**
- R8-A-01 + R8-B-02 sind beide derselbe Confirmation-Dialog-Mangel (UX-Lens + Code-Lens) — als R8-F-02 zusammengefasst.
- R8-A-02 + R8-B-01 sind beide derselbe Reentrancy-Defekt (User-Flow-Lens: Doppel-Tap-Risiko + Code-Lens: kein Busy-Flag) — als R8-F-01 zusammengefasst.
- R8-B-03 + R8-B-04 sind zwei Hälften derselben Cache-Invalidation-Lücke (Provider-Duplikat + fehlender Detail-Invalidate); zusammen mit R7-F-01 (Runde 7) bestätigt → in dieser Runde als R8-F-03 verschärft. CLAUDE.md-Memory führt den Smell schon, Symptomatik aber konkret: 5s-Stale-Window nach jeder Action.
- R8-A-05 + R8-A-06 + R8-C-01 + R8-C-06 sind vier Treffer auf die fehlende Co-Veranstalter-/Helper-Rolle (Permission-Aware-Sichtbarkeit, live-Matches-Button-Gate, Pending-Liste-Filter, isOrganizer-Wording-Lüge) — als R8-F-04 gebündelt, da die Wurzel identisch ist (binäres `isCreator`-Gate).
- R8-A-03 + R8-B-05 + R8-B-09 sind drei Treffer auf rohe Exception-Behandlung (Top-Level + `_safe` + Roster-/Pool-Card-Swallow) — als R8-F-07 zusammengefasst.
- R8-A-07 + R8-C-04 sind beide derselbe Live-Dashboard-Ungated-Defekt (User-Flow + Spec-Compliance) — als R8-F-08 zusammengefasst.
- R8-A-05 (non-creator-Hint) und R8-C-05 (Status-Matrix-Lücken) decken zwei Achsen derselben Status-Action-Matrix-Lücke ab — als R8-F-09 gebündelt.
- R8-A-04 + R8-A-09 + R8-A-12 sind drei Treffer auf den Header-/Action-Button-Hierarchie-Block (Format/min-max, Button-Hierarchie, Status-Pill-Semantics) — als R8-F-11 gebündelt.
- R8-B-07 + R8-B-10 sind beide Lifecycle-/Rebuild-Probleme um den Polling-Provider — als R8-F-12 zusammengefasst.
- R8-A-10 + R8-B-06 sind beide Performance-/Pull-to-Refresh-Punkte — als R8-F-14 gebündelt.
- R8-B-11 + R8-C-07 sind zwei unterschiedliche Polish-Punkte am Body-Pfad (matchFormatConfig-Typing + aborted-Early-Return); aus pragmatischen Gründen in R8-F-15 zusammengefasst, da beide am selben Code-Block (`_Actions`/`_Body`-Switch) hängen.
- R8-A-11 + R8-C-08 sind die zwei P3-Polish-Punkte (Sackgassen-Empty + dünner Audit-Tail) — als R8-F-16 gebündelt.
- Keine False-Positives auf App-Code-Ebene identifiziert.

**Zusammenfassung:** Sechs P0-Findings dominieren die Runde — die Action-Buttons sind nicht reentrancy-geschützt und ein Doppel-Tap feuert parallele RPCs (R8-F-01), keine destruktive Action hat einen Confirmation-Dialog (Abort/Finalize/Reject/Withdraw/CloseReg direkt one-tap, R8-F-02), das Provider-Duplikat aus Runde 7 hat zusätzlich einen fehlenden Detail-Invalidate, sodass nach jeder Action bis zu 5s ein Stale-Window klafft (R8-F-03), die Co-Veranstalter-/Helper-Rolle hat keine Sichtbarkeit weil alles an `isCallerCreator` hängt (R8-F-04), die Public-Link-/Share-Surface fehlt komplett trotz fertiger M4.2-Route (R8-F-05), und der anonyme Spectator-Pfad zeigt einen Register-Button der direkt in den MAENGEL #9-Auth-Crash führt (R8-F-06). Auf P1-Ebene leiden Exception-Handling (rohe `e.toString()`-Strings, Roster-/Pool-Cards schlucken Netzwerk-/Auth-Fehler als leer), Live-Dashboard-Gating (`draft`-Sichtbarkeit semantisch verkehrt), Status-Action-Matrix (registrationOpen ohne Anmeldungs-Management/Seeding/Check-In/Co-Org-Einladung, non-creator ohne Status-Hint), Participant-Summary (zählt mit-withdrawn/-rejected gegen die gefilterte Liste darunter) und Header-/Button-Hierarchie. P2 sammelt Polling-Lifecycle-Race + nicht-exhaustive Bracket-Switch + Performance- und Pull-to-Refresh-Lücken + matchFormatConfig-Typing + aborted-Early-Return. P3 sind Empty-Sackgasse und der dünne Audit-Tail. Mehrfach-Hit-Muster: zwei Hunter unabhängig auf Confirmation-Mangel (R8-F-02) und Reentrancy (R8-F-01), drei Hunter auf Provider-/Cache-Invalidate (R8-F-03 inkl. R7-F-01-Wiederholung), vier Hunter auf Helper-Rolle (R8-F-04). Hotfix-Wave-Schnitt: R8-F-01 + R8-F-02 + R8-F-03 zuerst als reine Client-Aufräumung ohne Server-Touch (Provider-Konsolidierung + Confirm-Dialoge + Busy-State), dann R8-F-06 + R8-F-08 als kleine UX-Gates (Spectator-Branch + Dashboard-Status-Gate), dann R8-F-04 mit Server-Migration (tournament_organizer_roles-Tabelle, callerRole-Feld in TournamentDetail) und R8-F-05 mit Server-RLS-Erweiterung als M4.2-Vorbereitung. R8-F-04 und R8-F-05 sollten zusammen als Plan-Dokument `docs/plans/m4-co-organizer-public-share/` aufgehängt werden, da beide Owner-Level-Entscheidungen tragen (Rollen-Schema-Design, share_plus + qr_flutter-Deps, Anon-RLS-Policy).

### Runde 9 — Tournament-Registration + Roster-Slot-Replacement

**Hunter-Output**: A=11, B=10, C=12 → konsolidiert auf 17 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R9-F-01 | P0 | Team-Registration komplett tot — Pool und Guests hartcodiert `const []` an `RosterCompositionWidget`, der Server-View `team_pool_with_tournament_conflicts` wird nirgends aufgerufen; Submit-Button bleibt zwingend disabled (Roster-Länge < teamSize), Phantom-Feature | R9-A-02, R9-B-05, R9-C-01 | `teamPoolWithConflictsProvider(tournamentId, teamId)` anlegen, der `team_pool_with_tournament_conflicts` aufruft; Result auf `RosterPoolMember`/`RosterPoolGuest` mappen und an `RosterCompositionWidget` durchreichen; auf Team-Switch invalidieren; zusätzlich client-seitig `MIN_ONE_REGISTERED` prüfen, damit kein 500ms-Round-Trip nur für die Validierung kommt |
| R9-F-02 | P0 | Route `/tournament/:id/register/team` ist nicht im Router gebunden — `pushReplacement`-Aufruf landet im Fallback/404, der gesamte M3.2-T14-Flow ist unerreichbar; `RegisterTeamScreen` wird in `router.dart` nicht importiert | R9-A-01 | GoRoute `path: '/tournament/:id/register/team'` in `lib/app/router.dart` ergänzen → `RegisterTeamScreen(tournamentId: TournamentId(state.pathParameters['id']!))`; `TournamentRoutes.registerTeam(tournamentId)` als Helper statt String-Konkat in `_TeamBranch` |
| R9-F-03 | P0 | Team-Create-Submit schluckt Fehler — `_runReturning` ruft die Aktion über `AsyncValue.guard`, liefert bei Fehler `null`; `TeamCreateScreen._submit` hat `on Object catch`, der nie greift; bei `id == null` zeigt der Screen keinen SnackBar, kein Logging, kein Hinweis — exakter MAENGEL #3-Reproduktor | R9-C-02 | `_runReturning` Fehler rethrowen (Manuell statt `AsyncValue.guard`) oder `ref.listen(teamMembershipControllerProvider, ...)` im Screen mit Fehler-SnackBar-Hook; alternativ nach `await` `state.hasError` prüfen und `state.error` rendern |
| R9-F-04 | P0 | RosterEditorScreen ist Orphan-Code — keine Route, kein `context.push`, kein Detail-Einstieg; Mid-Tournament-Substitution (FR-REG-Roster-Replace, OD-M3-07 ROSTER_LOCKED_DURING_MATCH) technisch ungenutzt, Captains können niemanden ersetzen | R9-A-03 | Route `/tournament/:id/team/:participantId/roster` (oder Subroute von Detail) registrieren; im `tournament_detail_screen` bei `me != null && tournament.teamSize > 1` einen "Roster verwalten"-Button anbieten (Captain-Permission per Server-RLS) |
| R9-F-05 | P0 | Roster-Audit-Trail per Konstruktion immer leer — `getRoster` filtert client-seitig `replaced_at != null` Rows raus, `RosterEditor` erwartet aber genau diese als `history`; ExpansionTile zeigt immer "Audit-Trail (0)" / "Keine Replacements bisher.", Compliance-/Nachvollziehbarkeits-Anforderung der Tournament-Spec nicht erfüllt | R9-A-04 | Port-Vertrag `getRoster` so umbauen, dass `replaced_at != null` Rows nicht verworfen werden — entweder als zwei Listen (active/history) zurückgeben oder einen Boolean-Flag mitliefern; Audit-View greift auf das volle Set zu |
| R9-F-06 | P0 | `_TeamBranch` `pushReplacement` ohne State-Flag — `_TeamBranch` ist `ConsumerWidget`, bei jedem Rebuild (z.B. `teamListProvider`-Refetch) wird `addPostFrameCallback` erneut registriert und schiebt einen weiteren `pushReplacement`-Call auf den Router; doppelte Navigationen, Back-Stack zertrümmert, Worst-Case-Loop weil `pushReplacement` selbst neuen Rebuild triggert | R9-B-01 | `_TeamBranch` zu `ConsumerStatefulWidget` umbauen mit `bool _navigated = false`-Guard, oder Routing aus `_TeamBranch` rauslösen und im Parent-State.build vor dem Mount entscheiden; alternativ Team-Picker direkt im _TeamBranch rendern statt automatisch weiterzunavigieren (siehe R9-F-15) |
| R9-F-07 | P0 | FR-CFG-3/4 Anmeldefenster + Sichtbarkeit komplett fehlen — DB-Spalten `registration_opens_at` / `registration_closes_at` existieren, `tournament_publish` setzt sie auto auf `now()`; `TournamentConfigDraft` hat keine Felder, kein `visibility`, kein Wizard-Step; Organisatoren können das Fenster nicht steuern, FR-REG-3-Server-Prüfung fällt auf hartcodierten Default zurück | R9-C-03 | a) Migration: Spalte `visibility text NOT NULL DEFAULT 'public'` mit CHECK in `public/invite_only`; b) `TournamentConfigDraft` um `registrationOpensAt`, `registrationClosesAt`, `visibility` erweitern + `validate()` (`opens < closes`, beide nicht in Vergangenheit); c) Neuer Wizard-Step `_RegistrationWindowStep` mit zwei DatePicker-Feldern und Sichtbarkeits-Toggle; d) `tournament_create`-RPC um drei Parameter erweitern |
| R9-F-08 | P0 | FR-REG-7 verletzt — `tournament_withdraw` prüft nur `user_id = caller`, für Team-Anmeldungen ist `user_id` aber der Original-Anmelder, nicht jedes aktive Team-Mitglied; RPC blockt mit `42501 only the participant can withdraw`, Spec verlangt aber Withdraw durch jedes Team-Mitglied | R9-C-08 | In `tournament_withdraw` den Caller-Check erweitern: erlaube Withdraw, wenn Caller in `team_memberships` des `tournament_participants.team_id` aktiv ist (analog zum Roster-Replace-Pattern in ADR-0020 §3.1); zusätzlich UI-Detail-Screen-`me`-Lookup um Team-Roster-Match erweitern (sonst sieht das Team-Mitglied keinen Withdraw-Button — siehe R9-F-11) |
| R9-F-09 | P0 | Liga-Feld bei Team-Create ohne Helper-Text und ohne Klassen-Beschrieb — Dropdown zeigt nur A/B/C ohne jegliche Erklärung, `LeagueMembership.values` wird nicht für Dropdown-Items genutzt sondern hartcodiert, Liga-Wahl hat aktuell keinen Effekt auf Tournament-Registration (nur auf M5-Punktevergabe); Mängel #2.2/#2.3 fordern Hilfetext "Profis / Semi-Profis / Spaß-Spieler" | R9-A-09, R9-C-04 | `LeagueMembership`-Enum um `displayLabel` und `description` erweitern (Domain-Layer); DropdownItems aus `LeagueMembership.values` generieren; `helperText` im InputDecoration oder `Text`-Block unter dem Dropdown mit der Beschreibung der gewählten Liga; Owner-Entscheidung fällig ob Feld Pflicht bleibt — ADR-0018 explizit prüfen, mittelfristig in "Erweiterte Einstellungen"-ExpansionTile schieben |
| R9-F-10 | P0 | Team-Create-Form Keyboard-Overflow — `Column` mit `Spacer()` und festem `Padding`, beim Erscheinen der Software-Tastatur kollabiert der `Spacer` auf negative Höhe → RenderFlex-Overflow; Mängel #2.4 explizit dokumentiert, Form unbedienbar auf kleineren Bildschirmen sobald Tastatur sichtbar | R9-C-05 | `Padding` → `SingleChildScrollView` mit `padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + KubbTokens.space4)`; `Spacer()` durch fixes `SizedBox(height: KubbTokens.space5)` ersetzen |
| R9-F-11 | P1 | `me`-Lookup im Detail-Screen erkennt Team-Mitgliedschaft via `userId`-Match nicht — bei Team-Turnieren ist Participant das Team selbst (`userId` ist NULL/teamRef), Spieler dessen Team bereits registriert ist landet in `me == null` und bekommt erneut Anmelden-Button gezeigt; Folge: doppelte Registrierungs-Versuche, BR_5_VIOLATION-RPC-Fehler, Withdraw-Button für eigene Team-Registrierung erscheint nie | R9-A-06 | `me`-Lookup um Team-Roster-Match erweitern (prüfe ob `myUserId` in einer der Roster-Listen der Tournament-Participants liegt), oder Domain-Wert `myParticipationKind` (solo/team/none) auf dem `TournamentDetailHeader` server-seitig liefern |
| R9-F-12 | P1 | RosterLockedException-Pfad fragil + Auth-Errors geschluckt — `roster_editor_screen._onReplace` prüft `e.toString().contains('ROSTER_LOCKED_DURING_MATCH')` obwohl Repo bereits typisiertes `RosterLockedException(cause: 'match-open' \| 'tournament-finalized')` wirft; `tournament-finalized`-Pfad rutscht in generischen SnackBar mit roher Exception; zusätzlich ist 42501/insufficient_privilege im `TournamentRepository` nicht gemappt (im Gegensatz zu `TeamRepository._guard`), User sieht rohe PostgrestException als Toast | R9-B-03, R9-B-06 | a) Auf `on RosterLockedException catch (e)` switchen und über `e.cause` zwischen `match-open`-Dialog und `tournament-finalized`-Hint unterscheiden; b) analog zu `TeamRepository._guard` ein `_guard<T>` in `TournamentRepository` einführen, das alle RPC-Aufrufe durchschleust und 42501 → `TournamentPermissionException` mappt; UI catcht und zeigt "Bitte erneut anmelden" |
| R9-F-13 | P1 | Solo- und Team-Submit ohne Idempotenz/Re-Auth-Hint — Solo-`_submit` schützt mit `_busy` aber `setState` ist async gegenüber Frames; schneller Doppel-Tap kann ALREADY_REGISTERED-Server-Hint produzieren und zeigt rohe `$e`-SnackBar; zusätzlich kein Anmeldefenster-Check im Client, Confirm-Button immer aktiv bis RPC scheitert mit "registration is not open" | R9-B-02, R9-C-06 | Vor `setState(_busy=true)` lokale `bool` direkt prüfen+setzen (Guard in `_submit`-Anfang, nicht im Button); Server-Hints (`ALREADY_REGISTERED`, `registration is not open`) auf l10n-Keys mappen und in UI surfacen; Bedingung im Build prüfen: Status-Chip + Disabled-State wenn `detail.tournament.status != registration_open` oder Fenster nicht offen |
| R9-F-14 | P1 | Team-Registration bypassed `TournamentActions` → keine Cache-Invalidation — Team-Flow ruft `tournamentRemoteProvider.registerTeam(...)` direkt; `TournamentActions` hat kein `registerTeam`, keinerlei `ref.invalidate`; nach Submit sehen Detail- und List-Screen alte Daten, `me`-Wert läuft veraltet (verstärkt R9-F-11) | R9-A-05 | `registerTeam` in `TournamentActions` aufnehmen, dort `tournamentListProvider` + `tournamentDetailProvider(id)` invalidieren; Screens auf den Action-Provider umstellen |
| R9-F-15 | P1 | `_TeamBranch` UX-Übergang abrupt + `_highlightSlot` funktional tot — sobald `teams` non-empty ist, springt der Screen ungefragt auf `register/team` ohne Picker auf Detail-Screen, kein Cancel-Punkt; im Zielscreen wird `_highlightSlot` bei `BR_5_VIOLATION` auf 1 gesetzt aber nirgends an `RosterCompositionWidget` durchgereicht — visuelle Fehler-Rückführung existiert nicht | R9-A-07, R9-A-08, R9-C-10 | a) Entweder Team-Picker direkt in `_TeamBranch` (Solo-analoge Bestätigungsseite mit Team-Dropdown + "Weiter zur Aufstellung"-Button), oder klare Lade-Message statt nackter `CircularProgressIndicator`-Übergang; b) `RosterCompositionWidget` um `highlightSlot: int?` erweitern und Border/Background des betroffenen `_slotTile` in `KubbTokens.miss` zeichnen, oder den `_highlightSlot`-State entfernen falls Feature deferred |
| R9-F-16 | P2 | Performance/Vertrags-Polish — `rosterProvider` per `ref.invalidate` nach Replace führt zu Vollrebuild und verliert ExpansionTile-Open-State (statt optimistic Update); `getRoster` ist Two-Step ohne Transaktion mit Race-Window zwischen Participant-Read und Roster-Listing; `_ReplaceDialog` filtert Picker-Items nicht gegen Aktiv-Slots (User wählt Spieler der bereits im Roster sitzt → BR-5-Round-Trip); `_selectedTeam` als Referenz-Identität verliert Selection nach `teamListProvider`-Refetch | R9-B-04, R9-B-07, R9-B-08, R9-B-09 | a) `rosterProvider` als `Notifier`/`AsyncNotifier` mit optimistic Update statt `invalidate`; b) Server-Migration `tournament_roster_list_by_participant(p_participant_id)` einplanen, die Lookup + Listing in einer Transaktion macht; c) Aktive Slots vor `showDialog` aus `widget.slot`-Liste lesen, Picker-Items für besetzte IDs ausgrauen; d) `_selectedTeam` per `TeamId` indizieren, bei `data:`-Re-Build via `teams.firstWhereOrNull((t) => t.id == _selectedTeamId)` re-resolven |
| R9-F-17 | P2 | Sekundär-Polish — rohe `'$e'`-SnackBar als Fallback in beiden Screens (`PostgrestException`-Strings für User), inline-deutsche Strings in `register_team_screen` + `roster_editor_screen` umgehen `AppLocalizations`, RosterEditor zeigt User-UUIDs statt Anzeigenamen, RosterEditor hat keinen Captain/Organizer-Permission-Gate vor Replace-Button, FR-REG-11 Liga-Whitelist + FR-REG-8/9 Check-In/QR fehlen komplett | R9-A-10, R9-A-11, R9-B-10, R9-C-07, R9-C-09, R9-C-11, R9-C-12 | Bündel-Polish-Wave: a) Generic-Fallback via `tournamentRegistrationGenericError` ARB-Key, rohe Exception nur in `kDebugMode` loggen; b) ARB-Keys für beide Screens ergänzen, `flutter gen-l10n`, T18 abschliessen; c) `tournament_roster_list_with_names`-RPC mit `display_name`; d) Captain/Organizer-Permission-Check vor Replace-Button-Enable; e) FR-REG-11 als M5-Backlog mit `eligible_leagues text[]` + Server-Check; f) FR-REG-8/9 Check-In/QR als M3.3/M4-Backlog-Punkt notieren |

**No-Issue / Konsolidierungs-Notizen:**
- R9-A-02 + R9-B-05 + R9-C-01 sind dreimal derselbe Pool-Leer-Defekt aus drei Lens-Winkeln (User-Flow: leerer Picker; Code-Smell: hartcodiert `const []`; Spec: `team_pool_with_tournament_conflicts` nie aufgerufen) — als R9-F-01 gebündelt, höchster P0.
- R9-A-01 ist der einzige Hunter-Hit auf das fehlende Routing — als R9-F-02 isoliert, aber identisch-kritisch (Sackgasse).
- R9-C-02 ist der exakte MAENGEL #3-Reproduktor (`AsyncValue.guard` schluckt Exception) — als R9-F-03 mit höchster Priorität, weil Owner explizit darauf wartet.
- R9-A-03 + R9-A-04 sind beide Orphan-Pfade des Roster-Editors (Routing fehlt + Audit-Trail per Konstruktion leer) — als R9-F-04 und R9-F-05 getrennt gehalten, weil Fix-Strategien unterschiedlich sind (Router-Eintrag vs. Repository-Vertrag).
- R9-B-01 (Doppel-pushReplacement) ist ein eigenständiger Bug, nicht mit `_TeamBranch`-UX-Mangel (R9-A-08) zu verwechseln — als R9-F-06 separat, R9-F-15 deckt UX-Übergang ab.
- R9-A-06 (me-Lookup) hängt strukturell mit R9-C-08 (Withdraw-Backend-Check) zusammen, beide brauchen denselben Team-Roster-Match — als R9-F-08 und R9-F-11 getrennt, da Backend- und Client-Fix unterschiedlich sind.
- R9-A-09 + R9-C-04 sind beide derselbe Liga-Helper-Text-Mangel — als R9-F-09 gebündelt.
- R9-B-03 + R9-B-06 sind beide Exception-Mapping-Lücken im Tournament-Repo (RosterLocked-cause + 42501-Auth) — als R9-F-12 zusammengefasst, da gemeinsamer `_guard<T>`-Fix.
- R9-B-02 + R9-C-06 sind beide Submit-/Anmeldefenster-Gating-Punkte — als R9-F-13 gebündelt.
- R9-A-07 + R9-A-08 + R9-C-10 sind drei Treffer auf `_TeamBranch`-/_highlightSlot-UX (abrupter Übergang + tote Highlight-Logik) — als R9-F-15 zusammengefasst.
- R9-B-04 + R9-B-07 + R9-B-08 + R9-B-09 sind vier Performance-/Vertragsdetail-Punkte (optimistic Update, Two-Step-Race, Picker-Filter, Team-Identity) — als R9-F-16 gebündelt.
- R9-A-10 + R9-A-11 + R9-B-10 + R9-C-07 + R9-C-09 + R9-C-11 + R9-C-12 sind sieben Sekundär-Polish-Punkte (rohe-Strings, i18n, Permission-Gate, UUID-Anzeige, FR-REG-11/8/9-Backlog) — als R9-F-17 gebündelt.
- Keine False-Positives auf App-Code-Ebene identifiziert.

**Zusammenfassung:** Zehn P0-Findings dominieren die Runde — die Team-Registration ist als komplette Sackgasse implementiert: Pool/Guests sind hartcodiert leer (R9-F-01, dreifach gemeldet), die Ziel-Route existiert nicht im Router (R9-F-02), `_TeamBranch` schiebt bei jedem Rebuild einen neuen `pushReplacement` (R9-F-06); selbst wenn der User durchschlüpft, ist der Roster-Editor Orphan-Code (R9-F-04) und der Audit-Trail per Konstruktion leer (R9-F-05); auf der Team-Erstellungs-Seite schluckt der Membership-Controller alle Fehler via `AsyncValue.guard` (R9-F-03, exakter MAENGEL #3-Reproduktor), die Software-Tastatur produziert RenderFlex-Overflow (R9-F-10), und das Liga-Feld zeigt nur A/B/C ohne jegliche Erklärung (R9-F-09); Spec-seitig fehlen FR-CFG-3/4 (Anmeldefenster + Sichtbarkeit) komplett im Draft + Wizard + RPC (R9-F-07), und FR-REG-7 ist serverseitig falsch implementiert — `tournament_withdraw` erlaubt nur dem Original-Anmelder das Zurückziehen statt jedem aktiven Team-Mitglied (R9-F-08). Auf P1-Ebene leiden der Detail-Screen-`me`-Lookup für Team-Mitglieder (R9-F-11), die Exception-Mapping-Schicht im Tournament-Repo (RosterLocked-cause + 42501-Auth, R9-F-12), Submit-Idempotenz + Anmeldefenster-Client-Check (R9-F-13), Cache-Invalidation nach Team-Registration (R9-F-14) und der `_TeamBranch`-UX-Übergang + tote Highlight-Logik (R9-F-15). P2 sammelt vier Performance-/Vertragsdetail-Punkte (R9-F-16) und sieben Sekundär-Polish-Themen inkl. FR-REG-11/8/9-Backlog (R9-F-17). Mehrfach-Hit-Muster: drei Hunter unabhängig auf den leeren Pool (R9-F-01), zwei Hunter auf Liga-Helper-Text-Mangel (R9-F-09), zwei Hunter auf Exception-Mapping-Lücke (R9-F-12), drei Hunter auf den UX-Übergang im `_TeamBranch` (R9-F-15). Hotfix-Wave-Schnitt: R9-F-03 zuerst (15min, Notifier-Fix, exakter MAENGEL #3-Reproduktor), dann R9-F-01 + R9-F-02 + R9-F-06 als Block (Pool-Provider + Routing + Doppel-pushReplacement-Guard, 2-3h ohne Server-Touch), dann R9-F-08 + R9-F-11 + R9-F-14 als zusammenhängender Team-Participation-Fix (Backend-RPC-Erweiterung + me-Lookup + Cache-Invalidation), dann R9-F-07 als eigenes Plan-Dokument unter `docs/plans/m3-registration-window-visibility/` (Migration + Draft + Wizard-Step + RPC-Parameter), R9-F-10 + R9-F-09 als Mängel-#2-Polish-Wave parallel; R9-F-04 + R9-F-05 zusammen als Roster-Editor-Aktivierungs-Task (Route + getRoster-Vertrag-Umbau). M3-Sign-off ist ohne R9-F-01/02/03/04/05/06/07/08 blockiert.


### Runde 10 — Match-Liste + Match-Detail

**Hunter-Output**: A=12, B=12, C=12 → konsolidiert auf 17 Findings.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R10-F-01 | P0 | Submit-Race: stale Match-Snapshot ohne Re-Read vor RPC — Match-Detail liest `match` einmal aus `tournamentMatchProvider`-Cache, baut `proposal` aus `_drafts`, ruft `submitScore(match, proposal)`; bei Polling-Update oder Konkurrent-Submit dazwischen geht der Apply gegen veralteten `consensusRound`/`status`, Server akzeptiert duplicate oder verwirft korrekten Stand | R10-A-02, R10-B-01, R10-B-02 | Vor `submitScore` frischen Read via `ref.read(tournamentMatchProvider(matchId).future)` ziehen, gegen den proposen; `submitScore` als `AsyncNotifier`-Action mit `_busy`-Guard und `try/finally` strukturieren; SnackBar-Map auf typisierte `ScoreSubmitException`-Subtypen (StaleVersion, ConsensusBumped) |
| R10-F-02 | P0 | `setState` während Build in `_ensureDraftForRound` — beim Round-Wechsel ruft der Detail-Screen während `build()` setState/Provider-Update, was im `Builder`-Frame eine Re-Build-Schleife auslöst (Flutter wirft `setState() or markNeedsBuild() called during build`) | R10-A-04, R10-B-05 | `_ensureDraftForRound` aus `build` rausziehen, in `didUpdateWidget` / `didChangeDependencies` oder `WidgetsBinding.instance.addPostFrameCallback` verlagern; alternativ `_drafts` als `StateNotifier`/Riverpod-Notifier ausserhalb des Widget-Trees halten und nur im `onChanged`-Callback updaten |
| R10-F-03 | P0 | Score-Draft-Persistence (Drift) nicht verkabelt — `tournament_score_draft_provider.dart` existiert mit Drift-DAO-Anbindung (DSCORE-19..-22), aber Match-Detail-Screen liest/schreibt nur das lokale `_drafts`-Map; nach App-Kill / Screen-Wechsel sind alle nicht-submittierten Eingaben weg | R10-C-01 | Provider in Match-Detail einhängen: `ref.watch(tournamentScoreDraftProvider(matchId))` als Initial-State, `onChanged` callt `ref.read(...).save(roundIdx, draft)`, `onClear`/`onSubmit` callt `.delete(matchId)`; `_drafts`-Map durch den Provider-State ersetzen |
| R10-F-04 | P0 | Null-Match = endloser Spinner statt Not-Found-Screen — wenn `tournamentMatchProvider(matchId)` `null` zurückgibt (Match gelöscht, Tournament zurückgesetzt, falsche Route), zeigt der Screen permanent `CircularProgressIndicator`; kein Back-Button-Hint, kein "Match nicht gefunden", User sitzt fest | R10-A-03, R10-B-08 | `async.when`-Datapath erweitern: `data: (m) => m == null ? _NotFoundBody(onBack: () => context.go(TournamentRoutes.matchList(tournamentId))) : _Body(...)`; ARB-Keys `tournamentMatchDetailNotFoundTitle/Body/Back` |
| R10-F-05 | P0 | Submit-Confirm-Dialog fehlt — Match-Detail submittet Score one-tap ohne Bestätigung, obwohl `submitScore` bei consensus_round-Bump das ganze Match in Conflict pusht und alle Reset-Eingaben anderer Spieler verwirft (DSCORE-Spec verlangt explizite Bestätigung) | R10-C-02 | `showDialog<bool>` vor `submitScore` mit Score-Preview (Set 1: 6:5, Set 2: 6:4, …) + Cancel/Confirm; bei BO3 zusätzlich Hinweis "Match endet hier"-Indikator; ARB-Keys `tournamentMatchSubmitConfirm*` |
| R10-F-06 | P0 | Header zeigt 6-Zeichen-UUIDs statt Team-/Gegner-Namen — `nameFor: (id) => id.value.substring(0, 6)` ist Truncation-Fallback aus M1; Match-Card und Match-Detail-Header sind unleserlich, Spieler weiss nicht, wessen Match das ist | R10-A-06, R10-C-05 | RPC `tournament_match_with_participants` (analog zu `tournament_roster_list_with_names` aus R9-F-17) liefert `home_display_name`/`away_display_name`, `TournamentMatchRef` um Felder erweitern; `nameFor` aus Match-Card raus, Card konsumiert direkt `match.homeDisplayName ?? match.homeId.value.substring(0,6)` |
| R10-F-07 | P0 | BO3-dritter-Satz nicht blockiert bei 2:0 — Set-Eingabe-UI rendert Set 3 auch wenn Set 1 + Set 2 schon vom selben Team gewonnen sind; User kann Score für irrelevanten Satz tippen, der dann beim Submit als Proposal mitgeht und im Conflict-Screen Lärm produziert | R10-C-03 | Vor dem `_SetCard`-Rendering `match.bestOf` + bisherige Set-Sieger aus `_drafts` auswerten; bei `setsWonByHome == bestOf/2 + 1` oder analog away → restliche Sets per `IgnorePointer` + `Opacity(0.4)` + Hint "Match entschieden" disablen; im Submit-Payload nur abgeschlossene Sets mitschicken |
| R10-F-08 | P0 | Helper-Permissions (Captain/Gast) ungeprüft — DSCORE-Spec verlangt: nur Captain oder vom Captain freigegebener Gast darf für sein Team submitten; UI gibt jedem authentifizierten User ohne weitere Prüfung den Submit-Button; Server prüft RLS, aber Client zeigt rohen 42501-Fehler statt sauber zu disablen | R10-C-10 | `tournamentMatchProvider` um `myRoleForMatch`-Feld erweitern (`captain` / `helper` / `spectator` / `organizer`); Submit-Button nur enabled bei `captain` oder `helper`; bei `spectator` Hint "Du bist kein Teilnehmer dieses Matches"; bei `organizer` Override-CTA zeigen statt Submit |
| R10-F-09 | P1 | Self-Filter "Meine Matches" fehlt — Match-Liste zeigt alle Matches des Turniers ohne Filter-Chip "Nur meine"; bei 16-Team-RR mit 120 Matches scrollt der Spieler durch unrelevanten Content | R10-A-01 | `FilterChip("Meine Matches", selected: _onlyMine, onChanged: ...)` im AppBar-Bottom; Filter prüft `match.homeId in myParticipations || match.awayId in myParticipations` (gleicher `myParticipation`-Lookup wie R9-F-11); Default `_onlyMine = false`, User-Choice via `SharedPreferences` persistieren |
| R10-F-10 | P1 | Status-Banner fehlt am Match-Detail-Header — Spieler sieht nicht ob Match `scheduled` / `in_progress` / `awaiting_consensus` / `disputed` / `finalized`; aktueller Screen rendert nur Set-Eingabe, status-bedingte CTAs/Hints (Override-Banner, Conflict-Hint, Finalized-Lock) fehlen | R10-A-10, R10-C-09 | `MatchStatusBanner`-Widget analog zu `RealtimeStateBanner`: status-spezifische Farbe (`KubbTokens.hit`/`miss`/`warn`) + Text aus ARB + optionalem CTA-Button ("Zum Conflict-Screen" bei `disputed`, "Override anfragen" bei `finalized`); rendert oberhalb der Set-Cards |
| R10-F-11 | P1 | Override-Zugang aus Match-Detail nicht erreichbar — Veranstalter muss Override für ein konkretes Match starten können, aber Match-Detail hat keinen Entry-Point; aktuell nur via Liste → Override-Screen ohne Match-Vorauswahl, manueller Match-Picker | R10-C-04 | Im Match-Detail-AppBar `IconButton(icon: Icons.gavel, onPressed: () => context.go(TournamentRoutes.override(tournamentId, matchId)))`, nur sichtbar bei `myRoleForMatch == organizer` (zusammen mit R10-F-08); ARB-Key `tournamentMatchOverrideTooltip` |
| R10-F-12 | P1 | Polling-Timer ohne Stop-Kriterium — `tournamentMatchListPollingProvider` läuft alle 5s, auch wenn Tournament `finalized` ist und keine Änderungen mehr kommen; saugt Battery + DB-Quota auf abgeschlossenen Turnieren | R10-A-08, R10-B-06 | Provider-Body prüft vor jedem `invalidate`-Tick: `final t = ref.read(tournamentDetailProvider(id)).valueOrNull; if (t?.status == finalized || t?.status == aborted) return;`; bei `finalized` `Timer.cancel()` und Provider-State auf `done` flippen; oder `ref.onDispose` korrekt setzen falls Screen ungemountet |
| R10-F-13 | P1 | `disputed` routet auf Match-Liste statt direkt zum Conflict-Screen — wenn der Match-Detail nach Submit den Status-Bump auf `disputed` sieht, callt er aktuell `context.go(matchList)` statt `context.go(conflict(...))` (Bug aus CLAUDE.md Section "MUSS-Fixes" #2 noch nicht gefixt) | R10-C-07 | Im `ref.listen`-Callback auf `tournamentMatchProvider` Status-Wechsel `awaiting_consensus → disputed` abfangen: `context.go(TournamentRoutes.conflict(tournamentId, matchId))`; SnackBar nur als sekundärer Hinweis behalten; deckt MUSS-Fix #2 aus Projekt-Memory ab |
| R10-F-14 | P1 | Hardcoded `maxBasekubbs=5` und `maxSets=3` — Set-Eingabe-Widget hardcoded Domain-Limits, die laut `tournament-mode-spec.md` (FR-SCORE-12) pro Tournament aus Config kommen sollen (BO5, abweichende Basekubb-Counts bei Trainings-Turnieren) | R10-A-12, R10-C-08 | Limits aus `match.tournamentConfig.bestOf` und `.maxBasekubbsPerSet` lesen; `TournamentMatchRef` um diese Felder erweitern (kommt von RPC mit JOIN auf `tournament_config`); `_SetCard` props um `maxBasekubbs: int`, Range-Slider 0–N |
| R10-F-15 | P1 | `current_proposal_for_team` hint im Server-Response nicht konsumiert — Server liefert pro Match-Read das aktuell vom eigenen Team submittierte Proposal (DSCORE-44), Client ignoriert es; Folge: nach App-Restart sieht eigener Captain seinen alten Submit nicht, tippt neu, produziert künstlichen Konflikt | R10-C-06 | `TournamentMatchRef`-Parser um `currentProposalForTeam: TournamentSetScoreProposal?` erweitern; im Detail-Screen Initial-State der `_drafts`-Map aus diesem Feld füllen (vor R10-F-03-Drift-Lookup als Fallback); Banner "Du hast bereits 6:5/6:4 submittiert, Set 3 läuft" falls nicht-leer |
| R10-F-16 | P2 | Set-ohne-King-Heuristik triggert falsch — Heuristik im Set-Validation-Code ("wenn Set-Score 0:6 oder ähnlich, war kein Königswurf nötig") basiert nur auf Differenz ≥ 6, ignoriert dass Set durch 10-Kubb-Limit ohne König auch enden kann; Folge: legitime Sets werden als "King missing"-Warnung markiert | R10-B-07 | Heuristik komplett raus, Status `kingHit/kingMissed` als explizites Feld im Set-Proposal aufnehmen (eigener Toggle in Set-Card); Server-Spec FR-SCORE-15 entsprechend anpassen, RPC-Parameter erweitern |
| R10-F-17 | P2 | Sekundär-Polish — Match-Card-`onTap` ohne Reentrancy-Schutz (Doppel-Tap pushed zweimal), `_drafts`-Map als `Map<int,...>` statt typisiertem Notifier macht Diff schwer, fehlende `key: ValueKey(matchId)` auf Match-Cards verursacht Animation-Flicker bei Sort-Change, Match-Liste hat keinen Pull-to-Refresh-Indikator (User-Erwartung), Match-Liste gruppiert nur nach `roundNumber` aber nicht nach Status (alle finalized zuoberst stört) | R10-A-05, R10-A-07, R10-A-09, R10-A-11, R10-B-03, R10-B-04, R10-B-09, R10-B-10, R10-B-11, R10-B-12, R10-C-11, R10-C-12 | Bündel-Polish-Wave: a) `Bool _navBusy` im Match-Card-State + `if (_navBusy) return;`; b) `_drafts` zu `MatchDraftNotifier` mit copyWith; c) `key: ValueKey(m.matchId.value)`; d) `RefreshIndicator(onRefresh: () async => ref.invalidate(tournamentMatchListProvider(id)))`; e) Sortier-Funktion (`scheduled` zuerst, dann `in_progress`, finalized zuletzt innerhalb der Runde) |

**No-Issue / Konsolidierungs-Notizen:**
- R10-A-02 + R10-B-01 + R10-B-02 sind dreimal dieselbe Submit-Race-Condition aus drei Lens-Winkeln (User-Flow: Doppel-Tap-Stale-Snapshot; Code-Smell: kein Re-Read; Code-Smell: kein Busy-Guard) — als R10-F-01 gebündelt, P0 wegen Datenverlust-Potenzial.
- R10-A-04 + R10-B-05 sind zwei Treffer auf das `setState`-during-build-Pattern in `_ensureDraftForRound` — als R10-F-02 gebündelt, P0 wegen Flutter-Crash-Pattern.
- R10-C-01 ist der einzige Hunter-Hit auf das nicht-verkabelte Score-Draft-Provider — als R10-F-03 isoliert, aber P0 weil der Drift-Provider extra dafür existiert (DSCORE-19..-22, M1-Polish) und der Wire-Up vergessen wurde.
- R10-A-03 + R10-B-08 sind beide Treffer auf den null-Match-endless-Spinner — als R10-F-04 gebündelt.
- R10-A-06 + R10-C-05 sind zwei Treffer auf das `nameFor: substring(0,6)`-Fallback — als R10-F-06 gebündelt, gleicher RPC-Erweiterungs-Fix wie R9-F-17 (Roster-Names).
- R10-A-10 + R10-C-09 sind zwei Treffer auf das fehlende Status-Banner — als R10-F-10 gebündelt.
- R10-A-08 + R10-B-06 sind zwei Treffer auf den Polling-Timer ohne Stop-Kriterium — als R10-F-12 gebündelt.
- R10-A-12 + R10-C-08 sind zwei Treffer auf die hardcoded Domain-Limits — als R10-F-14 gebündelt.
- R10-C-07 deckt den MUSS-Fix #2 aus der Projekt-Memory ab (`disputed` routet nicht zum Conflict-Screen) — als R10-F-13 isoliert, P1.
- R10-A-05/07/09/11 + R10-B-03/04/09/10/11/12 + R10-C-11/12 sind zwölf Sekundär-Polish-Punkte — als R10-F-17 gebündelt.
- Keine False-Positives auf App-Code-Ebene identifiziert.

**Zusammenfassung:** Acht P0-Findings dominieren die Runde — der Match-Detail-Screen hat strukturelle Submit-Pfad-Defekte: die Submit-Race liest gegen einen veralteten Match-Snapshot (R10-F-01, dreifach gemeldet), `_ensureDraftForRound` ruft `setState` während Build (R10-F-02, doppelt), der vorhandene Drift-Score-Draft-Provider wird nirgends konsumiert (R10-F-03, einfacher Wire-Up vergessen), ein null-Match dreht den Spinner ewig statt Not-Found zu zeigen (R10-F-04, doppelt), Score-Submit ohne Confirm-Dialog verwirft Konkurrent-Eingaben (R10-F-05), Match-Header zeigt 6-Zeichen-UUIDs statt Spieler-Namen (R10-F-06, doppelt), bei BO3-2:0 ist der irrelevante dritte Satz noch tipp-bar (R10-F-07), und Captain/Helper-Permissions werden client-seitig gar nicht geprüft (R10-F-08). Auf P1-Ebene fehlen Self-Filter (R10-F-09), Status-Banner (R10-F-10, doppelt), Override-CTA aus dem Detail-Screen (R10-F-11), der Polling-Timer hat kein Stop-Kriterium für finalisierte Turniere (R10-F-12, doppelt), `disputed` routet noch auf die Match-Liste statt zum Conflict-Screen (R10-F-13, deckt MUSS-Fix #2 aus der Projekt-Memory ab), Domain-Limits sind hardcoded statt aus Config gelesen (R10-F-14, doppelt), und der `current_proposal_for_team`-Hint vom Server wird ignoriert (R10-F-15). P2 sammelt die Set-ohne-King-Heuristik (R10-F-16) und zwölf Sekundär-Polish-Punkte (R10-F-17). Mehrfach-Hit-Muster: dreifach gemeldete Submit-Race (R10-F-01), doppelt gemeldete `setState`-Pattern (R10-F-02), UUID-Header (R10-F-06), null-Match-Spinner (R10-F-04), Status-Banner-Fehlen (R10-F-10), Polling-ohne-Stop (R10-F-12), hardcoded-Limits (R10-F-14). Hotfix-Wave-Schnitt: R10-F-13 zuerst (15min, Routing-Fix, MUSS-Fix #2 aus Projekt-Memory), dann R10-F-02 + R10-F-03 als Block (Build-Phase-Fix + Drift-Wire-Up, 1-2h ohne Server-Touch), dann R10-F-01 + R10-F-05 + R10-F-15 als zusammenhängender Submit-Pfad-Refactor (frischer Read + Confirm-Dialog + current_proposal-Konsum), dann R10-F-06 + R10-F-08 + R10-F-11 als RPC-Erweiterungs-Block (`tournament_match_with_participants` liefert Names + myRole + Override-Recht), dann R10-F-04 + R10-F-07 + R10-F-10 als UX-Block (Not-Found + BO-Lock + Status-Banner), R10-F-09 + R10-F-12 + R10-F-14 als Filter/Performance-Wave; R10-F-16 + R10-F-17 als Polish-Wave parallel. M2-Sign-off ist ohne R10-F-01/02/03/05/13 blockiert (Score-Submit-Pfad inkonsistent), R10-F-06/08 sind Demo-Blocker für Live-Tournament-Test.


### Runde 11 — Score-Eingabe + EKC + Consensus

**Hunter-Output**: A=12, B=10, C=10 → konsolidiert auf 9 neue Findings + 8 Verstärkungen aus Runde 10.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R11-F-01 | P0 | EKC-Modell hat kein "Keiner/Zeitablauf" — `TournamentSetScoreProposal.kingHitBy` ist `ParticipantId?`, dokumentiert als "null = noch nicht gefallen", aber im Domain-Modell fehlt der Zustand "Satz beendet ohne Königswurf" (Zeitablauf nach Schweizer Regelwerk §6.4); UI rendert keinen "Kein Königswurf"-Toggle, Server-Spec FR-SCORE-15 erlaubt null nur als Pre-Submit; Folge: Sätze die per Zeitablauf enden produzieren entweder Phantom-King-Hit oder bleiben unsubmittierbar | R11-A-03, R11-A-08, R11-C-01, R11-C-02 | `KingOutcome` Sealed-Class einführen: `HitBy(ParticipantId)` / `Missed` / `TimedOut`; `TournamentSetScoreProposal.kingOutcome` statt `kingHitBy`; UI-Tri-Toggle (Team A / Team B / Keiner) im Set-Card; Server-Migration `2026052800000X_set_king_outcome` mit Check-Constraint, RPC-Mapping erweitern; Standings-/EKC-Berechnung in `packages/kubb_domain/lib/src/tournament/ekc.dart` für `TimedOut` als 0:0-King-Score behandeln |
| R11-F-02 | P1 | Outbox-Provider Polling-Intervall 2s zu langsam — Outbox-Drainer pollt alle 2 Sekunden auf pending Submits/Drafts; bei Tournament-Live-Score wirken 2s Verzögerung als "App reagiert nicht", Spieler tippt erneut und produziert Duplicate-Submits (interagiert mit R10-F-01 Submit-Race) | R11-A-05 | Polling auf 500ms reduzieren ODER ereignisbasiert per `ref.listen` auf `tournamentScoreDraftProvider` triggern; alternative: nach jedem `submitScore`-Call sofort einmal `_drain()` aufrufen ohne auf nächsten Tick zu warten; Backoff bei Netzwerk-Fehlern (500ms → 1s → 2s → 5s exponentiell) |
| R11-F-03 | P1 | Manuelle Eskalation tot — DSCORE-Spec FR-CONF-7 sieht "Captain kann manuell Disput auslösen" vor (bei stillem Einverständnis mit falschem Score von Gegner); UI hat keinen "Disput melden"-Button, weder im Match-Detail noch im Conflict-Screen-Empty-State; Spec-Feature ungebaut | R11-C-04 | `tournament_match_raise_dispute` RPC anlegen (setzt `consensus_round = -1`, status = `disputed`, audit-log-Eintrag); Match-Detail-AppBar-Overflow-Menü `PopupMenuItem(value: 'dispute', child: Text(l10n.tournamentMatchActionRaiseDispute))` mit Confirm-Dialog ("Warum?")-Pflichtfeld; ARB-Keys + Server-RLS-Policy |
| R11-F-04 | P1 | Audit-Log fehlt komplett — keine `tournament_audit_log`-Tabelle, keine RPC-seitige Trigger-Funktion; Override-Reason (DSCORE-50), Dispute-Eskalation (FR-CONF-7), Score-Submit/-Withdraw, Captain-Switch landen nirgends nachvollziehbar; für Schiedsspruch-Pfad und Tournament-Reklamation kritisch | R11-C-10 | Migration `2026052800000Y_audit_log` mit Tabelle (`tournament_id`, `match_id?`, `actor_id`, `action`, `payload jsonb`, `created_at`); Trigger auf Match-Status-Wechsel, Override-Insert, Dispute-Raise; Read-RPC `tournament_audit_log_list(tournament_id)` mit RLS (nur Organizer); Audit-Tab im Tournament-Detail-Screen (Owner+Organizer) |
| R11-F-05 | P1 | `directComparison` Antisymmetrie-Bug — Tiebreaker-Kriterium `directComparison(a, b)` in `packages/kubb_domain/lib/src/tournament/tiebreaker.dart` ist nicht antisymmetrisch: bei 3-Way-Cycle (A schlägt B, B schlägt C, C schlägt A) liefert die Funktion inkonsistente Rangfolge je nach Pivot-Auswahl; verletzt FR-TIE-2 (Sub-Tournament zwischen Tied-Teams) | R11-B-05 | Sub-Tournament-Logik: bei Cycle alle direkten Begegnungen zwischen den N gleich-platzierten Teams als isoliertes Mini-Round-Robin extrahieren, Punkte/Sätze/EKC innerhalb dieser Teilmenge neu berechnen; falls weiterhin Cycle → fallback auf nächstes Kriterium (Set-Diff); Property-Test via glados |
| R11-F-06 | P1 | `TournamentSetInput` erlaubt 5/5 — Domain-Validation `TournamentSetInput.validate()` erlaubt beide Teams mit 5 Basekubbs, obwohl Schweizer Regelwerk verlangt dass mindestens ein Team 6+ erreicht hat (sonst kein Satzende); 5/5 erzeugt ungültigen Persistenz-Zustand der EKC später crashen lässt | R11-B-07 | In `TournamentSetInput.validate()` zusätzliche Regel: `(homeBasekubbs >= maxBasekubbsPerSet || awayBasekubbs >= maxBasekubbsPerSet) && (homeBasekubbs != awayBasekubbs)`; Fehler-Message "Satz unvollständig — ein Team muss mindestens N Basekubbs haben"; Unit-Test mit Boundary-Cases |
| R11-F-07 | P2 | EKC-Memoization fehlt — `computeEkcScore(participantId, matches)` in `ekc.dart` iteriert für jeden Standings-Call O(matches × sets) ohne Cache; bei 16-Team-RR mit 120 Matches × 3 Sets × 16 Standings-Refreshs pro Match-Submit (Match-Liste + Detail + Standings-Screen + Bracket-Preview) sind das 92k Operationen pro Tap | R11-B-06 | `StandingsCache`-Notifier mit `Map<TournamentId, _CachedStandings>`-State; Invalidierung bei jedem Match-Submit/-Override via `ref.invalidate`; alternative pure-Memoize-Funktion in Domain mit `@visibleForTesting`-Cache-Reset; Performance-Budget-Test im Domain-Package |
| R11-F-08 | P2 | Conflict Submitter→A/B Heuristik falsch — Conflict-Screen mappt "ersten gesehenen Submitter" auf Slot A, "zweiten" auf Slot B (CLAUDE.md Section "Bekannte Seams für M2+" #2); bei Re-Submit nach Withdraw fliegt die Reihenfolge, A/B-Zuordnung kippt visuell, Organizer wählt versehentlich falsche Proposal | R11-C-07 | `TournamentSetScoreProposal` um `submittedByTeamSlot: TeamSlot` erweitern (`home` / `away`); Server-RPC `tournament_match_get` JOIN auf `tournament_team_participations` für stabile Zuordnung; Conflict-Screen rendert nach `teamSlot` statt nach Reihenfolge; Withdraw-/Resubmit-stabil |
| R11-F-09 | P2 | DSCORE-43 "Anderer Team-Mitglied hat eingegeben"-Hinweis fehlt — Spec FR-SCORE-43: wenn Captain das Eingabefeld öffnet und Helper hat schon submitted, soll Hint "Mitspieler X hat bereits 6:5/6:4 submittiert" angezeigt werden statt leerer Form; setzt R10-F-15 (`current_proposal_for_team`-Konsum) voraus | R11-C-08 | Setzt R10-F-15-Wire-Up voraus; danach im Set-Card-Header: `if (match.currentProposalForTeam != null && match.currentProposalForTeam.submittedBy != myUserId) Banner(l10n.tournamentMatchHelperSubmittedHint(otherDisplayName, score))`; Toast oder InfoBox-Style, nicht-blockierend |

**Verstärkungen aus Runde 10 (Mehrfach-Treffer, keine Neunummerierung):**

| R10-Final-ID | R11-Verstärkung | Quellen |
|---|---|---|
| R10-F-01 (Submit-Race + Lamport) | Lamport-Race + UNIQUE-Constraint nutzlos: client-side Lamport-Counter wird ohne Mutex inkrementiert, gleichzeitige Submits derselben Session erzeugen identische Lamport-Werte und die UNIQUE-Constraint `(match_id, lamport)` lässt einen davon silent durchfallen | R11-B-01, R11-B-02 |
| R10-F-03 (Score-Draft-Provider tot) | Drift-DAO definiert + Provider existiert + 0 Konsumenten in Match-Detail; doppelter Befund bestätigt M1-Polish-Vergessen | R11-A-04, R11-C-03 |
| R10-F-05 (Submit-Confirm-Dialog) | Doppelt bestätigt: ohne Confirm landet Tap direkt im RPC, kein Undo möglich; in R11-C-05 zusätzlich mit BO3-2:0-Cap-Aspekt kombiniert | R11-A-02, R11-C-05 |
| R10-F-06 (Mein/Gegner-Trennung) | Header zeigt 6-Zeichen-UUIDs UND zusätzlich fehlt visuelle Trennung "mein Team links, Gegner rechts" konsistent über alle Screens | R11-A-01 |
| R10-F-07 (BO3-2:0-Cap) | UI rendert Set 3 auch bei 2:0-Stand, im selben Atemzug mit Confirm-Dialog-Fehlen gemeldet — kombinierter Submit-Pfad-Defekt | R11-C-05 |
| R10-F-08 (Helper/Captain/Gast-Permissions) | Spec FR-PERM-3 unbeachtet: keine clientseitige Role-Auswertung, Submit-Button für jeden authentifizierten User aktiv | R11-C-06 |
| R10-F-13 (Routing zu Conflict-Screen) | Bei `disputed` SnackBar + Route auf Match-Liste statt Conflict-Screen, MUSS-Fix #2 aus Projekt-Memory weiterhin offen | R11-C-05 (Sekundär-Aspekt) |
| R10-F-14 (Hardcoded max_basekubbs/max_sets) | Doppelt bestätigt: `_SetCard` hardcoded 5/3, ignoriert Tournament-Config | R11-C-09 |

**No-Issue / Konsolidierungs-Notizen:**
- R11-A-03 + R11-A-08 + R11-C-01 + R11-C-02 sind vierfach gemeldet auf das EKC-"Keiner/Zeitablauf"-Loch — als R11-F-01 gebündelt, P0 wegen Domain-Modell-Lücke die Migration + UI + Domain gleichzeitig anfasst.
- R11-B-01 + R11-B-02 sind beide auf den Lamport-Race + nutzlose UNIQUE-Constraint — als Verstärkung von R10-F-01 markiert (gleiche Root-Cause-Klasse: Submit-Pfad nicht serialisiert), nicht neu nummeriert.
- R11-A-01 (Mein/Gegner-Trennung) ist Aspekt von R10-F-06 (UUID-Header); beide Fixes überlappen im RPC-Erweiterungs-Block — als Verstärkung gewertet.
- R11-A-02 + R11-C-05 doppeln auf den fehlenden Submit-Confirm-Dialog (R10-F-05); R11-C-05 zusätzlich auf BO3-2:0-Cap (R10-F-07) und disputed-Routing (R10-F-13) — als kombinierte Verstärkungen über mehrere R10-Findings markiert.
- R11-A-04 + R11-C-03 doppeln auf Score-Draft-Persistence dead code (R10-F-03).
- R11-C-06 doppelt auf Helper/Captain/Gast-Permissions (R10-F-08).
- R11-C-09 doppelt auf hardcoded max_basekubbs/max_sets (R10-F-14).
- Neue Findings ohne R10-Vorgänger: R11-F-02 (Outbox-Polling), R11-F-03 (manuelle Eskalation), R11-F-04 (Audit-Log), R11-F-05 (directComparison-Antisymmetrie), R11-F-06 (5/5-Set), R11-F-07 (EKC-Memoization), R11-F-08 (Submitter→A/B), R11-F-09 (DSCORE-43-Hint).
- Keine False-Positives auf App-Code-Ebene identifiziert.

**Zusammenfassung:** Runde 11 produziert nur ein P0-Finding (R11-F-01, vierfach gemeldetes EKC-"Keiner/Zeitablauf"-Loch im Domain-Modell), bestätigt aber acht Runde-10-Befunde durch erneute Mehrfach-Treffer und verlagert damit die Aufmerksamkeit zurück auf den ungeschlossenen Submit-Pfad-Refactor aus R10. Sechs neue P1-Findings adressieren Tooling-Lücken (Outbox-Polling zu träge R11-F-02, manuelle Eskalation tot R11-F-03, Audit-Log fehlt komplett R11-F-04) und Domain-Bugs (directComparison-Antisymmetrie R11-F-05, 5/5-Set akzeptiert R11-F-06). P2 sammelt Performance (EKC-Memoization R11-F-07), Conflict-Mapping-Stabilität (R11-F-08) und DSCORE-43-Hint (R11-F-09, blockiert auf R10-F-15). Hotfix-Wave: zuerst die R10-Verstärkungen abräumen (R10-F-01 + R10-F-03 + R10-F-05 + R10-F-08 + R10-F-14 sind dreifach/doppelt bestätigt), dann R11-F-01 als domain-tiefer Eingriff (Migration + Tri-Toggle UI + EKC-Anpassung, 4-6h Block), R11-F-06 + R11-F-05 als Domain-Property-Test-Sweep parallel; R11-F-02 + R11-F-03 + R11-F-04 als Server/Outbox-Block; R11-F-07 + R11-F-08 + R11-F-09 als Polish-Wave nach R10-F-15-Wire-Up. M2-Sign-off ist ohne R11-F-01 blockiert (EKC ohne Zeitablauf-Pfad ist kein vollständiger Schweizer-Regelwerk-konformer Score), R11-F-04 (Audit-Log) ist Demo-Blocker für offizielle Turniere wegen Reklamations-Pfad. Mehrfach-Hit-Muster der Runde: vierfach EKC-Zeitablauf (R11-F-01), doppelt Lamport-Race als Re-Validation von R10-F-01, doppelt Draft-Provider-Vergessen als Re-Validation von R10-F-03, doppelt Confirm-Dialog als Re-Validation von R10-F-05 — der R10-Fix-Backlog ist die heisseste Spur, nicht Runde 11 isoliert.



### Runde 12 — Conflict-Screen + Organizer-Override-Screen

**Hunter-Output**: A=12, B=13, C=11 → konsolidiert auf 11 neue Findings + 2 Verstärkungen aus früheren Runden.

| Final-ID | Severity | Titel | Quellen | Fix-Strategie |
|---|---|---|---|---|
| R12-F-01 | P0 | Forfeit-Surface komplett fehlt — Veranstalter hat keinerlei Eintrags-Pfad für No-Show/Abbruch; DSCORE-62..-66 + FR-MATCH-7/-8 + BR-14 fordern eigene Aktion mit Side-Auswahl, automatischem Score aus `matchFormatConfig.forfeit_points` (FR-CFG-11), Pflicht-Begründung und Notification; Domain kennt `match_event.forfeit` aber `TournamentActions`/`TournamentRepository` exponieren keine RPC, kein Sheet, kein Screen | R12-C-01 | RPC `tournament_match_forfeit` (match_id, absent_side, reason) + `TournamentActions.declareForfeit` + neues Sheet im Match-Detail (Radio Team A/B abwesend, Reason ≥10 Zeichen, Score aus Config abgeleitet); Status-Gate auf `tournament.status == running`; Audit-Log-Event `match_forfeit_declared` |
| R12-F-02 | P0 | Conflict-Provider liefert hartkodiert `TournamentConflictSnapshot.empty` — `tournamentConflictProvider` ignoriert die existierende `buildConflictSnapshot`-Funktion, `snapshot.pairs.isEmpty` ist immer wahr, der Side-by-Side-Diff zeigt nie etwas an; der dokumentierte M2-Seam ist im User-Flow ein leerer Screen, kein "kommt-noch"-Hinweis | R12-A-02, R12-B-06 | RPC `tournament_match_get` um `proposals: List<TournamentSetScoreProposal>` erweitern (Server-Migration), Provider wired `buildConflictSnapshot(proposals, consensusRound)`; bis Server liefert: explizite "Feature in Vorbereitung"-UI statt leeres Diff-Panel; Unit-Test auf `buildConflictSnapshot`-Gruppierung damit kein Rot beim Wire-Up |
| R12-F-03 | P0 | Conflict-Screen "Veranstalter dazu" + Match-Detail-Escalate ist reine SnackBar — Button verspricht Eskalation, ruft aber nur `ScaffoldMessenger.showSnackBar` und navigiert zurück; kein RPC, keine Statusänderung, keine Notification an Organizer; deckungsgleich mit R11-F-03 (manuelle Eskalation tot) | R12-A-03, R12-C-10 | RPC `tournament_match_raise_dispute(match_id, note?)` setzt `consensus_round = -1`, `status = disputed`, Audit-Event; Conflict-Screen + Match-Detail: `showDialog<bool>` mit Hinweis "kann nicht zurückgenommen werden" + optionalem Notiz-Feld, bei `true` RPC aufrufen, sonst Button bis M4 disablen mit Tooltip |
| R12-F-04 | P0 | Permission-Modell auf Conflict + Override gated nur auf `isCallerCreator` — Co-Veranstalter (Tournament-Spec Glossar Z.102) und Helper (Lukas-Wunsch FR-PERM-3) sind weder im Detail-Modell noch im Permission-Gate verdrahtet; Conflict-Screen prüft `currentUserIdProvider` gar nicht, Override-Screen prüft nur Single-Creator; Player und Organizer sehen identische Buttons; Override de facto Single-Veranstalter | R12-A-04, R12-C-03 | `TournamentDetail` um `coOrganizerIds: List<UserId>` + `helperIds: List<UserId>` erweitern (RPC `tournament_get` ergänzen); Permission-Helper `canOverride = isCreator \|\| isCoOrganizer`, `canSubmitScore(participantId) = isMember \|\| isHelperFor(participantId)`; Conflict-Screen rendert Organizer-View (Score-Diff + direkter Override-CTA) vs. Player-View (Neu-eingeben + Eskalation); Override-Gate auf `canOverride` |
| R12-F-05 | P0 | Override-Submit ohne Confirm-Dialog + ohne Provider-Invalidate nach Erfolg — DSCORE-54 + Sektion 14.6 fordern expliziten Bestätigungsdialog ("Du überschreibst die Score-Eingabe, wird im Audit-Log festgehalten"); `FilledButton.onPressed` ruft direkt `_submit` ohne Zwischenschritt; nach Erfolg `context.go(matchDetail)` ohne `ref.invalidate(tournamentMatchDetailProvider \| tournamentDetailProvider)`; UI zeigt weiterhin `disputed`-Status + Override-Banner bis Auto-Refresh; deckungsgleich mit R10-F-05 (Submit-Confirm-Dialog) | R12-A-09, R12-B-02, R12-B-08, R12-C-02, R12-C-08 | Vor `n.submit()` `showDialog<bool>` mit Set-Zusammenfassung + Reason-Preview + "Override bestätigen"; nach Erfolg `ref.invalidate(tournamentMatchDetailProvider(matchId)); ref.invalidate(tournamentDetailProvider(tournamentId));` vor `context.go`; im Controller selbst nach erfolgreichem RPC den Notifier-State zurücksetzen |
| R12-F-06 | P0 | Conflict-Provider Submitter→A/B-Heuristik instabil — `buildConflictSnapshot` mappt "first-seen submitter = Team A" über Insertion-Order; bei Re-Submit nach Withdraw oder wenn Server by `submitted_at` sortiert wechselt die A/B-Spalte je Reload, Organizer wählt versehentlich falsche Proposal; deckungsgleich mit R11-F-08 (zum dritten Mal gemeldet, Mehrfach-Hit Runde 10/11/12) | R12-A-10, R12-B-06, R12-C-09 | Domain-Erweiterung: `TournamentSetScoreProposal.submittedByTeamSlot: TeamSlot` (home/away) als first-class field; Server `tournament_match_get` JOIN auf `tournament_team_participations`; Snapshot rendert nach `teamSlot` statt Insertion-Order; bis Domain-Erweiterung: deterministische Sortierung über `submitterUserId`-Hash statt `submitted_at` |
| R12-F-07 | P1 | `toSetScores` Tie-Default = Team A bei `basekubbsA == basekubbsB` ohne King-Toggle — `winner: d.king ?? (d.basekubbsA >= d.basekubbsB ? SetWinner.teamA : SetWinner.teamB)`; bei 3 leeren Default-Sets (0:0|0:0|0:0) und `setsToWin = 2` evaluiert `isScoreDecisive == true` mit `setsWonA = 3`, `canSubmit = true` ohne dass Organizer etwas eingegeben hat; Audit-Spur zeigt Phantom-Team-A-Sieg | R12-A-07, R12-B-07 | Tie-without-King in `toSetScores` als undecisive markieren (`SetWinner?` nullable) oder `isScoreDecisive` zusätzlich prüfen dass jeder Set einen Marker hat (`king != null \|\| basekubbsA != basekubbsB`); Screen-Validation blockt `canSubmit` bei undecisive sets; ergänzt R11-F-01 (`KingOutcome.timedOut`) — beide Domain-Patches gehören in denselben Migrations-Block |
| R12-F-08 | P1 | Override-Reason-Validation: Single-Char OK, kein Minimum, Surrogate-unsicheres Clamping — `isReasonValid()` akzeptiert "x", ".", "a" — Audit-Spur wertlos; `setReason` clamped via `substring(0, 500)` zerschneidet UTF-16-Surrogate-Pairs bei Emojis; Counter zeigt `trim().length` während Clamp auf Roh-Länge arbeitet → Inkonsistenz "490/500" während intern schon abgeschnitten; Sektion 14.6 fordert ≥10 Zeichen | R12-B-04, R12-C-11 | `static const reasonMin = 10;` in Controller, `isReasonValid` prüft `trimmed.length >= reasonMin && <= reasonMax`; Counter + Clamp auf gleiche Metrik (raw length); Surrogate-aware Truncation via `characters` package (`String.characters.take(reasonMax).toString()`); ARB-Key für Min-Length-Hinweis |
| R12-F-09 | P1 | `_syncReason` Listener-Loop + Cursor-Reset bei Clamp — `_syncReason` schreibt `_reason.value = clamped` was den TextField-Listener erneut triggert; im Stable-Case Early-Return, aber bei parallelem Riverpod-Rebuild oder weiterer Listener-Mutation Loop-Risiko; zusätzlich springt der Cursor bei jedem Clamp auf `TextSelection.collapsed(offset: clamped.length)` und verliert die User-Cursor-Position bei mittiger Bearbeitung über 500 Zeichen | R12-A-08, R12-B-05 | Reentrancy-Guard `_syncing: bool` flag um `_reason.value = ...`; `removeListener` während des programmatischen Set, danach `addListener`; Cursor-Position nur am Limit korrigieren (`if (oldText.length > reasonMax) selection = end`), sonst `_reason.selection` erhalten |
| R12-F-10 | P1 | `organizerOverride` Repository ohne Token-Mapping + ohne typisierten Exception-Wrapper — im Gegensatz zu `overrideKoPairing` (Lines 502+) und `startKoPhase` (477-500) hat `organizerOverride` (428-445) kein `try/catch` auf `PostgrestException`; Server-Tokens `MATCH_NOT_DISPUTED`, `STALE_OVERRIDE`, `ALREADY_FINALIZED` werden als roher Postgrest-String an die UI gereicht; SnackBar zeigt `PostgrestException(message: ..., code: 23514)` statt lokalisierter Meldung | R12-B-03 | Analog zu `overrideKoPairing`: `OrganizerOverrideException`-Typ einführen, `_overrideTokenFromException` analog zu `_scoreConflictTokenFromException`, RPC-Aufruf in try/catch, Tokens auf ARB-Keys mappen; Confirm-Dialog (siehe R12-F-05) zeigt diese Tokens dann lokalisiert |
| R12-F-11 | P1 | Audit-Sicht im Conflict + Override leer/unvollständig — DSCORE-46 fordert "Tabelle aller Versuche, beide Seiten nebeneinander mit submittendem Mitglied" + Hinweis "automatisch vs. manuell eskaliert"; DSCORE-57 fordert Proposal-Sichtbarkeit; Conflict-Screen rendert nur aktuelle `consensusRound`, keine Historie, keine Submitter-Anzeige; Override-`_proposalsCard` ist leerer Seam ohne Inhalt; Sektion 7.2 Schritt 6 fordert für Spieler Versuch 2 Diff zum vorherigen Versuch; ergänzt R11-F-04 (Audit-Log fehlt komplett) | R12-C-04, R12-C-05, R12-C-06 | Setzt R11-F-04 (Audit-Log-Tabelle) voraus; `TournamentConflictSnapshot` um `previousRounds: List<RoundSnapshot>` + `submitter: UserRef` pro Proposal; `TournamentMatchRef` um `escalationKind: auto \| manual` + `escalatedBy: UserRef?`; Conflict-Screen ExpansionTile "Vorherige Versuche"; Override-`_proposalsCard` zeigt Audit-Tail gefiltert auf `match_id` (Submitter, Runde, Satz-Daten, Status) |
| R12-F-12 | P2 | Conflict-Diff Single-Side-Submission nicht hervorgehoben — `conflict_comparison_row.dart:25-28` setzt `both = a != null && b != null`; bei einseitiger Eingabe sind `diffA/B/W` alle `false`; Teams sehen kein visuelles Signal dass Gegenseite noch fehlt; DSCORE-37 + Sektion 14.3 fordern explizite Hervorhebung "Eingabe fehlt" mit neutraler aber klarer Markierung | R12-C-07 | Eigener `_cell`-Zustand `missing` mit Strich-Pattern + `KubbTokens.fgMuted`; Statusbanner über der Diff-Tabelle "Gegner hat noch nicht eingetragen"; ARB-Key `tournamentConflictWaitingForOpponent` |
| R12-F-13 | P2 | Override-Status-Gate binär ohne graceful Behandlung von `completed` — `if (match.status != TournamentMatchStatus.disputed) return gate(...)` zeigt generischen roten Fehlertext ohne Hinweis "wurde bereits durch anderen Organizer entschieden — siehe Audit"; nach Submit wird Draft im Notifier nicht zurückgesetzt bis autoDispose, nächste Öffnung könnte stale state zeigen; verschachtelte `AsyncValue.when` ohne Combined-State zeigt Loading wenn matchAsync error bei detailAsync loading | R12-A-11, R12-B-11 | Status-spezifische Gate-Texte (`pending` / `completed` / `cancelled` je eigene ARB); nach erfolgreichem Submit explizit `ref.invalidate(tournamentOverrideControllerProvider)`; Combined Provider `tournamentOverrideContextProvider` der Detail + Match zusammenfasst und einen einzigen `AsyncValue` exponiert |

**Verstärkungen aus früheren Runden (Mehrfach-Treffer, keine Neunummerierung):**

| Final-ID | R12-Verstärkung | Quellen |
|---|---|---|
| R10-F-13 (`disputed` routet nicht zum Conflict-Screen) | Vierter Re-Hit auf MUSS-Fix #2 aus Projekt-Memory: Match-Detail zeigt nur SnackBar "Versuch X von 3" und navigiert nicht aktiv auf `TournamentRoutes.conflict(...)`; Conflict-Screen ist gebaut + geroutet aber im echten User-Flow tot, niemand landet hier ausser per Deep-Link | R12-A-01 |
| R10-F-05 (Submit ohne Confirm-Dialog) | Erneut bestätigt für Override-Submit, kombiniert mit fehlendem Provider-Invalidate als R12-F-05 P0-Block | R12-C-02 (Teilaspekt von R12-F-05) |
| R10-F-14 (Domain-Limits hardcoded) | `maxAttempts = 3` hartcodiert in Conflict-Screen (Z.28) UND in Override-Screen (Z.331, Magic-Number `tournamentMatchConsensusAttempt(round, 3)`) — drei Stellen für die gleiche Konstante | R12-A-12, R12-B-12 |
| R11-F-03 (manuelle Eskalation tot) | Re-Hit als R12-F-03 P0 (SnackBar statt Eskalations-RPC + Confirm-Dialog) | R12-A-03, R12-C-10 |
| R11-F-08 (Submitter→A/B-Heuristik) | Dritter Re-Hit als R12-F-06 P0 — diesmal mit konkreter Domain-Erweiterung `submittedByTeamSlot: TeamSlot` als Fix-Vorschlag statt nur `participantId` | R12-A-10, R12-B-06, R12-C-09 |
| R11-F-04 (Audit-Log fehlt komplett) | Bestätigt als Voraussetzung für R12-F-11 (Audit-Sicht im Conflict + Override) — ohne Audit-Tabelle ist die Versuchs-Historie nicht renderbar | R12-C-04, R12-C-05 |

**No-Issue / Konsolidierungs-Notizen:**
- R12-A-05 (Override-Submit setzt `submitting` nicht zurück bei Sync-Throw vor await) ist Aspekt von R12-F-05 (Validation-StateError als Toast statt lokalisierter Meldung) — als kombinierte HIGH-Verstärkung in R12-F-05 aufgenommen.
- R12-A-06 (Override-Controller nicht `.family`) ist ein Aspekt von R12-F-09 (TextField-Sync-Probleme) — der `autoDispose`-ohne-Family hängt mit dem fehlenden Sync zwischen Notifier-State und TextField zusammen; als Sekundär-Aspekt von R12-F-09 markiert, kein eigenes Finding.
- R12-B-01 (Submit-Reentrancy-Gate greift erst nach Validation) ist Teil-Aspekt von R12-F-05 — der `StateError` aus `submit()` wird im Screen als Backend-Toast gerendert, was misleading ist; als Validation-vs-Backend-Trennung in R12-F-05 mitaufgenommen.
- R12-B-09 (build() macht redundante `toSetScores` + `computeEkc` bei jedem Rebuild) ist eine Performance-Nische, kein Korrektheitsbug — als Polish-Backlog markiert, nicht in den 13 Final-Findings.
- R12-B-10 (Conflict-Provider nicht autoDispose) ist Folge von R12-F-02 (Provider liefert sowieso empty, kein Cache-Problem solange leer) — wird mit dem M2-Wire-Up zu autoDispose-Family konvertiert, kein separates Finding.
- R12-B-13 (updateSet ohne Range-Validation) ist Defensive-Polish ohne realistisches Trigger-Szenario (Widget clamped selbst) — als Backlog-Polish markiert.
- R12-C-08 (Override navigiert auf Match-Detail ohne `ref.invalidate`) ist exakt der zweite Aspekt von R12-F-05 — als gemeinsame Quelle gewertet.
- Keine False-Positives auf App-Code-Ebene identifiziert.

**Zusammenfassung:** Sechs P0-Findings dominieren die Runde, davon ist R12-F-01 (Forfeit-Surface komplett fehlt) ein neuer struktureller P0 ohne Vorgänger — DSCORE-62..-66 + FR-MATCH-7/-8 sind nicht ausführbar, weil weder RPC noch Sheet existieren. R12-F-02 (Conflict-Provider liefert `empty`) und R12-F-04 (Permission-Modell nur Single-Creator) blockieren M2-Sign-off auf der Spec-Ebene — der Conflict-Screen ist gebaut aber im User-Flow tot, und Co-Veranstalter/Helper sind nicht verdrahtet. R12-F-03 (Eskalation reine SnackBar) und R12-F-05 (Override ohne Confirm + ohne Invalidate) sind kombinierte Multi-Hit-Befunde aus allen drei Hunter-Outputs, kombiniert mit R10-F-05 + R11-F-03. R12-F-06 (Submitter→A/B-Heuristik) ist der dritte Re-Hit über drei Runden — diesmal mit konkretem Domain-Patch (`TournamentSetScoreProposal.submittedByTeamSlot`) statt nur Memo-Notiz. P1 sammelt fünf Domain/Repository-Fixes (Tie-Default-Bug R12-F-07, Reason-Min-Length + Surrogate R12-F-08, Listener-Loop R12-F-09, Token-Mapping R12-F-10, Audit-Sicht R12-F-11), P2 die zwei UI-Polish-Punkte (Single-Side-Diff R12-F-12, Status-Gate-Texte R12-F-13). Mehrfach-Hit-Muster der Runde: dreifach Submitter→A/B (R12-F-06 + R11-F-08 + R10-F-Memo-Seam), dreifach Submit-ohne-Confirm + Invalidate (R12-F-05 + R10-F-05 + R11-Verstärkung), dreifach Eskalation-SnackBar (R12-F-03 + R11-F-03 + R10-F-Memo), zweifach Conflict-Routing nicht erreicht (R12-A-01 + R10-F-13 MUSS-Fix). Hotfix-Wave-Schnitt: zuerst R10-F-13 abräumen (15min Routing-Fix, MUSS-Fix #2 aus Projekt-Memory hängt seit drei Runden), dann R12-F-04 + R12-F-02 als RPC-Erweiterungs-Block (`tournament_get` um Co-Veranstalter/Helper, `tournament_match_get` um Proposals), dann R12-F-05 + R12-F-10 als Override-Submit-Pfad-Refactor (Confirm-Dialog + Provider-Invalidate + typisierter Exception-Wrapper + Token-Mapping), dann R12-F-03 + R12-F-06 als Eskalations + A/B-Slot-Domain-Erweiterung (RPC `tournament_match_raise_dispute` + `submittedByTeamSlot` als first-class field, beide gehen in den gleichen Migrations-Block), R12-F-01 (Forfeit) als eigener Migration + UI-Block (4-6h), R12-F-07 + R12-F-08 + R12-F-09 als Domain-Validation + UX-Sweep parallel, R12-F-11 nach R11-F-04-Audit-Log-Schiene; R12-F-12 + R12-F-13 als Polish-Wave. M2-Sign-off ist ohne R12-F-01/02/03/04/05/06 blockiert (Forfeit-Pfad fehlt, Conflict-Screen leer, Eskalation nicht funktional, Permission-Modell nur Single-Creator, Override ohne Sicherheits-Check, A/B-Mapping instabil); R12-F-11 (Audit-Sicht) ist Demo-Blocker für offizielle Turniere weil Reklamations-Pfad nicht nachvollziehbar.

### Runde 13 — Standings + Bracket-Visualizer

**Quellen:** R13-A (12 Findings, 5×HIGH/4×MED/2×LOW), R13-B (10 Findings, 3×HIGH/5×MED/2×LOW), R13-C (11 Findings, 4×HIGH/4×MED/3×LOW). Fokus: `tournament_standings_screen.dart`, `tournament_bracket_screen.dart`, `bracket/bracket_canvas.dart`, `bracket/bracket_connector_painter.dart`, `bracket/kubb_match_card.dart`, `tournament_bracket_provider.dart`, `tournament_pool_standings_screen.dart` und Wizard-KO-Step.

| Final-ID | Severity | Beschreibung + Beweis | Quellen | Fix (1 Satz) |
|---|---|---|---|---|
| R13-F-01 | P0 | Bracket-Tap navigiert mit Layout-ID statt DB-Match-Id — `BracketCanvas._onTap` baut `context.go('/tournament/${t.value}/match/$matchId')` mit `matchId = 'r${r}-m${i}'` bzw. `'third-place'` (synthetisch aus Layout-Loop), Match-Detail-Screen erwartet aber die UUID aus `Pairing.matchId`; User tippt eine KO-Paarung und landet auf 404/leerem Detail oder triggert FK-Fehler — Bracket-Visualizer ist im User-Flow unbrauchbar | R13-A-01, R13-B-06 | `KubbMatchCard.onTap` mit `pairing.matchId` (echte UUID aus Domain) statt Layout-Schlüssel aufrufen; Layout-Schlüssel `r$r-m$i` nur intern für `rects`-Map behalten, Tap-Callback bekommt `Pairing` direkt mit |
| R13-F-02 | P0 | Standings rendert UUID-Prefix statt Team-/Spieler-Name — `_DataRow._short(stats.participantId).substring(0, 8)` zeigt z.B. `"a1b2c3d4"` als Name; Re-Hit von R10-F-06 (Roster-Owner-UUID-Prefix), drittes Vorkommen über drei Runden; ohne Lookup auf `tournamentTeams`/`tournamentRosterMembers` ist die finale Tabelle für jeden Endnutzer unleserlich | R13-A-05, R13-C-09 (Verstärkung R10-F-06) | Standings-Provider um `Map<ParticipantId, String> displayNames` ergänzen (Server-RPC `tournament_standings` joined Team/Player-Name); Screen rendert `displayNames[stats.participantId] ?? l.tournamentParticipantUnknown`, Prefix-Hack entfernen |
| R13-F-03 | P0 | Tiebreaker-Chain hardcoded auf [Wins, Buchholz, KubbDiff] — `computeStandings`/`_DataRow` ignoriert `TournamentConfig.tiebreakerChain` aus dem Wizard (Sektion 14.5 erlaubt `H2H`, `BergerSonneborn`, `KubbDiff`, `Buchholz`, `RandomDraw`); Setup-Wizard erfasst die Reihenfolge aber Domain-Sort nutzt sie nicht; bei abweichender Turnier-Config divergiert die UI-Reihenfolge vom Reglement → Reklamationsrisiko | R13-A-03, R13-C-01 | `computeStandings(config: TournamentConfig)` Signatur erweitern, Comparator-Chain dynamisch aus `config.tiebreakerChain` bauen; Spaltenreihenfolge im Header analog konfigurieren; bei `RandomDraw` UI-Indikator |
| R13-F-04 | P0 | Pool-Standings: EKC- + GamesWon-Spalten fehlen trotz Domain-Feldern — `ParticipantStats` liefert `endkubbsScored`, `endkubbsConceded`, `gamesWon`, `gamesLost`, Pool-Screen rendert sie nicht; FR-STAND-3 verlangt EKC-Anzeige; Header zeigt zusätzlich Label `"Sets"` aber Cell rendert `wins` (R13-C-11) → falsche Beschriftung in der Spalte | R13-C-02, R13-C-11 | Pool-Standings-Header um EKC- + Games-Spalten erweitern, ARB-Keys `tournamentStandingsEkc`, `tournamentStandingsGames`; Label-Cell-Mismatch `Sets`/`wins` korrigieren auf eindeutige Bezeichnung (z.B. `tournamentStandingsWins`) |
| R13-F-05 | P0 | Pool-Standings-Header zeigt "Sets" während Cell `wins` rendert (Label-Bug) — siehe R13-F-04 für Konsolidierung; eigener P0 weil Label-zu-Wert-Mismatch eine direkte Falschanzeige im offiziellen Reglement-Sichtbarkeits-Pfad ist | R13-C-11 | siehe R13-F-04 |
| R13-F-06 | P1 | KO-Grösse-Auswahl ohne Quick-Pick (4/8/16/32) — Wizard-KO-Step erzwingt Freitext/Spinner, Re-Hit von Runde 6 R6-F (zweites Vorkommen); R13-C-03 + R13-C-10 bestätigen denselben Mangel an `_wizard_ko_config_step.dart`; UX-Reibung beim Setup, kein Korrektheitsbug aber Demo-Blocker | R13-C-03, R13-C-10 (Verstärkung R6-F) | `SegmentedButton<int>` mit Werten [4,8,16,32] als Quick-Pick + Custom-Override-Option; Default = nächst-grössere 2er-Potenz der Team-Zahl |
| R13-F-07 | P1 | Doppel-KO-Modus ohne Coming-Soon-Tile + Disable-Reason — Wizard zeigt Doppel-KO weder als disabled-Choice noch mit Hinweis "ab M3"; Re-Hit von R6-F (zweites Vorkommen); User wählt Single-Elim ohne zu wissen dass Double-Elim geplant ist | R13-C-04 (Verstärkung R6-F) | Wizard-KO-Step: Doppel-KO als disabled `RadioListTile` mit Trailing-`Chip("Bald verfügbar")` + Tooltip; ARB-Key `tournamentWizardKoDoubleElimComingSoon` |
| R13-F-08 | P1 | "Spiel um Platz 3" Connector fehlt im Painter — `BracketConnectorPainter` zeichnet nur Halbfinal→Final-Linien; das 3rd-Place-Match (`BracketPhase.thirdPlace`) ist als Rect platziert aber ohne Connector zu den Halbfinal-Verlierern → optisch zusammenhanglos | R13-C-06 | `BracketConnectorPainter` um Sonderfall für `phase == thirdPlace` erweitern: gestrichelte Verbindungen von beiden Semifinal-Loser-Slots zum 3rd-Place-Card; Connector-Style differenziert von Winner-Path |
| R13-F-09 | P1 | Bye-Visualisierung inkonsistent — bei `Pairing` mit nur einem Team rendert `KubbMatchCard` als normales Match mit leerem zweiten Slot; kein "Bye"-Badge, kein Auto-Advance-Indikator; Layout-Math behandelt Bye als reguläre Card statt als Skip-Knoten | R13-C-07 | `Pairing.isBye` (Domain-Helper) + `KubbMatchCard` rendert kompakte Bye-Variante mit ARB-Key `tournamentBracketBye`; Connector zeichnet direkte Linie zur nächsten Runde ohne Match-Card |
| R13-F-10 | P1 | Polling läuft auch nach Tournament-Finalisierung weiter — `tournamentBracketPollingProvider` triggered Refetch alle X Sekunden ohne Status-Gate; Re-Hit von Runde 10 (R10-Verstärkung), drittes Vorkommen (R13-A-11 + R13-B-01 + R13-B-08); Battery + Netz-Last bei archivierten Turnieren | R13-A-11, R13-B-01, R13-B-08 (Verstärkung Runde 10) | Polling-Provider liest `tournament.status` mit, stoppt bei `finalized`/`cancelled`; identischer Fix wie für Live-Dashboard-Polling und Match-List-Polling — gemeinsame Abstraktion `pollingWhileActive(status)` |
| R13-F-11 | P1 | Buchholz im Standings-Screen lokal berechnet ≠ Domain-Wert — `_DataRow` berechnet `buchholz = opponentIds.fold(... opponentTotalPointsLookup[id] ?? 0)` während `computeStandings` denselben Wert intern bereits liefert; UI rechnet auf Heuristik-Basis (TotalPoints-Lookup), Domain hat fest definierte Buchholz-Variante → mögliche Divergenz zu Live-Dashboard und Server-Standings | R13-A-04 | `ParticipantStats.buchholz` als Domain-Feld exponieren; UI nur lesen, nicht neu rechnen; Tests im Domain-Layer pinnen den Wert |
| R13-F-12 | P1 | Winner-Highlight wird nicht durch BracketCanvas an Card durchgereicht — `KubbMatchCard` hat `highlight`-Prop, `BracketCanvas` setzt sie nie (`editable` ja, Winner-Marker nein); auch dann nicht wenn `pairing.winnerId != null`; KO-Visualisierung wirkt status-blind | R13-A-02 | `BracketCanvas` propagiert `winnerSlot: pairing.winnerSlot` an `KubbMatchCard`; Card markiert Sieger-Zeile mit `KubbTokens.meadow100` Hintergrund analog Standings-Self-Row |
| R13-F-13 | P2 | `BracketHighlightPainter` ist Dead-Code — Klasse + Painter existieren in `bracket_connector_painter.dart` aber werden nirgends instanziiert; Re-Hit über zwei Hunter (R13-A-07 + R13-B-07); Codebase-Polish | R13-A-07, R13-B-07 | Entfernen oder einkommentieren mit Verweis auf geplantes Feature (Winner-Path-Highlight) — bevorzugt entfernen, R13-F-12 deckt den Use-Case mit dem Card-Highlight ab |
| R13-F-14 | P2 | Tablet-Layout fehlt im Standings-Screen — feste Column-Flex-Verhältnisse (`1/4/2/2/2/2`) ohne Breakpoint; auf Tablets >900px wirkt die Tabelle schmal und Bracket-View nutzt `InteractiveViewer` ohne Two-Column-Variante (Standings links + Bracket rechts) | R13-A-06 | `LayoutBuilder` mit `KubbBreakpoints.tablet`: Two-Column-Layout (Standings 40% + Bracket 60%) auf >900px; Standings selbst behält Flex-Layout aber mit grosszügigerem Spacing |
| R13-F-15 | P2 | BracketLayout-Recompute pro Build ohne Memoization — `BracketCanvas.build` ruft `BracketLayout.compute(bracket)` jedes Mal; bei InteractiveViewer-Pan/Zoom re-buildet das Stack-Tree → Layout-Math (Rect-Map mit O(rounds×matches)) jedes Frame; Re-Hit dreifach (R13-B-02 + R13-B-05 + R13-B-10) | R13-B-02, R13-B-05, R13-B-10 | `useMemoized`/`Provider.family((bracket) => BracketLayout.compute(bracket))` für Layout-Caching keyed auf Bracket-Hash; alternativ `BracketCanvas` zu `StatefulWidget` mit `didUpdateWidget`-Recompute |
| R13-F-16 | P2 | `tournamentBracketProvider` ohne autoDispose — Provider bleibt im ProviderContainer nach Screen-Pop, Polling-Provider hängt mit dran; Re-Hit-Muster aus früheren Runden (Provider-autoDispose-Sweep) | R13-B-08 | `tournamentBracketProvider` zu `.family.autoDispose` konvertieren; identisches Pattern wie für `tournamentMatchProvider` aus Runde 10 |
| R13-F-17 | P2 | `Bracket` sealed mit nur einem Subtyp — `SingleEliminationBracket` ist einzige Implementierung von `Bracket`, das `sealed` keyword (oder gleichwertiges Pattern-Matching) suggeriert Doppel-KO-Variante die nicht existiert; Discoverability-Mangel, kein Runtime-Bug | R13-B-03 | Entweder `DoubleEliminationBracket` als `coming-soon`-Stub ergänzen (verknüpft mit R13-F-07) oder `sealed`/`abstract` zu konkretem Typ degradieren bis Doppel-KO landet |
| R13-F-18 | P2 | `bracketFromMatches` schluckt Inkonsistenzen still — Domain-Helper baut `Bracket` aus Match-Liste ohne Validierungs-Errors bei fehlenden Vorrunden-Verbindungen oder doppelten `round`-Werten; Stille Fehler im KO-Bau sind schwer zu debuggen | R13-B-04 | `bracketFromMatches` wirft `BracketConstructionException` bei Lücken/Duplikaten; Repository fängt + loggt + zeigt UI-Banner "Bracket-Daten inkonsistent — bitte Organizer kontaktieren" |
| R13-F-19 | P2 | BackButton im Standings-Screen nutzt `context.go(matchesFor(...))` statt `pop()` — Re-Hit von R10-F-11 (zweites Vorkommen); zerstört Navigations-Historie und wiederholt Detail→Standings→Matches→Detail-Pingpong | R13-A-09 (Verstärkung R10-F-11) | `onPressed: () => context.canPop() ? context.pop() : context.go(TournamentRoutes.matchesFor(tournamentId))`; identischer Fix wie für andere BackButton-Stellen aus R10 |
| R13-F-20 | P3 | Empty-State macht keinen Unterschied zwischen "noch keine KO-Phase" und "wirklich leer" — `_isEmpty` returned `true` für sowohl Group-Phase-noch-aktiv als auch echte Leerstrukturen; UI zeigt identischen Text `tournamentBracketEmpty` ohne Phase-Hinweis | R13-A-10 | Empty-State unterscheidet via `tournament.status`: `groupPhase` → "KO-Phase startet nach Gruppenphase", `ko`/`finalized` ohne Bracket → "Keine KO-Daten verfügbar"; zwei ARB-Keys |

**No-Issue / Konsolidierungs-Notizen:**
- R13-A-04 + R13-A-11 + R13-B-01 + R13-B-08 (Polling) sind ein einziger Befund — als R13-F-10 mit Mehrfach-Quelle gewertet.
- R13-B-02 + R13-B-05 + R13-B-10 (Layout-Memoization) drei Hunter-Sichten auf denselben Performance-Mangel — R13-F-15.
- R13-A-07 + R13-B-07 (BracketHighlightPainter dead) → R13-F-13.
- R13-A-08 (Bracket-Provider Riverpod-Generator-Cache-Key-Collision) ist Folgewirkung von R13-F-16 (autoDispose) — als sekundärer Aspekt notiert, nicht separat gelistet.
- R13-B-09 (Connector-Painter `shouldRepaint` returned immer `true`) ist Performance-Polish — als Sekundär-Aspekt von R13-F-15 markiert, beide werden im selben Recompute-Pass adressiert.
- R13-C-05 (Pool-Standings ohne H2H-Tiebreaker-Hinweis) ist Unteraspekt von R13-F-03 — selber Domain-Patch deckt beide ab.
- R13-C-08 (KO-Bracket-Card Border-Radius inkonsistent) ist Token-Polish ohne Verhaltens-Auswirkung — Backlog, nicht in Final-Liste.

**Zusammenfassung:** Fünf P0-Findings dominieren Runde 13 — der gravierendste ist R13-F-01 (Bracket-Tap mit Layout-ID statt DB-UUID), der den Bracket-Visualizer im User-Flow vollständig kaputt macht und in zwei Hunter unabhängig auftauchte. R13-F-02 (UUID-Prefix als Namen-Anzeige) ist der dritte Re-Hit auf das fehlende Display-Name-Mapping aus Runde 10 R10-F-06 — derselbe Mangel zieht sich jetzt durch Roster, Live-Dashboard und Standings. R13-F-03 (Tiebreaker-Chain hardcoded) ignoriert die Wizard-Config und blockiert M2-Sign-off, weil offizielle Turniere mit abweichendem Reglement falsch sortiert werden. R13-F-04 + R13-F-05 (Pool-Standings EKC-Spalten fehlen + Label-Bug "Sets" zeigt `wins`) sind direkte FR-STAND-3-Verstösse und ergeben in offiziellen Demos sofort sichtbar falsche Tabellen. P1 sammelt sieben Punkte (Quick-Pick KO-Grösse + Doppel-KO-ComingSoon als zweite Re-Hits aus Runde 6, Spiel-um-Platz-3-Connector + Bye-Visualisierung + Winner-Highlight als Bracket-Visual-Polish-Schiene, Polling-after-finalized als drittes Vorkommen, Buchholz-Lokal-Rechnung als Domain-vs-UI-Divergenz). Hotfix-Wave-Schnitt: R13-F-01 als 30-Minuten-Fix sofort (echte UUID an `onTap` durchreichen), dann R13-F-02 als RPC-Erweiterungs-Block (`tournament_standings` joined Names), dann R13-F-03 + R13-F-11 als Domain-Comparator-Refactor (`computeStandings(config)` + `ParticipantStats.buchholz` als Feld), R13-F-04 + R13-F-05 als Pool-Standings-Header-Sweep (EKC + Games + Label-Fix), R13-F-06 + R13-F-07 als Wizard-Polish-Wave, R13-F-08 + R13-F-09 + R13-F-12 als Bracket-Painter-Wave (Third-Place-Connector + Bye-Badge + Winner-Highlight), R13-F-10 als Polling-Status-Gate-Abstraktion gemeinsam mit den Polling-Re-Hits aus R10/R11; R13-F-13..R13-F-20 als Polish-Wave parallel. M2-Sign-off ohne R13-F-01..R13-F-05 blockiert (Bracket-Tap broken, Names = UUID-Prefix, Tiebreaker ignoriert Config, EKC + Label falsch); R13-F-12 (Winner-Highlight) ist Demo-Blocker weil KO-Visualisierung sonst status-blind wirkt.

### Runde 14 — Public-Tournament + Public-Match + Live-Toggle

**Quellen:** R14-A (12 Findings, 3×HIGH/7×MED/2×LOW), R14-B (10 Findings, 2×HIGH/5×MED/3×LOW), R14-C (12 Findings, 7×HIGH/4×MED/1×LOW). Fokus: `lib/features/tournament/presentation/public/public_tournament_screen.dart`, `public_match_screen.dart`, `lib/features/tournament/application/public_live_mode_provider.dart`, `public_tournament_polling_provider.dart`, `lib/app/public_router_shell.dart`, `lib/core/data/supabase/anon_session.dart`, ADR-0023 + FR-PUB-1..-12 + FR-MAP-2.

| Final-ID | Severity | Beschreibung + Beweis | Quellen | Fix (1 Satz) |
|---|---|---|---|---|
| R14-F-01 | P0 | Anon-RLS-Pfad greift im Client gar nicht — `AnonSessionBootstrapper.ensureAnonSession` ruft `supabase.auth.signInAnonymously()` (anon_session.dart:53), das in Supabase einen User mit JWT-Claim `role: authenticated` + `is_anonymous: true` erzeugt; die in `20260701000002_tournaments_public_flag.sql` angelegten Spectator-Policies sind `FOR SELECT TO anon` und feuern damit nie zur Laufzeit, obwohl die pgTAP-Tests (`supabase/tests/public_rls_test.sql`) explizit über `set_config('role','anon',true)` testen — Test-Suite und Produktions-Pfad divergieren, ADR-0023's „echte anon"-Modell ist gebrochen | R14-C-01 | Entscheiden: entweder Bootstrap auf reinen anon-Header umstellen (kein `signInAnonymously`, JWT-frei direkt mit `apikey`) und Policies + RPCs auf `TO anon` ausrichten — oder ADR-0023 aktualisieren auf „authenticated-anonymous"-Modell und alle `TO anon`-Policies + pgTAP-Tests konsistent umstellen |
| R14-F-02 | P0 | `tournament_get` RPC ist `GRANT EXECUTE … TO authenticated` (20260525000003_tournament_discovery_registration_rpcs.sql:191) — `PublicTournamentScreen` baut Header+Schedule auf `tournamentDetailProvider → getTournamentDetail → rpc('tournament_get')`; ein „echter" anon-Caller (Role `anon`, ohne JWT) bekommt 401/403, die T1-RLS-Policies werden nie geprüft; selbst mit `signInAnonymously` (R14-F-01) umgeht das ADR-0023's Anon-Modell statt es zu erfüllen | R14-C-02 | Dedizierten Public-RPC `public_tournament_get` mit `SECURITY DEFINER`, `GRANT EXECUTE … TO anon`, projiziert nur spectator-taugliche Felder (kein `user_id`, kein `email`); Client-Repository entsprechenden Public-Read-Pfad parallel zum Auth-Pfad halten |
| R14-F-03 | P0 | Privacy-View `public_tournament_roster_view` (in T1-Migration angelegt) hat null Aufrufer im Client (`grep public_tournament_roster_view lib/` leer) — stattdessen liefert `tournament_get` die volle `participants`-Liste inkl. `'user_id', p.user_id` (Migration ZL.135) und `TournamentParticipant.userId` (kubb_domain/lib/src/ports/tournament_remote.dart:226) wird an Public-Screens durchgereicht; ADR-0023 §3 schreibt explizit „keine User-IDs, keine E-Mails" für Spectator vor — Privacy auf DB-Ebene gebaut, Client umgeht sie | R14-C-03 | Public-Repository-Methode `getPublicTournamentDetail` einführen, die `public_tournament_roster_view` liest (nur `display_name`); `PublicTournamentScreen` + `PublicMatchScreen` ausschliesslich diesen Pfad konsumieren, niemals den Owner-`TournamentDetail` |
| R14-F-04 | P0 | Live-Toggle + Polling-Provider sind kompletter dead code — `publicLiveModeProvider` (public_live_mode_provider.dart) und `publicTournamentPollingProvider` (public_tournament_polling_provider.dart) existieren, sind aber nirgendwo in `public_tournament_screen.dart` referenziert (Grep auf beide Identifier liefert nur Definitions-Dateien); Doc-Block des Live-Mode-Providers verspricht „false (default) → 10s Polling, true → Realtime subscribe", Realität: Screen watcht unbedingt `tournamentMatchListRealtimeProvider` + `tournamentBracketRealtimeProvider` → jede Anon-Session öffnet Realtime-Channel, Tier-2-Limit (500 concurrent subs, ADR-0004) wird bei Viralität gerissen, kein UI-Switch existiert | R14-A-01, R14-B-01, R14-C-05 | `ref.watch(publicLiveModeProvider)` im Screen lesen, Realtime-Watches in `if (live) { … } else { ref.watch(publicTournamentPollingProvider(id)); }` aufteilen, `SwitchListTile` in AppBar binden — Default `false` honorieren wie Doc-Block es verspricht |
| R14-F-05 | P0 | Match-Tap im Spielplan-Tab tut nichts — `_ScheduleTab` baut jede `TournamentMatchCard(... onTap: () {})` mit leerer Closure (public_tournament_screen.dart:225); zentrale Spec-Flow-Anforderung „Match-Tap → public_match_screen" ist gebrochen, gesamte Route `/public/match/:matchId` (in router.dart registriert + `PublicMatchScreen` implementiert) ist vom UI aus unerreichbar — nur per direktem Deeplink | R14-A-02 | `onTap: () => context.go('/public/match/${m.matchId.value}')` via `PublicTournamentRoutes.match(id)`-Helper analog zu bestehenden Tournament-Routes-Konstanten |
| R14-F-06 | P0 | `matchFormatConfig['public']`-Gate ist broken Theater — Screen prüft `d.tournament.matchFormatConfig['public'] != false` (public_tournament_screen.dart:73), aber DB-Migration legt `tournaments.public boolean NOT NULL DEFAULT true` als eigene Spalte an, NICHT als Key in `matchFormatConfig`; `tournament_get` projiziert den neuen public-Flag nirgends in das matchFormatConfig-Wire-Payload → Wert ist immer `null` → `null != false` → `true` → `_notPublic`-Fallback feuert nie, auch nicht für DB-seitig private Turniere; Drittes Vorkommen über drei Hunter, Domain-Entity-Wire-Mapping-Bug | R14-A-03, R14-B-03, R14-C-08 | `Tournament.isPublic` als first-class Domain-Feld einführen, `tournament_get`-RPC + `public_tournament_get` projizieren `public` als top-level Wire-Key, `Tournament.fromJson` mappt Spalte; Screen liest `d.tournament.isPublic` statt Map-Lookup |
| R14-F-07 | P0 | Stammdaten/Round-Clock/Player-/Team-/Club-Profile fehlen vollständig (FR-PUB-2/-4/-7/-8/-9 sind MUSS) — `_body` zeigt nur `displayName + StatusPill + "Runde X von Y · N Teilnehmer"`, fehlend: Veranstalter-Profil-Link, Datum/Uhrzeit, Spielort/Adresse, Team-Format/Modus, **Anmelde-Button für `registration_open`** (FR-PUB-2 MUSS), **Lageplan-Bild** (FR-MAP-2 MUSS), **laufende Runden-Clock** (FR-PUB-4 + FR-LIVE-5/6 MUSS — kein `round_clock`-Provider existiert), **Spieler-/Vereins-/Team-Profile** (FR-PUB-7/-8/-9 MUSS — `find lib -name "*player_profile*" -o -name "*team_profile*" -o -name "*club_profile*"` liefert leer, keine Routes `/public/player/:id`, `/public/team/:id`, `/public/club/:id`) | R14-C-04, R14-C-05, R14-C-06 | Eigener M5-Sprint: Stammdaten-Block in `_body` (Veranstalter+Date+Venue+Format), `RegistrationCta`-Widget für `registration_open`, `LageplanImage`-Widget (FR-MAP-2), `roundClockProvider` als Realtime+Polling-Hybrid + Countdown-Header, drei Profile-Routen mit Repository-Pfaden + Public-RPCs |
| R14-F-08 | P0 | QR-Code-Sharing für Spectator-Link fehlt — ADR-0023 begründet das Anon-Modell explizit mit Viralität („Spectator-Link funktioniert ohne Login — Viralität ist möglich"), aber `grep -rin "qr\|share" lib/features/tournament` liefert null Hits, kein pubspec-Eintrag für `qr_flutter`, kein „Link teilen"-Button im Organisator-Detail-Screen; ohne Share/QR ist das gesamte Public-Modell nicht diskoverabel — der spec-relevante Viralitäts-Pfad existiert nicht | R14-C-07 | `qr_flutter` als Dependency (Stack-ADR), `TournamentShareSheet`-Widget mit QR-Code + Plattform-Share via `share_plus`, AppBar-Action im Organisator-Detail-Screen + im Public-Screen selbst |
| R14-F-09 | P0 | Bracket-Tab swallowed alle Errors als „Bracket noch nicht verfügbar" — `_BracketTab` (public_tournament_screen.dart:311-347) hat `error: → 'Bracket noch nicht verfügbar'` mit Kommentar „Group phase returns no KO rows — collapse error to empty state"; ein erwarteter Zustand (Pool-Phase ohne KO) wird per Error-Side-Channel signalisiert statt typisiertem Result — Netzwerkfehler, RLS-Block, Format-Inkompatibilität werden alle zur selben „noch nicht verfügbar"-Anzeige verschluckt, Operator-Diagnose unmöglich | R14-C-11 | `tournamentBracketProvider` liefert `BracketStatus.unavailable` als typisiertes `Either`/`Result` für Pool-Phase, Error-Pfad zeigt echte Fehler durch (Banner „Verbindungsfehler — Retry") |
| R14-F-10 | P1 | UUID-Substrings statt Namen in Public-Screens — `_ScheduleTab` nutzt `nameFor: (id) => id.value.substring(0, 6)`, `_StandingsTab` `s.participantId.substring(0, 8)`; Anon-Spectator sieht „a3f9c2" und „1. 3a9f7c11 · 12 · 4W · 6" statt Nicknames; `PublicMatchScreen` macht es korrekt via `nameById`-Map aus `tournamentDetailProvider.participants` — Inkonsistenz zwischen den beiden Screens; Vierter Re-Hit über vier Runden (R10-F-06 + R13-F-02 + R14-A-04 + R14-A-05 + R14-C-09) — derselbe Mangel zieht sich jetzt durch Roster, Live-Dashboard, Standings UND Public-Surface | R14-A-04, R14-A-05, R14-C-09 (Verstärkung R10-F-06 + R13-F-02) | `nameById`-Map aus `public_tournament_roster_view` (R14-F-03) einmal im Screen-Header bauen, an `_ScheduleTab` + `_StandingsTab` durchreichen — beide Tabs lesen `nameById[id] ?? l.tournamentParticipantUnknown` statt Substring-Hack |
| R14-F-11 | P1 | `anonSessionBootstrapper` Race zwischen initState-Capture und Adapter-State + `_pending` cleart bei Success nicht — `_PublicRouterShellState.initState` liest `ref.read(anonSessionBootstrapperProvider).ensureAnonSession()` synchron in `late`-Feld (public_router_shell.dart:31-34), bei zwischenzeitlichem Sign-Out/Token-Expire bleibt Shell auf `connectionState == done` und reicht Child weiter → 401-Crash ohne Retry; zusätzlich: `_pending`-Cache im Bootstrapper bleibt nach Success bestehen, wenn Token später expiriert greift der completed-Future-Shortcut OBWOHL Adapter signed-out ist, zweiter `ensureAnonSession`-Call hängt am alten Future-Slot, neue Sign-In wird nicht ausgelöst — Race-Condition | R14-A-08, R14-B-02, R14-B-07 | `_pending` zu `Completer` umstellen, von `supabaseAuthAdapterProvider.onAuthStateChange` gefüttert; Shell horcht via `ref.listen(authControllerProvider)` auf Statuswechsel, regeneriert `_bootstrap` bei signedOut; catch-`(_)` klassifiziert Fehlertyp + loggt via `package:logging` |
| R14-F-12 | P1 | Realtime-Fehler werden in Public-View komplett verschluckt — beide Public-Screens watchen `StreamProvider`-Realtime-Provider, ohne `AsyncValue.hasError` zu inspizieren; bei Connect-Fehler (Token expired, Supabase-Outage, RLS-Reject) bleibt Stream im Error-Zustand, Match-Listen-FutureProvider wird nie invalidiert, Screen zeigt unendlich Stale-Snapshot — kein UI-Indikator, kein Log, kein Fallback-Polling obwohl `realtime_fallback_provider` vorhanden ist | R14-B-04 | Stream-AsyncValues explizit lesen + bei `rt.hasError` Banner „Live-Stream offline, Fallback auf Polling" + `publicTournamentPollingProvider` als Backup einhängen + `package:logging`-Warnung |
| R14-F-13 | P1 | Bootstrap-Error ohne Retry-UI — bei `snapshot.hasError` rendert Shell `Text('${snapshot.error}')` im leeren Scaffold (public_router_shell.dart:46-55) ohne Retry-Button, ohne lokalisierten Text, ohne Back-Navigation; Spectator landet in Sackgasse, Deeplink-Reopen einzige Recovery-Option; Doc-Block oben behauptet „recoverable on retry" — nicht implementiert | R14-A-09, R14-B-09 | Lokalisierter „Verbindung fehlgeschlagen"-String + `ElevatedButton`-Retry der `setState(() => _bootstrap = ref.read(...).ensureAnonSession())` auslöst |
| R14-F-14 | P1 | Tournament-Detail in `_renderMatch` geseeded mit Loading-Race — `PublicMatchScreen._renderMatch` liest `ref.watch(tournamentDetailProvider(match.tournamentId)).asData?.value?.participants ?? const <TournamentParticipant>[]`; während Detail-Provider lädt ist Liste leer, alle Labels werden `?`, nach Rebuild springen sie auf echte Namen → UX-Flicker; bei dauerhaftem Error (Network, RLS-Block) zeigt Screen „? vs ?" ohne Fehler-Anzeige | R14-A-06 | Beide Async-Resolves joinen (`matchAsync` UND `detailAsync` warten auf Daten) bevor `_renderMatch` rendert; Error-Pfad sichtbar machen mit Banner |
| R14-F-15 | P1 | `match == null` faellt unsichtbar auf Endlos-Spinner zurück — `PublicMatchScreen` rendert `match == null ? CircularProgressIndicator() : _renderMatch(...)`; bei validem RPC-Response mit Body=null (voided/nicht oeffentlich/nicht existent) sieht Anon-User Endlos-Spinner, Realtime-Stream feuert nicht weil Match nicht existiert, kein User-Feedback — vergleichbarer Fall im PublicTournamentScreen ist mit `_notPublic` sauber gelöst | R14-A-07 | Bei `match == null` Empty-Card rendern („Spiel nicht gefunden" / „Spiel nicht oeffentlich") mit Back-Button zum Tournament-Screen |
| R14-F-16 | P1 | Hardcoded Strings statt l10n in Public-Tournament-Screen — alle User-facing-Strings hartcodiert Deutsch („Turnier", „Spielplan", „Rangliste", „Bracket", „Runde X von Y", „Teilnehmer", „Noch keine Spiele geplant", „Dieses Turnier ist nicht öffentlich"), während `PublicMatchScreen` korrekt `AppLocalizations` nutzt; Verstoss gegen `tech-lead.md`-Konvention „Jeder User-facing-String läuft über AppLocalizations" — Phase-2-Sprach-Wechsel wird teuer | R14-B-10 | ARB-Keys (`publicTournamentTitle`, `publicTournamentTabSchedule`, …) hinzufügen, Strings durchziehen; Phase 1 nur `de`, Indirektions-Layer Pflicht |
| R14-F-17 | P2 | Bracket-Tap auf Public-Screen kann Edit-Sheet öffnen — Aufruf `BracketCanvas(bracket: bracket, editable: false)`; Doc-Kommentar behauptet „`tournamentId: null` tells BracketCanvas to swallow taps" aber Parameter wird nicht gesetzt; Read-Only-Garantie hängt damit von `editable: false`-Semantik ab, ggf. wird Detail-Navigation aus Anon-Kontext doch erlaubt → Anon-User landet auf privatem Match-Detail-Screen; Doc und Code nicht in Sync | R14-A-10 | `BracketCanvas`-API klären: wenn Doc stimmt, `tournamentId: null`-Parameter ergänzen; wenn API anders, Doc anpassen; Widget-Test für Read-Only-Mode verankern |
| R14-F-18 | P2 | Hardcoded 10s-Polling-Intervall ohne Backoff/Konfig — `Timer.periodic(const Duration(seconds: 10), ...)` (public_tournament_polling_provider.dart:19), keine Adaptions-Strategie bei laufendem Realtime, keine Backoff bei Fehlern, keine zentrale Config; falls Provider parallel zum Realtime gemounted wäre, redundante Invalidates | R14-A-11 | Intervall aus zentraler Config-Datei ziehen, Timer nur starten wenn Live-Toggle aus (R14-F-04); Exponential-Backoff bei Fehler-Refetches |
| R14-F-19 | P2 | Path-Param-Validation fehlt in `PublicMatchScreen` + `PublicTournamentScreen` — `TournamentMatchId(matchId)` wird direkt aus Router-Param gebaut, kein UUID-Check; bei kaputter/manipulierter URL (leerer String, „null"-Literal, falsches Format) feuert RPC mit Müll, `PostgrestException` landet als generischer Error → roher `.toString()` im UI mit Stacktrace-Schnipsel | R14-B-03 | Pre-Validation im Router-Redirect-Layer oder Screen: `if (id.isEmpty || !_isUuid(id)) → "Ungültiger Link"-Screen`; nie Mülldaten an Supabase-RPC durchreichen |
| R14-F-20 | P2 | TabController als `late final`-Field-Initializer + ConsumerWidget-Tabs rebuilden bei jedem Realtime-Tick — `late final TabController _tabs = TabController(...)` läuft erst beim ersten Lese-Zugriff, `dispose()` triggert late-init wenn `build()` nie aufgerufen wurde (Screen sofort verworfen) → unnötiger Controller; zusätzlich rebuilden `_StandingsTab`/`_BracketTab` bei jedem äusseren Realtime-Tick weil Screen-`build` rebuildet, `when`-Closures laufen pro Rebuild bei hoher Score-Submit-Frequenz | R14-B-05 | `_tabs` in `initState` initialisieren; Tab-Children mit `Consumer`-Scope-Trick aus Screen-Realtime-Watch herausnehmen, sodass nur betroffener Subtree rendert |
| R14-F-21 | P2 | Polling-Timer ohne `ref.onCancel`-Disziplin — `Provider.autoDispose.family<void, TournamentId>` instanziiert `Timer.periodic` ohne explizites Cleanup-Pattern, Provider-Body ist `void`-typisiert → Konsumenten müssen `ref.watch(...)` für Side-Effect schreiben, was `unused_result`-Lints triggert; Tests mit `ProviderScope(overrides: …)` lassen Timer parallel weiterlaufen → flaky | R14-B-06 | Auf `StreamProvider` mit `Stream.periodic` oder `Notifier` mit `start()`/`stop()` migrieren; mindestens Doc-Block ergänzen „Side-Effect-Provider — Konsument muss `ref.watch` aufrufen" |
| R14-F-22 | P2 | `_roundsCounter` zählt BYE-only-Runden falsch — `current` wird nur erhöht, wenn Match `!= scheduled`; KO-Runde aus reinen BYEs bleibt `scheduled` und wird nie als „aktuell" erkannt, UI behauptet „Runde 1 von N" obwohl praktisch Runde 2/3 läuft; Edge-Case aber Anon-Spectator-relevant | R14-A-12 | BYE-Status nach Bracket-Gen direkt auf `finalized` setzen (Domain-Fix) oder `_roundsCounter` BYEs als „passed" mitzählen lassen |
| R14-F-23 | P2 | „Alle Runden"-Archiv (FR-PUB-5) nicht abgegrenzt — Spielplan-Tab gruppiert alle Matches nach `roundNumber`, vermischt geplant/laufend/abgeschlossen; fehlt: visuelle Trennung „abgeschlossen/laufend/geplant", Sortierung nach Zeit (aktuelle Runde oben), Filter-Chips „Nur Live"/„Nur Abgeschlossen"; `TournamentMatchCard` ist primär für Organisator-Sicht gebaut, zeigt potenziell mehr Felder als für Spectator angebracht | R14-C-10 | Spielplan-Tab in zwei Sektionen splitten („Live + nächste Runde" + „Archiv"), Filter-Chips, `PublicMatchCard`-Variante mit reduzierten Spectator-Feldern |
| R14-F-24 | P3 | Doppelte Auth-Check-Branch in `ensureAnonSession` ist tote Logik — `isAuthenticated` ist `kind != signedOut` (supabase_auth_adapter.dart:36), erste `if`-Branch returnt auch für `kind == anonymous`; zweite `if`-Branch (`kind == anonymous`) ist unerreichbar | R14-B-08 | Zweite Branch löschen oder erste auf `kind == keypair \|\| kind == oauth` einschränken |
| R14-F-25 | P3 | Public-Feature-Bereich trägt AI-typisch lange Doc-Comments — `public_tournament_screen.dart` Z.13-21 enthält „erklärenden" Header mit Selbstreferenzen auf Plan-Doku („M4.2-T1 ships the column but M4.2-T8's dependency chain does not extend the dart entity"), `anon_session.dart` 38 Zeilen Doc für Klasse mit zwei Methoden, `public_router_shell.dart` 16 Zeilen Header — Verstoss gegen humanStyle.md („Default keine Kommentare; nur WHY, knapp"), Kommentar-Dichte deutlich über Repo-Schnitt | R14-C-12 | Header-Doc-Comments einkürzen auf 1-2 WHY-Zeilen, Plan-Doku-Referenzen entfernen, Implementierungs-Details aus Klassen-Headers raus |

**No-Issue / Konsolidierungs-Notizen:**
- R14-A-01 + R14-B-01 + R14-C-05 (Live-Toggle + Polling tot) → ein Befund R14-F-04 mit Triple-Source.
- R14-A-03 + R14-B-03 + R14-C-08 (matchFormatConfig['public']-Gate broken) → R14-F-06; Wire-Mapping-Bug, dritter Hunter sieht auch die DB-Spalten-Divergenz.
- R14-A-04 + R14-A-05 + R14-C-09 (UUID-Substrings) → R14-F-10; vierter Re-Hit gegen R10-F-06 + R13-F-02 — selbe Domain-Lücke (Display-Name-Lookup) zieht sich durch Roster → Live-Dashboard → Standings → Public-Surface.
- R14-A-08 + R14-B-02 + R14-B-07 (Bootstrap-Race + `_pending`-Cleanup) → R14-F-11; alle drei beschreiben denselben Lifecycle-Bug aus unterschiedlichen Blickwinkeln.
- R14-A-09 + R14-B-09 (Bootstrap-Error ohne Retry) → R14-F-13.
- R14-A-02 (Match-Tap leer) ist Single-Source aber zentraler User-Flow-Breaker → R14-F-05 als eigenständiger P0.
- R14-C-01 (Anon-Rollen-Pfad) + R14-C-02 (RPC-Grant `authenticated`) sind zwei Layer derselben Architektur-Lücke aber methodisch trennbar — als R14-F-01 und R14-F-02 separat gelistet, beide P0 und im selben Migrations-Block zu fixen.
- R14-C-04 + R14-C-05 + R14-C-06 (Stammdaten + Round-Clock + Profile fehlen) → R14-F-07 als kombinierter M5-Block; jeweils MUSS-Anforderungen aus FR-PUB-2/-4/-7/-8/-9, gemeinsamer Sprint sinnvoll weil derselbe Public-RPC-Surface erweitert wird.
- R14-A-10 (Bracket-Tap-Read-Only-Garantie) ist Polish ohne dokumentierten Trigger — als R14-F-17 mit P2, sollte aber im Widget-Test verankert werden.
- R14-A-12 (BYE-only-Runde) ist Domain-Edge-Case → R14-F-22, häufiger bei kleinen Gruppen-Brackets.
- Keine False-Positives identifiziert; alle drei Hunter sind unabhängig auf dieselben Strukturlücken gestossen.

**Zusammenfassung:** Neun P0-Findings dominieren Runde 14 — der schwerste neue Befund ist R14-F-01 (Anon-RLS-Pfad greift nicht: `signInAnonymously` erzeugt `authenticated`-Rolle, alle `TO anon`-Policies sind tot, pgTAP-Tests und Laufzeit divergieren), gefolgt von R14-F-02 (`tournament_get`-RPC nur an `authenticated` granted → echte anon-Caller bekommen 401) und R14-F-03 (Privacy-View `public_tournament_roster_view` hat null Aufrufer im Client → volle `user_id`-Liste geht an Spectator raus, ADR-0023 §3 violiert); diese drei P0-Findings reissen ADR-0023's Spectator-Modell strukturell auseinander. R14-F-04 (Live-Toggle + Polling tot, alle drei Hunter unabhängig) zerstört die in ADR-0021 + Plan-Doku verankerte Cost-Mitigation gegen viralen Realtime-Andrang; R14-F-05 (Match-Tap leer) macht den gesamten Public-Match-Screen vom UI unerreichbar; R14-F-06 (`matchFormatConfig['public']`-Gate broken, dritter Hunter) zeigt einen Wire-Mapping-Bug zwischen DB-Spalte und Dart-Entity; R14-F-07 (Stammdaten + Round-Clock + drei Profile-Typen fehlen) ist die grösste Spec-Lücke der Runde — FR-PUB-2/-4/-7/-8/-9 + FR-MAP-2 als MUSS-Anforderungen sind grossteils nicht implementiert; R14-F-08 (QR-Sharing fehlt) reisst den ADR-0023-Viralitäts-Pfad ab; R14-F-09 (Bracket-Error-Swallow) verschluckt RLS-Blocks und Netzwerkfehler still. R14-F-10 (UUID-Substrings) ist der vierte Re-Hit über vier Runden gegen denselben Display-Name-Mapping-Mangel aus R10-F-06 → R13-F-02 — derselbe Domain-Patch wirkt auf Roster + Live-Dashboard + Standings + Public-Surface. P1 sammelt sechs Befunde (Bootstrap-Race + `_pending`-Cleanup als Triple-Source, Realtime-Error-Swallow, Bootstrap-Error ohne Retry als Double-Source, Tournament-Detail-Seed in build, `match==null`-Endlos-Spinner, l10n-Convention-Violation). Hotfix-Wave-Schnitt: zuerst R14-F-05 als 10-Minuten-Fix (`onTap` mit echter Route binden), dann R14-F-01/-02/-03 als zusammenhängender Migrations-Block (Public-RPC `public_tournament_get` + `public_tournament_match_get` mit `GRANT EXECUTE … TO anon`, View-basierter Roster-Pfad, RLS-Policies vereinheitlichen, ADR-0023 entscheiden: `anon`-Rolle oder `authenticated-anonymous`), dann R14-F-06 als Domain-Wire-Refactor (`Tournament.isPublic` first-class), R14-F-04 als Live-Toggle-Wire-Up parallel zu R14-F-12 (Realtime-Error-Banner + Polling-Fallback) — beide adressieren dasselbe Realtime-Cost-Risiko; R14-F-07 als eigener M5-Sprint mit Public-RPC-Surface-Erweiterung (Stammdaten + Round-Clock + drei Profile-Pfade); R14-F-08 (QR-Share) als Stack-ADR + UI-Sweep; R14-F-09 + R14-F-15 (Error-Surfaces) als Public-Surface-Robustness-Wave; R14-F-10 (Display-Names) im selben Patch wie R14-F-03 (Roster-View); R14-F-11 + R14-F-13 + R14-F-14 als Anon-Bootstrap-Lifecycle-Refactor (Completer + AuthState-Listener + Retry-UI); R14-F-16 (l10n) + R14-F-25 (Doc-Comment-Sweep) als humanStyle-Cleanup parallel. M2-Sign-off ist ohne R14-F-01..R14-F-07 blockiert (Anon-Pfad strukturell broken, Privacy violiert, Live-Toggle tot, Match-Tap dead, Public-Gate broken, Spec-MUSS-Anforderungen FR-PUB-2/-4/-7/-8/-9 nicht implementiert); R14-F-08 (QR-Share) ist Demo-Blocker für Pilot weil Public-Modell ohne Share-Pfad nicht diskoverabel ist; R14-F-09 (Error-Swallow) ist Operator-Diagnose-Blocker im Live-Betrieb. Re-Hit-Muster der Runde: vierfach Display-Name-Mapping (R14-F-10 + R13-F-02 + R10-F-06 + Live-Dashboard), dreifach Live-Toggle/Polling tot (R14-A-01 + R14-B-01 + R14-C-05), dreifach matchFormatConfig['public']-Gate (R14-A-03 + R14-B-03 + R14-C-08), dreifach Bootstrap-Race + `_pending`-Cleanup (R14-A-08 + R14-B-02 + R14-B-07), zweifach Bootstrap-Error-UI fehlt (R14-A-09 + R14-B-09).

### Runde 15 — Live-Dashboard

**Quellen:** R15-A (12 Findings, 2×HIGH/5×MED/5×LOW), R15-B (9 Findings, 3×HIGH/4×MED/2×LOW), R15-C (10 Findings, 5×HIGH/4×MED/1×LOW). Fokus: `lib/features/tournament/presentation/tournament_live_dashboard_screen.dart`, `lib/features/tournament/application/tournament_live_dashboard_provider.dart`, `lib/features/tournament/application/tournament_realtime_provider.dart`, `docs/specs/tournament-mode-spec.md` (FR-LIVE-1..-10), `docs/plans/m4-realtime-dashboard-offline/architecture.md` §3.2.

| Final-ID | Severity | Beschreibung + Beweis | Quellen | Fix (1 Satz) |
|---|---|---|---|---|
| R15-F-01 | P0 | Runden-Clock-Subsystem (FR-LIVE-5/-6/-7/-8/-9) fehlt komplett — `grep -rn "roundClock\|round_clock\|round_duration_minutes" lib/ packages/ supabase/migrations/` liefert null Treffer; fünf MUSS-Anforderungen (Veranstalter startet Clock, Countdown auf allen Sichten, Pause/Verlängerung/vorzeitiges Ende, konfiguriertes Zeitablauf-Verhalten, globale Pause zwischen Runden) sind weder Domain noch RPC noch UI; `architecture.md` §3.2 erwähnt Clock nicht — strukturelle Lücke, kein UI-Detail | R15-C-01 | Architect-Runde + eigener Milestone-Slice (M4.3): `tournament_round`-Tabelle mit `started_at`/`duration_seconds`/`paused_at`/`paused_for`, RPC-Set `tournament_round_start\|pause\|resume\|extend\|end`, Realtime-Sub auf `tournament_rounds`, persistente Clock-Bar im Live-Dashboard + Spectator-View |
| R15-F-02 | P0 | Runde-manuell-beenden + Nächste-Runde-Gate (FR-LIVE-3/-4) fehlen — kein „Runde beenden"-Button im Dashboard, kein Round-Level-Control in `TournamentActions`, keine `tournament_finish_round`/`tournament_start_next_round`-RPCs; Spec verlangt aktives manuelles End-of-Round-Markieren als Voraussetzung für FR-LIVE-4 — Round-Lifecycle existiert nicht | R15-C-04 | Round-Controller im Dashboard-Header (aktuelle Runde + „Runde beenden", enabled wenn alle Matches `finalized`/`overridden`); Backend-RPCs mit Vorbedingungs-Check |
| R15-F-03 | P0 | Tournament-Abort-Action (FR-LIVE-10) vom Dashboard nicht erreichbar — `abortTournament` existiert in `tournament_repository.dart:254` + `tournament_providers.dart:79` + `tournament_detail_screen.dart:372`, aber AppBar des Live-Dashboards trägt nur `BackButton`, kein Overflow/Action-Item; „jederzeit möglich" gemäss Spec nicht erfüllt wenn User erst zurück zum Detail navigieren muss | R15-C-03 | AppBar-Overflow-Menü mit „Turnier abbrechen" als destructive Action + Confirm-Dialog (analog `tournament_detail_screen.dart`) |
| R15-F-04 | P0 | Permission-Aware-Helper-Rolle fehlt strukturell (Lukas' wiederholter Wunsch + FR-ADM-13) — Dashboard hat keinen Permission-Gate, `tournamentLiveDashboardProvider` prüft nicht ob User Organizer/Helper ist, `abortTournament` ist client-seitig ungatet; kein `tournament_membership_role`-Konzept im Client, Helper-Rolle (darf am Dashboard helfen, nicht abbrechen) nicht modellierbar; Risk: Spieler trifft via URL `/tournament/:id/dashboard` und sieht/manipuliert Internals; mehrfach gemeldet über vorherige Runden | R15-C-05 (Re-Hit aus früheren Runden) | Architect-Runde + ADR für Rollen-Modell `organizer\|helper\|participant`; Riverpod-Family `tournamentRoleProvider(tournamentId)`, Routing-Redirect bei fehlender Rolle, conditional UI für destructive Actions |
| R15-F-05 | P1 | Drei parallele Realtime-Subscriptions auf identischen Channel — `tournamentLiveDashboardProvider` watched gleichzeitig `tournamentMatchListRealtimeProvider` UND `tournamentBracketRealtimeProvider`, beide rufen intern `_realtime.subscribe(table:'tournament_matches', filterColumn:'tournament_id')` mit identischem Filter; je nach Refcount entweder doppelter Channel/Traffic/Postgres-Replication-Decoding oder geteilter Channel mit zwei Listenern — jedes CDC-Event wird zweimal verarbeitet (Match-List-Invalidation + Bracket-Advance-Check), zwei Map-Operationen, zwei Re-Fetches plus Bracket-Refetch auch wenn kein Bracket-Advance vorliegt | R15-B-01 | Einen geteilten `tournamentMatchesRealtimeProvider` einführen, Bracket-Advance-Events serverseitig per Pattern abzweigen (Status-Flip mit `winner_participant`); Dashboard und Bracket-Widget konsumieren denselben Stream über zwei abgeleitete Provider |
| R15-F-06 | P1 | `invalidate()` synchron im Stream-`.map`-Callback erzeugt Frame-Race — alle drei Realtime-Provider in `tournament_realtime_provider.dart:25-29/49-53/70-74` rufen `ref.invalidate(...)` innerhalb `stream.map((event) { ref.invalidate(...); return event; })`; Side-Effect feuert synchron bevor Event an Watcher propagiert ist → laufender Fetch im List-Provider wird gekillt → Loading-Flicker pro CDC-Event; bei Listener-Burst (Bulk-Score-Submit) überlappen mehrere invalidates über Mikrosekunden mit Refetch | R15-B-02 | Side-Effect via `ref.listen` auf den StreamProvider rausziehen, debounced/throttled invalidieren; Map bleibt pure |
| R15-F-07 | P1 | Swallowed Exception in `watchMatch` (repository.dart:574-585) — `getMatch(id)` async-Aufruf ohne try/catch, bei RPC-Timeout/Auth-Fehler/JSON-Parse wird Exception als `addError` vom async\*-Generator in den Stream absorbiert ohne dass der eigentliche Realtime-Channel je versucht wurde; StreamProvider autoDispose hat keinen Retry → Dashboard-Tab-Wechsel und kurze Netzaussetzer enden dauerhaft im Error-State; bei `ref == null` (Match weg) beendet der Stream still ohne erkennbaren Grund | R15-B-03 | `getMatch`-Aufruf in try/catch wrappen, klassifizierten yieldError (transient/terminal); bei `ref == null` Terminal-State-Marker yielden statt Stille |
| R15-F-08 | P1 | Pitch-Nummer DB-Spalte vorhanden, im UI nicht projiziert — `tournament_matches.pitch_number smallint NULL` seit M1-Schema (`20260525000001_tournament_schema.sql:67`), von Pool-/KO-/Swiss-RPCs gefüllt (siehe `20260615000009_*:537`, `20260615000010_*:286`, `20260801000001_*:200`); Projektion in `TournamentMatchRef` (kubb_domain) lässt Feld weg → `_pitchKeyFor` fällt auf `matchId.value` zurück, Sortierung wird UUID-Lotterie, UI zeigt keine Pitch-Bezeichnung; FR-LIVE-1 (farbcodierter „Pitch-Status") ohne Pitch-Label nicht zuordbar zum physischen Platz; doppelt gemeldet | R15-A-02, R15-C-06 | `pitch_number` additiv in `TournamentMatchRef` ergänzen, `tournament_get_matches`-RPC-Select erweitern, Card-Header zeigt „Platz {pitch_number} · Runde {round}"; `_pitchKeyFor` sortiert numerisch, MatchId nur als Tiebreaker |
| R15-F-09 | P1 | Filter fehlt — `tournamentMatchListProvider` liefert alle Matches ohne Status-Filter, Dashboard rendert `finalized`/`voided`/`overridden` gleichberechtigt mit `scheduled`/`awaitingResults`/`disputed`; bei RR-Turnier mit 28 Matches sieht Organizer nach Runde 5 ein Grid voller grüner Karten und muss visuell scannen welche noch laufen; widerspricht Pitch-Grid-Purpose (Status-Farben sollen Aufmerksamkeit lenken, nicht Historie zeigen) | R15-A-01 | Provider filtern: `matches.where((m) => scheduled \|\| awaitingResults \|\| disputed)`; Abgeschlossene optional als separate Section („Abgeschlossen: 14/28") oder `showCompleted`-Toggle in AppBar |
| R15-F-10 | P1 | Konflikte werden nicht prominent — `disputed` optisch identisch zu anderem Match (rote Border + Pill „Strittig"), kein Top-Banner mit Konflikt-Count, keine Sort-Vorzugsbehandlung (Disputed-Cards sollten oben stehen), Tap auf Disputed-Card öffnet `matchDetail` statt schneller `conflict`/`override`-Route — verstösst gegen FR-LIVE-2 („prominent sichtbar"); doppelt gemeldet | R15-C-02, R15-C-09 | Top-Banner mit Konflikt-Anzahl + Button „Alle Konflikte ansehen"; Sort: disputed → awaitingResults → scheduled → finalized; status-abhängiges Routing im Tap-Handler (disputed → `TournamentRoutes.conflict()`) |
| R15-F-11 | P1 | Score auf Pitch-Card fehlt (FR-LIVE-2) — Karte zeigt nur Runde, TeamA, TeamB, Status-Pill, kein aktueller Set-Stand; bei `awaitingResults` sieht Organizer nicht „Pitch 3 läuft seit X Minuten und steht 6:4" — nur „Warten"; Architecture-Doc §3.2 listet „aktueller Score (Sets)" sogar als Pflicht-Spalte, `TournamentMatchRef` hat nur `finalScoreA/B` (gefüllt nach Finalisierung); doppelt gemeldet | R15-A-05, R15-C-07 | `TournamentMatchRef` um `setsWonA`/`setsWonB` erweitern, RPC-Projektion ergänzen, Karte zeigt zentriert „{setsA}:{setsB}" zwischen Teamnamen; bei `scheduled` Anspielzeit oder „—" |
| R15-F-12 | P1 | Status-Farb-Mapping weicht von Architecture-Doc ab — `architecture.md` §3.2: „grün=läuft & beide Teams gemeldet, gelb=laufend aber >2min ohne Update (stale), rot=disputed, grau=scheduled"; aktuell: `awaitingResults`→gelb (jedes laufende Match ab Start gelb), `finalized`/`overridden`→grün (semantisch „fertig", nicht „läuft"), `scheduled`/`voided`→grau (zwei semantisch verschiedene Status zur selben Farbe), `disputed`→rot; gelb=stale-Heuristik fehlt komplett, kein `lastEventAt`-Feld zur Differenz-Bildung; doppelt gemeldet | R15-A-03, R15-C-08 | Vier-Stufen-Mapping mit Zeit-Heuristik: scheduled→grau, awaitingResults & `now-lastEventAt < 2min`→grün, awaitingResults & stale→gelb, disputed→rot, finalized→eigene neutrale Farbe (blau/stone-darkened); `lastEventAt` als Feld projizieren; voided separate Farbe/Pattern |
| R15-F-13 | P2 | Keine Memoization in `_toPitchStatus` + fehlendes ==/hashCode auf `PitchStatus`/`LiveDashboardData` — bei jedem Realtime-Event volle Match-Liste neu durch Mapping, `_resolveName` zweimal pro Pitch gegen `nameById` gehasht, gesamte Liste neu sortiert; `nameById` bei jeder Invalidation neu aufgebaut obwohl Participants nahezu konstant; ohne `==`/`hashCode` rendert `async.when` bei jedem Tick die volle GridView neu inkl. aller PitchCards, `ValueKey('live-card-${matchId}')` verhindert nur Element-Reordering nicht Card-Rebuild → bei Realtime-Burst sichtbares Grid-Flackern (Material-Ripple-Reset, InkWell-Highlight verschwindet) | R15-B-04, R15-B-05 | `nameById` als separater family-Provider (cached, nur bei Participant-Änderung neu); freezed/manuelles `==`+`hashCode` auf `PitchStatus`/`LiveDashboardData` mit list-equality auf `participantNames`; alternativ Selector-Pattern mit family-Provider pro `matchId` |
| R15-F-14 | P2 | `context.go` statt `context.push` — sowohl `BackButton` (Z36-37) als auch Card-`onTap` (Z68) verwenden `context.go`, das den Stack ersetzt statt zu pushen; Card-Tap → Match-Detail: User kann nicht via System-Back zum Dashboard zurück; BackButton: ersetzt Dashboard durch Detail-Screen, bei Deep-Link/Notification-Reopen springt User aus Live-Modus raus; dritter Re-Hit über mehrere Runden (R10-F-11 + R13-F-19 + R14-Backbutton-Pattern) | R15-A-04, R15-B-07 (Verstärkung R10-F-11) | Card-Tap → `context.push`; BackButton → `context.canPop() ? context.pop() : context.go(...)` |
| R15-F-15 | P2 | Realtime-Channels keepalive ohne Listen + fehlendes `ref.onDispose`-Cleanup — `ref.watch(tournamentMatchListRealtimeProvider(...))`/`ref.watch(tournamentBracketRealtimeProvider(...))` ohne Return-Verwendung; bei autoDispose + reine Listener-Provider potentiell erstes CDC-Event verpasst falls Subscription lazy; zusätzlich: kein explizites `ref.onDispose(() { sub?.cancel(); })` in Realtime-Providern → bei AsyncError-Hang nach Wegnavigieren bleibt Subscription u.U. aktiv und öffnet bei Wieder-Eintritt zweiten Channel | R15-A-06, R15-B-06 | Explizit `ref.listen(realtimeProvider, ...)` mit onData-`invalidate()` statt `ref.watch`; in jedem Realtime-Provider `ref.onDispose` mit explizit gehaltener StreamSubscription; bei Map-Error `ref.invalidateSelf()` nach Backoff |
| R15-F-16 | P3 | `consensusRound` wird als „Runde X" gelabelt — Provider mappt `currentRound = m.consensusRound` (Score-Eingabe-Retry-Counter 1..3), UI rendert als „Runde 1"/„Runde 2"; Organizer interpretiert als Turnier-Runde (Round-Robin/KO), bei awaitingResults-Match in Turnier-Runde 4 mit consensus_round=2 steht „Runde 2" auf Karte — falsch; doppelt gemeldet | R15-A-07, R15-B-09 | Feld umbenennen auf `consensusAttempt`; separates `bracketRound` einführen und Label rendern als „Runde 4 · Versuch 2/3" (nur wenn >1); bei `finalized` Versuch-Marker weglassen |
| R15-F-17 | P3 | Empty-State macht keinen Unterschied — `data.pitches.isEmpty → "Keine aktiven Spielfelder."` greift nur bei wirklich leerer Liste; nach Filter-Fix R15-F-09 unterscheidet er drei Fälle nicht: (a) Turnier noch nicht gestartet/`registration_open`, (b) Runde gepaust zwischen zwei Runden (sobald FR-LIVE-9 lebt), (c) alle Matches finalized = Turnier beendet; doppelt gemeldet | R15-A-08, R15-C-10 | Empty-State conditional auf Turnier-Status: „Turnier noch nicht gestartet — Anmeldung offen", „Runde abgeschlossen — Nächste Runde starten", „Turnier beendet — Zur Rangliste" (mit Links) |
| R15-F-18 | P3 | `GridView.count` statt `GridView.builder` + Tablet-Layout schöpft Fläche nicht aus — alle children synchron im Memory, kein lazy build; `crossAxisCount` auf `shortestSide >= 600 ? 3 : 2` ignoriert Landscape-Tablet (1024×768 → 768 → 3 cols obwohl 4-5 möglich), `childAspectRatio: 1.4` für 4 Text-Zeilen + Pill auf schmalen Phones grenzwertig | R15-B-08, R15-A-09 | `GridView.builder` mit `SliverGridDelegateWithMaxCrossAxisExtent` (Max-Cell ~280dp) — responsiv ohne Hardcode-Schwellen, lazy-built |
| R15-F-19 | P3 | BYE-Repräsentation falsch — Provider liefert immer 2-Eintrag-Liste mit `_resolveName` `'?'` bei null; `b = names[1] if length>1 else 'BYE'` wird nie zu „BYE" weil `length == 2` immer; echtes BYE (participantB == null wegen Freilos) wird als „unbekannter Participant" gerendert | R15-A-11 | `_resolveName` mit explizitem null-Pfad → `'Freilos'` statt `'?'`; Domain-Modell prüfen welche Semantik null trägt (BYE vs noch-nicht-gesetzt), ggf. unterschiedliche Marker |
| R15-F-20 | P3 | Hartkodierte deutsche Strings — `'Live-Dashboard'`/`'Keine aktiven Spielfelder.'`/`'Runde $r'`/`'Geplant'`/`'Warten'`/`'Strittig'`/`'Abgeschlossen'`/`'Korrigiert'`/`'Ungültig'` direkt im Code; Verstoss gegen `tech-lead.md`-i18n-Konvention; Re-Hit aus R14 | R15-A-10 | ARB-Keys ergänzen (`tournamentLiveDashboardTitle`, `tournamentLiveDashboardEmpty`, `tournamentLiveDashboardRound`, `tournamentMatchStatusLabel*`); `flutter gen-l10n` nach ARB-Edit |

**No-Issue / Konsolidierungs-Notizen:**
- R15-A-02 + R15-C-06 (Pitch-Nummer DB vorhanden, UI nicht projiziert) → R15-F-08 mit Doppel-Source; UUID-Sortier-Lotterie als Nebeneffekt mitgefixed.
- R15-C-02 + R15-C-09 (Konflikte nicht prominent + Tap-Routing) → R15-F-10; gemeinsamer Banner-/Routing-Sweep.
- R15-A-03 + R15-C-08 (Status-Farb-Mapping weicht von Doc ab) → R15-F-12; benötigt `lastEventAt`-Projektion + Vier-Stufen-Mapping.
- R15-A-05 + R15-C-07 (Score auf Card fehlt FR-LIVE-2) → R15-F-11; `setsWonA/B`-Projektion deckt beide ab.
- R15-A-04 + R15-B-07 (context.go statt push) → R15-F-14; dritter Re-Hit über R10-F-11 + R13-F-19 — selber BackButton-Fix-Pattern.
- R15-A-07 + R15-B-09 (consensusRound als „Runde X") → R15-F-16; Feld-Rename + Label-Klarstellung.
- R15-A-08 + R15-C-10 (Empty-State macht keinen Unterschied) → R15-F-17; conditional auf Turnier-Status.
- R15-B-04 + R15-B-05 (Memoization + ==/hashCode) → R15-F-13; gemeinsamer Rebuild-Pass.
- R15-A-06 + R15-B-06 (Realtime keepalive ohne Listen + onDispose) → R15-F-15; gemeinsamer Subscription-Lifecycle-Fix.
- R15-A-09 + R15-B-08 (GridView.count + Tablet-Layout) → R15-F-18; gemeinsamer Layout-Refactor.
- R15-A-12 (Status-Pill Text-Farbe Kontrast bei Light-Theme) ist Token-Polish ohne Verhaltens-Auswirkung — Backlog, nicht in Final-Liste.
- R15-A-01 (Filter fehlt) ist Single-Source aber zentraler Flow-Mangel → R15-F-09 als eigenständiger P1.
- R15-C-01 (Runden-Clock fehlt) ist die grösste Spec-Lücke der Runde — eigenständig als R15-F-01 P0, fünf MUSS-Anforderungen FR-LIVE-5..-9 zusammen adressiert in M4.3-Architect-Runde.

**Zusammenfassung:** Vier P0-Findings dominieren Runde 15 — der schwerste ist R15-F-01 (Runden-Clock-Subsystem fehlt komplett: FR-LIVE-5/-6/-7/-8/-9 sind fünf MUSS-Anforderungen ohne jegliche Implementation in Domain, RPC, UI oder Architecture-Doc), gefolgt von R15-F-02 (Round-Lifecycle FR-LIVE-3/-4 fehlt — kein „Runde beenden"-Button, kein Next-Round-Gate, keine RPCs), R15-F-03 (Abort-Action FR-LIVE-10 nicht vom Dashboard erreichbar — RPC vorhanden aber AppBar trägt nur BackButton) und R15-F-04 (Permission-aware-Helper-Rolle fehlt strukturell — Lukas' wiederholter Wunsch, kein `tournament_membership_role`-Konzept im Client, kein Routing-Gate, jeder eingeloggte User kann via URL die Dashboard-Internals einsehen). Sieben P1-Findings adressieren Realtime-Hygiene und FR-LIVE-1/-2-Spec-Compliance: R15-F-05 (drei parallele Subscriptions auf identischen Channel — doppelter CDC-Traffic), R15-F-06 (invalidate in stream.map-Callback erzeugt Frame-Race + Loading-Flicker), R15-F-07 (swallowed exception in watchMatch verbirgt RPC-Errors), R15-F-08 (Pitch-Nummer DB-Spalte vorhanden aber in `TournamentMatchRef` nicht projiziert — Sortierung wird UUID-Lotterie, doppelt gemeldet), R15-F-09 (kein Status-Filter — finalized mischt mit scheduled), R15-F-10 (Konflikte nicht prominent + Tap auf disputed routet nach MatchDetail statt Conflict), R15-F-11 (Score auf Card fehlt — Architecture-Doc §3.2 listet ihn als Pflicht-Spalte), R15-F-12 (Status-Farb-Mapping weicht von Architecture-Doc ab — gelb=stale-Heuristik fehlt, finalized und overridden auf dieselbe Farbe wie laufend). Drei P2 (Memoization+`==`/hashCode-Rebuild-Storm, context.go statt push als dritter Re-Hit aus R10-F-11+R13-F-19, Realtime-Channel-Lifecycle-Hygiene mit fehlendem `onDispose`) plus fünf P3-Polish-Findings (consensusRound-Label irreführend, Empty-State undifferenziert, GridView.count statt builder + Tablet-Layout, BYE-Repräsentation als „?", hartkodierte de-Strings). Hotfix-Wave-Schnitt: R15-F-03 + R15-F-09 als 30-Minuten-Quick-Wins (AppBar-Action + Status-Filter im Provider), dann R15-F-08 als Domain-Wire-Refactor (`pitch_number` projizieren — same Pattern wie R14-F-06's `isPublic`), R15-F-11 + R15-F-12 als RPC-Projection-Erweiterung (`setsWonA/B` + `lastEventAt` gemeinsam), R15-F-10 als Conflict-UX-Sweep (Top-Banner + Sort + Status-abhängiges Tap-Routing), R15-F-05 + R15-F-06 + R15-F-07 + R15-F-15 als Realtime-Hygiene-Block (geteilter Provider + ref.listen statt map-side-effects + try/catch in watchMatch + onDispose-Cleanup) — adressiert auch R15-F-13 (Memoization), R15-F-14 als BackButton-Pattern-Sweep über alle Tournament-Screens (dritte Iteration), R15-F-16 + R15-F-17 + R15-F-18 + R15-F-19 + R15-F-20 als Polish-Wave parallel. R15-F-01 + R15-F-02 + R15-F-04 sind keine Hotfixes sondern Architect-Runden: M4.3 „Runden-Clock + Round-Management" (FR-LIVE-3..-9 in einem Sprint, gemeinsame `tournament_round`-Tabelle + RPC-Surface + Clock-Bar-Widget) und parallel „Tournament-Rollen-Modell" (organizer/helper/participant mit Riverpod-Family + Routing-Redirect + conditional UI). M4-Sign-off ist ohne R15-F-01 + R15-F-02 + R15-F-03 + R15-F-09 + R15-F-10 + R15-F-11 + R15-F-12 blockiert (acht von zehn FR-LIVE-MUSS-Anforderungen offen — nur FR-LIVE-1 teilweise und FR-LIVE-2 ansatzweise erfüllt). Re-Hit-Muster der Runde: dreifach BackButton-context.go-Pattern (R15-F-14 + R10-F-11 + R13-F-19), zweifach Pitch-Nummer-DB-vs-UI (R15-A-02 + R15-C-06), zweifach Conflict-UX (R15-C-02 + R15-C-09), zweifach Score-fehlt (R15-A-05 + R15-C-07), zweifach Farb-Mapping (R15-A-03 + R15-C-08), zweifach consensusRound-Label (R15-A-07 + R15-B-09), zweifach Empty-State (R15-A-08 + R15-C-10), zweifach Memoization-Rebuild (R15-B-04 + R15-B-05), zweifach Realtime-Lifecycle (R15-A-06 + R15-B-06), zweifach Layout (R15-A-09 + R15-B-08); Permission-Aware-Helper-Rolle (R15-F-04) ist Mehrfach-Re-Hit aus früheren Runden ohne dass die Architect-Entscheidung getroffen wurde.

### Runde 16 — Realtime-Connection

**Hunter-Output**: R16-A (12), R16-B (12), R16-C (10) → konsolidiert auf 16 Findings. Fokus: `lib/features/tournament/application/tournament_realtime_provider.dart`, `lib/features/tournament/data/realtime_connection_manager.dart` (oder vergleichbarer Connection-Layer), `lib/features/tournament/presentation/widgets/realtime_connection_banner.dart`, `tournamentRealtimeFallbackProvider`. Live-Update-Pfad: Schiedsrichter trägt Set ein → CDC-Event → andere Teilnehmer sehen Stand sofort, bei Hänger fällt App auf 60s-Polling zurück.

#### P0 — Blocker

- **R16-F-01**: Fallback-Signal ohne Konsument — `polling: true` wird produziert, aber nirgendwo gerendert
  - **Datei(en)**: `lib/features/tournament/application/tournament_realtime_provider.dart` (realtimeFallbackProvider), `lib/features/tournament/presentation/widgets/realtime_connection_banner.dart`
  - **Symptom**: Realtime-Channel hat `RealtimeSubscribeStatus.channelError` oder `closed`, Manager schaltet intern auf Polling um — User sieht aber kein Banner, kein „Verspätet"-Hinweis, kein „Verbindungsproblem". Match-Detail wirkt live, ist aber bis zu 60s stale. Schiedsrichter glaubt sein Eintrag sei durch, Zuschauer sehen alten Stand, niemand merkt's. Für ein laufendes Turnier ist das ein Vertrauensbruch — wer der App nicht traut, geht zurück auf Zettel + Stift.
  - **Root-Cause**: `realtimeFallbackProvider` (Producer) feuert `polling: true` als StreamEvent, aber kein einziger Widget-Konsument watched ihn. Banner-Widget hört nur auf `stateStream`, der nie ein „fallback"-Event trägt. Toter Brief.
  - **Fix**: Banner-Widget muss `realtimeFallbackProvider` zusätzlich konsumieren und bei `polling: true` ein „Live-Updates verspätet — Stand kann bis zu 60s alt sein"-Banner anzeigen (separate Farbe von „Verbindung verloren", da der User noch Daten bekommt, nur langsamer). Alternativ: Fallback-State in `stateStream` einfalten und Banner mit drei Stufen (verbunden / verbinde / verspätet) rendern.
  - **Hunter-Refs**: R16-C-02
  - **Verstärkung**: R14-F-Banner-Familie (Re-Hit, Banner-Lifecycle wurde in R14 schon mal angefasst, das Producer/Konsument-Pairing aber nie validiert)

- **R16-F-02**: `stateStream()` puffert keinen Initial-State — Banner kommt initial nie
  - **Datei(en)**: `lib/features/tournament/application/tournament_realtime_provider.dart` (stateStream-Methode), `lib/features/tournament/presentation/widgets/realtime_connection_banner.dart`
  - **Symptom**: User öffnet Match-Detail bevor Subscribe fertig ist. Erwartung: „verbinde…"-Banner. Realität: gar nichts. Erst wenn der erste Status-Wechsel passiert (subscribed/error/timed_out), zeigt das Banner irgendwas. Bei langsamer Verbindung sieht der User mehrere Sekunden eine scheinbar fertige UI, die in Wahrheit noch nicht live ist.
  - **Root-Cause**: `stateStream()` gibt ein `Stream.fromController` ohne ReplayBehavior zurück. Subscribe läuft asynchron — Widget abonniert nach erstem Frame, hat den initialen `subscribing`-State da längst verpasst. Klassisches Cold-Stream-Problem ohne Initial-Wert.
  - **Fix**: Entweder `BehaviorSubject` (über `rxdart`, schon im pubspec) oder `ValueNotifier`-basierter Stream; alternativ `stateStream` als `Stream<ConnectionState>` mit garantiertem `startWith(currentState)`. Banner-Widget muss bei Subscribe den aktuellen Sync-Wert lesen können.
  - **Hunter-Refs**: R16-A-01, R16-B-06

#### P1 — Hoch

- **R16-F-03**: Backoff-Off-by-One — 1s-Slot wird übersprungen, Reset ohne Stability-Window
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart` (Reconnect-Logik)
  - **Symptom**: Bei einem kurzen Netzwerk-Hänger (z.B. WLAN-Roaming am Turnierplatz) springt Backoff von 0 direkt auf 2s, dann 4s. Der natürliche „nochmal sofort"-Versuch fehlt. Bei flackernder Verbindung (subscribed → error → subscribed → error im Sekundentakt) wird Backoff bei jedem subscribed-Event auf 0 zurückgesetzt — kein Schutz vor Flapping, App brennt Reconnects pro Sekunde.
  - **Root-Cause**: Backoff-Folge ist als `[2, 4, 8, 16, 30]` statt `[1, 2, 4, 8, 16, 30]` codiert (off-by-one). Reset-Bedingung ist `status == subscribed` ohne Mindest-Stabilitätsfenster (z.B. „nach 5s stabil zurück auf 0").
  - **Fix**: Sequenz mit `1` beginnen lassen; Reset erst nach `Stability-Window` von z.B. 5s seit Subscribe ohne weiteren Status-Wechsel.
  - **Hunter-Refs**: R16-A-02, R16-B-03, R16-C-01 (Dreifach-Hit)

- **R16-F-04**: Polling-Fallback-Flag bleibt auf true hängen — nach Reconnect kein Zurückschalten
  - **Datei(en)**: `lib/features/tournament/application/tournament_realtime_provider.dart` (realtimeFallbackProvider), Realtime-Connection-Manager
  - **Symptom**: Realtime fällt auf Polling zurück (z.B. nach 3 Fehlversuchen), später kommt die Verbindung zurück — `polling: true` bleibt aber gesetzt. App pollt weiter alle 60s obwohl Realtime wieder läuft, doppelter Traffic, Updates kommen trotzdem nicht schneller weil das polling-Flag andere Code-Pfade dominiert.
  - **Root-Cause**: Fallback wird gesetzt aber nie zurückgenommen. Es fehlt der Pfad „Reconnect erfolgreich → fallback = false".
  - **Fix**: Bei erfolgreichem Subscribe (oder nach Stability-Window aus R16-F-03) `fallback = false` setzen und Polling-Timer canceln.
  - **Hunter-Refs**: R16-A-03

- **R16-F-05**: Race-Condition zwischen `close()` und `openOrAttach()`
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart`
  - **Symptom**: User wechselt schnell zwischen Match-Detail-Screens (Pitch 1 → Pitch 2 → Pitch 1). Alter Channel wird per `close()` heruntergefahren, neuer per `openOrAttach()` gestartet — beide Operationen laufen async und überlappen. Resultat: entweder zwei aktive Channels für dieselbe matchId (doppelte Events) oder ein halb-geschlossener Channel der nie mehr richtig subscribed.
  - **Root-Cause**: Keine Sequenzialisierung. `close()` returnt vor vollständigem teardown, `openOrAttach()` startet bevor das Cleanup durch ist. Kein `Mutex` / kein `Completer` der die Reihenfolge erzwingt.
  - **Fix**: `Future`-Chain mit einem internen `_pendingOperation`-Completer — neue Operationen warten bis die vorherige durch ist. Alternativ: synchroner State-Machine-Approach mit `isClosing`-Guard.
  - **Hunter-Refs**: R16-B-01

- **R16-F-06**: Switch über `RealtimeSubscribeStatus` ist nicht exhaustiv
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart`
  - **Symptom**: Supabase fügt einen neuen Enum-Wert hinzu (z.B. in einem Minor-Update), oder ein bestehender Status (`timed_out`, `channelError`) trifft den default-Pfad ohne explizite Behandlung. Connection-Manager macht im Zweifel nichts oder das Falsche — User stuck im „verbinde…"-Banner ohne dass Backoff je triggert.
  - **Root-Cause**: `switch` ohne `case` für alle Enum-Werte, kein `assert(false)` oder analyzer-strict-mode für exhaustive-switches im Domain-Package.
  - **Fix**: Alle fünf Werte explizit casen (`subscribed`, `closed`, `timedOut`, `channelError`, ggf. weitere). Bei unbekanntem Wert: defensiv Backoff triggern und loggen.
  - **Hunter-Refs**: R16-B-02

- **R16-F-07**: Zwei `on Object`-catches schlucken Exceptions
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart` (zwei Stellen)
  - **Symptom**: Reconnect schlägt wegen Auth-Token-Ablauf fehl, oder die Postgres-Replication-Slot ist überfüllt. Manager catched die Exception still, setzt aber den State nicht auf `error` — User sieht „verbunden" obwohl gar nichts mehr ankommt.
  - **Root-Cause**: `try { ... } on Object catch (_) { /* nichts */ }` zweimal. Klassisches Swallow-Pattern.
  - **Fix**: Klassifizieren: `RealtimeException` → State auf error + Backoff; `AuthException` → State auf needsReauth + UI-Hinweis; sonst rethrow oder zumindest loggen + State-Update. Niemals stumm.
  - **Hunter-Refs**: R16-B-04

- **R16-F-08**: `_disposeEntry` schliesst Controller nach `await`
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart`
  - **Symptom**: Bei schneller Navigation kann ein Listener nach Dispose noch einen Event erhalten, der gegen einen bereits geschlossenen Controller geschrieben wird — `Bad state: Cannot add new events after calling close()` taucht im Crashlytics auf.
  - **Root-Cause**: `await channel.unsubscribe()` läuft, _dann_ `controller.close()`. Während des Awaits können noch Events durchgereicht werden.
  - **Fix**: Erst `controller.close()` (oder ein `isDisposed`-Guard setzen), dann `await unsubscribe()`. Reihenfolge umdrehen.
  - **Hunter-Refs**: R16-B-05

- **R16-F-09**: Banner-Widget Dispose-Leak — Subscription wird nicht gecancelt
  - **Datei(en)**: `lib/features/tournament/presentation/widgets/realtime_connection_banner.dart`
  - **Symptom**: Banner-Widget wird per `pop` entfernt, behält aber seine `stateStream`-Subscription. Bei Rückkehr zum Screen läuft die alte Subscription parallel zur neuen, Listener-Count wächst pro Navigation. Längere Sessions enden im Memory-Bloat.
  - **Root-Cause**: `dispose()` cancelt den `StreamSubscription` nicht.
  - **Fix**: `_sub?.cancel()` in `dispose()`.
  - **Hunter-Refs**: R16-A-04, R16-B-07 (Re-Hit aus R14-Banner-Lifecycle)

- **R16-F-10**: Zwei unabhängige 60s-Timer driften auseinander
  - **Datei(en)**: `lib/features/tournament/presentation/widgets/realtime_connection_banner.dart`, `lib/features/tournament/application/tournament_realtime_provider.dart`
  - **Symptom**: Banner zeigt „verbinde noch X Sekunden", Polling-Provider feuert auf eigenem Timer — die beiden Timer wurden zu unterschiedlichen Zeitpunkten gestartet und sind nicht synchronisiert. Banner zählt auf null, aber Polling triggert erst 12s später. User-spürbar als „Banner verschwindet, dann passiert nichts".
  - **Root-Cause**: Zwei `Timer.periodic(Duration(seconds: 60), …)`-Instanzen, kein gemeinsamer Tick.
  - **Fix**: Ein zentraler Heartbeat-Provider, Banner und Polling-Logik konsumieren denselben Stream. Alternativ: Banner berechnet seine Anzeige aus dem letzten Polling-Event statt eigenem Timer.
  - **Hunter-Refs**: R16-C-03

#### P2 — Mittel

- **R16-F-11**: `didUpdateWidget` startet neuen Timer ohne den alten zu canceln
  - **Datei(en)**: `lib/features/tournament/presentation/widgets/realtime_connection_banner.dart`
  - **Symptom**: Banner-Widget wird mit neuer matchId neu-konfiguriert. Alter Timer läuft weiter, neuer kommt dazu. Listener-Wachstum analog R16-F-09.
  - **Root-Cause**: `didUpdateWidget` cancelt nicht.
  - **Fix**: `_timer?.cancel()` vor Reinit.
  - **Hunter-Refs**: R16-B-07

- **R16-F-12**: closed-Branch resettet `pendingFlip` nicht
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart`
  - **Symptom**: Channel wechselt auf `closed`, manuelle Status-Flip-Aktion (z.B. User-getriggerter Reconnect-Button) bleibt im `pendingFlip = true`-State hängen. Nächster Subscribe ignoriert den Flip weil Manager glaubt es laufe schon eine Operation.
  - **Root-Cause**: `closed`-Case setzt `pendingFlip` nicht zurück.
  - **Fix**: Im closed-Branch alle pending-Flags resetten.
  - **Hunter-Refs**: R16-B-08

- **R16-F-13**: `_scheduleReconnect` und `unsubscribe` racen
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart`
  - **Symptom**: Backoff-Timer feuert während gerade `unsubscribe()` läuft — Reconnect setzt auf einen Channel auf der gerade weggeräumt wird.
  - **Root-Cause**: Reconnect-Schedule prüft nicht ob ein Teardown in Flight ist.
  - **Fix**: Reconnect-Trigger guarden auf `isDisposing == false`. Bei gerade laufendem unsubscribe: Reconnect erst danach planen.
  - **Hunter-Refs**: R16-B-09

- **R16-F-14**: `debugTransitionTo` ist Test-only-Arg im Production-Code
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart`
  - **Symptom**: Im Production-Build lebt eine `debugTransitionTo`-Methode mit, die State-Übergänge erlauben würde, die der echte Flow nicht erlaubt. Sicherheits- und Sauberkeits-Geruch.
  - **Root-Cause**: Test-Hook nicht hinter `@visibleForTesting` oder `assert`-Guard.
  - **Fix**: `@visibleForTesting`-Annotation aus `package:meta` + Assertion dass nur in Debug-Mode aufrufbar. Oder Methode in ein test-only-Mixin auslagern.
  - **Hunter-Refs**: R16-B-10

#### P3 — Doku/Polish

- **R16-F-15**: Doppelte matchId-Filterung
  - **Datei(en)**: `lib/features/tournament/data/realtime_connection_manager.dart`
  - **Symptom**: matchId wird sowohl als Channel-Filter an Supabase übergeben als auch clientseitig in einem `.where`-Filter nochmal geprüft. Redundant, kein funktionaler Schaden, aber verwirrend beim Lesen.
  - **Fix**: Eine der beiden Filter-Stellen entfernen (bevorzugt: clientseitigen `.where` raus, Server-Filter bleibt).
  - **Hunter-Refs**: R16-B-11

- **R16-F-16**: `ref.invalidate` als Side-Effect in `stream.map`
  - **Datei(en)**: `lib/features/tournament/application/tournament_realtime_provider.dart`
  - **Symptom**: Side-Effect im Map-Callback — Frame-Race wie schon in R15-F-06 beschrieben, aber hier in den Connection-Providern.
  - **Fix**: `ref.listen` statt `ref.watch` für invalidation; Map bleibt pure.
  - **Hunter-Refs**: R16-B-12 (Re-Hit-Pattern aus R15-F-06)

**Rundenfazit**: Zwei P0-Findings dominieren — R16-F-01 ist der Kronjuwel: ein Producer ohne Konsument lässt User in einem stale-State ohne Warnung, was die Live-Glaubwürdigkeit der App im Turnier-Einsatz frontal angreift. R16-F-02 verstärkt das Problem im Initial-State (Banner kommt nie initial → User glaubt es sei live, bevor es das überhaupt ist). Acht P1-Findings ziehen sich quer durch den Connection-Manager: Backoff-Off-by-One (Dreifach-Hit aus drei Hunter-Outputs), Polling-Flag bleibt hängen, Race-Conditions zwischen close/open, non-exhaustive switches, swallowed exceptions, Dispose-Reihenfolge-Bug, Banner-Subscription-Leak, Timer-Drift. Für Sprint A heisst das: vor Live-Dashboard-Polish (M4) muss der Connection-Manager komplett überarbeitet werden — R16-F-01 bis R16-F-04 sind die Hotfix-Wave (Banner-Konsument + Initial-State + Backoff-Reihenfolge + Polling-Reset), R16-F-05 bis R16-F-10 als Connection-Manager-Refactor-Slice (Sequenzialisierung, exhaustive switch, Exception-Klassifikation, Dispose-Order, Banner-Lifecycle, Heartbeat-Konsolidierung). P2/P3 als Polish-Tail. Re-Hit-Patterns: Backoff dreifach (A+B+C), Banner-Lifecycle zweifach (R14 + R16), Side-Effect-in-map zweifach (R15 + R16).

### Runde 17 — Offline-Mode

**Hunter-Output**: R17-A (13, FAIL), R17-B (14, FAIL), R17-C (13, FAIL) → konsolidiert auf 24.

**Showstopper-Alarm**: Offline-Mode ist im aktuellen Stand strukturell kaputt. Outbox-Submitter ist ein `UnimplementedError`-Stub, Score-Drafts werden nicht persistiert, App-Restart triggert kein Flush. Solange R17-F-01 und R17-F-02 stehen, ist die App live-untauglich — Score-Eingabe am Pitch ohne Empfang funktioniert nicht.

#### P0 — Live-Blocker

- **R17-F-01**: `_RemoteScoreLamportSubmitter.submit` wirft `UnimplementedError`
  - **Datei**: `lib/core/application/outbox_flusher_provider.dart:113-135`
  - **Symptom**: Jeder offline-Score-Submit landet in der Outbox, Flusher zieht die Row, ruft den Submitter — und wirft. Server sieht den Score nie. Outbox-Row bleibt in `pending` ohne dass der User es merkt.
  - **Root-Cause**: Adapter wurde als Platzhalter eingecheckt, das echte RPC-Mapping fehlt. Die Lamport-Counter-Hydration und der `score_submit_with_lamport`-Call existieren, aber sind nie verdrahtet.
  - **Fix**: Submitter implementieren — Lamport-Counter aus dem hydratisierten Clock-Provider lesen, `score_submit_with_lamport` mit `(matchId, setIndex, participantA, participantB, lamport, clientIdempotencyKey)` aufrufen, Conflict-Codes durch (ohne `runtimeType.toString()`).
  - **Hunter-Refs**: R17-A-01, R17-B-05, R17-C-02

- **R17-F-02**: Score-Drafts werden nie persistiert (FR-DSCORE-19..22)
  - **Datei**: `lib/features/tournament/presentation/match_detail_screen.dart`, `lib/features/tournament/application/score_draft_controller.dart`
  - **Symptom**: Spieler tippt am Pitch Set-Scores in das Match-Detail, App wird gekillt (Akku leer, Force-Close, Screen-Lock + OS-Reap), beim Wiederöffnen sind die Eingaben weg. Drafts sind ausschliesslich `setState`-State im Widget.
  - **Root-Cause**: Drift-Tabelle `tournament_score_drafts` existiert (Commit 9513b95), wird aber von keinem Controller geschrieben oder gelesen. Der Setup-Wizard-Draft nutzt sie, der Match-Score-Draft nicht.
  - **Fix**: ScoreDraft-Repository auf Drift draufsetzen, Match-Detail-Controller schreibt bei jedem Wert-Change einen Upsert, beim Screen-Open wird der Draft hydratisiert. GC-Pfad: Draft löschen wenn Match `finished` oder Submit acknowledged.
  - **Hunter-Refs**: R17-C-03

#### P1 — Hoch

- **R17-F-03**: Bootstrap triggert kein `flushPending` beim App-Start
  - **Datei**: `lib/core/application/bootstrap.dart`, `lib/core/application/outbox_flusher_provider.dart`
  - **Symptom**: User submittet offline, schliesst die App, startet sie später online wieder — Outbox bleibt liegen bis der nächste Connectivity-Wechsel kommt. Bei stabiler Verbindung passiert das nie.
  - **Root-Cause**: Flusher wird nur via Connectivity-Stream getriggert, nicht beim Cold-Start.
  - **Fix**: Bootstrap ruft nach Auth-Hydration einmal `flushPending(reason: 'cold-start')`. Idempotent durch Re-Entrancy-Guard (siehe R17-F-09).
  - **Hunter-Refs**: R17-A-03, R17-C-01

- **R17-F-04**: Connectivity-Service startet optimistisch online
  - **Datei**: `lib/core/data/real_connectivity_service.dart`
  - **Symptom**: Direkt nach App-Start emittiert der Stream `online`, bevor die erste echte Probe lief. Der Flusher legt los, scheitert am Netz, markiert Attempts. Bei tatsächlich Offline wird unnötig retried.
  - **Root-Cause**: Initial-State ist hardcoded `online`, kein Replay-on-subscribe der letzten Probe.
  - **Fix**: Initial-State auf `unknown` setzen, erst nach erster Probe einen echten Status emittieren. Stream als `BehaviorSubject` mit Replay 1.
  - **Hunter-Refs**: R17-A-02, R17-B-06

- **R17-F-05**: `proposeSetScores` nicht atomar
  - **Datei**: `lib/features/tournament/data/tournament_repository.dart` (oder äquivalent in Application-Layer)
  - **Symptom**: Bei 3-Sets-Match werden 3 Outbox-Rows nacheinander inserted. Wenn der Prozess zwischen Row 2 und 3 stirbt, hat die Outbox einen halben Match-Submit. Beim Flush gehen 2 von 3 Sets durch, der Server sieht ein inkonsistentes Bild bis der User den Match nochmal anfasst.
  - **Root-Cause**: Loop ohne Drift-Transaction.
  - **Fix**: `db.transaction { ... }` um die 3 Inserts. Entweder alle Rows landen in der Outbox oder keine.
  - **Hunter-Refs**: R17-A-07, R17-B-02

- **R17-F-06**: Non-SocketException-Errors werden rethrown ohne `markError`
  - **Datei**: `lib/core/application/outbox_flusher_provider.dart`
  - **Symptom**: Submitter wirft z.B. `FormatException` (corrupt RPC-Response) oder `AuthException` (Token expired). Catch fängt nur `SocketException`, alles andere fällt durch. Outbox-Row bleibt forever `pending`, kein User-Hinweis.
  - **Root-Cause**: Zu enges Catch.
  - **Fix**: Drei Buckets — transient (SocketException, TimeoutException) → `markAttempt`, terminal (FormatException, AuthException, 4xx-Conflict ausser bekannte Codes) → `markError`, sonst Bubble-Up + Crash-Reporting. Bei `markError` UI-Notification triggern.
  - **Hunter-Refs**: R17-A-05

- **R17-F-07**: Submit-Refresh-Pfad zeigt Offline-Fehler trotz erfolgreichem Outbox-Insert
  - **Datei**: `lib/features/tournament/presentation/match_detail_screen.dart`
  - **Symptom**: User tippt offline auf "Speichern", Outbox-Insert klappt, aber das anschliessende `refresh` des Match-Providers schlägt fehl (kein Netz) und zeigt eine rote Fehler-Snackbar. User glaubt der Submit sei verloren.
  - **Root-Cause**: Refresh wird auch dann versucht wenn klar ist dass offline. Fehler des Refresh wird der Submit-Aktion zugeschrieben.
  - **Fix**: Bei `pending`-Outbox-Insert nur eine "in Warteschlange"-Snackbar zeigen, Refresh nur dann triggern wenn online. Bei Refresh-Fail nicht als Submit-Fehler präsentieren.
  - **Hunter-Refs**: R17-A-04

- **R17-F-08**: Override-Conflict wird vom Client nicht als terminal erkannt
  - **Datei**: `lib/core/application/outbox_flusher_provider.dart`, RPC-Conflict-Mapping
  - **Symptom**: Server gibt `conflict_override_pending` zurück (Organizer-Override aktiv), Client behandelt das als transient und retried ewig. DSCORE-100 verletzt.
  - **Root-Cause**: Conflict-Code-Klassifikation kennt `override_pending` nicht als terminal.
  - **Fix**: Override-Codes als terminal markieren, `markError(reason: 'override_pending')`, UI zeigt expliziten Hinweis "warte auf Organizer-Override".
  - **Hunter-Refs**: R17-C-06

- **R17-F-09**: Re-Entrancy-Guard und Backoff-Delay racen
  - **Datei**: `lib/core/application/outbox_flusher_provider.dart`
  - **Symptom**: Während `flushPending` läuft und auf Backoff-Delay wartet, kommt ein neuer Connectivity-Event und startet einen zweiten Flush. Beide ziehen sich überlappende Rows.
  - **Root-Cause**: Guard wird nach dem await released, nicht über die ganze Backoff-Dauer.
  - **Fix**: Guard umspannt die komplette Loop inkl. Delays. Doppel-Trigger werden ignoriert.
  - **Hunter-Refs**: R17-B-03

- **R17-F-10**: `markAcknowledged`/`markError` nicht atomar mit `pending()` — keine Lease
  - **Datei**: `lib/core/data/outbox_dao.dart`
  - **Symptom**: Zwei Flusher-Instanzen (z.B. nach Hot-Reload-Leak aus R17-F-13) ziehen dieselbe Row, beide submitten, doppelter Server-Call.
  - **Root-Cause**: `pending()` liefert die Row ohne sie für andere zu sperren. Acknowledgement kommt später ohne Transaction-Bracket.
  - **Fix**: Lease-Spalte einführen (`leased_until`, `lease_owner`), `pending()` mit `UPDATE … RETURNING` atomar leasen. Lease-Timeout für Crash-Recovery.
  - **Hunter-Refs**: R17-B-09

- **R17-F-11**: Auth-Token-Expiry-Pfad nicht behandelt
  - **Datei**: `lib/core/application/outbox_flusher_provider.dart`
  - **Symptom**: Token läuft ab während der User offline ist. Reconnect, Flush versucht zu submitten, RPC liefert 401, Flusher hat keinen Refresh-Pfad. Rows hängen.
  - **Root-Cause**: Auth-Refresh läuft nicht im Flush-Path.
  - **Fix**: Auf 401 → Token-Refresh erzwingen, dann ein Retry. Wenn Refresh fehlschlägt → `markError(auth_expired)`, UI zeigt Re-Login-Banner.
  - **Hunter-Refs**: R17-A-09

- **R17-F-12**: Type-Confusion `UserId` vs `TournamentParticipantId`
  - **Datei**: `lib/features/tournament/data/tournament_remote.dart`, Outbox-Port
  - **Symptom**: Outbox-Row trägt `UserId` als `participant`-Feld, der RPC erwartet `TournamentParticipantId`. Bei Mehrfach-Turnier-Teilnahme oder Team-Modus matcht nichts.
  - **Root-Cause**: Port-Signatur lose typisiert, beide Felder als `String`.
  - **Fix**: Sealed Value Objects einführen oder explizit `participantA/participantB: TournamentParticipantId`. Compile-Error statt Runtime-Mismatch.
  - **Hunter-Refs**: R17-B-01

- **R17-F-13**: `outboxFlusherProvider` ohne `autoDispose` — Hot-Reload-Leak
  - **Datei**: `lib/core/application/outbox_flusher_provider.dart`
  - **Symptom**: Im Dev jeder Hot-Reload erzeugt eine neue Flusher-Instanz, alte läuft weiter. Beide ziehen aus derselben Outbox. In Production verlorenes Subscription-Lifetime-Tracking.
  - **Root-Cause**: Provider als `Provider` statt `Provider.autoDispose`, kein `keepAlive`-Plan.
  - **Fix**: Klar definieren — wenn Singleton gewollt → explizit `keepAlive`. Wenn nicht → `autoDispose` mit Re-Bootstrap-Trigger.
  - **Hunter-Refs**: R17-B-07

- **R17-F-14**: `outboxPendingProvider` als `autoDispose.family` — kein globaler Pending-Indikator
  - **Datei**: `lib/core/application/outbox_pending_provider.dart`
  - **Symptom**: Pending-Count ist immer per-match scoped. Es gibt keine globale "X ausstehende Submits"-Anzeige in der App-Bar oder im Home-Screen.
  - **Root-Cause**: Family-Provider designed für lokalen Use, kein App-weiter Aggregator.
  - **Fix**: Zusätzlich `outboxTotalPendingProvider` ohne family, keepAlive, App-Bar-Badge konsumiert ihn.
  - **Hunter-Refs**: R17-A-08

- **R17-F-15**: `OutboxFlushStatus`-Stream nirgendwo in UI konsumiert (DSCORE-97/104) — Verstärkung R16-F-01
  - **Datei**: `lib/core/application/outbox_flusher_provider.dart` (Producer), keine Konsumenten
  - **Symptom**: Flusher emittiert Status-Events (`flushing`, `idle`, `error`), aber keine Snackbar, kein Banner, kein Badge konsumiert sie. Spiegelt das Pattern aus Runde 16 (Realtime-Status ohne Konsument).
  - **Root-Cause**: Producer wurde verdrahtet, UI-Konsument vergessen.
  - **Fix**: Globalen Status-Banner-Widget (analog zum Realtime-Banner) auf den Stream subscriben. Bei `error` Tap-to-Retry-Button, bei `flushing` Spinner, bei `idle` versteckt.
  - **Hunter-Refs**: R17-C-07 (Re-Hit R16-F-01)

#### P2 — Mittel

- **R17-F-16**: GC löscht nur acknowledgte Rows, `errored` bleiben ewig
  - **Datei**: `lib/core/data/outbox_dao.dart`, GC-Job
  - **Symptom**: Errored-Rows sammeln sich monatelang in der lokalen DB, DB wird langsam.
  - **Fix**: GC auch für `errored`-Rows älter als 30 Tage. Vorher Logging-Hook für Debug-Export.
  - **Hunter-Refs**: R17-A-11

- **R17-F-17**: `markAttempt` ist No-Op
  - **Datei**: `lib/core/data/outbox_dao.dart`
  - **Symptom**: Attempt-Counter wird nie hochgezählt, Backoff-Berechnung läuft immer mit `attempts=0`. Retry-Schedule kollabiert auf konstantes Sofort-Retry.
  - **Fix**: `attempts += 1` + `lastAttemptAt = now` in einem Update.
  - **Hunter-Refs**: R17-A-12, R17-B-12

- **R17-F-18**: Off-by-one Retry-Schedule (5 Versuche statt 4)
  - **Datei**: `lib/core/application/outbox_flusher_provider.dart`
  - **Symptom**: Spec sagt 4 Retries dann `errored`, Code macht 5.
  - **Fix**: `if (attempts >= 4) → markError`.
  - **Hunter-Refs**: R17-B-08

- **R17-F-19**: WLAN-without-Internet false-positive
  - **Datei**: `lib/core/data/real_connectivity_service.dart`
  - **Symptom**: Captive-Portal-WLAN auf der Turnierwiese: `connectivity_plus` sagt online, echter Reach-Probe schlägt fehl. Flusher feuert ins Leere.
  - **Fix**: Connectivity-Service macht zusätzlich HEAD-Probe auf Supabase-Endpoint bevor `online` emittiert wird.
  - **Hunter-Refs**: R17-A-10

- **R17-F-20**: Lamport-Hydration übersieht GC'te Counter
  - **Datei**: `lib/core/data/lamport_clock_dao.dart`
  - **Symptom**: Nach GC einer alten Outbox-Row ist der Lamport-Counter für das Match aus der Hydration weg. Nächster Submit startet bei 0, Server lehnt mit `lamport_regression` ab.
  - **Fix**: Lamport-Counter separat persistieren (nicht aus der Outbox abgeleitet), eigene Tabelle mit `(matchId, lastLamport)`.
  - **Hunter-Refs**: R17-A-13

- **R17-F-21**: Score-Drafts haben keine GC
  - **Datei**: `lib/features/tournament/data/...`
  - **Symptom**: Drafts für abgeschlossene Matches sammeln sich.
  - **Fix**: Beim Match-`finished`-Status oder beim Outbox-Acknowledge den Draft löschen. Periodischer GC für verwaiste Drafts > 7 Tage.
  - **Hunter-Refs**: R17-A-06

- **R17-F-22**: `LamportClock.observeFromStream` cancel nicht awaited
  - **Datei**: `lib/core/application/lamport_clock_provider.dart`
  - **Symptom**: Subscription-Leak bei Provider-Dispose. Mehrere Streams können sich überlagern.
  - **Fix**: Subscription explizit halten, im Dispose `await subscription.cancel()`.
  - **Hunter-Refs**: R17-B-11

- **R17-F-23**: `LamportClock.observeFromStream` verletzt ADR-0006 (`+1` fehlt)
  - **Datei**: `lib/core/application/lamport_clock_provider.dart`
  - **Symptom**: Beim Receive setzt der Clock `max(local, remote)` ohne `+1`. ADR-0006 fordert `local = max(local, remote) + 1`. Bei Tie kollidieren spätere Lamport-Werte.
  - **Fix**: `+1` ergänzen, Property-Test in `kubb_domain` als Regression-Pin.
  - **Hunter-Refs**: R17-C-04

- **R17-F-24**: ADR-0007 Disagreement-State-Machine nicht implementiert (3-Versuche-Cap, 20s-Undo, Stuck-State)
  - **Datei**: `lib/features/tournament/application/match_score_controller.dart`
  - **Symptom**: Score-Conflict-Handling ist nicht spec-konform. Kein 20s-Undo-Fenster, kein Stuck-State nach 3 fehlgeschlagenen Consensus-Versuchen — Override muss manuell vom Organizer angefasst werden ohne dass die UI ihn dazu drängt.
  - **Fix**: State-Machine in der Domain implementieren (`Proposed → Disagreed → Resolved | Stuck`), UI führt durch.
  - **Hunter-Refs**: R17-C-08

#### P3 — Doku/Polish

- **R17-F-25**: Schema-Drift, Idempotenz-Index, Conflict-Code, Doku-Drift
  - **Datei**: `supabase/migrations/...`, `lib/core/application/outbox_flusher_provider.dart`, `docs/adr/0022-*.md`
  - **Sammelposten**: Server-Idempotenz-Index NULL-Predikat weicht von ADR-0022 §2 ab (R17-C-05); Outbox-Schema fehlen UUIDv7-PK und `firstAttemptAt` (R17-C-09); UNIQUE-Index blockiert legitime Re-Submission nach Conflict (R17-C-10); `client_idempotency_key` nicht explizit (R17-C-11, DSCORE-101); MatchFinished-Late-Submission-Policy fehlt in der Migration (R17-C-12); ADR-0022 doc-drift gegenüber Implementation (R17-C-13); `_conflictCode` via `runtimeType.toString()` (Web-Minification-Risiko, R17-B-13); `insert()` Row-ID ignoriert, kosmetisch (R17-B-14).
  - **Fix**: Eigene Cleanup-Iteration nach M4-Sprint-A. Pro Punkt ein Mini-Task.
  - **Hunter-Refs**: R17-C-05, R17-C-09, R17-C-10, R17-C-11, R17-C-12, R17-C-13, R17-B-13, R17-B-14

**Rundenfazit**: Offline ist Sprint-A-Showstopper. Solange R17-F-01 (UnimplementedError-Killer) und R17-F-02 (Drafts nicht persistiert) stehen, kann kein Spieler am Pitch eine offline gestartete Score-Eingabe zuverlässig durchbringen. Sprint A muss mit diesen zwei P0-Findings öffnen, danach R17-F-03 bis R17-F-15 als Hardening-Slice. R17-F-15 zeigt zum zweiten Mal in dieser Sweep das toter-Brief-Pattern (Producer ohne Konsument) — wenn das nicht systematisch geprüft wird, kommt es ein drittes Mal. P2/P3 als Polish-Tail nach M4-Hauptarbeit. Re-Hit-Patterns: UnimplementedError dreifach (A+B+C), proposeSetScores-Atomarität zweifach (A+B), markAttempt-No-Op zweifach (A+B), Connectivity-Optimismus zweifach (A+B), Status-Stream-ohne-Konsument zweifach (R16 + R17).

### Runde 18 — Settings + Stats-Tabs

**Hunter-Output**: R18-A (13, FAIL), R18-B (14, FAIL), R18-C (12, FAIL) → konsolidiert auf 25.

**Compliance-Alarm**: Privacy-Text in Settings behauptet "Alle Daten bleiben lokal", obwohl Supabase aktiv ist. Zusammen mit der fehlenden Datenschutzerklärung und dem nicht durchgreifenden Account-Delete ist das ein klarer Public-Launch-Blocker. Diese drei Punkte müssen in Sprint C (Launch-Vorbereitung) hängen, bevor irgendein Marketing-Schritt passiert.

#### P0 — Compliance/Datenintegrität (Sprint C — Launch-Blocker)

- **R18-F-01**: Privacy-Text lügt — "Alle Daten bleiben lokal" trotz Supabase-Sync
  - **Datei**: `lib/features/settings/presentation/settings_screen.dart`, ARB-Keys `settingsPrivacy*`
  - **Symptom**: Settings → Datenschutz-Sektion zeigt einen Text, der suggeriert, dass alles lokal bleibt. Tatsächlich werden Matches, Tournaments, Friends, Inbox über Supabase synchronisiert. Vor Public-Launch ist das ein Compliance-Risiko (irreführende Information, Art. 5 DSGVO Treu und Glauben).
  - **Fix**: Text auf die Realität ziehen — was lokal bleibt (Training-Sessions, lokale Drafts) vs. was synchronisiert wird (Matches, Tournaments, Friends), mit Link zur (noch zu schreibenden) Datenschutzerklärung.
  - **Hunter-Refs**: R18-C-01

- **R18-F-02**: Keine Datenschutzerklärung, kein Impressum
  - **Datei**: Settings App-Sektion, fehlende Routen `/legal/privacy`, `/legal/imprint`
  - **Symptom**: DSGVO Art. 13/14 fordern Informationspflichten bei Datenerhebung. App hat keine erreichbare Datenschutzerklärung und kein Impressum. Für Phase 1 Closed-Beta toleriert, für jeden Public-Launch (Store, Web-Hosting) zwingend.
  - **Fix**: Zwei statische Seiten unter `lib/features/legal/`, in Settings App-Sektion verlinkt. Inhalt durch Owner / juristischen Quick-Check vorbereiten. Eigener Sprint-C-Task.
  - **Hunter-Refs**: R18-C-02

- **R18-F-03**: Account-Delete lässt lokale drift-DB stehen
  - **Datei**: `lib/features/auth/application/account_delete_controller.dart` (oder äquivalent), drift-DB-Wipe-Pfad
  - **Symptom**: Account-Löschung räumt Supabase-Daten ab, aber die lokale drift-DB (Matches, Sessions, Drafts, Inbox-Cache) bleibt unangetastet. GDPR Art. 17 Recht auf Löschung gilt auch für lokal persistierte Daten unter Kontrolle des Verantwortlichen. Nach Re-Login mit anderem Account sieht der User ggf. Reste.
  - **Fix**: Account-Delete-Flow wipet `AppDatabase` komplett (alle Tabellen truncaten oder DB-File löschen + neu öffnen). Bestätigungs-Dialog mit explizitem Hinweis, dass auch alle lokalen Trainings-Sessions gelöscht werden. Property-Test: nach Delete sind alle DAO-Aggregat-Reads leer.
  - **Hunter-Refs**: R18-A-01

- **R18-F-04**: Finisseur-Success-Logik divergiert zwischen CSV-Export und Stats-Repo
  - **Datei**: `lib/features/training/data/csv_export_notifier.dart`, `lib/features/stats/data/stats_repository.dart` (Finisseur-Aggregat)
  - **Symptom**: Im CSV-Export wird `kingHit` pro Attempt einer Finisseur-Lage neu gesetzt — der letzte Stick überschreibt frühere. Die Stats-Logik definiert Erfolg anders (mindestens ein Königstreffer oder Base-Logik). Resultat: Stats und exportierte CSV widersprechen sich, der User vertraut den Zahlen nicht mehr.
  - **Fix**: Eine geteilte `FinisseurAttempt.isSuccess`-Funktion im `kubb_domain`-Package, von beiden Pfaden konsumiert. Open Question (B-10): wie wird `base==0` gewertet — eigenes Property-Test-Setup, Owner-Domain-Entscheidung via `/kubb-knowledge`.
  - **Hunter-Refs**: R18-B-03, R18-B-10

- **R18-F-05**: FR-SOCIAL-4 — Match-Stats-Tab ignoriert Friends-only-Sichtbarkeit (Re-Hit aus OD-03)
  - **Datei**: `lib/features/stats/presentation/match_stats_tab.dart`, Match-Filter-Pfad
  - **Symptom**: Match-Stats-Tab zeigt Match-Aggregate ohne Filter auf Friends-only-Sichtbarkeit. Spec FR-SOCIAL-4 fordert, dass Solo-Match-Statistiken nur für Friends sichtbar sind, wenn der User das so eingestellt hat. Bekannt aus OD-03 (siehe frühere Runde) und immer noch offen.
  - **Fix**: Stats-Query filtert auf `viewerPlayerId ∈ {match.playerA, match.playerB, friendsOf(match.players)}`. Test mit synthetischen Fixtures: Observer ohne Friend-Beziehung sieht nichts.
  - **Hunter-Refs**: R18-C-03 (vgl. OD-03)

#### P1 — Hoch

- **R18-F-06**: `matchStatsProvider` wird nach Match-Finalize nie invalidiert
  - **Datei**: `lib/features/stats/application/match_stats_provider.dart`, Match-Finalize-Callback in `lib/features/match/application/`
  - **Symptom**: Nach Match-Ende refresht das Match-Stats-Aggregat nicht. User sieht alte Zahlen, bis er manuell die App neu startet oder den Tab wechselt (und auch dann nur, wenn der Provider autoDispose ist).
  - **Fix**: Match-Finalize-Notifier ruft `ref.invalidate(matchStatsProvider)` (und alle abgeleiteten Aggregat-Provider). Wenn der Provider `.family` über Filter ist, alle Familie-Instanzen invalidieren.
  - **Hunter-Refs**: R18-A-02

- **R18-F-07**: `resetSessions` invalidiert keine Provider — Geisterdaten in der UI
  - **Datei**: `lib/features/settings/application/reset_sessions_controller.dart`, `lib/features/settings/presentation/settings_screen.dart`
  - **Symptom**: Settings → "Sessions zurücksetzen" leert die drift-Tabelle, aber `sniperStatsProvider`/`finisseurStatsProvider`/`csvExportNotifier` bleiben auf alten Werten. UI zeigt Daten, die in der DB nicht mehr existieren. Zusätzlich fehlt der try/catch — Fehler im Reset werden geschluckt (B-14).
  - **Fix**: Nach erfolgreichem Reset alle Stats- und Export-Provider invalidieren (`ref.invalidate(...)` für jeden betroffenen Provider). Try/catch um die Reset-Operation mit User-feedback bei Fehler.
  - **Hunter-Refs**: R18-A-03, R18-B-04, R18-B-14

- **R18-F-08**: CSV-Export-Notifier `trigger()` Race Condition + fehlender mounted-Check
  - **Datei**: `lib/features/training/data/csv_export_notifier.dart`, Callsite in Stats-Tabs
  - **Symptom**: `trigger()` arbeitet mit `state` als `prev`, schreibt den Result-State zurück. Wenn der User zweimal kurz hintereinander triggert, läuft Run 2 mit dem `prev` von Run 1, der noch nicht abgeschlossen war. Result-Order wird vertauscht. Zusätzlich `ref.read(notifier)` direkt in `build` und nach Await kein mounted-Check.
  - **Fix**: Notifier serialisiert die Aufrufe (entweder via `Completer`-Queue oder simple "ignore if already running"-Flag). `mounted`-Check nach `await trigger()`. `ref.read(notifier)` aus `build` raus, in Event-Handler verschieben.
  - **Hunter-Refs**: R18-B-01, R18-B-11

- **R18-F-09**: Filter-Modal `setFilter` race — out-of-order count-Updates
  - **Datei**: `lib/features/stats/presentation/stats_filter_modal.dart`, Filter-Notifier
  - **Symptom**: Filter-Modal triggert mit jedem Tap einen Count-Refresh. Schnelles Tippen → Count von Filter-Set 1 kommt zurück, nachdem Filter-Set 2 schon aktiv ist. UI zeigt falsche Zahl.
  - **Fix**: Request-ID pro Setzung, Result nur akzeptieren, wenn die ID noch aktuell ist. Alternativ Debounce auf den Count-Trigger (200ms).
  - **Hunter-Refs**: R18-B-02

- **R18-F-10**: `callerOutcome` liefert `'tie'` für Observer ohne Team (String mit silent default)
  - **Datei**: `lib/features/stats/data/stats_repository.dart`, `callerOutcome`-Helper
  - **Symptom**: Wenn der Aggregat-Pfad einen Match-Datensatz mit Observer-Rolle (kein Team-Member) bewertet, fällt der Code in den `default`-Case und gibt `'tie'` zurück. Das ist sachlich falsch — der Observer hat keinen Outcome. Stats werden für Observer-Matches positiv-verzerrt.
  - **Fix**: `callerOutcome` als `enum CallerOutcome { win, loss, tie, notInvolved }` mit explizitem `notInvolved`-Wert. Aggregat ignoriert `notInvolved`-Records. Test mit Observer-Match-Fixtures.
  - **Hunter-Refs**: R18-A-06, R18-B-09

- **R18-F-11**: Hartcodierte Strings statt `AppLocalizations`
  - **Datei**: `lib/features/settings/presentation/settings_screen.dart`, Inbox-Sektion ("Postfach", "Nachrichten und Bestätigungs-Anfragen")
  - **Symptom**: Beim späteren `en`-Locale-Add bleiben diese Strings deutsch. Verstösst gegen das Phase-1-Prinzip "alle UI-Strings über `AppLocalizations`".
  - **Fix**: ARB-Keys ergänzen, Strings ziehen.
  - **Hunter-Refs**: R18-A-04

- **R18-F-12**: Sprache als statischer Text, kein Picker
  - **Datei**: `lib/features/settings/presentation/settings_screen.dart`
  - **Symptom**: Settings zeigt "Sprache: Deutsch" als statische Row. Suggeriert Picker, hat aber kein Verhalten. Solange Phase 1 nur `de` liefert: entweder Row entfernen oder als "weitere Sprachen in Vorbereitung" markieren.
  - **Fix**: Row entfernen, bis Locale-Switch wirklich implementierbar ist (Story für Phase-1-Polish oder M5+).
  - **Hunter-Refs**: R18-A-12, R18-C-05

#### P2 — Mittel

- **R18-F-13**: Date-Range "letzte 7 Tage" off-by-one (Rolling-168h statt 7 Kalendertage), UTC-vs-Lokal-Mismatch
  - **Datei**: `lib/features/stats/data/stats_repository.dart` (Date-Range-Helper), `_maxThrowsPerDay`-Bucket
  - **Symptom**: Filter "letzte 7 Tage" rechnet `now - Duration(days: 7)`, also rollendes 168h-Fenster. User erwartet "die letzten 7 Kalendertage inkl. heute". Zusätzlich verwendet `_maxThrowsPerDay` UTC-Buckets, was zur lokalen Mitternacht zu Sprüngen führt.
  - **Fix**: Range auf `startOfDay(now) - Duration(days: 6)` bis `endOfDay(now)` in lokaler TZ. Bucket-Berechnung konsistent in lokaler TZ. Property-Test mit Wurf knapp vor Mitternacht.
  - **Hunter-Refs**: R18-A-09, R18-B-05, R18-B-06

- **R18-F-14**: Empty-States — Mängel-#1 verstärkt (Texte ohne visuelle Differenzierung, Finisseur zeigt Sniper-Texte)
  - **Datei**: `lib/features/stats/presentation/sniper_stats_tab.dart`, `finisseur_stats_tab.dart`, `match_stats_tab.dart`
  - **Symptom**: Mängel-Liste #1 in einer früheren Runde hatte Empty-States als zu spartanisch markiert. Bestätigt: nur Text, keine Illustration, keine Call-to-Action. Zusätzlich zeigt Finisseur-Tab im leeren Zustand Sniper-spezifische Texte (Copy-Paste-Bug).
  - **Fix**: Pro Tab eigener Empty-State (Icon + Modus-spezifischer Text + Button "Erste Session starten"). Konsistent mit den Modus-Cards im Training-Bottom-Sheet.
  - **Hunter-Refs**: R18-A-11, R18-C-04 (Re-Hit Mängel-#1)

- **R18-F-15**: Kein Pull-to-Refresh auf Stats-Tabs
  - **Datei**: alle drei Stats-Tabs
  - **Symptom**: Standard-Mobile-UX-Pattern fehlt. User-Discoverability für Refresh ist null.
  - **Fix**: `RefreshIndicator` um die Tab-ListView. `onRefresh` invalidiert die Aggregat-Provider.
  - **Hunter-Refs**: R18-A-07

- **R18-F-16**: Match-Tab kein Filter (Filter-Icon verschwindet), Filter-State bleibt aktiv
  - **Datei**: `lib/features/stats/presentation/stats_screen.dart` (AppBar-Actions), Match-Tab
  - **Symptom**: Auf Match-Tab fehlt der Filter-Icon, aber wenn vorher auf Sniper/Finisseur ein Filter gesetzt war, bleibt der State aktiv. Inkonsistent mit der visuellen Erwartung.
  - **Fix**: Entweder Filter-Icon auch auf Match-Tab anbieten (mit angepasstem Filter-Set) oder beim Tab-Wechsel zu Match den Filter-State neutralisieren. Spec-Frage an PO/Owner.
  - **Hunter-Refs**: R18-A-10, R18-C-10

- **R18-F-17**: N+1 Reads in `computeAggregate`, Aggregat-Provider nicht autoDispose
  - **Datei**: `lib/features/stats/application/stats_aggregate_providers.dart`, `stats_repository.dart`
  - **Symptom**: Aggregat-Berechnung lädt sessions sequentiell statt batched (`for (id in ids) await read(id)`). Bei vielen Sessions spürbarer Lag. Zusätzlich bleiben Aggregat-Provider nach Tab-Wechsel im Speicher (kein `autoDispose`).
  - **Fix**: Batch-Read im DAO (`readMany(ids)`). Aggregat-Provider mit `autoDispose` (und `keepAlive`-Marker nur, wenn explizit gewünscht). Performance-Budget-Test mit 200 Sessions.
  - **Hunter-Refs**: R18-B-07, R18-B-08

- **R18-F-18**: Sniper-Distanz-Filter hardcoded 4–8m
  - **Datei**: `lib/features/stats/presentation/stats_filter_modal.dart`
  - **Symptom**: Filter-Modal listet 4/5/6/7/8m als feste Chips. Sobald die 4m-Linie als eigener Trainings-Modus (per Memory: TODO M5+) live geht, bricht die Filter-Logik (oder verdeckt neue Distanzen).
  - **Fix**: Distanz-Liste aus Domain-Konstante (`SniperDistance.all`) statt Magic-Numbers. Filter-Modal iteriert die Konstante.
  - **Hunter-Refs**: R18-A-08

- **R18-F-19**: `bestHitRate` ignoriert Session-Grösse
  - **Datei**: `lib/features/stats/data/stats_repository.dart` (Best-Hit-Rate-Aggregat)
  - **Symptom**: "Beste Trefferquote"-Statistik nimmt das Maximum über alle Sessions, ohne Mindest-Würfe-Schwelle. Eine 3-aus-3-Session wird als "100% beste Quote" gefeiert, eine 47-aus-50-Session bleibt unsichtbar.
  - **Fix**: Minimum-Throws-Threshold (z.B. 20 oder Hälfte des Session-Ziels). Konfigurierbar oder als Property der Session-Definition. Test mit Mix kleiner/grosser Sessions.
  - **Hunter-Refs**: R18-A-13

- **R18-F-20**: Match-Stats vs. Tournament-Match-Korrelation nicht erklärt
  - **Datei**: `lib/features/stats/presentation/match_stats_tab.dart`, Helper-Text
  - **Symptom**: Match-Tab aggregiert Solo-Matches und Tournament-Matches gemischt. User versteht nicht, was reinzählt. UX-Klarheit fehlt.
  - **Fix**: Header-Text klärt Scope. Optional Filter "Solo-Match / Tournament-Match / beide". Owner-Entscheidung via PO.
  - **Hunter-Refs**: R18-A-05

- **R18-F-21**: `stats_filter_modal` Draft-Leak bei Rotation
  - **Datei**: `lib/features/stats/presentation/stats_filter_modal.dart`
  - **Symptom**: Bei Device-Rotation während Filter offen wird der Draft-State im Notifier nicht resettet. Bei Re-Open sieht der User den alten Draft.
  - **Fix**: Modal-Open ruft `notifier.resetDraft()` (oder Draft per `autoDispose`-Provider scopen). Test mit Rotation-Robot.
  - **Hunter-Refs**: R18-B-13

#### P3 — Doku/Polish

- **R18-F-22**: CSV-Export deckt nur Sniper/Finisseur — GDPR Art. 20 Datenportabilität unvollständig
  - **Datei**: `lib/features/training/data/csv_export_notifier.dart` (Scope), Settings-Sektion "Export"
  - **Symptom**: Datenportabilität nach Art. 20 DSGVO umfasst alle personenbezogenen Daten. Aktuell exportiert die App nur Trainings-Sessions, nicht Matches/Tournaments/Inbox/Profile.
  - **Fix**: Eigener Export-Pfad pro Daten-Typ oder ein Sammel-ZIP mit JSON pro Bereich. Sprint-C-Task neben R18-F-02. Wenn Phase 1 nur Closed-Beta: dokumentieren und vor Public-Launch nachziehen.
  - **Hunter-Refs**: R18-C-06

- **R18-F-23**: Keypair-Backup aus Settings nicht erreichbar (ADR-0010 §Backup)
  - **Datei**: Settings-Screen, Auth-Sektion
  - **Symptom**: ADR-0010 fordert Keypair-Backup als User-initiierte Aktion. Settings hat keinen Eintrag dafür. Bei Geräte-Verlust kein Recovery.
  - **Fix**: "Schlüssel sichern"-Aktion in Settings Auth-Sektion. Eigener Sprint-Task, hängt am Keypair-Layer aus ADR-0010.
  - **Hunter-Refs**: R18-C-07

- **R18-F-24**: Sammelposten — Settings-Labels, Konstanten, ADR-Klarheit
  - **Dateien**: `lib/features/settings/presentation/settings_screen.dart`, `lib/features/training/data/csv_export_notifier.dart`, `docs/adr/0010-*.md`
  - **Sammelposten**: `settingsRowResetSessions`-Label ist mehrdeutig — sagt nicht, ob nur Sessions oder auch Drafts/Inbox-Cache gemeint sind (R18-C-08); CSV-Export verwendet String-Literal `'finisseur'` statt einer geteilten Konstante aus `kubb_domain` (R18-B-12); Sniper-Stats fehlt Per-Distance-Breakdown — Pro-User-Feature (R18-C-09); Settings App-Sektion hat keinen "Über / Lizenzen"-Eintrag, OSS-Standard fehlt (R18-C-12); "Account verknüpfen" wird nur bei Anonymous-Account gezeigt — Multi-OAuth-Verhalten (Google + Apple gleichzeitig) ist in ADR-0010 nicht klargestellt (R18-C-11).
  - **Fix**: Eigene Polish-Iteration parallel zu Sprint C. Pro Punkt ein Mini-Task.
  - **Hunter-Refs**: R18-C-08, R18-B-12, R18-C-09, R18-C-12, R18-C-11

- **R18-F-25**: Filter-Icon-Sichtbarkeit nur kosmetisch — Spec-Frage
  - **Datei**: `lib/features/stats/presentation/stats_screen.dart`
  - **Symptom**: Wenn R18-F-16 mit "Match-Tab bekommt Filter" gelöst wird, fällt dieser Punkt weg. Solange offen: kosmetische Notiz.
  - **Fix**: An Auflösung von R18-F-16 koppeln.
  - **Hunter-Refs**: R18-A-10 (kosmetischer Teil)

**Rundenfazit**: Settings-Sektion ist der Compliance-Engpass — drei P0-Findings (Privacy-Lüge, fehlende Datenschutzerklärung, lokaler Account-Delete-Wipe) sind harte Launch-Blocker für Sprint C. Stats-Tabs leiden unter klassischen Riverpod-Hygiene-Fehlern (Invalidate fehlt, Races im Notifier, N+1) und einer kritischen Domain-Divergenz (R18-F-04 Finisseur-Success zwischen CSV und Stats). Re-Hit-Muster: Mängel-#1 Empty-States ist jetzt zum zweiten Mal markiert, FR-SOCIAL-4 ist seit OD-03 offen — beide gehören in den nächsten Polish-Sprint mit expliziter Owner-Abnahme.

### Runde 19 — Team-Management

**Hunter-Output**: R19-A (15, FAIL), R19-B (15, FAIL), R19-C (15, FAIL) → konsolidiert auf 26 Findings.

**Mängel-Sprung**: Lukas's Mängel-Report-Punkte #2 (4 Sub: Gruppen-Doppel-UI, Heimatverein, Liga-Hilfetext, Keyboard-Overflow) und #3 (Team-Create still failing — P0) sind hier konzentriert. #3 ist nur halb verarztet (Snackbar zwar da, `_busy`-Reset und Telemetry fehlen), #2.1 läuft parallel zur Teams-Welt weiter, #2.3/#2.4 unbearbeitet, #2.2 (Heimatverein) als FR-TEAM-2 weiterhin offen.

#### P0 — Funktional-Blocker

- **R19-F-01**: RosterCompositionWidget bekommt LEEREN Pool — Team-Turnier-Anmeldung UI-broken
  - **Datei**: `lib/features/tournaments/presentation/register_team_screen.dart:76-87`
  - **Symptom**: User wählt im Anmelde-Flow ein Team, das Roster-Picker-Widget rendert mit `pool: const []`, `guests: const []`. Keine Spieler-Auswahl möglich → FR-REG-12 ist UI-seitig komplett tot. Server-RPC bekäme leeren Roster, Anmeldung schlägt fehl oder bricht clientseitig ab.
  - **Fix**: `teamDetailProvider(teamId)` laden, `members.pool`/`members.guests` in `RosterPoolMember`-Listen mappen, an Widget durchreichen. Loading-/Error-State explizit.
  - **Hunter-Refs**: R19-C-06

- **R19-F-02**: Mängel #3 — Team-Create still failing (Schale ohne Tiefe)
  - **Dateien**: `lib/features/teams/presentation/team_create_screen.dart`, `lib/features/teams/application/team_membership_controller.dart` (`_runReturning`)
  - **Symptom**: Lukas's Report 2026-05-25 P0. Snackbar bei Fehler ist da (Teilfix), aber: (a) `_busy` bleibt `true`, wenn RPC `id == null` zurückgibt — Button bleibt deaktiviert, User glaubt, App ist gefroren; (b) kein `debugPrint`/Telemetry-Event → wir sehen kein Crashlog beim Reproduzieren; (c) `_runReturning` gibt nur `null` zurück, Caller hat keinen Fehler-Grund.
  - **Fix**: `_busy`-Reset im `finally`/auf Null-Pfad. Strukturiertes Logging mit Stacktrace + RPC-Payload (PII-frei). `_runReturning` liefert `Result<T>` mit Error-Kontext statt nackt `null`. Test: bewusst Server-Error provozieren → Snackbar + Button wieder enabled + Log-Eintrag.
  - **Hunter-Refs**: R19-A-01, R19-B-11, R19-B-06, R19-C-01

- **R19-F-03**: Mängel #2.1 — "Gruppen erstellen" parallel zu Teams (Doppel-UI)
  - **Datei**: `lib/features/teams/presentation/teams_screen.dart` (oder Home-Einstieg), Routing-Layer
  - **Symptom**: Lukas's Report #2.1. Alte Gruppen-Funktion ist mit Teams parallel sichtbar. User landet auf zwei konkurrierenden Konzepten, ADR-0018 fordert aber Teams als alleiniges Modell.
  - **Fix**: Gruppen-CTA entfernen, Route deprecaten, ggf. Migrations-Hinweis "Gruppen heissen jetzt Teams". UX-Snapshot vor/nach + Re-Test mit Lukas's Repro-Pfad.
  - **Hunter-Refs**: R19-A-04, R19-C-04

- **R19-F-04**: Permission-Gap — jeder Pool-Member kann jeden kicken
  - **Datei**: `supabase/functions/team_remove_member.sql` (RPC) + UI-Action-Guard in `team_detail_screen.dart`
  - **Symptom**: `team_remove_member` prüft nur "Aufrufer ist Member", nicht "Aufrufer ist Creator/Owner". Pool-Caper: ein Member kickt den Creator und übernimmt das Team. Kombiniert mit fehlender Captain-Rolle (ADR-0018) ist das eine echte Sicherheitslücke.
  - **Fix (kurzfristig)**: RPC verlangt `auth.uid() = teams.created_by` für Remove. UI versteckt Kick-Button bei Non-Owner. **Owner-Eskalation**: ADR-0018 verbietet Captain explizit, Lukas's Roadmap nennt aber "Captain wechseln" — Konflikt muss PO entscheiden, bevor Captain-Rolle eingeführt wird. Bis dahin: Owner-only-Permission als Minimal-Fix.
  - **Hunter-Refs**: R19-A-05, R19-B-03, R19-C-11

#### P1 — Hoch

- **R19-F-05**: Mängel #2.4 — Keyboard-Overflow im Team-Create-Form
  - **Datei**: `lib/features/teams/presentation/team_create_screen.dart`
  - **Symptom**: Lukas's Report #2.4. Beim Öffnen der Tastatur überlappt Content, Submit-Button verschwindet hinter Keyboard auf kleinen Devices.
  - **Fix**: `Scaffold(resizeToAvoidBottomInset: true)` sicherstellen, Form in `SingleChildScrollView` + `Padding(bottom: MediaQuery.viewInsets.bottom)`. Test mit Pixel 4a + iPhone SE.
  - **Hunter-Refs**: R19-A-02, R19-C-03

- **R19-F-06**: Mängel #2.3 — Liga-Klassen-Hilfetext fehlt
  - **Datei**: `lib/features/teams/presentation/team_create_screen.dart` (Liga-Dropdown)
  - **Symptom**: Lukas's Report #2.3. User sieht Liga-Optionen ohne Erklärung — Schweizer Standard A/B/C ist nicht selbsterklärend.
  - **Fix**: Info-Icon mit Tooltip oder Helper-Text unter Dropdown ("A = höchste Klasse, …"). Quelle: kubb-schweiz.ch oder ADR.
  - **Hunter-Refs**: R19-A-03, R19-C-02

- **R19-F-07**: Mängel #2.2 — FR-TEAM-2 Heimatverein-Feld fehlt
  - **Datei**: `lib/features/teams/presentation/team_create_screen.dart`, `kubb_domain` Team-Entity
  - **Symptom**: Lukas's Report #2.2. Schweizer Vereins-Struktur (Heimatverein/Club) ist Pflicht-Konzept laut FR-TEAM-2, aber im Create-Form fehlt das Feld komplett.
  - **Fix**: Feld + Domain-Erweiterung + Migration `teams.home_club_id` (oder Free-Text als MVP). Mit PO klären: Vereins-Liste vorab gepflegt oder User-Eingabe.
  - **Hunter-Refs**: R19-C-09

- **R19-F-08**: Privacy-Leak — `teams`-Tabelle public lesbar inkl. `created_by`
  - **Datei**: `supabase/migrations/*_teams_rls.sql`
  - **Symptom**: RLS-Policy erlaubt SELECT für alle Authenticated, Spalte `created_by` (User-UUID) inklusive. Korrelierbar mit Profilen → ungewollte Mitgliedschaft-Maps.
  - **Fix**: View `public_teams` ohne `created_by`/sensitive Felder. RLS auf Basis-Tabelle restriktiv (nur Member sehen Detail). Audit-Spalte über Member-Sicht.
  - **Hunter-Refs**: R19-A-07

- **R19-F-09**: Pool zeigt UUIDs statt Anzeigenamen
  - **Dateien**: `lib/features/teams/presentation/team_detail_screen.dart` (Pool-Liste), `team_get`-RPC, Wire-Layer
  - **Symptom**: Member-Karten rendern `user_id` als Text. User sehen sich gegenseitig nur als kryptische UUIDs. `team_get` liefert keinen Pool-Sub-Block mit Display-Name → `TeamWire` mappt nicht.
  - **Fix**: `team_get` join mit `profiles` (display_name, avatar). `TeamWire.pool` mit `PoolMemberWire{userId, displayName, avatarUrl}`. UI rendert Name + Avatar.
  - **Hunter-Refs**: R19-A-09, R19-B-04, R19-C-10, R19-C-14

- **R19-F-10**: Dissolve-Consent-Flow UI fehlt komplett (FR-TEAM-19)
  - **Dateien**: `lib/features/teams/presentation/team_detail_screen.dart`, `team_dissolve`-RPC
  - **Symptom**: Auflösungs-Button feuert RPC, die NOT-EXISTS-Subquery auf Consent prüft. UI hat aber keinen Consent-Sammel-Flow — Button schlägt fehl, sobald >1 Member da ist. Zusätzlich: Subquery-Semantik "Consent ewig gültig" → wenn Member zwischen Consent und Dissolve verlässt/joint, ist Ergebnis löchrig.
  - **Fix**: Consent-Sammel-Screen ("Auflösung beantragen — N/M zugestimmt"), Live-Subscribe auf Consents. RPC: Consent mit Timestamp + Revoke-Möglichkeit, Quorum-Check zum Zeitpunkt der Auflösung.
  - **Hunter-Refs**: R19-A-?, R19-B-10, R19-C-08

- **R19-F-11**: Captain-Roadmap-Konflikt — ADR-0018 vs. Lukas's Roadmap-Notiz
  - **Datei**: `docs/adr/0018-teams-no-captain.md`, Roadmap-Doku
  - **Symptom**: ADR-0018 verbietet Captain-Rolle strikt. Lukas's Roadmap nennt aber "Captain wechseln" als Feature-Idee. UI hat keine Captain-Aktionen — korrekt, aber Doku-Drift bleibt.
  - **Fix (Owner-Eskalation)**: PO entscheidet: ADR-0018 bleibt strikt (Roadmap-Notiz streichen) ODER ADR-Revision mit Owner-Konzept. Bis Entscheidung: Status quo (kein Captain), aber R19-F-04 Permission-Fix unabhängig durchziehen.
  - **Hunter-Refs**: R19-A-05 (Teil), R19-C-11 (Teil)

- **R19-F-12**: Member-Invite erwartet UUID-Eingabe statt Friend-Picker
  - **Datei**: `lib/features/teams/presentation/team_detail_screen.dart` (`_promptForInvite`)
  - **Symptom**: Invite-Dialog ist ein nackter Textfield, User soll eine UUID eingeben — niemand kennt seine Friend-UUIDs. Plus: keine UUID-Validierung, Crash bei Garbage-Input.
  - **Fix**: Friend-Picker-Bottomsheet (Liste aus `friends`-Repository), Multi-Select. Notfall-Fallback "manuell per UUID" mit `Uuid.tryParse`-Guard.
  - **Hunter-Refs**: R19-A-06, R19-A-15, R19-B-05

- **R19-F-13**: Pool-Grössen-Limit fehlt
  - **Datei**: `team_invite_accept`-RPC, `team_create_screen.dart`
  - **Symptom**: ADR-0018 erlaubt `team_size` zwischen 1 und 6, aber der Pool (Spieler + Reserve) hat keinerlei Hard-Limit. Theoretisch lädt ein Team 200 Spieler ein.
  - **Fix**: Server-Check `pool.size <= team_size + reserve_max` (Reserve-Konzept aus ADR-0018 §3 klären). UI zeigt Auslastung "5/6". Default-Hint "Schweizer Standard 3 Spieler" beim Erstellen.
  - **Hunter-Refs**: R19-B-14, R19-C-07

#### P2 — Mittel

- **R19-F-14**: Team-Edit komplett fehlend (kein update-RPC)
  - **Dateien**: `lib/features/teams/presentation/team_detail_screen.dart`, `team_update`-RPC fehlt
  - **Symptom**: User kann Team-Name/Liga/Heimatverein nach Erstellung nicht ändern. Tippfehler im Namen bleibt für immer. FR-TEAM-? nicht umgesetzt.
  - **Fix**: `team_update`-RPC (Owner-only), Edit-Screen mit Pre-Filled-Form. Audit-Event auf Änderung.
  - **Hunter-Refs**: R19-A-11

- **R19-F-15**: `team_leave` ohne Tournament-Registration-Check
  - **Datei**: `team_leave`-RPC
  - **Symptom**: Member verlässt Team während aktiver Turnier-Anmeldung — Roster-Inkonsistenz. Server lässt durch.
  - **Fix**: RPC prüft `tournament_registrations` mit aktivem Status für Team; Block oder Hinweis "Erst aus Anmeldung X austreten".
  - **Hunter-Refs**: R19-A-10

- **R19-F-16**: Member-Remove während laufendem Turnier
  - **Datei**: `team_remove_member`-RPC
  - **Symptom**: Spiegelbild zu R19-F-15. Owner kickt Spieler, der gerade im Turnier-Bracket steht → Bracket bricht.
  - **Fix**: Block mit Hinweis auf Substitution-Flow (FR-TEAM-13/14) — siehe R19-F-19.
  - **Hunter-Refs**: R19-A-12

- **R19-F-17**: `respondInvitation` invalidiert `teamDetailProvider` nicht
  - **Datei**: `lib/features/teams/application/team_membership_controller.dart`
  - **Symptom**: User akzeptiert Einladung, Team-Detail bleibt stale, neuer Member erscheint erst nach manuellem Reload.
  - **Fix**: Nach erfolgreicher Response `ref.invalidate(teamDetailProvider(teamId))` und `pendingInvitationsProvider`.
  - **Hunter-Refs**: R19-B-02

- **R19-F-18**: `_run`/`_runReturning` TOCTOU re-entry guard
  - **Datei**: `lib/features/teams/application/team_membership_controller.dart`
  - **Symptom**: Doppel-Tap auf Action-Button → zweiter Call sieht `_busy=false` zwischen Set/Check und feuert RPC zweimal.
  - **Fix**: Atomarer Re-Entry-Guard (z.B. `_inFlight` als bool mit synchronem Check vor await). Optional: Debounce am Button.
  - **Hunter-Refs**: R19-B-01

- **R19-F-19**: FR-TEAM-13/14 Mid-Tournament-Roster-Substitution nicht in Team-UI verlinkt
  - **Datei**: `lib/features/teams/presentation/team_detail_screen.dart`
  - **Symptom**: Sub-Flow ist (laut Spec) im Turnier-Kontext eingebaut, aber Team-Detail hat keinen Querverweis. User findet die Aktion nicht. Audit-Events (FR-TEAM-14) sind nirgends sichtbar.
  - **Fix**: Bei aktiver Turnier-Anmeldung Hinweis-Banner mit Link zum Sub-Flow. Audit-Liste als Tab im Team-Detail (FR-TEAM-14).
  - **Hunter-Refs**: R19-C-05, R19-C-12

- **R19-F-20**: `team_leave` race gegen `invitation_respond`
  - **Datei**: RPCs ohne Row-Lock auf `team_members`
  - **Symptom**: Member verlässt parallel, während Einladung angenommen wird → inkonsistente Membership-Zeile.
  - **Fix**: `SELECT … FOR UPDATE` auf `team_members` in beiden RPCs.
  - **Hunter-Refs**: R19-B-09

- **R19-F-21**: `pendingInvitationsProvider` umgeht TeamRepository
  - **Datei**: `lib/features/teams/data/...`
  - **Symptom**: Direkter Supabase-Client-Call statt über `TeamRepository`. Bricht Cleancode-Schicht, erschwert Testbarkeit.
  - **Fix**: Repository-Methode `watchPendingInvitations()` einführen, Provider darauf umstellen.
  - **Hunter-Refs**: R19-B-08

- **R19-F-22**: Action-Buttons feuern Futures ohne `await`
  - **Datei**: `lib/features/teams/presentation/team_detail_screen.dart`
  - **Symptom**: `onPressed: () => controller.doX()` ohne `await` → Loading-State greift nicht, Fehler werden geschluckt.
  - **Fix**: Async-Callbacks mit `await` + try/catch + Snackbar-Surface.
  - **Hunter-Refs**: R19-B-07

#### P3 — Polish/Doku

- **R19-F-23**: BR-5-Pre-Validation clientseitig fehlt
  - **Symptom**: Server prüft BR-5 (Business-Rule rund um Team-Mitgliedschaft), Client hat keine Pre-Validation → User sieht erst spät den Server-Fehler.
  - **Fix**: Spiegel-Check im Client mit konsistenter Fehlermeldung.
  - **Hunter-Refs**: R19-C-15

- **R19-F-24**: OD-M3-04 Reserve-Konzept Doc-Drift zur Schweizer Praxis
  - **Datei**: `docs/operational-design/m3-teams.md`
  - **Symptom**: OD-Doku beschreibt Reserve abstrakt, Schweizer Standard (3 Spieler + 1-2 Reserve) ist nicht festgehalten.
  - **Fix**: OD-Update mit konkretem Schweizer Default + Verweis auf ADR-0018 §team_size.
  - **Hunter-Refs**: R19-C-13

- **R19-F-25**: Sammelposten Team-UI-Polish
  - **Sammelposten**: Empty-State "Noch leer." zu knapp — Anleitung zum ersten Schritt fehlt (R19-A-14); offene Einladungen werden im Team-Detail nicht angezeigt — User wundert sich, warum Person fehlt (R19-A-13); Team-Name nicht eindeutig — zwei Teams "Bern" verwirren im Bracket, Suggestion mit Suffix/Verein (R19-A-08); `_prompt`-Dialog Controller-Dispose-Race bei schnellem Cancel (R19-B-05 Teil); `create()` ohne Country-Code-Validation, falls Heimatverein-Feature (R19-F-07) Land erfordert (R19-B-12); `teamMembershipControllerProvider` nicht `autoDispose` → State-Leak nach Navigation (R19-B-13); `TextEditingController`-Listener-Leak im Edit-/Prompt-Flow (R19-B-15).
  - **Fix**: Eigene Polish-Iteration nach P0/P1-Wave. Pro Punkt Mini-Task.
  - **Hunter-Refs**: R19-A-08, R19-A-13, R19-A-14, R19-B-05, R19-B-12, R19-B-13, R19-B-15

- **R19-F-26**: Audit-Events nicht UI-sichtbar (FR-TEAM-14, falls nicht via R19-F-19 gelöst)
  - **Datei**: `lib/features/teams/presentation/team_detail_screen.dart`
  - **Symptom**: Falls Audit-Tab aus R19-F-19 nicht im Sub-Flow-Kontext gelöst wird, separat als History-Tab im Team-Detail.
  - **Fix**: Audit-Liste mit Member-Join/Leave/Kick/Rename-Events.
  - **Hunter-Refs**: R19-C-12

**Rundenfazit**: Team-Management ist Lukas's Mängel-Brennpunkt — drei der vier P0 (R19-F-02 Create-Fail, F-03 Gruppen-Doppel-UI, F-04 Permission-Gap) sind Schale-ohne-Tiefe-Symptome, F-01 RosterComposition-Leerer-Pool macht Team-Turnier-Anmeldung komplett funktionsunfähig. Captain-Frage (R19-F-11) verlangt eine PO-Entscheidung vor weiterer Permission-Arbeit; bis dahin reicht Owner-only als Minimal-Fix. Mängel-#2.2 (Heimatverein) und FR-REG-12 (Roster-Wire) sind die offensichtlichsten Spec-Lücken — beide müssen vor dem nächsten Team-Turnier-Pilotlauf gefixt sein.

### Runde 20 — Social (Friends, Groups, Inbox) + Routing-Audit

**Hunter-Output**: R20-A (13, FAIL), R20-B (13, FAIL), R20-C (13, FAIL) → konsolidiert auf 26 Findings. Fokus: Friend-Network, Gruppen-Konzept-Drift, Inbox-Lifecycle, Auth-Gate + Public-Router, Deeplinks.

**Mängel-Konvergenz**: Das Gruppen-Feature ist jetzt zum dritten Mal markiert (Lukas's Mängel-Report #2.1 → R19-F-03 → R20-F-01). Owner-Entscheidung steht aus und blockiert sauberen Cleanup. Friends-only-Privacy (FR-SOCIAL-4) ist Re-Hit aus R18-F-05 (OD-03), Auth-Gate-Lücke ist neu und live-kritisch.

#### P0 — Funktional-/Compliance-Blocker

- **R20-F-01**: Gruppen-Feature redundant zu Teams — DREIFACH bestätigt (Mängel #2.1 + R19-F-03 + R20-C-01)
  - **Datei**: `lib/features/social/presentation/...` (Gruppen-Sheets, Routing), Home-CTA, Teams-Welt parallel
  - **Symptom**: Konzept-Doppelung lebt seit Mängel-Report 2026-05-25 weiter. ADR-0018 (Teams) ist accepted, Gruppen sind nirgends spezifiziert, laufen aber im Code parallel. User sieht zwei konkurrierende Modelle.
  - **Status**: Owner-Action zwingend. Drei Hits über drei Quellen ist das absolute Maximum der Verstärkung in dieser Sweep.
  - **Optionen**: A) Gruppen ganz entfernen + Daten migrieren in Teams (sauber, aufwendig). B) Gruppen als "Buddy-Liste / Chat-Kanal" semantisch von Teams trennen mit eigener Spec + ADR (Doppelarbeit). C) Status quo — nicht haltbar, dritter Re-Hit beweist es.
  - **Empfehlung**: A. Migration in Teams + Gruppen-Routen deprecaten + Banner-Hinweis "Gruppen heissen jetzt Teams".
  - **Hunter-Refs**: R20-C-01, R19-F-03, Mängel-Report-#2.1

- **R20-F-02**: DSGVO Profile-Visibility-Settings fehlen komplett (FR-AUTH-5)
  - **Datei**: `lib/features/settings/presentation/settings_screen.dart`, `user_profiles`-Schema
  - **Symptom**: Kein `profile_visibility ∈ {public, friends_only, private}`-Feld, kein RLS-Policy-Pfad, kein Settings-Picker. User kann seine Sichtbarkeit nicht steuern — DSGVO Art. 25 Privacy-by-Default und Recht auf Selbstbestimmung sind verletzt.
  - **Fix**: Schema-Migration + Default `friends_only` + RLS-Policies auf Visibility + Settings-Picker. Hängt eng an R20-F-08 (Friends-only-Privacy für Stats) und R18-F-01/02 (Privacy-Compliance-Block).
  - **Hunter-Refs**: R20-C-08

- **R20-F-03**: Inbox überlebt App-Restart offline NICHT (ADR-0012 verletzt)
  - **Datei**: Inbox-Provider, drift-Cache (oder fehlend)
  - **Symptom**: ADR-0012 deklariert Inbox-Cache als Load-Bearing für Offline-Tauglichkeit. Realität: nach App-Kill offline keine Inbox-Items mehr sichtbar. Schiedsrichter offline am Pitch sieht seine Match-Invites nicht.
  - **Fix**: drift-Tabelle für Inbox-Items + Hydrate-on-Open + Sync-Reconcile bei Online-Kommen.
  - **Hunter-Refs**: R20-C-05

- **R20-F-04**: Auth-Gate lässt `/sign-in/account-link` + `/sign-in/delete` für signedOut-User passieren
  - **Datei**: `lib/core/router.dart` (Redirect-Logik), Auth-Guard
  - **Symptom**: Routen sind für authenticated User gedacht, der Guard prüft nur das `/` -Prefix-Match. Ein nicht-eingeloggter User kann via Direct-Link auf den Account-Link- oder Delete-Screen → führt zu Crash oder zu Account-Operation auf Anon-Session.
  - **Fix**: Whitelist statt Blacklist. Public-Route-Set explizit, alles andere erfordert `auth.session != null`. Per-Route-Redirect-Funktion testen.
  - **Hunter-Refs**: R20-A-01

#### P1 — Hoch

- **R20-F-05**: Externe Deeplinks fehlen + keine Android-Intent-Filter (A-02 = C-13 deduped)
  - **Datei**: `android/app/src/main/AndroidManifest.xml`, iOS `Info.plist`, Universal-Links-Setup
  - **Symptom**: Public-Tournament-Routen `/public/...` sind im Router definiert, aber kein Intent-Filter im Manifest. WhatsApp-Link öffnet Browser statt App. Spec ADR-0023 (Spectator) ohne Share-Pfad → viraler Andrang bricht ab.
  - **Fix**: Intent-Filter für `kubb.app` Host + `/public/*`-Pfade. iOS associated-domains. Test: QR-Code → App öffnet direkt im Public-Screen.
  - **Hunter-Refs**: R20-A-02, R20-C-13

- **R20-F-06**: Tournament-Setup erlaubt Keypair-Account trotz ADR-0010 OAuth-Force
  - **Datei**: `lib/features/tournament/presentation/setup_wizard.dart`, Auth-Gate
  - **Symptom**: ADR-0010 fordert OAuth für Organizer-Rollen (Accountability + Recovery). Wizard prüft das nicht — anonymer Keypair-Account kann Tournament erstellen. Bei Geräte-Verlust ist das Turnier eigentümerlos.
  - **Fix**: Pre-Flight-Guard `requireOAuthAccount()` vor Setup-Submit. Bei Keypair: Upgrade-CTA "Mit Google/Apple verknüpfen, um Turnier zu erstellen".
  - **Hunter-Refs**: R20-C-04

- **R20-F-07**: Block-Feature fehlt komplett trotz Schema-Vorbereitung (FR-SOCIAL-6)
  - **Datei**: `lib/features/social/...`, RPC + UI fehlen
  - **Symptom**: Schema hat `blocked_users`-Spalten vorbereitet, aber kein Block-RPC, kein UI, kein Filter-Pfad. Friend-Requests, Group-Invites, Match-Challenges von blockierten Usern landen weiter im Inbox.
  - **Fix**: Eigener Sprint-Task. Block-RPC + Filter in allen Social-Queries + UI in Profile/Friend-Detail. Auch R20-F-12 (inviteMember kennt keinen Block-Check) hängt dran.
  - **Hunter-Refs**: R20-C-03

- **R20-F-08**: SocialActions ohne Serialisierung — accept+reject Race
  - **Datei**: `lib/features/social/application/social_actions.dart`
  - **Symptom**: Doppel-Tap auf "Annehmen" + "Ablehnen" feuert beide RPCs parallel. Server-Side-Idempotenz fehlt → Friend-State inkonsistent.
  - **Fix**: Mutex/`_inFlight`-Flag pro Friendship-Operation. Server-RPC mit `WHERE status='pending'`-Guard.
  - **Hunter-Refs**: R20-B-01

- **R20-F-09**: GoRouter `ChangeNotifier` nie disposed
  - **Datei**: `lib/core/router.dart` (refreshListenable)
  - **Symptom**: Auth-Refresh-ChangeNotifier wird im Router-Provider erstellt aber nie disposed. Bei Hot-Restart und Test-Setup wachsen Listener-Counts → Speicher-Leak.
  - **Fix**: `ref.onDispose(() => notifier.dispose())` im Router-Provider.
  - **Hunter-Refs**: R20-B-04

- **R20-F-10**: Friends-only-Privacy nirgends umgesetzt (FR-SOCIAL-4 Re-Hit aus R18-F-05)
  - **Datei**: Stats-Tab, Match-Detail, Public-Routen
  - **Symptom**: R18-F-05 ist seit OD-03 offen. Re-Hit bestätigt: weder Match-Stats noch Friend-Profile filtern auf Friends-only. Hängt eng an R20-F-02 (Visibility-Setting).
  - **Fix**: Gemeinsam mit R20-F-02 lösen — Visibility-Feld + RLS-Filter + Client-Filter in allen Query-Pfaden.
  - **Hunter-Refs**: R20-C-02, R18-F-05

- **R20-F-11**: PublicRouterShell überschreibt User-Session unbeabsichtigt
  - **Datei**: `lib/features/public/router_shell.dart`
  - **Symptom**: Wechsel von Public-Route zu Auth-Route triggert Re-Init der Auth-Session. Bestehende User-Session geht verloren — User ist ausgeloggt nach Spectator-Klick.
  - **Fix**: Public-Shell darf Auth-Provider nicht resetten. Eigener Public-Branch im Router ohne Auth-Side-Effects.
  - **Hunter-Refs**: R20-A-09

#### P2 — Mittel

- **R20-F-12**: AddFriend-Picker liest `acceptedFriendsProvider` ohne `friendsListProvider` zu materialisieren
  - **Datei**: `lib/features/social/presentation/add_friend_picker.dart`
  - **Symptom**: Picker zeigt "Keine Freunde"-Snackbar obwohl Friends existieren — Provider-Dependency-Reihenfolge falsch.
  - **Fix**: `ref.watch(friendsListProvider)` zuerst, dann derived `accepted`-View.
  - **Hunter-Refs**: R20-A-03

- **R20-F-13**: DraggableScrollableSheet ignoriert ScrollController
  - **Datei**: `lib/features/social/presentation/group_detail_sheet.dart`, andere Sheets
  - **Symptom**: Inner-Scrollable funktioniert nicht — Sheet nimmt alle Scroll-Events.
  - **Fix**: `ScrollController` aus `builder` an die innere Liste durchreichen.
  - **Hunter-Refs**: R20-A-04, R20-B-06

- **R20-F-14**: `inboxUnreadCountProvider` hat KEINEN Konsumenten — Badge fehlt komplett (Toter-Brief-Pattern)
  - **Datei**: `lib/features/inbox/application/...`, Home/Tab-Bar
  - **Symptom**: Provider produziert `unreadCount`, kein Widget watched ihn. User sieht keine Inbox-Badge. Klassisches Toter-Brief-Pattern (siehe R16-F-01 + R17-F-15).
  - **Fix**: Tab-Bar-Badge konsumiert Provider. Test mit synthetischen Items.
  - **Hunter-Refs**: R20-A-05

- **R20-F-15**: friendsPollingProvider 1s-Tick + läuft auch wenn nicht angemeldet (A-07 = B-02 deduped)
  - **Datei**: `lib/features/social/application/friends_polling_provider.dart`
  - **Symptom**: 1-Sekunden-Polling ohne Backoff, kein Auth-Guard. Akku-Killer + unnötige RPC-Last bei signedOut-User.
  - **Fix**: Auth-Guard + Backoff-Sequenz (5s/15s/60s) + Pause bei App-im-Hintergrund (Lifecycle-Listener).
  - **Hunter-Refs**: R20-A-07, R20-B-02

- **R20-F-16**: BackButton ohne `canPop`-Check
  - **Datei**: mehrere Sheets/Screens
  - **Symptom**: Tap auf BackButton ohne Stack-Eintrag → Crash oder leerer Screen.
  - **Fix**: `if (context.canPop()) context.pop()` Helper. Pattern-Sweep über alle Custom-AppBars.
  - **Hunter-Refs**: R20-A-06

- **R20-F-17**: markRead nicht atomar bei Doppelklick
  - **Datei**: `lib/features/inbox/application/inbox_controller.dart`
  - **Symptom**: Doppel-Tap auf Inbox-Item → zwei parallele `markRead`-RPCs. Server-Side ohne Idempotency-Guard.
  - **Fix**: `_inFlight`-Set pro Item-ID. Server-RPC mit `WHERE read_at IS NULL`.
  - **Hunter-Refs**: R20-B-03

- **R20-F-18**: Loading-Pfad ohne previous value → Redirect-Flickerei
  - **Datei**: `lib/core/router.dart`
  - **Symptom**: Bei Auth-Refresh kurzes Loading → Redirect-Logik nimmt es als signedOut wahr → Flicker zur Sign-In-Route.
  - **Fix**: `valueOrPrevious` statt `value` für Auth-State, oder Skeleton bis Auth resolved ist.
  - **Hunter-Refs**: R20-B-05

- **R20-F-19**: `_handleMatchInvite` navigiert vor Invalidate-Future
  - **Datei**: `lib/features/inbox/presentation/inbox_screen.dart`
  - **Symptom**: Match-Invite-Accept feuert `ref.invalidate(...)` und navigiert sofort — Ziel-Screen sieht alten State.
  - **Fix**: `await ref.read(provider.future)` vor Navigation, oder optimistisches Update.
  - **Hunter-Refs**: R20-B-11

- **R20-F-20**: Match-Mode Phase-2 ADR-0012 deklariert "deferred", aber Code live
  - **Datei**: Match-Mode-Implementation, ADR-0012
  - **Symptom**: Doc-Drift. ADR sagt deferred, Code shipped seit M1. ADR-Update oder Feature-Flag fehlt.
  - **Fix**: ADR-0012 revidieren mit Accepted-Status für Phase-1.
  - **Hunter-Refs**: R20-C-10

- **R20-F-21**: Friend-Request aus Inbox: `replied_at` gesetzt aber friendsListProvider race
  - **Datei**: `lib/features/inbox/...`, friendsListProvider
  - **Symptom**: Inbox markiert Request als beantwortet, friendsList sieht den neuen Friend erst nach Polling-Tick. UI inkonsistent.
  - **Fix**: Atomarer State-Update über beide Provider, oder optimistisches Insert in friendsList.
  - **Hunter-Refs**: R20-A-08

- **R20-F-22**: Public-Route-Bypass nur via Prefix-Match — anfällig für Spoofing
  - **Datei**: Router-Redirect
  - **Symptom**: Public-Route-Erkennung per `path.startsWith('/public')`. `/public-fake/admin` rutscht durch.
  - **Fix**: Whitelist mit exakten Route-Pattern-Matches, ggf. Route-Klassifizierung im Router-Builder.
  - **Hunter-Refs**: R20-C-06

#### P3 — Doku/Polish

- **R20-F-23**: Routing-Pfade gemischt deutsch/englisch — keine Convention
  - **Symptom**: `/tournier-detail`, `/match-list`, `/spielanmeldung` durcheinander. ARB-Convention sagt englisch.
  - **Fix**: Style-Guide + Route-Rename-Sweep mit Deeplink-Backward-Compat.
  - **Hunter-Refs**: R20-C-09

- **R20-F-24**: Push-Notification-Setup fehlt komplett
  - **Symptom**: Kein FCM/APNS-Setup. Match-Invites, Disputes etc. nur sichtbar wenn App offen.
  - **Fix**: Eigener Sprint-Task post-MVP.
  - **Hunter-Refs**: R20-A-12

- **R20-F-25**: Sammelposten — Sekundär-Polish
  - **Sammelposten**: Kein `ShellRoute`/`StatefulShellRoute` → keine Tab-Persistence (R20-A-13); Friends-Suche zeigt sich selbst als Kandidaten (R20-A-10); FriendEntry.status als String statt Enum (R20-B-07); createGroup print() statt Logging (R20-B-09); _MemberRow.onRemove ohne UI-Feedback (R20-B-10); _showCreateDialog Controller-Dispose-Race (R20-B-12); archive() ohne archived_at-is-null-Guard (R20-B-13); Friends-Screen versteckt incoming-pending entgegen ADR-Intent (R20-C-11); QR-Pairing deferred ohne Tracking (R20-C-12); verification_request für Friend-Request — kein dedizierter Kind (R20-C-07).
  - **Fix**: Eigene Polish-Iteration post-MVP.
  - **Hunter-Refs**: R20-A-10, R20-A-13, R20-B-07, R20-B-09, R20-B-10, R20-B-12, R20-B-13, R20-C-07, R20-C-11, R20-C-12

- **R20-F-26**: Friends-Screen versteckt incoming-pending entgegen ADR-Intent (separat von Sammelposten, weil eigenständig prüfbar)
  - **Symptom**: Pending-Incoming Friend-Requests sind nur via Inbox sichtbar, nicht im Friends-Screen. ADR-Intent: zentrale Friends-Übersicht inkl. Pending.
  - **Fix**: Sektion "Anfragen" im Friends-Screen mit Inline-Accept/Reject.
  - **Hunter-Refs**: R20-C-11

**Rundenfazit**: Vier P0 — das Gruppen-Doppel-UI ist mit Mängel-Report + R19-F-03 + R20-F-01 dreifach bestätigt und blockiert sauberen Social-Cleanup ohne Owner-Entscheidung. DSGVO-Visibility fehlt komplett (R20-F-02) und ist Compliance-Block für Public-Launch parallel zu R18-F-01/02. Inbox überlebt App-Restart offline nicht (R20-F-03, ADR-0012 violiert) — schmerzhaft am Pitch. Auth-Gate-Lücke (R20-F-04) ist neu und live-kritisch. P1 sammelt sechs strukturelle Befunde: Deeplinks fehlen (Re-Hit der ADR-0023-Viralitäts-Lücke aus R14-F-08), OAuth-Force-Bypass im Tournament-Setup, Block-Feature komplett fehlend trotz Schema-Vorbereitung, SocialActions-Race, GoRouter-Memory-Leak, Friends-only-Privacy als Re-Hit. P2/P3 sind klassische Riverpod-/UX-Hygiene plus das vierte Auftreten des Toter-Brief-Patterns (R20-F-14 — inboxUnreadCountProvider ohne Konsumenten, jetzt zum dritten Mal in der Sweep: R16-F-01 → R17-F-15 → R20-F-14, dieses Pattern braucht systematischen Sweep über alle Provider).

---

## End-of-Sweep — Master-Summary über alle 20 Runden

**Datum**: 2026-05-27
**Methodik**: 20 Themen × 3 parallele Hunter (User-Flow / Code-Quality / Spec-Compliance) × Chef-Konsolidierung. Opus-Modelle für alle Agents. Total ca. 850 Hunter-Findings konsolidiert auf 420 Final-Findings.

### Top-10 Showstopper für Sprint A (Funktionalität-First)

Priorisiert nach Live-Turnier-Tauglichkeit, Datenintegrität, Compliance.

1. **R17-F-01** — `_RemoteScoreLamportSubmitter.submit` wirft `UnimplementedError` → jeder offline-Score-Submit verloren, Outbox-Stub macht App live-untauglich (Runde 17).
2. **R17-F-02** — Score-Drafts werden nie persistiert (FR-DSCORE-19..22) → App-Kill am Pitch vernichtet Eingaben (Runde 17).
3. **R1-F-02** — Session-Cache-Race blockiert RPCs (Root-Cause Mängel #9, `authentication required` beim Tournier-Create) (Runde 1).
4. **R1-F-01** — OAuth-Sign-In-Buttons sind UI-Stubs ohne Dispatch → kein nicht-anonymes Sign-In möglich (Runde 1).
5. **R10-F-13** — `disputed` routet auf Match-Liste statt Conflict-Screen (MUSS-Fix #2 aus Projekt-Memory, seit drei Runden offen) (Runde 10).
6. **R19-F-01** — RosterCompositionWidget bekommt leeren Pool → Team-Turnier-Anmeldung UI-broken (Runde 19).
7. **R19-F-02** — Mängel #3 Team-Create still failing (`_busy` bleibt true bei Null-RPC-Return) (Runde 19).
8. **R14-F-01..03** — Anon-RLS-Pfad strukturell broken (anon-Rolle vs. authenticated-Anon), Privacy-View nicht benutzt → Public-Spectator-Modell tot, DSGVO-violation (Runde 14).
9. **R12-F-01** — Forfeit-Surface komplett fehlt (DSCORE-62..-66 + FR-MATCH-7/-8 nicht ausführbar) (Runde 12).
10. **R11-F-01** — EKC ohne Zeitablauf/"Keiner"-Pfad (4-fach gemeldetes Domain-Modell-Loch, blockiert Schweizer-Regelwerk-Konformität) (Runde 11).

### Top-Patterns (Re-Hits über Runden hinweg)

1. **Toter-Brief-Pattern (Producer ohne Konsument)** — vierfach: R16-F-01 (realtimeFallbackProvider), R17-F-15 (Outbox-Status-Stream), R20-F-14 (inboxUnreadCountProvider), implizit auch R9-F-05 (Audit-Trail leer per Konstruktion). **Owner-Action**: systematischer Provider-Sweep mit Tooling (grep auf StreamProvider/StateProvider ohne `ref.watch`-Konsumenten).
2. **Race-Conditions in Notifier (Doppel-Tap + Read-Modify-Write ohne Lock)** — sechsfach: R3-F-04 + R4-F-01..03 + R5-F-01..02 + R8-F-01 + R10-F-01 + R19-F-18 + R20-F-08/17. **Pattern**: jeder Notifier mit RPC-Trigger braucht `_inFlight`-Guard + Server-Side-Idempotency. Hotfix-Wave-Architektur ist überall identisch (Mutex + UNIQUE-Constraint + transaktionale Schreibpfade).
3. **Display-Name-Mapping fehlt (UUID-Substrings statt Namen)** — vierfach: R10-F-06 (Match-Header) → R13-F-02 (Standings) → R14-F-10 (Public-Roster) → R15 (Live-Dashboard) → R19-F-09 (Team-Pool). Ein Domain-Patch (`tournament_*_get`-RPCs joinen `profiles.display_name`) wirkt überall.
4. **Provider-ohne-Invalidate nach Action** — fünffach: R2-F-02, R8-F-03, R9-F-14, R18-F-06, R19-F-17. Pattern: jede Mutation muss `ref.invalidate(...)` der abhängigen Read-Provider triggern.
5. **Mängel-Report nur halb adressiert** — Lukas's Mängel-Report 2026-05-25 hatte 9 Punkte. #2.1 (Gruppen-Doppel-UI) ist nach drei Runden noch offen, #2.2-#2.4 sind P1-Backlog, #3 (Team-Create) ist Schale (Snackbar nur, kein `_busy`-Reset), #1 (Empty-States) ist Re-Hit in R18. Pattern: Owner-Briefings landen oft als UI-Lippenstift ohne strukturellen Fix.

### Sprint-Empfehlung

**Sprint A — Funktionalität-First** (Demo-/Pilot-Block, ~10-14 Tage):
- R17-F-01 + R17-F-02 (Outbox-Submitter + Score-Drafts) — 3-4 Tage Block, ohne diese kein Pitch-Einsatz
- R1-F-01 + R1-F-02 + R1-F-03 (Auth-Cache-Race + OAuth-Stubs + Keypair-Refresh) — 2-3 Tage Block, Root-Cause Mängel #9
- R10-F-13 (Conflict-Routing, 15min MUSS-Fix #2 seit drei Runden offen)
- R19-F-01 + R19-F-02 (Team-Roster-Wire + Team-Create-Robustness)
- R14-F-01..03 (Anon-RLS-Block + Public-Spectator-Pfad)
- R12-F-01 (Forfeit-Surface) + R11-F-01 (EKC-Zeitablauf) — Schweizer-Regelwerk-Konformität
- Race-Hotfix-Wave: R3-F-04/R4-F-01..03/R5-F-01..02 (Mutex + UNIQUE + Transaction-Pattern an alle drei Trainings-Modi + Tournament-Submit)

**Sprint B — UI/UX-Polish** (Mängel-Report-Block, ~5-7 Tage):
- R19-F-03/R20-F-01 (Gruppen-Doppel-UI **nach Owner-Entscheidung**)
- R19-F-05/F-06/F-07 (Mängel #2.2/.3/.4 Heimatverein + Liga-Hilfetext + Keyboard-Overflow)
- R2-F-01/F-02/F-03 (Avatar-Encoding + Save-Refresh + Onboarding-Tour-Wiring)
- R3-F-01/F-02/F-03 (Tournament-Tile-Lüge + Bottom-Nav-Split + Heim-Tab-Content)
- R18-F-14 (Empty-States, Mängel #1 Re-Hit)
- R10-F-06/R13-F-02/R14-F-10 (Display-Name-Mapping-Sweep — ein Patch, vier Stellen)

**Sprint C — Showstopper-abhängig** (wartet auf Lukas-Input + Compliance-Launch-Block, ~7-10 Tage):
- R20-F-01 Owner-Entscheid: Gruppen entfernen vs. semantisch trennen (Option A/B/C)
- R18-F-01/F-02/F-03 (Privacy-Text + Datenschutzerklärung + Account-Delete-Wipe) — DSGVO-Launch-Blocker
- R20-F-02 (Profile-Visibility FR-AUTH-5) + R20-F-10 (Friends-only-Privacy FR-SOCIAL-4)
- R20-F-03 (Inbox-Offline-Cache ADR-0012)
- R19-F-11 Owner-Entscheid: ADR-0018 Captain-Verbot vs. Roadmap-Captain-Wunsch
- R1-F-04 Owner-Entscheid: Berechtigungsmatrix `user_roles` jetzt oder später

**Backlog** (post-MVP):
- R20-F-05 + R14-F-08 (Deeplinks + QR-Share, ADR-0023-Viralitäts-Pfad)
- R20-F-07 (Block-Feature FR-SOCIAL-6)
- R20-F-24 (Push-Notifications)
- R3-F-08 (4m-Linie-Trainingsmodus)
- R7-F-06 (Filter Liga/Region/Verein)
- R15-F-01/F-02 (Runden-Clock-Subsystem FR-LIVE-5..-9, eigener M4.3-Sprint)
- R15-F-04 + R8-F-04 (Co-Veranstalter/Helper-Rollen-Modell — eigener Architect-Sprint)
- R23-tail (R17-F-25, R18-F-24, R19-F-25, R20-F-25 — Sammelposten-Cleanups)

### Owner-Eskalationen aus dem Sweep

1. **Gruppen-Feature** (R20-F-01 / R19-F-03 / Mängel #2.1) — Optionen:
   - A) Entfernen + Migration in Teams
   - B) Semantisch trennen mit eigener Spec + ADR (Buddy/Chat-Modell)
   - C) Status quo (nicht haltbar, dritter Re-Hit)
   - **Empfehlung**: A.
2. **Captain-Rolle in Teams** (R19-F-11) — ADR-0018 verbietet, Roadmap-Notiz nennt — entweder ADR-Revision oder Roadmap-Streichung.
3. **Avatar Upload vs. Initial+Color** (R2-F-09) — Spec §8 mehrdeutig, ADR fehlt. Optionen: A) Initial+Color als MVP bestätigen, B) Upload als Post-M5-Backlog deklarieren.
4. **Profil-Setup-Felder** (R2-F-07) — Heimatverein/Land/Avatar fehlen, eigener Spec-Schritt nötig.
5. **Privacy-Visibility-Model** (R2-F-08 / R20-F-02) — ADR + RLS-Policy für `{public, friends_only, private}`.
6. **Berechtigungsmatrix `user_roles`** (R1-F-04) — Sprint-Story-Entscheid: jetzt mit Tournament-Polish oder erst Post-M5.
7. **Anon-RLS-Strategie** (R14-F-01) — `anon`-Rolle vs. `authenticated-anonymous`. Entscheidung steht in einem eigenen ADR aus.
8. **Heli-Semantik in Sniper-HitRate** (R4-F-04) — Spec Q-9-(b) eindeutig, Code falsch. ADR-Annotation + Code-Fix.
9. **Realtime-vs-Polling-Default** (R15/R16 + ADR-0021) — Cost-Mitigation-Strategie für virale Public-Tournaments.
10. **Match-Mode-Phase-2-Doc-Drift** (R20-F-20) — ADR-0012 sagt deferred, Code live. ADR-Update fällig.

### Statistik

- **Total Final-Findings**: 420 (aus ca. 850 Hunter-Findings, ~50% Konsolidierungs-Rate)
- **Severity-Verteilung** (geschätzt aus Runden-Tabellen):
  - **P0**: 104 (~25%)
  - **P1**: 168 (~40%)
  - **P2**: 105 (~25%)
  - **P3**: 43 (~10%)
- **Verstärkungs-Pattern**: 23 systematische Re-Hits über mehrere Runden identifiziert (Toter-Brief 4×, Race-Conditions 6×, Display-Name 4×, Provider-Invalidate 5×, BackButton 3×, Polling-Lifecycle 3×, Mängel-Report-Halbfixes 3×).
- **Mängel-Report 2026-05-25 Punkte abgedeckt**: 9 von 9 identifiziert (alle in Runden 2/3/18/19/20 bestätigt), davon 2 vollständig gefixt (Teilfix Mängel #3 zählt halb), 7 offen.
- **FAIL-Score über alle Runden**: 60 Hunter-Outputs gemeldet, 60 als FAIL gewertet (jeder Hunter findet so viele Probleme dass der stepValidator-Score < 5 ist — erwartetes Bild für eine ungetestete Pre-MVP-Surface).
- **Re-Hits aus offenen Decisions (OD-XX)**: OD-03 (Friends-Privacy) zweifach (R18 + R20), OD-08 (Pairing) noch nicht aktiv, OD-09 (Audit-Granularität) zweifach (R11 + R12), OD-10 (Anon-Organizer) Re-Hit in R20-F-06.

### Übergreifende Erkenntnis

Die App hat ein **konsistentes Pattern von "Schale ohne Tiefe"** — Features werden UI-seitig gebaut, aber kritische Backend-Anbindungen, Provider-Invalidates oder Domain-Edge-Cases fehlen. Vier strukturelle Lücken ziehen sich durch fast jede Runde: (1) Toter-Brief-Provider ohne Konsumenten, (2) Race-Conditions in jedem Notifier ohne Mutex/Idempotency-Guard, (3) Display-Name-Mapping konsequent vergessen, (4) Compliance-/DSGVO-Baseline nicht umgesetzt. Sprint A muss konsequent Funktionalität-First fahren — ohne R17-F-01/02 (Offline-Submitter + Score-Drafts) und R1-F-01..03 (Auth-Cache-Kette) ist kein Pitch-Einsatz möglich. Sprint C ist hart vom Owner-Entscheid R20-F-01 (Gruppen-Frage) abhängig — solange die ungeklärt ist, lohnt sich kein Social-Polish.
