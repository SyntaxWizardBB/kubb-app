# ADR-0030: Turnier-Komposition als Stufen-Graph (Framework)

- **Status**: Proposed
- **Date**: 2026-06-07
- **Bezug**: `docs/P6_RULES_DECISIONS.md` (alle Stufen-Typen + Per-Phasen-
  Rulesets §A, Schoch §G, Consolation §E, Mighty-Quali §F, Double-Elim §D,
  Seeding §I), `docs/P6_SETUP_WIZARD_SPEC.md` (heutiger Setup-Fluss),
  `docs/SKV_TOUR_POINTS.md` (Terminal-Mapping → Platzierung → Punkte;
  „errechnete Reihung reicht"), ADR-0017 (KO-Phase-Semantik, Phase-pro-Match,
  Server-Authority-Trigger), ADR-0019 (Pool-Phase + Cut), ADR-0027
  (Double-Elimination), ADR-0028 (Consolation/Trostturnier).
- **Domain-Quelle**: `packages/kubb_domain/lib/src/tournament/` — `bracket.dart`,
  `pool_phase.dart`/`pool_cut.dart`, `pairing/swiss_system.dart`,
  `shootout.dart`, `tournament_setup.dart` (`ConsolationConfig`,
  `ConsolationSource`, `MatchFormatSpec`), `standings.dart`, `tiebreaker.dart`,
  `elo_seeding.dart`. Server: `tournament_start_ko_phase`
  (`20260615000010`/`20261204000000`), Consolation-Server (`20261203000000`),
  `tournament_finalize` (`20261201000032` §6).

> **Reines DESIGN-/Entscheid-Dokument.** Dieses ADR legt das Modell, die
> Semantik des Runners und die Validierungs-Invarianten fest. Es enthält
> **keine** fertige Implementierung und **keine** Test-Suite — Build-Reihenfolge
> und Property-Gates werden beim Implementieren materialisiert (wie ADR-0027/0028).

## Kontext & Motivation

Reale Schweizer Turniere (Beleg: KubbMAIster-Turniertafel) sind **verkettete
Pipelines aus mehreren Stufen mit je eigenem Regelsatz und Verlierer-Routing**:
Vorrunde (4 Gruppen) → Haupt-KO → Finale, parallel dazu zwei Neben-Cups
(Klingnauer „roter Pfad", Höseler „weisser Pfad"), die aus **unterschiedlichen
Verlierer-Gruppen** des Hauptbaums gespeist werden und **eigene Regeln** haben.

Heute sind solche Kombinationen **fest verdrahtet**: `round_robin_then_ko`,
Pool→KO, optional **ein** Consolation-Baum (ADR-0028). Der Veranstalter kann
keine eigenen Mehrstufen-Formate zusammenstellen (zweite Gruppenphase, mehrere
Neben-Cups, beliebige Verlierer-Wege).

**Beobachtung**: Alle benötigten *Stufen-Algorithmen* existieren bereits (Pools,
Swiss/Schoch, Single-/Double-Elim, Consolation, Mighty-Quali, Shootout). Es
fehlt die **Orchestrierungs-Schicht**: ein generischer Graph + Runner +
Validierung + Editor. Die Consolation-Quellen (`early_ko_losers`,
`prelim_rank_band`) sind faktisch schon **Proto-Routing-Kanten** und werden hier
verallgemeinert.

## Entscheidung

Ein Turnier wird als **gerichteter azyklischer Graph (DAG) aus Stufen** modelliert:

- **Knoten = Stufe** mit Typ + eigenem Regelsatz + Seeding-Quelle.
- **Kante = Routing-Regel** mit *Selektor* (welche Teilnehmer der Quell-Stufe
  fliessen in die Ziel-Stufe).
- **Terminal-Mapping** bildet die Ergebnisse jeder Stufe auf globale Endränge ab.

Der **freie DAG-Editor** ist das Ziel-UI (Stufe 3 der Designdiskussion). **Frei
heisst „jeder *gültige* Graph", nicht „alles geht"** — die Validierung (unten)
ist das Herzstück, nicht der Editor. Die **Engine ist identisch**, ob das UI
geführt oder frei ist; der Editor ist die oberste Lage.

Die heutigen festen Kombis werden zu **Preset-Graphen** (Rückwärtskompatibilität,
§Kompatibilität). Die bestehenden Stufen-Algorithmen werden zu **Node-Typen**.

