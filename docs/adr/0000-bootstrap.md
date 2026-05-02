# ADR-0000: Project bootstrap decisions

- **Status**: Accepted
- **Date**: 2026-05-02

## Decisions locked at project bootstrap

These are confirmed by the project owner and not up for revision without an explicit ADR superseding them.

### Framework

- **Flutter 3.41.9 / Dart 3.11.5** (stable channel). Single codebase for mobile, web, and desktop.
  - Rationale: cross-platform reach (organizer on laptop, players on phone) without maintaining two codebases.

### Target platforms (Phase 1)

- **Android**, **Web**, **Linux Desktop**.
- Out of scope for v1: iOS (requires macOS or cloud-CI; deferred until v1 ships).

### UI language

- **Material 3** (`useMaterial3: true`) with a seed color (`#C8102E` — Swiss red), light + dark theme.

### Internationalization

- **flutter_localizations + intl + ARB** as the i18n stack.
- Phase 1 ships only `de` (Switzerland). Codebase is structured so adding `en`/`fr`/`it` is mechanical.
- All user-facing strings go through `AppLocalizations`.

### Code conventions

- **Identifier language**: English.
- **Comments**: English. Comments are rare — only when "why" is non-obvious. No "AI-generated" markers.
- **Linter**: `very_good_analysis` (strict). `flutter analyze` must be clean.
- Domain terms (Kubb, König, Wurfstock, Anspiel, etc.) keep their German/Swedish form as proper nouns.

### Test strategy

- Ambitious coverage: unit (domain), widget (screens), integration (flows), golden (critical components).
- `flutter test` must be green before any commit lands on main.

### Repository

- Hosted on GitHub, **private**, account `SyntaxWizardBB`.
- Per `~/Workbench/CLAUDE.md`: no AI traces in commits or files. Commit messages read as written by Lukas.
- `CLAUDE.md`, `.claude/`, and `docs/rules/*.pdf` are gitignored.

### Active rule set

- **Schweizer Kubbverband v1.11** (April 2026) is the first concrete rule set.
- Engine designed as parameterized `RuleSet` to allow other rule sets later (WCK, Hausregeln, etc.).

### Out of scope (Phase 1)

- Detailed per-player statistics dashboards.
- League points / Masters qualification computation.
- iOS builds.
- CI/CD pipeline (design at end of MVP).
- Custom rule editor UI.

## Consequences

- The bootstrap is opinionated and minimal — only the dev loop, lint, l10n, and Material 3 are wired up. Everything domain-shaped (state management, persistence, networking, routing) is deferred to ADR-0001 to allow a deliberate stack choice with the user in the loop.
- Anyone joining the project can run `flutter analyze` and `flutter test` and get a green baseline immediately.
