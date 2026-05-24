# Kubb-App · Detail-Spezifikation Score-Eingabe und Konfliktauflösung (v0.2)

> **Status:** Zweiter Wurf · **Stand:** 2026-05-24
>
> **Zweck:** Dieses Dokument detailliert den Prozess der Score-Eingabe und der Konfliktauflösung. Es ist eine Vertiefung der Anforderungen FR-SCORE und FR-CONF aus der Haupt-Spezifikation und beschreibt alle Flows, Edge Cases und UI-Anforderungen so genau, dass daraus Screens und Implementierung abgeleitet werden können.
>
> **Bezugsdokument:** `tournament-mode-spec.md` v0.4
>
> **Änderungen gegenüber v0.1:**
> - Team-Pool-Modell statt einzelner Captain: jedes registrierte Team-Mitglied kann Scores eintragen
> - Manuelle Eskalation an den Veranstalter durch ein Team-Mitglied als MUSS aufgenommen
> - Wiederholende Erinnerungs-Pushs alle 5 Minuten statt einmaliger Erinnerung
> - Lokales Caching auch nicht abgeschickter Eingabe-Entwürfe (App-Neustart-resistent)
> - In-App-Chat im Strittig-Fall entfernt (mündlich am Pitch reicht)
> - Massen-Aktion für mehrere strittige Matches explizit ausgeschlossen
> - Override-Begründung weiterhin Freitext (keine Pflicht-Inhalte)

---

## Inhaltsverzeichnis

