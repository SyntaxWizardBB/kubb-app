# Sprint-Plan — Sniper-Training MVP (F1)

## Meta
- Slug: sniper-training-mvp
- Erstellt: 2026-05-02
- Gesamt-Tasks: 24
- Geschätzte Stunden: 39.5h (Senior, Faktor 0.8 bereits eingerechnet)
- Größen-Mapping: S=0.5–1h, M=1–3h, L=3–5h

## Übersicht

Fünf Milestones, jeder liefert ein eigenständig demonstrierbares Teilergebnis. Schnittlogik:

1. **M1 — Fundament & Theme**: pubspec, drei `ThemeData`-Instanzen, AppShell mit go_router, l10n-Pipeline. Demo: App startet leer, Theme-Wechsel funktioniert per Provider-Mock.
2. **M2 — Core-DB**: drift-Schema v1 mit vier Tabellen, DAOs, In-Memory-Tests. Demo: alle DB-Operationen grün via Tests, kein UI.
3. **M3 — Player & Settings**: Profil-Onboarding-Flow + AppSettings-Persistenz. Demo: Erststart fragt Namen, AppSettingsModal toggelt Theme persistent.
4. **M4 — Reusable Widgets & HomeScreen**: KubbTapPad, KubbCounter, KubbAppBar, KubbBottomSheet plus HomeScreen mit Recent-Liste, Tournier-Karte, News-Link. Demo: HomeScreen lädt mit leerer Recent-Liste, FAB öffnet TrainingSheet.
5. **M5 — Sniper-Flow & Crash-Recovery**: Voller Trainings-Flow inklusive Recovery, Eye-Toggle, Heli-Filter, SummaryScreen, Integration-Test. Demo: Komplette MVP-User-Journey vom Tap auf FAB bis Summary, inklusive Force-Kill-Restart.

TDD greift in M5 für die Notifier-Logik (Hit/Miss/Heli-Aggregation, Heli-Filter, Crash-Recovery). Reine UI-Tasks bleiben ohne Test-First.

## Milestones

| ID | Name | Tasks | Geschätzt (h) | Beschreibung |
|---|---|---|---|---|
| M1 | Fundament & Theme | 5 | 5.5 | Deps, Tokens, drei Themes, AppShell, l10n-Pipeline |
| M2 | Core-DB | 4 | 7.5 | drift-Schema, DAOs, In-Memory-Tests, DB-Provider |
| M3 | Player & Settings | 5 | 6.5 | Profile, Onboarding, AppSettings, AppSettingsModal |
| M4 | Reusable Widgets & HomeScreen | 5 | 7.5 | TapPad / Counter / AppBar / BottomSheet, HomeScreen |
| M5 | Sniper-Flow & Crash-Recovery | 5 | 12.5 | TrainingRepo, Notifier (TDD), Screens, Recovery, Tests |
| **Gesamt** | | **24** | **39.5** | |

## Ausführungsreihenfolge

### M1 — Fundament & Theme

| Task | Titel | Größe | Abhängig von |
|---|---|---|---|
| M1-T1 | Pubspec-Dependencies für F1 | S | — |
| M1-T2 | KubbTokens als ThemeExtension | S | M1-T1 |
| M1-T3 | KubbTheme — Light/Dark/HighContrast | M | M1-T2 |
| M1-T4 | l10n-Pipeline + leere de.arb | S | M1-T1 |
| M1-T5 | AppShell + go_router-Skelett | M | M1-T3, M1-T4 |

### M2 — Core-DB

| Task | Titel | Größe | Abhängig von |
|---|---|---|---|
| M2-T1 | drift-Schema v1: vier Tabellen + Indizes | M | M1-T1 |
| M2-T2 | DAOs: Player / Session / SessionEvent / AppSettings | M | M2-T1 |
| M2-T3 | appDatabaseProvider + AppSettings-Wertobjekt | S | M2-T2 |
| M2-T4 | DAO-Tests in-memory | M | M2-T2 |

### M3 — Player & Settings

| Task | Titel | Größe | Abhängig von |
|---|---|---|---|
| M3-T1 | PlayerRepository + currentProfileProvider | S | M2-T3 |
| M3-T2 | OnboardingScreen mit Validierung | M | M3-T1, M1-T5 |
| M3-T3 | ProfileScreen (read-only) | S | M3-T1, M1-T5 |
| M3-T4 | AppSettingsNotifier mit Persistenz | M | M2-T3 |
| M3-T5 | AppSettingsModal | M | M3-T4 |

### M4 — Reusable Widgets & HomeScreen

| Task | Titel | Größe | Abhängig von |
|---|---|---|---|
| M4-T1 | KubbAppBar + KubbBottomSheet | M | M1-T3 |
| M4-T2 | KubbTapPad + KubbCounter | M | M1-T3 |
| M4-T3 | KubbIcons (Brand + lucide-Wrapper) | S | M1-T3 |
| M4-T4 | TrainingSheet (FAB-Sheet) | S | M4-T1 |
| M4-T5 | HomeScreen mit Recent-Karte, Tournier, News-Link | M | M4-T1, M4-T3, M4-T4, M3-T1, M3-T5 |

