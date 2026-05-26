# M2 Demo Script — Round-Robin-then-KO mit Bronze

> Dauer: ~20 Min
> Setup: Tablet (Organizer/Veranstalter) + 4 Phones (Players)
> Stand: 2026-05-26

## Voraussetzungen

- Supabase Frankfurt mit Migrations `20260601000010..16` applied (Owner-Action `supabase db push` aus `supabase/migrations/`).
- 4 Test-Accounts angelegt und auf den Phones eingeloggt: `alpha`, `beta`, `gamma`, `delta`. Owner ist auf dem Tablet als separater Account `owner-demo` eingeloggt.
- Wir nutzen Format `round_robin_then_ko` mit 4 Teilnehmern statt 8 — Vorrunde dauert dann 6 Spiele statt 28, was im 20-Min-Fenster passt. Bracket-Logik ist identisch (Top-4 → 2 Halbfinals + Finale + Spiel um Platz 3). Falls die volle 8-Spieler-Variante gezeigt werden soll, Dauer auf ~45 Min einplanen.
- App-Build aus `main` mit M2.3 abgeschlossen, Region Frankfurt.

## Schritt 1: Setup-Wizard, Format wählen (3 Min)

**Aktion**: Owner öffnet auf dem Tablet "Neues Turnier" und durchläuft die Wizard-Schritte 1–4: Name "Demo M2", Datum heute, Liga-relevant=ja, Format=`round_robin_then_ko`. Die Schrittanzeige springt nach Format-Wahl auf "Schritt 4 von 6".

**Erwartung**: Wizard zeigt dynamisch zwei zusätzliche Schritte (KO-Konfig, Tiebreaker-Reihenfolge). Der "Liga-relevant=ja"-Default propagiert in Schritt 5 als Bronze=ja.

## Schritt 2: KO-Konfig und Tiebreaker-Reihenfolge (2 Min)

**Aktion**: Schritt 5: Qualifier-Anzahl=4, Spiel um Platz 3=ja, Seeding-Modus=Auto-from-Standings. Schritt 6: Tiebreaker-Chain mit Drag-Reorder anpassen — Owner zieht "Direktvergleich" über "Satzverhältnis", bestätigt mit "Erstellen".

**Erwartung**: Detail-Screen des neuen Turniers öffnet sich, Status "Setup", `ko_config` ist serverseitig persistiert (kurzer Supabase-Studio-Blick optional).

## Schritt 3: Registrierung der vier Spieler (2 Min)

**Aktion**: Auf jedem Phone öffnen `alpha…delta` das Turnier per Code/QR und drücken "Anmelden". Owner auf dem Tablet öffnet "Anmeldungen" und approved alle vier nacheinander.

**Erwartung**: Teilnehmerliste füllt sich live auf 4/4. Phone-Seite zeigt "Approved — warte auf Start".

## Schritt 4: Vorrunde starten und Round-Robin spielen (5 Min)

**Aktion**: Owner drückt "Turnier starten". Bei 4 Teilnehmern werden 6 Round-Robin-Matches generiert. Die vier Spieler spielen ihre Matches durch und tragen die Set-Scores auf den Phones ein (jeweils Best-of-3, abgekürzt mit eindeutigen Scores um Konflikt-Screens zu vermeiden).

**Erwartung**: Standings-Tab auf dem Tablet aktualisiert sich nach jedem finalisierten Match (Polling 5 s). Nach 6 Matches stehen alle vier Teilnehmer mit eindeutigen Plätzen 1–4.

## Schritt 5: Seeding-Editor und manuelle Override (2 Min)

**Aktion**: Owner drückt "Vorrunde abschliessen". Der Seeding-Editor zeigt die vier Spieler in der von der Tiebreaker-Chain vorgeschlagenen Reihenfolge. Owner tauscht Seed 3 und Seed 4 per Drag und bestätigt mit "Seeding speichern".

**Erwartung**: Audit-Event `seeding_set` wird geschrieben. Die getauschte Reihenfolge bleibt sichtbar, "KO starten"-Button wird aktiv.

## Schritt 6: KO-Phase starten, Bracket erscheint (1 Min)

**Aktion**: Owner drückt "KO starten".

**Erwartung**: Navigation in den Bracket-Tab. Sichtbar: zwei Halbfinale-Karten (Seed 1 vs. 4, Seed 2 vs. 3), eine Finale-Karte rechts daneben, separat das Spiel um Platz 3. Phones der vier Spieler zeigen ihr jeweils nächstes Halbfinale-Match im "Mein Spiel"-Bereich.

## Schritt 7: Halbfinals spielen, Sieger rücken automatisch ins Finale (2 Min)

**Aktion**: Die zwei Halbfinals werden auf den Phones gespielt und finalisiert.

**Erwartung**: Sobald ein Halbfinale finalisiert ist, erscheint der Sieger als Teilnehmer im Finale und der Verlierer im Spiel um Platz 3 (Trigger `tournament_advance_ko_winner`). Bracket-View auf dem Tablet zeigt die neuen Slots befüllt. Owner kommentiert hier kurz das Walkover-Verhalten (wird in Schritt 7 nicht ausgelöst, ist nur erklärt).

## Schritt 8: Finale und Spiel um Platz 3 (2 Min)

**Aktion**: Die zwei Finalisten spielen das Finale, parallel spielen die zwei Halbfinal-Verlierer das Spiel um Platz 3.

**Erwartung**: Beide Matches finalisieren, Bracket-View zeigt Sieger-Badges. Tournament-Status wechselt auf `completed` sobald beide Finalspiele finalized sind.

## Schritt 9: Endrangliste (1 Min)

**Aktion**: Owner öffnet den Standings-Tab.

**Erwartung**: Plätze 1 und 2 aus dem Finale, Platz 3 aus dem Bronze-Match, Platz 4 als Bronze-Verlierer. Bei der 8-Spieler-Variante würden die Plätze 5–8 aus den Vorrunden-Standings (Tiebreaker-Chain) übernommen — bei 4 Spielern entfällt das. Owner-Abnahme M2 abgeschlossen.
