# M3 — Teams + Pool + Roster — Offene Entscheidungen

> Status: Entwurf, wartet auf Abnahme
> Datum: 2026-05-26

Folgende Punkte sind vor Implementierungsstart zu klären. Jeder Punkt blockt mindestens einen Task aus dem Milestone-Plan.

## OD-M3-01: Schutz gegen Missbrauch der gleichberechtigten Captain-Rechte? `[resolved]`

**Frage**: FR-TEAM-5 sagt: alle registrierten Pool-Mitglieder haben identische Captain-Rechte. Spec-Open-Point 1 (§7.1) fragt nach Schutzmechanismen. Was bauen wir in M3?

**Warum blockierend**: Bestimmt RPC-Logik in M3.1-T2 plus UI-Verhalten in M3.1-T10.

**Optionen**:
- **A) Keine zusätzlichen Schutzmechanismen** — jedes Mitglied kann jedes andere entfernen, Pool-Daten ändern, Team auflösen. Audit-Trail dokumentiert alles.
  - Pros: einfachste Implementierung, deckt FR-TEAM-5 wörtlich ab.
  - Cons: ein verärgertes Mitglied kann den Pool sprengen. Owner-Pilot-Phase mit Freundeskreis wenig riskant, aber für Mass-Adoption fragil.
- **B) Audit + Inbox-Notification an alle bei kritischen Aktionen** — Removal eines Mitglieds erzeugt Audit-Event plus Push / Inbox-Eintrag an alle anderen Pool-Mitglieder.
  - Pros: nachvollziehbar, soziale Kontrolle. Keine harte Sperre, aber Transparenz.
  - Cons: ein Insert mehr pro Removal — vernachlässigbarer Aufwand.
- **C) Mehrheits-Bestätigung für kritische Aktionen** — Removal braucht 50%+ Zustimmung. Dissolve braucht 100% (FR-TEAM-19 sagt das bereits).
  - Pros: harte Sicherheit.
  - Cons: Voting-Mechanik plus UI plus Pending-Action-Tabelle. Eigenes M3.4-Sub-Milestone. Deutlich mehr Aufwand.
- **D) Cooldown** — frisch eingeladene Mitglieder können in den ersten 48h keine kritischen Aktionen ausführen.
  - Pros: verhindert Drive-by-Removals.
  - Cons: künstliche Sperre, könnte legitime Use-Cases blockieren (Team-Reorg innerhalb eines Tages).

**Empfehlung**: B — Audit-Event plus Inbox-Notification. Begründung: FR-TEAM-5 ist explizit über Gleichberechtigung — eine Voting-Mechanik widerspricht dem Geist. Audit plus Notification ist das Minimum, das soziale Kontrolle ermöglicht ohne Recht-Asymmetrie einzuführen. C wäre eigenes Feature und sollte erst kommen wenn der Bedarf empirisch belegt ist.

**Marker**: `[committee]` (UX-Bewertung), `[owner]` (Policy-Entscheidung, weil das die Mass-Adoption-Story berührt).

**Resolution**: Resolved 2026-05-26 — Architect-Empfehlung übernommen. Option B per ADR-0018 (Accepted). Audit-Event plus Inbox-Notification an alle aktiven Pool-Mitglieder bei kritischen Aktionen (Removal, Edit, Dissolve). FR-TEAM-5 Gleichberechtigung bleibt intakt, soziale Kontrolle via Transparenz. Begründung siehe ADR-0018 §Mitgliedschafts-Lifecycle.

## OD-M3-02: Roster-Eingabe — wie viele Slots maximal? `[resolved]`

**Frage**: `tournaments.team_size` ist heute `BETWEEN 1 AND 6` (M1-Schema). Welche Werte unterstützen wir aktiv für M3 — und damit, wie viele Roster-Slots können vorkommen?

**Warum blockierend**: Beeinflusst UI-Layout (Roster-Composition-Widget muss responsive für 2..6 Slots sein), CHECK-Constraint auf `tournament_roster_slots.slot_index`, Bracket-Layout (sehr breite Roster lassen Bracket-Boxen unleserlich werden).

