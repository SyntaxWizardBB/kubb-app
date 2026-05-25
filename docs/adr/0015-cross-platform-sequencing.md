# ADR-0015: Cross-Platform-Sequenzierung für den Tournament-MVP

- **Status**: Accepted
- **Date**: 2026-05-25
- **Bezug**: ADR-0005 (per-platform persistence), `docs/plans/tournament-foundation/open-decisions.md` OD-02

## Kontext

Der Owner-Ziel-Stack ist Flutter auf fünf Plattformen: iOS, Android, Windows, Web, Linux. Der aktuelle Stand auf der Dev-Maschine ist:

- **Android**: funktioniert. Demo-fähig.
- **iOS**: kein Build-Setup vorhanden (kein Apple Developer Account, kein macOS-Build).
- **Linux**: Build scheitert an pkg-config-Kette für sqlite3_flutter_libs. Liegt am dev-Setup, nicht am Code.
- **Web**: nicht getestet. ADR-0005 sah einen WASM-Spike vor, der noch nicht durchgeführt wurde — drift braucht entweder sqlite3.wasm + OPFS oder die `SupabaseTournamentRemote`-only-Variante.
- **Windows**: kein Build-Setup, kein Test.

Der Tournament-MVP-Slice braucht eine Plattform-Entscheidung, sonst gerät die erste Milestone in unnötige Plattform-Reibung.

## Entscheidung

**Tournament-MVP zielt auf Android allein. Web wird vor M2 nachgezogen. iOS, Linux, Windows nach M5.**

Begründung in Reihenfolge der Priorität:

1. **Android funktioniert heute**. Owner hat ein eigenes Phone, kann die Demo unmittelbar laufen lassen. Keine Build-Pipeline-Investition vor erstem Feature-Test.
2. **Web wird mit M2 zwingend** — Veranstalter-Setup-Wizard ist komplex und auf dem Tablet/Browser bedeutend angenehmer. Spätestens für das Live-Dashboard (M4) ist Web obligatorisch. Vor M2 ist ein 2-Tage-Spike vorgesehen, um zu klären, ob der `SupabaseTournamentRemote`-only-Pfad auf Web (ohne lokales drift) sauber durchzieht. Das ist die ADR-0005-vorgesehene Web-Variante.
3. **iOS verlangt Pipeline-Investition** — Apple Developer Account ($99/Jahr), macOS-Build-Maschine oder Cloud-Build-Service. Nicht im MVP-Wertbeitrag, sondern Distribution-Topic. Verschoben nach M5.
4. **Linux** ist Dev-Komfort, nicht User-Target. Wird nachgezogen wenn der pkg-config-Bug Zeit kostet — eigener Tag, sobald Owner es selbst lokal nutzen will.
5. **Windows** wird mit Linux/iOS angesehen — nach M5.

## Konsequenzen

### Positiv

- Schnellster Pfad zum demobaren MVP. Keine 1–2 Wochen Build-Pipeline-Setup vor dem ersten Feature-Test.
- Web kommt früh genug für die Veranstalter-Rolle. Veranstalter sitzt im MVP-Demo am Phone, ab M2 am Browser.
- Klare Sequenz, keine "Alles-Parallel"-Falle.

### Negativ

- iOS-User können den MVP nicht testen. Wenn das Pilot-Publikum stark iOS-affin ist (Schweizer Sport-Demographie kann das durchaus sein), entsteht Reibung beim Recruiting von Test-Spielern.
- Linux-Build-Fix wird länger ungelöst.
- Web-Spike kostet 2 Tage, die vom Feature-Zeitbudget abgehen.

### Neutral

- ADR-0005 bleibt der Anker: Web nutzt Supabase als einzige Persistenz + `IndexedDbDraftCache` für UI-State. Kein drift-on-Web.

## Alternativen

### A — Alle 5 Plattformen ab M1

**Verworfen** wegen Pipeline-Setup-Kosten:
- macOS-Build-Maschine + Apple Developer Account-Onboarding: 3–7 Tage.
- pkg-config-Fix Linux: 0.5–2 Tage.
- Web-Spike + IndexedDB-Cache-Implementierung: 3–5 Tage.
- Windows-Build-Smoke-Test: 1 Tag.

Summe vor erstem Feature-Code: 1.5–3 Wochen. Im 3–4-Wochen-MVP-Slice wären das 30–80 % des Budgets. Nicht tragbar.

### B — Android + Web ab M1 parallel

Diskutabel. Pro: Veranstalter-UX ab MVP angenehm. Contra: Web-Spike + IndexedDB-Layer ist Vorbereitungs-Aufwand, der dem MVP-Feature-Fortschritt direkt abgeht (3–5 Tage). Web wird für den 8-Spieler-Pilot-Demo nicht benötigt; Owner kann das Setup auch am Phone bedienen.

**Verworfen für den MVP, übernommen für M2**.

### C — Nur Android, Web/iOS/Linux/Windows beliebig später

Diskutabel. Pro: maximale Simplizität. Contra: Owner hat Web/Tablet als Veranstalter-Setup im Kopf, lange Wartezeit auf Web ist UX-schädlich. Mit M2-Frist ist die Sequenz B-erweitert-für-M2 besser.

**Verworfen** zugunsten der gewählten Sequenz.

## Folgepunkte

- Vor M2: 2-Tage-Spike "Flutter Web mit `SupabaseTournamentRemote`-only ohne drift". Spike-Ergebnis als Mini-ADR oder Update zu diesem ADR.
- Vor iOS-Einstieg: eigene ADR zur Distribution (App Store, TestFlight, Apple Developer-Account-Onboarding).
- Linux-Build-Fix: separater Task, nicht in M1–M5.

## Status-Notiz

Sobald M1 abgenommen ist und der Web-Spike ansteht, wird dieses ADR auf "Accepted" gehoben. Bis dahin **Proposed** — Owner kann Sequenz noch verschieben (siehe OD-02 in `open-decisions.md`).
