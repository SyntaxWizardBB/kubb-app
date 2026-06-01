# ADR-0027: Double-Elimination (WB + LB + Grand Final mit Bracket-Reset)

- **Status**: Proposed
- **Date**: 2026-06-01
- **Bezug**: `docs/P6_RULES_DECISIONS.md` §D (verbindliche Spezifikation),
  ADR-0017 (KO-Phase-Semantik, Phase-pro-Match, Server-Authority,
  `tournament_advance_ko_winner`), ADR-0016 (Bracket-Visualization),
  ADR-0019 (Pool-Phase).
- **Domain-Quelle**: `packages/kubb_domain/lib/src/tournament/bracket.dart`
  (`Bracket.singleElimination`, `_standardBracketOrder`, `KoMatchRow`,
  `bracketFromMatches`).
- **Server-Quelle**: `supabase/migrations/20260601000014_fn_compute_ko_bracket.sql`,
  `…000015_rpc_tournament_start_ko_phase.sql`,
  `…000016_trigger_advance_ko_winner.sql`,
  `…20260615000010_start_ko_phase_pool_extend.sql`.

> **Hinweis Nummernkollision**: Die Nummer `0021` ist im `docs/adr/`-Ordner
> bereits durch `0021-realtime-subscription-architecture.md` belegt. Dieses
> Dokument liegt wie vom Auftrag verlangt unter `0021-double-elimination.md`;
> beim Merge sollte es auf die nächste freie laufende Nummer umbenannt werden.

## Entscheidung

Double-Elimination wird als zweiter Bracket-Typ (`bracket_type =
'double_elimination'`, Spalte existiert bereits in
`20261001000001_tournament_setup_fields.sql`) eingeführt — Winner-Bracket (WB),
Loser-Bracket (LB) im major/minor-Schema, Grand Final (GF) mit optionalem
Bracket-Reset. Die Generierungs-Topologie ist deterministisch aus `N` geseedeten
Qualifiern ableitbar und wird sowohl in Dart (`packages/kubb_domain`) als auch
serverseitig in plpgsql gespiegelt (Property-Parität als Merge-Gate, analog
ADR-0017 §7). Es gibt **kein** Spiel-um-Platz-3 (Platz 3 = LB-Finalverlierer,
P6 §D.5).

---

## 1. Domain-API (`packages/kubb_domain/lib/src/tournament/bracket.dart`)

### 1.1 Neue Typen

`Bracket` ist bereits eine `sealed class`. Eine zweite Subklasse wird
hinzugefügt; die `BracketPhase`-Enum wird erweitert. Bestehende Bezeichner und
Records (`BracketEntry`, `BracketPairing`, `BracketRound`, `KoMatchRow`) werden
unverändert wiederverwendet.

```dart
/// Phase marker for a [BracketRound] — see ADR-0017 §4 (single-elim) and
/// ADR-0027 (double-elim). `winners`/`finals`/`thirdPlace` bleiben für
/// Single-Elim; die vier neuen Werte sind double-elim-spezifisch.
enum BracketPhase {
  winners,
  thirdPlace,
  finals,
  // Double-Elimination (ADR-0021 §2):
  wb,             // winner bracket round
  lb,             // loser bracket round (major + minor)
  grandFinal,     // GF spiel 1
  grandFinalReset // GF spiel 2 (only materialised wenn with_bracket_reset)
}

/// Wire-Mapping (DB phase text <-> BracketPhase). Single source of truth
/// für Repository-Adapter und plpgsql-Parität.
const Map<String, BracketPhase> kBracketPhaseWire = {
  'group': BracketPhase.winners, // group wird nie als KO-Row gemappt
  'ko': BracketPhase.winners,
  'final': BracketPhase.finals,
  'third_place': BracketPhase.thirdPlace,
  'wb': BracketPhase.wb,
  'lb': BracketPhase.lb,
  'grand_final': BracketPhase.grandFinal,
  'grand_final_reset': BracketPhase.grandFinalReset,
};
```

