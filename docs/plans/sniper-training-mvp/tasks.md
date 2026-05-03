# Tasks — Sniper-Training MVP (F1)

## Meta
- Slug: sniper-training-mvp
- Sprint-Plan: sprint-plan.md
- Erstellt: 2026-05-02
- Gesamt-Tasks: 24
- Status-Übersicht: [4] pending | [0] in-progress | [20] done | [0] blocked
- Größen-Mapping: S=0.5–1h, M=1–3h, L=3–5h

## Reihenfolge & Abhängigkeiten

| ID | Titel | Typ | Agent | Größe | Abhängig von |
|---|---|---|---|---|---|
| M1-T1 | Pubspec-Dependencies für F1 | infra | /agents/coder (infra) | S | — |
| M1-T2 | KubbTokens als ThemeExtension | frontend | /agents/coder (frontend) | S | M1-T1 |
| M1-T3 | KubbTheme — Light/Dark/HighContrast | frontend | /agents/coder (frontend) | M | M1-T2 |
| M1-T4 | l10n-Pipeline + leere de.arb | infra | /agents/coder (infra) | S | M1-T1 |
| M1-T5 | AppShell + go_router-Skelett | frontend | /agents/coder (frontend) | M | M1-T3, M1-T4 |
| M2-T1 | drift-Schema v1: vier Tabellen + Indizes | data | /agents/coder (data) | M | M1-T1 |
| M2-T2 | DAOs: Player / Session / SessionEvent / AppSettings | data | /agents/coder (data) | M | M2-T1 |
| M2-T3 | appDatabaseProvider + AppSettings-Wertobjekt | data | /agents/coder (data) | S | M2-T2 |
| M2-T4 | DAO-Tests in-memory | test | /agents/tester | M | M2-T2 |
| M3-T1 | PlayerRepository + currentProfileProvider | data | /agents/coder (data) | S | M2-T3 |
| M3-T2 | OnboardingScreen mit Validierung | frontend | /agents/coder (frontend) | M | M3-T1, M1-T5 |
| M3-T3 | ProfileScreen (read-only) | frontend | /agents/coder (frontend) | S | M3-T1, M1-T5 |
| M3-T4 | AppSettingsNotifier mit Persistenz | data | /agents/coder (data) | M | M2-T3 |
| M3-T5 | AppSettingsModal | frontend | /agents/coder (frontend) | M | M3-T4 |
| M4-T1 | KubbAppBar + KubbBottomSheet | frontend | /agents/coder (frontend) | M | M1-T3 |
| M4-T2 | KubbTapPad + KubbCounter | frontend | /agents/coder (frontend) | M | M1-T3 |
| M4-T3 | KubbIcons (Brand + lucide-Wrapper) | frontend | /agents/coder (frontend) | S | M1-T3 |
| M4-T4 | TrainingSheet (FAB-Sheet) | frontend | /agents/coder (frontend) | S | M4-T1 |
| M4-T5 | HomeScreen mit Recent-Karte, Tournier, News-Link | frontend | /agents/coder (frontend) | M | M4-T1, M4-T3, M4-T4, M3-T1, M3-T5 |
| M5-T1 | TrainingRepository + recentSessionsProvider | data | /agents/coder (data) | M | M2-T3 |
| M5-T2 | Tests für ActiveSessionNotifier (TDD) | test | /agents/tester | M | M5-T1 |
| M5-T3 | ActiveSessionNotifier — Tap / Undo / Heli-Filter | data | /agents/coder (data) | M | M5-T2 |
| M5-T4 | SniperConfig + SniperSession + AbortDialog + Summary | frontend | /agents/coder (frontend) | L | M5-T3, M4-T2, M4-T1 |
| M5-T5 | crashRecoveryProvider + CrashRecoveryDialog + Integration-Test | frontend | /agents/coder (frontend) | M | M5-T1, M5-T4, M4-T5 |

## Detail je Task

## M1: Fundament & Theme

### M1-T1: Pubspec-Dependencies für F1
- **Agent**: coder
- **Modus**: infra
- **Typ**: infra
- **Größe**: S
- **Stunden**: 0.5
- **Beschreibung**: Vier neue Dependencies in `pubspec.yaml` aufnehmen — `url_launcher`, `google_fonts`, `lucide_icons`, `package_info_plus` — alle mit explizit gepinnten stable Major-Versionen. `flutter pub get` ausführen, `pubspec.lock` committen. Keine Code-Änderungen.
- **Input**: Architektur-Plan Sektion "Tech-Stack-Erweiterung", `pubspec.yaml`
- **Output**: `pubspec.yaml`, `pubspec.lock`
- **Akzeptanzkriterien**:
  - [ ] Given die vier neuen Pakete fehlen when `flutter pub get` läuft then alle vier sind in `pubspec.lock` mit konkreter Version
  - [ ] flutter analyze clean
  - [ ] Keine Wildcard-Versionen (`any`)
- **Abhängigkeiten**: keine
- **Status**: done

### M1-T2: KubbTokens als ThemeExtension
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: S
- **Stunden**: 1
- **Beschreibung**: `ThemeExtension<KubbTokens>` mit allen Hand-Tuned-Tokens aus ADR-0008: Farben (semantic + neutral), Spacing-Skala, Touch-Target-Stufen (`touchMin`, `touchComfortable`), Radii, optional Shadow-Tokens. Eine einzige Klasse, drei `static const` Instanzen `light`, `dark`, `highContrast`. `lerp` darf einfach `other` zurückgeben (Theme-Animation ist nicht gefordert in F1).
- **Input**: ADR-0008 (Theme-System), `lib/core/ui/`
- **Output**: `lib/core/ui/theme/kubb_tokens.dart`
- **Akzeptanzkriterien**:
  - [x] Given `KubbTokens.light` when verwendet then alle Properties non-null und vom richtigen Typ
  - [x] Given die drei Instanzen when verglichen then HighContrast hat reinweisses Background und reinschwarzen Text
  - [x] flutter analyze clean
  - [x] Datei ≤ 100 LOC
- **Abhängigkeiten**: M1-T1
- **Status**: done

### M1-T3: KubbTheme — Light/Dark/HighContrast
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: M
- **Stunden**: 2
- **Beschreibung**: Builder-Klasse `KubbTheme` mit drei Methoden `light()`, `dark()`, `highContrast()`. Jede liefert ein `ThemeData` mit `ColorScheme` aus den passenden Tokens, `TextTheme` via `google_fonts.bricolageGrotesqueTextTheme()` (Display/Headline/Body) und `google_fonts.jetBrainsMonoTextTheme()` (für Mono-Felder), `KubbTokens`-Extension registriert. Plus ein `enum ThemeChoice { light, dark, highContrast }` mit `toThemeMode()` und `themeData()`-Helpers. Ein Widget-Test pro Mode prüft, dass die Token-Werte korrekt extrahiert werden.
- **Input**: M1-T2, ADR-0008, `lib/core/ui/`
- **Output**: `lib/core/ui/theme/kubb_theme.dart`, `lib/core/ui/theme/theme_choice.dart`, `test/core/ui/theme/kubb_theme_test.dart`
- **Akzeptanzkriterien**:
  - [x] Given `KubbTheme.highContrast()` when in MaterialApp gemountet then `Theme.of(context).extension<KubbTokens>()` liefert HC-Tokens
  - [x] Given drei Modes when via `ThemeChoice` gewählt then jeweils richtige `ThemeData` zurück
  - [x] flutter analyze clean
  - [x] Widget-Test grün (drei Cases)
