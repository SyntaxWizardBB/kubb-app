# Feature-Plan: Stats Screen mit Charts (F3)

## Meta

- **Slug:** stats-screen
- **Beschreibung (Owner):** Neuer `StatsScreen` (Route `/stats`) mit Filter-Bar (Distanz, Datums-Range), Aggregate-Block (Trefferrate, Total Würfe, Sessions, längste Streak), Trend-Chart (`fl_chart` LineChart) über die letzten Sessions, Personal-Bests, scrollbare Session-Liste. Erreichbar via Stats-Button im AppSettingsModal.
- **Erstellt:** 2026-05-02
- **Status:** complete
- **Plan-Verzeichnis:** docs/plans/stats-screen/
- **Temp-Verzeichnis (ephemer):** /tmp/kubb_app/stats-screen/
- **Branch:** feature/sniper-training-mvp

## Bounded-Context-Zuordnung

- [x] training / stats (neuer Sub-Context `lib/features/stats/`, pragmatisch — read-only Aggregate über drift, kein eigener Domain-Layer)
- [x] core / ui (Stats-Eintrag im AppSettingsModal, Route in router)

## Backlog (Step 1 — Product Owner)

Volldokument: `po-output.md`. Kurz: 6 User Stories, alle MUST oder SHOULD, Given/When/Then in `po-output.md`.

## Architektur (Step 2 — Architect)

Volldokument: `architecture.md`. Neuer Bounded Context `stats/` als pragmatischer read-only-Aggregator. Neue Library `fl_chart` (Industry-Standard für Flutter-Charts). Keine neue ADR (kein neuer Stack-Wechsel jenseits Charts-Lib; Sub-Context unter feature-Pattern).

## Sprint-Plan (Step 3 — Scrum Master)

| # | Milestone | Tasks | Beschreibung |
|---|---|---|---|
| M1 | Foundation | T1, T2, T3 | fl_chart-Dep, Filter+Aggregate VOs |
| M2 | Repo + Provider | T4, T5 | StatsRepository + Provider, Tests |
| M3 | UI | T6, T7 | Filter-Bar, Aggregate-Block, Chart, Liste |
| M4 | Integration | T8, T9 | Navigation, Widget-Tests, Plan-Done-Doc |

## Final-Review

- [x] Tech-Lead: `flutter analyze` clean, `dart analyze` (kubb_domain) clean
- [x] Tests grün — 142 Tests gesamt (14 neu)
- [x] Commit-History clean (kein AI-Trace)
- [x] Push erfolgt am 2026-05-02

## Commit-Liste

- `43a1382` feat(stats): add fl_chart dep and stats filter/aggregate value objects
- `954a884` feat(stats): add stats repository computing aggregates from session log
- `f251e1f` test(stats): cover aggregate, streak, filters and personal-bests
- `ec9214a` feat(stats): add stats filter notifier and aggregate provider
- `adbce9c` test(stats): cover empty aggregate and filter recompute
- `d8daf5b` feat(stats): add stats screen with filter bar, aggregate block and session list
- `ac01620` feat(stats): add /stats route and stats entry in settings modal
- `5efff63` test(stats): cover empty state, populated screen and filter recompute
