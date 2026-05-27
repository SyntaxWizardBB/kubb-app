# M5 — Schweizer System + Liga-Punkte + Saisontabelle — Offene Entscheidungen

> Status: Resolved — alle 7 ODs am 2026-05-27 vom Owner per Autonom-Mandat geschlossen, Architect-Empfehlungen 1:1 übernommen.
> Datum: 2026-05-27
> ADR-Anker: ADR-0024 (OD-M5-01, OD-M5-02), ADR-0025 (OD-M5-03, OD-M5-04). OD-M5-05..-07 bleiben in dieser Datei dokumentiert (kein eigener ADR nötig).

Folgende Punkte sind vor Implementierungsstart zu klären. Jeder blockt mindestens einen Task aus dem Milestone-Plan. Jeder OD bekommt eine Architect-Empfehlung plus eine Eskalations-Frage an den Owner.

## OD-M5-01: Tiebreaker-Reihenfolge im Schweizer System

**Status**: Resolved — Option B (Buchholz → Direct-Encounter → Random mit Seed).
**Resolution**: Architect-Empfehlung übernommen. Kubb-WM-Konvention ohne Sonneborn-Berger; Random deterministisch via Seed (Turnier-ID + Runden-Nr). Verankert in ADR-0024.

**Frage**: Welche Tiebreaker-Reihenfolge gilt bei gleichem Score im Pairing und in der Schluss-Rangliste — Buchholz, Sonneborn-Berger, Direct-Encounter, Random?

**Warum blockierend**: Bestimmt die Signatur von `BuchholzCalculator` und die Sortier-Logik in `SwissSystemStrategy`. Falsche Reihenfolge führt zu nicht-deterministischen Pairings (für gleiche Eingaben unterschiedliche Outputs).

**Optionen**:

- **A) Klassisch FIDE**: Buchholz → Sonneborn-Berger → Direct-Encounter → Random.
- **B) Kubb-WM-Reglement**: Buchholz → Direct-Encounter → Random (kein Sonneborn-Berger, weil in Kubb selten relevant).
- **C) Nur Buchholz + Random**: schlank, deterministisch, weniger Test-Aufwand.

**Empfehlung des Architect**: **B — Buchholz → Direct-Encounter → Random**. Begründung: Kubb-Turniere folgen real der WM-Konvention. Sonneborn-Berger ist Schach-Idiom und in Kubb nicht etabliert. Direct-Encounter ist intuitiv ("ihr habt gegeneinander gespielt, der Sieger steht vor") und ohne grossen Algorithmus implementierbar. Random als letzte Reserve bleibt deterministisch via Seed (Turnier-ID + Runden-Nr).

**Eskalations-Frage an Owner**: "Folgt euer Liga-Reglement (oder das angepeilte Schweizer Kubb-Reglement) der FIDE-Konvention mit Sonneborn-Berger, oder reicht Buchholz + Direct-Encounter?" — Researcher-Frage an Verbands-Dokumente (Schweizer Kubb-Verband / EKC) falls Owner unsicher.

## OD-M5-02: Liga-Punkte-Schema Default (3-1-0 vs 1-1-1)

**Status**: Resolved — Option A (3-1-0 als Default, pro Turnier konfigurierbar).
**Resolution**: Architect-Empfehlung übernommen. Match-Punkte sind orthogonal zu Liga-Punkten (FR-POINTS-1) und beeinflussen nur die Buchholz-Sortierung im Pairing. Konfigurierbarkeit erlaubt EKC-/Vereins-Reglemente. Verankert in ADR-0024.

**Frage**: Bei der Berechnung von Match-Punkten innerhalb des Turniers — wie viele Punkte gibt es für Sieg / Unentschieden / Niederlage? Fussball-Schema (3-1-0) oder Kubb-EKC-Schema (1-1-1, also alle bekommen Anwesenheitspunkt)?

**Warum blockierend**: `LeaguePointsEngine` braucht die Match-Punkt-Tabelle als Konfig-Input. Default bestimmt, was beim Turnier-Erstellungs-Wizard vorausgewählt ist.

**Optionen**:

- **A) 3-1-0** (Fussball-Style) — stärkere Spreizung, klare Belohnung von Siegen.
- **B) 2-1-0** (klassisch Schach) — moderate Spreizung.
- **C) 1-1-1** (EKC-Style mit Anwesenheitspunkt) — egalitärer.
- **D) Konfigurierbar pro Turnier ohne Default-Empfehlung**.

**Empfehlung des Architect**: **A — 3-1-0 als Default, konfigurierbar pro Turnier**. Begründung: 3-1-0 ist das international etablierteste Schema und passt zur Tournament-Mode-Spec FR-POINTS-1, die Basispunkte über Platzierung berechnet. Match-Punkte innerhalb des Turniers (gegen Liga-Punkte aus FR-POINTS-1) sind orthogonal: Match-Punkte beeinflussen die Buchholz-Sortierung im Pairing, Liga-Punkte folgen FR-POINTS-1. Konfigurierbarkeit erlaubt, EKC- oder Vereins-Reglemente abzubilden.

**Eskalations-Frage an Owner**: "Welches Schema kennen eure Spieler aus dem aktuellen Liga-Betrieb? Wenn überwiegend 1-1-1: Default umstellen, sonst 3-1-0 stehen lassen."

## OD-M5-03: Cross-Tournament-Aggregation — linear oder mit Decay?

**Status**: Resolved — Option A (linear additiv, kein Decay, keine Streichresultate).
**Resolution**: Architect-Empfehlung übernommen. `v_season_standings` ist `SUM(final_points)` über alle Awards der Saison. Spätere ATP-/Streichresultat-Logik bleibt als View-Migration möglich, kein Schema-Bruch. Verankert in ADR-0025.

**Frage**: Wenn ein Spieler in 3 Turnieren je 10 Punkte holt — bekommt er 30 Punkte in der Saison-Tabelle (linear) oder weniger, weil ältere Turniere abgewertet werden (Decay, z.B. ATP-Style)?

**Warum blockierend**: Bestimmt die View `v_season_standings`-Definition. Linear ist trivial (`SUM(final_points)`). Decay verlangt Zeit-Gewichtung im SELECT.

**Optionen**:

- **A) Linear additiv** — `Σ final_points` aller Turniere der Saison.
- **B) Decay** — neuere Turniere zählen mehr (z.B. exponentieller Decay über die Saison-Länge).
- **C) Best-of-N** — nur die N besten Turnier-Ergebnisse zählen (ATP-Modell).

**Empfehlung des Architect**: **A — Linear additiv**. Begründung: Liga-Punkte-Spec (FR-POINTS, FR-GLB) erwähnt keine Decay-Logik; Saison hat in Kubb klares Start-/Endedatum (Wechselfenster Dezember–April, siehe Spec §2 Glossar), Decay ist nicht traditionell. Best-of-N ist Tour-Format (ATP), für Liga unüblich. Linear ist transparent ("jeder Punkt zählt einmal"), Spieler verstehen es ohne Erklärung. Falls später ATP-Modell gewünscht: View-Definition ist eine Migration, kein Schema-Bruch.

**Eskalations-Frage an Owner**: "Soll die Saison-Tabelle alle Turniere linear summieren, oder gibt es im Liga-Reglement eine Streichresultat-Regel (z.B. schlechtestes Turnier zählt nicht)?"

## OD-M5-04: Schweizer-System-Rundenzahl + Pairing-Ort

**Status**: Resolved — (a) Default `ceil(log2(n))`, im Wizard Min 3 / Max 9; (b) Client-Pairing mit RPC-Validation.
**Resolution**: Architect-Empfehlung übernommen. Algorithmus lebt in `kubb_domain` (Dart, property-testbar), Server-RPC `tournament_pair_round` validiert Permutation, Repeat-Schutz und Bye-Constraints (~30 LOC PL/pgSQL). Edge-Function-Option bleibt als Härtung in M6 möglich. Verankert in ADR-0025.

**Frage**: Zwei verwobene Sub-Fragen:
(a) Default-Rundenzahl = ceil(log2(n))? Veranstalter-konfigurierbar?
(b) Wo läuft der Pairing-Algorithmus — Server (PL/pgSQL-Stub plus Dart-Helper über Edge-Function) oder Client (Dart-Domain wird vom UI aufgerufen, Ergebnis als RPC-Argument an Server gepostet)?

**Warum blockierend**: (a) bestimmt Wizard-Validierung. (b) bestimmt M5.2-T3 fundamental: Edge-Function vs reine SQL-RPC.