1. [Überblick und Designziele](#1-überblick-und-designziele)
2. [Glossar](#2-glossar)
3. [Match-Lebenszyklus](#3-match-lebenszyklus)
4. [Akteure und Berechtigungen](#4-akteure-und-berechtigungen)
5. [Eingabe-Verfahren](#5-eingabe-verfahren)
6. [Vergleichslogik](#6-vergleichslogik)
7. [Hauptflüsse](#7-hauptflüsse)
8. [Eskalation an den Veranstalter](#8-eskalation-an-den-veranstalter)
9. [Override durch den Veranstalter](#9-override-durch-den-veranstalter)
10. [BYE und Forfeit](#10-bye-und-forfeit)
11. [Edge Cases](#11-edge-cases)
12. [Offline-Verhalten und lokales Caching](#12-offline-verhalten-und-lokales-caching)
13. [Benachrichtigungen](#13-benachrichtigungen)
14. [UI-Anforderungen](#14-ui-anforderungen)
15. [Audit und Nachvollziehbarkeit](#15-audit-und-nachvollziehbarkeit)
16. [Akzeptanzkriterien](#16-akzeptanzkriterien)
17. [Offene Punkte](#17-offene-punkte)

---

## 1. Überblick und Designziele

### 1.1 Was dieser Flow leistet

Der Score-Eingabe- und Konfliktauflösungs-Flow ist das zentrale Verfahren, mit dem Match-Ergebnisse rechtssicher in der App festgehalten werden.

### 1.2 Designziele

1. **Vertrauen durch beidseitige Bestätigung:** Ein Score gilt erst dann als verbindlich, wenn beide Teams ihn übereinstimmend bestätigen.
2. **Konflikte werden lokal gelöst, bevor sie eskalieren:** Bei Abweichungen bekommen die Teams drei Chancen, sich zu einigen, plus die Möglichkeit, jederzeit manuell zu eskalieren.
3. **Schnell am Pitch:** Die Eingabe muss in maximal 30 Sekunden möglich sein.
4. **Robust gegen Netzwerk- und App-Probleme:** Offline-Eingaben dürfen nicht verloren gehen. Auch nicht abgeschickte Entwürfe überstehen einen App-Neustart.
5. **Vollständig nachvollziehbar:** Alle Eingaben bleiben einsehbar.

### 1.3 Was nicht im Geltungsbereich ist

- Berechnung der Ranglistenpunkte aus Match-Scores (siehe FR-RANK und FR-POINTS).
- Initiale Anmeldung zum Match (siehe FR-REG und FR-MATCH).
- Bracket-Generierung und Pitch-Zuteilung (siehe FR-PAIR).
- Team-Pool und Roster-Verwaltung (siehe FR-TEAM).

---

## 2. Glossar

| Begriff | Definition |
|---|---|
| **Eingabe** | Eine in der App erfasste Einschätzung des Match-Ergebnisses durch ein Team-Mitglied, bestehend aus Satz-Daten. Sie gilt als Eingabe seines Teams. |
| **Team-Eingabe** | Die aktuell gültige Eingabe eines Teams im aktuellen Versuch. Bei mehrfachen Eingaben durch verschiedene Team-Mitglieder gilt die zuletzt vor Versuchs-Abschluss eingegangene Eingabe. |
| **Versuch** | Eine Runde, in der beide Teams eine Eingabe abgeben. Pro Match sind drei Versuche möglich. |
| **Satz-Daten** | Pro Satz: Anzahl getroffener Basekubbs pro Team plus Information, wer den König gefällt hat (oder ob die Zeit abgelaufen ist). |
| **Übereinstimmung** | Die Eingaben beider Teams sind in allen Satz-Daten byte-genau identisch. |
| **Abweichung** | Mindestens ein Feld in den Satz-Daten der beiden Teams unterscheidet sich. |
| **Strittig** | Match-Zustand, nachdem drei Versuche zu keiner Übereinstimmung geführt haben oder ein Team-Mitglied manuell eskaliert hat. |
| **Override** | Manueller Eintrag eines Scores durch den Veranstalter, unter Umgehung des normalen Vergleichs. |
| **Eskalation** | Übergabe eines strittigen Matches an den Veranstalter zur finalen Entscheidung. |
| **Manuelle Eskalation** | Vorzeitige Übergabe an den Veranstalter durch ein Team-Mitglied, bevor der dritte Versuch abgeschlossen ist. |
| **Entwurf** | Eine vom Team-Mitglied teilweise oder vollständig ausgefüllte, aber noch nicht abgesendete Eingabe. Lokal zwischengespeichert. |
| **Outbox** | Lokale Warteschlange für offline abgeschickte Eingaben, die beim Reconnect synchronisiert werden. |

---

## 3. Match-Lebenszyklus

### 3.1 Zustände

| Zustand | Beschreibung |
|---|---|
| **GEPLANT** | Match ist erstellt, aber Runde noch nicht gestartet. |
| **LÄUFT** | Runden-Clock läuft, das Match wird gespielt. Score-Eingabe noch nicht aktiv. |
| **WARTET_AUF_EINGABEN** | Mindestens ein Team hat eine Eingabe abgegeben oder die Runden-Clock ist abgelaufen. Beide Teams können noch eintragen. |
| **PRÜFUNG** | Beide Teams haben für den aktuellen Versuch Eingaben abgegeben, das System vergleicht. |
| **ABGESCHLOSSEN** | Eingaben stimmen überein, Score ist verbindlich, Rangliste aktualisiert sich. |
| **STRITTIG** | Drei Versuche ohne Übereinstimmung oder manuelle Eskalation; Veranstalter wurde eskaliert. |
| **VOM_VERANSTALTER_AUFGELÖST** | Veranstalter hat im strittigen Fall einen finalen Score eingetragen. |
| **OVERRIDDEN** | Veranstalter hat manuell einen Score eingetragen, ohne die normale Eingabe abzuwarten. |
| **ABGEBROCHEN** | Match wurde vom Veranstalter abgebrochen, kein Score wird gewertet. |

### 3.2 Übergänge

```
                    ┌──────────────┐
                    │   GEPLANT    │
                    └──────┬───────┘
                           │ Runden-Clock startet
                           ▼
                    ┌──────────────┐
                    │    LÄUFT     │──────────────────────┐
                    └──────┬───────┘                       │ Veranstalter
                           │                               │ Override
                           │ erste Team-Eingabe            ▼
                           │ submittet                ┌─────────────┐
                           ▼                          │ OVERRIDDEN  │
                  ┌─────────────────────┐             └─────────────┘
       ┌──────────│ WARTET_AUF_EINGABEN │
       │          └──────────┬──────────┘
       │ manuelle             │
       │ Eskalation           │ beide Teams haben submittet
       │                      ▼
       │                ┌──────────┐
       │                │ PRÜFUNG  │
       │                └────┬─────┘
       │                     │
       │       ┌─────────────┼─────────────┐
       │       │             │             │
       │       ▼             ▼             ▼
       │ Übereinstimmung Abweichung    3. Versuch
       │       │       (Versuch 1-2)    ohne Einigung
       │       │             │             │
       │       ▼             ▼             ▼
       │ ┌────────────┐  (zurück zu     ┌─────────────┐
       │ │ABGESCHLOSSEN│ WARTET_AUF_  ◄──│   STRITTIG  │
       │ └────────────┘  EINGABEN)       └──────┬──────┘
       │                                        │ Veranstalter
       └────────────────────────────────────────┘ entscheidet
                                                 ▼
                                  ┌─────────────────────────────┐
                                  │ VOM_VERANSTALTER_AUFGELÖST  │
                                  └──────────────┬──────────────┘
                                                 │
                                                 ▼
                                        ┌─────────────────┐
                                        │  ABGESCHLOSSEN  │
                                        └─────────────────┘
```

Von jedem Zustand außer ABGESCHLOSSEN und ABGEBROCHEN kann der Veranstalter das Match abbrechen oder per Override auflösen.

### 3.3 Übergangs-Regeln

- **DSCORE-1 (MUSS):** Der Übergang von LÄUFT zu WARTET_AUF_EINGABEN erfolgt automatisch, sobald ein Team-Mitglied (egal welches Teams) die erste Eingabe abgibt **oder** die Runden-Clock abläuft.
- **DSCORE-2 (MUSS):** Der Übergang von WARTET_AUF_EINGABEN zu PRÜFUNG erfolgt, sobald beide Teams für den aktuellen Versuch eine Eingabe abgegeben haben.
- **DSCORE-3 (MUSS):** Der Übergang von PRÜFUNG zu ABGESCHLOSSEN erfolgt nur, wenn die Eingaben byte-genau übereinstimmen.
- **DSCORE-4 (MUSS):** Der Übergang von PRÜFUNG zurück zu WARTET_AUF_EINGABEN erfolgt, wenn die Eingaben abweichen und der aktuelle Versuch kleiner als 3 ist.
- **DSCORE-5 (MUSS):** Der Übergang von PRÜFUNG zu STRITTIG erfolgt, wenn die Eingaben abweichen und der aktuelle Versuch gleich 3 ist.
- **DSCORE-6 (MUSS):** Der Übergang von WARTET_AUF_EINGABEN zu STRITTIG ist auch durch manuelle Eskalation eines Team-Mitglieds möglich, bevor Versuch 3 abgeschlossen ist.
- **DSCORE-7 (MUSS):** Der Übergang von STRITTIG zu VOM_VERANSTALTER_AUFGELÖST erfolgt, sobald der Veranstalter einen finalen Score eingetragen hat.
- **DSCORE-8 (MUSS):** VOM_VERANSTALTER_AUFGELÖST geht unmittelbar in ABGESCHLOSSEN über.

---

## 4. Akteure und Berechtigungen

| Aktion | Mitglied Team 1 | Mitglied Team 2 | Veranstalter | Co-Veranstalter | Public |
|---|:-:|:-:|:-:|:-:|:-:|
| Match-Detail ansehen | ✓ | ✓ | ✓ | ✓ | ✓ |
| Score-Eingabe abgeben | ✓ | ✓ | – | – | – |
| Frühere Eingabe ersetzen (vor Versuch-Abschluss) | ✓ (eigenes Team) | ✓ (eigenes Team) | – | – | – |
| Manuelle Eskalation auslösen | ✓ (eigenes Team) | ✓ (eigenes Team) | – | – | – |
| Strittiges Match auflösen | – | – | ✓ | ✓ | – |
| Score-Override | – | – | ✓ | ✓ | – |
| Match abbrechen | – | – | ✓ | ✓ | – |
| Alle Versuche einsehen | eigene Team-Eingaben | eigene Team-Eingaben | ✓ | ✓ | – |

- **DSCORE-9 (MUSS):** Alle registrierten Mitglieder eines Team-Pools (mit Captain-Rechten) dürfen Eingaben für Matches ihres Teams abgeben. Es spielt keine Rolle, ob das Mitglied im aktuellen Roster oder am Pitch ist.
- **DSCORE-10 (MUSS):** Gast-Spieler haben keine Berechtigung zur Score-Eingabe.

---

## 5. Eingabe-Verfahren

### 5.1 Was wird pro Satz erfasst

Bei **EKC-Punktesystem** pro Satz:
- Anzahl getroffener Basekubbs Team 1: ganze Zahl von 0 bis `basekubbsPerSide` (Default 5).
- Anzahl getroffener Basekubbs Team 2: ganze Zahl von 0 bis `basekubbsPerSide`.
- König gefällt von: „Team 1" / „Team 2" / „Keiner (Zeitablauf)".

Bei **klassischem Punktesystem** pro Satz:
- Satz-Gewinner: „Team 1" / „Team 2" / „Unentschieden (Zeitablauf)".

- **DSCORE-11 (MUSS):** Pro Match werden so viele Sätze erfasst, wie tatsächlich gespielt wurden. Das ist mindestens 1 und höchstens die im Turnier konfigurierte „Best-of-N"-Zahl.
- **DSCORE-12 (MUSS):** Das eingebende Team-Mitglied kann während der Eingabe Sätze hinzufügen oder entfernen, solange die Untergrenze 1 und die Obergrenze N nicht verletzt werden.
- **DSCORE-13 (MUSS):** Bei Best-of-3 mit einem 2:0-Ergebnis darf der dritte Satz nicht eingetragen werden. Das System validiert dies.

### 5.2 Validierung

- **DSCORE-14 (MUSS):** Basekubb-Zahlen müssen ganzzahlig im erlaubten Bereich liegen.
- **DSCORE-15 (MUSS):** Wenn „König gefällt von" auf Team 1 oder Team 2 gesetzt ist, muss die Anzahl Basekubbs des gewinnenden Teams gleich `basekubbsPerSide` sein. Konfigurierbar abschaltbar pro Turnier.
- **DSCORE-16 (MUSS):** Wenn „Keiner (Zeitablauf)" gesetzt ist, dürfen Basekubbs beider Teams unter `basekubbsPerSide` liegen.
- **DSCORE-17 (MUSS):** Die Eingabe kann erst abgesendet werden, wenn alle Pflichtfelder ausgefüllt sind.
- **DSCORE-18 (MUSS):** Eine fehlerhafte Eingabe zeigt eine klare Fehlermeldung mit dem konkreten Feld an.

### 5.3 Lokales Caching des Entwurfs

- **DSCORE-19 (MUSS):** Jede Änderung im Eingabe-Formular wird lokal als Entwurf gespeichert.
- **DSCORE-20 (MUSS):** Der Entwurf überlebt einen App-Neustart und ein erneutes Öffnen der Match-Detailseite. Beim Wiedereintritt findet das Mitglied den aktuellen Eingabe-Stand vor.
- **DSCORE-21 (MUSS):** Der Entwurf wird verworfen, sobald die Eingabe erfolgreich abgesendet wurde (entweder online oder in die Outbox).
- **DSCORE-22 (MUSS):** Der Entwurf wird verworfen, wenn das Match in ABGESCHLOSSEN, VOM_VERANSTALTER_AUFGELÖST, OVERRIDDEN oder ABGEBROCHEN übergeht.

### 5.4 Vorschau

- **DSCORE-23 (MUSS):** Während der Eingabe zeigt die App eine Live-Vorschau des resultierenden Match-Scores anhand des konfigurierten Punktesystems.
- **DSCORE-24 (MUSS):** Die Vorschau aktualisiert sich bei jeder Änderung in den Feldern unmittelbar.
- **DSCORE-25 (MUSS):** Die Vorschau zeigt auch den Match-Sieger an („Wir gewinnen 16:5" / „Wir verlieren 5:16" / „Unentschieden 10:10").

### 5.5 Absenden

- **DSCORE-26 (MUSS):** Vor dem Absenden zeigt die App einen Bestätigungs-Dialog mit der vollständigen Eingabe.
- **DSCORE-27 (MUSS):** Mit Klick auf „Absenden" wird die Eingabe gespeichert (online oder Outbox).
- **DSCORE-28 (MUSS):** Nach dem Absenden zeigt die App den Status:
  - „Warte auf Eingabe vom Gegner" (wenn die andere Seite noch nicht submittet hat)
  - „Eingaben werden geprüft" (wenn beide submittet haben)
  - „Match abgeschlossen" (wenn übereinstimmend)
  - „Eingaben weichen ab" mit Detail (siehe Sektion 6)

### 5.6 Ersetzen vor Versuchs-Abschluss

- **DSCORE-29 (MUSS):** Solange der aktuelle Versuch noch nicht abgeschlossen ist (die andere Seite hat noch nicht submittet oder die Prüfung läuft noch nicht), kann ein Team-Mitglied die eigene Team-Eingabe ersetzen.
- **DSCORE-30 (MUSS):** Die zuletzt vor Versuchs-Abschluss eingegangene Eingabe gilt als Team-Eingabe für diesen Versuch.
- **DSCORE-31 (MUSS):** Jede Ersetzung wird im Audit-Log mit Mitglied, Zeitstempel und Eingabe-Inhalt festgehalten.
- **DSCORE-32 (MUSS):** Sobald beide Seiten submittet haben und der Vergleich stattgefunden hat, ist eine Ersetzung für diesen Versuch nicht mehr möglich. Bei Abweichung wird automatisch der nächste Versuch eröffnet.

---

## 6. Vergleichslogik

### 6.1 Was bedeutet „Übereinstimmung"

- **DSCORE-33 (MUSS):** Zwei Team-Eingaben stimmen überein, wenn sie in folgenden Aspekten identisch sind:
  - Anzahl Sätze
  - Für jeden Satz: Basekubbs Team 1, Basekubbs Team 2, „König gefällt von"-Wert.
- **DSCORE-34 (MUSS):** Bei klassischem Punktesystem stimmt eine Eingabe überein, wenn der Satz-Gewinner pro Satz identisch ist.
- **DSCORE-35 (MUSS):** Die Reihenfolge der Sätze muss übereinstimmen (Satz 1 mit Satz 1 verglichen).

### 6.2 Was bedeutet „Abweichung"

- **DSCORE-36 (MUSS):** Jede Differenz in mindestens einem Feld gilt als Abweichung. Es gibt keine „Fast-Übereinstimmung" und keine Toleranzen.

### 6.3 Anzeige der Abweichung

- **DSCORE-37 (MUSS):** Im Abweichungsfall wird beiden Teams die genaue Differenz angezeigt:
  - Welcher Satz weicht ab.
  - Welches Feld in diesem Satz weicht ab.
  - Was die eigene Eingabe und was die der Gegenseite ist.
- **DSCORE-38 (MUSS):** Die Anzeige ist nebeneinander oder übereinander, sodass die Teams schnell sehen, wo sie sich uneinig sind.
- **DSCORE-39 (MUSS):** Die Anzeige hebt die abweichenden Felder farblich hervor.

---

## 7. Hauptflüsse

### 7.1 Standard-Flow: Einigkeit beim ersten Versuch

```
1. Match endet.
2. Mitglied A1 von Team A öffnet Match-Detail, trägt Sätze ein, prüft Vorschau, sendet ab.
3. App zeigt Team A: "Warte auf Eingabe vom Gegner."
4. Mitglied B1 von Team B öffnet Match-Detail, trägt Sätze ein, prüft Vorschau, sendet ab.
5. System vergleicht die beiden Team-Eingaben.
6. Eingaben stimmen überein → Match → ABGESCHLOSSEN.
7. Alle Team-Mitglieder beider Teams erhalten Push: "Match abgeschlossen, Score eingetragen."
8. Rangliste aktualisiert sich.
```

### 7.2 Konflikt-Flow: Abweichung, Einigkeit nach Versuch 2 oder 3

```
1. Versuch 1: Beide Teams senden Eingaben, weichen ab.
2. System zeigt beiden Seiten die Differenz an.
3. Alle Team-Mitglieder beider Teams erhalten Push: "Score-Eingabe abweichend, bitte erneut eintragen (Versuch 2 von 3)."
4. Teams besprechen sich am Pitch.
5. Versuch 2: Beide senden erneut.
   ┌─ Übereinstimmung → ABGESCHLOSSEN.
   └─ Abweichung →
       6. System zeigt erneut die Differenz, jetzt auch im Vergleich zum vorherigen Versuch.
       7. Alle erhalten Push: "Letzter Versuch (3 von 3), bitte erneut eintragen."
       8. Versuch 3: Beide senden erneut.
          ┌─ Übereinstimmung → ABGESCHLOSSEN.
          └─ Abweichung → STRITTIG (siehe 7.3).
```

### 7.3 Eskalations-Flow: 3. Versuch ohne Einigung

```
1. Match → STRITTIG.
2. Alle Team-Mitglieder beider Teams sehen: "Eingaben weichen ab. Veranstalter wurde benachrichtigt."
3. Team-Mitglieder können keine weiteren Eingaben mehr abgeben.
4. Veranstalter erhält Push (laut, ignoriert Stummschaltung): "Pitch X strittig, Aktion erforderlich."
5. Veranstalter öffnet die Match-Detailseite in seinem Dashboard.
6. Veranstalter sieht:
   - Alle 6 Eingaben (3 Versuche × 2 Teams) nebeneinander.
   - Live-Vorschau der Auswirkung auf die Rangliste je nach Entscheidung.
7. Veranstalter klärt vor Ort mit den Teams.
8. Veranstalter trägt den finalen Score selbst ein.
9. Match → VOM_VERANSTALTER_AUFGELÖST → ABGESCHLOSSEN.
10. Alle Team-Mitglieder beider Teams erhalten Push: "Veranstalter hat entschieden: Score = X:Y."
11. Rangliste aktualisiert sich.
```

### 7.4 Manuelle Eskalation durch ein Team-Mitglied

```
1. Versuch 1 oder 2 weicht ab. Versuch 3 ist noch nicht abgeschlossen.
2. Ein Team-Mitglied sieht keine Möglichkeit zur Einigung mit der Gegenseite.
3. In der Match-Detailseite klickt es „Veranstalter hinzuziehen".
4. Dialog: "Möchtest du den Veranstalter sofort eskalieren? Dieser Schritt kann nicht zurückgenommen werden."
5. Bestätigung → Match → STRITTIG.
6. Veranstalter wird hochpriorisiert benachrichtigt.
7. Weiter wie in 7.3 ab Schritt 5.
```

### 7.5 Einseitiger Eingabe-Flow (wiederholende Erinnerung)

```
1. Nur Team A hat eingetragen, Team B nicht.
2. Nach 5 Minuten ohne Gegen-Eingabe → Push an alle registrierten Mitglieder von Team B: "Bitte trage den Score für dein Match auf Pitch X ein."
3. Nach weiteren 5 Minuten → erneuter Push an Team B.
4. Nach insgesamt 15 Minuten (3 Erinnerungen ohne Reaktion) → zusätzlich Push an Veranstalter: "Team B hat seit X Minuten nicht eingetragen, Match Y bleibt offen."
5. Die Erinnerungs-Pushs an Team B laufen weiter, bis die Eingabe erfolgt oder der Veranstalter eingreift.
6. Veranstalter kann per Override eingreifen oder weiter warten.
```

### 7.6 Beide Teams tragen gleichzeitig ein

- **DSCORE-40 (MUSS):** Wenn beide Teams in einem sehr engen Zeitfenster gleichzeitig submitten, gilt die zuerst beim Server eintreffende Eingabe als „erste Eingabe" und die zweite als die Antwort. Der Vergleich findet statt, sobald beide angekommen sind. Es entsteht kein Wettlauf-Problem.

### 7.7 Mehrere Mitglieder desselben Teams tragen gleichzeitig ein

- **DSCORE-41 (MUSS):** Wenn mehrere Mitglieder desselben Teams gleichzeitig oder kurz hintereinander eintragen, gilt die zuletzt eingegangene Eingabe als Team-Eingabe für diesen Versuch.
- **DSCORE-42 (MUSS):** Jede einzelne Eingabe wird im Audit-Log gespeichert (mit Mitglied und Zeitstempel), auch wenn sie durch eine spätere ersetzt wird.
- **DSCORE-43 (SOLL):** Die App zeigt einem Mitglied, das gerade die Eingabe-Maske öffnet, einen Hinweis, falls bereits ein anderes Team-Mitglied eine Eingabe für diesen Versuch abgegeben hat: „Mitglied X hat bereits eine Eingabe abgegeben. Deine Eingabe würde diese ersetzen."

---

## 8. Eskalation an den Veranstalter

### 8.1 Wann erfolgt sie

- **DSCORE-44 (MUSS):** Eskalation erfolgt automatisch, sobald der dritte Versuch ohne Übereinstimmung endet.
- **DSCORE-45 (MUSS):** Eskalation kann auch manuell durch ein Team-Mitglied vor Versuch 3 ausgelöst werden (siehe 7.4).

### 8.2 Was sieht der Veranstalter

- **DSCORE-46 (MUSS):** Eine spezielle „Strittig-Ansicht" pro Match mit:
  - Match-Stammdaten (Pitch, Teams, Runde, Zeit).
  - Tabelle aller Versuche, beide Seiten nebeneinander, inklusive der jeweils submittenden Mitglieder.
  - Visuelle Hervorhebung der abweichenden Felder pro Versuch.
  - Live-Vorschau der Auswirkung auf die Rangliste für jeden möglichen Entscheidungs-Score.
  - Audit-Log: Wer hat wann was eingetragen.
  - Hinweis, ob die Eskalation automatisch (Versuch 3) oder manuell (durch wen) erfolgte.

### 8.3 Wie wird entschieden

- **DSCORE-47 (MUSS):** Der Veranstalter trägt den finalen Match-Score selbst ein, in derselben Form wie ein Team-Mitglied (pro Satz).
- **DSCORE-48 (MUSS):** Der Veranstalter kann eine Begründung im Klartext hinterlegen (optional bei automatischer Eskalation, empfohlen).
- **DSCORE-49 (MUSS):** Mit dem Absenden geht das Match in VOM_VERANSTALTER_AUFGELÖST über. Es gibt keine weitere Bestätigung durch die Teams.

### 8.4 Was die Teams nach der Entscheidung sehen

- **DSCORE-50 (MUSS):** Alle Mitglieder beider Teams sehen den finalen Score, die Begründung (falls hinterlegt) und einen Hinweis, dass die Entscheidung durch den Veranstalter erfolgte.
- **DSCORE-51 (MUSS):** Der Score erscheint in der Rangliste und in allen öffentlichen Sichten ohne besondere Markierung als „durch Veranstalter entschieden". Im Audit-Log ist die Entscheidung als solche kenntlich.

---

## 9. Override durch den Veranstalter

### 9.1 Wann ist Override erlaubt

- **DSCORE-52 (MUSS):** Der Veranstalter kann Score-Override in folgenden Zuständen anwenden:
  - LÄUFT (sehr selten – z. B. bei vorzeitigem Abbruch eines Matches und sofortiger Wertung).
  - WARTET_AUF_EINGABEN (z. B. wenn ein Team offline ist und keine Eingabe abgeben kann).
  - STRITTIG (Standard-Eskalations-Weg, siehe Sektion 8).

### 9.2 Wie funktioniert Override

- **DSCORE-53 (MUSS):** Der Veranstalter trägt den Score in derselben Eingabemaske ein wie ein Team-Mitglied.
- **DSCORE-54 (MUSS):** Vor dem Absenden muss der Veranstalter den Override bestätigen (Dialog mit Hinweis: „Du überschreibst die Score-Eingabe der Teams").
- **DSCORE-55 (MUSS):** Eine Begründung ist beim Override **pflichtig**, als Freitext (keine strukturierten Inhalts-Vorgaben).
- **DSCORE-56 (MUSS):** Nach Override geht das Match in OVERRIDDEN über und gilt als abgeschlossen.

### 9.3 Was passiert mit bereits abgegebenen Eingaben

- **DSCORE-57 (MUSS):** Eingaben, die Team-Mitglieder vor dem Override abgegeben haben, bleiben im Audit-Log erhalten, werden aber für die Wertung verworfen.
- **DSCORE-58 (MUSS):** Alle Mitglieder beider Teams werden über den Override per Push informiert.

---

## 10. BYE und Forfeit

### 10.1 BYE-Matches

- **DSCORE-59 (MUSS):** BYE-Matches durchlaufen den Eingabe-Flow **nicht**. Sie werden automatisch in den Status ABGESCHLOSSEN gesetzt, sobald die Runde gestartet wird.
- **DSCORE-60 (MUSS):** Der Score wird gemäß der Turnier-Konfiguration (z. B. 16:0) automatisch eingetragen.
- **DSCORE-61 (MUSS):** BYE-Matches sind in der Match-Detail-Ansicht klar als „BYE" markiert.

### 10.2 Forfeit-Matches (No-Show)

- **DSCORE-62 (MUSS):** Wenn ein Team nicht zum Pitch erscheint, kann der Veranstalter das Match als Forfeit werten.
- **DSCORE-63 (MUSS):** Der Forfeit-Eintrag erfolgt durch den Veranstalter in der Match-Detail-Ansicht über die Aktion „Forfeit erklären", mit Auswahl der abwesenden Seite.
- **DSCORE-64 (MUSS):** Der Score wird automatisch gemäß Turnier-Konfiguration eingetragen.
- **DSCORE-65 (MUSS):** Eine Begründung ist erforderlich.
- **DSCORE-66 (MUSS):** Das anwesende Team wird informiert.

### 10.3 Forfeit bei mid-Turnier-Ausfall

- **DSCORE-67 (MUSS):** Wenn ein Team im Verlauf des Turniers ausfällt (FR-MATCH-8), werden alle nachfolgenden geplanten Matches dieses Teams automatisch in ABGESCHLOSSEN mit Forfeit-Score versetzt.

---

## 11. Edge Cases

### 11.1 Team-Mitglied ändert Eingabe vor Versuchs-Abschluss

- **DSCORE-68 (MUSS):** Solange die andere Seite noch nicht submittet hat oder die Prüfung noch nicht abgeschlossen ist, kann jedes Team-Mitglied seine Team-Eingabe ersetzen. Die letzte gültige Eingabe vor Abschluss zählt.
- **DSCORE-69 (MUSS):** Jede Änderung wird im Audit-Log mit Mitglied, Zeitstempel und Eingabe-Inhalt festgehalten.

### 11.2 Mitglied A trägt ein, Mitglied B desselben Teams ersetzt

- **DSCORE-70 (MUSS):** Die spätere Eingabe ersetzt die frühere für die Team-Eingabe. Beide Eingaben bleiben im Audit-Log.
- **DSCORE-71 (MUSS):** Die App informiert das Mitglied, das eine fremde Eingabe ersetzen würde, vor dem Absenden (siehe DSCORE-43).

### 11.3 Team-Mitglied submittet, geht offline, dann tritt die andere Seite ein

- **DSCORE-72 (MUSS):** Die Eingabe des offline gegangenen Mitglieds liegt bereits beim Server, der Vergleich kann auch ohne Online-Status stattfinden.
- **DSCORE-73 (MUSS):** Push-Benachrichtigungen treffen das Mitglied bei Reconnect.

### 11.4 Team-Mitglied submittet offline und kommt erst spät online

- **DSCORE-74 (MUSS):** Die Eingabe wird lokal in der Outbox gespeichert.
- **DSCORE-75 (MUSS):** Beim Reconnect wird die Outbox abgearbeitet.
- **DSCORE-76 (MUSS):** Falls der Veranstalter in der Zwischenzeit einen Override durchgeführt hat oder ein anderes Team-Mitglied eingetragen hat, wird die spät eintreffende Eingabe gemäß Konflikt-Regeln behandelt: Bei Override wird sie verworfen mit Hinweis; bei einer noch offenen Team-Eingabe ersetzt sie diese, falls noch im aktiven Versuch.

### 11.5 Kein Mitglied eines Teams ist erreichbar

- **DSCORE-77 (MUSS):** Das andere Team trägt ein und wartet auf die Gegenseite.
- **DSCORE-78 (MUSS):** Erinnerungs-Pushs wiederholen sich alle 5 Minuten (siehe 7.5).
- **DSCORE-79 (MUSS):** Nach 15 Minuten ohne Eingabe wird der Veranstalter informiert.
- **DSCORE-80 (MUSS):** Der Veranstalter kann per Override eingreifen.

### 11.6 Unentschieden im EKC-Score (z. B. 10:10)

- **DSCORE-81 (MUSS):** Ein Unentschieden in Match-Punkten ist im EKC-System möglich (z. B. wenn jede Seite einen Satz gewinnt mit gleicher Basekubb-Anzahl). Das System akzeptiert dies ohne Sonderlogik.

### 11.7 Team-Mitglied trägt mehr Sätze ein als gespielt

- **DSCORE-82 (MUSS):** Die UI verhindert mehr als die im Turnier konfigurierte Maximal-Satzzahl. Validierung serverseitig spiegelt dies.

### 11.8 Team-Mitglied trägt für falsche Seite ein

- **DSCORE-83 (MUSS):** Die Eingabe-Maske ist eindeutig: Mitglied sieht „Mein Team" und „Gegner" mit Namen. Die UI verhindert Seiten-Verwechslung.
- **DSCORE-84 (MUSS):** Falls beide Teams ihre Eingabe spiegelverkehrt machen, würden die Eingaben „übereinstimmen aus eigener Sicht", aber serverseitig als Abweichung registriert.

### 11.9 Turnier wird während eines offenen Matches abgebrochen

- **DSCORE-85 (MUSS):** Bei Turnier-Abbruch geht jedes Match in ABGEBROCHEN über, unabhängig vom Eingabestatus.
- **DSCORE-86 (MUSS):** Bereits abgeschlossene Matches bleiben in ABGESCHLOSSEN.

### 11.10 Eingabe wird nach Match-Abschluss noch geändert

- **DSCORE-87 (MUSS):** Nach ABGESCHLOSSEN kann ein Score nur noch durch den Veranstalter geändert werden (manueller Korrektureintrag). Team-Mitglieder haben keine Möglichkeit mehr.
- **DSCORE-88 (MUSS):** Eine manuelle Korrektur durch den Veranstalter ist eine separate Aktion und wird im Audit-Log festgehalten.

### 11.11 Mehrfaches Submitten durch wiederholtes Klicken

- **DSCORE-89 (MUSS):** Wenn ein Mitglied „Absenden" mehrfach drückt, gilt nur die zuletzt erfolgreich beim Server angekommene Eingabe.
- **DSCORE-90 (MUSS):** Idempotenz-Keys auf Client-Seite verhindern Doppel-Verarbeitung.

### 11.12 App-Neustart mitten in der Eingabe

- **DSCORE-91 (MUSS):** Der lokal gespeicherte Entwurf (siehe 5.3) wird beim Wiedereintritt geladen. Das Mitglied findet seine Eingabe in dem Zustand vor, in dem es die App verlassen hat.

### 11.13 Mehrere strittige Matches gleichzeitig

- **DSCORE-92 (MUSS):** Bei mehreren gleichzeitig strittigen Matches behandelt der Veranstalter sie einzeln. Es gibt **keine Massen-Aktion**. Das Dashboard listet die offenen strittigen Matches priorisiert auf, der Veranstalter arbeitet sie nacheinander ab.

---

## 12. Offline-Verhalten und lokales Caching

### 12.1 Entwurfs-Caching (vor Absenden)

- **DSCORE-93 (MUSS):** Eingaben in das Formular werden lokal als Entwurf gespeichert (siehe 5.3).
- **DSCORE-94 (MUSS):** Der Entwurf besteht aus den eingegebenen Werten plus einer Status-Markierung „nicht abgeschickt".
- **DSCORE-95 (MUSS):** Ein lokaler Entwurf ist auf das aktuelle Gerät beschränkt und nicht zwischen Geräten synchronisiert. Würde ein Mitglied auf einem anderen Gerät eintragen, beginnt es mit einem leeren Formular.

### 12.2 Outbox (nach Absenden, offline)

- **DSCORE-96 (MUSS):** Wenn die Eingabe offline abgesendet wird, wandert sie in die Outbox.
- **DSCORE-97 (MUSS):** Die App zeigt einen Hinweis: „Du bist offline, deine Eingabe wird synchronisiert, sobald du wieder verbunden bist."
- **DSCORE-98 (MUSS):** Sobald die Verbindung wiederhergestellt ist, sendet die App die Outbox an den Server.
- **DSCORE-99 (MUSS):** Erfolg: Die Eingabe wird wie eine reguläre Online-Eingabe behandelt.
- **DSCORE-100 (MUSS):** Konflikt (z. B. Veranstalter hat Override durchgeführt): Die Eingabe wird verworfen, das Mitglied wird informiert.

### 12.3 Idempotenz

- **DSCORE-101 (MUSS):** Jede Eingabe-Operation hat einen client-generierten Idempotenz-Key.
- **DSCORE-102 (MUSS):** Der Server lehnt Duplikate mit demselben Idempotenz-Key ab.

### 12.4 Was sieht der User offline

- **DSCORE-103 (MUSS):** Eine bereits geladene Match-Detailseite ist offline einsehbar.
- **DSCORE-104 (MUSS):** Der lokale Entwurfs- und Outbox-Status ist offline einsehbar.

---

## 13. Benachrichtigungen

| Ereignis | Empfänger | Kanal | Priorität | Wiederholung |
|---|---|---|---|---|
| Match-Eingabe-Fenster geöffnet (Runden-Clock abgelaufen) | Alle Mitglieder beider Teams | Push + In-App | Normal | Einmalig |
| Eigene Eingabe erfolgreich abgegeben | Submittendes Mitglied | In-App-Bestätigung | Niedrig | Einmalig |
| Erste Seite hat submittet, andere noch nicht | Wartende Team-Mitglieder | Push | Normal | Alle 5 Min, bis Eingabe oder Eskalation |
| Versuch 1 abweichend | Alle Mitglieder beider Teams | Push | Normal | Einmalig |
| Versuch 2 abweichend | Alle Mitglieder beider Teams | Push | Normal | Einmalig |
| Versuch 3 ohne Einigung → STRITTIG | Alle Mitglieder beider Teams | Push (laut) | Hoch | Einmalig |
| Manuelle Eskalation durch Team-Mitglied | Anderes Team + Veranstalter | Push (laut) | Hoch | Einmalig |
| Veranstalter wird eskaliert | Veranstalter | Push (laut) | Hoch | Einmalig |
| Match abgeschlossen (Übereinstimmung) | Alle Mitglieder beider Teams | Push | Normal | Einmalig |
| Match abgeschlossen (durch Veranstalter aufgelöst) | Alle Mitglieder beider Teams | Push | Normal | Einmalig |
| Match wurde per Override entschieden | Alle Mitglieder beider Teams | Push | Hoch | Einmalig |
| Match wurde abgebrochen | Alle Mitglieder beider Teams | Push | Normal | Einmalig |
| Team hat seit 15 Min nicht eingetragen | Veranstalter | Push | Normal | Einmalig (Erstmeldung) |
| Anderes Team-Mitglied hat soeben eine Eingabe abgegeben | Submittendes Mitglied selbst | In-App-Bestätigung | Niedrig | Einmalig |

- **DSCORE-105 (MUSS):** Alle Benachrichtigungen erscheinen auch im In-App-Postfach, unabhängig vom Kanal.
- **DSCORE-106 (MUSS):** Hochpriorisierte Pushs (Eskalation, Override) ignorieren die Stummschaltungs-Einstellungen.

---

## 14. UI-Anforderungen

> **Hinweis:** Diese Sektion beschreibt Verhalten und Inhalte. Konkrete visuelle Gestaltung wird separat als Design-Spec erstellt (siehe Claude-Design-Handoff).

### 14.1 Match-Detail-Seite (Team-Mitglied-Sicht)

Inhalt:
- Kopfbereich: Pitch-Nummer, Turnier-Name, Runde, eigenes Team und Gegner.
- Status-Banner mit aktuellem Match-Zustand.
- Verbleibende Zeit der Runden-Clock (falls noch laufend).
- Eingabe-Bereich (siehe 14.2), nur sichtbar wenn Match in LÄUFT, WARTET_AUF_EINGABEN oder STRITTIG.
- Eigene aktuelle Team-Eingabe dieses Versuchs (falls vorhanden), inklusive Vermerk, welches Mitglied sie zuletzt geändert hat.
- Status der anderen Seite („noch nicht submittet" / „submittet, wartet auf Vergleich" / etc.).
- Historie der Versuche (falls Versuch ≥ 2).
- Button „Veranstalter hinzuziehen" für manuelle Eskalation (sichtbar wenn Match in WARTET_AUF_EINGABEN und Versuch < 3).
- Hinweis auf Lageplan-Link.

### 14.2 Eingabe-Bereich

Pro Satz:
- Klare Beschriftung „Satz 1", „Satz 2", „Satz 3".
- Zwei Bereiche nebeneinander oder untereinander: „Mein Team" und „Gegner [Name]".
- Pro Bereich: Basekubb-Eingabe (Stepper oder direkte Tastatur), König-Schalter.
- Ein Schalter „König gefällt von" mit Optionen „Mein Team", „Gegner", „Keiner (Zeitablauf)".
- Live-Vorschau des Match-Scores unter den Sätzen.
- Buttons: „Satz hinzufügen", „Satz entfernen".

Abschluss:
- „Absenden"-Button, prominent platziert.
- Bestätigungs-Dialog vor finalem Senden.
- Hinweis, falls ein anderes Team-Mitglied bereits eine Eingabe für diesen Versuch abgegeben hat (DSCORE-43).

### 14.3 Konflikt-Anzeige

Im Abweichungsfall:
- Roter Status-Banner: „Eingaben stimmen nicht überein. Bitte einigt euch und tragt erneut ein."
- Vergleichs-Tabelle: pro Satz die eigene und die Gegner-Eingabe nebeneinander.
- Abweichende Felder farblich (z. B. rot) hervorgehoben.
- Anzeige des aktuellen Versuchs („Versuch 2 von 3").
- Button: „Erneut eintragen" (öffnet die Eingabe-Maske mit den eigenen vorherigen Werten als Default).
- Button: „Veranstalter hinzuziehen" für manuelle Eskalation.

### 14.4 Manuelle-Eskalations-Dialog

Beim Klick auf „Veranstalter hinzuziehen":
- Bestätigungs-Dialog: „Du eskalierst dieses Match an den Veranstalter. Dieser Schritt kann nicht zurückgenommen werden. Möchtest du fortfahren?"
- Optional: Freitextfeld für eine kurze Notiz an den Veranstalter (KANN).

### 14.5 Veranstalter-Dashboard – Strittig-Ansicht

Pro strittiges Match:
- Pitch, Teams, Status STRITTIG mit roter Markierung.
- Hinweis: Eskalation automatisch (Versuch 3) oder manuell (durch wen).
- Tabelle aller Versuche, beide Seiten nebeneinander mit jeweils submittendem Mitglied.
- Vergleichs-Hervorhebung der Abweichungen.
- Auswirkungs-Vorschau auf die Rangliste pro möglichem Entscheidungs-Score.
- Eingabe-Maske, identisch mit der Team-Eingabe.
- Optional-Feld „Begründung".
- Button „Entscheidung speichern".

### 14.6 Veranstalter-Dashboard – Override-Aktion

In der Match-Detailseite des Veranstalters:
- Aktion „Score überschreiben" sichtbar in allen Zuständen außer ABGESCHLOSSEN und ABGEBROCHEN.
- Eingabe-Maske wie bei Team-Eingabe.
- Pflichtfeld „Begründung" (Freitext, mit Mindestlänge z. B. 10 Zeichen).
- Bestätigungs-Dialog mit Hinweis: „Du überschreibst die Score-Eingabe der Teams. Dies wird im Audit-Log festgehalten."

### 14.7 Offline-Anzeige

- Persistenter Banner am oberen Bildschirmrand wenn offline: „Offline – deine Eingaben werden synchronisiert, sobald du wieder verbunden bist."
- Outbox-Anzeige: In einem dedizierten „Synchronisations-Status"-Bereich kann das Mitglied sehen, welche Eingaben noch nicht synchronisiert sind.
- Entwurfs-Hinweis: Beim Wiedereintritt in eine Match-Detailseite mit lokal gespeichertem Entwurf erscheint ein Hinweis „Du hast eine nicht abgeschickte Eingabe für dieses Match. Möchtest du sie fortsetzen?"

---

## 15. Audit und Nachvollziehbarkeit

### 15.1 Was wird protokolliert

- **DSCORE-107 (MUSS):** Jede Eingabe (auch ersetzte und durch neue überschriebene) wird mit folgenden Daten gespeichert:
  - Match-ID
  - Submitter (User-ID, zugehöriges Team)
  - Versuch-Nummer
  - Eingabe-Inhalt (Satz-Daten)
  - Zeitstempel
  - Submissions-Status (gültig / ersetzt / verworfen wegen Override)
  - Begründung (falls vorhanden)

- **DSCORE-108 (MUSS):** Jeder Status-Übergang des Matches wird mit Zeitstempel und auslösendem Akteur protokolliert.
- **DSCORE-109 (MUSS):** Manuelle Eskalationen werden mit Mitglied, Zeitstempel und optionaler Notiz protokolliert.

### 15.2 Wer kann das Audit-Log einsehen

- **DSCORE-110 (MUSS):** Veranstalter und Co-Veranstalter sehen das vollständige Audit-Log aller Matches ihres Turniers.
- **DSCORE-111 (MUSS):** Plattform-Administratoren sehen alle Audit-Logs.
- **DSCORE-112 (MUSS):** Team-Mitglieder sehen das Audit-Log ihrer eigenen Team-Matches.
- **DSCORE-113 (MUSS):** Public hat keinen Zugriff auf Audit-Logs.

### 15.3 Was wird öffentlich angezeigt

- **DSCORE-114 (MUSS):** Im Public-View wird nur der finale Match-Score angezeigt, nicht die Versuche oder Konflikte.
- **DSCORE-115 (MUSS):** Bei VOM_VERANSTALTER_AUFGELÖST und OVERRIDDEN gibt es keinen sichtbaren Unterschied im Public-View.

---

## 16. Akzeptanzkriterien

| ID | Kriterium |
|---|---|
| **AK-1** | Zwei Team-Mitglieder unterschiedlicher Teams tragen identische Sätze ein → Match wechselt zu ABGESCHLOSSEN innerhalb von 2 Sekunden. |
| **AK-2** | Zwei Team-Mitglieder unterschiedlicher Teams tragen abweichende Sätze ein → alle Team-Mitglieder beider Teams bekommen Push und sehen die Differenz farblich hervorgehoben. |
| **AK-3** | Nach drei Versuchen ohne Einigung → Match wechselt zu STRITTIG, Veranstalter bekommt hochpriorisierte Push. |
| **AK-4** | Ein Team-Mitglied löst manuelle Eskalation aus → Match wechselt zu STRITTIG, Veranstalter wird informiert. |
| **AK-5** | Veranstalter trägt finalen Score ein → Match wechselt zu ABGESCHLOSSEN, alle Team-Mitglieder bekommen Push. |
| **AK-6** | Team-Mitglied submittet offline → lokale Bestätigung erscheint, beim Reconnect wird die Eingabe übermittelt. |
| **AK-7** | Team-Mitglied submittet, geht offline, Veranstalter macht Override → bei Reconnect wird die Eingabe abgelehnt und das Mitglied informiert. |
| **AK-8** | Einer der Teams submittet nicht innerhalb von 5 Minuten → wiederholende Erinnerungs-Pushs alle 5 Minuten, nach 15 Min Veranstalter informiert. |
| **AK-9** | BYE-Match wird automatisch mit BYE-Score eingetragen. |
| **AK-10** | Forfeit-Match wird durch Veranstalter mit Begründung gewertet. |
| **AK-11** | Eingabe mit fehlerhaften Werten (z. B. Basekubbs > 5) wird mit klarer Fehlermeldung abgelehnt. |
| **AK-12** | Zwei Team-Mitglieder unterschiedlicher Teams submitten gleichzeitig → keine Race Condition. |
| **AK-13** | Zwei Mitglieder desselben Teams submitten in kurzem Abstand → die spätere Eingabe ersetzt die frühere, beide bleiben im Audit-Log. |
| **AK-14** | Mehrfaches Submitten desselben Eingabe-Versuchs führt nicht zu Mehrfach-Verarbeitung (Idempotenz). |
| **AK-15** | App-Neustart mitten in der Eingabe → bei Wiedereintritt findet das Mitglied den Entwurf vor. |
| **AK-16** | Das Audit-Log zeigt jede Eingabe (inkl. ersetzter), jeden Status-Übergang und jede Begründung mit Zeitstempel an. |
| **AK-17** | Im Public-View ist nicht erkennbar, ob ein Match durch Veranstalter aufgelöst oder per Override entschieden wurde. |

---

## 17. Offene Punkte

1. **Hinweis bei paralleler Eingabe innerhalb desselben Teams (DSCORE-43):** Aktuell als SOLL markiert. Soll dies eine harte MUSS-Anforderung sein, mit einer Bestätigungs-Schwelle, bevor eine fremde Eingabe überschrieben wird?
2. **Optionale Notiz bei manueller Eskalation (DSCORE-Section 14.4):** Aktuell als KANN markiert. Soll das Notiz-Feld pflichtig sein, damit der Veranstalter Kontext bekommt?
3. **Hartes Zeitlimit für die Eingabe-Phase:** Aktuell nur Erinnerungs-Pushs. Bewusst kein hartes Limit, kann später eingeführt werden, falls in der Praxis benötigt.

---

*Ende der Detail-Spezifikation Score-Eingabe und Konfliktauflösung v0.2.*
