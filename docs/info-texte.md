# Info-Texte — Turnier-Setup-Wizard

> Soll-Texte für die Info-Buttons im Setup-Wizard. Pro auswählbarem oder
> konfigurierbarem Element ein kurzer Erklärungstext (1–3 Sätze), den der
> Organisator über das kleine "i"-Symbol öffnet. Reviewbare Bibliothek —
> noch nicht im Code verdrahtet (ausser den vier markierten).
>
> Schreibregeln: nicht technisch, anfängertauglich (auch ohne Kubb-Vorwissen
> bedienbar), Auswirkung UND Zeitpunkt nennen, Schweizer Schriftdeutsch mit
> echten Umlauten und ss statt ß. Was inhaltlich (v. a. Kubb-Regeln) nicht
> sicher belegt ist, trägt den Status `TODO: mit Lukas klären` statt einer
> geratenen Erklärung.
>
> Status-Werte:
> - `neu` — Text hier neu geschrieben, im Code noch nicht hinterlegt.
> - `bereits verdrahtet` — der Text existiert schon im Code; hier zur Kontrolle
>   übernommen.
> - `TODO: mit Lukas klären` — Bedeutung aus den Quellen nicht sicher belegbar.

---

## Schritt 1 — Stammdaten

**Turniername** — *Name des Turniers* — Der Name, unter dem dein Turnier in
der Liste und für alle Teilnehmer erscheint. Die App hängt automatisch die
Jahreszahl an (z. B. "Frühlingscup 2026"). — Status: `neu`

**Club-Auswahl** — *Wer richtet aus?* — Wählst du einen Club, zählt das
Turnier als offizielles, für die Liga wertbares Vereinsturnier. Wählst du
"Spasstournier – ohne Wertung", ist es ein privates Turnier ohne Liga-Bezug,
und du kannst es auf Einladung beschränken. — Status: `neu`

**Liga-Kategorien** — *Für welche Liga zählt es?* — Legt fest, in welche
Liga-Wertung die Ergebnisse einfliessen. Nur bei einem Vereinsturnier sicht-
und auswählbar; ein Spasstournier hat keine Liga-Kategorie. — Status: `neu`

**Auf Einladung** — *Nur eingeladene Spieler* — Wenn aktiv, können sich nicht
alle frei anmelden — nur die Spieler, die du unten gezielt einlädst, dürfen
mitspielen. Die Einladungen werden nach dem Anlegen des Turniers verschickt.
Nur für Spassturniere ohne Club. — Status: `neu`

**Eingeladene Spieler** — *Wen einladen?* — Such die Spieler über den Namen
und tippe "Einladen". Nur diese erhalten Zugang zum Turnier. Du kannst Einträge
jederzeit wieder entfernen, bevor du das Turnier anlegst. — Status: `neu`

**Ort** — *Wo wird gespielt?* — Der Veranstaltungsort, kurz benannt (z. B.
"Sportplatz Brügg"). Erscheint in der Turnierübersicht. — Status: `neu`

**Adresse** — *Genaue Anschrift* — Die vollständige Adresse zum Anfahren. Hilft
den Teilnehmern, den Spielort zu finden. — Status: `neu`

**Startdatum** — *Wann geht es los?* — Datum und Uhrzeit, an denen das Turnier
beginnt. — Status: `neu`

**Registrierungs-Deadline** — *Anmeldeschluss* — Bis zu diesem Zeitpunkt können
sich Teilnehmer anmelden. Danach ist keine neue Anmeldung mehr möglich. —
Status: `neu`

**Check-in bis** — *Einchecken bis* — Bis dahin müssen angemeldete Teilnehmer
vor Ort bestätigen, dass sie da sind. Wer bis dahin nicht eingecheckt hat, kann
aus der Spielplanung fallen. — Status: `neu`

