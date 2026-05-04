# Finisseur Refactor + Onboarding Bug

Bündel aus einem Onboarding-Tastatur-Bugfix und einer breiten Aufräumrunde im Finisseur-Modus. Alles auf der bestehenden Schema-Version v3 — kein Bump nötig.

## Scope

### Bug 1 — Onboarding Keyboard Overflow

Die Onboarding-Spacers crashten in einen Negative-Constraint, sobald die Tastatur den Scaffold-Bottom-Inset reduzierte. Fix:

- `Scaffold.resizeToAvoidBottomInset: false` — Tastatur wird Overlay.
- Inhalt in einen `SingleChildScrollView` mit `MediaQuery.viewInsets.bottom`-Padding gesetzt, damit der Confirm-Button trotz Tastatur erreichbar bleibt.
- `TextInputAction.go` als Submit-Action — Enter auf der Software-Tastatur erstellt das Profil direkt.

### Block B — Finisseur

1. **AppSettings** bekommt drei neue Boolean-Felder (`longDubbieTracking`, `penaltyKubbTracking`, `kingThrowTracking`). Defaults sind `true`, sodass bestehende DBs ohne Migration nichts verlieren.
2. **Settings-Screen** zeigt unter dem Heli-Toggle eine eigene Finisseur-Sektion mit drei Switches.
3. **8m-Treffer → Long Dubbie**: der Wurf, der Feldkubb plus Basiskubb gleichzeitig umlegt, wird jetzt mit einem Tap erfasst (`fieldHits += 1` UND `eightMHit = true`). Das Schema bleibt — nur die Semantik ändert sich.
4. **Vereinfachte Basis-Phase**: solange noch Feldkubbs stehen, läuft der alte Field-Chip-Pfad. Sobald nur noch Basiskubbs übrig sind, ersetzt ein Hit/Miss-Pad (plus optional Heli) die Chips. Jeder Tap commitet und springt automatisch zum nächsten Stock.
5. **Strafkubb-Reduktion**: Die "1× geworfen" Reihe ist weg. Die "2× geworfen" Reihe heisst jetzt "Strafkubb". `penalty1` bleibt in der DB für Audit, wird aber nicht mehr geschrieben.
6. **Built-in-Presets entfernt**: keine Standard/5-5/10-0/Spät-Chips mehr. Stepper allein reichen.
7. **Visibility nach Settings**: Long Dubbie, Heli, Strafkubb und Königswurf sind nur sichtbar, wenn das jeweilige Tracking-Setting an ist.
8. **Back-Button** im AppBar des Stick-Screens und Config-Screens. Ist bereits Progress vorhanden, fragt ein Confirm-Dialog vor dem Verwerfen. PopScope sichert den System-Back.
9. **Stats-Tab Sniper/Finisseur**: TabBar oben im Stats-Screen splittet die Ansicht. Der Finisseur-Tab zieht ein eigenes Aggregate (Erfolgsrate, Sticks pro Session, Long-Dubbies, Heli, Strafkubb, Königswurf-Quote, Trend, Session-Liste).
10. **TrainingSheet Footer-Link** "Statistik anzeigen" unter den beiden Mode-Karten.

## Bezug zu ADRs

- ADR-0001 (Tech-Stack): keine neuen Deps. Bestehende Riverpod / drift / freezed-Patterns.
- ADR-0002 (Bounded Contexts): `training/` bleibt pragmatisch, `stats/` erweitert seine Aggregate-Methoden.
- ADR-0005 (Per-Platform-Persistence): nur Settings-Keys neu, keine Schema-Änderung.

## Tests

- `+18 Tests` insgesamt: 7 für die neuen Settings (Defaults, Roundtrip, drei Setter), 6 für FinisseurStickScreen (Long Dubbie tap, Visibility-Off-Cases, Basis-Phase Auto-Advance), 3 für StatsRepository (empty, success-counting, sortierung), 2 für StatsScreen-Tab-Switch, 1 für Onboarding-Submit-Action, 1 für TrainingSheet-Footer-Link.
- Total: 200 Tests grün.

## Status

Done — gepushte Branch `feature/sniper-training-mvp`. `flutter analyze` und `dart analyze` (kubb_domain) sauber.
