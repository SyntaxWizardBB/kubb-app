# Tasks — F4 Finisseur

## TASK-F4-01: Drift schema bump v3 + new tables
- **Type**: data
- **Size**: S
- **Files**: `lib/core/data/tables/sessions.dart`, `lib/core/data/tables/finisseur_stick_events.dart` (new), `lib/core/data/app_database.dart`
- **Goal**: schema v3, columns mode/finField/finBase added to Sessions, new table FinisseurStickEvents created with PK + FK + unique index.
- **Acceptance**: `flutter analyze` clean, `dart run build_runner build` regenerates `app_database.g.dart`.

## TASK-F4-02: FinisseurStickEventDao + SessionDao extension
- **Type**: data
- **Size**: S
- **Files**: `lib/core/data/dao/finisseur_stick_event_dao.dart` (new), `lib/core/data/dao/session_dao.dart`
- **Goal**: DAO with `insert`, `forSession`, `countForSession`. SessionDao gets `activeFinisseurForPlayer`. App-database registers new DAO.
- **Acceptance**: Generated file compiles, DAO has all methods.

## TASK-F4-03: ActiveFinisseurState + StickResult value classes
- **Type**: domain
- **Size**: S
- **Files**: `lib/features/training/application/active_finisseur_state.dart`
- **Goal**: Manual immutable classes (analog to ActiveSessionState).
- **Acceptance**: copyWith works, equality not required (consumed via Riverpod state).

## TASK-F4-04: FinisseurRepository
- **Type**: data
- **Size**: M
- **Files**: `lib/features/training/data/finisseur_repository.dart`
- **Goal**: startFinisseur, recordStick, markCompleted, discard, loadActiveOrNull, loadStickEvents.
- **Acceptance**: Provider exposed, methods generate UUIDv7 ids and UTC timestamps.

## TASK-F4-05: ActiveFinisseurNotifier
- **Type**: domain
- **Size**: M
- **Files**: `lib/features/training/application/active_finisseur_notifier.dart`
- **Goal**: AsyncNotifier with startSession/updateCurrentStick/advance/complete/abortAndDelete.
- **Acceptance**: State updates ripple to UI; advance persists current stick.

## TASK-F4-06: Repository + Notifier tests
- **Type**: tests
- **Size**: M
- **Files**: `test/features/training/data/finisseur_repository_test.dart`, `test/features/training/application/active_finisseur_notifier_test.dart`
- **Goal**: Min 8 cases — start, recordStick persists, completed status, discard cascades, advance increments, complete state=null, constraints (field+base ≤ 10 enforced at config layer not here, but max-counts checked).
- **Acceptance**: All tests pass.

## TASK-F4-07: FinisseurConfigScreen
- **Type**: frontend
- **Size**: M
- **Files**: `lib/features/training/presentation/finisseur_config_screen.dart`, `lib/features/training/presentation/widgets/kubb_stack_preview.dart`
- **Goal**: Steppers, Constraint clamping, Visual Stack preview, 4 built-in presets, Start button → push to /session/:id.
- **Acceptance**: UI matches spec, constraint clamping works, route-push fires.

## TASK-F4-08: FinisseurStickScreen
- **Type**: frontend
- **Size**: L
- **Files**: `lib/features/training/presentation/finisseur_stick_screen.dart`, `lib/features/training/presentation/widgets/pip_progress.dart`
- **Goal**: Pip-Progress (6 pips with tones), Remaining-Block, Field-Chip-Selector, Toggles (8m, Heli, King), Strafkubb-Eingabe (stick 0 only), King-Detail. Calls notifier.advance() on Next button.
- **Acceptance**: UI matches spec, all conditional sections appear correctly, end-of-session navigation to /summary/:id.

## TASK-F4-09: SummaryScreen Finisseur variant
- **Type**: frontend
- **Size**: M
- **Files**: `lib/features/training/presentation/summary_screen.dart`
- **Goal**: Branch by session.mode. Finisseur: Verdict (Sauber finished/Nicht geschafft), sticks-used count, Königswurf, Strafkubbs, Heli, Dauer rows. Restart button calls Finisseur start.
- **Acceptance**: Both modes render correctly.

## TASK-F4-10: TrainingSheet wire-up + recent-sessions Finisseur tag
- **Type**: frontend
- **Size**: S
- **Files**: `lib/features/training/presentation/widgets/training_sheet.dart`, `lib/features/training/application/recent_sessions_provider.dart`
- **Goal**: Toast removed, tap navigates to /training/finisseur/config. Recent-sessions provider tags Finisseur sessions with modeTag='Finisseur' and shows config+success in subtitle.
- **Acceptance**: Tap navigates, recent list shows Finisseur sessions readably.

## TASK-F4-11: Router + Stats filter + l10n strings + widget tests
- **Type**: frontend + tests
- **Size**: M
- **Files**: `lib/app/router.dart`, `lib/features/stats/data/stats_repository.dart`, `lib/l10n/app_de.arb`, multiple new widget tests
- **Goal**: Routes added; StatsRepository filters out finisseur-mode sessions from sniper aggregates; ARB has all new strings; widget tests for Config/Stick/Summary (~6-8 tests).
- **Acceptance**: All ~165 tests green, analyze clean.

## TASK-F4-12: Plan-Done Doc Commit
- **Type**: docs
- **Size**: S
- **Files**: `docs/plans/finisseur-mode/feature-plan.md`
- **Goal**: Mark feature as done after push.