```dart
@immutable
final class DoubleEliminationBracket extends Bracket {
  const DoubleEliminationBracket({
    required this.wbRounds,
    required this.lbRounds,
    required this.grandFinal,        // genau 1 pairing
    required this.grandFinalReset,   // null wenn !withBracketReset
    required this.withBracketReset,
  });

  /// WB-Runden, number = 1..log2(size), phase == BracketPhase.wb.
  final List<BracketRound> wbRounds;

  /// LB-Runden, number = 1..2*(wbRounds.length-1), phase == BracketPhase.lb.
  /// Ungerade number => minor, gerade number => major (siehe §1.3).
  final List<BracketRound> lbRounds;

  final BracketRound grandFinal;          // phase == grandFinal, 1 pairing
  final BracketRound? grandFinalReset;    // phase == grandFinalReset, 1 pairing
  final bool withBracketReset;

  @override
  Bracket fill({required int round, required int position,
      required String participantId}) { /* siehe §1.5 */ }
}
```

`BracketRound.number` ist **phasen-lokal** (WB-R1, LB-R1, GF-R1 sind je
`number=1`). Disambiguierung läuft ausschliesslich über `phase` — exakt wie der
bestehende Single-Elim-Trick „Third-Place teilt `round_number/bracket_position`
mit dem Finale, `phase` trennt sie" (`bracket.dart` Doc-Kommentar, Migration
`…000014` Z. 157-162). Das hält die DB-Spalten `round_number` /
`bracket_position` semantisch identisch zu ADR-0017.

### 1.2 Factory-Signatur

```dart
factory Bracket.doubleElimination(
  List<String> participantIds, {
  bool withBracketReset = true,
  BracketSeedingPattern seedingPattern = BracketSeedingPattern.recursive,
});
```

`withThirdPlace` entfällt (P6 §D.5: gesperrt). Default `withBracketReset = true`.

### 1.3 Grundgrössen (P6 §D.1)

```
n         = participantIds.length            // >= 2
size      = next_pow2(n)
byes      = size - n
wbRounds  = log2(size)
lbRounds  = 2 * (wbRounds - 1)               // 0 wenn size==2
```

- WB-Runde `k` hat `size / 2^k` Matches (`k = 1..wbRounds`).
- LB-Runde-Match-Zählung (P6 §D.2):
  - **minor** Runden (ungerade `j`): konsolidieren LB-Überlebende
    untereinander.
  - **major** Runden (gerade `j`): paaren LB-Überlebende gegen frisch
    eingespeiste WB-Verlierer.

  Geschlossene Form für `size = 2^m` (`m = wbRounds`):

  | LB-Runde `j` | Typ   | #Matches        | Speist WB-Verlierer aus |
  |--------------|-------|-----------------|--------------------------|
  | 1            | minor | `size/4`        | WB-R1 (`size/2` Verlierer, paarweise) |
  | 2            | major | `size/4`        | WB-R2 (`size/4` Verlierer) |
  | 3            | minor | `size/8`        | — |
  | 4            | major | `size/8`        | WB-R3 |
  | …            | …     | …               | … |
  | `2k-3`       | minor | `size/2^k`      | — |
  | `2k-2`       | major | `size/2^k`      | WB-R`k` |
  | …            | …     | …               | … |
  | `lbRounds`   | major | `1`             | WB-R`wbRounds` (= WB-Finalverlierer) |

  **Einspeisungs-Regel (verbindlich, P6 §D.2):** Verlierer aus **WB-Runde `k`**
  fallen in **LB-Runde `2k-2`** (major) für `k >= 2`; WB-R1-Verlierer fallen in
  **LB-R1**. Sonderfall: bei `size = 4` ist `lbRounds = 2`, LB-R1 ist gleichzeitig
  minor-Konsolidierung (1 Match aus den 2 WB-R1-Verlierern) und LB-R2 ist das
  LB-Finale (WB-R2-Verlierer vs. LB-R1-Sieger). Bei `size = 2` ist `lbRounds = 0`
  → reines GF zwischen den zwei Teilnehmern (GF + optionaler Reset).

### 1.4 Drop-Mapping & Cross-Bracket-Anti-Rematch (P6 §D.2)

Verlierer eines WB-Matches dürfen im LB nicht sofort wieder auf den gerade
besiegten Gegner treffen. Standard-Lösung = feste Permutation pro Einspeise-Runde:
obere WB-Hälfte → untere LB-Hälfte und umgekehrt.