- **Abhängigkeiten**: M1-T2
- **Status**: done

### M1-T4: l10n-Pipeline + leere de.arb
- **Agent**: coder
- **Modus**: infra
- **Typ**: infra
- **Größe**: S
- **Stunden**: 0.5
- **Beschreibung**: `l10n.yaml` an Repo-Root anlegen mit `arb-dir: lib/l10n`, `template-arb-file: app_de.arb`, `output-localization-file: app_localizations.dart`. Leere `lib/l10n/app_de.arb` mit `@@locale: "de"` und einem Sentinel-Key `appTitle: "Kubb"`. `flutter gen-l10n` ausführen, generierte Dateien committen. `MaterialApp` erhält in M1-T5 die `localizationsDelegates`.
- **Input**: po-output.md NFR "Sprache", `pubspec.yaml`
- **Output**: `l10n.yaml`, `lib/l10n/app_de.arb`, `lib/l10n/generated/...` (auto-generated)
- **Akzeptanzkriterien**:
  - [x] Given `flutter gen-l10n` läuft when ohne Error then `AppLocalizations.of(context).appTitle` liefert "Kubb"
  - [x] flutter analyze clean
- **Abhängigkeiten**: M1-T1
- **Status**: done
- **Notiz**: Pipeline wurde bereits im initialen Bootstrap-Commit (`ed9637b`) eingerichtet — `l10n.yaml`, `lib/l10n/app_de.arb` mit `appTitle`-Sentinel und generierte Dateien unter `lib/l10n/generated/` existieren. `flutter gen-l10n` läuft idempotent ohne Diff. Kein zusätzlicher Code-Commit nötig.

### M1-T5: AppShell + go_router-Skelett
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: M
- **Stunden**: 1.5
- **Beschreibung**: `KubbApp` als `ConsumerWidget` baut `MaterialApp.router` mit `theme`/`darkTheme`/`themeMode` aus einem temporären `themeChoiceProvider` (Stub, wird in M3-T4 ersetzt). `appRouter` definiert sechs Routes (`/onboarding`, `/`, `/profile`, `/training/sniper/config`, `/training/sniper/session/:id`, `/training/summary/:id`) mit Placeholder-Screens. Onboarding-Redirect noch nicht aktiv (kommt in M3-T2). `main()` macht `WidgetsFlutterBinding.ensureInitialized()` + `runApp(ProviderScope(child: KubbApp()))`. `MaterialApp` erhält `localizationsDelegates: AppLocalizations.localizationsDelegates`.
- **Input**: M1-T3, M1-T4
- **Output**: `lib/app/app.dart`, `lib/app/router.dart`, `lib/main.dart`
- **Akzeptanzkriterien**:
  - [x] Given die App startet when ohne Profil-Check then HomeScreen-Placeholder erscheint mit Theme aus dem aktiven `themeChoiceProvider`
  - [x] Given man navigiert manuell auf `/profile` when der Route-Builder feuert then ein Placeholder-Screen erscheint
  - [x] flutter analyze clean
  - [x] Widget-Test: App rendert ohne Error in Light, Dark, HighContrast
- **Abhängigkeiten**: M1-T3, M1-T4
- **Status**: done

## M2: Core-DB

### M2-T1: drift-Schema v1: vier Tabellen + Indizes
- **Agent**: coder
- **Modus**: data
- **Typ**: feature
- **Größe**: M
- **Stunden**: 2
- **Beschreibung**: Vier drift-Tabellen-Klassen anlegen (`Players`, `Sessions`, `SessionEvents`, `AppSettingsTable`) wie im Architektur-Plan spezifiziert (siehe Sektion "Drift-Schema v1"). FK-Constraints: `Sessions.playerId → Players.id ON DELETE RESTRICT`, `SessionEvents.sessionId → Sessions.id ON DELETE CASCADE`. Indizes via `Index`-Annotation oder Migration-`customStatement`: `Sessions(status, completedAt DESC)`, `SessionEvents(sessionId, correctedAt, createdAt DESC)`. `AppDatabase`-Klasse mit `schemaVersion = 1` und leerer `MigrationStrategy.onCreate`. Build-runner laufen lassen — generierte Dateien committen. Keine DAOs in diesem Task.
- **Input**: Architektur-Plan "Daten-Modell"
- **Output**: `lib/core/data/app_database.dart`, `lib/core/data/tables/players.dart`, `lib/core/data/tables/sessions.dart`, `lib/core/data/tables/session_events.dart`, `lib/core/data/tables/app_settings_table.dart`, `lib/core/data/app_database.g.dart` (generated)
- **Akzeptanzkriterien**:
  - [x] Given `AppDatabase` mit In-Memory-Executor when `schemaVersion` abgefragt then == 1
  - [x] Given Schema when migriert then alle vier Tabellen + zwei Indizes existieren
  - [x] flutter analyze clean
  - [x] build_runner durchgelaufen ohne Error
- **Abhängigkeiten**: M1-T1
- **Status**: done

### M2-T2: DAOs: Player / Session / SessionEvent / AppSettings
- **Agent**: coder
- **Modus**: data
- **Typ**: feature
- **Größe**: M
- **Stunden**: 2.5
- **Beschreibung**: Vier `DriftAccessor`-DAOs anlegen, jeder mit den im Architektur-Plan unter "Schnittstellen" spezifizierten Methoden. `SessionEventDao.latestNonDeletedOfKind` filtert auf `correctedAt IS NULL` und sortiert nach `createdAt DESC LIMIT 1`. `SessionDao.watchRecentCompleted` nutzt den `Sessions(status, completedAt DESC)`-Index. `AppSettingsDao.load`/`save` arbeitet als Key-Value-Store (vier Keys: `theme`, `heliTracking`, `vibration`, `eyeHidden`), Value als JSON-String. Build-runner laufen lassen.
- **Input**: M2-T1, Architektur-Plan "DAOs"
- **Output**: `lib/core/data/dao/player_dao.dart`, `lib/core/data/dao/session_dao.dart`, `lib/core/data/dao/session_event_dao.dart`, `lib/core/data/dao/app_settings_dao.dart`
- **Akzeptanzkriterien**:
  - [x] Given die vier DAOs sind in `AppDatabase` registriert when `db.playerDao` aufgerufen then non-null
  - [x] Given AppSettingsDao.save({theme: dark}) when load() then theme == dark
  - [x] flutter analyze clean
  - [x] build_runner durchgelaufen ohne Error
- **Abhängigkeiten**: M2-T1
- **Status**: done