**Scoring (EKC / Classic)** — *Zählweise der Sätze* — Bestimmt, wie ein
einzelner Satz gewertet wird. Bei EKC zählt jeder Feldkubb einen Punkt. Bei
Classic zählt nur der Satzsieger — Sätze, die nicht zu Ende gespielt werden,
fliessen nicht in die Wertung ein. Diese Wahl gilt für alle Spiele des
Turniers. — Status: `neu`

**Sureshot** — *Sonderregel Sureshot* — Schaltet die Sureshot-Variante für alle
Spiele ein. Mit Sureshot muss die Königsfigur am Ende eines Satzes durch die
Beine hindurch abgeworfen werden statt normal im Stehen. Lässt sich ein- und
ausschalten. — Status: `neu`

**Diggy** — *Sonderregel Diggy* — Schaltet die Diggy-Variante für alle Spiele
ein. Liegt beim Einwerfen ein Kubb auf einem anderen und dabei im Spielfeld
(also ein gültiger Einwurf), darf das einwerfende Team ihn platzieren. —
Status: `neu`

**Strafkubb ausserhalb Basislinie** — *Strafkubb-Platzierung* — Ein Strafkubb
entsteht, wenn ein eingeworfener Kubb nach dem zweiten Versuch nicht gültig
steht; der Gegner darf ihn frei aufstellen. Ist diese Option aktiv, muss der
Strafkubb 30 cm (eine Stocklänge) Abstand zum König und zur Baseline haben. —
Status: `neu`

**Anspielregel (2-4-6 vs. frei)** — *Eröffnung* — "2-4-6" heisst: in der ersten
Runde werden 2 Wurfstöcke geworfen, in der zweiten 4, ab der dritten 6 — ein
sanfter Einstieg. "Frei" lässt die Eröffnung offen. Gilt für alle Spiele. —
Status: `neu`

**Regelwerk-PDF** — *Regeln als PDF* — Optionales Dokument mit den Turnierregeln,
das Teilnehmer einsehen können. — Status: `neu`

**Lageplan-PDF** — *Lageplan als PDF* — Optionaler Plan des Spielgeländes (Felder,
Anfahrt, Infrastruktur) zum Herunterladen. — Status: `neu`

**Eintrittsgebühr** — *Startgeld* — Betrag, den Teilnehmer zahlen. Leer oder 0
bedeutet kostenlos ("Gratis"). — Status: `neu`

**Zahlmethoden** — *Wie bezahlt wird* — Wähle, welche Zahlungsarten du vor Ort
akzeptierst (Bar, TWINT, Karte). Mehrfachauswahl möglich. — Status: `neu`

**Ansprechperson (Name / Telefon)** — *Kontakt für Rückfragen* — Name und
Telefonnummer der Person, die Teilnehmer bei Fragen erreichen. Optional. —
Status: `neu`

**Info-Texte (Verpflegung / Anreise / Unterkunft / Wetter)** — *Hinweise für
Teilnehmer* — Freitextfelder für praktische Infos rund ums Turnier. Erscheinen
in der Turnierbeschreibung; alle optional. — Status: `neu`

---

## Schritt 2 — Teilnehmer

**Teamgrösse (Minimum)** — *Kleinste Teamgrösse* — Wie viele Spieler ein Team
mindestens haben muss. Bei 1 spielen Einzelpersonen. — Status: `neu`

**Max. Spieler pro Team** — *Grösste Teamgrösse* — Wie viele Spieler ein Team
höchstens haben darf. Liegt dieser Wert über dem Minimum, sind Teams
unterschiedlicher Grösse erlaubt. — Status: `neu`

**Maximale Teilnehmerzahl** — *Teilnehmer-Obergrenze* — Wie viele Teams sich
höchstens anmelden dürfen. Ist das Limit erreicht, sind keine weiteren
Anmeldungen möglich. — Status: `neu`

---

## Schritt 3 — Format