**Optionen**:
- **A) 2v2, 3v3** — Schweizer Standard-Kubb. Wenig UI-Aufwand.
  - Pros: deckt 95% der Schweizer Turniere.
  - Cons: Liga-Vorgabe in einigen Kantonen ist 6v6 (Vereins-Liga).
- **B) 2v2, 3v3, 4v4, 5v5, 6v6** — alle vom Schema zugelassenen Grössen.
  - Pros: kein Use-Case ausgeschlossen.
  - Cons: 6 Roster-Slots auf 360px-Mobile-Screen — designerischer Mehraufwand.
- **C) Konfigurierbar per Turnier ohne harte Liste** — das CHECK-Constraint bleibt (1..6), und die UI rendert dynamisch.
  - Pros: keine Code-Änderung wenn Liga 4v4 ergänzt.
  - Cons: gleicher UI-Aufwand wie B.

**Empfehlung**: B — die Liste {2, 3, 4, 5, 6} im Wizard explizit anbieten, UI muss bis 6 Slots responsive bleiben. CHECK-Constraint passt schon. Begründung: das Schema lässt es bereits zu, die UI für 6 Slots ist machbar (vertikal scrollbar mit dichten Rows). Spec FR-CFG-1 spricht von "Teamgrösse 1, 2, 3, 4, 5, 6" — wir setzen das 1:1 um.

**Marker**: `[domain]` (Kubb-Realität), `[owner]` (Zielgruppen-Frage).

**Resolution**: Resolved 2026-05-26 — Architect-Empfehlung übernommen. Option B per ADR-0018 (Accepted). Wizard bietet {2, 3, 4, 5, 6} als Auswahlliste. Schema-CHECK `team_size BETWEEN 1 AND 6` aus M1 bleibt unverändert. UI muss bis 6 Roster-Slots responsive bleiben (Mobile 360px scrollbar). Begründung siehe ADR-0018 §Datenmodell.

## OD-M3-03: Cross-Pool-Tiebreaker — Schwierigkeitsgrad pro Pool berücksichtigen? `[resolved]`

**Frage**: Wenn beim Pool-Cut zwei Top-Qualifier aus verschiedenen Gruppen punkte-gleich sind — wie ranken wir sie für das KO-Seeding?

**Warum blockierend**: Beeinflusst `pool_cut.dart`-Algorithmus und `_tournament_compute_pool_cut`-Helper.

**Optionen**:
- **A) Cross-Pool-Tiebreaker mit gemeinsamer `TiebreakerChain`** — alle Top-Qualifier werden in eine Liste geworfen und nach der bestehenden Tiebreaker-Chain sortiert (`total_points`, `buchholz_minus_h2h`, `direct_comparison`, `wins`).
  - Pros: konsistent mit M1-Logik, kein neuer Code.
  - Cons: Buchholz innerhalb einer Gruppe vergleicht Gegner unterschiedlicher Stärke — Pool A kann schwächer sein als Pool B. Direkter Vergleich gibt es nicht zwischen Pools.
- **B) Pool-Stärke-Normalisierung** — Score wird durch eine Pool-Stärke geteilt (z.B. durchschnittliche Punkte des Pools). Höhere Pool-Stärke ergibt mehr Wert pro Sieg.
  - Pros: mathematisch fair.
  - Cons: deutlich komplexer, schwer erklärbar gegenüber Veranstaltern.
- **C) Schweizer-Pattern** — bei Punktegleichheit explizit das Sets-Verhältnis-Differenz, dann Basekubb-Differenz, dann Buchholz. Bewusst KEIN direkter Vergleich (existiert nicht Cross-Pool).
  - Pros: deterministisch, in Schweizer Turnier-Praxis verbreitet.
  - Cons: hartcodierte Reihenfolge anders als M1-Tiebreaker-Chain.

**Empfehlung**: A mit angepasster Reihenfolge — beim Cross-Pool-Cut wird die bestehende `TiebreakerChain` verwendet, aber `direct_comparison` wird übersprungen (Cross-Pool nicht definiert). Wenn der Veranstalter `direct_comparison` als Kriterium hat, fällt es Cross-Pool automatisch aus dem Vergleich raus (gleich für alle = keine Sortierung).

**Marker**: `[domain]` (Kubb-Realität — sollte mit `/kubb-knowledge` validiert werden).

