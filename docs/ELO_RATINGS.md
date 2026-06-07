# ELO-Rating-System — Spezifikation (System 2)

- **Stand**: 2026-06-07
- **Status**: Verbindliche Spec. Modell mit Owner entschieden 2026-06-07.
- **Zweck**: Fortlaufendes Spielstärke-Rating pro Spieler. Zwei getrennte
  Disziplinen: ein **öffentlicher Turnier-ELO** (treibt das Seeding, erscheint in
  Profil + Bestenliste) und ein **privater persönlicher ELO** (kombiniert Turnier
  + 1vs1, nur im eigenen Profil).
- **Abgrenzung**: Dies ist **NICHT** die Tour-/Saison-Punktewertung (→
  `docs/SKV_TOUR_POINTS.md`, System 1). ELO ist erwartungswert-basiert,
  Match-für-Match, feldgrössen-unabhängig — eine andere Mathematik mit anderem
  Zweck.

## Quellenlage / Ausgangsbasis

Vieles existiert bereits und ist **scharf**:
- Store `public.player_ratings(user_id, discipline, elo, games)`, Default 1200,
  öffentlich lesbar, schon multi-disziplin-fähig (`discipline`-Spalte;
  `20261201000001`).
- Turnier-Writer-Trigger `tournament_write_match_elo` auf `tournament_matches`
  (`20261201000004`): Standard-ELO K=24, feuert bei jedem `finalized`/`overridden`
  mit Sieger, über alle Formate. Team = Summe aktiver Mitglieder-ELO, gleiches
  Delta an jedes Mitglied; Gäste unbewertet.
- Seeding-Konsument `tournament_autoseed_from_elo` (`20261201000002`) +
  `elo_seeding.dart`.

Diese Spec **erweitert** das auf zwei Disziplinen + Sichtbarkeit + Provisorium.

> CLAUDE.md-Bezug: Der **1vs1-Match-Modus** (`public.matches`) ist ausdrücklich
> **nicht** Teil der Trainings-Sperre und darf bewertet werden. Das **Solo-
> Training** (Finisseur/Sniper) bleibt eingefroren und speist **nie** ein ELO.

## 1. Zwei Disziplinen

| | **Turnier-ELO** | **Persönlicher ELO** |
|---|---|---|
| `discipline` | `tournament` | `personal` |
| Quelle | nur Turnier-Matches | Turnier-Matches **und** 1vs1-Matches |
| Sichtbarkeit | **öffentlich** (eigenes + fremde Profile, Bestenliste) | **privat** (nur eigenes Profil) |
| Treibt Seeding | **ja** | nein |
| Bestenliste | ja (global) | nein |

„Kombiniert" = die `personal`-Disziplin **akkumuliert aus beiden Quellen** in
einer fortlaufenden Zahl (nicht: ein Blend aus zwei separaten Werten).

## 2. Quellen-Matrix (welcher Match-Typ schreibt welche Disziplin)

| Match-Typ | schreibt `tournament` | schreibt `personal` |
|---|---|---|
| Turnier-Match (`tournament_matches`, finalized/overridden + Sieger) | ✅ | ✅ |
| 1vs1-Match (`public.matches`, finalized + `winner_team_id`) | ❌ | ✅ |
| Solo-Training | ❌ | ❌ |

Umsetzung: der bestehende Turnier-Trigger schreibt künftig in **beide**
Disziplinen; ein **neuer** Trigger auf `public.matches` schreibt **nur** `personal`.

## 3. ELO-Formel

Standard-ELO, ganzzahlig, Startwert **1200** (`_elo_default`):

```
ratingW = Σ ELO der bewertbaren Mitglieder der Sieger-Seite (Default 1200)
ratingL = Σ ELO der bewertbaren Mitglieder der Verlierer-Seite
expectedW = 1 / (1 + 10^((ratingL − ratingW) / 400))

für jedes bewertbare Mitglied m der Sieger-Seite:  elo_m += round(K(m) × (1 − expectedW))
für jedes bewertbare Mitglied m der Verlierer-Seite: elo_m -= round(K(m) × (1 − expectedW))
games_m += 1   (pro Mitglied, pro Match)
elo_m = max(0, elo_m)
```

- **Seiten-Aggregat = Summe** der Mitglieder-ELO (deckungsgleich mit
  Seeding/§I). Solo = 1-Mann-Seite.
- Erwartungswert ist skaleninvariant in der Rating-**Differenz** → Summe beider
  Seiten ist äquivalent zum Mittel für den Erwartungsterm; die Seitengrösse zählt
  nur, wenn die Seiten ungleich gross sind (dann bevorzugt die Summe korrekt die
  grössere Roster).

### Provisorium / dynamisches K

```
K(m) = 40   wenn games_m < 10   (provisorisch)
     = 24   sonst
```

- `games_m` ist der **disziplin-eigene** Zähler (Turnier- und persönlicher ELO
  zählen Spiele getrennt). Neue Spieler pendeln sich in den ersten ~10 Spielen
  schneller ein.