**Optionen für (b)**:

- **A) Client-Side-Pairing** — `SwissSystemStrategy` läuft in Dart, Client postet Pairings als JSON an RPC, RPC inserted nur (kein Algorithmus serverseitig). Pro: keine Postgres-Algorithmus-Komplexität, Algorithmus testbar in `kubb_domain`. Contra: Trust-Boundary — bösartiger Client kann beliebige Pairings posten. Mitigation: Server validiert Pairing-Set (alle Teilnehmer enthalten, keine Doppel, kein verbotenes Repeat).
- **B) Server-Side über Edge-Function** — Supabase Edge Function (Deno + TypeScript-Port von SwissSystem) führt Pairing serverseitig aus. Pro: Single Source of Truth. Contra: Algorithmus doppelt halten (Dart + TS) oder Algorithmus in Deno-Native (Aufwand). Trust-Boundary saubererer, aber Implementations-Kosten höher.
- **C) Server-Side in PL/pgSQL** — Pairing-Logik in Postgres-Funktion. Contra: PL/pgSQL ist schlechter Boden für Backtracking, Tests sind schmerzhaft. Verworfen.

**Empfehlung des Architect**: (a) **Default = ceil(log2(n)), Veranstalter-konfigurierbar im Wizard mit Min 3, Max 9 Runden**. (b) **A — Client-Side-Pairing mit Server-Validation**. Begründung: Dart-Domain ist Test-Heimat, Algorithmus muss nicht doppelt gehalten werden. Trust-Boundary wird durch RPC-seitige Validation gewahrt (`tournament_pair_round` prüft: Set ist Permutation aller offenen Teilnehmer, kein Repeat aus Vorrunden ausser explizit erlaubt, ein Bye max). Validations-Code ~30 LOC PL/pgSQL.

**Eskalations-Frage an Owner**: "Wieviel Trust-Härte willst du in M5? Wenn Liga-Admin-Manipulation real ist (z.B. Wett-Anreize), brauchen wir Edge-Function (Option B, +2 Tage Aufwand). Sonst reicht RPC-Validation."

## OD-M5-05: Saison-Termin-Vergabe und -Granularität

**Status**: Resolved — Option A (frei konfigurierbar, `transfer_window_*` nullable als Reserve).
**Resolution**: Architect-Empfehlung übernommen. `seasons` bekommt `started_on`, `ended_on`, `transfer_window_start`, `transfer_window_end`; letztere bleiben in M5 NULL. Spieltag-Slots (Option C) sind Premature-Structure für die Pilot-Phase und werden erst bei Bedarf nachgezogen.

**Frage**: Wie streng modellieren wir Saisons? Pro Saison ein Wochenend-Turnier? Saison-Start- und Endedatum frei konfigurierbar? Was passiert mit Turnieren, deren Datum ausserhalb der Saison liegt?

**Warum blockierend**: Bestimmt die Felder von `seasons` (started_on, ended_on, ggf. registration_window) und die Validation bei `season_tournaments`-Insert.

**Optionen**:

- **A) Frei konfigurierbar**: Liga-Admin setzt Start + Ende. Validation nur "Turnier-Datum muss in [start, end] liegen". Keine Termin-Granularität-Annahmen.
- **B) Strukturiert mit Wechselfenster**: Saison hat zusätzlich `transfer_window_start` + `transfer_window_end` (Dezember–April per Spec §2). Erzwingt Saison-Wechsel-Workflow.
- **C) Pro Wochenende ein Turnier-Slot**: Saison wird in Spieltage gegliedert, jeder Spieltag ein Turnier. Maximaler Struktur-Druck. Verworfen — zu starr für Pilot-Phase.

**Empfehlung des Architect**: **A — Frei konfigurierbar in M5, mit `transfer_window_*`-Feldern als nullable Vorbereitung für FR-GLB-11**. Begründung: M5 hat Liga-Wechsel-Workflow NICHT in Scope (siehe `risks-and-deferrals.md` R-M5-G1). Wir reservieren die Spalten, lassen sie aber leer; spätere Workflow-Erweiterung muss kein Schema migrieren. Pilot-Liga ist klein genug, dass Liga-Admin manuell entscheidet, welches Turnier zur Saison zählt.

