# Feature-Plan: Profile Edit + Avatar (F2)

## Meta

- **Slug:** profile-edit-avatar
- **Beschreibung (Owner):** ProfileScreen um Edit-Mode erweitern (Name); deterministische Initialen-Avatare mit ableitbarer Background-Farbe aus dem Token-System; optional Color-Picker; Onboarding zeigt Avatar-Vorschau live mit.
- **Erstellt:** 2026-05-02
- **Status:** complete
- **Plan-Verzeichnis:** docs/plans/profile-edit-avatar/
- **Temp-Verzeichnis (ephemer):** /tmp/kubb_app/profile-edit-avatar/
- **Branch:** feature/sniper-training-mvp

## Bounded-Context-Zuordnung

- [x] player / team (pragmatisches CRUD)
- [x] core / infrastructure (drift Schema-Bump v1 → v2)

## Backlog (Step 1 — Product Owner)

Volldokument: `po-output.md`. Kurz: 5 User Stories, alle MUST oder SHOULD, Akzeptanzkriterien Given/When/Then in `po-output.md`.

## Architektur (Step 2 — Architect)

Volldokument: `architecture.md`. Bounded Context bleibt `player/` (pragmatisch CRUD). Schema-Bump v1 → v2 mit `addColumn(avatarColor)`. Neuer Helper `AvatarColorHelper` (deterministisch aus ID-Hash → Token-Palette). Neues Widget `AvatarCircle` in `lib/core/ui/widgets/`. Keine neue ADR (kein Stack-Wechsel, kein neuer Bounded Context).

## Sprint-Plan (Step 3 — Scrum Master)

| # | Milestone | Tasks | Beschreibung |
|---|---|---|---|
| M1 | Schema + Repo | T1, T2 | drift v2 + PlayerDao.update + Repo.update |
| M2 | Avatar Visuals | T3 | AvatarColorHelper + AvatarCircle |
| M3 | UX | T4, T5 | Onboarding-Vorschau + ProfileScreen Edit-Mode |
| M4 | Tests + Docs | T6, T7 | neue Tests, Plan-Done-Doc |

## Final-Review

- [x] Tech-Lead: `flutter analyze` clean, `dart analyze` (kubb_domain) clean
- [x] Tests grün — 128 Tests gesamt (22 neu)
- [x] Commit-History clean (kein AI-Trace)
- [x] Push erfolgt am 2026-05-02

## Commit-Liste

- `ef87dc2` docs(plans): add F2 profile-edit-avatar plan artefacts
- `91a794c` feat(player): bump drift schema to v2 with avatarColor column
- `719abe7` feat(player): add updateById on dao and update on repository
- `a3e8c19` feat(player): add AvatarColorHelper and AvatarCircle widget
- `8afbbda` feat(player): add live avatar preview to onboarding
- `67c1536` feat(player): add edit mode and color picker to profile screen
- `0184e3f` test(player): cover update path, avatar helper, edit mode and preview