**Format-Modus (Klassisch vs. Stufen-Graph)** — *Wie das Turnier aufgebaut ist*
— "Klassisch" führt durch den gewohnten Ablauf: eine Vorrunde und danach ein
K.-o. "Stufen-Graph" ist für Fortgeschrittene: du baust den Turnierablauf aus
einzelnen Stufen selbst zusammen und verbindest sie. Im Stufen-Graph-Modus
entfällt der separate K.-o.-Schritt — die K.-o.-Stufen baust du direkt im
Graphen. — Status: `neu`

**Vorrunde-Typ (Keine / Gruppenphase / Schoch)** — *Wie die Vorrunde läuft* —
Bestimmt, wie gespielt wird, bevor das K.-o. beginnt. "Gruppenphase": jeder
spielt in seiner Gruppe gegen jeden, die Bestplatzierten ziehen weiter. "Schoch":
ein gemeinsamer Pool, die Paarungen werden nach jeder Runde neu nach Tabellenstand
gebildet — gut für grosse Felder. — Status: `neu`

**KO-Typ (Einfach / Doppelt / Trostturnier)** — *Welcher K.-o.-Baum* — Steuert,
wie das Ausscheiden funktioniert: bei "einfach" ist man nach einer Niederlage raus,
bei "doppelt" erst nach der zweiten, und das "Trostturnier" gibt früh
Ausgeschiedenen einen Nebenwettbewerb. Ausführliche Erklärung im
"K.-o.-Systeme erklärt"-Sheet (siehe unten). — Status: `neu`

**Max. Sätze** — *Sätze pro Spiel (Vorrunde)* — Die höchstmögliche Anzahl
Sätze, die ein Vorrunden-Spiel dauern darf. In der Vorrunde dürfen Spiele
unentschieden enden; die Rangliste entscheidet über das Weiterkommen. —
Status: `neu`

**Anzahl Gruppen** — *In wie viele Gruppen* — Wie viele Gruppen in der
Gruppenphase gebildet werden. Aus jeder Gruppe ziehen gleich viele Teams ins
K.-o. — diese Zahl muss zur K.-o.-Grösse passen (sie wird im nächsten Schritt
geprüft). — Status: `neu`

**Gruppierungsstrategie** — *Wie Teams auf Gruppen verteilt werden* — Legt fest,
nach welchem Prinzip die Teams den Gruppen zugeordnet werden. Die drei Optionen
(Reissverschluss, Blockweise, Zufall) sind unten einzeln erklärt. — Status: `neu`

**Gruppierung: Snake / Reissverschluss** — *Reissverschluss* — Reissverschluss:
stärkste und schwächste Teams werden abwechselnd auf die Gruppen verteilt,
damit die Gruppen etwa gleich stark sind. — Status: `bereits verdrahtet`

**Gruppierung: Blockweise (gesetzt)** — *Blockweise nach Setzung* — Blockweise
nach Setzung: die Top-Teams werden der Reihe nach auf die Gruppen verteilt. —
Status: `bereits verdrahtet`

**Gruppierung: Zufall** — *Zufall* — Zufällige Verteilung auf die Gruppen. Mit
gesetztem Seed reproduzierbar. — Status: `bereits verdrahtet`

**Random-Seed** — *Startwert für die Zufallsverteilung* — Eine Zahl, die die
zufällige Gruppierung steuerbar macht: derselbe Seed erzeugt immer dieselbe
Verteilung. Lässt du das Feld leer, wird jedes Mal neu gemischt. — Status: `neu`

**Qualifikanten pro Gruppe** — *Wie viele pro Gruppe weiterkommen* — Wird
automatisch aus K.-o.-Grösse geteilt durch Anzahl Gruppen berechnet — du legst
ihn nicht selbst fest. Zeigt "—", solange die K.-o.-Grösse noch nicht gewählt
ist. — Status: `neu`

