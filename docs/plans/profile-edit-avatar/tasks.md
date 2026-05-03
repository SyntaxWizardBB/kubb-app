# Tasks — Profile Edit + Avatar (F2)

## TASK-T1: drift Schema v2 + addColumn(avatarColor)

- **Type**: data
- **Size**: M
- **Bounded Context**: core
- **Agent**: coder (data)
- **Files**: `lib/core/data/tables/players.dart`, `lib/core/data/app_database.dart`

### Goal
Players-Tabelle hat neue nullable Spalte `avatarColor`. schemaVersion 2 mit `onUpgrade`.

### Acceptance
- Given v1-DB; When App startet; Then onUpgrade addColumn ohne Datenverlust.
- Given Test-In-Memory-DB; Then Spalte avatarColor existiert via onCreate.

---

## TASK-T2: PlayerDao.update + PlayerRepository.update

- **Type**: data
- **Size**: S
- **Agent**: coder (data)
- **Files**: `lib/core/data/dao/player_dao.dart`, `lib/features/player/data/player_repository.dart`

### Goal
Mutation für Name und avatarColor by id. Stream emittiert.

### Acceptance
- Given Player p1; When repo.update(id: p1.id, name: 'Bea', avatarColor: '0xFF...'); Then DB row enthält neuen Namen und Farbe.

---

## TASK-T3: AvatarColorHelper + AvatarCircle Widget

- **Type**: frontend
- **Size**: M
- **Agent**: coder (frontend)
- **Files**: `lib/features/player/presentation/avatar_color.dart`, `lib/core/ui/widgets/avatar_circle.dart`

### Goal
Pure Helper-Funktionen + reines View-Widget. Keine Provider, kein State.

### Acceptance
- AvatarColorHelper.palette enthält 6 Token-Farben.
- defaultColorFor(id) ist deterministisch.
- initialsFor(name) liefert 1-2 Großbuchstaben, robust gegen leere/whitespace Eingaben.
- AvatarCircle rendert Circle mit Initiale + Farbe.

---

## TASK-T4: Onboarding mit Avatar-Vorschau

- **Type**: frontend
- **Size**: S
- **Agent**: coder (frontend)
- **Files**: `lib/features/player/presentation/onboarding_screen.dart`

### Goal
Vorschau-Avatar oberhalb des TextFields. Aktualisiert live während Eingabe. Default-Farbe (palette[0]).

### Acceptance
- Given OnboardingScreen geöffnet; When User "Lu" eintippt; Then AvatarCircle zeigt "LU".

---

## TASK-T5: ProfileScreen Edit-Mode + Color-Picker

- **Type**: frontend
- **Size**: M
- **Agent**: coder (frontend)
- **Files**: `lib/features/player/presentation/profile_screen.dart`

### Goal
Edit-Toggle, TextField, Color-Chips, Save/Cancel.

### Acceptance
- Read-Mode rendert Avatar + Name + Daten wie bisher.
- Edit-Tap → TextField + Color-Chips + Save/Cancel.
- Save → repo.update → zurück in Read-Mode.
- Cancel → Verwerfung.
- Save-Button disabled wenn Name leer.

---

## TASK-T6: Tests

- **Type**: tests
- **Size**: M
- **Agent**: tester
- **Files**: alle test/-Files unter player/ und core/data/

### Goal
≥7 neue Tests für DAO.update, Repo.update, AvatarColorHelper, AvatarCircle (Widget), ProfileScreen Edit-Mode (Widget), Onboarding-Vorschau (Widget), Schema-v2 (DB).

### Acceptance
- `flutter test` zeigt ~115 Tests, alle grün.
- `flutter analyze` clean.

---

## TASK-T7: Doku-Done

- **Type**: docs
- **Size**: S
- **Agent**: coder (docs)
- **Files**: `docs/plans/profile-edit-avatar/feature-plan.md`

### Goal
Status auf complete, Push-Datum eintragen.