```dart
/// Liefert den 0-basierten LB-Slot (Pairing-Index * 2 + side) in LB-Runde
/// 2k-2 (major), in den der Verlierer des bracket_position p (1-based) der
/// WB-Runde k fällt. `lbMatchesInTarget = size / 2^k`.
int lbDropTarget(int wbRound, int wbPosition, int size) {
  final k = wbRound;
  final lbMatches = size >> k;            // size / 2^k
  // 0-based WB-Pairing-Index in seiner Runde:
  final i = wbPosition - 1;
  // Anti-Rematch: spiegele die Pairing-Reihenfolge der eingespeisten
  // Verlierer relativ zur LB-Slot-Reihenfolge. Der WB-Verlierer besetzt
  // immer den B-Slot einer major-LB-Paarung (A = LB-Überlebender).
  final lbPairing = (lbMatches - 1) - i;  // Reflexion
  return lbPairing * 2 + 1;               // +1 => B-Slot
}
```

- Für WB-R1 (`k = 1`, Ziel LB-R1, minor): beide Verlierer eines Slot-Paars
  werden *gegeneinander* gesetzt. Mapping:
  `lbR1Pairing = (wbR1Position - 1) ~/ 2`, Seite =
  `(wbR1Position - 1) % 2` (gerade → A, ungerade → B). Die Reflexion wird
  hier zwischen den beiden Hälften angewandt (obere WB-Paare in untere LB-R1
  und umgekehrt), implementiert als
  `lbR1Pairing = (size/4 - 1) - ((wbR1Position - 1) ~/ 2)`.

Die Permutation ist eine **reine Funktion** von `(wbRound, wbPosition, size)` —
identisch in Dart und plpgsql implementierbar, damit Property-Parität trivial
testbar bleibt.

### 1.5 BYE-Behandlung (P6 §D.4)

- WB-Seeding = identisch Single-Elim: `_standardBracketOrder(size)`, BYEs an
  Top-Seeds. Das WB-Tableau ist **exakt** das Output von
  `Bracket.singleElimination` (Wiederverwendung, kein Re-Implement).
- Ein WB-BYE-Match speist **keinen** realen Verlierer ins LB ein → der Ziel-
  LB-Slot ist selbst ein BYE (`isBye: true`). Der LB-Gegner rückt kampflos auf.
- Konsequenz nicht-2^n: LB bleibt voll `size`-basiert; LB-BYEs lösen sich in
  den frühen minor/major-Runden auf (analog Single-Elim, `bracket.dart`).

### 1.6 Generierungs-Pseudocode

```
function doubleElimination(ids, withBracketReset):
  n      = len(ids); size = next_pow2(n); byes = size - n
  if n == 1: return DoubleEliminationBracket(leer, leer, GF=leer, ...)

  # --- WB: 1:1 Single-Elim wiederverwenden ---
  se      = Bracket.singleElimination(ids)          # liefert WB-Runden
  wbRounds = se.rounds mit phase := wb               # R1 echt, R2.. placeholder
  wbCount  = len(wbRounds)                            # = log2(size)

  # --- LB: leere Runden anlegen ---
  lbCount = 2 * (wbCount - 1)
  lbRounds = []
  for j in 1..lbCount:
    if j is odd:   matches = size >> ((j+3)/2)        # minor:  size/2^((j+3)/2)
    else:          matches = size >> ((j+2)/2)        # major:  size/2^((j+2)/2)
    lbRounds.append( BracketRound(number=j, phase=lb,
                                  pairings = placeholder * matches) )
  # (Schliessende Form: minor j -> size/2^((j+3)/2), major j -> size/2^((j+2)/2);
  #  letzte Runde lbCount hat 1 Match.)

  # --- WB-R1-Verlierer-BYE-Vorbefüllung im LB ---
  # Für jedes WB-R1-BYE-Pairing wird der ziel-LB-R1-Slot als isBye markiert
  for each wbR1 pairing p mit BYE-Sieger:
    (lbR, slot) = lbR1DropTarget(p)
    markiere lbRounds[lbR].pairings[slot] als isBye

  # --- Grand Final + Reset ---
  grandFinal      = BracketRound(number=1, phase=grandFinal,  pairings=[placeholder])
  grandFinalReset = withBracketReset
                    ? BracketRound(number=1, phase=grandFinalReset, pairings=[placeholder])
                    : null

  return DoubleEliminationBracket(wbRounds, lbRounds, grandFinal,
                                  grandFinalReset, withBracketReset)
```

