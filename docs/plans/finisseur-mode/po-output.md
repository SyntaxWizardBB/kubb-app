# PO-Output — F4 Finisseur

## User Stories

### S1 — Konfig wählen (MUST)
Als Trainer möchte ich Anzahl Feldkubbs und Basiskubbs für die Endsituation wählen, damit ich verschiedene Match-Endspiele üben kann.

```
Given ich öffne den Finisseur-Konfig-Screen
When  ich Feldkubbs auf 7 und Basiskubbs auf 3 stelle
Then  zeigt die Visual-Preview 7 Feldkubbs und 3 Basiskubbs
And   der Start-Button startet eine Session mit field=7, base=3
```

### S2 — Constraint-Logik (MUST)
Als Trainer möchte ich, dass ungültige Kombinationen automatisch verhindert werden, damit ich keine unmöglichen Setups starte.

```
Given Feldkubbs steht auf 8 und Basiskubbs auf 2
When  ich Feldkubbs auf 9 erhöhe
Then  bleiben Feldkubbs bei 9 und Basiskubbs werden auf 1 reduziert
And   die Constraint-Note zeigt "10 / 10"
```

### S3 — Preset wählen (MUST)
```
Given ich sehe die vier Built-in Presets (Standard 7/3, 5/5, 10/0, Spät 3/5)
When  ich auf "5/5" tippe
Then  springt die Konfig auf field=5, base=5
And   das gewählte Preset ist visuell hervorgehoben
```

### S4 — Stock-Eingabe (MUST)
Als Trainer möchte ich pro Stock erfassen können, was passiert ist, damit der Verlauf der Endsituation sauber dokumentiert ist.

```
Given eine laufende Session mit field=7, base=3, ich bin bei Stock 1
When  ich "2 Feldkubbs umgeworfen" auswähle und auf "Stock 2" tippe
Then  zeigt der Pip-Progress Stock 1 als "done", Remaining = 5 Feldkubbs
And   bin ich auf Stock 2
```

### S5 — Helikopter (MUST)
```
Given Stock 3 ist aktiv
When  ich Helikopter aktiviere
Then  werden andere Eingaben (Field, 8m, King) für diesen Stock disabled
And   der Stock zählt als verbraucht ohne Treffer
```

### S6 — Königswurf am Ende (MUST)
```
Given alle Feld- und Basiskubbs sind down (oder Stock 6 ist aktiv)
When  Königswurf-Toggle erscheint und ich ihn aktiviere
Then  kann ich Position (oben/unten) und Outcome (Treffer/verfehlt) wählen
```

### S7 — Strafkubb-Eingabe (SHOULD)
```
Given Stock 1 ist aktiv und base > 0
When  ich Strafkubb-Wurf 1× auf 2 setze
Then  reduziert sich der Max-Wert für Wurf 2× auf (base − 2)
And   die Summe Strafkubbs ≤ base
```

### S8 — Erfolgs-Berechnung (MUST)
```
Given alle Feldkubbs + Basiskubbs umgeworfen + König getroffen vor Stock-Verbrauch
When  Session abgeschlossen
Then  zeigt Summary "Sauber finished" mit Sticks-Used-Count
```

### S9 — Persistenz (MUST)
```
Given eine laufende Session mit erfassten Stock-Daten
When  ich Session abschliesse
Then  ist die Session und alle Stock-Events in drift persistent
```

### S10 — Navigation aus TrainingSheet (MUST)
```
Given ich öffne das TrainingSheet auf der Home-Page
When  ich auf die Finisseur-Karte tippe
Then  öffnet sich der Finisseur-Konfig-Screen (kein Toast mehr)
```

## Nicht-funktional
- **Performance**: 1-Tap auf Field-Chips, Toggles. Reaktion < 100ms.
- **Offline**: vollständig — keine Cloud-Abhängigkeit.
- **i18n**: alle neuen Strings via AppLocalizations.

## MoSCoW
| Story | Prio |
|---|---|
| S1, S2, S3, S4, S5, S6, S8, S9, S10 | MUST |
| S7 (Strafkubb) | SHOULD — wichtig für Realismus, aber nicht App-blockend |
