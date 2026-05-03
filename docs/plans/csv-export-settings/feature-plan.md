# Feature F5: CSV Export + erweiterter SettingsScreen

## Ziel

Letztes Feature der F2-F5 Reihe. Bringt zwei sichtbare Bausteine, die im Design-Bundle noch fehlen:

1. **CSV-Export**: Modaldialog, der alle gespeicherten Trainings-Sessions (Sniper + Finisseur) als CSV exportiert. Filter nach Modus und Zeitraum. Auf Mobile via `share_plus` zum System-Share, auf Desktop/Web als Datei in Downloads-Verzeichnis.
2. **SettingsScreen**: Vollwertiger Screen (nicht Modal) mit Account-, Daten- und App-Sektionen. Ersetzt das bisherige `AppSettingsModal` als primären Settings-Ort. Hamburger im HomeScreen führt nun nach `/settings`.

Das alte `AppSettingsModal` wird aus dem Routing entfernt — alle Settings leben im neuen Screen. Code des Modals wird gelöscht (oder ggf. zu einem Quick-Settings-Snippet reduziert, falls künftig nötig — vorerst weg).

## Scope

**In:**
- `CsvExporter` pure-Dart Helper (nimmt Sessions + Events, liefert CSV-String).
- `CsvExportRepository` lädt Sessions + Events per Filter.
- `CsvExportModal` UI-Bottomsheet.
- `share_plus` integration für Mobile-Share.
- `path_provider` Fallback für Desktop.
- `SettingsScreen` mit Account / Daten / App-Sektionen + Routing-Hooks.
- Bestätigungs-Dialoge für destruktive Aktionen (Profil löschen, Sessions löschen).
- Hard-Delete Helper (Profil → wirft auf Onboarding-Redirect via Bootstrap-Pattern; Sessions → bleibt im SettingsScreen).
- Hamburger-Route umbiegen.
- ARB-Strings DE.
- Unit + Widget-Tests.

**Out:**
- Kein iCloud / Drive Backup.
- Keine User-konfigurierbaren CSV-Felder.
- Kein Custom-Date-Range-Picker (nur Presets All / 30d / 90d / Year — wie Design).
- Keine Achievement-Sektion (Design-Spec hat sie, ist aber Phase 2 — Routing-Hook bleibt mit Coming-Soon-Snackbar).
- Kein Stats-Link im Settings-Screen aufwendig — verlinkt einfach auf bestehende `/stats`.

## Bezug zu bestehender Code-Basis

- DAOs `SessionDao`, `SessionEventDao`, `FinisseurStickEventDao`, `PlayerDao` sind komplett.
- `SessionDao.allCompletedForPlayer` liefert Sniper+Finisseur sortiert.
- `PlayerRepository.create/update` da — Delete-Methode kommt neu hinzu.
- Routing existiert (`go_router`). Neue Route: `/settings`.
- Bootstrap-Redirect setzt auf `currentProfileProvider` — Profil-Löschen triggert Auto-Redirect zum `/onboarding`.

## Risiken

- `share_plus` bringt Plattform-Channels (Android/iOS hauptsächlich). Auf Linux-Desktop ist Verhalten degraded. Mitigation: bei Linux Pfad = lokale Datei in tmp/Downloads + SnackBar mit Pfad.
- Profil-Löschen entfernt FK-protected Sessions. `Players` hat `KeyAction.restrict` von Sessions — wir müssen Sessions zuerst löschen, dann Profil.
