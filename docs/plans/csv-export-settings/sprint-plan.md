# Sprint-Plan: F5 — CSV Export + SettingsScreen

## Reihenfolge

| # | Task | Size | Notes |
|---|---|---|---|
| 1 | Add `share_plus` dep + delete-Methods in DAOs/Repositories | S | infra + data |
| 2 | `CsvExporter` pure-Dart + Tests | S | TDD-First |
| 3 | `CsvExportRepository` + Tests | M | drift-In-Memory |
| 4 | `CsvShareService` (mobile + desktop fallback) | S | platform-channel adapter |
| 5 | `CsvExportNotifier` + `CsvExportModal` UI | M | bottomsheet |
| 6 | `SettingsScreen` + ARB-Strings | M | drei Sektionen |
| 7 | Confirmation-Dialoge + Hamburger-Routing umbiegen + AppSettingsModal löschen | M | UI-Glue |
| 8 | Widget-Tests Settings + Confirm-Flow | S | golden / smoke |

Alle Commits unter Senior-LOC-Limit. Tests grün vor jedem Commit.
