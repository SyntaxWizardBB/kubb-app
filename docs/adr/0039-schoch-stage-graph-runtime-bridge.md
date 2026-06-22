# ADR-0039: Schoch im Stufen-Graph — Laufzeit-Brücke (Feld-Edges, Runner, Pairing-Fluss)

- **Status**: Accepted
- **Date**: 2026-06-22
- **Bezug**: ADR-0037 (Typ-Graph als jsonb-Sub-Graph); ADR-0036 (Buchholz/Schoch
  server-autoritativ, Client rechnet — Server validiert); ADR-0035 (Vorrunden-
  Rangfolge aus dem Stage-Typ); ADR-0030 (Stufen-Graph-Framework);
  `docs/specs/stage-graph-and-stage-type-modeling-spec.md`;
  `docs/specs/schoch-swiss-pairing-buchholz-spec.md`;
  CP-3-Owner-Entscheid (OFFEN-1, revidiert auf Feld-Edges; siehe Kontext).

## Context

Der Typ-Graph einer Schoch-Stufe (Ebene 2) hat ein Datenmodell (ADR-0037), aber
keine Laufzeit. Der Stufen-Graph-Runner kennt nur eine Stufen-Semantik: sind alle
Matches einer Stufe terminal, wird die Stufe geschlossen und geroutet. Schoch
braucht mehr — eine Stufe besteht aus mehreren Runden, und nur die *letzte* Runde
schliesst die Stufe. Die Zwischenrunden brauchen eine organizer-getriggerte
Paarung. Beides fehlt heute komplett.

Die M4-Architektur-Runde hat die Brücke entworfen. Ein adversarischer Review hat
die Richtung bestätigt, aber zwei Sachen aufgedeckt: das Design stand auf
veralteten Code-Ankern, und es übersah die `swiss`→`schoch`-Umbenennung. Beides
ist hier korrigiert; jeder Anker wurde gegen den aktuellen Code verifiziert.

Der CP-3-Entscheid zu OFFEN-1 (Vorrunde-Routing) ist gegenüber den Plan-Dokumenten
revidiert: `tasks.md`/`sprint-plan.md` hielten als frühe Empfehlung "nur Runden +
Paarungsregel, keine Feld-Edges" fest. Der Owner hat OFFEN-1 in M4 auf das
**Feld-Edges-Modell** gezogen — derselbe jsonb-Sub-Graph aus ADR-0037 trägt jetzt
auch die Vorrunde, nicht eine separate Paarungsregel-Sonderform. Diese ADR
dokumentiert den revidierten Entscheid; er hebt die frühere "nur Runden"-Notiz auf.

Owner-seitig wurden zusätzlich die Mängel #1 (Start-Pfad), #3 (Runden-Persistenz)
und #4 (Pairing-Fluss-Lücke) in den M4-Scope dieser Brücke gezogen.

## Decision

### 1. OFFEN-1 — Vorrunde als Feld-Edges (kein Sonderfall)

Die Ebene-2-Struktur einer Schoch-Stufe ist der jsonb-Sub-Graph aus ADR-0037:
`TypeStageCategory{ko, vorrunde}`, `TypeRound{fields, matchFormat, koMatchup?,
koTiebreak?, pairingRule?}`, `TypeField{id, roundNumber, slot}` und die sealed
`FieldEdge` (`WinnerEdge`, `LoserEdge`, `OpenEdge`, `AdvanceAllEdge`).

- Vorrunde-Felder sind die physischen Platten. Der Runden-Übergang ist eine
  `AdvanceAllEdge(r → r+1)` — "alle weiter", die Paarung der nächsten Runde
  bestimmt die Schoch-Strategie, nicht eine Edge pro Feld.
- KO-Felder sind das Bracket mit granularen `WinnerEdge`/`LoserEdge`.

Damit fällt die frühere "nur Runden + Paarungsregel"-Sonderform weg. Ein Modell,
zwei Kategorien.

### 2. HIGH-1 — Runner-Brücke (Intra-Stufen-Verzweigung, nur Schoch)