## Modell

### Node (Stufe)

```
Node {
  id:        string
  type:      pool | round_robin | swiss | single_elim | double_elim
             | consolation | shootout_quali
  ruleset:   MatchFormatSpec   // best_of, time_limit, tiebreak, scoring, ...
                               // (bestehender Per-Phasen-Ruleset, P6 §A)
  seeding:   from_elo | from_prev_ranking | manual | as_routed
  config:    typ-spezifisch    // pools: groupCount/qualifiersPerGroup;
                               // elim: withThirdPlace/seedingPattern; ...
}
```

### Edge (Routing-Regel)

```
Edge {
  from:      nodeId
  selector:  top_k(K)                 // beste K der Schluss-Reihung
           | ranks(a..b)              // Rangband a..b
           | losers_of_rounds({r...}) // Verlierer best. KO-Runden  ← Neben-Cups
           | non_qualifiers           // alle nicht via andere Kante Weitergeleiteten
           | winners                  // Sieger (Endrang 1 der Stufe)
  to:        nodeId
  seeding_in: order-preserving | reseed_by_source_rank | manual
}
```

`losers_of_rounds` + Ziel-`consolation`-Node = exakt der heutige
Klingnauer/Höseler-Mechanismus — jetzt **beliebig oft** und mit **eigenen
Regeln pro Ziel-Node**.

### Terminal-Mapping (→ Endplatzierung → SKV-Punkte)

Jede Stufe definiert, wie ihre lokalen Ergebnisse auf **globale Endränge**
abbilden (Offset + lokale Reihung). Gemäss `docs/SKV_TOUR_POINTS.md` gilt
**„errechnete Reihung reicht"**: KO-Stufen liefern Ränge per Bracket-Position
(Tiers), Nicht-KO-Plätze werden aus den Stufen-Standings gereiht — **kein
Platzierungs-Match nötig**. Das Mapping garantiert: **jeder Teilnehmer hat genau
einen globalen Endrang**.

## Runner-Semantik (Server-autoritativ)

Ereignisgesteuert, generalisiert `tournament_start_ko_phase` + Consolation-Seeding:

1. Eine Stufe wird **abgeschlossen** (alle Matches terminal → lokale Reihung steht).
2. Der Runner wertet ihre **ausgehenden Kanten** aus, wendet die Selektoren auf
   die lokale Reihung an.
3. Selektierte Teilnehmer werden in die **Ziel-Stufe(n)** materialisiert
   (Seeding gemäss `seeding_in`); deren Matches werden erzeugt, sobald **alle**
   eingehenden Kanten der Ziel-Stufe erfüllt sind (Join-Barriere).
4. Stufen ohne ausgehende Kanten + Terminal-Mapping ergeben die Endränge.

Server bleibt Autorität (Trigger/RPC wie ADR-0017 §5). Reihenfolge-/Atomaritäts-
Garantien wie bei den bestehenden KO-Advance-Triggern.

## Validierung & Spielbarkeits-Gate (das eigentliche Herz)

Die Konfiguration muss **vor Publikation/Start lückenlos geprüft** werden — ein
freier Editor erlaubt sonst unspielbare Turniere (zu wenige/zu viele Spieler in
einer Stufe, verwaiste Teilnehmer, nie endende Graphen). Die Validierung ist
eine **reine Domain-Funktion** (pure Dart, deterministisch, voll testbar) und
zugleich ein **harter Server-Gate** in den Publish-/Start-RPCs — Client und
Server prüfen denselben Code-Pfad (analog der bestehenden Setup-Validierung).

### Schweregrade

- **ERROR** → blockiert Publish/Start. Der Graph ist nicht spielbar.
- **WARNING** → erlaubt, aber sichtbarer Hinweis (z.B. Tagesplanbarkeit,
  ungewöhnlich viele Runden). Veranstalter bestätigt bewusst.

Jeder Befund trägt einen stabilen Code + die betroffene Node/Edge-Id, damit das
UI direkt an der richtigen Stelle markieren kann (analog qualifier-count.md U3–U9).

### Graph-Invarianten (ERROR)

- **V1 Azyklisch**: kein Zyklus (sonst läuft der Runner nie terminal).
- **V2 Mengen-Erhalt**: für jede Stufe gilt Σ(eingehende Selektoren) =
  Eingangs-Kapazität; kein Teilnehmer wird doppelt geroutet, keiner geht verloren
  (`non_qualifiers` fängt den Rest). Selektoren dürfen sich nicht überlappen.