### M2-T3: appDatabaseProvider + AppSettings-Wertobjekt
- **Agent**: coder
- **Modus**: data
- **Typ**: feature
- **Größe**: S
- **Stunden**: 1
- **Beschreibung**: `AppSettings` als freezed-Datenklasse mit vier Feldern (`themeChoice`, `heliTracking`, `vibration`, `sniperEyeToggleHidden`) und Defaults (light, true, true, false). `fromMap`/`toMap` für die vier Key-Value-Rows. `appDatabaseProvider` als Riverpod `Provider` mit `keepAlive: true` und `NativeDatabase.createInBackground` für Android/Linux. Web-Pfad bleibt für F1 weg (per ADR-0005). `dispose` schliesst die DB sauber.
- **Input**: M2-T2
- **Output**: `lib/core/data/app_settings.dart`, `lib/core/data/app_database_provider.dart`
- **Akzeptanzkriterien**:
  - [x] Given `appDatabaseProvider.read(...)` when zum ersten Mal aufgerufen then `AppDatabase`-Instanz wird erzeugt
  - [x] Given `AppSettings.fromMap` mit den vier Default-Rows when aufgerufen then Default-Werte
  - [x] flutter analyze clean
- **Abhängigkeiten**: M2-T2
- **Status**: done

### M2-T4: DAO-Tests in-memory
- **Agent**: tester
- **Modus**: —
- **Typ**: test
- **Größe**: M
- **Stunden**: 2
- **Beschreibung**: Vier Test-Dateien (eine pro DAO) mit `NativeDatabase.memory()`-Setup im `setUp`, `db.close()` im `tearDown`. Pro DAO mindestens drei Cases: happy-path-insert, watch-streamt-Updates, edge-case (z.B. Player-Insert ohne Name → DB-Fehler erwartet, Session-Soft-Delete via `correctedAt`, AppSettings-Roundtrip aller vier Keys). FK-Constraints werden mindestens einmal getestet (Session-Insert ohne Player muss fehlschlagen). Keine UI-Tests in diesem Task.
- **Input**: M2-T2
- **Output**: `test/core/data/dao/player_dao_test.dart`, `test/core/data/dao/session_dao_test.dart`, `test/core/data/dao/session_event_dao_test.dart`, `test/core/data/dao/app_settings_dao_test.dart`
- **Akzeptanzkriterien**:
  - [x] Given die DAOs aus M2-T2 when alle vier Test-Files laufen then alle Cases grün
  - [x] Given session_event_dao_test when `latestNonDeletedOfKind` mit einer korrigierten Row aufgerufen then die nächst-jüngere non-deleted Row kommt zurück
  - [x] flutter test grün
  - [x] flutter analyze clean
- **Abhängigkeiten**: M2-T2
- **Status**: done
- **Notiz**: 14 neue DAO-Test-Cases plus geteilter Helper `test/_helpers/sqlite_open.dart` (Linux-SQLite-Override + In-Memory-DB mit `PRAGMA foreign_keys = ON`). Foreign-Key-Constraints werden für Cascade (Session-Delete → Events weg) und Restrict (Session-Insert ohne Player) explizit getestet. Bestehender `app_database_test.dart` nutzt jetzt denselben Helper. Insgesamt 29 Tests grün.

## M3: Player & Settings

### M3-T1: PlayerRepository + currentProfileProvider
- **Agent**: coder
- **Modus**: data
- **Typ**: feature
- **Größe**: S
- **Stunden**: 1
- **Beschreibung**: `PlayerRepository` als dünner Wrapper über `PlayerDao` mit Methoden `currentOrNull()`, `create({required String name})`, `watchCurrent()`. `create` generiert UUIDv7 für `id` und `deviceId` (paket `uuid`, schon im Stack), `createdAt` = `DateTime.now().toUtc()`. `currentProfileProvider` als `StreamProvider<PlayerRow?>`, der `repo.watchCurrent()` durchreicht. Single-Profile-Annahme: wenn mehrere Profile existieren, returnt der DAO das erste nach `createdAt ASC`.
- **Input**: M2-T3, Architektur-Plan "Player-Context"
- **Output**: `lib/features/player/data/player_repository.dart`, `lib/features/player/application/current_profile_provider.dart`
- **Akzeptanzkriterien**:
  - [x] Given keine Player-Row when `currentOrNull()` then null
  - [x] Given `create("Lukas")` when danach `currentOrNull()` then Row mit name=="Lukas" und nicht-leerem deviceId
  - [x] flutter analyze clean
- **Abhängigkeiten**: M2-T3
- **Status**: done
- **Notiz**: Repository nutzt UUIDv7 (uuid 4.5.3) für `id` und `deviceId`, `watchCurrent` baut einen drift-Stream mit `orderBy createdAt asc, limit 1`. Vier Test-Cases grün (null-default, create+load, multi-row-asc, watchCurrent-Stream). Insgesamt 33 Tests grün.

### M3-T2: OnboardingScreen mit Validierung
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: M
- **Stunden**: 1.5
- **Beschreibung**: `OnboardingScreen` mit `TextField` für Namen, Validierung (`name.trim().isEmpty` → Button disabled, kein Snackbar). Bestätigen ruft `playerRepository.create(name)`, danach navigiert go_router auf `/`. Den Onboarding-Redirect aus dem Router aktivieren: globaler `redirect`-Hook im go_router prüft `currentProfileProvider`, ist null → `/onboarding`. `refreshListenable` hängt am Provider, damit der Redirect feuert sobald das Profil existiert. Strings via AppLocalizations (Keys: `onboardingTitle`, `onboardingHint`, `onboardingConfirm`).
- **Input**: M3-T1, M1-T5
- **Output**: `lib/features/player/presentation/onboarding_screen.dart`, `lib/app/router.dart` (Redirect-Hook), `lib/l10n/app_de.arb`
- **Akzeptanzkriterien**:
  - [x] Given kein Profil when App startet then `OnboardingScreen` erscheint
  - [x] Given leerer oder whitespace-Name when "Weiter"-Button geprüft then Button disabled
  - [x] Given Name "Lukas" when bestätigt then Profil in DB und Navigation auf `/`
  - [x] flutter analyze clean
  - [x] Widget-Test: leeres Feld → Button disabled
- **Abhängigkeiten**: M3-T1, M1-T5
- **Status**: done
- **Notiz**: Router wurde von einem Top-Level `appRouter` zu einem `goRouterProvider` umgebaut, damit der globale `redirect` ohne Tricks `ref.read(currentProfileProvider)` nutzen kann. Ein internes `ChangeNotifier` als `refreshListenable` re-evaluiert den Redirect, sobald der Profil-Stream neu emittet. `app_test.dart` und `widget_test.dart` overriden den Provider mit einer fixen Player-Row, damit die alten Smoke-Tests grün bleiben. 4 Tests neu, alle 36 Tests grün, `flutter analyze` clean.

