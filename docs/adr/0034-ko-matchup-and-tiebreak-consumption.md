# ADR-0034: KO-Matchup & Tiebreak-Methode — echte Konsumierung (Klassik + Stufen-Graph)

- **Status**: Accepted
- **Date**: 2026-06-18
- **Bezug**: ADR-0033 §4 (Stufen-Knoten-Config); Compliance-Review 2026-06-18;
  Engine-Surface-Investigation (Owner-Entscheid „auch Klassik nachrüsten").

## Kontext (selbst verifiziert)

Die ADR-0033-§4-Arbeit deckte auf, dass **zwei KO-Konfigurationen heute reine
Stubs sind — auch im klassischen Pfad**:

1. **`ko_matchup`** (`seed_high_vs_low` | `one_vs_two`): gespeichert in
   `tournaments.ko_matchup` (Migration `…001000001`) und in
   `tournament_start_ko_phase` persistiert, aber **nie konsumiert**.
   `_tournament_compute_ko_bracket(p_seeds jsonb, p_third_place boolean)`
   (`20260601000014`) wendet **immer** die rekursive Standard-Bracket-Ordnung an
   (1 vs N, 2 vs N-1, …); der zweite Param ist `with_third_place`, **nicht**
   Matchup. `one_vs_two` (1 vs 2, 3 vs 4, …) wird nirgends erzeugt.

2. **`ko_tiebreak_method`** (`classic_kingtoss_removal` |
   `mighty_finisher_shootout`): gespeichert in `tournaments.ko_tiebreak_method`,
   aber **nirgends gelesen** — nicht bei Generierung, Scheduling, Resolution.
   Der bestehende Shootout-Server (`20261202000000`) löst **Vorrunden-
   Qualifikations-Ties** (Pool), **nicht** KO-Match-Gleichstände;
   `mighty_finisher_shootout` ist dort ausdrücklich „out-of-band".

→ „Parität mit Klassisch" für diese zwei = **speichern + anzeigen** (das tut
Klassisch). Echte *Konsumierung* ist ein **neues Verhalten**, das die ADR-0033
nicht hatte. Owner-Entscheid: **echt konsumieren, in BEIDEN Pfaden** (konsistent,
keine Stage-vs-Klassik-Divergenz).

## Entscheidung

### 1. Matchup — Bracket-Round-1-Pairing (Klassik + Stage)
Die Round-1-Paarung respektiert `ko_matchup`:
- `seed_high_vs_low` (Default): unverändert (Standard-Bracket-Ordnung).
- `one_vs_two`: benachbarte Setzplätze treffen sich (1-2, 3-4, …).

Umsetzung: **`_tournament_compute_ko_bracket` erhält einen additiven dritten
Parameter `p_matchup text DEFAULT 'seed_high_vs_low'`** (rückwärtskompatibel; alle
Bestandsaufrufe behalten Default). Round-1-Seed-Slot-Belegung verzweigt auf
Matchup; **spätere Runden + Bracket-Integrität bleiben unverändert** (Gewinner
steigen in dieselben `bracket_position`-Slots auf). Klassik ruft mit
`tournaments.ko_matchup`, Stage mit `config->>'ko_matchup'`. Pure-Dart-Mirror
(`_standardBracketOrder`) analog erweitern, damit Domain-Vorschau matcht.

### 2. Tiebreak-Methode — KO-Match-Gleichstand-Auflösung (NEUES Feature)
Bei einem in der regulären Zeit **unentschiedenen KO-Match** bestimmt
`ko_tiebreak_method`, **wie** entschieden wird:
- `classic_kingtoss_removal`: zweiter King-Toss, dann pro Runde ein Kubb entfernt
  — physisch gespielt, App **erfasst nur das Ergebnis** (Sieger).
- `mighty_finisher_shootout`: Mighty-Finisher-Shootout als Decider — erfasst über
  den Shootout-Erfassungs-Flow.

**Diese Methode hat KEINE bestehende Infrastruktur** (der Pool-Shootout-Server ist
ein anderes Konzept). Konsum = Eingriff in den **Match-Scoring-/Finalize-Flow**
(`tournament_match_detail_screen`, Score-RPC) + ein Methoden-abhängiger Tiebreak-
Erfassungs-Schritt. Das ist **kein Verdrahten, sondern ein eigenständiges Feature**
und wird **separat und zuletzt** gebaut (eigener Plan-Block, eigene Tests, kein
Eingriff in die Match-Generierung).

### 3. Sequenzierung & Risiko
Die genuin sicheren/tractablen Teile zuerst, das Match-Resolution-Feature zuletzt:
1. **Pool-Multi-Gruppen (Stage)** — `_tournament_compute_pools` wiederverwenden;
   additiv, berührt Klassik nicht. (ADR-0033 §4, sofort.)
2. **Voll-Config-UI pro Knoten** (Matchup/Tiebreak/Per-Runden-Format/Grouping) —
   schreibt die Keys; Parität mit Klassik. (ADR-0033 §4, sofort.)
3. **Matchup-Konsum** (dieser ADR §1) — beide Pfade; additiver Bracket-Param.
   Berührt **live KO-Generierung** → Probe in BEGIN/ROLLBACK, Goldens prüfen.
4. **Per-Runden-Format (Stage-Runde 1)** — neuer stage-aware Schedule-Helper.
   Ehrlich-teilweise: spätere Stage-KO-Runden haben **noch keinen** Scheduler
   (separater ADR-0031-Nachbau) — wird dokumentiert, nicht stillschweigend.
5. **Tiebreak-Methoden-Konsum** (dieser ADR §2) — **eigenes Feature**, zuletzt,
   eigener Plan/Tests; Scoring-Flow-Eingriff.

## Abgrenzung / Guardrails
- Klassik-KO-Pfad ist **nicht eingefroren** (nur Solo-Training ist es), aber
  **live-relevant** → jede Funktionsänderung additiv, Stale-Body per
  Höchst-Timestamp-Grep, Probe in `BEGIN/ROLLBACK`, **kein `db reset`**, Goldens
  (Bracket) + Suite grün vor Commit.
- Bracket-Math-Änderung NUR Round-1-Pairing; Aufstiegs-Slots/`bracket_position`
  unverändert (sonst bräche die Advance-Logik).
- Tiebreak-Feature (§2) fasst die Match-Generierung **nicht** an.

> Reihenfolge im Plan (PLAN.md P5.3*): pool → UI → matchup → stage-round1-format →
> tiebreak-feature. Schritte 1–2 liefern sofort sichtbaren §4-Wert; 3–5 sind die
> echten Engine-/Feature-Eingriffe mit je eigener Verifikation.