- **V3 Vollständige Platzierung**: jeder Teilnehmer erreicht genau ein
  Terminal-Mapping → lückenlose, kollisionsfreie globale Rangliste (1..N).
- **V4 Erreichbarkeit**: jede Stufe ist von einer Quell-Stufe (oder der
  Teilnehmer-Liste) aus erreichbar; keine isolierten Knoten, keine toten Kanten.
- **V5 Seeding auflösbar**: `from_prev_ranking` nur, wenn eine eingehende Kante
  eine geordnete Quelle liefert; `manual` nur mit hinterlegter Seed-Liste.

### Spieler-Anzahl-Constraints pro Stufen-Typ (ERROR)

Jeder Node-Typ deklariert seine **gültige Eingangs-Kapazität**; die Validierung
propagiert die Teilnehmerzahlen entlang der Kanten (Kapazitäts-Propagation:
Output-Grösse jeder Stufe = Σ ihrer Selektoren) und prüft sie gegen:

| Node-Typ | Min | Max / Teilbarkeit |
|---|---|---|
| `single_elim` / `double_elim` | 2 | — (Nicht-2er-Potenz via BYE, ADR-0017 §3) |
| `pool` / `round_robin` | `groupCount × 2` | Teilnehmer durch `groupCount` aufteilbar; `qualifiersPerGroup < Gruppengrösse` |
| `swiss` | `rounds + 1` | gerade Zahl bevorzugt (sonst BYE-Logik) |
| `consolation` | 2 | speisende Quelle muss ≥ Min liefern |
| `shootout_quali` | 2 | `slots < pool_size` (P6 §F) |

Zusätzlich: jede Stufe muss **mindestens 2** Teilnehmer bekommen (sonst kein
Match); `qualifierCount`/Selektor-Grenzen `2 ≤ K ≤ Quellgrösse`.

### Kapazität / Planbarkeit (WARNING)

- **V6 Match-/Feld-Last**: geschätzte Gesamt-Matchzahl + parallele Stufen vs.
  verfügbare Felder (`tournament_assign_pitches`); Hinweis auf Tagesplanbarkeit.
- **V7 Runden-Tiefe**: ungewöhnlich viele Stufen/Runden → Hinweis.

### Gate-Punkte

- **Im Editor**: Live-Validierung bei jeder Änderung; Publish-Button bleibt
  gesperrt, solange ein ERROR offen ist.
- **Server**: `tournament_publish` / `tournament_start_*` rufen dieselbe
  Validierung als finale, nicht umgehbare Schranke auf.

Validierung ist **gemeinsame Engine** für geführtes UI *und* freien Editor.

## Templates / wiederverwendbare Konfigurationen

Ein einmal gebauter Turnier-Graph (inkl. „lustiger" Mehrstufen-Formate, aller
Rulesets, Seeding-Quellen und Routing-Kanten) muss **als Template gespeichert
und wiederverwendet** werden können — sonst muss jeder Veranstalter sein Format
jedes Mal neu zusammenstecken.

### Modell

```
StageGraphTemplate {
  id, name, description, owner_user_id, club_id?,
  visibility:  private | club | public,
  graph:       { nodes[], edges[], terminal_mapping }   // teilnehmer-AGNOSTISCH
  created_at, updated_at
}
```

- **Teilnehmer-agnostisch**: ein Template beschreibt **Struktur + Regeln**, nicht
  konkrete Spieler/Seeds. Beim Anwenden wird es auf die aktuelle Teilnehmerliste
  instanziiert (Seeding gemäss Node-Config aufgelöst).
- **Parametrisierbar**: Felder wie `groupCount`, `qualifierCount`,
  `rounds`, `slots` können beim Anwenden überschrieben werden (das Template hält
  Defaults). So passt „Gruppen → KO + 2 Neben-Cups" auf 24 *und* 48 Teilnehmer.

### Operationen

