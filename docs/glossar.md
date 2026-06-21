# Glossar — Turnier-Setup (Naming-Bibliothek)

> Gemeinsame Sprach- und Namensbasis fuer den Setup-Wizard und den Stufen-Graph.
> Aus diesem Glossar leiten wir ab: (1) das User-Wording in der App, (2) die
> Code-Identifier (Refactor), (3) die Info-Texte fuer die Info-Buttons.
> Status v1.0 — abgenommen.

## Status-Legende
- ✅ **einig** — so festgelegt, wird umgesetzt
- 🔁 **Vorschlag** — noch zu bestaetigen
- ❓ **offen** — bewusst NICHT entschieden, du entscheidest

## Info-Button-Prinzip (gilt fuer ALLE Info-Texte)
- **Nicht technisch.** Keine Code-/Fachjargon-Begriffe, keine Variablennamen.
- **Anfaengertauglich:** Jemand, der noch nie von Kubb gehoert hat, muss den Wizard damit bedienen koennen.
- **Auswirkung + Zeitpunkt nennen:** Was bewirkt die Auswahl, und WANN/WO passiert etwas. Beispiel KO-Setzung "Manuell": erklaeren, dass man die Setzliste nach der Vorrunde selbst festlegt und das KO erst danach starten kann.
- **Jedes auswaehlbare/konfigurierbare Element im Setup-Wizard bekommt einen Info-Button.**

## Lese-Schema
Jeder Eintrag: **Konzept** — User-Wort (DE) — Code-Identifier (EN, ist/soll) — Bedeutung (Klartext, was passiert / Auswirkung) — Vorkommen — Status.
Die Spalte "Bedeutung" wird spaeter 1:1 zum Info-Button-Text.

---

## 1. Vorrunde

| Konzept | User-Wort | Code | Bedeutung (Klartext) | Status |
|---|---|---|---|---|
| Vorrunden-Modus A | **Gruppenphase** | `VorrundeType.groupPhase` (`group_phase`) | Jeder spielt in seiner Gruppe gegen jeden. Aus jeder Gruppe ziehen die Bestplatzierten weiter. | ✅ |
| Vorrunden-Modus B | **Schoch** | `VorrundeType.schoch` (`schoch`) | Paarungen werden nach jeder Runde neu nach Tabellenstand gebildet (Sieger gegen Sieger). Flexible Rundenzahl, ein gemeinsamer Pool. Gut fuer grosse Felder. | ✅ |

**Regel:** User-sichtbar gibt es nur **Gruppenphase** und **Schoch**.
Das Wort **"Schweizer System"** (und "Swiss") wird ueberall entfernt → **Schoch**.
Aktuell noch zu ersetzen: `tournamentFormatSwiss`, `tournamentSwissSystem`, `tournamentSwissOversize`, `stageGraphNodeTypeInfoSwiss`, `stageGraphConfigSwissHint`. ✅

---

## 2. Stufentypen (Stufen-Graph-Knoten)

| User-Wort (soll) | Code (ist) | Bedeutung (Klartext) | Status |
|---|---|---|---|
| **Gruppenphase** | `StageNodeType.pool` | Gruppen, jeder gegen jeden, Beste steigen auf. | 🔁 (Label von "Gruppe" → "Gruppenphase") |
| **Schoch** | `StageNodeType.swiss` | wie Vorrunde Schoch. | ✅ (Wort), Label-Quelle noch "swiss" |
| **K.-o. (einfach)** | `StageNodeType.singleElim` | Wer verliert, ist raus. | ✅ |
| **K.-o. (doppelt)** | `StageNodeType.doubleElim` | Erst nach der zweiten Niederlage raus (Verliererbracket). | ✅ |
| **Trosttournier** | `StageNodeType.consolation` | Nebenwettbewerb fuer frueh Ausgeschiedene. | ✅ |

Nicht im Auswahl-Picker (existieren als Typ fuer Altdaten): `roundRobin`, `shootoutQuali`. ✅

> Anmerkung: `swiss`/`pool`/`roundRobin` als Code-Namen passen nicht sauber zum
> User-Wording (Schoch / Gruppenphase). Ein Code-Rename ist Teil des Refactors —
> siehe Abschnitt 12.

---

## 3. Gruppierung

| User-Wort (soll) | Code | Bedeutung (Klartext) | Status |
|---|---|---|---|
| **Gruppierungsstrategie** | (Label) | Wie die Teams auf die Gruppen verteilt werden. | ✅ |
| **Snake / Reissverschluss** | `PoolGroupingStrategy.snake` | Staerkste und schwaechste Teams abwechselnd verteilt → ausgeglichene Gruppen. | 🔁 (heute "Snake (Schweizer-Liga)" → "Schweizer" raus) |
| **Blockweise (gesetzt)** | `PoolGroupingStrategy.seeded` | Top-Teams der Reihe nach auf die Gruppen verteilt. | 🔁 |
| **Zufall** | `PoolGroupingStrategy.random` | Zufaellige Verteilung, mit Seed reproduzierbar. | 🔁 |

