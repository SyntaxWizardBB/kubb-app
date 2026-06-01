# P6 — Regel-Entscheidungen für das Tournament-Setup

- **Stand**: 2026-05-31
- **Rolle**: Regel-Entscheider P6 (verbindliche Defaults, keine Rückfragen)
- **Quellen**:
  - `ruleSets` (Infomails: Bâton d'Or / Bâton Rouille, Wasserschloss Solo Trophy, SM Einzel, Lions/Simba Cup, Foggy King/Nebelprinz, Winterthur Kubb Open / Pärkli)
  - `docs/rules/README.md` (Engineering-Summary Schweizer Kubbverband v1.11)
  - `docs/domain-knowledge/qualifier-count.md`, `docs/domain-knowledge/spiel-um-platz-3.md`
  - `docs/adr/0017-ko-phase-semantics.md`
  - `packages/kubb_domain/lib/src/tournament/{bracket.dart,ko_phase.dart,tiebreaker.dart,pairing.dart}`

**Konventionen dieses Dokuments**: Enum-/Wire-Werte in `snake_case` (DB-Konvention). Zeiten in
Sekunden (`*_seconds`), passend zum bestehenden Setup-Feld `time_limit_seconds`. „Best of n"
wird als `sets_to_win` (Siege zum Matchgewinn) + `max_sets` (Anzahl gespielter Sätze) modelliert:
Bo3 = `sets_to_win: 2, max_sets: 3`; Bo5 = `sets_to_win: 3, max_sets: 5`; Bo2 = `sets_to_win: 2,
max_sets: 2` (Punktewertung statt Satz-K.o., siehe G).

---

## A. KO-Regelsatz-Defaults (Best-of / Zeitlimits / Tiebreak je Phase)

**Entscheidung.** Pro KO-Runde wird ein eigener `KoRoundRuleset` konfiguriert. Default-Profil
(ableitbar aus der Anzahl KO-Runden, von hinten gerechnet — Finale = letzte Runde):

| Runden-Bucket (Default) | sets_to_win | max_sets | time_limit_seconds | tiebreak_after_seconds | tiebreak_enabled | final_no_tiebreak |
|---|---|---|---|---|---|---|
| Frühe Runden (alles bis inkl. „Sechzehntel-äquivalent", d.h. die Runden **vor** den letzten 4) | 2 | 3 | 2400 (40 min) | 1500 (25 min) | true | – |
| Mittlere Runden (Achtel/Viertel, d.h. die Runden, die zu den letzten 4 führen, exkl. HF/Final) | 3 | 5 | 3600 (60 min) | 2400 (40 min) | true | – |
| Halbfinale | 3 | 5 | 3600 (60 min) | — | **false** | – |
| Finale | 3 | 5 | 3600 (60 min) | — | **false** | **true** |

Operationalisierung (deterministisch, ohne Runden-Namen raten): sei `R` = Anzahl KO-Runden.
- Letzte Runde (`r == R`) → Finale-Profil.
- Vorletzte Runde (`r == R-1`) → Halbfinale-Profil (Bo5, kein Tiebreak).
- Runden mit `r >= R-3 && r < R-1` (Achtel/Viertel-Bereich) → Bo5 mit Tiebreak nach 40 min.
- Alle früheren Runden (`r < R-3`) → Bo3 mit Tiebreak nach 25 min.

Bei kleinen Brackets (z.B. nur 4 Qualifier = HF + Final) greifen nur Halbfinale- und Finale-Profil.

**Tiebreak-Set-Semantik (verbindlich, aus allen Mails konsistent):** Nach Tiebreak-Beginn wird der
**laufende Satz fertig gespielt**. Ein **weiterer** Satz wird nur begonnen, wenn das Match nach
diesem Satz unentschieden steht (1:1 bzw. 2:2). Danach ist das Match in jedem Fall zu Ende. →
Flag `finish_current_set_then_decider: true` (immer true im KO).

**Begründung.** Direkt aus Bâton d'Or: „bis und mit 1/32 Bo3, Tiebreak nach 25 min, Limit 40 min;
ab Sechzehntel Bo5, Limit 60 min, Tiebreak nach 40 min; ab Halbfinale ohne Tiebreak" (ruleSets
Z. 59, 113). SM Einzel: „KO Bo5 mit Tiebreak nach 50 min, Finale ohne Tiebreak" (Z. 266) bestätigt
das Bo5-Muster mit Final-Sonderregel. Die 60-min/40-min-Bo5-Werte sind die häufigste Kombination
über die Mails hinweg.

**Erlaubte Optionen.** Veranstalter kann pro Runde überschreiben: `sets_to_win ∈ {1,2,3}`,
`max_sets ∈ {1,2,3,5}`, `time_limit_seconds` frei (0 = ohne Limit, wie Wasserschloss HF/Final
Z. 192), `tiebreak_enabled` bool, `tiebreak_after_seconds` frei (< `time_limit_seconds`),
`final_no_tiebreak` bool. Quick-Picks: `bo3_25_40`, `bo5_40_60`, `bo5_no_tb`, `unlimited_no_tb`.

---

## B. KO-Tiebreak-Methode

**Entscheidung.** Zwei Methoden als Enum `ko_tiebreak_method`:
- `classic_kingtoss_removal` (**Default für alle KO-Matches**)
- `mighty_finisher_shootout` (nur für Qualifikations-/Rangierungs-Zwecke, **nicht** als Match-Tiebreak im KO)

**Semantik `classic_kingtoss_removal`** (ruleSets Punkt 2, Z. 9–13 / 222–226 / 286 / 317–319):
1. Bei Ablauf der `tiebreak_after_seconds` wird das Tiebreak ausgerufen; die **laufende Wurfrunde
   wird fertig gespielt**.
2. **Zweiter Kingtoss** (möglichst nah an den König). Sieger erhält den *Tiebreakvorteil*.
3. Nach der nächsten Einwerfrunde der bevorteilten Person werden die Kubbs aufgestellt und der
   **hinterste Kubb des verteidigenden Teams** aus dem Spiel genommen. Bei Gleichstand (zwei gleich
   weit hinten) wählt die verteidigende Seite.
4. Danach nach **jeder** Einwerfrunde ein weiterer Kubb der gegnerischen Seite raus → jede Runde
   ein Kubb weniger. Entfernte Kubbs bleiben für den Rest des Satzes draussen.
5. Entscheidungssatz während Tiebreak: vorher **dritter Kingtoss**; Sieger wählt zwischen
   Anspiel+Seite **oder** Tiebreakvorteil. Erster Kubb wird in der gesamt 4. Wurfrunde entfernt
   (= nach der 2. Einwerfrunde der bevorteilten Seite).

**Semantik `mighty_finisher_shootout`** (ruleSets Punkt 4, Z. 19 / 232): siehe F — ein Speed-Run
gegen die eigene Aufstellung, der über *Anzahl benötigter Stöcke* rangiert; bei Gleichstand
8m-Sudden-Death. Das ist ein **Qualifikations-/Tiebreak-Verfahren auf Turnierebene**, kein
Mechanismus, um ein einzelnes laufendes KO-Match zu entscheiden.

**Begründung.** Alle sechs Turnier-Mails definieren für KO-Matches ausschliesslich den klassischen
Kingtoss-Removal-Tiebreak (Punkt 2). Der Mighty-Finisher (Punkt 4) erscheint nur im Wasserschloss-
Modell als *Qualifikations-Shootout* für Gruppenzweite (Z. 184) und in der Rangierungs-Kette als
*Shootout* (Z. 17, 400) — nie als Match-Decider im Bracket.

**Erlaubte Optionen.** Pro KO-Match-Tiebreak nur `classic_kingtoss_removal` (Default, faktisch
einzige Wahl im Match). `mighty_finisher_shootout` ist als Verfahren wählbar in (F) Wildcard-Quali
und (H) Rangierungs-Tiebreaker.

---

## C. Begegnungslogik / Seeding im KO

**Entscheidung.** Default `seed_high_vs_low` (Standard-Bracket-Seeding: Seed 1 vs Seed n, 2 vs n−1,
… via Recursive-Standard-Order). Enum `ko_seeding_pattern`: `seed_high_vs_low` (Default) |
`one_vs_two`. Mappt direkt auf `BracketSeedingPattern.recursive` (Default) bzw. die lineare/1-vs-2-
Variante in `bracket.dart`.

**Begründung.** Standard-Turnierpraxis und bereits Code-Default: `bracket.dart` nutzt
`BracketSeedingPattern.recursive` als Default (Z. 49) — Seed 1 und 2 treffen frühestens im Finale
aufeinander; BYEs gehen an Top-Seeds (FR-FMT-11, qualifier-count.md). Das Wasserschloss-Mail setzt
den KO-Baum explizit „nach dem Durchschnitt der gewonnenen Punkte pro Spiel" (Z. 184), also
seed-basiert beste vs. schwächste — kein 1-vs-2-Direktduell. ADR-0017 §7 portiert genau diese
Recursive-Order serverseitig.

**Erlaubte Optionen.** `seed_high_vs_low` (Default) und `one_vs_two` (Nischenfall, wenn der
Veranstalter Vorrunden-Platzierte direkt gegeneinander setzen will). Manuelle Seeding-Overrides
bleiben via `SeedingMode.manual` (`ko_phase.dart`) möglich.

---

## D. Double-Elimination (Double-KO) — vollständige strukturelle Spezifikation

**Entscheidung.** Neuer Bracket-Typ `double_elimination` analog zu `SingleEliminationBracket` in
`bracket.dart`. Winner-Bracket (WB) + Loser-Bracket (LB) + Grand Final (GF) mit Bracket-Reset.
Spezifikation für die Generierung:

### D.1 Grundgrössen
- `N` = Anzahl Qualifier, `size = next_pow2(N)`, `byes = size − N`.
- WB ist ein normales Single-Elim-Bracket über `size` Slots (identisch zur bestehenden
  `Bracket.singleElimination`, Recursive-Seeding, BYEs an Top-Seeds).
- WB hat `wbRounds = log2(size)` Runden. WB-Runde `k` hat `size / 2^k` Matches.
- LB hat `lbRounds = 2 * (wbRounds − 1)` Runden.

### D.2 Loser-Bracket-Struktur (Standard-Double-Elim, „major/minor"-Schema)
Die LB-Runden alternieren zwischen **minor** (nur WB-Verlierer-Einspeisung von vorhandenen
LB-Überlebenden gepaart … nein, präzise:) und **major** Runden:

- **LB-Runde 1 (minor)**: Pairt die Verlierer von **WB-Runde 1** untereinander.
  → `size/4` Matches.
- **LB-Runde 2 (major)**: Pairt die `size/4` Überlebenden aus LB-R1 gegen die `size/4` Verlierer
  von **WB-Runde 2**. → `size/4` Matches.
- **LB-Runde 3 (minor)**: Pairt die `size/8` Überlebenden aus LB-R2 untereinander. → `size/8`.
- **LB-Runde 4 (major)**: `size/8` Überlebende aus LB-R3 gegen `size/8` Verlierer aus **WB-Runde 3**.
- … allgemein: ungerade LB-Runden (minor) konsolidieren LB-Überlebende untereinander;
  gerade LB-Runden (major) speisen die Verlierer der nächsthöheren WB-Runde ein.
- **Letzte LB-Runde** (LB-Finale): 1 Match. Sieger = LB-Champion, zieht ins Grand Final.

**Einspeisungs-Regel (verbindlich):** Verlierer aus **WB-Runde `k`** fallen in **LB-Runde `2k−2`**
(major), für `k >= 2`. WB-Runde-1-Verlierer fallen in LB-Runde 1. Beispiel `size = 8` (wbRounds=3,
lbRounds=4):
- WB-R1-Verlierer (4) → LB-R1 (2 Matches).
- WB-R2-Verlierer (2) → LB-R2, gepaart gegen die 2 LB-R1-Sieger.
- WB-R3-Verlierer (1, = WB-Finalist-Verlierer) → LB-R4 (LB-Finale), gegen den LB-R3-Sieger.

**Cross-Bracket-Anti-Rematch-Seeding:** Beim Einspeisen der WB-Verlierer in eine major-LB-Runde
wird die Slot-Reihenfolge gespiegelt/rotiert, sodass ein Spieler nicht sofort wieder auf den
gleichen Gegner trifft, dem er gerade im WB unterlegen ist. Default-Regel: WB-Verlierer der
oberen Bracket-Hälfte werden in die untere LB-Hälfte eingespeist und umgekehrt (Standard
„loser bracket cross-seeding"). Implementierbar als feste Permutation pro Runde.

### D.3 Grand Final + Bracket-Reset
- **GF Spiel 1** (`grand_final`): WB-Champion vs. LB-Champion.
- Gewinnt der **WB-Champion** GF1 → Turnier zu Ende (WB-Champ war verlustfrei, LB-Champ hatte
  bereits eine Niederlage → 2. Niederlage = Aus).
- Gewinnt der **LB-Champion** GF1 → **Bracket-Reset**: ein zweites Match `grand_final_reset` (GF2)
  wird gespielt; beide haben dann je 1 Niederlage. Sieger GF2 = Turniersieger.
- Default `with_bracket_reset: true`. Optional abschaltbar (`false` = GF1 entscheidet einmalig,
  „kürzeres" Format für Zeitnot).

### D.4 Seeding & BYE
- WB-Seeding identisch zu Single-Elim (Recursive-Standard-Order, BYEs an Top-Seeds).
- Ein WB-Match, das durch ein BYE „gewonnen" wurde, speist **keinen** realen Verlierer ins LB ein
  → der entsprechende LB-Slot wird selbst zum BYE und der gegenüberstehende LB-Teilnehmer rückt
  kampflos auf. (Analog zur BYE-Behandlung in `bracket.dart`; LB-BYEs entstehen genau dort, wo das
  speisende WB-Match ein BYE-Match war.)
- Konsequenz für nicht-2^n: die LB-Struktur bleibt voll (`size`-basiert), die durch WB-BYEs
  erzeugten LB-BYEs lösen sich in den frühen minor/major-Runden auf.

### D.5 Match-Phasen-Werte (DB, analog ADR-0017 §1)
`tournament_matches.phase` erhält neue Werte für Double-Elim:
`wb` (Winner-Bracket), `lb` (Loser-Bracket), `grand_final`, `grand_final_reset`.
Sieger-/Verlierer-Fortschreibung läuft trigger-basiert wie ADR-0017 §5, erweitert um die
LB-Einspeisungs-Regel aus D.2 (Verlierer eines WB-Matches → vorgegebener LB-Slot).

**Begründung.** Standard-Double-Elim-Topologie (major/minor LB, GF mit Reset) ist die in der
Bracket-Theorie und international übliche Form; sie garantiert, dass der Turniersieger genau bei
zwei Niederlagen ausscheidet und Fairness gegenüber dem verlustfreien WB-Champion (1-Niederlage-
Vorteil im GF) wahrt. Bracket-Reset ist nötig, weil sonst der WB-Champion bei einer einzigen
GF-Niederlage trotz nur einer Gesamt-Niederlage ausschiede — inkonsistent mit „double". Die
Wiederverwendung der bestehenden Recursive-Seeding-/BYE-Logik aus `bracket.dart` hält die
Property-Parität (ADR-0017 §7) erhalten.

**Erlaubte Optionen.** `with_bracket_reset` bool (Default true). Per-Phasen-Rulesets (A) auch hier
anwendbar (`wb`/`lb`/`grand_final` je eigenes `KoRoundRuleset`). `third_place` ist bei
Double-Elim **nicht** nötig (Platz 3 = LB-Finalverlierer ergibt sich strukturell) → bei
`double_elimination` ist `with_third_place_playoff` standardmässig `false` und gesperrt.

---

## E. Consolation-Bracket (Bâton Rouille / „Best of the Rest")

**Entscheidung.** Optionales `consolation_bracket` als zweites, eigenständiges KO-Tableau.
Konfiguration:
- `enabled` bool (Default `false`).
- `source` Enum `consolation_source`:
  - `early_ko_losers` — **Default** wenn aktiviert: Verlierer aus den **ersten beiden KO-Runden**
    (analog Bâton Rouille: 1/64- und 1/32-Verlierer, ruleSets Z. 61/115).
  - `prelim_rank_band` — Verlierer/Nicht-Qualifizierte eines Platzierungs-Bands aus der Vorrunde
    (analog Pärkli: Ränge 17–24, Z. 372). Parameter `rank_from`/`rank_to`.
- Default-Quell-Runden bei `early_ko_losers`: KO-Runde 1 und 2.
- Default-Quell-Band bei `prelim_rank_band`: Ränge `qualifierCount+1 .. qualifierCount+8`
  (= die nächsten 8 nach dem regulären Cut; Pärkli nimmt 17–24 bei Top-16-Cut → exakt dieses Muster).

**Default-Regelsatz Consolation** (aus Bâton Rouille, Z. 61/115): alle Runden Bo3 mit Tiebreak
nach 20 min und Limit 30 min (`sets_to_win:2, max_sets:3, time_limit_seconds:1800,
tiebreak_after_seconds:1200`); **Finale** Bo5 mit Tiebreak nach 50 min und Limit 60 min
(`sets_to_win:3, max_sets:5, time_limit_seconds:3600, tiebreak_after_seconds:3000`).

**Begründung.** Bâton Rouille speist exakt die 1/64- und 1/32-Verlierer ein und nennt die
Zeit-/Bo-Werte explizit (Z. 61, 115). Pärkli teilt nach der Vorrunde in zwei Tableaus: Top-16 →
Hauptcup, Ränge 17–24 → „Best of the Rest" (Z. 372). Beide Muster sind so verbreitet, dass sie als
die zwei Default-Quellen taugen.

**Erlaubte Optionen.** `enabled` bool; `source ∈ {early_ko_losers, prelim_rank_band}`;
bei `early_ko_losers` konfigurierbare `source_rounds` (Default {1,2}); bei `prelim_rank_band`
`rank_from`/`rank_to`. Eigene Per-Phasen-Rulesets wie in (A), vorbelegt mit dem Default-Regelsatz
oben. Seeding wie Hauptbracket (`seed_high_vs_low`).

---

## F. Mighty-Finisher-Quali (Wasserschloss-Modell)

**Entscheidung.** Optionaler Wildcard-Qualifikationsschritt zwischen Vorrunde und KO. Enum
`wildcard_qualifier_method: mighty_finisher_shootout`. Konfiguration:
- `enabled` bool (Default `false`).
- `pool` Enum: `group_runners_up` (Default — alle Gruppenzweiten) | `rank_band`.
- `slots` int — Anzahl zu vergebender KO-Plätze. **Default = 6** (Wasserschloss: 10 Gruppenzweite →
  6 Wildcards ins Achtelfinale, Z. 184). Validierung `1 <= slots < pool_size`.

**Ablauf (verbindlich, exakt ruleSets Punkt 4, Z. 19/232):**
1. Jede Person/Team wirft **8 Kubbs** ein; eine andere Person stellt diese auf.
2. **2 zusätzliche Kubbs** stehen auf der Grundlinie (gesamt 10 stehende Kubbs + König).
3. Die einwerfende Person wirft so viele Stöcke (in 6er-Runden), bis **alle Kubbs und der König
   regulär gefallen** sind. Gewertet wird die **Anzahl benötigter Stöcke** (weniger = besser).
4. Rangierung der Pool-Teilnehmer nach benötigten Stöcken aufsteigend; die besten `slots`
   qualifizieren sich.
5. **Gleichstand auf KO-relevanten Plätzen → 8m-Sudden-Death**: alle Gleichstehenden werfen
   nacheinander je einen Stock (aus 8 m) auf einen Basekubb. Sobald mind. eine Person **nicht**
   trifft, während mind. eine **trifft**, scheiden alle Nicht-Treffer aus. Wiederholen, bis die
   Anzahl Verbliebener der Anzahl offener KO-Plätze entspricht.

**Begründung.** Direkte Übernahme des Wasserschloss-Quali-Modells (Z. 184) plus der exakten
Shootout-Mechanik aus Regeln Punkt 4 (Z. 232). 6 Slots ist die belegte Zahl bei 10 Gruppenzweiten.

**Erlaubte Optionen.** `enabled` bool; `slots` frei (Default 6); `pool ∈ {group_runners_up,
rank_band}`. Tiebreak-Verfahren fix `eight_meter_sudden_death`.

---

## G. Schoch-Modus (Vorrunde) — Bestätigung Paarungslogik

**Entscheidung & Bestätigung.** Der bestehende Swiss/Buchholz-Algorithmus
(`PairingStrategyKind.swissSystem`, `pairing/swiss_system.dart`, `pairing/buchholz.dart`) **deckt
die Schoch-Definition aus den Mails korrekt ab**. Verbindliche Parameter:
- **Live-Score-Paarung**: nach jeder Runde wird neu gepaart, abhängig von der aktuellen Rangliste
  (Z. 315/343/384) → Swiss-System mit „pair by current standings". ✔ entspricht
  `PairingStrategyKind.swissSystem`.
- **Primärwertung**: Anzahl getroffener Basekubbs (+ Satzgewinn-Bonus, siehe Scoring `ekc`).
- **Sekundärwertung**: **Buchholz** (Summe der Gegnerstärken) → `TiebreakerCriterion.buchholz*`
  in `tiebreaker.dart`. ✔ vorhanden.
- **Max. 8 Punkte/Satz**: bestätigt durch EKC-Punktsystem (1 Punkt je Basekubb × max 5 + 3 für
  Satzgewinn = 8; Z. 259/304). Gehört in die `ekc`-Scoring-Engine (`ekc_score.dart`), nicht in die
  Paarung.
- **Anzahl Durchgänge (Default aus n Teilnehmern)**: Default `rounds = 8`. Beleg: SM Einzel,
  Lions, Foggy King, Winti, Pärkli spielen alle „8 Spiele" (bzw. 7 bei den kleineren
  Neben-Cups: Simba/Nebelprinz/Pärkli, Z. 308/336/372). Default-Formel:
  `rounds = clamp(ceil(log2(n)) + 3, 5, 9)`, vorbelegt auf **8** für typische Feldgrössen
  (n ≈ 32–128). Kleinere Felder → weniger Runden, untere Schranke 5.

**Begründung.** Die Mails beschreiben „Schochmodus" / „EKC-Schoch" eindeutig als Live-Score-Swiss
mit Buchholz-Sekundärwertung (Z. 314–315, 342–343, 382–384). Genau dieses Verhalten ist in
`swiss_system.dart` + `buchholz.dart` modelliert; das Domain-Modell ist konform. 8 Runden ist der
durchgängige Empirie-Wert der Hauptturniere.

**Erlaubte Optionen.** `prelim_format: schoch` (= Swiss mit Live-Score-Paarung). `rounds` frei
(Default 8, bzw. 7 für Neben-Cup-Profil). Scoring fix `ekc` für Schoch (Basekubb-Zählung ist
zwingend für die Primärwertung). Sätze Bo2 (`sets_to_win:2, max_sets:2`, Punktewertung — kein
3. Satz, beide Sätze werden gespielt und Punkte summiert).

---

## H. Rangierungs-/Tiebreaker-Kette (Gleichstand nach Vorrunde)

**Entscheidung.** Default-Kette `prelim_tiebreaker_chain` als geordnete Liste von
`TiebreakerCriterion` (mappt 1:1 auf `tiebreaker.dart`):

1. `total_points` — Punkteverhältnis / Gesamtpunkte (Primärwertung).
2. `buchholz_minus_h2h` — Buchholz-Sekundärwertung (Schoch).
3. `direct_comparison` — Resultat der Direktbegegnung.
4. `mighty_finisher_shootout` — Shootout als letzte sportliche Entscheidung.
5. (Fallback) deterministischer Tie-Break über Participant-ID (bereits in `TiebreakerChain` als
   Schluss-Fallback, garantiert totale Ordnung — ADR-0017 §4).

**Begründung.** Die Mails nennen unterschiedliche, aber kompatible Ketten: Wasserschloss/SM/Bâton:
„Punkteverhältnis, Direktbegegnung, Shootout" (Z. 17/230); Winti/Pärkli: „Buchholz, dann Shootout"
(Z. 396–400). Die Default-Kette vereint beide sinnvoll: erst die punktbasierte Primärwertung, dann
Buchholz (für Schoch-Felder die feinere Stärke-Metrik), dann Direktbegegnung (klassisch), zuletzt
Shootout (physische Entscheidung). Bei `round_robin` ohne Buchholz fällt Kriterium 2 faktisch weg
(alle Gegnerstärken über volle Liga ähnlich) und greift Direktbegegnung.

**Erlaubte Optionen.** Veranstalter kann die Reihenfolge umstellen und Kriterien entfernen/
hinzufügen aus `{total_points, buchholz_minus_h2h, median_buchholz, kubb_difference,
direct_comparison, wins, mighty_finisher_shootout, random}`. Empfohlene Presets:
`swiss_default` = [total_points, buchholz_minus_h2h, direct_comparison, mighty_finisher_shootout];
`round_robin_default` = [total_points, direct_comparison, kubb_difference, mighty_finisher_shootout].

---

## I. Ranking/Seeding-Quelle vor Turnierstart (Phase 5)

**Entscheidung.** Auto-Seeding-Quelle Enum `seed_source`: `elo` (Default) | `manual` | `random`.
Berechnung des Seed-Werts pro Teilnehmer:
- **Einzel**: `seed_rating = player.elo` (App-internes ELO/Rating aus der Spielerstatistik).
- **Team/Gruppe**: `seed_rating = sum(elo der gemeldeten Mitglieder)` — **ELO-Summe** der Roster-
  Mitglieder. Bei ungleichen Teamgrössen normalisiert: `seed_rating = avg(member_elo) *
  effective_size`, wobei `effective_size` die für die Liga gewichtete Kopfzahl ist (2er-Teams
  zählen 2/3, vgl. README „2-player teams weighted at 2/3", Z. 93). Default-Implementierung ohne
  Liga-Kontext: schlichte **Summe** der Mitglieder-ELO.
- Sortierung absteigend nach `seed_rating` → Seed 1 = höchstes Rating.
- Fehlende ELO (neue Spieler): Default-Startwert `elo_default = 1200`; Teilnehmer ohne jegliche
  Historie werden ans untere Seed-Ende sortiert (Tie-Break über `random` mit fixem Turnier-Seed,
  reproduzierbar).

**Begründung.** ELO-Summe ist die geforderte und intuitiv korrekte Aggregation für Gruppen (ein
Team aus drei starken Spielern soll höher gesetzt werden als eines aus drei schwachen). Der
2/3-Gewichtungsfaktor für 2er-Teams ist bereits Liga-Konvention im Regelwerk (README Z. 93) und
hält Auto-Seeding und spätere Liga-Punkte konsistent. ELO 1200 als Startwert ist der übliche
neutrale Default.

**Erlaubte Optionen.** `seed_source ∈ {elo, manual, random}` (Default `elo`).
Team-Aggregation `team_rating_mode ∈ {sum, average, weighted}` (Default `sum`; `weighted` nutzt
2/3-Faktor). `elo_default` konfigurierbar (Default 1200). Manuelles Override pro Seed bleibt über
`SeedingMode.manual` (`ko_phase.dart`) erhalten.

---

## Zusammenfassung — Defaults zum sofortigen Umsetzen

| Bereich | Default |
|---|---|
| **A. Früh-KO** | Bo3 (`sets_to_win:2,max_sets:3`), `time_limit_seconds:2400`, `tiebreak_after_seconds:1500` |
| **A. Achtel/Viertel** | Bo5 (`3/5`), `time_limit:3600`, `tiebreak_after:2400` |
| **A. Halbfinale** | Bo5 (`3/5`), `time_limit:3600`, `tiebreak_enabled:false` |
| **A. Finale** | Bo5 (`3/5`), `time_limit:3600`, `final_no_tiebreak:true` |
| **A. Tiebreak-Set** | `finish_current_set_then_decider:true` (immer) |
| **B. KO-Tiebreak-Methode** | `classic_kingtoss_removal` |
| **C. KO-Seeding** | `seed_high_vs_low` (recursive, BYEs an Top-Seeds) |
| **D. Double-Elim** | `double_elimination`, `with_bracket_reset:true`, Phasen `wb/lb/grand_final/grand_final_reset`, LB-Einspeisung WB-R`k`→LB-R`2k−2`, kein Spiel-um-Platz-3 |
| **E. Consolation** | `enabled:false`; wenn an → `early_ko_losers` {R1,R2}, Bo3/25min, Final Bo5/50min |
| **F. Mighty-Finisher-Quali** | `enabled:false`; wenn an → `group_runners_up`, `slots:6`, 8 Kubbs einwerfen + 2 Base, Wertung nach Stöcken, Gleichstand `eight_meter_sudden_death` |
| **G. Schoch** | `prelim_format:schoch` (=Swiss live-score + Buchholz), `rounds:8` (7 für Neben-Cup), Scoring `ekc`, Bo2; bestehender Swiss/Buchholz-Algorithmus ist konform |
| **H. Rangierung** | `[total_points, buchholz_minus_h2h, direct_comparison, mighty_finisher_shootout]` + ID-Fallback |
| **I. Seeding-Quelle** | `seed_source:elo`; Team = **Summe** der Mitglieder-ELO; `elo_default:1200` |

**Geschriebenes Dokument:** `/home/lukas/Workbench/FlutterKubbClub/KubbProj/docs/P6_RULES_DECISIONS.md`