- Folge: pro Match kann das Delta je Mitglied unterschiedlich sein (verschiedene
  K), d.h. ein Match ist mit Provisorium **nicht mehr strikt nullsummig** — das
  ist Standard für ELO-Systeme mit Anlauf-K und so beabsichtigt.

## 4. Team- / Gast-Behandlung

- Eine Seite (A/B) kann ein Team sein (Turnier-Roster bzw. `match_teams`).
- **Bewertbare Mitglieder**: Turnier = aktive Roster-Mitglieder mit `user_id`;
  1vs1 = `match_participants` mit `kind='in_app'`, `user_id`, akzeptiert.
- **Gäste / Walk-ins** (kein `user_id`) tragen **kein** ELO und werden nicht
  aktualisiert. Eine reine Gast-Seite trägt den neutralen Default zum
  Erwartungsterm bei.

## 5. Sichtbarkeit / RLS

- `discipline='tournament'`: **öffentlich lesbar** (Profil, fremde Profile,
  Bestenliste, Seeding) — wie heute.
- `discipline='personal'`: **nur vom Besitzer lesbar** (`user_id = auth.uid()`).
- Die RLS-SELECT-Policy muss daher **disziplin-abhängig** filtern (heute ist
  `player_ratings` pauschal öffentlich → anpassen). Schreiben weiterhin nur via
  SECURITY-DEFINER-Trigger (keine Client-Write-Policy).

## 6. Launch-Verhalten (kein Backfill)

- **Keine** rückwirkende Nachberechnung historischer Matches. ELO zählt ab
  Einführung.
- Bestehende `discipline='overall'`-Zeilen (vom heutigen Writer erzeugt) werden
  per einmaliger Migration auf `discipline='tournament'` **umbenannt** (kein
  Replay, nur Beibehaltung des bereits Getriggerten). `personal` startet leer
  (Spieler erscheinen mit erstem gewertetem Match, sonst Default 1200).

## 7. Bestenliste (Turnier-ELO)

- **Global**, eine Liste über **Spieler** (nie Teams).
- **Alle sofort sichtbar**: jeder mit ≥1 gewertetem Spiel (`games ≥ 1`) erscheint.
  Kein Mindestspiele-Filter.
- **Provisorisch-Badge**: Spieler mit `games < 10` werden als „provisorisch"
  markiert (transparent, aber nicht ausgeblendet).
- Sortierung: `elo` desc → `games` desc → `nickname` asc.
- Lese-RPC analog `tournament_ranking_get` (öffentlich, SECURITY DEFINER), liest
  `discipline='tournament'`.

## 8. Profil-Anzeige

- **Eigenes Profil**: beide Zahlen — Turnier-ELO (öffentlich) **und** persönlicher
  ELO (privat, nur hier), je mit Spielzahl + ggf. Provisorisch-Hinweis.
- **Fremde Profile**: **nur** Turnier-ELO. Persönlicher ELO erscheint nie bei
  anderen.

## 9. Seeding

- `tournament_autoseed_from_elo` liest künftig `discipline='tournament'`
  (heute `'overall'` → nach der Umbenennung deckungsgleich). Aggregation, No-
  History-ans-Ende-Sortierung und `elo_seeding.dart` bleiben unverändert
  (P6_RULES_DECISIONS §I).

## 10. Sonstiges

- **Kein Decay**, keine Inaktivitäts-Anpassung.
- ELO ist immer **pro User**; Teams haben kein eigenes ELO (Team-Stärke = Summe
  der Mitglieder, nur fürs Seeding).

## 11. Mapping auf den Code (was sich ändert)

- `tournament_write_match_elo` (`20261201000004`): schreibt statt `'overall'`
  künftig **`'tournament'` UND `'personal'`**; K via `games`-abhängigem
  Provisorium statt fix 24.
- **Neu**: Trigger `match_write_personal_elo` auf `public.matches` (AFTER UPDATE,
  `status → 'finalized'` mit `winner_team_id`), schreibt nur `'personal'`.
- **Neu**: Migration `discipline 'overall' → 'tournament'` (Rename bestehender
  Zeilen).
- RLS auf `player_ratings`: disziplin-abhängige SELECT-Policy.
- **Neu**: Bestenliste-RPC + Screen; Profil-Erweiterung (zwei Zahlen, privat/
  öffentlich getrennt).
- `_elo_k()` → durch games-abhängige K-Wahl ersetzt (oder zweite Konstante
  `_elo_k_provisional()` + Schwelle `_elo_provisional_games()`).

## 12. Offene / nachgelagerte Punkte

1. **Provisorisch-Schwelle (10) und K (40/24)** sind erste Werte — nach echten
   Daten ggf. justieren.
2. **1vs1 walk-in-only-Matches** (beide Seiten ohne `user_id`) erzeugen keinen
   ELO-Effekt — bewusst.
3. **Bestenliste-Performance**: Index `(discipline, elo DESC)` existiert schon
   (`20261201000001`).
4. **Persönlicher-ELO-Verlauf/History** (Chart) ist nicht Teil von v1.

> Fundament für System 2. Unabhängig von System 1 (Punkte) und System 3
> (Format-Framework) baubar.