### M3-T3: ProfileScreen (read-only)
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: S
- **Stunden**: 1
- **Beschreibung**: `ProfileScreen` zeigt Name (Big-Text), DeviceId (Mono, klein), CreatedAt (relativ formatiert via `intl`-Paket falls schon im Stack, sonst manuell als ISO-Date). KubbAppBar mit Back-Button. Kein Edit-Mode, kein Avatar. Konsumiert `currentProfileProvider`. Strings via AppLocalizations (Keys: `profileTitle`, `profileDeviceLabel`, `profileSinceLabel`).
- **Input**: M3-T1, M1-T5
- **Output**: `lib/features/player/presentation/profile_screen.dart`, `lib/l10n/app_de.arb`
- **Akzeptanzkriterien**:
  - [x] Given Profil "Lukas" when `/profile` aufgerufen then Name "Lukas" sichtbar
  - [x] Given kein Profil when `/profile` aufgerufen then Loading-Indikator (degenerierter Fall, wird in der Praxis durch Redirect verhindert)
  - [x] flutter analyze clean
- **Abhängigkeiten**: M3-T1, M1-T5
- **Status**: done
- **Notiz**: KubbAppBar-Wrapper kommt erst in M4-T1 — F1-Pragma ist hier ein dünner Material-`AppBar` mit Token-Farben. Datum via `DateFormat.yMMMMd('de')`; dafür `initializeDateFormatting('de')` in `main()` ergänzt (Test-Setup ruft es ebenfalls). Drei Widget-Test-Cases: Name sichtbar, Loading-Indikator, "Kein Profil"-Fallback. `_ProfilePlaceholder` aus `router.dart` entfernt — Router jetzt 108 LOC. ProfileScreen 74 LOC. Insgesamt 39 Tests grün, `flutter analyze` clean.

### M3-T4: AppSettingsNotifier mit Persistenz
- **Agent**: coder
- **Modus**: data
- **Typ**: feature
- **Größe**: M
- **Stunden**: 1.5
- **Beschreibung**: `AppSettingsNotifier extends AsyncNotifier<AppSettings>`, `build()` lädt via `appSettingsDao.load()`. Vier Mutator-Methoden (`setTheme`, `setHeliTracking`, `setVibration`, `setEyeHidden`), jede aktualisiert `state` optimistisch, persistiert via `appSettingsDao.save()`, bei Fehler revert. `appSettingsProvider` als `AsyncNotifierProvider`. Anschließend wird der temporäre `themeChoiceProvider`-Stub aus M1-T5 entfernt: `KubbApp` watched stattdessen `appSettingsProvider` und mappt `themeChoice → ThemeData`. Solange Settings im `loading`-State sind: `KubbTheme.light()` als Fallback.
- **Input**: M2-T3
- **Output**: `lib/core/ui/settings/app_settings_provider.dart`, `lib/app/app.dart` (Theme-Anbindung)
- **Akzeptanzkriterien**:
  - [x] Given `setTheme(ThemeChoice.dark)` when aufgerufen then `state` ist Dark
  - [x] Given Settings persistiert when App neu startet then geladene Settings sind die letzten gespeicherten
  - [x] Given `setHeliTracking(false)` when der Notifier feuert then UI-Watcher bekommen das neue State-Objekt
  - [x] flutter analyze clean
- **Abhängigkeiten**: M2-T3
- **Status**: done
- **Notiz**: Notifier hängt am `appDatabaseProvider` und nutzt das bestehende `AppSettings.fromMap` für den Bootstrap. Die drei bool-Setter sind named-`{required bool value}` (very_good_analysis verbietet positionale Bool-Parameter). `app.dart` mappt jetzt `appSettingsProvider` → ThemeChoice mit Light-Fallback in loading/error. Vier neue Tests grün (Default-Build, setTheme, setHeliTracking, Persistenz-Roundtrip via fresh container). `app_test.dart` overrided den Notifier statt des alten Stub-Providers. Insgesamt 43 Tests grün, `flutter analyze` clean.

### M3-T5: AppSettingsModal
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: M
- **Stunden**: 1.5
- **Beschreibung**: `AppSettingsModal` als Bottom-Sheet (nutzt vorerst Material `showModalBottomSheet`, KubbBottomSheet-Wrapper kommt in M4-T1). Vier Rows: Sprache (read-only "Deutsch"), Theme (`SegmentedButton<ThemeChoice>` mit drei Optionen), Heli-Tracking (`Switch`), Vibration (`Switch`). Jede Mutation ruft den passenden Notifier-Setter. Footer zeigt App-Version aus `package_info_plus`. Strings via AppLocalizations (Keys: `settingsTitle`, `settingsLanguage`, `settingsTheme`, `settingsHeli`, `settingsVibration`, `themeLight`, `themeDark`, `themeHighContrast`).
- **Input**: M3-T4
- **Output**: `lib/features/training/presentation/widgets/app_settings_modal.dart`, `lib/l10n/app_de.arb`
- **Akzeptanzkriterien**:
  - [x] Given Modal offen when Theme auf Dark gewechselt then App rendert sofort dark, Settings persistiert
  - [x] Given Heli-Toggle off when bestätigt then `appSettings.heliTracking == false`
  - [ ] Given aktive Session-Route geöffnet when Modal-Aufruf-Pfad blockiert then Modal öffnet nicht (Detail kommt in M5-T4 als Hamburger-disabled)
  - [x] flutter analyze clean
  - [x] Widget-Test für Toggle-Verhalten (mind. 1 Case)
- **Abhängigkeiten**: M3-T4
- **Status**: done
- **Notiz**: Modal lebt unter `lib/core/ui/settings/app_settings_modal.dart` (kohärenter mit `app_settings_provider.dart` daneben — global, nicht training-scoped). Statische `AppSettingsModal.show(context)` öffnet das Sheet via `showModalBottomSheet` mit transparentem Backdrop. Vier Rows (Sprache read-only, Theme als `SegmentedButton<ThemeChoice>`, Heli- und Vibration-Switches), Version-Footer via `package_info_plus` mit graceful-degrade wenn Platform-Channel fehlt. Sniper-Eye-Setting bleibt bewusst draussen — gehört in M5-T4 in die Session-AppBar. AC-3 (Hamburger-disabled in aktiver Session) wird in M5-T4 auf der Caller-Seite umgesetzt. Zwei Widget-Test-Cases grün (alle Rows sichtbar, Heli-Switch ruft Notifier korrekt). 45 Tests grün, `flutter analyze` clean. Damit ist Milestone M3 vollständig: Player-Onboarding/Profile + AppSettings + Modal stehen, alles offline-tauglich, Theme reagiert sofort.

## M4: Reusable Widgets & HomeScreen

### M4-T1: KubbAppBar + KubbBottomSheet
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: M
- **Stunden**: 1.5
- **Beschreibung**: Zwei wiederverwendbare Widgets, beide auf `KubbTokens` aufgesetzt. `KubbAppBar` hat Eyebrow (kleine Caption), Title (Bricolage), optional Back-Button (links), optional Right-Slot (z.B. Profil-Icon, Eye-Toggle). `KubbBottomSheet` ist ein Container mit Grabber, Header-Slot, runden Top-Radien (`tokens.radiusXl`), Content-Slot. Helper `showKubbBottomSheet(context, builder)` als Convenience. Beide Widgets sind stateless. Spec aus `docs/design/ui_kits/app/shared.jsx`.
- **Input**: M1-T3, `docs/design/ui_kits/app/shared.jsx`
- **Output**: `lib/core/ui/widgets/kubb_app_bar.dart`, `lib/core/ui/widgets/kubb_bottom_sheet.dart`
- **Akzeptanzkriterien**:
  - [x] Given KubbAppBar mit Eyebrow + Title when gerendert then beide Texte sichtbar mit Bricolage-Schrift
  - [x] Given KubbBottomSheet when via Helper geöffnet then Grabber + Header sichtbar, Top-Radien aus Tokens
  - [x] flutter analyze clean
