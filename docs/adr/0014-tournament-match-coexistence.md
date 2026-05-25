# ADR-0014: Tournament-Match-Pfad neben Solo-Match-Pfad

- **Status**: Accepted
- **Date**: 2026-05-25
- **Depends on**: ADR-0002 (bounded contexts), ADR-0012 (social + Solo-Match), ADR-0013 (Solo-Match server-shaped)
- **Bezug**: `docs/plans/tournament-foundation/architecture.md` §3.3, `open-decisions.md` OD-06

## Kontext

Solo-Match (per ADR-0012, Implementierung per ADR-0013) lebt seit Phase 2 als server-shaped Feature in `public.matches` + zugehörigen RPCs. Die Reconciliation-Logik (`_match_try_reconcile`) erwartet pro Round-Proposal ein Tripel `(winner_team_id, score_a, score_b)` — also ein **Match-Total**-Resultat, kein Satz-genauer Score.

Turniermodus verlangt zwei zusätzliche Dinge:

1. Eingabe **pro Satz** (Basekubbs Team A, Basekubbs Team B, König gefällt von) statt nur Match-Total — Voraussetzung für die EKC-Punktevergabe und den Tiebreaker "Kubb-Differenz" (FR-RANK-4).
2. Verknüpfung des Matches mit einer Turnier-Runde, einem Pitch und ggf. einem Roster — Felder, die in Solo-Match keinen Sinn haben.

Es gibt drei plausible Wege, das zu modellieren — siehe Alternativen unten.

## Entscheidung

**Turnier-Matches teilen die Identität (`public.matches.id`) mit Solo-Matches, aber den Schreib-Pfad nicht.**

Konkret:

- `public.matches` bekommt eine zusätzliche Spalte `tournament_id uuid NULL REFERENCES public.tournaments(id) ON DELETE CASCADE`. Solo-Matches haben NULL.
- Neue Tabelle `tournament_matches(match_id PK FK, tournament_id, tournament_round_id, pitch_number, participant_a_id, participant_b_id, is_bye bool, is_forfeit bool, forfeit_against text NULL)`. Pro Turnier-Match ein Eintrag.
- Neue Tabelle `tournament_set_scores(match_id, attempt, user_id, set_index, basekubbs_a, basekubbs_b, king_felled_by)`. Pro Satz-Eingabe-Versuch ein Eintrag, indexiert via PK auf (match_id, attempt, user_id, set_index).
- Neue RPCs: `tournament_propose_set_score`, `tournament_organizer_override`, `tournament_start_round`, `tournament_finalize`. Diese arbeiten mit Satz-Daten und schreiben in `tournament_set_scores`, vergleichen pro Versuch über alle teilnehmenden User, finalisieren `matches.status = 'finalized'` bei Übereinstimmung.
- Solo-Match-RPCs (`match_propose_result`, `match_get`, `match_finish_play`) bleiben **unverändert**. Sie ignorieren `tournament_id`.

Der Lese-Pfad ist gemeinsam: `match_get` funktioniert für beide Welten (gibt das Tournament-Bündel mit dazu wenn `tournament_id IS NOT NULL`).

## Alternativen

### A — Gemeinsamer Schreib-Pfad

Eine RPC `match_propose_result_v2`, die ein flexibles Schema akzeptiert (entweder Match-Total für Solo, oder Satz-Liste für Turnier). Die Reconciliation-Logik wird verzweigend.

**Verworfen**, weil:
- Ein Eingriff in lauffähigen Solo-Match-Code, mit konkretem Regressions-Risiko in einer schon ausgelieferten Feature-Schicht.
- Die Reconciliation-Logik wird zur if-tournament-then-else-Konstruktion in SQL — schwer zu lesen, schwer zu testen.
- Die Audit-Trail-Payloads weichen ohnehin auseinander.

### C — Komplett getrennte Match-Tabellen

`tournament_matches` als eigenständige Tabelle ohne FK auf `public.matches`. Solo-Match und Turnier-Match haben keine gemeinsame Identität.

**Verworfen**, weil:
- Match-Historie pro User (FR-PROFILE-4: "Match-Historie filterbar nach Gegner, Turnier, Format, Ergebnis") braucht eine einheitliche Sicht. Mit zwei Tabellen wird das `UNION ALL` mit Spalten-Mapping.
- Spätere Vereinheitlichung (wenn beide Welten mehr Code teilen) wird teurer als jetzt mit der gemeinsamen ID anzufangen.

## Konsequenzen

### Positiv

- Solo-Match-Code wird nicht berührt. Keine Regressions-Risiken in einer ausgelieferten Funktion.
- Match-Historie pro User funktioniert über eine einzige `public.matches`-Tabelle (mit zwei optionalen Detail-Joins).
- `tournament_set_scores` ist konzeptuell sauber: ein Datensatz pro Satz-Eingabe, was die FR-SCORE-Anforderungen 1:1 abbildet.
- Server-RPC-Anzahl bleibt überschaubar — vier neue RPCs, keine Erweiterung bestehender.

### Negativ

- Zwei parallele Schreib-Pfade müssen langfristig gewartet werden. Bug-Fixes in der Reconciliation-Logik müssen ggf. in beiden RPCs nachgezogen werden.
- RLS-Policies auf `public.matches` müssen jetzt zwei Berechtigungs-Pfade kennen: "Solo-Match-Participant" und "Tournament-Team-Member". Policy-Beschreibung wird länger.

### Neutral

- Die spätere Konsolidierung (wenn Tournament-Match-Anteil ⩾ Solo-Match-Anteil ist und/oder Solo-Match veraltet) ist möglich: eine zentrale `propose_result(payload jsonb)`-RPC mit Adapter-Logik. Diese Option bleibt offen.
- Audit-Logs bleiben in zwei Tabellen (`match_audit_events`, `tournament_audit_events`). Eine spätere Vereinheitlichung ist machbar, aber nicht MVP.

## Migration

Eine neue Migrations-Datei `20260601000001_tournament_schema.sql` legt die neuen Tabellen + RPCs + RLS-Policies an und fügt die `tournament_id`-Spalte zu `public.matches`. Default NULL, kein Datenmigrations-Schritt erforderlich.

## Offene Punkte

- RLS-Policy `matches_participant_read`: muss um den Tournament-Lese-Pfad erweitert werden (Tournament-Team-Member oder Public-View für `tournaments.status IN (published, live, completed)`).
- Index-Strategie auf `tournament_set_scores`: PK auf (match_id, attempt, user_id, set_index) plus Sekundär-Index auf (match_id, attempt) für den Vergleichs-Lookup.