**Resolution**: Resolved 2026-05-26 — Architect-Empfehlung übernommen. Option A mit Anpassung per ADR-0019 (Accepted). Bestehende `TiebreakerChain` wird Cross-Pool wiederverwendet, `direct_comparison` wird automatisch übersprungen (Cross-Pool nicht definiert, gleich für alle). Begründung siehe ADR-0019 §Cross-Pool-Tiebreaker.

## OD-M3-04: Reservespieler im Roster? `[resolved]`

**Frage**: Soll das Roster zwischen "aktiv für aktuelles Match" und "Reserve" unterscheiden? Spec-Open-Point 2 (§7.1).

**Warum blockierend**: Beeinflusst Datenmodell von `tournament_roster_slots` und UI-Design von Roster-Editor.

**Optionen**:
- **A) Kein Reserve-Konzept** — das Roster hat genau `team_size` Slots. Mid-Tournament-Substitution macht den Wechsel. Reserve ist ein impliziter Pool-Mitglied-Status ("alle nicht-im-Roster sind potenzielle Ersatzspieler").
  - Pros: einfacher, Spec FR-TEAM-16 KANN-Erweiterung kann später kommen.
  - Cons: pro Match kein Snapshot "wer hat tatsächlich gespielt".
- **B) Roster mit aktiven plus Reserve-Slots** — `tournament_roster_slots` bekommt `role text CHECK ('active','reserve')`. Pre-Match wählt das Team aus.
  - Pros: bildet die Realität ab (Reserve sitzt auf der Bank).
  - Cons: zusätzliche UI ("Match-Lineup wählen"), pro Match eine Aktion mehr.
- **C) Per-Match-Active-Snapshot** — `tournament_match_lineups`-Tabelle, pro Match wird festgehalten welche Roster-Slots tatsächlich gespielt haben. Default: alle Slots = aktiv.
  - Pros: vollständiger Audit-Trail, ohne UI-Aufwand wenn Default passt.
  - Cons: zusätzliche Tabelle plus RPC.

**Empfehlung**: A für M3, C als M5+ Vorhaben. Begründung: Schweizer Kubb-Praxis spielt selten mit echtem Reserve-Konzept. FR-TEAM-16 ist explizit KANN. Wenn Owner nach Pilot-Phase einen Use-Case sieht, kann C nachträglich kommen ohne Migration der bestehenden Daten.

**Marker**: `[committee]` (UX-Komplexität), `[owner]` (Roadmap-Priorisierung).

**Resolution**: Resolved 2026-05-26 — Architect-Empfehlung übernommen. Option A für M3 per ADR-0018 und ADR-0020 (Accepted). Kein Reserve-Konzept im M3-Datenmodell — Roster hat genau `team_size` Slots. `tournament_match_lineups` (Variante C) wird als M5+ Folge-Ticket erfasst. Begründung siehe ADR-0020 §Alternatives C.

## OD-M3-05: Pool-Cut bei Punktegleichheit nach Pool-Tiebreaker — wer rückt nach? `[resolved]`

**Frage**: Pool hat 4 Teams, Top-2 qualifizieren. Platz 2 und 3 sind nach allen Tiebreakern identisch — was passiert?

**Warum blockierend**: Beeinflusst `pool_cut.dart` und Server-RPC-Verhalten.

**Optionen**:
- **A) Coin-Flip / Random** — bei vollständigem Tie wird zufällig gewählt, Audit-Event vermerkt das.
  - Pros: deterministisch (Random mit Tournament-Seed als Salt), funktioniert immer.
  - Cons: kein Spieler ist mit Zufallsentscheidung happy. Spec sagt nirgendwo "Random".
- **B) Veranstalter-Override** — RPC wirft `TIEBREAKER_NEEDS_RESOLUTION`. Frontend zeigt Veranstalter einen Dialog "Entscheide manuell".
  - Pros: Mensch entscheidet, klare Verantwortlichkeit.
  - Cons: blockiert KO-Start.
- **C) Stichkampf** — eigenes Match wird generiert ("Pool A: Tie-Break X vs. Y"). Ergebnis entscheidet.
  - Pros: sportliche Lösung.
  - Cons: zusätzlicher Match-Pfad, Logistik.