`tournament_run_stage_graph` (latest body: `20261299000000_stage_seed_resolver.sql`)
bekommt einen runden-scoped Zweig, der **nur** für den Schoch-Typ greift. Direkt
nach dem stufenweiten all-terminal-Check und vor dem Stufen-Close: ist die Stufe
vom Typ `schoch` (Legacy `swiss` toleriert), wird statt stufenweit *runden-scoped*
geprüft.

- Runde `r < R` fertig → **keine** Stufenschliessung. Stattdessen ein
  Audit-Signal `swiss_round_complete` (Organizer-Trigger für die nächste Paarung).
- Runde `r ≥ R` fertig → der bestehende Close-/Route-/Cascade-Pfad läuft
  unverändert.

Alle anderen Typen (KO, RR, pool, group_phase) gehen byte-identisch durch den
bestehenden Pfad — der Schoch-Zweig ist ein vorgeschalteter `IF`, kein Eingriff in
die Default-Logik.

### 3. HIGH-2/3 — Pairing-Fluss (organizer-getriggert, Client rechnet — Server validiert)

Die Paarung der nächsten Runde ist eine bewusste Organizer-Aktion
("Nächste Runde paaren"), kein Auto-Cascade.

- **Client**: eine neue `TournamentActions.pairRound` (existiert heute nicht — das
  Organizer-Dashboard hält den fehlenden Seam explizit fest). Sie liest den
  stage_node-scoped Stand, ruft `SwissSystemStrategy.planRound` (pure Dart,
  deterministisch) und schickt das Ergebnis an den Server. Delegation über den
  `tournamentRemote`-Port wie die übrigen Actions.
- **Server**: `tournament_pair_round` (latest body:
  `20261283000000_rename_organizer_teams.sql` — byte-identische Token-Rename-Kopie
  des Logik-Ursprungs `20261281000000_gate_split.sql`) wird **additiv** um
  `p_stage_node_id` erweitert:
  - `p_stage_node_id IS NULL` → byte-identisch, backward-kompatibel (klassischer
    Pfad unverändert).
  - `p_stage_node_id IS NOT NULL` → stage-scoped: Schoch-Typ prüfen, Stufe muss
    `active` sein, runden-scoped Progression-Gate, stage-scoped
    `validate_swiss_pairing`, INSERT mit gesetzter `stage_node_id`.

Das ist ADR-0036-konform: der Client rechnet die Paarung (Heuristik + Test-Truth),
der Server validiert und persistiert (autoritativ). Das Finalisieren der letzten
Runden-Matches feuert den Runner-Trigger (Entscheidung 2) — der Loop schliesst sich.

### 4. Mangel #1 — Start-Pfad-Konvergenz

`schoch_then_ko` hört auf, die Schoch-Vorrunde als einzelnen RR-Pool zu
materialisieren (heute geht der Hybrid-Start über `tournament_start_pool_phase`).
Runde 1 wird über den Schoch-Pfad gepaart wie jede Folgerunde. Damit konvergiert
der Start auf den Stufen-Graph-Pfad — ein Pairing-Mechanismus für alle Runden, kein
Pool-Sonderfall für Runde 1.

### 5. Mangel #3 — Runden-Persistenz über `config['rounds']`

Die Rundenzahl `R` lebt als `config['rounds']` der Schoch-Stufe. **Keine neue
Spalte.** Der Wizard-Draft schreibt den Wert; der Runner liest ihn für das
runden-scoped Gate (Entscheidung 2). Der Domain-Reader liest ihn schon:
`stage_validation.dart` `_minInputForNode` wertet `config['rounds']` für
`StageNodeType.schoch` aus (`rounds + 1`, sonst 2). Die #3-Lücke ist also nur das
**Schreiben** aus dem Wizard und das **Lesen** im Runner — nicht der Reader im
Domain.

### 6. Mangel #4 — Pairing-Fluss-Lücke

Deckungsgleich mit Entscheidung 3 abgedeckt: es gab keinen Client-Pfad, keine
stage-scoped RPC-Variante. Beides wird gebaut.

