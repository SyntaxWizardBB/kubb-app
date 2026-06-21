# Setup-Wizard — Addendum (abgestimmte Verbesserungen)

> Von Lukas gemeldete Verbesserungen, mit ihm geklaert. Zwei Stroeme:
> (A) Wizard-Tweaks (eigener kleiner Batch), (B) Seeding/Gruppierung (gehoert in
> die stage-seeding-spec-Umsetzung).

## A) Pitches

1. **Deduplizierung:** Manuell erfasste Pitchnummern werden dedupliziert.
2. **Mindest-Anzahl:** Es muessen **mindestens ceil(maxTeilnehmer / 2)** eindeutige
   Pitchnummern vorhanden sein (Beispiel: 81 Teilnehmer -> 41 Pitches). Gezaehlt
   werden eindeutige Nummern, nicht die Range-Breite — `1-40` reicht bei 81 nicht,
   `1-41` schon. Weniger blockiert das Anlegen; mehr ist erlaubt (z.B. grosse Halle).
   Konsistent mit "1 Begegnung = 1 Feld" (glossar.md, Abschnitt 7).
3. **Pro-Gruppe-Zuteilung exklusiv + dynamisch:** Ein Pitch gehoert genau einer
   Gruppe. Waehlt man Pitch 10 in Gruppe A, verschwindet Pitch 10 dynamisch aus
   den Chips aller anderen Gruppen.

## B) Gruppierungsstrategie / Seeding (stage-seeding-spec)

- Setz-Quellen: **ELO / Zufall / Manuell / aus Vorrunde** (per Spec).
- **ELO-Basis: Team-ELO** (Summe der Roster-ELO; existiert via `tournament_autoseed_from_elo`).
- **Cold-Start** (keine verlaesslichen ELO-/Liga-Daten): Default **Zufall**
  (deterministisch, mit Seed reproduzierbar); **Manuell** jederzeit waehlbar.
- Die Gruppierungsstrategie verteilt anhand dieser Setz-Reihenfolge (Setzliste vs.
  Verteilung sauber trennen, stage-seeding-spec Abschnitt 3).

## C) Wizard-Tweaks

1. **Screen 2 (Teilnehmer) — Max-Teilnehmer-Erklaerung:** ergaenzen, dass bei
   Ueberanmeldung die weiteren Teams auf die **Warteliste** kommen und Stueck fuer
   Stueck nachruecken, wenn sich Teams abmelden oder von Setup-Berechtigten entfernt
   werden. (Warteliste existiert serverseitig: registration `waitlist`, Nachruecken
   nach `registered_at`.)
2. **KO-Typ -> Screen 4:** Die KO-Typ-Wahl gehoert nicht in die Vorrunden-/Format-
   Config (Screen 3), sondern in die KO-Config (Screen 4). Screen 3 entscheidet nur
   Vorrunde / Format-Modus.
3. **Schoch-Runden:** Regler durch **Zahleneingabe** ersetzen.
4. **KO-Config Tiebreak:** Kein separates "Tiebreak nach"-Zeitfeld mehr. Der
   Tiebreak startet automatisch nach Ablauf von "Zeit pro Match". Die **Turnier-Uhr
   haelt an**, bis das Tiebreak-Ergebnis eingetragen ist (Halte-Mechanik existiert in
   `match_timer.dart` / "held clock").
