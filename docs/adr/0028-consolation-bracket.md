# ADR-0028: Trostturnier (Consolation Bracket, Modell B)

- **Status**: Proposed
- **Date**: 2026-06-02
- **Bezug**: `docs/P6_KO_MODELS.md` (Modell B — verbindliche Konzept-Entscheidung),
  `docs/P6_RULES_DECISIONS.md` §E (Consolation-Defaults: eigener Regelsatz,
  Seeding wie Hauptbracket), `docs/P6_SETUP_WIZARD_SPEC.md` (Hauptbaum =
  Zweierpotenz / keine Freilose, Spiel um Platz 3 immer an),
  ADR-0017 (KO-Phase-Semantik, Phase-pro-Match, Server-Authority-Trigger,
  Recursive-Seeding, BYE an Top-Seeds nach FR-FMT-11),
  ADR-0027 (Double-Elimination — Abgrenzung; phasen-lokale `round_number`,
  passiver Read-Mapper).
- **Domain-Quelle**: `packages/kubb_domain/lib/src/tournament/bracket.dart`
  (`Bracket.singleElimination`, `_standardBracketOrder`, `lbDropTarget`,
  `BracketPhase`, `kBracketPhaseWire`, `KoMatchRow`, `bracketFromMatches`),
  `packages/kubb_domain/lib/src/tournament/tournament_setup.dart`
  (`ConsolationConfig`, `ConsolationSource`, `MatchFormatSpec`).

> **Reines DESIGN-/Entscheid-Dokument.** Dieses ADR legt die Topologie und die
> deterministischen Funktionen fest und enthält Code-Skizzen in Dart als
> Spezifikation. Es enthält **keine** fertige Implementierung und **keine**
> Test-Suite — die Build-Reihenfolge und die Property-Paritäts-Gates werden wie
> bei ADR-0027 §6/§5 erst beim Implementieren materialisiert.

## Entscheidung