**Platz-Zuteilung pro Gruppe** — *Welche Felder für welche Gruppe* — Ordnet jeder
Gruppe (A, B, C, …) die Felder zu, auf denen ihre Spiele laufen. Ein Feld darf
mehreren Gruppen dienen. Nur in der Gruppenphase und nur, wenn du Felder angelegt
hast. — Status: `neu`

**Schoch-Runden** — *Anzahl Schoch-Runden* — Wie viele Runden im Schoch-Modus
gespielt werden. Mehr Runden trennen die Tabelle sauberer — bei grossen Feldern
zu empfehlen. Die Paarungen jeder Runde entstehen live nach Tabellenstand. —
Status: `neu`

**Match-Zeit** — *Zeit pro Spiel* — Zeitlimit für eine einzelne Begegnung, in
Minuten. — Status: `neu`

**Pause zwischen Matches** — *Pause nach einem Spiel* — Wie lange nach einem Spiel
pausiert wird, bevor das nächste auf demselben Feld startet, in Minuten. 0 heisst
keine Pause. — Status: `neu`

---

## Schritt 4 — Stufen-Graph (eingebettet)

> Diese Elemente erscheinen im Stufen-Graph-Modus innerhalb des eingebetteten
> Builders. Hier baust du den Turnierablauf aus Stufen (Knoten) und Verbindungen
> (Kanten) zusammen.

**Template-Auswahl** — *Vorlage wählen* — Statt alles neu zu bauen, kannst du
eine gespeicherte Vorlage laden und als Ausgangspunkt nutzen. Anwenden übernimmt
die komplette Konfiguration der Vorlage in deinen Aufbau. — Status: `neu`

**Stufen-Name** — *Name der Stufe* — Frei wählbarer Name, um die Stufe im
Graphen zu erkennen (z. B. "Gruppenphase", "Hauptbaum"). Der Name lässt sich
nicht mehr ändern, solange Kanten daran hängen. — Status: `neu`

**Stufentyp** — *Stufentyp* — Bestimmt, wie in dieser Stufe gespielt wird. Die
einzelnen Typen sind unten erklärt. — Status: `bereits verdrahtet`

**Stufentyp: Gruppenphase** — *Gruppenphase* — Jeder spielt in seiner Gruppe gegen
jeden. Aus jeder Gruppe ziehen die Bestplatzierten weiter. Bei n Teilnehmern pro
Gruppe sind das n-1 Runden. — Status: `bereits verdrahtet`

**Stufentyp: Schoch** — *Schoch* — Schoch: die Paarungen werden nach jeder Runde
neu nach Tabellenstand gebildet — Sieger gegen Sieger, Verlierer gegen Verlierer.
Flexible Rundenzahl, ein gemeinsamer Pool. Ideal für grosse Felder, weil nicht
jeder gegen jeden spielen muss. — Status: `bereits verdrahtet`

**Stufentyp: K.-o. (einfach)** — *K.-o. (einfach)* — Wer ein Spiel verliert, ist
raus. Schnell und kurz, aber eine einzige Niederlage beendet das Turnier. —
Status: `bereits verdrahtet`

**Stufentyp: K.-o. (doppelt)** — *K.-o. (doppelt)* — Erst nach der zweiten
Niederlage ist man raus (Verliererbracket). Fairer als einfaches K.-o., braucht
aber mehr Spiele und Zeit. — Status: `bereits verdrahtet`

**Stufentyp: Trosttournier** — *Trosttournier* — Nebenwettbewerb für früh
ausgeschiedene Teams, damit sie weiterspielen. Beeinflusst die Hauptwertung nicht.
— Status: `bereits verdrahtet`

**Seeding-Quelle der Stufe** — *Woher die Startreihenfolge kommt* — Legt fest,
woher die Setzliste für diese Stufe stammt: aus der ELO-Wertung, aus einer
Vorrangliste, von dir manuell gesetzt, oder "wie geroutet" (in der Reihenfolge,
in der die Teams aus der vorherigen Stufe ankommen). — Status: `neu`