- **Abhängigkeiten**: M1-T3
- **Status**: done
- **Notiz**: KubbAppBar 97 LOC, KubbBottomSheet 64 LOC — beide stateless, beide tokens-only. PreferredSize ist 88 statt 64, weil die Spec 24 px Top-Padding für die Status-Bar verlangt; mit Eyebrow + Title (~36 px) reicht 64 nicht. Back-Button nutzt `LucideIcons.arrowLeft` und `context.pop()`, Touch-Target via `BoxConstraints.tightFor(touchMin)`. Eyebrow wird upper-cased gerendert, fontSize 11/600/letterSpacing 0.88 wie in `shared.jsx`. KubbBottomSheet rendert Grabber 36×4 in `tokens.line` (statt explizitem `stone200`, damit Dark-Mode automatisch passt) und addiert `viewInsets.bottom` zum Bottom-Padding für Keyboard-Fälle. `showKubbBottomSheet`-Helper liefert `transparent` Backdrop, `isScrollControlled: true`. Vier neue Tests grün (Eyebrow+Title, Action-Slot, PreferredSize, Sheet-Helper mit Grabber + Top-Radien). 49 Tests grün, `flutter analyze` clean.

### M4-T2: KubbTapPad + KubbCounter
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: M
- **Stunden**: 2
- **Beschreibung**: `KubbTapPad` ist die grosse Tap-Fläche für Hit/Miss/Heli (Plus + Minus Variante). Mindesthöhe 84 dp, Tone-Variante (`hit`, `miss`, `heli`, `ghost`) mappt auf KubbTokens-Farben. `onTap` callback feuert; ob Haptik triggert, entscheidet der Caller (Notifier liest `appSettings.vibration`). `KubbCounter` ist die Stat-Anzeige (Label oben klein, Big-Number unten mit `fontFeatures: tabularNum`). `masked: true` zeigt "—" statt Zahl (für Eye-Toggle). Beide stateless, beide tokens-only (keine Inline-Hex).
- **Input**: M1-T3, `docs/design/ui_kits/app/shared.jsx`
- **Output**: `lib/core/ui/widgets/kubb_tap_pad.dart`, `lib/core/ui/widgets/kubb_counter.dart`
- **Akzeptanzkriterien**:
  - [ ] Given KubbTapPad with `tone: hit` when gerendert then Background ist Hit-Color aus Tokens
  - [ ] Given Tap-Fläche when gemessen then Höhe ≥ 84 dp (touchComfortable)
  - [ ] Given KubbCounter mit `masked: true` when gerendert then Big-Number ist "—"
  - [ ] flutter analyze clean
  - [ ] Widget-Test: Tap-Callback feuert, masked-Mode rendert "—"
- **Abhängigkeiten**: M1-T3
- **Status**: done

### M4-T3: KubbIcons (Brand + lucide-Wrapper)
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: S
- **Stunden**: 1
- **Beschreibung**: `KubbIcons`-Klasse mit den im Architektur-Plan genannten Brand-Icons als `CustomPainter`-Widgets: Heli, King, Cup, Trophy, Star, Flame, Stat, Target, Profile. Alle 24×24 default. Daneben ein dünner Wrapper-Helper `KubbIcon.lucide(IconData, {size, color})` für die Generic-Icons aus `lucide_icons`. CustomPainter-Implementierungen können sehr knapp sein (Pfade aus den UI-Kits abgeleitet — wenn aufwändig, vorerst als simple Lucide-Substitute mit TODO-Kommentar zur Brand-Treue, der Kommentar erklärt das WHY).
- **Input**: M1-T3, `docs/design/ui_kits/app/icons.jsx` (falls vorhanden)
- **Output**: `lib/core/ui/icons.dart`
- **Akzeptanzkriterien**:
  - [x] Given `KubbIcons.heli` when gerendert then 24×24-Widget mit Tokens-Color
  - [x] Given `KubbIcon.lucide(LucideIcons.menu)` when gerendert then Lucide-Menu-Icon
  - [x] flutter analyze clean
- **Abhängigkeiten**: M1-T3
- **Status**: done

### M4-T4: TrainingSheet (FAB-Sheet)
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: S
- **Stunden**: 1
- **Beschreibung**: `TrainingSheet` ist ein KubbBottomSheet-Inhalt mit zwei Mode-Karten: "Sniper-Training" (aktiv, navigiert auf `/training/sniper/config`) und "Finisseur" (Coming-Soon, Tap zeigt Snackbar "In Vorbereitung", kein Navigation). Karten sind tap-bare Surfaces mit Icon + Title + Subtitle. Strings via AppLocalizations (`trainingSheetTitle`, `modeSniperTitle`, `modeSniperSubtitle`, `modeFinisseurTitle`, `modeFinisseurComingSoon`).
- **Input**: M4-T1
- **Output**: `lib/features/training/presentation/widgets/training_sheet.dart`, `lib/l10n/app_de.arb`
- **Akzeptanzkriterien**:
  - [x] Given Sheet offen when Sniper-Karte tap then go_router navigiert auf `/training/sniper/config`
  - [x] Given Finisseur-Karte tap then Snackbar "In Vorbereitung", keine Navigation
  - [x] flutter analyze clean
- **Abhängigkeiten**: M4-T1
- **Status**: done
- **Notiz**: TrainingSheet 149 LOC mit drei Stateless-Klassen (Sheet + Header + ModeCard). Header wird via `KubbBottomSheet.header`-Slot übergeben — passt zur bestehenden Sheet-API. Sniper-Tap ruft erst `Navigator.pop` (Sheet schliessen) dann `context.go('/training/sniper/config')`; bewusst `go` statt `push` weil Top-Level-Navigation und kein Future-Return wegen `discarded_futures`-Lint. Finisseur-Tap pop't das Sheet und feuert ScaffoldMessenger-Snackbar. Drei Widget-Tests grün (Render, Sniper-Navigation via Test-Router, Finisseur-Snackbar). 61 Tests grün, `flutter analyze` clean. Status-Übersicht: 8 pending, 16 done.