**Empfehlung**: B — Veranstalter-Override mit klarer UI. Begründung: in der Praxis ist vollständiger Tie nach 7 Tiebreaker-Kriterien extrem selten (besonders mit EKC-Score-System mit feiner Basekubb-Granularität). Wenn er auftritt, ist eine bewusste Entscheidung ehrlicher als Zufall. Stichkampf-Pfad (C) ist Aufwand für einen Edge-Case der vielleicht 1x pro 100 Turniere vorkommt.

**Marker**: `[domain]` (Schweizer Praxis sollte abgefragt werden), `[committee]` (UX-Frage zur Veranstalter-Eskalation).

**Resolution**: Resolved 2026-05-26 — Architect-Empfehlung übernommen. Option B per ADR-0019 (Accepted). RPC `_tournament_compute_pool_cut` wirft `TIEBREAKER_NEEDS_RESOLUTION` (ERRCODE 40001) bei vollständigem Tie nach Cross-Pool-Chain, Frontend zeigt Veranstalter-Eskalations-Dialog. Manuelle Entscheidung schreibt `tournament_seeding_overrides`-Eintrag. Kein Coin-Flip, kein automatischer Stichkampf. Begründung siehe ADR-0019 §Vollständiger Tie.

## OD-M3-06: Team-Sieg-Punkte — pro Set oder pro Match? `[resolved]`

**Frage**: Wenn Team A 2:0 gegen Team B gewinnt — was zählt für die Team-Standings? Match-Sieg gibt z.B. 3 Punkte, oder Set-Siege zählen separat?

**Warum blockierend**: Beeinflusst `standings.dart` plus die Wizard-Konfiguration.

**Optionen**:
- **A) Match-Sieg-Punkte** — analog M1: 3 Punkte für Match-Sieg, 1 für Unentschieden, 0 für Niederlage. EKC-Score (Basekubb-Differenz) als Tiebreaker.
  - Pros: konsistent mit M1, einfach.
  - Cons: Best-of-3 vs. Best-of-5 wird im Tiebreaker nur schwach differenziert.
- **B) Set-Sieg-Punkte** — pro gewonnenem Set 1 Punkt. Match 2:1 = 2 Punkte für Sieger, 1 für Verlierer. Match 2:0 = 2:0.
  - Pros: Set-Performance wird belohnt, knappere Differenz zwischen 2:0 und 2:1.
  - Cons: ändert Konzept von M1.
- **C) Konfigurierbar pro Turnier** — Wizard-Feld "Punkteformel".
  - Pros: Flexibilität.
  - Cons: mehr UI plus Tests.

**Empfehlung**: A — bleibt bei Match-Sieg-Punkten. Begründung: M1 hat das verdrahtet, Tournament-Foundation-Plan §M1 Akzeptanz-Kriterium sagt "Match-Status finalized → Rangliste aktualisiert". Konsistenz schlägt Flexibilität in M3. Wenn Liga-Reglemente in M5 etwas anderes erzwingen, kommt C im Liga-Block.

**Marker**: `[domain]` (Schweizer Liga-Realität), `[owner]` (Roadmap).

**Resolution**: Resolved 2026-05-26 — Architect-Empfehlung übernommen. Option A per ADR-0018 (Accepted). Match-Sieg-Punkte (3 / 1 / 0) konsistent zu M1, Set-Tiebreaker bleibt EKC-Score (Basekubb-Differenz). Konfigurierbarkeit (Option C) wird als M5+ Liga-Folgeticket erfasst, wenn Liga-Reglemente das erzwingen. Begründung siehe ADR-0018 §Decision.

## OD-M3-07: Substitution während laufendem Match? `[resolved]`

**Frage**: Spec FR-TEAM-13: "Roster anpassen während des Turniers". Ist das während eines laufenden Matches möglich, oder nur zwischen Matches?

**Warum blockierend**: Beeinflusst Server-Validierung in `tournament_roster_replace` (M3.2-T2).

**Optionen**:
- **A) Nur zwischen Matches** — Replace ist nur erlaubt wenn das Team-Participant keine aktive `tournament_matches.status='awaiting_results'`-Row hat.
  - Pros: klare Match-Integrität. Wer spielt, spielt das Match zu Ende.
  - Cons: bei akuter Verletzung mitten im Set ist das hart.
