# ADR-0043: Dependency-Wartung 2026-08 — Toolchain-Bump und gestaffelte Package-Upgrades

- **Status**: Accepted
- **Date**: 2026-08-20
- **Bezug**: ADR-0001 (Stack); ADR-0015 (Cross-Platform — Android first). Stack-Regel: `flutter pub outdated` ist ein Wartungs-Task, kein Auto-Update auf main.

## Kontext

Die Toolchain lag ein paar Monate zurück. Im Zuge einer Maschinen-Wartung wurde hochgezogen:

- Flutter 3.41.9 → 3.47.1 (stable)
- Dart 3.11.5 → 3.13.1
- Android emulator 36.6.11 → 37.1.11, platform-tools 37.0.0 → 37.0.1
- VSCode 1.125 → 1.134

`flutter doctor` ist clean, die zwei AVDs (`kubb_pixel`, `kubb_pixel_2`) laufen weiter. Das SDK-Upgrade hat drei Repo-Stände angefasst, alle korrekt und nötig:

- `pubspec.lock` — SDK-gepinnte transitive Pakete an die neue Flutter-Version angeglichen.
- `analysis_options.yaml` — Dart-3.13-Migration, ergänzt die Plattform-Ordner in den Analyzer-Excludes.
- Die sieben Bracket-Goldens — der Engine-Bump verschiebt das Antialiasing an den Border-Radien um 0.05–0.24% der Pixel. Layout unverändert, Goldens neu gezogen.

`flutter pub outdated` listete zusätzlich einen Stapel veralteter Projekt-Dependencies. Dieser ADR hat sie ursprünglich in drei Gruppen zur gestaffelten Abnahme vorgelegt. Der Owner hat am selben Tag entschieden, alle drei Gruppen sofort zu ziehen, jede als eigener Commit mit grünen Quality-Gates.

## Entscheidung

Alle drei Gruppen umgesetzt, mit zwei bewussten Abweichungen vom "immer die neueste Version" (siehe §Abweichungen).

**Gruppe A — innerhalb bestehender Constraints.** firebase_core 4.13.0, firebase_messaging 16.5.0, go_router 17.5.0, supabase_flutter 2.17.2, supabase 2.16.1. Reines Lockfile-Update; supabase 2.16 ersetzt `jwt_decode` und `retry` durch das neue `supabase_common`.

**Gruppe B — Codegen-Kette.** Die Annahme im Ur-Entwurf, es gehe nur um angehobene Constraints, war falsch: die Constraints standen fast alle auf `any`. Blockiert hat eine Kette, die sich erst mit `sqlite3` 3.x auflöst.