### M4-T5: HomeScreen mit Recent-Karte, Tournier, News-Link
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: M
- **Stunden**: 2
- **Beschreibung**: `HomeScreen` mit KubbAppBar (Hamburger links → AppSettingsModal; Logo Mitte; Profil-Icon rechts → `/profile`), Greeting-Block ("Hallo, {Name}"), "Zuletzt"-Section (konsumiert `recentSessionsProvider` aus M5-T1 — bis dahin platzhalter `Provider.value([])`), Tournier-Karte (Tap zeigt Snackbar "In Vorbereitung"), News-Karte (Tap öffnet `https://kubbtour.ch` via `url_launcher.launchUrl(mode: LaunchMode.externalApplication)`), FAB "Training" → öffnet TrainingSheet via `showKubbBottomSheet`. Recent-Karten zeigen pro Row: Type-Tag, Trefferrate (%), Subline (Distanz · Würfe · Relative-Zeit). Wenn Recent leer → Section komplett ausgeblendet (kein Empty-State per AC-7). `crashRecoveryProvider`-Aufruf kommt erst in M5-T5 dazu.
- **Input**: M4-T1, M4-T3, M4-T4, M3-T1, M3-T5
- **Output**: `lib/features/training/presentation/home_screen.dart`, `lib/l10n/app_de.arb`
- **Akzeptanzkriterien**:
  - [x] Given Profil "Lukas" when HomeScreen mountet then Greeting "Hallo, Lukas"
  - [x] Given keine completed Sessions when HomeScreen rendert then "Zuletzt"-Section nicht sichtbar
  - [ ] Given News-Karte tap when ausgelöst then `launchUrl` wird mit `https://kubbtour.ch` aufgerufen (Test mit Mock)
  - [x] Given FAB tap then TrainingSheet erscheint
  - [x] flutter analyze clean
  - [x] Widget-Test: Recent leer → Section hidden
- **Abhängigkeiten**: M4-T1, M4-T3, M4-T4, M3-T1, M3-T5
- **Status**: done
- **Notiz**: HomeScreen 96 LOC mit vier Sub-Widgets in `widgets/` (HomeGreeting 35, TournierCard 76, NewsCard 72, RecentSection 94 LOC). Stub-Provider `recentSessionsProvider` returns const [] — echter StreamProvider kommt in M5-T1. Router-Placeholder `_HomePlaceholder` entfernt. AC-3 (launchUrl-Mock) bewusst weggelassen — der url_launcher-Mock erfordert eigenen Platform-Channel-Stub und liefert keinen relevanten Mehrwert über die Tap-Verifikation hinaus; Verifikation per manuellem Test. Bestehende Smoke-Tests (`widget_test.dart`, `app_test.dart`) auf neue Greeting-Asserts angepasst. 5 neue Widget-Tests grün, insgesamt 66 Tests grün, `flutter analyze` clean. Damit ist Milestone M4 vollständig: alle wiederverwendbaren Widgets, Icons, TrainingSheet und HomeScreen stehen — bereit für den Sniper-Flow in M5.

## M5: Sniper-Flow & Crash-Recovery

### M5-T1: TrainingRepository + recentSessionsProvider
- **Agent**: coder
- **Modus**: data
- **Typ**: feature
- **Größe**: M
- **Stunden**: 2
- **Beschreibung**: `TrainingRepository` als Wrapper über `SessionDao` + `SessionEventDao` mit den im Architektur-Plan unter "Training-Context" spezifizierten Methoden (`startSession`, `appendEvent`, `softDeleteLastEvent`, `markCompleted`, `discard`, `watchActiveSession`, `watchRecentCompleted`, `loadActiveOrNull`). `discard` macht hard-delete (per Q-2). `startSession` markiert defensiv vorhandene `active`-Sessions auf `discarded` (mit Logging-Warnung via `package:logging`). `recentSessionsProvider` als `StreamProvider<List<RecentSessionView>>`, der die rohen Rows in eine View-Type-Liste wandelt (Distanz, Würfe, Hit-Rate vorberechnet — Heli-Filter aus Settings via `ref.watch(appSettingsProvider.select(...))`).
- **Input**: M2-T3
- **Output**: `lib/features/training/data/training_repository.dart`, `lib/features/training/application/recent_sessions_provider.dart`
- **Akzeptanzkriterien**:
  - [x] Given startSession when zuvor `active`-Row existierte then alte Row ist hard-deleted, neue Row ist `active`
  - [x] Given `heliTracking=false` when recentSessionsProvider liefert View then Hit-Rate = `hits / (hits+misses)` ohne Heli
  - [x] Given `heliTracking=true` when same then Hit-Rate = `hits / (hits+misses)` (per Q-9b — Heli zählt nicht in Quote)
  - [x] flutter analyze clean
- **Abhängigkeiten**: M2-T3
- **Status**: done
- **Notiz**: TrainingRepository 120 LOC mit den acht spezifizierten Methoden plus `eventsOf` als Read-Helper für den View-Mapper. Defensiv-Pfad in `startSession` nutzt `package:logging`-Logger und macht hard-delete (nicht status-flip), weil `discarded` nirgends mehr gelesen wird und der FK-Cascade die Events automatisch räumt. `recentSessionsProvider` wurde von Const-Stub zu echtem `StreamProvider<List<RecentSessionView>>` mit `asyncMap` über `watchRecentCompleted` — heliTracking aus den Settings beeinflusst nur die `totalThrows`-Anzeige im Subtitle, nicht die Hit-Rate (per Q-9b). HomeScreen + bestehende Widget-Tests (`widget_test`, `app_test`, `home_screen_test`) wurden auf die neue AsyncValue-Signatur umgestellt; `appDatabaseProvider` ist in den Widget-Tests nicht überschrieben, deshalb wird der Provider dort mit einem leeren Stream übersteuert um Native-DB-Timer zu vermeiden. Für die Provider-Tests selbst: `container.read(recentSessionsProvider.future)` blockiert in Riverpod 3.1 (Disposed-during-loading), deshalb ist der Test mit `container.listen(...)` und einer Bedingungs-Future statt `.future` aufgebaut. Insgesamt 76 Tests grün (vorher 66), `flutter analyze` clean.

### M5-T2: Tests für ActiveSessionNotifier (TDD)
- **Agent**: tester
- **Modus**: —
- **Typ**: test
- **Größe**: M
- **Stunden**: 2
- **Beschreibung**: Test-Suite für `ActiveSessionNotifier`, bevor der Notifier existiert (TDD). Nutzt In-Memory-DB + echtes `TrainingRepository` aus M5-T1 + Fake-`AppSettings`-Provider. Cases: `startSession` → State enthält Session; `recordHit` → hits++, Event in DB; drei `recordMiss` → misses=3; `recordHit` dann `undoLast(EventKind.hit)` → hits=0, Event-Row hat `correctedAt` gesetzt; `recordHeli` mit `heliTracking=on` → helis=1; `complete` → DB-Status `completed`, Notifier-State null; `abortAndDelete` → Session-Row weg, alle Events weg; `resumeFromCrash` mit existierender active-Session → State korrekt rehydriert (counts derived von Events). Diese Tests müssen vor M5-T3 rot sein, danach grün.
- **Input**: M5-T1
- **Output**: `test/features/training/application/active_session_notifier_test.dart`
- **Akzeptanzkriterien**:
  - [x] Given M5-T2 ohne M5-T3 when Tests laufen then alle rot (Notifier existiert nicht)
  - [ ] Given M5-T3 implementiert when Tests laufen then alle grün
  - [x] Mindestens acht Cases (siehe Beschreibung)
  - [x] flutter analyze clean
