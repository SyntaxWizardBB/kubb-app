# F5 — CSV Export + SettingsScreen — DONE

Status: shipped on `feature/sniper-training-mvp`.

## Commits

- `chore(deps): add share_plus and delete helpers in player and session daos`
- `feat(settings): add csv exporter and export row model`
- `feat(settings): add csv export repository with filters`
- `feat(settings): add csv share service for mobile and desktop`
- `feat(settings): add csv export notifier and modal with filter chips`
- `feat(settings): replace settings modal with full settings screen and danger actions`
- `test(settings): widget tests for settings screen and csv export modal`

## Final state

- `flutter analyze` clean.
- `flutter test`: 182 grün.
- `AppSettingsModal` und sein Test entfernt — Settings leben ausschliesslich im neuen `/settings` Screen.
- Hamburger im HomeScreen routet jetzt nach `/settings`.
- Profil- und Sessions-Löschung mit Bestätigungs-Dialog. Profil-Löschen triggert die Bootstrap-Redirect-Logik nach `/onboarding`.
- CSV-Export geht auf Mobile via `share_plus` zum System-Share, auf Desktop in das Downloads-Verzeichnis (Pfad als SnackBar).

## Mit F5 abgeschlossen — F2-F5 Bundle

Damit ist die "alle Design-Screens laufen"-Mission durch. Sniper-Training, Profil-Edit, Stats, Finisseur und CSV/Settings sind live und navigierbar.