- `drift` ≥2.32 verlangt `sqlite3 ^3.x`. `sqlite3` 3.0 lädt die native Bibliothek über [Build-Hooks](https://dart.dev/tools/hooks) statt über `DynamicLibrary`. Damit ist `sqlite3_flutter_libs` obsolet (das Paket steht selbst auf `0.6.0+eol` mit dem Hinweis, auf `sqlite3` 3.x zu wechseln) und der Linux-Loader-Override in `test/_helpers/sqlite_open.dart` ebenfalls — `package:sqlite3/open.dart` existiert nicht mehr. Der Override lag in 43 Testdateien und ist ersatzlos raus.
- Verifiziert: das APK enthält `libsqlite3.so` weiterhin für arm64-v8a, armeabi-v7a und x86_64.
- Danach lösten sich drift 2.34, flutter_riverpod 3.4.2, riverpod_generator 4.0.8, riverpod_lint 3.1.8, json_serializable 6.14.1 und build_runner 2.16.0 in einem Zug auf.
- `custom_lint` ist raus. Es war nie in `analysis_options.yaml` als Plugin eingetragen, also wirkungslos, und riverpod_lint ≥3.1.4 ist mit dem letzten veröffentlichten custom_lint 0.8.1 inkompatibel (analyzer_plugin 0.13 gegen 0.14). Neuere riverpod_lint-Versionen hängen ohnehin am eingebauten `analysis_server_plugin` statt an custom_lint.
- Alle `any`-Constraints haben jetzt Untergrenzen, wie es `tech-lead.md` verlangt. Offen bleiben nur `intl`, `path` und `collection` — die pinnt das Flutter-SDK.

**Gruppe C — Major-Sprünge.**

| Package | Von | Nach | Was daran hing |
|---|---|---|---|
| connectivity_plus | 6.1.5 | 7.3.1 | Kein Dart-API-Bruch, nur Android-Build-Config. `ConnectivityService` unverändert. |
| app_links | 6.4.1 | 7.2.1 | Ebenfalls kein Dart-Bruch. `AuthDeepLinkService` unverändert. |
| fl_chart | 0.69.2 | 1.2.0 | Einziger relevanter Bruch wäre das entfernte `tooltipRoundedRadius` — der Trend-Chart hat keine Tooltip-Konfiguration. |
| flutter_secure_storage | 8.1.0 | **10.3.1**, nicht 11 | Siehe §Abweichungen. |

**Android-Toolchain.** connectivity_plus 7 verlangt AGP ≥8.12.1, app_links 7.1 sogar AGP 9.x — und Flutter 3.47 warnt ohnehin auf AGP ≥9.0.1, Gradle ≥9.1.0, Kotlin ≥2.3.20. Also mitgezogen: AGP 8.11.1 → 9.1.1, Gradle 8.14 → 9.3.1, Kotlin 2.2.20 → 2.3.21, google-services 4.4.4 → 4.5.0. `jvmTarget` wandert aus dem deprecateten `kotlinOptions`-Block in `kotlin { compilerOptions { … } }`.

## Abweichungen von "neueste Version"

Zwei Stellen, an denen bewusst nicht die höchste verfügbare Version gewählt wurde.

**flutter_secure_storage bleibt auf 10.3.1.** v11 entfernt den Jetpack-Security-Backend und die alten Cipher-Algorithmen ersatzlos. Das Changelog ist explizit: Daten, die mit einer Version vor v10 geschrieben wurden, sind nach dem Upgrade auf v11 unlesbar. Wir kommen von v8. Betroffen wären die vier Credential-Arten im `SecureTokenStore`, die Device-ID und vor allem das Keypair — nach ADR-0010 ist das die Identität des Nutzers, nicht bloss ein Cache. v10 migriert die Blobs beim ersten Zugriff auf die neuen Cipher. Der Sprung auf 11 ist deshalb erst ein Release später gefahrlos, wenn jede Installation einmal unter v10 gelaufen ist. `encryptedSharedPreferences` ist in v10 deprecated und wird ignoriert, der ganze `aOptions`-Block war danach nur noch Default und ist raus.

**freezed sitzt auf der 4.0.0-dev-Linie.** riverpod_generator 4.0.8 verlangt analyzer ^13, und kein stabiles freezed unterstützt analyzer 13 — 3.2.5 ist die letzte stabile Version und deckelt darunter. Die Alternative wäre, die halbe Codegen-Kette auf dem alten analyzer festzuhalten. freezed ist eine reine Build-Zeit-Dependency, der generierte Code ist eingecheckt und die Gates sind grün, deshalb ist die Dev-Version hier vertretbar. Beim nächsten Wartungslauf prüfen, ob ein stabiles freezed 4 draussen ist.

## Nicht gemacht

**Built-in Kotlin.** Flutter 3.47 warnt, dass der Kotlin-Gradle-Plugin künftig Build-Fehler verursacht, und verweist auf AGPs built-in Kotlin. Das ist aktuell nicht erreichbar: mit `android.builtInKotlin=true` bringen sowohl AGP 9.1.1 als auch 9.2.1 Kotlin 2.2.10 mit, Flutter fordert aber mindestens 2.2.20. Getestet, scheitert reproduzierbar. Bleibt beim KGP.

**AGP 9.2 / neue DSL.** AGP 9.2.1 verlangt Gradle ≥9.4.1, Flutter 3.47 unterstützt Gradle nur bis 9.3.1. Also AGP 9.1.1. Die neue DSL (`android.newDsl=true`, ab AGP 9.0 Default) ist ebenfalls nicht nutzbar, weil der Kotlin-Gradle-Plugin nicht dagegen laufen kann. `android/gradle.properties` bleibt auf `newDsl=false` — der von AGP bis 10.0 unterstützte Übergangspfad — und `android/app/build.gradle.kts` trägt dafür ein `@file:Suppress("DEPRECATION")`.

**`anonKey` → `publishableKey`.** supabase_flutter deprecated `anonKey` in `lib/main.dart`. Der Wechsel betrifft das Key-Setup (dart-define, Codemagic-Env-Gruppe `supabase`) und ist damit Owner-Sache, nicht Teil eines Dependency-Bumps. Eigener Task.

## Alternativen

- **Nichts tun.** Verschiebt die Schuld nach hinten; der Abstand zu den Majors wächst und die spätere Migration wird teurer. Verworfen — der Toolchain-Bump war eh schon passiert.
- **Gestaffelt über mehrere Sprints** (der ursprüngliche Vorschlag dieses ADR). Vom Owner verworfen. Im Rückblick hätte die Staffelung nichts gebracht: Gruppe B liess sich ohne die sqlite3-Migration überhaupt nicht bewegen, und Gruppe C hing an derselben Android-Toolchain. Die Abhängigkeiten laufen quer zu den Gruppen.
- **Alles kompromisslos auf Latest.** Hätte bei flutter_secure_storage 11 die Keypair-Identität bestehender Installationen zerstört. Verworfen.

## Konsequenzen

- Ein Wartungslauf, elf Commits, jeder für sich mit grünen Gates: `flutter analyze` auf dem Vor-Stand von 14 Info-Findings, `dart analyze` im Domain-Package unverändert, 1725 App-Tests und 843 Domain-Tests grün, Android-APK baut und enthält die native SQLite-Bibliothek.
- `test/_helpers/sqlite_open.dart` schrumpft auf `openTestDatabase()`. Die Umgebungsvariable `KUBB_TEST_SQLITE_PATH` gibt es nicht mehr; falls sie irgendwo in CI gesetzt ist, ist sie wirkungslos.
- Die Versionshinweise in `tech-lead.md` (Dart 3.11+, Flutter 3.41+, drift 2.x, go_router 14.x) sind überholt. go_router steht auf 17, Riverpod auf 3. Nachziehen.
- Zwei Nachfolge-Tasks: flutter_secure_storage auf 11 heben, sobald ein Release mit v10 draussen war, und `anonKey` auf `publishableKey` umstellen.
- Der Trend-Chart hat keine Testabdeckung. Bei fl_chart 0.69 → 1.2 wäre eine visuelle Regression unbemerkt durchgegangen. Ein Golden für `StatsTrendChart` wäre günstig.