- **B) Pro Set erlaubt** — Replace zwischen Sets eines Best-of-3-Matches möglich. Im laufenden Set nicht.
  - Pros: realistisch — Verletzung passiert, Set wird mit aktuellem Spieler beendet (oder forfeitet), nächstes Set mit Ersatz.
  - Cons: muss "Set ist aktuell offen / abgeschlossen" tracken — aktuell trackt Score-Spec das pro Set-Proposal, aber kein expliziter Set-State auf Match-Ebene.
- **C) Jederzeit erlaubt** — auch mitten im Set Substitution möglich.
  - Pros: maximale Flexibilität.
  - Cons: Score-Eingabe-Konsistenz — wer hat den Wurf im Set gemacht? Tracking pro Wurf gibt es nicht (per ADR-0014 + OD-08 aus M1).

**Empfehlung**: A für M3, B als M4 oder M5 Erweiterung. Begründung: Set-Tracking-Layer würde Score-Spec-Anpassung erfordern, das ist M3-Out-of-Scope. Match-Boundary ist eine klare Grenze. Bei wirklicher Verletzung mid-Match: Match wird per `voided` oder Forfeit-Pfad behandelt (M4 Erweiterung), Ersatz kommt im nächsten Match.

**Marker**: `[domain]` (Schweizer Praxis — Schiedsrichter-Regel).

**Resolution**: Resolved 2026-05-26 — Architect-Empfehlung übernommen. Option A für M3 per ADR-0020 (Accepted). Substitution nur zwischen Matches erlaubt — RPC `tournament_roster_replace` wirft `MATCH_IN_PROGRESS` wenn das Team-Participant ein Match mit Status `awaiting_results` hat. Pro-Set-Substitution (Option B) bleibt M4+ Erweiterung. Begründung siehe ADR-0020 §Mid-Tournament-Substitution.

---

## Übersicht der ODs nach Marker

| ID | `[committee]` | `[owner]` | `[domain]` | `[resolved]` | Blockt |
|---|---|---|---|---|---|
| OD-M3-01 | ja | ja | — | ja | M3.1-T2 |
| OD-M3-02 | — | ja | ja | ja | M3.2-T7 |
| OD-M3-03 | — | — | ja | ja | M3.3-T4 |
| OD-M3-04 | ja | ja | — | ja | M3.2-T1 (Schema-Frage) |
| OD-M3-05 | ja | — | ja | ja | M3.3-T4, M3.3-T6 |
| OD-M3-06 | — | ja | ja | ja | M3.1-T1 (Punkteformel-Speicherung), M3.2 |
| OD-M3-07 | — | — | ja | ja | M3.2-T2 |

Zählung: 7 ODs gesamt — alle 7 resolved 2026-05-26 per Architect-Empfehlung. Implementation kann starten.

## Entscheidungs-Reihenfolge — erledigt

Alle 7 ODs sind am 2026-05-26 per Architect-Empfehlung resolved. Die ursprünglich vorgeschlagene Sequenz ist obsolet — M3.1, M3.2 und M3.3 sind parallel entblockt.

Die Architect-Empfehlungen sind in den drei zugehörigen ADRs verankert:

- **ADR-0018** (Team-Modell, Accepted): OD-M3-01, OD-M3-02, OD-M3-04, OD-M3-06.
- **ADR-0019** (Pool-Phase-Algorithmus, Accepted): OD-M3-03, OD-M3-05.
- **ADR-0020** (Roster-Substitution-Regeln, Accepted): OD-M3-04, OD-M3-07.

Implementations-Start nach M4-Erteilung möglich.

## Was die ODs explizit NICHT entscheiden

- **Logo-Upload** — File-Storage-Strategie. Bleibt URL-Feld. Avatar-Pipeline M5+.
- **Vereine** (FR-CLUB) — eigener Milestone. `home_club_id` ist FK-Stub, mehr nicht.
- **Liga-Wechsel-Mechanik** — `league_membership` ist Init-only. M5.
- **Team-Statistiken im öffentlichen Profil** (FR-PUB-9 vollständig) — eigener Stats-Block, OD-03 aus Tournament-Foundation.
- **Realtime für Pool-Standings** — bleibt Polling, kommt M4.
