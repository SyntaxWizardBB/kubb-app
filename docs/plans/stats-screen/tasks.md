# Tasks: Stats Screen (F3)

## TASK-1: Foundation — fl_chart dep + Filter & Aggregate VOs

- **Type**: data
- **Size**: S
- **Bounded Context**: stats
- **Agent**: coder (data)
- **Dependencies**: —
- **Files**: `pubspec.yaml`, `lib/features/stats/data/stats_filter.dart`, `lib/features/stats/data/stats_aggregate.dart`

**Goal:** `fl_chart` als Dependency, `StatsFilter` (immutable mit `copyWith`) und `StatsAggregate` (immutable VO) existieren.

**Acceptance:**
- Given: `flutter pub get` läuft sauber durch.
- When: ich `StatsFilter()` und `StatsAggregate.empty()` instanziiere.
- Then: keine Compile-Errors.

## TASK-2: StatsRepository

- **Type**: data
- **Size**: M
- **Bounded Context**: stats
- **Agent**: coder (data)
- **Dependencies**: T1
- **Files**: `lib/features/stats/data/stats_repository.dart`, `lib/core/data/dao/session_dao.dart` (eine neue Methode `allCompletedForPlayer`)

**Goal:** `StatsRepository.computeAggregate(playerId, filter, heliTracking)` returnt korrekt aggregierte Daten.

**Acceptance:**
- Given: 3 completed Sessions in der DB.
- When: ich `computeAggregate` aufrufe ohne Filter.
- Then: `totalSessions == 3`, `hitRatePercent` korrekt, `trendPoints` hat 3 Werte chronologisch, `longestHitStreak` korrekt.

## TASK-3: StatsRepository Tests

- **Type**: tests
- **Size**: M
- **Bounded Context**: stats
- **Agent**: tester
- **Dependencies**: T2
- **Files**: `test/features/stats/data/stats_repository_test.dart`

**Goal:** Mind. 5 Tests die Aggregate-Berechnung, Streak, Filter, Empty-State, heliTracking-Toggle prüfen.

## TASK-4: StatsFilterNotifier + statsAggregateProvider

- **Type**: data
- **Size**: S
- **Bounded Context**: stats
- **Agent**: coder (data)
- **Dependencies**: T2
- **Files**: `lib/features/stats/application/stats_filter_notifier.dart`, `lib/features/stats/application/stats_aggregate_provider.dart`

**Goal:** Filter-Notifier mutiert State, Aggregate-Provider rebuildet bei Filter-Wechsel.

## TASK-5: Provider Tests

- **Type**: tests
- **Size**: S
- **Bounded Context**: stats
- **Agent**: tester
- **Dependencies**: T4
- **Files**: `test/features/stats/application/stats_aggregate_provider_test.dart`

**Goal:** 2 Tests: Empty-State und Filter-Wechsel triggert Recompute.

## TASK-6: StatsScreen + Filter-Bar + Aggregate-Block + Session-Liste

- **Type**: frontend
- **Size**: L
- **Bounded Context**: stats
- **Agent**: coder (frontend)
- **Dependencies**: T4
- **Files**: `lib/features/stats/presentation/stats_screen.dart`, `lib/features/stats/presentation/widgets/stats_filter_bar.dart`, `lib/features/stats/presentation/widgets/stats_aggregate_block.dart`, `lib/features/stats/presentation/widgets/stats_session_list.dart`

**Goal:** Screen zeigt Filter, Aggregate, Liste — Empty-State falls 0 Sessions.

## TASK-7: Trend-Chart Widget

- **Type**: frontend
- **Size**: M
- **Bounded Context**: stats
- **Agent**: coder (frontend)
- **Dependencies**: T6
- **Files**: `lib/features/stats/presentation/widgets/stats_trend_chart.dart`, integration in `stats_screen.dart`

**Goal:** `LineChart` rendert Trendpunkte, Empty-State falls 0/1 Punkte.

## TASK-8: Route + Navigation via AppSettingsModal

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core/ui + stats
- **Agent**: coder (frontend)
- **Dependencies**: T6
- **Files**: `lib/app/router.dart`, `lib/core/ui/settings/app_settings_modal.dart`, `lib/l10n/app_de.arb`

**Goal:** `/stats` Route existiert; Tap auf "Statistik" im AppSettingsModal navigiert dorthin.

## TASK-9: Widget-Tests + Plan-Done

- **Type**: tests + docs
- **Size**: M
- **Bounded Context**: stats
- **Agent**: tester + coder (docs)
- **Dependencies**: T7, T8
- **Files**: `test/features/stats/presentation/stats_screen_test.dart`, `docs/plans/stats-screen/feature-plan.md`

**Goal:** Mind. 3 Widget-Test-Cases (Empty, mit Sessions, Filter-Wechsel). Plan-Doku auf "complete" gesetzt.