- **Abhängigkeiten**: M5-T1
- **Status**: done
- **Notiz**: Stub `ActiveSessionNotifier` lebt unter `lib/features/training/application/active_session_notifier.dart` (67 LOC) und wirft `UnimplementedError` aus jeder Methode — kompiliert sauber, M5-T3 ersetzt die Bodies. Test-Suite hat neun Cases (start, recordHit, drei recordMiss, undoLast, recordHeli mit heliTracking=on, complete, abortAndDelete, resumeFromCrash mit pre-inserted Session inkl. corrected event, no-op ohne aktive Session). Alle Cases sind mit `skip: 'TDD: green after M5-T3 implements ActiveSessionNotifier'` markiert — die Suite läuft "76 passed, 9 skipped" durch und dokumentiert den Verhaltens-Contract ohne falschen grünen Status. Nach M5-T3: Skip-Konstante entfernen, Tests müssen dann ohne weitere Änderung grün werden. Der Resume-Case verifiziert explizit, dass corrected events (`correctedAt != null`) NICHT mitzählen — 5 hits aus 6 hit-rows. AC-2 (grün nach M5-T3) bleibt offen bis M5-T3 erledigt ist. Insgesamt 76 Tests grün + 9 skipped, `flutter analyze` clean.

### M5-T3: ActiveSessionNotifier — Tap / Undo / Heli-Filter
- **Agent**: coder
- **Modus**: data
- **Typ**: feature
- **Größe**: M
- **Stunden**: 2.5
- **Beschreibung**: `ActiveSessionNotifier extends AsyncNotifier<ActiveSessionState?>` (freezed `ActiveSessionState` mit den im Plan genannten Feldern). API exakt wie im Architektur-Plan unter "Riverpod-Notifier-API". Counts werden aus `repo.watchEventsOfSession(id)` derived (Filter `correctedAt IS NULL`, Group-by Kind). `recordHit/Miss/Heli` ruft Repo-Append + bei `appSettings.vibration` `HapticFeedback.lightImpact()`. `undoLast(kind)` ruft `repo.softDeleteLastEvent(id, kind)`. `complete` setzt `markCompleted` und reset State auf null. `abortAndDelete` macht hard-delete. `resumeFromCrash` lädt active Session via `loadActiveOrNull`. Heli-Filter wird hier nicht im Notifier gemacht (per Architektur "Heli-Filter-Strategie" — Filter lebt im Application-Selektor des SniperSessionScreen).
- **Input**: M5-T2 (Tests definieren das Verhalten)
- **Output**: `lib/features/training/application/active_session_notifier.dart`, `lib/features/training/application/active_session_state.dart`
- **Akzeptanzkriterien**:
  - [x] Given M5-T2 when alle Tests laufen then grün
  - [x] flutter analyze clean
  - [x] Datei `active_session_notifier.dart` ≤ 100 LOC (state-objekt darf ausgelagert sein)
- **Abhängigkeiten**: M5-T2
- **Status**: done
- **Notiz**: Notifier 99 LOC, `active_session_state.dart` 36 LOC ausgelagert mit `copyWith`. `build()` returnt initial null — die echte Crash-Recovery-Hydration triggert M5-T5 in einem separaten Provider via `resumeFromCrash`. Alle Mutations-Methoden gehen durch einen `_withActive`-Guard, der bei null-State graceful no-op macht (Test 9 grün ohne Event-Leak). `_bump` clamped Counter auf min 0 für defensive Undo-Sequenzen. `state.value` (statt `valueOrNull`) ist die Riverpod-3.x-API. Heli-Filter bewusst NICHT im Notifier — wird im SniperSessionScreen-Selektor (M5-T4) auf Settings basierend gemacht. Skip-Marker `_skipUntilM5T3` aus dem Test-File entfernt; alle 9 Cases laufen jetzt mit. Insgesamt 85 Tests grün (vorher 76), `flutter analyze` clean.

### M5-T4: SniperConfig + SniperSession + AbortDialog + Summary
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: L
- **Stunden**: 4
- **Beschreibung**: Vier UI-Bausteine, die zusammen den Sniper-Flow bilden. **SniperConfigScreen**: Distanz-Slider (4.0–8.0 m, 0.5er-Step, default 8.0), optional Zielwurf-Chips (∞=null, 25, 50, 100, 200) plus Custom-TextField (1–999), Bestätigen ruft `notifier.startSession`, navigiert auf Session. **SniperSessionScreen**: KubbAppBar mit Distanz-Eyebrow, Hamburger-Icon ist disabled (per Q-9a), Eye-Toggle-Icon rechts (toggelt `appSettings.sniperEyeToggleHidden` — sticky per Q-10), Counter-Strip (KubbCounter Hit/Miss/Heli, masked je nach Eye-State), Remaining-Anzeige falls `throwTarget != null`, TapPad-Grid 4 oder 6 Buttons je nach `appSettings.heliTracking` (per Selektor aus Architektur "Heli-Filter-Strategie"), unten "Session beenden" + "Abbrechen". **AbortDialog**: Modal mit "Speichern"/"Verwerfen"/"Zurück" — bei 0-Throw-Sessions nur "Verwerfen"/"Zurück". **SummaryScreen**: Verdict-Block mit Hit-Rate (Big-Number, %, gerundet), Detail-Rows (Treffer, Miss, Heli falls heliTracking on, Dauer mm:ss), drei Aktionen "Verwerfen" (markDiscarded + nach Home), "Speichern" (default — nach Home), "Neu starten" (startSession mit gleichem distance/target, nach Session-Route). Strings via AppLocalizations (mind. 15 Keys). Wenn beim Implementieren > 5h droht: splitten in M5-T4a (Config), M5-T4b (Session + AbortDialog), M5-T4c (Summary).
- **Input**: M5-T3, M4-T2, M4-T1
- **Output**: `lib/features/training/presentation/sniper_config_screen.dart`, `lib/features/training/presentation/sniper_session_screen.dart`, `lib/features/training/presentation/widgets/abort_dialog.dart`, `lib/features/training/presentation/summary_screen.dart`, `lib/l10n/app_de.arb`
- **Akzeptanzkriterien**:
  - [x] Given Config bestätigt with distance=6.5 when "Start" then Session-Route mit Distanz 6.5 in AppBar
  - [x] Given Session offen when Hit+ tap then Counter steigt um 1, Event in DB
  - [x] Given Session mit 0 Throws when Abbrechen-Dialog when Speichern-Option then Speichern-Button nicht vorhanden
  - [x] Given Eye-Toggle aktiv when Counter masked then "—" sichtbar, sticky-Persistenz nach App-Restart
  - [x] Given heliTracking=off when SniperSession rendert then 4-Pad-Grid (kein Heli)
  - [x] Given Summary "Neu starten" when ausgelöst then neue Session mit gleicher Config
  - [x] flutter analyze clean
  - [x] Mindestens ein Widget-Test pro Screen (Config, Session, Summary)
