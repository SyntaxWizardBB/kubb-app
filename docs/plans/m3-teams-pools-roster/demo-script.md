# M3 Demo Script — Teams, Pools, Roster mit Pool-Phase und KO

> Dauer: ~45–60 Min
> Setup: Tablet (Veranstalter) plus drei Phones (Captains `cap-hammer`, `cap-block`, `cap-heli`)
> Stand: 2026-05-26

## Voraussetzungen

- Supabase Frankfurt mit allen M3-Migrationen applied (`teams`, `team_pools`, `team_pool_members`, `tournament_team_rosters`, `tournament_pool_assignments`, plus `tournament_pool_phase_*`-Felder).
- Test-DB-Seed liefert: drei Captain-Accounts, vierzehn Pool-Member-Accounts (Mischung registriert plus Gäste), Owner-Account `owner-demo`. Vier weitere Captain-Accounts samt Teams sind vorbereitet, sodass 16 Anmeldungen erreichbar sind (drei Captains demoen live, die übrigen Teams melden sich vor der Demo via Setup-Skript an).
- App-Build aus `main` mit M3.3 abgeschlossen, Region Frankfurt.
- Drei Phones eingeloggt, Tablet auf Owner-Account, alle Geräte im gleichen WLAN.

## Schritt 1: Teams gründen und Pools füllen (8 Min)

**Aktion**: Die drei Captains öffnen auf ihren Phones "Neues Team", gründen "Hammer-Crew", "Block-Mafia" und "Helikopter-Heroes". Jeder Captain fügt registrierte Mitglieder per Invite hinzu plus mindestens einen Gast-Spieler (Name, optional Geburtsjahr). Mitglieder bestätigen Invites auf ihren Phones.

**Erwartung**: Team-Detailscreen zeigt vollständigen Pool (Mitglieder plus Gäste). Captain-Badge erscheint für alle Mitglieder, nicht für Gäste. `FR-TEAM-1`, `FR-TEAM-4`, `FR-TEAM-5`, `FR-TEAM-6`, `FR-TEAM-9` sichtbar erfüllt.

## Schritt 2: Veranstalter legt 16-Team-Turnier an (5 Min)

**Aktion**: Owner öffnet auf dem Tablet "Neues Turnier", Wizard mit Name "Demo M3", Format `round_robin_then_ko`, Modus `teams`, `team_size=3`, Pool-Phase aktiviert mit 4 Gruppen, Top-2 qualifizieren, KO mit Spiel um Platz 3. Tiebreaker-Chain unverändert.

**Erwartung**: Turnier-Detail-Screen öffnet mit Status "Setup", Felder `pool_count=4`, `qualifiers_per_pool=2`, `bronze_match=true` persistiert. Anmelde-Code/QR sichtbar.

## Schritt 3: Captains melden Teams mit Roster-Auswahl an (8 Min)

**Aktion**: Jeder der drei Live-Captains öffnet das Turnier per Code, drückt "Team anmelden", wählt im Roster-Composition-Widget drei Spieler aus dem Pool aus (Drag in den Roster-Slot). Owner approved auf dem Tablet alle drei Anmeldungen plus die dreizehn vorab via Seed-Skript registrierten Teams.

**Erwartung**: Teilnehmerliste zählt live auf 16/16. Roster-Detail zeigt pro Team drei Spieler. `FR-TEAM-12`, `FR-REG-2` erfüllt. Owner drückt "Pool-Auslosung", System verteilt 16 Teams auf 4 Pools à 4 Teams (sichtbar im "Gruppen"-Tab).

## Schritt 4: Mid-Tournament-Substitution vor Pool-Start (5 Min)

**Aktion**: Captain "Hammer-Crew" meldet auf dem Phone "Spieler verletzt sich" — öffnet Roster-Edit, tauscht einen Roster-Spieler gegen ein anderes Pool-Mitglied (Drag-and-Drop im Substitution-Sheet), bestätigt mit Grund "Verletzung".

**Erwartung**: Audit-Event `roster_substitution` im Tournament-Audit-Log sichtbar (Owner-Tablet, Tab "Audit"). Neuer Roster-Eintrag aktiv, alter Eintrag als historisch markiert. `FR-TEAM-13`, `FR-TEAM-14` erfüllt.

## Schritt 5: Pool-Phase starten (2 Min)

**Aktion**: Owner drückt "Pool-Phase starten".

**Erwartung**: Pro Pool werden 6 Round-Robin-Matches generiert (insgesamt 24 Pool-Matches). Tab "Gruppen" zeigt 4 Tabellen mit je 4 Teams, alle Begegnungen geplant. Phones der Captains zeigen das nächste Pool-Match im "Mein Team"-Bereich.

## Schritt 6: Alle Pool-Matches gespielt (15 Min)

**Aktion**: Captains tragen Set-Scores für alle 24 Pool-Matches ein (Best-of-3, Scores absichtlich klar gehalten, um Konflikt-Screens zu vermeiden). Owner verfolgt am Tablet die Live-Tabellen pro Pool.

**Erwartung**: Pool-Tabellen aktualisieren sich nach jedem finalisierten Match (Polling 5 s). Top-2 pro Pool werden in den Tabellen hervorgehoben (Badge "qualifiziert"). Nach Match 24 ist der "KO starten"-Button aktiv.

## Schritt 7: Cross-Pool-Tiebreaker, optional Tie-Resolution-Dialog (5 Min)

**Aktion**: Owner drückt "KO starten". System berechnet Cross-Pool-Seeding über die Tiebreaker-Chain (Punkte, Direktvergleich entfällt über Pools hinweg, dann Satzverhältnis, dann Buchholz). Falls ein nicht auflösbarer Tie zwischen Pool-Erstplatzierten besteht, erscheint der Tie-Resolution-Dialog mit manueller Reihenfolgewahl.

**Erwartung**: Sichtbares Seeding 1–8 quer über alle Pools. Audit-Event `seeding_set` geschrieben (bei manueller Tie-Resolution zusätzlich `tie_resolved_manually`). Übergang ans KO-Bracket aus M2 sauber, ohne Datensprung.

## Schritt 8: KO-Phase mit Finale und Spiel um Platz 3 (10 Min)

**Aktion**: Acht qualifizierte Teams spielen Viertelfinale, Halbfinale, Finale plus Spiel um Platz 3 auf den Phones. Owner kommentiert am Tablet Bracket-View und Endrangliste.

**Erwartung**: Bracket befüllt sich nach jedem Match via `tournament_advance_ko_winner`. Tournament-Status wechselt auf `completed` sobald Finale plus Bronze finalized sind. Endrangliste: Plätze 1 und 2 aus dem Finale, Platz 3 aus dem Bronze-Match, Platz 4 als Bronze-Verlierer, Plätze 5–16 aus den Pool-Standings (Tiebreaker-Chain). Roster-Lock greift (`FR-TEAM-15`). Owner-Abnahme M3 abgeschlossen.