- **Speichern**: aus dem aktuellen Setup („Als Vorlage speichern") → Template.
- **Anwenden**: Template wählen → instanziiert den Graphen ins neue Turnier-Setup,
  danach frei editierbar (Template bleibt unverändert — Kopie-Semantik).
- **Validierung beim Anwenden**: dieselbe Validierungs-Engine läuft gegen die
  konkrete Teilnehmerzahl (ein Template kann strukturell valide, aber für *diese*
  Feldgrösse unspielbar sein → klare Fehlermeldung, z.B. „braucht ≥ 16 Teams").
- **Mitgelieferte Presets**: die kanonischen Formate (Single-Elim, Pool→KO,
  +Consolation, Schoch→KO, sowie eine „KubbMAIster-Style"-Vorlage Gruppen→KO+2
  Cups) als **read-only System-Templates** als Startpunkt.

### Persistenz

Eigene Tabelle `tournament_stage_graph_templates` (RLS: `private` nur Owner,
`club` für Club-Mitglieder, `public` für alle — analog der bestehenden
Sichtbarkeits-Muster). Der `graph`-Body als validiertes JSONB. Ein konkretes
Turnier referenziert beim Erstellen optional `source_template_id` (nur als
Herkunfts-Hinweis; keine Live-Bindung — Kopie-Semantik).

## Bau-Lagen (auch innerhalb „Stufe 3")

1. **Daten-Modell + Runner**: Persistenz (Stage-/Edge-Tabellen), Node-Typen aus
   bestehenden Algorithmen, Runner-Materialisierung. Bestehende Kombis als
   Preset-Graphen abbildbar.
2. **Validierung & Spielbarkeits-Gate** (V1–V7 + Spieler-Anzahl-Constraints) als
   reine Domain-Funktion (pure Dart) + nicht umgehbarer Server-Gate in
   Publish/Start. **Vor** dem Editor, weil jede Komponier-UI darauf aufsetzt.
3. **Templates**: Speichern/Anwenden teilnehmer-agnostischer Graphen +
   System-Presets. Baut auf Modell (1) + Validierung (2) auf.
4. **Visueller DAG-Editor** im Setup-Wizard (zuletzt). Davor: geführtes
   Komponieren über dieselbe Engine.

Lagen 1–3 sind identisch zur „geführten" Variante; der freie Editor ist Lage 4.

## Kompatibilität / Migration

- Bestehende `bracket_type`/`format`-Kombis werden als **kanonische Preset-Graphen**
  ausgedrückt (Single-Elim = 1 Node; Pool→KO = Pool-Node → Elim-Node;
  +Consolation = zusätzliche `losers_of_rounds`-Kante → Consolation-Node).
- `tournament_finalize` (heute nur Status-Flip) wird um den **Terminal-Mapping →
  Platzierungs-Berechnung**-Schritt erweitert (gemeinsamer Eingang für Strang 1).
- Kein Bruch: Turniere ohne expliziten Graph laufen über ihren Preset-Graphen.

## Abgrenzung

- **Nicht** Teil dieses ADR: die SKV-Punkte-Formel (→ `SKV_TOUR_POINTS.md`,
  Strang 1) und das ELO-Rating (Strang 2). Der Graph **liefert** die
  Platzierungen, die Strang 1 konsumiert — mehr nicht.
- Platzierungs-**Matches** (untere Ränge ausspielen) sind **bewusst nicht** im
  Scope: Owner-Entscheid „errechnete Reihung reicht".

## Offene Punkte

1. **Persistenz-Schema**: neue Tabellen `tournament_stages` + `tournament_stage_edges`
   vs. Erweiterung des bestehenden Setup-JSON. (Empfehlung: eigene Tabellen wegen
   Runner-Queries + RLS.)
2. **Scheduling/Feld-Zuweisung** über parallele Stufen (mehrere Cups gleichzeitig)
   — Interaktion mit `tournament_assign_pitches` (`20261201000003`).
3. **Runner-Aufteilung**: wie viel plpgsql (Server-Autorität) vs. Domain-Dart
   (Validierung/Reihung). Empfehlung: Reihung/Selektoren als pure Dart,
   Materialisierung server-seitig (Trigger/RPC).
4. **Live-Editing**: darf ein Graph nach Turnierstart noch geändert werden
   (nur leere Folge-Stufen)? Default: nach Start eingefroren.
5. **Editor-UX**: Node-Palette, Kanten-Zeichnen, Live-Validierungs-Feedback,
   Preset-Bibliothek als Startpunkt.

> Fundament für Strang 3 (Format-Framework). Reihenfolge gegenüber Strang 1
> (SKV-Punkte) und Strang 2 (ELO) wird separat festgelegt; alle drei sind
> unabhängig baubar.