Das Trostturnier (Consolation Bracket, „Modell B" aus `P6_KO_MODELS.md`) wird
als dritte K.-o.-Achsen-Option (`bracket_type` bleibt `single_elimination`; das
Trostturnier ist ein **additiver zweiter Baum** über das vorhandene
`ConsolationConfig`) eingeführt. Der **Hauptbaum** ist ein unverändertes
Single-Elimination nach ADR-0017 (Recursive-Seeding, Spiel um Platz 3 **immer**
an, **keine** Freilose im Hauptbaum / Zweierpotenz-Grösse). Daneben läuft ein
**separater** Trostturnier-Baum, der die früh ausgeschiedenen Hauptbaum-Verlierer
gestaffelt sowie optional direkt aus der Vorrunde eingespeiste Teams sammelt und
die hinteren Plätze (ab Platz 5) ausspielt.

Es gibt **kein Grand-Final-Merge**. Anders als beim Double-Elim aus **ADR-0027**,
wo der LB-Sieger über das Grand Final (mit Bracket-Reset) noch den Turniertitel
holen kann, führt der Trostturnier-Baum **niemals** zurück in den Hauptbaum: Der
Trostturnier-Sieger gewinnt das Nebenturnier (Platz 5), **nicht** den
Turniertitel. Platz 1/2 ist mit dem Hauptbaum-Final endgültig entschieden.

Die Topologie ist deterministisch aus (a) der Hauptbaum-Grösse
`consolation_main_bracket_size`, (b) der Direkt-Einspeisung
`consolation_direct_count` und (c) den gestaffelt einsteigenden
Hauptbaum-Verlierern ableitbar und wird — wie in ADR-0017 §7 / ADR-0027 §1 —
sowohl in Dart (`packages/kubb_domain`) als auch serverseitig in plpgsql
gespiegelt (Property-Parität als Merge-Gate). Die Slot-Befüllung erledigt zur
Laufzeit der bestehende Server-Trigger (`tournament_advance_ko_winner`,
ADR-0017 §5), die Factory materialisiert nur die Struktur.

---

## Kontext

`P6_KO_MODELS.md` legt die beiden „zweiter Baum"-Modelle fest. Modell A
(Double-Elim) ist über ADR-0027 bereits spezifiziert; Modell B (Trostturnier)
ist dort als Konzept beschrieben, lässt aber zwei Punkte ausdrücklich offen
(`P6_KO_MODELS.md` §„Offene Implementierungs-Details"):

1. die **Freilos-Regel** im Trostturnier (Hauptbaum ist freilos-frei,
   das Trostturnier braucht intern Freilose), und
2. die **exakte Einstiegsrunden-Zuordnung** der gestaffelten Verlierer „analog
   `lbDropTarget` aus ADR-0027".

Dieses ADR schliesst beide Lücken, definiert die Konfig-Form (`p_setup`,
snake_case) und das Mapping auf das bereits vorhandene `ConsolationConfig`,
fixiert die Endrang-Berechnung und benennt den Read-Path-Phase-Marker, damit die
Implementierungs-Tasks (Domain → Server → UI) ohne Rückfragen starten können.

Die strukturellen Invarianten kommen aus den verbindlichen Quellen:

- `P6_SETUP_WIZARD_SPEC.md` Z. 74/76: Hauptbaum-Grösse = Zweierpotenz, keine
  Freilose im Hauptbaum; Spiel um Platz 3 ist **immer** an (Toggle entfernt).
- `P6_SETUP_WIZARD_SPEC.md` Z. 107 / `P6_KO_MODELS.md` Z. 99/122:
  Halbfinal-Verlierer gehen ins **Spiel um Platz 3**, **nie** ins Trostturnier.
- `P6_RULES_DECISIONS.md` §E: Trostturnier ist ein eigenständiges KO-Tableau mit
  eigenem Per-Phasen-Regelsatz; Seeding wie Hauptbracket (`seed_high_vs_low`).

---

## 1. Bracket-Struktur (Brief-Punkt 1)

### 1.1 Hauptbaum = Single-Elimination (ADR-0017), unverändert

Der Hauptbaum ist **bit-identisch** das Output von
`Bracket.singleElimination(ids, withThirdPlace: true)`:

- Recursive-Seeding (`_standardBracketOrder`, `bracket.dart` Z. 304-314).
- Grösse = Zweierpotenz (`consolation_main_bracket_size ∈ {4,8,16,32,…}`),
  **keine Freilose** im Hauptbaum (`P6_SETUP_WIZARD_SPEC.md` Z. 74). Weil der
  Veranstalter die Hauptbaum-Grösse als Zweierpotenz wählt und genau so viele
  Teams aus der Vorrunde qualifiziert werden, treten im Hauptbaum **keine**
  BYE-Pairings auf.
- **Spiel um Platz 3 ist immer aktiv** (`withThirdPlace = true`,
  `P6_SETUP_WIZARD_SPEC.md` Z. 76). Es entsteht über die bestehende
  `BracketPhase.thirdPlace`-Logik (ADR-0017 §4), in die der
  `tournament_advance_ko_winner`-Trigger die beiden Halbfinal-Verlierer spiegelt.

Das Trostturnier verändert den Hauptbaum **nicht** — keine zusätzlichen Slots,
keine geänderte Seed-Order, keine Freilose. Es ist ein zusätzlicher Match-Block.

### 1.2 Trostturnier = separater zweiter Baum, kein Grand-Final-Merge

Das Trostturnier ist ein **eigenständiges Single-Elimination-Tableau** (mit
eigenem Trost-Final = Platz 5/6 und eigenem Trost-Spiel-um-Platz-3 = Platz 7/8).
Es ist strukturell vom Hauptbaum **getrennt**:

- Es gibt **keinen** Match, der Trostturnier-Teilnehmer mit Hauptbaum-Teilnehmern
  zusammenführt (kein Grand Final, kein Bracket-Reset).
- Es gibt **keine** Kante zurück in den Hauptbaum. Wer aus dem Hauptbaum fällt,
  kann den Titel nicht mehr gewinnen.

### 1.3 Explizite Abgrenzung zu ADR-0027

| | ADR-0027 (Double-Elim, Modell A) | ADR-0028 (Trostturnier, Modell B) |
|---|---|---|
| Zweiter Baum | Loser-Bracket (LB), **gekoppelt** | Trostturnier, **separat** |
| Merge | **Grand Final** (WB-Sieger vs. LB-Sieger), optionaler Reset | **kein** Grand-Final-Merge |
| Titel über zweiten Baum | **Ja** — LB-Sieger kann Turniersieger werden | **Nein** — Trost-Sieger holt nur Platz 5 |
| Spiel um Platz 3 | **nein** (Platz 3 = LB-Finalverlierer) | **immer ja** (Hauptbaum, Halbfinal-Verlierer) |
| Freilose im zweiten Baum | über `size` aufgelöst, an LB-R1 | **erlaubt** (siehe §4) |

**Verbindlicher Satz:** Beim Trostturnier kann — anders als beim LB-Sieger im
Double-Elim von ADR-0027 — der Sieger des zweiten Baums **nicht** den
Turniertitel holen; es gibt keinen Weg zurück in den Hauptbaum.

---

## 2. Gestaffelter Loser-Feed (Brief-Punkt 2)

### 2.1 Prinzip

Verlierer einer Hauptbaum-Runde steigen je nach **Ausscheide-Runde** in eine
**unterschiedliche** Trostturnier-Runde ein: früh ausgeschiedene früh, später
ausgeschiedene später (`P6_KO_MODELS.md` Z. 111-124). Die **Halbfinal-Verlierer
gehen NICHT ins Trostturnier**, sondern ins Spiel um Platz 3 (Hauptbaum,
ADR-0017 §4).

Sei

```
mainSize   = consolation_main_bracket_size   // Zweierpotenz
mainRounds = log2(mainSize)                   // Hauptbaum-Rundenzahl
```

Hauptbaum-Runde `mainRounds-1` ist das Halbfinale, `mainRounds` ist das Finale.
Nur Verlierer aus den Runden `1 .. mainRounds-2` (Achtel-/Viertelfinale etc.)
speisen ins Trostturnier ein.

### 2.2 Geschlossene Drop-Formel `consolationDropTarget`

Analog zu `lbDropTarget` (`bracket.dart` Z. 283-289) ist die Zuordnung eine
**reine, geschlossene Funktion** von `(mainRound, position, mainSize)` — kein
Laufzeit-Lookup. Der Sentinel `kConsolationThirdPlace = -1` markiert den
Halbfinal-Ausschluss (Verlierer geht ins Spiel um Platz 3, nicht ins
Trostturnier); `kConsolationNone = 0` markiert „kein Drop" (Final / out of range).

```dart
/// Sentinels for the consolation drop target (ADR-0028 §2).
const int kConsolationThirdPlace = -1; // semifinal loser -> 3rd-place playoff
const int kConsolationNone = 0;        // final / no consolation feed

/// Closed-form, pure mapping (ADR-0028 §2.2): which consolation round a loser of
/// main-bracket round [mainRound] (1-based) enters. [mainSize] is the
/// power-of-two main-bracket size; [position] is the 1-based pairing index in
/// the main round (kept for parity with [lbDropTarget]; the target ROUND does
/// not depend on it — only the within-round seeding/slot does, see §3.3).
///
/// mainRounds = log2(mainSize). Round mainRounds-1 = semifinal (its losers go to
/// the third-place playoff, NOT the consolation), round mainRounds = final.
///
/// The return value is the target consolation ROUND, not a slot. Staggered feed
/// (major/minor mechanic, like the LB in ADR-0027 §1.3): a loser eliminated in
/// main round `r` (1 <= r <= mainRounds-2) enters consolation round `r`. For
/// r == 1 the loser is one of the consolation-R1 entrants (seeded via §3.3). For
/// r >= 2 the loser does NOT open a fresh consolation-R`r` pairing; it occupies
/// the B-slot of a pairing whose A-slot is the consolation survivor of the prior
/// round (the round is then sized recursively, §3.3 — never via
/// next_pow2(total)). This is exactly the "Gestaffelter Einstieg" block in
/// P6_KO_MODELS.md (lines ~111-124).
int consolationDropTarget(int mainRound, int position, int mainSize) {
  final mainRounds = _log2(mainSize);
  if (mainRound >= mainRounds) return kConsolationNone;       // final -> P1/P2
  if (mainRound == mainRounds - 1) return kConsolationThirdPlace; // semifinal
  // Feeding rounds 1..mainRounds-2 map 1:1 onto consolation rounds.
  return mainRound; // consolation round index (1-based)
}

int _log2(int n) {
  var r = 0;
  var x = n;
  while (x > 1) {
    x >>= 1;
    r++;
  }
  return r;
}
```

Der **Slot innerhalb** der Ziel-Trostrunde (welches Pairing, A/B-Seite) folgt der
Seeding-Regel aus §3.3 (Direkt-Starter + reflektierte Verlierer); die *Runde*
selbst ist die geschlossene Formel oben. Damit ist `consolationDropTarget` —
wie `lbDropTarget` — in Dart und plpgsql trivial paritätstestbar.

### 2.3 Halbfinal-Ausschluss

Der Halbfinal-Ausschluss ist in der Formel **explizit** modelliert: für
`mainRound == mainRounds-1` liefert `consolationDropTarget`
`kConsolationThirdPlace`, nie eine Trostrunde. Der Trigger leitet diese Verlierer
ausschliesslich in die bestehende `BracketPhase.thirdPlace`-Logik (ADR-0017 §4).

---

## 3. Direkt-Einspeisung & durchgerechnete Beispiele (Brief-Punkte 2 + 3)

### 3.1 Durchgerechnetes Beispiel — 8er-Hauptbaum, `consolation_direct_count = 0`

```
mainSize=8, mainRounds=3.  (Hauptbaum A..H, vgl. P6_KO_MODELS.md Z. 84-108)

HAUPTBAUM
  Viertelfinale (R1, 4 Matches)   -> 4 Verlierer (H,E,F,G)
  Halbfinale    (R2, 2 Matches)   -> 2 Verlierer (D,C)  --> Spiel um Platz 3
  Final         (R3, 1 Match)     -> Platz 1/2 (A,B)

consolationDropTarget pro Runde:
  R1 (Viertelfinale, =mainRounds-2): -> Trost-R1   (4 Verlierer)
  R2 (Halbfinale,    =mainRounds-1): -> kConsolationThirdPlace (NICHT Trost)
  R3 (Final):                        -> kConsolationNone

TROSTTURNIER (4 Teilnehmer, Zweierpotenz, keine Byes)
  Trost-R1 (Trost-HF, 2 Matches):  H-E -> H , F-G -> F
  Trost-R2 (Trost-Final):          H-F            -> Platz 5/6
  Trost-P3 (Trost-Spiel um P3):    E-G            -> Platz 7/8

Endrang:  1 A · 2 B · 3/4 (D,C) · 5/6 (H,F) · 7/8 (E,G)
```

Konsistent mit dem ASCII- und Endrang-Beispiel `P6_KO_MODELS.md` Z. 84-108
(4 QF-Verlierer → Trost-R1; HF-Verlierer → Spiel um Platz 3).

### 3.2 Durchgerechnetes Beispiel — 16er-Hauptbaum, `consolation_direct_count = 0`

```
mainSize=16, mainRounds=4.  (vgl. P6_KO_MODELS.md Z. 118-124)

HAUPTBAUM
  Achtelfinale  (R1, 8 Matches) -> 8 Verlierer
  Viertelfinale (R2, 4 Matches) -> 4 Verlierer
  Halbfinale    (R3, 2 Matches) -> 2 Verlierer --> Spiel um Platz 3
  Final         (R4, 1 Match)   -> Platz 1/2

consolationDropTarget pro Runde:
  R1 (Achtelfinale, =mainRounds-3): -> Trost-R1   (8 Verlierer)
  R2 (Viertelfinale,=mainRounds-2): -> Trost-R2   (4 Verlierer)
  R3 (Halbfinale,   =mainRounds-1): -> kConsolationThirdPlace (NICHT Trost)
  R4 (Final):                       -> kConsolationNone

TROSTTURNIER (staffel-bewusst, vgl. Rekurrenz §3.3; keine Byes)
  Trost-R1 (4 Matches): E_1 = 8 Achtelfinal-Verlierer (P_1=8, 0 Byes)
                        -> 4 Trost-R1-Sieger (= S_1)
  Trost-R2 (4 Matches): E_2 = 4 Trost-R1-Sieger (A-Slots)
                        + 4 Viertelfinal-Verlierer (B-Slots, frisch eingespeist)
                        = 8 (P_2=8, 0 Byes) -> 4 Trost-R2-Sieger (= S_2)
  Trost-R3 (Trost-HF, 2 Matches): E_3 = 4 (L_3=0) -> 2 Sieger (= S_3)
  Trost-R4 (Trost-Final): E_4 = 2 -> S_4 = 1  -> Platz 5/6
  Trost-P3 (Trost-Spiel um P3)  -> Platz 7/8 (Trost-HF-Verlierer)
```

Die Strukturzahlen (R1: 4 Matches/0 Byes, R2: 4 Matches/0 Byes, `consRounds = 4`)
sind **aus der Rekurrenz in §3.3 abgeleitet**, nicht aus `next_pow2(C)`: jede
Einstiegspopulation `E_r` (8, 8, 4, 2) ist bereits eine glatte Zweierpotenz, daher
ist der 16er (D=0) bye-frei.

Die 16er-Staffel entspricht exakt `P6_KO_MODELS.md` Z. 118-124
(Achtelfinal-Verlierer → Trost-R1, Viertelfinal-Verlierer → Trost-R2,
HF-Verlierer → Spiel um Platz 3). Beachte den Verlierer-„Zustrom" je Runde:
in Trost-R2 treffen die 4 Trost-R1-Sieger (A-Slot) auf die 4 frisch
eingespeisten Viertelfinal-Verlierer (B-Slot) — dieselbe Major-Runden-Mechanik
(A = Überlebender, B = frisch eingespeister Verlierer) wie `lbDropTarget` sie für
die LB-Major-Runden nutzt (`bracket.dart` Z. 274-289).

### 3.3 Kombination Direkt-Starter + gestaffelte Verlierer zu EINEM Baum

`consolation_direct_count` Teams aus der Vorrunde starten direkt im Trostturnier
(`P6_KO_MODELS.md` Z. 130-137). Sie werden mit den gestaffelt einsteigenden
Hauptbaum-Verlierern deterministisch zu **einem** Baum kombiniert. Die Topologie
ist — wie beim LB in ADR-0027 §1.3 — **staffel-bewusst** (major/minor): später
einsteigende Verlierer sind in den frühen Trostrunden **noch nicht präsent**, die
Baumgrösse darf daher **nicht** über `next_pow2(Gesamtteilnehmerzahl)` definiert
werden (das überzählt die R1-Population und liefert falsche Runden-/Bye-Zahlen).

1. **Trost-Topologie = staffel-bewusste Rekurrenz** (kein
   `next_pow2(Gesamtzahl)`). Sei `D = consolation_direct_count` und seien
   `L_r = mainSize / 2^r` die Hauptbaum-Verlierer aus Runde `r`
   (`r = 1 .. mainRounds-2`; `L_r = 0` für `r > mainRounds-2`). Die in **jeder**
   Trostrunde aktive Population entsteht rekursiv aus Überlebenden + frisch
   einsteigenden Verlierern dieser Runde:

   ```
   E_1 = D + L_1                       // Einsteiger Trost-R1 (Direkt + R1-Verlierer)
   P_r = next_pow2(E_r)                // pow2-Padding -> (P_r - E_r) Byes in Runde r
   S_r = P_r / 2                       // Überlebende nach Trost-Runde r (Byes inkl.)
   E_r = S_{r-1} + L_r    (r >= 2)     // Überlebende + frisch eingespeiste Verlierer

   consRounds = kleinstes r mit S_r == 1   // Trost-Final = Runde consRounds
   ```

   Die **Baumgrösse pro Runde** ergibt sich also aus der **früheste-Runde**-
   Population `E_1` (als `next_pow2`) und wächst durch die in jeder Major-Runde
   andockenden `L_r`; die **Rundenzahl** ist durch die **maximale einspeisende
   Hauptbaum-Runde** (Staffeltiefe) bestimmt, **nicht** durch
   `log2(next_pow2(C))`. Die Gesamtteilnehmerzahl
   `C = D + Σ_{r=1}^{mainRounds-2} L_r` wird nur noch für die **Bye-Bilanz pro
   Runde** (`P_r - E_r`, §4) gebraucht, nie für `consSize`/`consRounds`.
2. **Direkt-Starter seeden die frühe(n) Runde(n).** Die `D` Direkt-Starter werden —
   gemeinsam mit den **Trost-R1-Einsteigern** (= Hauptbaum-R1-Verlierer, die per
   §2.2 ebenfalls in Trost-R1 andocken) — über `_standardBracketOrder(P_1)`
   (Recursive-Seeding, `seed_high_vs_low` wie `P6_RULES_DECISIONS.md` §E) in die
   **erste** Trostrunde geseedet (`P_1 = next_pow2(E_1)`). Seed-Reihenfolge:
   zuerst die Direkt-Starter nach ihrem Vorrunden-Rang (höchster Rang = Seed 1),
   dann die R1-Verlierer nach Hauptbaum-Seed. Damit belegen die stärksten
   Direkt-Starter die Top-Seed-Slots (und erhalten ggf. die Byes aus §4).
3. **Gestaffelte Verlierer docken als B-Slot ihrer Ziel-Runde an.**
   Hauptbaum-Verlierer der Runde `r ≥ 2` steigen erst in Trost-Runde `r` ein
   (Ziel-**Runde** = Rückgabewert von `consolationDropTarget`, §2.2). Sie spielen
   dort **keine** eigenständigen Trost-R`r`-Pairings, sondern besetzen — analog
   zur LB-Major-Mechanik (ADR-0027 §1.4) — den **B-Slot** eines Pairings, dessen
   **A-Slot** der Trost-Überlebende der Vorrunde (Sieger aus Trost-R`r-1`) ist. Der
   konkrete B-Slot-Index folgt der Reflexion aus `lbDropTarget`
   (`bracketPosition` der Hauptbaum-Runde gespiegelt auf die Trost-Pairings der
   Zielrunde, Anti-Rematch zwischen den Hälften).

Damit ist die Kombination **deterministisch und eindeutig**: Direkt-Starter
(plus R1-Verlierer) füllen die früheste Runde via Recursive-Seeding; jede spätere
Hauptbaum-Runde dockt ihre `L_r` Verlierer als B-Slots ihrer Ziel-Trostrunde an
(A-Slot = Überlebender). Wo `consolation_direct_count = 0` (Beispiele §3.1/§3.2),
seeden allein die R1-Verlierer die erste Runde, und die Rekurrenz oben liefert
(bye-frei) genau die durchgerechneten Strukturen.

> **Nachrechnung der Rekurrenz für die Beispiele (D=0):**
> *8er:* `E_1 = 0 + 4 = 4`, `P_1 = 4` (0 Byes), `S_1 = 2`; `r = 2`: `L_2 = 0`
> (HF speist nicht ein) ⇒ `E_2 = 2`, `P_2 = 2`, `S_2 = 1` ⇒ `consRounds = 2`.
> *16er:* `E_1 = 0 + 8 = 8`, `P_1 = 8` (0 Byes), `S_1 = 4`; `r = 2`: `L_2 = 4`
> ⇒ `E_2 = 4 + 4 = 8`, `P_2 = 8` (0 Byes), `S_2 = 4`; `r = 3`: `L_3 = 0`
> ⇒ `E_3 = 4`, `S_3 = 2`; `r = 4`: `E_4 = 2`, `S_4 = 1` ⇒ `consRounds = 4`.
> Beide Male **bye-frei**, weil jede Einstiegspopulation `E_r` bereits eine glatte
> Zweierpotenz ist — exakt die Annotationen in §3.1/§3.2. Die alte Formel
> `consSize = next_pow2(C) = next_pow2(12) = 16` hätte für den 16er fälschlich
> 8 R1-Matches und 4 Byes behauptet; die Rekurrenz liefert korrekt 4 R1-Matches
> und 0 Byes.

---

## 4. Byes im Trostturnier (Brief-Punkt 4)

Anders als im Hauptbaum (der per Definition freilos-frei ist, §1.1) sind
**Freilose im Trostturnier ausdrücklich erlaubt** (`P6_KO_MODELS.md` Z. 149-153).
Sie sind nötig, weil `consolation_direct_count` frei wählbar ist und die
Einsteigerzahl pro Runde keine Zweierpotenz ergeben muss.

**Bye-Vergabe-Regel (deterministisch):**

1. **Pro Einstiegsrunde getrennt.** Die Bye-Auflösung wird **pro Trostrunde**
   betrachtet: Wenn die Einstiegspopulation `E_r` (Überlebende `S_{r-1}` + frisch
   eingespeiste Verlierer `L_r`, §3.3) keine Zweierpotenz ist, wird auf
   `P_r = next_pow2(E_r)` aufgefüllt; die `P_r - E_r` fehlenden Slots sind Byes
   (`isBye: true`). Genau diese Bye-Bilanz ist die einzige Verwendung der
   Gesamtteilnehmerzahl `C` (§3.3) — `Σ_r (P_r - E_r)` Byes insgesamt.
2. **Bye an Top-Seeds.** Die Byes gehen an die **höchsten Seeds** der jeweiligen
   Runde — exakt das FR-FMT-11-Muster aus ADR-0017 §3, das `Bracket.singleElim`
   bereits umsetzt (BYEs an Top-Seeds). In Trost-R1 sind die „höchsten Seeds"
   die Direkt-Starter mit dem besten Vorrunden-Rang (§3.3 Schritt 2); fehlen
   Direkt-Starter, die Hauptbaum-R1-Verlierer mit dem besten Hauptbaum-Seed.
3. **Walkover-Auflösung.** Ein Bye-Pairing wird beim Generieren als
   `is_bye_pairing` markiert; der `tournament_start_ko_phase`-Pfad finalisiert es
   sofort (Auto-Advance, ADR-0017 §3 / ADR-0027 §3.2), sodass der Bye-Sieger
   kampflos in die nächste Trostrunde aufrückt. Das ist identisch zum
   Single-Elim-Hauptbaum-Mechanismus, nur dass es im Hauptbaum nie auftritt.

Damit ist die Trost-Struktur — wie die LB-Struktur in ADR-0027 §1.5 — voll über
die staffel-bewusste Rekurrenz (§3.3) bestimmt; pro Runde überzählige Slots
(`P_r - E_r`) lösen sich als frühe Byes/Walkover auf. Es gibt **keine** globale
`consSize`-Annahme, weil später einsteigende Verlierer in den frühen Runden noch
nicht präsent sind.

---

## 5. Konfig-Form & Mapping auf `ConsolationConfig` (Brief-Punkt 5)

### 5.1 Felder in `p_setup` (snake_case)

| `p_setup`-Feld | Typ | Bedeutung | Mapping auf bestehende Domain |
|---|---|---|---|
| `consolation_main_bracket_size` | int (Zweierpotenz) | Hauptbaum-Grösse `mainSize` | **NEU** (Erweiterung) — leitet `mainRounds = log2` ab; nicht in `ConsolationConfig` vorhanden |
| `consolation_direct_count` | int ≥ 0 | Zahl der Direkt-Starter im Trostturnier | **NEU** (Erweiterung) — Modell-B-spezifisch, nicht in `ConsolationConfig` |
| `consolation_name` | string | frei wählbarer Anzeigename des Nebenturniers | **NEU** (Erweiterung) — reines Anzeige-/UI-Feld |
| `consolation_round_formats[]` | `MatchFormatSpec[]` | Per-Runde-Regelsatz des Trostturniers | **ERWEITERT** das bestehende einzelne `match_format` (`MatchFormatSpec?`) zu einer Liste pro Runde |

### 5.2 Verhältnis zur bestehenden `ConsolationConfig`

`ConsolationConfig` (`tournament_setup.dart` Z. 602-730) deckt heute den
**Bâton-Rouille-/Pärkli-Feed** ab und wird wie folgt zugeordnet:

- `enabled` → unverändert: Trostturnier (Modell B) an/aus.
- `source` / `ConsolationSource` → für Modell B ist die Quelle der gestaffelte
  Hauptbaum-Loser-Feed plus Direkt-Einspeisung. `early_ko_losers` bleibt die
  passende Semantik (Verlierer aus frühen KO-Runden); `source_rounds` wird durch
  die geschlossene Staffel-Formel (§2.2: alle Runden `1..mainRounds-2`)
  **subsumiert** — `source_rounds` kann als explizite Override-Liste erhalten
  bleiben, ist für Modell B aber redundant (Default = alle Nicht-HF-Runden).
- `match_format` (`MatchFormatSpec?`) → ist heute **ein** Regelsatz fürs ganze
  Trostturnier. `consolation_round_formats[]` ist die **explizite Erweiterung**
  auf einen Regelsatz **pro Runde** (`P6_RULES_DECISIONS.md` §E: „Eigene
  Per-Phasen-Rulesets … Finale Bo5, übrige Bo3"). Mapping-Regel:
  `consolation_round_formats[i]` = Format der Trost-Runde `i+1`; fehlt ein
  Eintrag, gilt das letzte vorhandene bzw. das `§E`-Default
  (Bo3/30min, Final Bo5/60min). Bei genau einem Eintrag ist es semantisch
  identisch zum bisherigen `match_format`.
- `rank_from`/`rank_to` → bleiben für `prelim_rank_band` (Pärkli) gültig; für
  den gestaffelten Modell-B-Feed werden sie nicht verwendet.

**Explizit als Erweiterung benannt:** `consolation_main_bracket_size`,
`consolation_direct_count`, `consolation_name` und die Listenform
`consolation_round_formats[]` gehen über das heutige `ConsolationConfig` hinaus
und werden bei der Implementierung additiv ergänzt (Drift-frei, weil die
bestehenden Felder unverändert weiter serialisiert werden).

### 5.3 Code-Skizze der Erweiterung (Dart)

```dart
/// Model-B (consolation) extension fields layered onto the existing
/// [ConsolationConfig] (ADR-0028 §5). Existing fields (enabled/source/
/// sourceRounds/rankFrom/rankTo/matchFormat) stay untouched for wire stability.
@immutable
final class ConsolationModelB {
  const ConsolationModelB({
    required this.mainBracketSize,   // consolation_main_bracket_size, pow2
    this.directCount = 0,            // consolation_direct_count
    this.name,                       // consolation_name (display only)
    this.roundFormats = const <MatchFormatSpec>[], // consolation_round_formats[]
  });

  final int mainBracketSize;
  final int directCount;
  final String? name;

  /// Per-round rule sets; index i => consolation round i+1. Empty => fall back
  /// to ConsolationConfig.matchFormat / the §E default (Bo3, final Bo5).
  final List<MatchFormatSpec> roundFormats;

  int get mainRounds {
    var r = 0, x = mainBracketSize;
    while (x > 1) { x >>= 1; r++; }
    return r;
  }
}
```

---

## 6. Endrang-Berechnung (Brief-Punkt 6)

Die Endrangliste ist deterministisch und kombiniert Hauptbaum (Plätze 1-4) mit
dem Trostturnier (ab Platz 5):

| Plätze | Quelle |
|---|---|
| 1 / 2 | Hauptbaum-**Final** (Sieger = 1, Verlierer = 2) |
| 3 / 4 | Hauptbaum-**Spiel um Platz 3** (Sieger = 3, Verlierer = 4) |
| 5 / 6 | Trostturnier-**Final** (Sieger = 5, Verlierer = 6) |
| 7 / 8 | Trostturnier-**Spiel um Platz 3** (Sieger = 7, Verlierer = 8) |
| 9+ | weitere Trost-Runden absteigend (frühere Trost-Verlierer = hintere Plätze) |

Konsistent mit dem Endrang-Beispiel `P6_KO_MODELS.md` Z. 108:
`1 A · 2 B · 3/4 (D,C) · 5/6 (H,F) · 7/8 (E,G)`.

Der Hauptbaum vergibt **nie** Plätze ab 5; das Trostturnier vergibt **nie**
Plätze 1-4. Beide Bäume sind in der Rangbildung disjunkt — passend zur
strukturellen Trennung aus §1 und zum HF-Ausschluss aus §2.3 (Halbfinal-Verlierer
landen über Platz 3/4 im Hauptbaum, nie im Trostturnier).

---

## 7. BracketPhase-Erweiterung für den Read-Path (Brief-Punkt 7)

### 7.1 Neuer Phase-Marker

Analog zu `wb`/`lb` in ADR-0027 §1.1 bekommt der Trostturnier-Baum eigene
Phase-Marker. Die `BracketPhase`-Enum wird um `consolation` (Trost-Runden) **und**
`consolationThirdPlace` (Trost-Spiel um Platz 3) erweitert, das Wire-Mapping
`kBracketPhaseWire` um die Strings `'consolation'` und `'consolation_third_place'`:

```dart
enum BracketPhase {
  winners,
  thirdPlace,
  finals,
  // Double-Elimination (ADR-0027 §1):
  wb,
  lb,
  grandFinal,
  grandFinalReset,
  // Consolation / Trostturnier (ADR-0028 §7): the consolation rounds carry
  // `consolation`; its 3rd-place playoff carries its OWN phase
  // `consolationThirdPlace`. The two are NOT folded into `thirdPlace`/
  // `consolation` + round_number, because consRounds can equal mainRounds (e.g.
  // an 8er main bracket with enough direct starters), which would collide on
  // (phase, round_number). phase stays the SOLE discriminator (ADR-0017/0027).
  consolation,
  consolationThirdPlace,
}

const Map<String, BracketPhase> kBracketPhaseWire = {
  'group': BracketPhase.winners,
  'ko': BracketPhase.winners,
  'final': BracketPhase.finals,
  'third_place': BracketPhase.thirdPlace,
  'wb': BracketPhase.wb,
  'lb': BracketPhase.lb,
  'grand_final': BracketPhase.grandFinal,
  'grand_final_reset': BracketPhase.grandFinalReset,
  'consolation': BracketPhase.consolation,                  // ADR-0028
  'consolation_third_place': BracketPhase.consolationThirdPlace, // ADR-0028
};
```

### 7.2 Belegung von `round_number` / `bracket_position`

Die Disambiguierung läuft — wie bei `third_place`/`wb`/`lb` — **ausschliesslich
über `phase`**, ohne neue Spalte:

- **Trost-Runden** (`phase = 'consolation'`): `round_number = 1..consRounds`
  (phasen-lokal, exakt wie ADR-0027 §1.1 WB/LB-Runden bei 1 beginnen),
  `bracket_position = 1..(#Matches der Trostrunde)`. Das Trost-Final ist die Row
  mit `round_number = consRounds`, `bracket_position = 1`.
- **Trost-Spiel um Platz 3**: nutzt die **eigene** Phase
  `phase = 'consolation_third_place'` (`round_number = 1`, `bracket_position = 1`,
  phasen-lokal). Es teilt sich **keine** `(phase, round_number)`-Koordinate mit
  irgendeiner anderen Row.

**Warum eine eigene Phase statt `third_place` + `round_number`-Bereich:** Eine
Trennung des Trost-Bronze vom Hauptbaum-Bronze allein über den
`round_number`-Bereich (Haupt: `mainRounds`; Trost: `consRounds`) wäre **nicht
eindeutig**: `consRounds` kann gleich `mainRounds` sein — z. B. ein 8er-Hauptbaum
(`mainRounds = 3`) mit genügend Direkt-Startern, sodass die Trost-Rekurrenz (§3.3)
ebenfalls `consRounds = 3` ergibt. Dann trügen Hauptbaum-Bronze und Trost-Bronze
**identische** `phase = 'third_place'` **und** `round_number = 3` → echte
Kollision. Die eigene Phase `consolationThirdPlace` schliesst diese Kollision
**strukturell** aus und hält die ADR-0017/0027-Invariante ein, dass `phase` der
**einzige** Diskriminator ist (DoD QG-08). Das bleibt **spaltenfrei** — es ist nur
ein zusätzlicher Wire-String / Enum-Wert, wie schon `wb`/`lb` gegenüber `winners`.

### 7.3 DB-Constraint & Read-Mapper

- `tournament_matches.phase` CHECK wird um `'consolation'` **und**
  `'consolation_third_place'` erweitert (idempotente Migration analog ADR-0027 §2:
  `DROP CONSTRAINT IF EXISTS` + neu mit beiden Strings in der Liste). **Keine** neue
  Spalte; `round_number`/`bracket_position` bleiben semantisch unverändert.
- `bracketFromMatches` (`bracket.dart` Z. 475) bekommt eine additive
  Fallunterscheidung — analog zur `hasDouble`-Erkennung in ADR-0027 §1.9: Sind
  `consolation`-Rows vorhanden, baut ein passiver `_consolationFromMatches` aus
  dem Hauptbaum (`winners`/`finals`/`thirdPlace`) **und** den `consolation`- sowie
  `consolationThirdPlace`-Rows einen kombinierten Read-Zustand über das bestehende
  `_pairingsForRound`-Helper. Der Mapper bleibt **passiv** (ADR-0017 §5 /
  ADR-0027 §1.9) — er schreibt keine Folge-Slots.

```dart
Bracket bracketFromMatches(List<KoMatchRow> matches) {
  final hasConsolation = matches.any((m) =>
      m.phase == BracketPhase.consolation ||
      m.phase == BracketPhase.consolationThirdPlace);
  if (hasConsolation) return _consolationFromMatches(matches); // ADR-0028 §7.3
  // ... bestehender Double-Elim- bzw. Single-Elim-Pfad unverändert ...
}
```

### 7.4 Slot-Befüllung zur Laufzeit (Server-Trigger)

Wie bei Single-/Double-Elim materialisiert die Factory nur die leere Topologie;
der bestehende `tournament_advance_ko_winner`-Trigger (ADR-0017 §5) füllt die
Folge-Slots. Erweiterung für `phase = 'consolation'`:

1. **Hauptbaum-Verlierer einspeisen** (Trigger-Zweig `phase IN ('ko','final')`):
   beim Finalisieren eines Hauptbaum-Matches der Runde `r` wird neben dem
   Sieger-Advance der **Verlierer** über `consolationDropTarget(r, position,
   mainSize)` in die Ziel-Trostrunde geschrieben (B-Slot, §3.3) — **ausser**
   `r == mainRounds-1` (Halbfinale → bestehende `third_place`-Logik) und
   `r == mainRounds` (Final → kein Drop).
2. **Trost-intern fortschreiben** (`phase = 'consolation'`): Sieger →
   Folge-Trostmatch (`round_number+1`, `ceil(bracket_position/2)`); A/B nach
   gerader/ungerader Position. Bye-Pairings sind beim Start bereits finalisiert
   (§4) und schieben den Bye-Sieger kampflos weiter.
3. **Trost-Bronze**: die beiden Trost-Halbfinal-Verlierer (Trost-R`consRounds-1`)
   werden in das `consolation_third_place`-Match (§7.2) gespiegelt — exakt die
   Bronze-Mechanik aus ADR-0017 §4, aber unter der **eigenen** Phase (nicht
   `third_place`), sodass kein `(phase, round_number)`-Konflikt mit dem
   Hauptbaum-Bronze entstehen kann (§7.2).

`mainSize` für die Drop-Berechnung wird — wie ADR-0027 §3.3 `size` aus dem
WB-Bestand — deterministisch aus dem Match-Bestand abgeleitet:
`mainSize = 2 ^ max(round_number über phase IN ('ko','final'))`. Keine neue
Spalte nötig.

---

## Konsequenzen

- **Maximale Wiederverwendung:** Hauptbaum = unverändertes
  `Bracket.singleElimination`; Trost-Bronze, Bye-Auflösung und Sieger-Advance
  reusen die bestehende Single-Elim-/ADR-0017-Mechanik. Nur die gestaffelte
  Einspeisung (`consolationDropTarget`) ist neue Logik — bewusst als reine
  Funktion analog `lbDropTarget` gehalten, damit Dart↔plpgsql-Parität trivial
  testbar bleibt.
- **Spaltenfrei:** `round_number`/`bracket_position` bleiben semantisch
  identisch; `phase` ist der einzige neue Diskriminator (zwei Werte:
  `consolation` für die Trost-Runden und `consolation_third_place` für das
  Trost-Spiel um Platz 3 — Letzteres bewusst als eigene Phase, weil `consRounds`
  gleich `mainRounds` sein kann und `third_place` + `round_number` dann kollidieren
  würde, §7.2). Minimal-invasiv für DB, Trigger und Read-Mapper.
- **Strukturell strenger als Double-Elim** beim Titel: ein einziger gerichteter
  Loser-Feed in den separaten Baum, kein Merge, kein Reset, keine Rückkante —
  weniger Trigger-Sonderlogik als der LB→GF-Pfad in ADR-0027.
- **Akzeptiertes Drift-Risiko:** zwei Generatoren (Dart + plpgsql) für die
  Trost-Topologie und die Drop-Formel → abgesichert über Property-Parität als
  Pflicht-Gate beim Implementieren (ADR-0017 §7 / ADR-0027 §5 Präzedenz).
- **UI** (Trost-Baum visuell unterhalb/neben dem Hauptbaum, eigener Name aus
  `consolation_name`) ist additive, risikoarme Arbeit und kommt — wie in
  ADR-0027 §6 — als letzter Build-Schritt nach Domain und Server.

## Alternativen

- **Trost-Verlierer in identische Slot-Indizes (ohne Reflexion)** statt der
  `lbDropTarget`-analogen Anti-Rematch-Reflexion (§3.3): verworfen, weil
  Direkt-Starter und gestaffelte Verlierer sonst gehäuft in dieselbe Trost-Hälfte
  fielen — inkonsistent zur etablierten Major-Runden-Mechanik aus ADR-0027 §1.4
  und schlechter ausbalanciert.
- **Halbfinal-Verlierer doch ins Trostturnier** (statt Spiel um Platz 3):
  verworfen — widerspricht `P6_KO_MODELS.md` Z. 99/122 und
  `P6_SETUP_WIZARD_SPEC.md` Z. 107 (Spiel um Platz 3 immer an, HF-Verlierer nie
  ins Trostturnier).
- **Grand-Final-Merge wie beim Double-Elim** (Trost-Sieger spielt um den Titel):
  verworfen — das ist genau der definierende Unterschied zwischen Modell A und
  Modell B (`P6_KO_MODELS.md` Z. 15-23/80). Beim Trostturnier ist Platz 1/2 mit
  dem Hauptbaum-Final endgültig.
- **Eigene `consolation`-Tabelle statt Phase-Diskriminator**: verworfen —
  Schema-/Status-Explosion, inkonsistent mit ADR-0017 §1 und ADR-0027 §2
  (Phase-pro-Match als einziger Diskriminator).
- **Freilose auch im Hauptbaum zulassen** (statt strikter Zweierpotenz):
  verworfen — widerspricht `P6_SETUP_WIZARD_SPEC.md` Z. 74. Freilose sind
  ausschliesslich im Trostturnier erlaubt (§4).
