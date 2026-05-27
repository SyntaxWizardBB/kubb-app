# ADR-0025: M5 — Saison-Aggregation linear + Schweizer-Pairing client-side mit Server-Validation

- **Status**: Accepted
- **Date**: 2026-05-27
- **Depends on**: ADR-0001 (Supabase Auth + DB), ADR-0014 (Tournament-Match-Coexistence), ADR-0022 (Offline-Sync-Outbox), ADR-0024 (Tiebreaker + Match-Punkte)
- **Bezug**: `docs/plans/m5-swiss-league-season/architecture.md` §3 (Datenmodell, `SwissSystemStrategy`), `open-decisions.md` OD-M5-03 + OD-M5-04, `docs/specs/tournament-mode-spec.md` §3.7 (FR-PAIR), §3.15 (FR-GLB)

## Kontext

M5 führt zwei verbundene Entscheidungen zusammen:

1. **Wie aggregiert die Saison-Tabelle Liga-Punkte über mehrere Turniere?** Linear (Σ aller Awards), mit Decay (ATP-Stil), oder Best-of-N (Streichresultate)? Die Wahl bestimmt `v_season_standings`.
2. **Wo läuft der Schweizer-Pairing-Algorithmus?** Server-seitig (Edge-Function oder PL/pgSQL) oder client-seitig (Dart-Domain) mit Server-Validation?

Die Aggregations-Wahl wirkt auf View-Komplexität und Spieler-Verständnis. Die Pairing-Ort-Wahl wirkt auf Trust-Boundary, Test-Heimat und Implementations-Aufwand.

OD-M5-03 und OD-M5-04 haben je drei Optionen diskutiert; dieser ADR fixiert beide.

## Entscheidung

### 1. Saison-Aggregation: linear additiv ohne Decay, ohne Streichresultate

`v_season_standings` summiert `season_standings_awards.final_points` pro `(season_id, league_id, participant_id)`:

```sql
CREATE VIEW v_season_standings AS
SELECT
  st.season_id,
  sa.league_id,
  sa.participant_id,
  SUM(sa.final_points) AS total_points,
  COUNT(DISTINCT st.tournament_id) AS tournaments_played
FROM season_standings_awards sa
JOIN season_tournaments st ON st.id = sa.season_tournament_id
GROUP BY st.season_id, sa.league_id, sa.participant_id;
```

Sortier-Default `ORDER BY total_points DESC, tournaments_played DESC, display_name ASC` (siehe OD-M5-06 Resolution).

**Begründung**:

- FR-POINTS und FR-GLB erwähnen keine Decay-Logik; Saison hat klares Start-/Endedatum (Wechselfenster Dezember–April per Spec §2 Glossar).
- Linear ist transparent — Spieler verstehen "jeder Punkt zählt einmal" ohne Erklärung.
- Reversal-Rows aus OD-M5-07 fallen natürlich in `SUM(final_points)` rein (negative Beträge); keine Spezial-Logik in der View nötig.
- Spätere ATP- oder Streichresultat-Logik ist eine View-Migration, kein Schema-Bruch.

### 2. Pairing: Client-Side in Dart mit Server-Validation per RPC

`SwissSystemStrategy` läuft in `packages/kubb_domain/lib/src/tournament/pairing/swiss_system.dart`. Client berechnet das Pairing pro Runde und postet das Resultat an die Supabase-RPC `tournament_pair_round(tournament_id, round_number, pairings jsonb)`.

Die RPC ist die Trust-Boundary:

```sql
-- Pseudocode, vollständige Migration in M5.2-T3
CREATE FUNCTION tournament_pair_round(p_tournament_id uuid, p_round int, p_pairings jsonb)
RETURNS void AS $$
BEGIN
  -- 1. Caller muss Veranstalter oder Plattform-Admin sein
  PERFORM auth_assert_organizer(p_tournament_id);

  -- 2. Pairings-Set ist exakt eine Permutation aller aktiven Teilnehmer
  PERFORM assert_pairing_is_permutation(p_tournament_id, p_pairings);

  -- 3. Keine Wiederholung aus Vorrunden (ausser explizit erlaubt via Flag)
  PERFORM assert_no_disallowed_repeats(p_tournament_id, p_round, p_pairings);

  -- 4. Maximal ein Bye, Bye-Gutschrift korrekt
  PERFORM assert_bye_constraints(p_pairings);

  -- 5. Insert in tournament_matches
  INSERT INTO tournament_matches (tournament_id, round, ...) ...;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

Validations-Code ~30 LOC PL/pgSQL.

**Begründung**:

- Dart-Domain ist Test-Heimat — Backtracking-Algorithmus ist in Dart geradeaus, in PL/pgSQL schmerzhaft.
- Edge-Function (Deno + TypeScript-Port) würde den Algorithmus doppelt erfordern oder einen Deno-Native-Rewrite — beide teuer.
- RPC-Validation deckt die Trust-Boundary: ein bösartiger Client kann keine ungültigen Pairings einschmuggeln. Honest-but-slow Client kostet maximal eine RPC-Roundtrip mit 4xx-Antwort.

### 3. Rundenzahl-Default und Limits

`tournament_setup_wizard` rechnet beim "Schweizer System"-Format `default_rounds = ceil(log2(n))` (n = registrierte Teilnehmer). Veranstalter kann im Wizard auf einen Wert zwischen 3 und 9 ändern. Validierung als CHECK-Constraint auf `tournaments.swiss_rounds`.

**Begründung**: `ceil(log2(n))` ist FIDE-Standard für sinnvolle Schweizer-Distanz, 3–9 deckt 4–512 Teilnehmer ab. Höhere Runden sind in Kubb unüblich.

## Alternativen

### A — Decay-basierte Saison-Aggregation (OD-M5-03 Option B)

Verworfen: erfindet Komplexität, die das Liga-Reglement nicht fordert. Spieler-Kommunikation wird schwerer.

### B — Best-of-N / Streichresultate (OD-M5-03 Option C)

Verworfen als Default: ATP-Modell ist Tour-Format, für Vereins-Liga unüblich. Kann später als View-Migration nachgereicht werden.

### C — Server-Side-Pairing via Edge-Function (OD-M5-04 Option B)

Verworfen: Dart-/TS-Doppel-Implementierung oder Algorithmus-Rewrite ist ~2 Tage Aufwand zusätzlich. Wert nur, wenn Liga-Admin-Manipulation real ist. Owner hat dies als unwahrscheinlich für Pilot-Phase eingestuft. Bleibt für M6 als optionale Härtung möglich.

### D — Pairing in PL/pgSQL (OD-M5-04 Option C)

Verworfen: PL/pgSQL ist schlechter Boden für Backtracking, Tests sind schmerzhaft.

## Konsequenzen

### Positiv

- `v_season_standings` ist ein einfacher SUM/COUNT-View — leicht zu indizieren, leicht zu erklären.
- Pairing-Algorithmus lebt in einem reinen Dart-Package, ist mit Property-Tests und Goldfiles vollständig abdeckbar.
- Trust-Boundary durch RPC-Validation gesetzt — keine Doppel-Implementierung nötig.
- Reversal-Logik aus OD-M5-07 läuft natürlich durch die SUM-Aggregation.

### Negativ

- RPC-Validation muss vollständig sein — eine fehlende Constraint-Prüfung erlaubt manipulative Inserts. pgTAP-Tests sind merge-blocking.
- Client-Pairing kostet eine RPC-Roundtrip pro Runde — in Offline-Szenarien (siehe ADR-0022) muss das Pairing in die Outbox, RPC-Validation läuft dann verzögert.
- Spätere Migration zu Edge-Function (M6+) bedeutet doppelte Pflege bis zur Ablösung — wird durch Verschieben akzeptiert.

### Neutral

- Sortier-Logik in der View ist im Default-`ORDER BY` festgelegt, aber Client kann darüber hinaus filtern (z.B. nach Liga-Mindestteilnahme) ohne View-Änderung.

## Test-Strategie

- **pgTAP** (M5.2-T3, merge-blocking): RPC `tournament_pair_round` lehnt Permutations-Verstoss, Repeat-Verstoss, Mehrfach-Bye und Nicht-Veranstalter-Caller ab.
- **Property-Tests** (`packages/kubb_domain/test/tournament/pairing/`): über zufällige Teilnehmerzahlen 4..64 und Score-Verläufe — Pairing-Set ist immer Permutation, Repeats ≤ Backtrack-Tiefe 3.
- **View-Test** (pgTAP): `v_season_standings` summiert Reversal-Rows korrekt, behält Sortierung bei.
- **Integration**: Goldfile-Test einer 5-Runden-Saison mit 16 Teilnehmern und einem nachträglichen Score-Reversal, Final-Standings müssen reproduzierbar sein.
