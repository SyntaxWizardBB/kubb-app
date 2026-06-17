# KubbMAIster-Topologie — Referenz für den Stufen-Graph

> Referenz-Setup für mehrkantige Stufen-Graphen (ADR-0033 P3.3). Zeigt, wie die
> „mehrere Cups, gespeist aus Verlierern früher Runden"-Struktur (Foto vom
> KubbMAIster-Turnier) mit den bestehenden Bausteinen (StageNode/StageEdge/
> EdgeSelector) modelliert wird — **ohne** neue Engine-Features.

## Das Bild

Ein grosses Feld spielt eine Vorrunde (Gruppen). Die Besten ziehen in ein
**Haupt-Bracket** (K.-o.). Wer im Haupt-Bracket **früh** ausscheidet, ist nicht
raus, sondern fällt in einen **Neben-Cup** (Trost-/B-/C-Turnier). So laufen
mehrere Endrunden parallel — jedes Team spielt bis zum Schluss um etwas.

```
                         ┌────────────── Haupt-Cup (single_elim) ── Sieger
  Gruppen (pool) ── TopK ┤
                         └─ Übrige ─────  … (siehe unten)

  Haupt-Cup ── LosersOfRounds{1}   ──►  B-Cup  (consolation)
  Haupt-Cup ── LosersOfRounds{2,3} ──►  C-Cup  (consolation)
```

Der Kern: **eine Stufe darf mehrere ausgehende Kanten haben.** Der Haupt-Cup
speist sich selbst *und* zwei Neben-Cups, je nach dem, in welcher Runde ein Team
verloren hat.

## Modellierung mit den vorhandenen Bausteinen

| Element | Baustein | Config |
|---|---|---|
| Vorrunde | `StageNode(type: pool)` | `groupCount`, `qualifierCount` (pro Gruppe!) |
| Haupt-Bracket | `StageNode(type: singleElim)` | — (Bracket aus Setzliste) |
| Neben-Cup B/C | `StageNode(type: consolation)` | — |
| „Beste K jeder Gruppe → Haupt" | `StageEdge` + `TopK(k)` | k = Qualifikanten pro Gruppe |
| „Verlierer Runde 1 → B-Cup" | `StageEdge` + `LosersOfRounds({1})` | — |
| „Verlierer Runde 2+3 → C-Cup" | `StageEdge` + `LosersOfRounds({2, 3})` | — |

### Selektoren (welche Teilnehmer eine Kante weiterleitet)

- **TopK** — die besten *K* jeder Quell-Stufe (Top 2 *pro Gruppe*, nicht gesamt).
- **Ranks(from, to)** — ein Rangbereich (z. B. Ränge 3–4 in ein zweites Tableau).
- **LosersOfRounds({…})** — die Verlierer bestimmter K.-o.-Runden. **Das ist der
  Side-Cup-Feed**: `{1}` = nur Erstrunden-Verlierer, `{2,3}` = wer in Runde 2
  oder 3 rausfliegt.
- **Winners** — alle Sieger der Quell-Stufe.
- **NonQualifiers** — alle, die sich NICHT qualifiziert haben (z. B. der Rest der
  Vorrunde in einen Plausch-Cup).

## Editor-Bedienung

- Im Stufen-Graph-Editor pro Neben-Cup einen Knoten anlegen (`consolation`).
- Vom Haupt-Bracket je eine Kante mit Selektor **„Verlierer Runden"** ziehen und
  die Runden kommagetrennt eintragen (`1` bzw. `2,3`).
- Mehrere Kanten ab derselben Stufe sind erlaubt und gewollt — der Hinweis in der
  Kanten-Sektion weist darauf hin.
- Auf Desktop (macOS/Windows/Linux/Web, ≥ 720 dp) steht zusätzlich die visuelle
  Canvas-Ansicht zur Verfügung; mobil die geführte Formular-Ansicht (ADR-0033 P4).

## Engine-Hinweis

Die Stufen-Engine (`tournament_generate_stage_matches`,
`tournament_route_completed_stage`) liest aus der Knoten-`config` nur das, was sie
wirklich braucht: bei `double_elim` das Flag `with_reset`. Gruppen-/Qualifikanten-
Zahl steuern **Routing/Kanten**, nicht den Generator (eine pool-Stufe erzeugt eine
Gruppe; mehrere Gruppen entstehen über mehrere pool-Knoten bzw. die Kanten-Logik).
Match-Format/Tiebreak kommen aus den Turnier-Vorrunde-/KO-Einstellungen, nicht
pro Knoten.
