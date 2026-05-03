# Tasks: F5 — CSV Export + SettingsScreen

## TASK-F5-1: Pubspec + DAO/Repo delete-Methods

- **Type**: data
- **Size**: S
- **Files**: `pubspec.yaml`, `lib/core/data/dao/session_dao.dart`, `lib/features/player/data/player_repository.dart`, `lib/core/data/dao/player_dao.dart`

### Goal
`share_plus` ist als dep da. `SessionDao.deleteAllForPlayer` + `PlayerDao.deleteById` + `PlayerRepository.delete` existieren.

### Acceptance
```
Given die App ist gebaut
When  ich `flutter pub get` ausführe
Then  share_plus ist installiert
And   `dart analyze` clean
```

## TASK-F5-2: CsvExporter pure-Dart + Tests

- **Type**: domain (pragmatic — lebt in features/settings/data, aber pure Dart)
- **Size**: S
- **Files**: `lib/features/settings/data/csv_exporter.dart`, `lib/features/settings/data/export_row.dart`, `test/features/settings/csv_exporter_test.dart`

### Goal
`CsvExporter().generate(rows)` liefert korrekt formatierten CSV mit Header und allen Spalten.

### Acceptance
```
Given eine Liste mit 1 Sniper-Row und 1 Finisseur-Row
When  ich generate() rufe
Then  die erste Zeile ist der Header mit allen 15 Spalten
And   Sniper-spezifische Felder bei Finisseur sind leer (und umgekehrt)
And   Felder mit Komma werden quoted
```

## TASK-F5-3: CsvExportRepository

- **Type**: data
- **Size**: M
- **Files**: `lib/features/settings/data/csv_export_repository.dart`, `lib/features/settings/data/csv_export_filter.dart`, `test/features/settings/csv_export_repository_test.dart`

### Goal
Lädt Sessions per Filter, aggregiert Events, mappt auf `ExportRow`.

### Acceptance
```
Given drei abgeschlossene Sessions (2 Sniper, 1 Finisseur), Filter all/both
When  load() läuft
Then  liefert 3 Rows
And   Sniper-Rows haben hits/misses/helis aus session_events aggregiert
And   Finisseur-Rows haben hits/misses/helis/sticks_used/success/king_hit aus stick_events aggregiert
```

## TASK-F5-4: CsvShareService

- **Type**: data
- **Size**: S
- **Files**: `lib/features/settings/data/csv_share_service.dart`

### Goal
Plattform-Adapter wrapper. Mobile → share_plus. Desktop/Web → path_provider + lokale Datei.

### Acceptance
```
Given ein CSV-String
When  share() läuft auf Linux
Then  Datei wird in Downloads/Documents geschrieben
And   ShareResult.path ist gesetzt
```

## TASK-F5-5: CsvExportNotifier + CsvExportModal

- **Type**: frontend
- **Size**: M
- **Files**: `lib/features/settings/application/csv_export_notifier.dart`, `lib/features/settings/application/csv_export_state.dart`, `lib/features/settings/presentation/csv_export_modal.dart`

### Goal
Modal mit Filter-Chips, Modus-Checkboxen, Vorschau, Download-Button. Disabled wenn Count==0.

### Acceptance
```
Given ich öffne den Modal mit 5 Sniper-Sessions im DB
When  ich Sniper deaktiviere und Finisseur deaktiviere
Then  ist der Download-Button disabled
And   ein Hint "Keine Sessions zum Exportieren" wird gezeigt
```

## TASK-F5-6: SettingsScreen + ARB

- **Type**: frontend
- **Size**: M
- **Files**: `lib/features/settings/presentation/settings_screen.dart`, `lib/l10n/app_de.arb`, `lib/app/router.dart`

### Goal
SettingsScreen mit Account/Daten/App. Route `/settings` registriert.

### Acceptance
```
Given ich navigiere zu /settings
Then  sehe ich Account/Daten/App Sektionen
And   alle Strings via AppLocalizations
```

## TASK-F5-7: Confirm-Dialoge + Hamburger-Routing + AppSettingsModal weg

- **Type**: frontend
- **Size**: M
- **Files**: `lib/features/training/presentation/home_screen.dart`, `lib/core/ui/settings/app_settings_modal.dart` (delete), `lib/features/settings/presentation/confirm_dialog.dart`, `lib/features/settings/application/danger_actions_notifier.dart`

### Goal
Hamburger im HomeScreen führt nun zu `/settings`. Profil-Löschen + Sessions-Löschen mit Confirmation. Altes Modal entfernt.

### Acceptance
```
Given ich tippe auf den Hamburger
Then  navigiere ich zu /settings (kein Bottomsheet)
```

```
Given ich tippe "Profil löschen"
And   bestätige im Dialog
Then  Profil + Sessions sind weg
And   Routing redirected zu /onboarding
```

## TASK-F5-8: Widget-Tests SettingsScreen + Confirm-Flow

- **Type**: tests
- **Size**: S
- **Files**: `test/features/settings/settings_screen_test.dart`, `test/features/settings/csv_export_modal_test.dart`

### Goal
Smoke-Tests für SettingsScreen + Confirm-Dialog + Disabled-State im Modal.

### Acceptance
```
Given das Test-Setup mit fake providern
When  ich SettingsScreen pumpe
Then  alle drei Sektionen rendern
And   Confirm-Dialog erscheint bei Tap auf "Profil löschen"
```