---

## 4. Setzung (Seeding)

Zwei verschiedene Achsen, sauber zu trennen:

**A) KO-Setzung — woher die Setzliste fuer den KO-Baum kommt:**

| User-Wort | Code | Bedeutung (Klartext) | Status |
|---|---|---|---|
| **Automatisch (aus Rangliste)** | `SeedingMode.auto` | Setzliste aus der Vorrunden-Rangliste. | ✅ |
| **Manuell** | `SeedingMode.manual` | Du legst die Setzliste selbst fest. **Wann/wo:** nach der Vorrunde auf einem eigenen Setzlisten-Screen (Qualifikanten per Drag&Drop sortieren), dann KO starten. Start gesperrt bis gespeichert. Geht um die **Setz-Reihenfolge**, NICHT um Feldnummern. | ✅ |
| **Aus ELO-Wertung** | `tournament_autoseed_from_elo` | Setzliste aus den ELO-Wertungen der Teams. | ✅ |

**B) Kanten-Setzung — wie Teams von einer Stufe in die naechste uebergehen (Stufen-Graph):**

| User-Wort | Code | Bedeutung (Klartext) | Status |
|---|---|---|---|
| **Reihenfolge uebernehmen** | `StageSeedingIn.orderPreserving` | Weitergeleitete Teams behalten die Reihenfolge der Quell-Stufe. | 🔁 |
| **Neu setzen nach Quell-Rang** | `StageSeedingIn.reseedBySourceRank` | Teams werden nach ihrem Rang in der Quell-Stufe neu gesetzt. | 🔁 |
| **Manuell** | `StageSeedingIn.manual` | Du legst die Setzung selbst fest. **Heute halbfertig:** auswaehlbar + gespeichert, aber KEIN Lauf-Flow und keine Engine-Auswertung (wie #10f-Runtime). | ❓ |

**Wann passiert manuelle Kanten-Setzung?** Wird im Redesign gebaut: beim Abschluss der Quell-Stufe oeffnet sich ein Setz-Schritt (analog zum KO-Setzlisten-Screen), bevor die naechste Stufe startet. ✅

---

## 5. KO-/Runden-Config (pro Runde, NICHT pro Match) — nur KO-Stufen

| User-Wort | Bedeutung (Klartext) | Status |
|---|---|---|
| **Begegnungen** | Wer gegen wen: **Beste vs. Schlechteste** oder **1. vs. 2.** | ✅ |
| **Saetze zum Sieg** | Wieviele gewonnene Saetze fuer den Matchsieg. | ✅ |
| **Zeit pro Match** | Zeitlimit pro Begegnung. | ✅ |
| **Pause danach** | Pause nach der Runde. | ✅ |
| **Tiebreak** | An/Aus. Wenn an → Methode noetig. **Nur bei KO-Stufen.** | ✅ |

**Vorrunde:** KEIN Tiebreak. Begegnungen duerfen unentschieden enden, die Rangliste entscheidet. ✅

---

## 6. Tiebreak-Methode (nur KO)

| User-Wort | Code (ist) | Bedeutung | Status |
|---|---|---|---|
| **Klassisch** | `KoTiebreakMethod.classicKingtossRemoval` | Herkömmlicher Entscheid ohne Zeit-Finisher. | ✅ |
| **Mighty-Finisher** | `KoTiebreakMethod.mightyFinisherShootout` | Zeit-Ablauf-Finisher: läuft eine zeitbegrenzte Partie ab, startet der Finisher und der Satz wird zu Ende gespielt. Steht es danach unentschieden, folgt ein Entscheidungssatz nach den festgelegten Finisher-Regeln. | ✅ |

Das bisherige Vorrunden-Tiebreak-Element ("Schweizer-konform") **entfällt** (Vorrunde hat keinen Tiebreak). ✅

> **Mighty-Finisher ≠ Shoot-out.** Der Code-Identifier `mightyFinisherShootout`
> ist irreführend benannt: der Mighty-Finisher ist der oben beschriebene
> Zeit-Ablauf-Finisher, NICHT ein Shoot-out. Das Shoot-out ist ein anderes
> Konzept — der Übergang Vorrunde→K.-o. bei platzierungsrelevantem
> Unentschieden (siehe `docs/vorrunde-rangfolge.md`).

---

## 7. Feld / Spielfeld / Pitch / Platz  ✅ geklaert

Ein **Feld** (= Spielfeld = Pitch = Platz) ist der Ort, auf dem **eine Begegnung** ausgetragen wird.
**1 Begegnung = 1 Feld** — die Anzahl ist gekoppelt und identisch: pro Runde gibt es genauso viele Felder wie Begegnungen. Ohne Feld keine Begegnung, ohne Begegnung kein Feld.

- **Begegnung** (Partie/Match): zwei Parteien spielen gegeneinander. Im Turnierbaum eine Kachel **F1..Fn**.
- **Feld**: der Platz, auf dem die Begegnung Fx laeuft. Kachel und Feld sind dasselbe Ding, 1:1.

**Folge:** Die Feld-/Pitch-Anzahl ergibt sich aus der Teilnehmerzahl der Runde (Runde 1 = N/2 Felder) — es gibt keine separat gesetzte feste Pitch-Zahl mehr.

---

## 8. Vorlagen (Presets) & Sichtbarkeit

| Konzept | User-Wort (soll) | Code (ist) | Bedeutung | Status |
|---|---|---|---|---|
| Vorlage | **Vorlage** / **Preset** | `StageGraphTemplate` | Gespeicherter, wiederverwendbarer Stufen-Graph inkl. aller Configs (inkl. Pitches). | ✅ |
| Sichtbarkeit: nur Team | **Privat (mein Team)** | `TemplateVisibility.club` | Nur Leute mit Setup-Berechtigung im selben Team/Organisation. | 🔁 (Wort) |
| Sichtbarkeit: alle | **Oeffentlich** | `TemplateVisibility.public` | Alle Organisatoren koennen die Vorlage nutzen. | 🔁 (Wort) |

**Festgelegt:** Zwei Sichtbarkeiten — **Privat (mein Team)** und **Oeffentlich**. Die heutige Dritt-Stufe "nur ich" (`private`) faellt weg. ✅

Gilt fuer **beide** Welten: den bisherigen Stufen-Graph UND den neuen, in dem man einen eigenen Stufentyp baut. Auch ein selbst modellierter Stufentyp muss als Vorlage speicher- und teilbar sein (privat/oeffentlich). ✅

**Preset-Regel (aus deinem Text):** Ein Preset selbst aendert sich nie. Bearbeiten = es wird auf einer **Kopie** gespielt/editiert. Eine bearbeitete Kopie kann als eigene Vorlage gespeichert werden. ✅

---

## 9. Manuelle Zuteilung  ✅ geklaert

"Manuelle Zuteilung" = die **manuelle KO-Setzung** (Abschnitt 4-A "Manuell"): nach der Vorrunde auf dem Setzlisten-Screen die Reihenfolge selbst festlegen. Die anderen beiden manuellen Stellen sind separat und bleiben wie sie sind:
- **Pitch-Reihenfolge**: direkt im Setup-Wizard. ✅ passt
- **Pitch-pro-Gruppe**: direkt im Setup-Wizard. ✅ passt

---

## 10. Status-Begriffe (Turnier-Lebenszyklus)

| User-Wort | Code | Bedeutung | Status |
|---|---|---|---|
| **Abgebrochen** | `TournamentStatus.aborted` | Turnier wurde abgebrochen. Kann fortgesetzt oder bearbeitet werden. | ✅ |

---

## 11. Stufen-Graph — Zweck (aus deinem Text, fuer das spaetere Redesign)

Der Stufen-Graph soll **zweierlei** voll konfigurierbar machen:
1. **Ablauf** zwischen Stufen (existiert: Knoten + Kanten).
2. **Die Stufentypen selbst** — als modellierbarer **Turnierbaum**: Runde fuer Runde Begegnungen anlegen, Sieger-/Verlierer-Kanten setzen (auch offen lassbar), KO reduziert, Vorrunde bleibt gleich. Pro Runde KO-Config (Abschnitt 5).

Details + Design-Vorschlag folgen, nachdem die offenen Fragen (Abschnitt 12) geklaert sind.

---

## 12. Offene Entscheidungen

Geklaert:
- **C1 (Felder):** 1 Begegnung = 1 Feld, gekoppelt, gleiche Anzahl. → Abschnitt 7. ✅
- **Tiebreak-Vorrunde:** Vorrunde hat keinen Tiebreak; Element entfaellt. ✅
- **Code-Rename:** Ja, Code-Identifier werden mitgezogen (`swiss`→`schoch`, `pool`→`groupPhase`, …). Groesserer Refactor inkl. Migrations-Beruehrung. ✅

Auch geklaert:
- **M (Manuelle Zuteilung):** = manuelle KO-Setzung (Setzlisten-Screen nach der Vorrunde). → Abschnitt 9. ✅
- **Sichtbarkeit:** Privat (Team) + Oeffentlich, fuer beide Welten; "nur ich" weg. → Abschnitt 8. ✅

Auch geklaert:
- **Kanten-Setzung-Woerter** (B): passen so. ✅

Auch geklaert:
- **Seeding "Aus ELO-Wertung"**: behalten, so benannt. ✅
- **Manuelle Kanten-Setzung**: Flow im Redesign bauen (Setz-Schritt vor Start der naechsten Stufe). ✅

**Glossar v1.0 — abgenommen.** Ab hier wird umgesetzt.

---

## 13. Refactor-Ableitung (kommt nach Einigung)
Aus dem fertigen Glossar leiten wir ab:
1. ARB-Strings (User-Wording) vereinheitlichen.
2. Code-Identifier angleichen (optional, siehe C-Rename).
3. Info-Texte = die "Bedeutung"-Spalten, ein Info-Button pro Setup-Element.