**Gruppen-Config: Gruppenzahl** — *Anzahl Gruppen* — In wie viele Gruppen das Feld
dieser Stufe aufgeteilt wird. — Status: `neu`

**Gruppen-Config: Qualifikanten pro Gruppe** — *Wie viele pro Gruppe weiterkommen*
— Qualifikanten zählen pro Gruppe, nicht über alle Gruppen zusammen: bei 2
ziehen die besten 2 jeder Gruppe weiter. — Status: `neu`

**KO-Config: Matchup (Beste vs. Schlechteste / 1. vs. 2.)** — *Wer gegen wen* —
Bestimmt die Paarungen im K.-o. "Beste vs. Schlechteste" lässt die stärksten
gegen die schwächsten antreten, "1. vs. 2." paart benachbarte Ränge. —
Status: `neu`

**KO-Config: Tiebreak-Methode** — *Entscheid bei Gleichstand* — Wie ein
unentschiedenes K.-o.-Spiel entschieden wird: "Klassisch" oder
"Mighty-Finisher". Beim Mighty-Finisher wird ein zeitbegrenztes Spiel zu Ende
gespielt, sobald die Zeit abgelaufen ist; steht es danach unentschieden, folgt
ein Entscheidungssatz nach den festgelegten Finisher-Regeln. "Klassisch" ist der
herkömmliche Entscheid ohne Zeit-Finisher. Nur im K.-o. relevant, die Vorrunde
hat keinen Tiebreak. — Status: `neu`

**KO-Config: Grand-Final-Reset** — *Zweites Finale möglich* — Nur beim doppelten
K.-o.: gewinnt das Team aus dem Verliererbaum das erste Finale, gibt es ein
zweites, entscheidendes Finale (beide haben dann genau eine Niederlage). —
Status: `neu`

**KO-Config: Anzahl K.-o.-Runden** — *Wie viele Runden* — Legt fest, über wie
viele Runden der K.-o.-Baum dieser Stufe gespielt wird. — Status: `neu`

**KO-Runde: Sätze / Zeit / Pause / Tiebreak (pro Runde)** — *Regeln je Runde* —
Pro K.-o.-Runde einstellbar: wie viele Sätze zum Sieg nötig sind, das Zeitlimit
pro Spiel, die Pause danach und ob ein Tiebreak greift. Spätere Runden dürfen
länger angesetzt sein als frühe. — Status: `neu`

**Kante: Von / Zu** — *Verbindung zwischen Stufen* — Eine Kante leitet Teilnehmer
von einer Stufe (Von) in die nächste (Nach) weiter. So baust du den Ablauf
zusammen. Eine Stufe darf mehrere Kanten haben — z. B. Sieger ins Hauptbaum UND
Verlierer in einen Neben-Cup. — Status: `neu`

**Kante: Selektor — Top-K** — *Top K* — Die besten K jeder Quell-Stufe ziehen
weiter — z. B. Top 2 jeder Gruppe. — Status: `neu`

**Kante: Selektor — Ränge** — *Ränge von–bis* — Ein zusammenhängender
Rangbereich der Quell-Stufe zieht weiter — z. B. Ränge 3–4 für ein zweites
Tableau. — Status: `neu`

**Kante: Selektor — Verlierer-Runden** — *Verlierer bestimmter Runden* — Verlierer
bestimmter K.-o.-Runden werden weitergeleitet — so speist man Trost-/Neben-Cups.
— Status: `neu`

**Kante: Selektor — Sieger** — *Sieger* — Alle Sieger der Quell-Stufe ziehen
weiter. — Status: `neu`

**Kante: Selektor — Nicht-Qualifizierte** — *Übrige* — Alle, die sich NICHT
qualifiziert haben, ziehen weiter — z. B. in einen Neben-Cup. — Status: `neu`

**Kanten-Seeding: Reihenfolge erhalten** — *Reihenfolge erhalten* — Die
weitergeleiteten Teams behalten die Reihenfolge aus der Quell-Stufe. — Status:
`bereits verdrahtet`

