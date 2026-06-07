# SKV-Tour-Punktesystem — Spezifikation (System 1)

- **Stand**: 2026-06-07
- **Status**: Verbindliche Spec, empirisch hergeleitet + validiert. Offene Punkte
  am Ende explizit markiert.
- **Zweck**: Saison-/Tour-Wertung über mehrere Turniere hinweg („bestes Team /
  bester Einzelspieler der Saison"). Pro Turnier werden feldgrössen-skalierte
  Platzierungspunkte vergeben; über die Saison kumuliert (mit Streichresultaten).
- **Abgrenzung**: Dies ist **NICHT** die Spielstärke-/Seeding-Wertung. Das
  fortlaufende Spielstärke-Rating (ELO) ist ein eigenes System (System 2, eigene
  Spec) mit anderer Mathematik. Hier geht es ausschliesslich um Tour-Ranglisten-
  punkte.

## Quellenlage

Das SKV-Tour-Punktesystem ist **nirgends öffentlich als Formel publiziert**
(weder auf kubbtour.ch noch im SKV-Spielregel-PDF, das nur die Spielregeln
enthält). Diese Spec wurde am 2026-06-07 **empirisch aus ~24 abgeschlossenen
Turnier-Schlussranglisten und den Jahresranglisten 2025 von kubbtour.ch
abgeleitet** und gegen die Jahres-Quersummen validiert. Die Kernparameter
decken sich exakt mit der bereits im Repo dokumentierten Engineering-Summary
(`docs/rules/README.md` §"League points").

Bei einer späteren Beschaffung des offiziellen Tour-Reglements (info@kubbtour.ch)
sind die hier markierten „offenen" Konstanten gegenzuprüfen.

---

## 1. Eignung (welches Turnier zählt)

- Ein Turnier zählt nur für die Tour-Wertung, wenn es **≥ 8 Teilnehmer (Teams
  bzw. Einzelspieler)** hat.
- In der App: nur **gewertete** Turniere (`tournament_is_rated` = `club_id IS NOT
  NULL`, CF1). Reine Spass-/Übungsturniere fliessen nicht in die Tour-Wertung.

## 2. Sieger-Punkte W(N) — feldgrössen-skaliert

Die Punkte des Siegers skalieren linear mit der Feldgrösse N (Anzahl gewerteter
Teilnehmer):

```
W(N) = 100 × (1 + (N − B) / (2·B))
```

- `B` = Referenz-/Basisgrösse je Liga (Sieger eines Turniers der Grösse B erhält
  genau 100 Punkte; bei 3·B erhält der Sieger 200 = doppelte Basis).
- Liga-Referenzgrössen (empirisch bestätigt, deckt sich mit „10/20/40"-Angabe
  der Engineering-Summary):

  | Liga / Kategorie | B | Beispiel (gemessen) |
  |---|---|---|
  | **A/B** (Hauptturnier, Team) | **10** | N=42 → 260 · N=28 → 190 · N=16 → 130 |
  | **C** (Nebenturnier) | **20** | N=20 → 100 |
  | **Einzel** | **40** | N=73 → 141 (⚠ siehe offene Punkte) |

- Für Liga A/B mit B=10 vereinfacht sich die Formel zu `W = 5·N + 50`.
- Es wird auf ganze Punkte gerundet (kaufmännisch).

## 3. Punkte je Platzierung

### 3.1 Ränge 1–4 — feste Faktoren (hart bestätigt)

```
P(Rang k) = round(W × faktor[k]),   faktor = [1.0, 0.8, 0.65, 0.5]
```

Über mehrere Turniere ganzzahlig bestätigt (z.B. KCUA W=260 → 260/208/169/130;
KubbMAIster W=190 → 190/152/124/95; Masters W=200 → 200/160/130/100).

### 3.2 Ränge ab 5 — KO-Stufen (gestuft pro Ausscheidungsrunde)

Alle Teilnehmer, die in **derselben KO-Runde** ausscheiden, erhalten **gleich
viele** Punkte (ein „Tier"). Auf kubbtour.ch heissen diese Tiers je nach Turnier
„Drittelfinal / Sechstelfinal / Zehntelfinal" o.ä. — das sind reine
**Anzeige-Labels für Platzierungs-Tiers**, keine Bracket-Mechanik. Im reinen
KO-Teil sind die Tiers Zweierpotenz-Gruppen, deren Wert sich je Runde etwa
halbiert:

```
Tier 1  (Viertelfinal-Verlierer,  Ränge 5–8)   ≈ 0.25  × W
Tier 2  (Achtelfinal-Verlierer,   Ränge 9–16)  ≈ 0.125 × W
Tier 3  (Sechzehntel-Verlierer,   Ränge 17–32) ≈ 0.0625 × W
Tier t  (allgemein)                            ≈ 0.5^(t+1) × W
```

Empirisch (sauberste Single-Elim-Felder): Kubb it Up (W=210) → Tier1=51
(=0,243·W), Tier2=27 (=0,129·W); SM Einzel (W=141) → Tier1=29, Tier2=15. Die
Halbierung je Runde ist über die Turniere stabil.

**Verbindliche App-Regel:** `P(Tier t) = round(W × 0.5^(t+1))`, wobei `t` die
Anzahl überstandener KO-Runden minus der ersten ist (Tier 1 = Viertelfinal-Aus).

### 3.3 Vorrunden-Schwanz (Nicht-KO-Plätze)

Teilnehmer, die es **nicht in den KO** schaffen (in der Vorrunde/Gruppenphase
ausgeschieden), erhalten **fein degressive Einzelwerte** statt Stufen. In den
echten Turnieren variiert dieser Schwanz format-abhängig (Platzierungsspiele
etc.) und ist **nicht allgemeingültig rekonstruierbar**.

**Designentscheidung (eigene, SKV-treue Regel für die App):** Vom Wert des
letzten KO-Tiers `P_last` linear absteigend bis zu einem Mindestwert
`P_min` über die verbleibenden Ränge:

```
Sei R_ko = letzter KO-Rang (z.B. 16 bei einem 16er-Bracket),
    P_last = Punkte des letzten KO-Tiers,
    P_min  = Mindestpunkte für den letzten Platz (Default 3),
    M      = N − R_ko (Anzahl Nicht-KO-Plätze).
Für Rang r in (R_ko+1 .. N):
    P(r) = round( P_last − (P_last − P_min) × (r − R_ko) / M )
```

Deterministisch, monoton fallend, für unsere Turnierformate konsistent.
`P_min` und die Linearität sind App-Konvention (nicht aus SKV bewiesen).

## 4. Team-Gewichtung (2er-Teams)

Für die Feldgrössen-/Liga-Einordnung zählen **2er-Teams als 2/3 Kopfzahl**
(Liga-Konvention, `docs/rules/README.md`). Relevant, wo Kopfzahl in die
Einstufung eingeht; bei reiner Platzierungswertung pro Team ohne Effekt.

## 5. Masters

- Masters-Punkte sind **fix**, nicht feldgrössen-skaliert:
  `W_masters = 100 × liga_multiplikator`.
- Liga-Multiplikator: **A/C ×2** (Sieger 200), **B ×1** (Sieger 100).
- Gewertet werden **Top 8** (Liga A/B) bzw. **Top 16** (Liga C).
- Rang-/Tier-Logik (§3) gilt analog auf der Masters-Basis.

## 6. Liga-Logik (welche Resultate in welche Rangliste)

- **Liga A/B**: nur Resultate aus **Hauptturnieren**.
- **Liga C**: Resultate aus Haupt- **und** Nebenturnieren; die maximale Punktzahl
  richtet sich nach der **Nebenturnier-Teilnehmerzahl** (B=20).
- Drei getrennte Team-Ranglisten (A/B/C) + eine **Einzelrangliste**. Mapping in
  der App: `tournaments.league_categories` (A/B/C) bzw. `team_size = 1` (Einzel)
  — siehe bestehende RPC `tournament_ranking_get` (P8-B1).

## 7. Saison-Aggregation + Streichresultate

- Punkte werden über die Saison **additiv** je Teilnehmer summiert
  (`SeasonStandingsAggregator`, ADR-0025).
- **Streichresultate aktiv** (empirisch bestätigt): es zählen nur die **besten N**
  Turnierergebnisse. Belege 2025: Breitizone (10 Resultate) → Summe = Total
  exakt; Tent it up I (15 Resultate) → Summe 1456, Total 1303 → die schlechtesten
  gestrichen.
- **N (Anzahl Wertungen)**: konfigurierbar pro Saison/Liga. Echte Tour-
  Grössenordnung: ~9–10 für Liga A (Einzelrangliste ≤ Anzahl Liga-A-Turniere,
  + ggf. Masters). Exakter Wert nicht publiziert → als Saison-Parameter führen.
- Sortierung: `totalPoints` ↓ → `tournamentCount` ↓ → `displayName` ↑.

## 8. Worked Example (Liga A, sauberes 16er-Bracket, N=16)

```
W = 100 × (1 + (16 − 10)/20) = 100 × 1.30 = 130
Rang 1 = 130 ; Rang 2 = 104 ; Rang 3 = 85 ; Rang 4 = 65
Rang 5–8  (Tier 1) = round(130 × 0.25)  = 33   (≈ gemessen Sure-Shot 30)
Rang 9–16 (Tier 2) = round(130 × 0.125) = 16
(kein Vorrunden-Schwanz, da 16 = Bracketgrösse)
```

## 9. Mapping auf den bestehenden Code (was sich ändert)

- **Ersetzt/ergänzt** `LeaguePointsEngine` (heute Matchpunkt+Bonus-Modell): die
  Engine muss auf dieses **Platzierung × Feldgrösse**-Modell umgestellt werden.
  Vorschlag: neue, klar benannte Domain-Funktion (z.B. `skvTourPoints(...)`)
  neben der bestehenden, damit die alte Logik (Tests) nicht zerstört wird.
- **Eingang**: pro Turnier eine **eindeutige Endplatzierung je Teilnehmer**. Die
  muss beim Finalize aus Vorrunden-Standings (`computeStandings` + Tiebreaker)
  und KO-Bracket-Resultat berechnet werden — **fehlt heute** in
  `tournament_finalize`.
- **Ausgang**: `TournamentPointsAward` je Teilnehmer → idempotenter Schreibpfad
  in `season_standings_awards` → bestehende Aggregation + `tournament_ranking_get`
  → bestehende Rangliste-/Saison-Screens.

## 10. Offene / noch zu verifizierende Punkte

1. **Einzel-Skalierung (B=40)**: bei SM Einzel exakt bestätigt, andere Einzel-
   Events streuen (mögliche abweichende Basen / Feldzählung). Vor produktivem
   Einsatz der Einzelrangliste mit mehr Einzel-Daten gegenprüfen.
2. **Exakter KO-Tier-Faktor**: 0,25 / 0,125 (Halbierung) ist empirisch ~±0,03
   genau; ob SKV exakt 0,25 oder z.B. einen rangbasierten Wert nutzt, ist nicht
   bewiesen. Für die App ist die Halbierung verbindlich gesetzt.
3. **Vorrunden-Schwanz**: bewusst eigene App-Regel (§3.3), nicht SKV-bewiesen.
4. **Streichresultat-Anzahl N**: nicht publiziert; als Saison-Parameter geführt.
5. **Masters Tier-Tiefe** und **2/3-Gewichtungs-Anwendung** bei gemischten
   Teamgrössen: noch nicht an Live-Daten verifiziert.

> Diese Spec ist das Fundament für die Umsetzung von System 1
> (Platzierung → SKV-Punkte → Awards → Rangliste). Phasenplan separat.