## Alternatives considered

- **Vorrunde als eigene Paarungsregel statt Feld-Edges** (frühere CP-3-Notiz).
  Verworfen: zwei Modelle für eine Stufe (Edges im KO, Sonderregel in der
  Vorrunde) brechen die Editor- und Summary-Parität und doppeln die Validierung.
  Ein Modell ist tragbar, seit `AdvanceAllEdge` den "alle weiter"-Übergang sauber
  ausdrückt.
- **Auto-Pairing der nächsten Runde im Runner** (kein Organizer-Trigger).
  Verworfen: widerspricht ADR-0036 (Client rechnet die Paarung) und nimmt dem
  Organizer die Kontrolle über Bye-Vergabe und manuelle Korrekturen zwischen
  Runden. Das Audit-Signal `swiss_round_complete` ist der bewusste Halt.
- **Neue Spalte `schoch_rounds` auf `tournament_stages`** (Mangel #3).
  Verworfen: der jsonb-Config trägt schon Per-Knoten-Parameter (ADR-0037), eine
  Spalte wäre eine zweite Quelle und eine Migration ohne Mehrwert.
- **Neue stage-aware `tournament_pair_round_stage`-RPC** statt additivem Parameter.
  Verworfen: dupliziert das Auth-Gate, den Progression-Check und die Validierung.
  Ein `NULL`-Parameter hält den klassischen Pfad byte-identisch und das Verhalten
  an einer Stelle.
- **Schoch-Vorrunde als RR-Pool belassen** (Mangel #1 nicht anfassen).
  Verworfen: zwei Pairing-Mechanismen (Pool für Runde 1, Schoch ab Runde 2) sind
  eine dauerhafte Divergenz-Quelle und genau die Lücke, die #4 sichtbar machte.

## Consequences

- Der Runner bekommt eine typ-spezifische Verzweigung. Sie ist additiv und ändert
  keinen Nicht-Schoch-Pfad — verifizierbar gegen die Stage-Goldens. Probe in
  `BEGIN/ROLLBACK`, kein `db reset`, latest body `20261299` als Basis (nicht das
  ältere `20261228` oder die Zwischenkopie `20261294`).
- `tournament_pair_round` muss vom `20261283`-Body abgeleitet werden, nicht vom
  `20261281`-Logik-Ursprung: `20261283` ist die byte-identische Rename-Kopie
  (Verein → Veranstalterteam). Wer von `20261281` kopiert, holt die alten
  `clubs`/`club_id`-Bezeichner zurück und bricht.
- Der `swiss`/`schoch`-Zweig in `tournament_generate_stage_matches` existiert
  bereits (eingeführt `20261247`, latest body `20261293`, dort
  `v_type IN ('swiss', 'schoch')`). Er wird wiederverwendet/erweitert, nicht neu
  gebaut. Basis ist `20261293`.
- Der Dispatch keyt auf `'schoch'` und toleriert Legacy `'swiss'`. Die CHECK-
  Constraints sind in `20261293` für beide Werte geweitet (deploy-sicher); ein
  späterer Cleanup darf `'swiss'` ziehen, sobald kein Deploy es mehr schreibt.
- Wachstumsgrenze unverändert aus ADR-0037: sehr grosse Typ-Graphen blähen den
  jsonb-Config; bei Bedarf später auf Tabellen migrierbar.

## Scale-Impact

**Trigger**: Pairing-Algorithmus / Runner-Trigger über wachsende Match-Mengen.
**Bei welcher Tier kritisch**: 2.
**Mitigation**: Der runden-scoped all-terminal-Check ist stage_node-gefiltert und
indexiert (`tournament_matches.stage_node_id`); `planRound` ist O(n log n) über die
Teilnehmer einer Stufe, nicht über das Turnier. Organizer-getriggert, also kein
Sub-Sekunden-Budget nötig.
**Performance-Budget**: Paarung < 1s bei ≤ 64 Teilnehmern pro Stufe.
**Migrationsrelevant?**: no.
