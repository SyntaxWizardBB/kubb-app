# player — bounded context

**Layering**: pragmatic CRUD (per ADR-0002).

Player and team identity. Mostly create / list / detail / edit.

```
player/
├── application/    Riverpod providers (PlayerListController, etc.)
├── data/           Drift tables: Players, Teams, TeamMembers
└── presentation/   List, detail, edit screens
```

Cloud sync is a thin write-through (organizer pushes; players read) via the shared `TournamentRemote` port.