Die Slot-Befüllung über Matchverlauf erledigt zur Laufzeit der Server-Trigger
(§3), nicht die Factory — exakt wie `Bracket.singleElimination` nur R1
materialisiert und R2+ als Placeholder lässt (`bracket.dart` Z. 84-92).

### 1.7 Durchgerechnetes Beispiel — 8 Qualifier (Seeds S1..S8)

```
n=8, size=8, byes=0, wbRounds=3, lbRounds=4.
Recursive-Order(8) = [1,8,5,4,3,6,7,2]  (aus _standardBracketOrder)

WB-R1 (4 Matches):  S1-S8 | S5-S4 | S3-S6 | S7-S2
WB-R2 (2):          W(m1)-W(m2) | W(m3)-W(m4)
WB-R3 (1, Final):   W(R2m1)-W(R2m2)            -> WB-Champion

LB-R1 minor (size/4=2):  L(WBR1 m1)-L(WBR1 m2) | L(WBR1 m3)-L(WBR1 m4)
   (Anti-Rematch-Reflexion: obere WB-Hälfte in untere LB-R1-Paarung u.u.)
LB-R2 major (size/4=2):  W(LBR1 m1)-L(WBR2 m?) | W(LBR1 m2)-L(WBR2 m?)
   WB-R2-Verlierer (k=2) -> LB-R 2k-2 = LB-R2, B-Slots, reflektiert.
LB-R3 minor (size/8=1):  W(LBR2 m1)-W(LBR2 m2)
LB-R4 major (size/8=1, LB-Final):  W(LBR3)-L(WBR3)   # WB-R3-Verlierer (k=3) -> LB-R 2*3-2 = LB-R4
   -> LB-Champion

GF (grand_final):        WB-Champion - LB-Champion
GF-Reset (grand_final_reset, nur falls LB-Champ GF1 gewinnt):  Rematch

Match-Total (with_bracket_reset=true):
  WB 4+2+1 = 7 ; LB 2+2+1+1 = 6 ; GF 1 ; GF-Reset 1 (materialisiert)  = 15
  (ohne Reset = 14)
```

### 1.8 Durchgerechnetes Beispiel — 6 Qualifier (Seeds S1..S6, non-2^n)

```
n=6, size=8, byes=2, wbRounds=3, lbRounds=4.
Slots: 1..6 = S1..S6, 7..8 = BYE. Recursive-Order(8) = [1,8,5,4,3,6,7,2].

WB-R1 (4 Matches):
   slot1(S1) - slot8(BYE)   -> BYE-Match, S1 advanced, KEIN LB-Drop
   slot5(S5) - slot4(S4)    -> echtes Match
   slot3(S3) - slot6(S6)    -> echtes Match
   slot7(BYE)- slot2(S2)    -> BYE-Match, S2 advanced, KEIN LB-Drop

LB-R1 minor (2 Matches):
   L(m1)-L(m2)   m1 ist BYE -> Slot A = isBye; L(m2)=Verlierer(S5/S4) rückt auf
   L(m3)-L(m4)   m4 ist BYE -> Slot B = isBye; L(m3)=Verlierer(S3/S6) rückt auf
   => beide LB-R1-Matches kollabieren zu Walkover; 2 reale Spieler ziehen
      kampflos in LB-R2.
LB-R2 major (2): W(LBR1 m1)-L(WBR2 m?) | W(LBR1 m2)-L(WBR2 m?)
LB-R3 minor (1), LB-R4 major (1, LB-Final) wie im 8er-Fall.
GF + optional Reset wie oben.

BYE-Auflösung: die 2 WB-BYEs erzeugen genau 2 LB-R1-BYE-Slots, die sich in
LB-R1 als Walkover auflösen — LB-Struktur bleibt size=8-basiert, voll.
```

### 1.9 Read-Mapper `bracketFromMatches` (Erweiterung)

`bracketFromMatches(List<KoMatchRow>)` bekommt eine Fallunterscheidung anhand
der vorhandenen Phasen:

```dart
Bracket bracketFromMatches(List<KoMatchRow> matches) {
  final hasDouble = matches.any((m) =>
      m.phase == BracketPhase.wb || m.phase == BracketPhase.lb ||
      m.phase == BracketPhase.grandFinal ||
      m.phase == BracketPhase.grandFinalReset);
  if (hasDouble) return _doubleEliminationFromMatches(matches);
  // ... bestehender Single-Elim-Pfad unverändert ...
}
```

`_doubleEliminationFromMatches` gruppiert Rows nach `phase` und je `roundNumber`,
baut `wbRounds`/`lbRounds`/`grandFinal`/`grandFinalReset` über das bestehende
`_pairingsForRound`-Helper (kein Re-Implement). Der Mapper bleibt **passiv**
(ADR-0017 §5): er spiegelt nur den DB-Stand, schreibt keine Folge-Slots.

---

## 2. Phase-Enum-Erweiterung (DB)

`tournament_matches.phase` CHECK wird um vier Werte erweitert. Aktuell
(`20260601000010_tournament_ko_phase.sql` Z. 28-29):

```sql
CHECK (phase IN ('group','ko','third_place','final'))
```

**Neue Migration** `20261101000001_double_elim_phase.sql`:

```sql
ALTER TABLE public.tournament_matches
  DROP CONSTRAINT IF EXISTS tournament_matches_phase_check;
ALTER TABLE public.tournament_matches
  ADD CONSTRAINT tournament_matches_phase_check
    CHECK (phase IN (
      'group','ko','third_place','final',
      'wb','lb','grand_final','grand_final_reset'));
```

- Idempotent (`DROP … IF EXISTS` + neu). Bestehende Single-Elim-Rows
  (`ko`/`final`/`third_place`) bleiben gültig.
- `bracket_type` (single/double) existiert bereits als
  `tournaments.bracket_type` (CHECK `single_elimination|double_elimination`,
  Migration `20261001000001` Z. 134-135) — **keine** neue Spalte nötig.
- `with_bracket_reset` lebt im `ko_config`-JSONB-Bag (`tournaments.ko_config`),
  Default `true`, analog zu `with_third_place_playoff`.

---

## 3. Server-Änderungen

### 3.1 Neuer Helper `_tournament_compute_de_bracket(seeds jsonb, with_reset bool)`

Neue plpgsql-Function, **parallel** zum bestehenden
`_tournament_compute_ko_bracket` (das unverändert bleibt). Spiegelt
`Bracket.doubleElimination` 1:1. Output-Row-Shape **identisch** zum Single-Elim-
Helper plus die neuen Phasen:

```
RETURNS TABLE(round_number int, bracket_position int,
              participant_a uuid, participant_b uuid,
              phase text, is_bye_pairing boolean)
```

Erzeugt in deterministischer Reihenfolge (für stabile Tests):
1. WB-Runden (`phase='wb'`) — R1 echte Paarungen aus
   `_standardBracketOrder(size)` (Code-Wiederverwendung via Extrahieren der
   Seed-Order-Schleife aus `…000014` in einen geteilten Helper
   `_tournament_seed_order(size int) RETURNS int[]`), R2+ Placeholder.
   WB-Final-Runde behält `phase='wb'` (nicht `final`) — Disambiguierung gegen
   GF läuft über die GF-Phasen.
2. LB-Runden (`phase='lb'`) — alle Placeholder, Match-Zählung nach §1.3-Tabelle.
   LB-R1-BYE-Slots vorbefüllt analog WB-BYE.
3. GF (`phase='grand_final'`, round_number=1, bp=1, Placeholder).
4. GF-Reset (`phase='grand_final_reset'`, round_number=1, bp=1) **nur** wenn
   `with_reset = true`.

### 3.2 `tournament_start_ko_phase` verzweigt nach `bracket_type`

In der bestehenden RPC (zuletzt `20260615000010_start_ko_phase_pool_extend.sql`)
wird vor dem Match-Insert (Z. 280 ff.) `tournaments.bracket_type` gelesen:

```sql
SELECT bracket_type, coalesce((ko_config->>'with_bracket_reset')::boolean, true)
  INTO v_bracket_type, v_with_reset
  FROM public.tournaments WHERE id = p_tournament_id;

IF v_bracket_type = 'double_elimination' THEN
  INSERT INTO public.tournament_matches(...)
  SELECT ... FROM public._tournament_compute_de_bracket(v_seeds_jsonb, v_with_reset) b;
ELSE
  -- bestehender Single-Elim-Pfad mit _tournament_compute_ko_bracket
END IF;
```