**Kanten-Seeding: Neu nach Quell-Rang** — *Neu nach Quell-Rang* — Die Teams werden
anhand ihres Rangs in der Quell-Stufe neu gesetzt, bevor sie in die nächste Stufe
gehen. — Status: `bereits verdrahtet`

**Kanten-Seeding: Manuell** — *Manuell* — Du legst die Setzung der weitergeleiteten
Teams selbst fest. Achtung: das kann den Phasenstart blockieren, bis die Setzung
gespeichert ist. — Status: `bereits verdrahtet`

---

## Schritt 5 — KO-Config (klassisch)

**KO-Bracket-Grösse** — *Wie viele Teams im K.-o.* — Wie viele Teams in den
K.-o.-Baum kommen (eine Zweierpotenz: 2, 4, 8, 16, …). Bei Gruppenphase muss
diese Zahl durch die Anzahl Gruppen teilbar sein, weil pro Gruppe gleich viele
weiterkommen. — Status: `neu`

**Seeding-Quelle: Automatisch aus Vorrunde** — *Setzliste aus der Vorrunde* — Die
Setzliste für den K.-o.-Baum wird automatisch aus der Vorrunden-Rangliste
gebildet. Du musst nichts von Hand sortieren. — Status: `neu`

**Seeding-Quelle: Manuell** — *Setzliste selbst festlegen* — Du legst die
Setzliste selbst fest. Das passiert nach der Vorrunde auf einem eigenen
Setzlisten-Screen, wo du die Qualifikanten per Ziehen sortierst. Erst wenn die
Setzliste gespeichert ist, lässt sich das K.-o. starten. — Status: `neu`

> Hinweis: Im klassischen K.-o.-Schritt gibt es nur die Quellen "Automatisch aus
> Vorrunde" und "Manuell". "Aus ELO-Wertung" als Quelle steht erst auf dem
> Setzlisten-Screen zur Verfügung (siehe Schritt 6).

**KO-Matchup (Beste vs. Schlechteste / 1. vs. 2.)** — *Wer gegen wen* — Bestimmt
die Paarungen im K.-o.-Baum. "Beste vs. Schlechteste" lässt die stärksten gegen
die schwächsten antreten, "1. vs. 2." paart benachbarte Ränge. — Status: `neu`

**KO-Tiebreak-Methode (Klassisch / Mighty-Finisher)** — *Entscheid bei Gleichstand*
— Wie ein unentschiedenes K.-o.-Spiel entschieden wird. "Mighty-Finisher" und
"Shoot-out" sind dabei nicht dasselbe. Der Mighty-Finisher wird gespielt, wenn
eine zeitbegrenzte Partie abläuft: der Finisher startet, sobald die Zeit abgelaufen
ist, und der laufende Satz wird zu Ende gespielt. Steht es danach unentschieden,
folgt ein Entscheidungssatz nach den festgelegten Finisher-Regeln. "Klassisch" ist
der herkömmliche Entscheid ohne Zeit-Finisher. Das Shoot-out ist ein anderes
Konzept (Übergang Vorrunde→K.-o. bei platzierungsrelevantem Unentschieden, siehe
`docs/vorrunde-rangfolge.md`). — Status: `neu`

**Trostturnier: Direkt-Starter** — *Wer direkt im Trostturnier startet* — Wie viele
Teams direkt aus der Vorrunde ins Trostturnier einsteigen, zusätzlich zu den im
Hauptbaum ausgeschiedenen. "Keine" heisst: nur Ausgeschiedene aus dem Hauptbaum.
— Status: `neu`

**Trostturnier: Name** — *Name des Trostturniers* — Pflichtfeld beim Trostturnier:
unter diesem Namen erscheint der Nebenwettbewerb. Ohne Namen kannst du nicht
weiter. — Status: `neu`