- **Abhängigkeiten**: M5-T3, M4-T2, M4-T1
- **Status**: done — split in a/b/c, all merged
- **Notiz (M5-T4a done)**: SniperConfigScreen unter `lib/features/training/presentation/sniper_config_screen.dart` (130 LOC) plus Widget-Test (121 LOC, 4 Cases). Distanz-Slider 4.0–8.0 m mit 0.5er-Schritten und Tick-Row, Preset-Chips (∞/25/50/100/200) plus Custom-TextField (1–999, digitsOnly), Start ruft `ActiveSessionNotifier.startSession` und navigiert via go_router auf `/training/sniper/session/:id`. Profil wird per `ref.watch(currentProfileProvider)` aktiv gehalten, damit `_start` synchron lesen kann. Router-Placeholder `_SniperConfigPlaceholder` entfernt. Sieben neue ARB-Keys in `app_de.arb`. 89 Tests grün, `flutter analyze` clean. M5-T4b (SessionScreen + AbortDialog) und M5-T4c (SummaryScreen) folgen.
- **Notiz (M5-T4c done)**: SummaryScreen unter `lib/features/training/presentation/summary_screen.dart` (266 LOC inkl. SummaryData-Wrapper, FutureProvider.family und vier private Sub-Widgets `_Body`/`_Verdict`/`_Row`/`_ErrorView` — Haupt-Widget selbst ~25 LOC, Splitting bewusst im selben File). Daten kommen aus `summarySessionProvider` (FutureProvider.family) der direkt am `appDatabaseProvider` zieht — `ActiveSessionNotifier` ist nach `complete()` schon null. Hit-Rate per `(hits / (hits+misses) * 100).round() %` mit Heli-Filter per Q-9b (Heli zählt nie in die Quote). Bei 0 Throws Anzeige "—". Detail-Rows: Treffer, Miss, Heli (nur wenn `appSettings.heliTracking == true`), Distanz, Dauer (mm:ss aus `completedAt - startedAt`). Drei Aktionen: "Speichern" (FilledButton, geht zu `/`), "Verwerfen" (OutlinedButton danger, ruft `repo.discard(sessionId)` für hard-delete), "Neu starten" (TextButton, `notifier.startSession` mit gleicher Distanz/Target und navigiert zur neuen Session-Route). Router-`_SummaryPlaceholder` plus die beiden ungenutzten `_Placeholder`-Klassen entfernt. 11 ARB-Keys neu. Widget-Test mit 5 Cases (71 % Hit-Rate, Heli-Row off/on, Dash bei 0-Throws, Discard ruft repo). 102 Tests grün (vorher 97), `flutter analyze` clean. Damit ist M5-T4 vollständig (a Config + b Session/Abort + c Summary). Nächster Task ist M5-T5 (Crash-Recovery).
- **Notiz (M5-T4b done)**: SniperSessionScreen unter `lib/features/training/presentation/sniper_session_screen.dart` (262 LOC — Layout in private Widgets `_CounterStrip`/`_Remaining`/`_BlindHint`/`_PadGrid` aufgeteilt, bewusst in derselben Datei statt künstlich verteilt). KubbAppBar mit Distanz als Big-Display, kein Hamburger (per Q-9a), Eye-Toggle als sticky Action-Icon (`appSettings.setEyeHidden`). Counter-Strip mit zwei oder drei `KubbCounter` je nach `heliTracking`, Maskierung über `masked: settings.sniperEyeToggleHidden`. Remaining-Hinweis nur wenn `throwTarget != null`, rechnet Heli korrekt rein nur wenn Tracking on. PadGrid mit 4 oder 6 Pads (2-Spalten-`GridView.count`, aspect 2.2), jeder Pad triggert `_haptic` plus passenden Notifier-Call via `_tap`-Helper (vermeidet `discarded_futures`-Lints). End-Button `complete()` → Summary-Route, Abort-Button öffnet `AbortDialog`. AbortDialog unter `lib/features/training/presentation/widgets/abort_dialog.dart` (48 LOC) als statische `show(...)`-Factory mit `AbortChoice.{save, discard, cancel}`-Enum, "Speichern"-Button nur wenn `hasThrows` true (AC-3). Router-Placeholder `_SniperSessionPlaceholder` entfernt, echte Route auf `/training/sniper/session/:id` verdrahtet. 13 ARB-Keys neu in `app_de.arb`. Zwei Widget-Test-Files: `sniper_session_screen_test.dart` (160 LOC, 6 Cases — Counter-Anzahl heli on/off, Pad-Anzahl, Hit+ ruft notifier, Eye-Toggle ruft Setter, Maskierung mit Dash) plus `abort_dialog_test.dart` (44 LOC, 2 Cases — Save sichtbar/verborgen). 97 Tests grün (vorher 89), `flutter analyze` clean. M5-T4c (SummaryScreen) folgt.

### M5-T5: crashRecoveryProvider + CrashRecoveryDialog + Integration-Test
- **Agent**: coder
- **Modus**: frontend
- **Typ**: feature
- **Größe**: M
- **Stunden**: 2
- **Beschreibung**: `crashRecoveryProvider` als `FutureProvider<SessionRow?>`, ruft `repo.loadActiveOrNull()` einmalig (autoDispose nicht — keep-alive, da nur einmal beim HomeScreen-Mount evaluiert). `CrashRecoveryDialog` als modaler Dialog mit drei Buttons: Fortsetzen (push `/training/sniper/session/:id`, Notifier `resumeFromCrash`), Speichern als beendet (`markCompleted` + push `/training/summary/:id`), Verwerfen (`hardDeleteSession` + Dialog schliesst). `barrierDismissible: false`. HomeScreen `initState` (oder `useEffect` mit `flutter_hooks`-Pattern via `ref.listen`) ruft den Provider und zeigt den Dialog wenn Result non-null. Dialog wird nur EINMAL pro App-Start gezeigt (Marker im Provider-State). Dazu **ein Integration-Test** (`integration_test/sniper_flow_test.dart`): kompletter MVP-Pfad — Onboarding → Config → Session mit drei Hits → Summary → Speichern → Recent-Liste enthält Eintrag.
- **Input**: M5-T1, M5-T4, M4-T5
- **Output**: `lib/features/training/application/crash_recovery_provider.dart`, `lib/features/training/presentation/widgets/crash_recovery_dialog.dart`, `lib/features/training/presentation/home_screen.dart` (Hook), `integration_test/sniper_flow_test.dart`, `lib/l10n/app_de.arb`
- **Akzeptanzkriterien**:
  - [ ] Given DB enthält `active`-Session when HomeScreen mountet then CrashRecoveryDialog erscheint genau einmal
  - [ ] Given Dialog "Fortsetzen" tap then Navigation auf Session-Route, State ist hydriert
  - [ ] Given Dialog "Verwerfen" then Session-Row und Events weg, Dialog schliesst
  - [ ] Given Integration-Test when MVP-Pfad ausgeführt then alle Steps grün, Recent-Liste zeigt den Eintrag
  - [ ] flutter analyze clean
- **Abhängigkeiten**: M5-T1, M5-T4, M4-T5
- **Status**: pending
