# Feature F4 — Finisseur Mode

Zweiter Trainingsmodus. Spieler stellt eine Match-End-Situation nach (x Feldkubbs auf Gegnerseite, y Basiskubbs auf der Basislinie) und versucht, mit max 6 Stöcken erst alle Feld-, dann alle Basiskubbs und zum Schluss den König zu treffen.

## Scope

In:
- Konfig-Screen mit Visual-Stack-Preview, Steppern (Field 0–10, Base 0–5, field+base ≤ 10), Built-in Presets (7/3, 5/5, 10/0, 3/5).
- Per-Stick-Eingabe-Screen mit Pip-Progress, Remaining-Anzeige, Field-Chip-Selector, Toggles (8m-Treffer, Helikopter, Königswurf), Strafkubb-Eingabe (nur am ersten Stock), King-Detail (oben/unten · Treffer/verfehlt).
- Persistenz via `finisseur_stick_events` Tabelle, schema bump auf v3.
- Summary-Screen-Variante mit Verdict (Sauber finished / Nicht geschafft), Stöcke-benötigt, Königswurf-Status, Strafkubb- und Heli-Counts.
- TrainingSheet: Toast entfernt, Navigation aktiv.
- StatsRepository erkennt Finisseur-Sessions (kein Crash bei aggregate, keine Verfälschung der Sniper-Aggregates).

Out:
- Property-Tests via glados (kann später dazukommen).
- Custom-Presets persistent gespeichert (User-Presets via DB) — built-ins reichen.
- Crash-Recovery für Finisseur-Sessions (Phase-1 ähnlich wie Sniper, aber separater Notifier — wird dokumentiert).
- Eigene Stats-Aggregate-Karte für Finisseur — bleibt für später.

## Bezug zu ADRs

- ADR-0001 (Tech-Stack): keine neuen Deps. Riverpod + drift + freezed-Stil-Klassen analog zu ActiveSessionState.
- ADR-0002 (Bounded Contexts): training/ bleibt pragmatisch — direkter Riverpod→Drift-Pfad.
- ADR-0005 (Per-Platform-Persistence): drift-Schema-Bump v2→v3 mit `addColumn` + `createTable` auf allen Plattformen.

## Open Questions

Keine — Spec eindeutig genug.

## Status

Planning → Implementation → Push.