**KO-Runde: Sätze zum Sieg** — *Sätze zum Matchsieg* — Wie viele gewonnene Sätze
ein Team für den Sieg in dieser Runde braucht. — Status: `neu`

**KO-Runde: Match-Zeit** — *Zeit pro Spiel* — Zeitlimit für eine Begegnung dieser
Runde, in Minuten. — Status: `neu`

**KO-Runde: Pause danach** — *Pause nach der Runde* — Wie lange nach dieser Runde
pausiert wird, in Minuten. — Status: `neu`

**KO-Runde: Tiebreak an/aus** — *Tiebreak in dieser Runde* — Schaltet für diese
Runde den Tiebreak ein oder aus. Ist er aus, kann ein Spiel rein über die Zeit
entschieden werden, ohne Stechen. — Status: `neu`

**KO-Runde: Tiebreak nach** — *Tiebreak ab welcher Zeit* — Ab welcher Spielzeit
der Tiebreak greift, in Minuten. Nur sichtbar, wenn der Tiebreak für die Runde
eingeschaltet ist. — Status: `neu`

---

## Schritt 6 — Seeding-Screen

> Dieser Screen erscheint nach der Vorrunde, wenn du "Manuell" als
> Seeding-Quelle gewählt hast. Hier legst du die Startreihenfolge für den
> K.-o.-Baum fest, bevor er startet.

**Setzliste sortieren** — *Reihenfolge per Ziehen* — Lange auf einen Eintrag
tippen und ziehen, um die Setzreihenfolge zu ändern. Position 1 ist der höchste
Setzplatz. — Status: `neu`

**Setzliste speichern** — *Setzung sichern* — Speichert die aktuelle Reihenfolge.
Erst nach dem Speichern lässt sich das K.-o. starten. — Status: `neu`

**Auto wiederherstellen** — *Auf Gruppen-Reihenfolge zurücksetzen* — Setzt deine
manuellen Änderungen zurück auf die automatische Reihenfolge aus der Vorrunde.
— Status: `neu`

**Aus ELO-Wertung** — *Setzliste aus ELO übernehmen* — Füllt die Setzliste mit
der Reihenfolge aus den ELO-Wertungen der Teams. Du kannst danach trotzdem von
Hand nachsortieren. — Status: `neu`

**KO-Phase starten** — *K.-o. starten* — Startet die K.-o.-Phase mit der
gespeicherten Setzliste. Geht erst, wenn die Setzung gespeichert ist. —
Status: `neu`

---

## KO-Modell-Sheet ("K.-o.-Systeme erklärt")

> Wird über das Info-Symbol neben dem KO-System im Format-Schritt geöffnet.
> Erklärt die drei K.-o.-Modelle ausführlicher. Bereits im Code hinterlegt.

**Single-Out** — *Single-Out* — Eine Niederlage und du bist draussen. Der Final
entscheidet Platz 1 und 2, dazu gibt es ein Spiel um Platz 3. Schnell und einfach.
— Status: `bereits verdrahtet`

**Double-Elimination** — *Double-Elimination* — Du musst zweimal verlieren, um
auszuscheiden. Wer im Hauptbaum verliert, fällt in den Verliererbaum und kann
sich von dort bis ins Finale zurückkämpfen — der Verliererbaum-Sieger kann am
Ende noch Turniersieger werden. Sportlich am fairsten, aber mehr Spiele. —
Status: `bereits verdrahtet`

**Trostturnier** — *Trostturnier* — Der Hauptbaum entscheidet Platz 1 und 2
endgültig. Wer im Hauptbaum ausscheidet (ausser den Halbfinal-Verlierern, die um
Platz 3 spielen), kommt ins Trostturnier und spielt dort die hinteren Plätze aus.
Optional starten zusätzlich einige Teams direkt aus der Vorrunde im Trostturnier.
Es gibt keinen Weg zurück ins Finale — aber alle bekommen mehr Spiele und eine
Platzierung. — Status: `bereits verdrahtet`