- Idempotency-Guard erweitern: `phase IN ('ko','third_place','final','wb','lb',
  'grand_final','grand_final_reset')` (Z. 89).
- BYE-Auto-Advance wie bisher: `is_bye_pairing` → `status='finalized'` +
  `winner_participant`, damit der Trigger den BYE-Sieger weiterschiebt (auch
  in WB-R2 und — bei BYE — in den LB-Walkover).
- `with_third_place_playoff` bei `double_elimination` ignorieren/auf `false`
  zwingen (P6 §D.5). Validierung: 422 `INVALID_KO_CONFIG` wenn
  `with_third_place_playoff = true` zusammen mit `double_elimination`.

### 3.3 `tournament_advance_ko_winner` — LB-Einspeisung

Der Trigger (`20260601000016`) wird erweitert. WHEN-Clause um die neuen Phasen
ergänzen:

```sql
WHEN (OLD.status NOT IN ('finalized','overridden')
  AND NEW.status     IN ('finalized','overridden')
  AND NEW.phase      IN ('ko','third_place','final',
                         'wb','lb','grand_final','grand_final_reset'))
```

Neue Trigger-Logik für Double-Elim (Property-Parität zur Dart-Domain §1.4):

1. **`phase='wb'`**: Sieger → WB-Folge-Match
   (`round_number+1`, `ceil(bracket_position/2)`, `phase='wb'`; odd→A, even→B)
   wie Single-Elim. Falls WB-Final (`round_number = wbRounds`): Sieger →
   `grand_final` Slot A.
   **Zusätzlich** Verlierer → LB:
   - berechne `(lb_target_round, lb_target_pos, lb_side)` via Spiegelung der
     `lbDropTarget`-Funktion (§1.4) — als plpgsql-Helper
     `_tournament_de_lb_target(wb_round int, wb_position int, size int)`.
   - schreibe Verlierer in `phase='lb'`-Row an `(lb_target_round,
     lb_target_pos)`, Slot A oder B nach `lb_side`.
   - Status-Promotion `scheduled→awaiting_results` sobald beide Slots gefüllt
     (bestehende Logik).
2. **`phase='lb'`**: Sieger → LB-Folge-Match. Minor→major-Übergang: der LB-
   Sieger landet im A-Slot der nächsten major-Runde (B-Slot reserviert für
   WB-Verlierer-Einspeisung). LB-Final-Sieger → `grand_final` Slot B.
3. **`phase='grand_final'`**:
   - Sieger == WB-Champion (Slot A) → Turnier-Ende, `tournaments.status`-Logik
     unverändert (alle Matches terminal → `finalized`).
   - Sieger == LB-Champion (Slot B) UND `with_bracket_reset` → fülle
     `grand_final_reset` (A = WB-Champion = GF1-Slot-A, B = LB-Champion),
     Status `awaiting_results`.
   - Sieger == LB-Champion UND **nicht** `with_bracket_reset` → Turnier-Ende.
4. **`phase='grand_final_reset'`**: Sieger = Turniersieger, keine Fort-
   schreibung.

`size` für die LB-Target-Berechnung wird aus dem Match-Bestand abgeleitet:
`size = 2 ^ max(round_number) über phase='wb'` (= `2^wbRounds`). Das vermeidet
eine zusätzliche Spalte und ist deterministisch.

Walkover/Forfeit bleibt kompatibel: der Trigger liest nur `winner_participant`
und berechnet den Verlierer aus `participant_a/b` (bestehende Logik Z. 65-69).
Ein BYE-WB-Match (kein realer Verlierer, da `participant_b IS NULL`) schreibt
`NULL` in den LB-Slot → der LB-Slot ist/bleibt BYE; die LB-Walkover-Auflösung
greift, sobald der reale LB-Gegner gesetzt ist (eigene Forfeit-Behandlung wie
bei WB-BYE in `tournament_start_ko_phase`).

---

## 4. Daten-Lese-Pfad

### 4.1 Repository `getBracket` (`tournament_repository.dart` Z. 596-612)

`inFilter('phase', …)` um die vier neuen Werte erweitern:

```dart
.inFilter('phase', const <String>[
  'ko', 'third_place', 'final',
  'wb', 'lb', 'grand_final', 'grand_final_reset',
])
```

Der Adapter `koMatchRowFromRow` mappt den `phase`-Text via `kBracketPhaseWire`
(§1.1) auf `BracketPhase`. `bracketFromMatches` erkennt anhand der Phasen
automatisch Single- vs. Double-Elim (§1.9) — der Provider
(`tournament_bracket_provider.dart`) und die UI-Schicht
(`bracket_canvas.dart`, `kubb_match_card.dart`) bleiben API-kompatibel, weil
beide gegen den `sealed Bracket`-Typ programmieren.

### 4.2 Visualization (`bracket_layout.dart`, `bracket_canvas.dart`)

`BoxRect.phase` ist bereits `BracketPhase`. Die Layout-Math braucht eine
Erweiterung, die WB-Spalten, LB-Spalten (unterhalb) und GF (rechts) in getrennten
Zeilen-/Spalten-Bändern anordnet — additive Erweiterung, nicht Teil des Domain-
Merge-Gates. UI ist letzter Build-Schritt (§6).

---

## 5. Test-Matrix

### 5.1 Dart Property-Tests (`packages/kubb_domain/test/tournament/properties/`)

Neu `double_elimination_properties_test.dart`, Stil wie
`bracket_properties_test.dart` (glados). Sweep über `N ∈ {2,4,6,8,16,32}` plus
zufällige `participantIds`:

| Property | Assertion |
|---|---|
| Determinismus | `doubleElimination(ids) == doubleElimination(ids)` |
| WB-Identität | `wbRounds` == `singleElimination(ids).rounds` (modulo Phase) |
| WB-Rundenzahl | `wbRounds.length == log2(next_pow2(N))` |
| LB-Rundenzahl | `lbRounds.length == 2*(wbRounds.length-1)` |
| LB-Slot-Zählung | minor `j` → `size/2^((j+3)/2)`; major `j` → `size/2^((j+2)/2)`; letzte LB-Runde == 1 Match |
| Drop-Mapping Bijektiv | Für jede WB-Runde `k≥2`: die `size/2^k` Verlierer mappen bijektiv auf die B-Slots von LB-R`2k-2` |
| Anti-Rematch | Kein WB-Verlierer landet im LB-Match gegen den Gegner, dem er gerade unterlag (Reflexion korrekt) |
| BYE-Position | BYEs sitzen an Top-Seeds im WB (FR-FMT-11); jeder WB-BYE erzeugt genau einen LB-BYE-Slot; #LB-BYE == `byes` |
| GF-Reset toggle | `withBracketReset=false` → `grandFinalReset == null`; `true` → genau 1 Reset-Pairing |
| Teilnehmer-Eindeutigkeit | Jeder reale Teilnehmer erscheint in WB-R1 höchstens einmal |

Konkrete durchgerechnete Erwartungswerte als fixe Unit-Tests: `N=8` (0 BYE,
15/14 Matches) und `N=6` (2 BYE, LB-R1-Walkover) — exakt §1.7/§1.8.

### 5.2 Server pgTAP / Parität (`supabase/tests/`)

- `_tournament_compute_de_bracket` Row-Count und Phasen-Verteilung für
  `N ∈ {2,4,6,8,16,32}` gegen die Dart-Erwartungswerte (Property-Parität-Gate
  wie ADR-0017 §7).
- Trigger-Tests: WB-Verlierer landet im korrekten LB-Slot; LB-Sieger steigt
  major→minor korrekt; GF1-Verlierer (WB-Champ) → Reset materialisiert; GF1-
  Sieger (WB-Champ) → kein Reset, Turnier terminal; BYE-WB → LB-Walkover löst
  auf.
- Falls pgTAP in der Pipeline fehlt: Dart-Integration-Tests gegen lokale
  Supabase-Instanz (Fallback wie ADR-0017 §7).

---

## 6. Inkrementelle Build-Reihenfolge

1. **Domain + Tests** (`kubb_domain`, kein Flutter, kein Server):
   `BracketPhase`-Erweiterung + `kBracketPhaseWire`, `DoubleEliminationBracket`,
   `Bracket.doubleElimination`, `lbDropTarget`/`_tournament_de_lb_target`-Äquivalent,
   `bracketFromMatches`-Verzweigung. Property-Tests §5.1 grün. **Merge-Gate.**