**Eskalations-Frage an Owner**: "Welche Saison-Strukturen siehst du in der Pilot-Phase real? Wenn eine echte Liga mit 8 Spieltagen pro Saison startet, brauchen wir Spieltag-Slots (Option C). Sonst belassen wir's bei Option A."

## OD-M5-06: Saison-Tabellen-Sortierung — Punkte / Anwesenheit / Hybrid

**Status**: Resolved — Option A (Σ Punkte desc, Tiebreak Turnier-Anzahl, danach Anzeigename).
**Resolution**: Architect-Empfehlung übernommen. Punkte sind das primäre Ranking-Signal (FR-RANK-1), Anwesenheit ist sekundärer Tiebreak. Liga-Konfigurierbarkeit (Option D) ist Premature-Customization und wird bei Bedarf als UI-Erweiterung nachgezogen. Kein Mindest-Teilnahme-Filter — alle Liga-Mitglieder erscheinen in der Tabelle.

**Frage**: Default-Sortierung im `season_standings_screen` — nach Σ Punkten allein, nach Anzahl Turniere (Anwesenheit), oder Hybrid (z.B. nur Spieler mit ≥N Turnieren werden sortiert, andere am Ende)?

**Warum blockierend**: Bestimmt UI-Default, ist UX-relevant fürs Liga-Erlebnis.

**Optionen**:

- **A) Σ Punkte absteigend, Tiebreak Anzahl Turniere**.
- **B) Σ Punkte absteigend, kein Anwesenheits-Filter**.
- **C) Hybrid**: Spieler mit ≥3 Turnieren oben sortiert, weniger-präsente Spieler in einer "Restliste" darunter.
- **D) Konfigurierbar pro Liga**.

**Empfehlung des Architect**: **A — Σ Punkte absteigend, Tiebreak nach Anzahl Turniere, danach alphabetisch nach Anzeigename**. Begründung: Punkte sind das primäre Ranking-Signal (FR-RANK-1). Anwesenheits-Tiebreak belohnt Liga-Engagement bei Punktgleichheit. Konfigurierbarkeit (Option D) ist Premature-Customization — wenn Liga-Admins später widersprechen, ist es eine UI-Erweiterung.

**Eskalations-Frage an Owner**: "Erwartest du, dass Liga-Mitglieder mit nur 1 Turnier in der Saison-Tabelle voll mitgezählt werden, oder soll es eine Mindest-Teilnahme geben?"

## OD-M5-07: Punkte-Vergabe-Zeitpunkt und Re-Compute-Verhalten

**Status**: Resolved — Append-only-Ledger mit Reversal-Rows.
**Resolution**: Architect-Empfehlung übernommen. Punkte werden sofort bei `tournament.status = finalized` als Award geschrieben. Korrekturen erzeugen Reversal-Rows (negative `final_points` + Note) plus neue Awards. View `v_season_standings` summiert über alle Rows — vollständige Audit-Trail, kein Mutations-Bug-Risiko, deckt FR-POINTS-13. Keine Einspruchs-Frist.

**Frage**: Wann werden Liga-Punkte fest? Sofort bei Turnier-Finalisierung (immutable Award-Row), oder erst nach Konflikt-Frist (z.B. 24h Einspruchs-Fenster)? Was passiert, wenn nachträglich ein Score korrigiert wird?

**Warum blockierend**: Bestimmt das Verhalten des `SeasonPointsSink`-Adapters und ob `season_standings_awards` mutable oder append-only ist.

**Empfehlung des Architect**: **Append-only-Ledger mit Reversal-Rows**. Punkte werden sofort bei Turnier-Status=`finalized` geschrieben. Wenn nachträglich korrigiert wird, fügen wir Reversal-Rows ein (negative `final_points` mit Begründungs-Note), neue Awards werden zusätzlich geschrieben. View `v_season_standings` summiert über alle Rows. Vorteil: vollständige Audit-Trail, kein Mutations-Bug-Risiko, FR-POINTS-13 rückwirkende Einbuchung wird natürlich abgebildet.

**Eskalations-Frage an Owner**: "Reicht uns dieser Audit-Trail-Ansatz, oder willst du, dass Punkte erst nach einer Einspruchs-Frist (z.B. 24h) gebucht werden?"
