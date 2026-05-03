# Product-Owner-Output: Stats Screen (F3)

## Stories

### S1 (MUST) — Aggregate-Übersicht

Als Trainer möchte ich beim Öffnen des Stats-Screens auf einen Blick meine Trefferrate, Anzahl Sessions, Total Würfe und längste Streak sehen, damit ich sofort eine Standortbestimmung habe.

**Akzeptanz:**

```
Given mindestens eine completed Session existiert
When  ich `/stats` öffne
Then  sehe ich oben Trefferrate (gross, %), Total Würfe, Total Sessions, längste Streak
And   alle Werte beziehen sich auf den aktuell aktiven Filter
```

### S2 (MUST) — Trend-Chart

Als Trainer möchte ich meinen Trefferraten-Verlauf der letzten Sessions als Linien-Chart sehen, damit ich Fortschritt visualisieren kann.

**Akzeptanz:**

```
Given mindestens 2 completed Sessions existieren
When  ich `/stats` öffne
Then  sehe ich einen LineChart mit X = Session-Index (chronologisch), Y = Hit-Rate %
And   der letzte Punkt ist optisch hervorgehoben
Given 0 Sessions existieren
When  ich `/stats` öffne
Then  sehe ich einen Empty-State-Hinweis statt eines leeren Charts
```

### S3 (MUST) — Filter

Als Trainer möchte ich nach Distanz und Datums-Range filtern, damit ich gezielt Teilbereiche analysieren kann.

**Akzeptanz:**

```
Given Sessions mit verschiedenen Distanzen und Daten existieren
When  ich Filter "Distanz: 8.0m" setze
Then  reagieren Aggregate, Chart und Session-Liste auf den Filter
When  ich Filter "letzte 7 Tage" setze
Then  werden nur Sessions der letzten 7 Tage gezählt
```

### S4 (SHOULD) — Personal Bests

Als Trainer möchte ich meine Personal Bests (höchste Hit-Rate mit Distanz, längste Hit-Streak, meiste Würfe an einem Tag) sehen, damit ich Bestmarken kenne.

**Akzeptanz:**

```
Given mindestens eine completed Session existiert
When  ich `/stats` öffne
Then  sehe ich einen "Bestmarken"-Block mit den drei Werten
And   bei 0 Sessions ist der Block ausgeblendet
```

### S5 (MUST) — Session-Liste

Als Trainer möchte ich eine scrollbare Liste meiner letzten Sessions (max 20) sehen, damit ich Detail-Übersicht habe.

**Akzeptanz:**

```
Given >0 Sessions existieren
When  ich nach unten scrolle
Then  sehe ich pro Zeile: Datum, Modus, Distanz, Trefferrate, Würfe
When  ich auf eine Zeile tippe
Then  öffnet sich der bestehende SummaryScreen für diese Session
```

### S6 (SHOULD) — Navigation

Als Nutzer möchte ich vom HomeScreen aus den Stats-Screen erreichen, damit der Zugang offensichtlich ist.

**Akzeptanz:**

```
Given ich bin auf `/`
When  ich das Hamburger-Menü öffne und "Statistik" tippe
Then  navigiere ich zu `/stats`
And   das Modal schliesst sich
```

## MoSCoW

| Story | Stufe |
|---|---|
| S1 Aggregate | MUST |
| S2 Trend-Chart | MUST |
| S3 Filter | MUST |
| S4 Personal Bests | SHOULD |
| S5 Session-Liste | MUST |
| S6 Navigation | SHOULD |

## Offene Fragen

- Keine. Hit-Rate-Konvention bereits in `recent_sessions_provider` etabliert (`hits / (hits+misses)`, totalThrows respektiert heliTracking).