### M5 — Sniper-Flow & Crash-Recovery

| Task | Titel | Größe | Abhängig von |
|---|---|---|---|
| M5-T1 | TrainingRepository + recentSessionsProvider | M | M2-T3 |
| M5-T2 | Tests für ActiveSessionNotifier (TDD) | M | M5-T1 |
| M5-T3 | ActiveSessionNotifier — Tap / Undo / Heli-Filter | M | M5-T2 |
| M5-T4 | SniperConfig + SniperSession + AbortDialog + Summary | L | M5-T3, M4-T2, M4-T1 |
| M5-T5 | crashRecoveryProvider + CrashRecoveryDialog + Integration-Test | M | M5-T1, M5-T4, M4-T5 |

## Critical Path

Längster Dependency-Pfad bis MVP-Demo:

`M1-T1 → M1-T3 → M1-T5 → M3-T1 → M3-T5 → M4-T5 → M5-T5`

Sieben Tasks, ~12.5h. Innerhalb davon sind die Engpässe:

- **M1-T3** (KubbTheme): blockt jedes UI-Widget. Wenn Theme nicht clean ist, fängt die ganze Pipeline an zu wackeln.
- **M2-T2** (DAOs): blockt sowohl Player- als auch Settings- als auch Training-Spur. Ohne DAOs steht alles Datenrelevante.
- **M5-T3** (ActiveSessionNotifier): die zentrale Logik des Features. TDD-Vorlauf in M5-T2 ist Pflicht.
- **M5-T4** (Sniper-Screens): grösster Task (L), Splittung wäre möglich (Config / Session / Summary), wurde aber bewusst zusammengelassen, weil die drei Screens am Notifier hängen und sich ein Commit anbietet. Wenn beim Implementieren > 5h droht, splitten.

## Fortschritt

| Milestone | Done | In Progress | Blocked | Pending | Total |
|---|---|---|---|---|---|
| M1 | 3 | 0 | 0 | 2 | 5 |
| M2 | 0 | 0 | 0 | 4 | 4 |
| M3 | 0 | 0 | 0 | 5 | 5 |
| M4 | 0 | 0 | 0 | 5 | 5 |
| M5 | 0 | 0 | 0 | 5 | 5 |
| **Gesamt** | **3** | **0** | **0** | **21** | **24** |

## Risiken & Mitigation

Übernommen aus dem Architektur-Plan plus neue Risiken aus dem Schnitt:

| Risiko | Wahrscheinlichkeit | Impact | Mitigation |
|---|---|---|---|
| Theme-Re-Render bei HighContrast-Wechsel zeigt noch Light-Tokens (Architektur-Plan, "Theme-Re-Renders") | mittel | hoch | M1-T3 enthält explizit drei separate `ThemeData`-Instanzen mit eigenen Token-Registrierungen. Widget-Test prüft Token-Wert pro Mode. |
| `currentProfileProvider`-AsyncLoading führt zu Flash-of-Onboarding bei jedem Cold-Start | mittel | mittel | go_router `refreshListenable` wartet auf den ersten emittierten Value (kein redirect bei `loading`). Test in M1-T5. |
| `MaterialApp.themeMode` reagiert nicht auf HC, weil HC kein nativer ThemeMode ist | hoch | mittel | M1-T3 baut `ThemeChoice`-Mapper, der HC als `ThemeData` direkt im `theme:`-Slot ausliefert (statt `themeMode`). |
| Sniper-Flow-Task M5-T4 wird > 5h | mittel | mittel | Wenn beim Implementieren erkennbar zu gross, splitten in M5-T4a (Config), M5-T4b (Session + AbortDialog), M5-T4c (Summary). Eskalation an Owner ist nicht nötig, ist ein reines Splitting. |
| drift-on-Web-Spike fehlt noch (CLAUDE.md, MUST-FIX 1) | niedrig für F1 | niedrig | F1 ist Android- und Linux-Target-only. Web bleibt explizit ungetestet (per po-output.md "Plattform-Targets"). Kein Blocker für diese Iteration. |
| Heli-Filter-Logik wird über mehrere Provider verteilt → inkonsistent | mittel | hoch | M5-T2 schreibt explizit Tests sowohl für `recentSessionsProvider` als auch für `ActiveSessionNotifier` mit `heliTracking=on/off`. Filter-Selektor ist EIN Helper, nicht zwei. |
| Crash-Recovery zeigt Dialog auch bei frischem Profil-Onboarding-Flow | niedrig | mittel | M5-T5 platziert `crashRecoveryProvider`-Aufruf erst NACH Profil-Check im HomeScreen.initState (per Architektur "Reihenfolge beim App-Start" Punkt 5). |
| `url_launcher` Web-Verhalten unklar | niedrig | niedrig | F1 testet nur Android + Linux. Web-Target ohne `url_launcher_web` ist Folge-Iteration. |

## Owner-Eskalationen

Keine. Alle 10 Q-Punkte aus po-output.md sind beantwortet, Architektur-Plan hat keine offenen Klärungen. Wenn beim Implementieren ein Task > L wird, splittet der `/agents/coder` selbständig — Eskalation nur, falls drei Splitting-Versuche scheitern.