2. **Server**: Migration `…_double_elim_phase.sql` (CHECK), geteilter
   `_tournament_seed_order`, `_tournament_compute_de_bracket`,
   `tournament_start_ko_phase`-Verzweigung, `tournament_advance_ko_winner`-LB-
   Logik. pgTAP-Parität §5.2 grün. **Merge-Gate.**
3. **Read-Pfad + UI**: `getBracket` `inFilter`-Erweiterung,
   `koMatchRowFromRow`-Mapping, `bracket_layout`/`bracket_canvas`-Anordnung für
   WB/LB/GF, Wizard-Toggle `with_bracket_reset` (Default true), Sperre des
   Spiel-um-Platz-3-Toggles bei `double_elimination`.

Reihenfolge erzwingt, dass die Pure-Domain-Wahrheit zuerst feststeht und Server
+ UI sich dagegen messen — exakt das Property-Parität-Pattern aus ADR-0017.

---

## Konsequenzen

- Zwei parallele Generatoren (Dart + plpgsql) für Double-Elim → akzeptiertes
  Drift-Risiko, abgesichert durch Property-Parität als Pflicht-Gate (ADR-0017
  §7 Präzedenz).
- `round_number`/`bracket_position` bleiben semantisch unverändert; die Phase
  ist der einzige neue Diskriminator → minimal-invasiv für DB und Trigger.
- Kein Spiel-um-Platz-3 bei Double-Elim (strukturell durch LB-Final abgedeckt) →
  weniger Sonderlogik als Single-Elim.
- Visualisierung (LB unterhalb WB, GF rechts) ist die einzige nennenswerte
  additive UI-Arbeit; Domain und Trigger sind die risikoreichen Teile und
  zuerst testbar.

## Alternativen

- **LB ohne Anti-Rematch-Permutation** (Verlierer in identischen Slot-Index):
  verworfen, weil sofortige Rematches gegen den WB-Bezwinger unfair und gegen
  Standard-Double-Elim-Praxis (P6 §D.2 verbindlich) sind.
- **Single-Match-GF ohne Reset als Default**: verworfen — bricht die „double"-
  Garantie (WB-Champion schiede bei einer einzigen GF-Niederlage trotz nur
  einer Gesamtniederlage aus, P6 §D.3). Reset bleibt Default `true`, abschaltbar.
- **Eigene `bracket_round`-Tabelle statt Phase-Diskriminator**: verworfen,
  Status-/Schema-Explosion, inkonsistent mit ADR-0017 §1.

---

## Verifikations-Status (Stand: Implementierung)

- **Domain**: vollständig implementiert + getestet — 35 neue Property-Tests, 255 Domain-Tests grün; Single-Elim unverändert (Regression grün).
- **Read-Pfad**: implementiert (`tournament_models` Phase-Map + `getBracket`/`bracketFromMatches` Auto-Erkennung), App-Tournament-Suite grün (173).
- **Server**: per Review-by-reading verifiziert (keine lokale Postgres-Instanz). Dependency-Liste gegen die Quell-Migrationen gegengecheckt. Migrationen `20261101000001_double_elim_phase.sql` + `20261101000002_double_elim_server.sql`.

### Offene Paritäts-Risiken → pgTAP-Pflicht, sobald lokale DB verfügbar
1. **LB→LB-Progression ist server-only** (Dart generiert nur die leere LB-Struktur, nicht die minor→major/major→minor-Weiterleitung). Höchste Priorität für pgTAP-Trigger-Tests (§5.2).
2. **WB-Final-Loser bei `size=4`** (Doppel-Aktion im Trigger: Winner→GF-A, Loser→LB-Final im selben Fire) — bestätigen.
3. **`size=2` (n=2)**: Generator spiegelt die Dart-Factory (WB-R1 + leeres GF); ADR-Prosa liest "reines GF" — Runtime-Endzustand bestätigen.
4. **LB-R1-BYE-Granularität**: Server markiert das LB-R1-*Pairing* als BYE, Dart markiert den *Slot* — pgTAP-Parität auf Pairing-Ebene vergleichen.
