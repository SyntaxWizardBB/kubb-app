# M3 — Teams + Pool + Roster — Risiken und Deferrals

> Status: Entwurf
> Datum: 2026-05-26

## Risiken pro Sub-Milestone

### M3.1 — Teams

**R-M3.1-1: Captain-Rechte-Modell ohne Schutz-Mechanik wird in Pilot-Phase missbraucht**

FR-TEAM-5 verlangt gleichberechtigte Captain-Rechte. Ohne Schutz-Mechanik (siehe OD-M3-01) kann ein verärgertes Mitglied den Pool sprengen — Mitglieder entfernen, Team auflösen, Liga-Wechsel beantragen. In der Pilot-Phase mit Owner und Freundeskreis kein realistisches Risiko, aber bei Mass-Adoption ein Vertrauens-Brecher.

**Mitigation**: OD-M3-01-Empfehlung B (Audit-Event plus Inbox-Notification an alle Pool-Mitglieder bei kritischen Aktionen) ist Minimum-Schutz. Wenn das nicht reicht: C (Mehrheits-Bestätigung) als eigenes M3.4-Sub-Milestone nachschieben.

**R-M3.1-2: Inbox-Integration für Team-Einladungen erfordert Inbox-Erweiterung**

Team-Einladungen sollen pro eingeladenem Nutzer einen Inbox-Eintrag erzeugen (FR-NOT). Aktuelle Inbox unterstützt vermutlich noch keinen `team_invitation`-Item-Type.

**Mitigation**: M3.1-T11 enthält den Inbox-Item-Type-Anlage. Falls Inbox-Refactor nötig, eskaliert M3.1-T11 zu eigenem Refactor-Task vor T2.

**R-M3.1-3: Gast-Spieler-Identitäten ohne Auth-Account**

Gäste haben keine `auth.users`-Row. Spätere Spielerprofile, Stats und FR-TEAM-10 (Gast claimt Account) hängen davon ab, dass die `team_guest_players.id` als stabile Identität dient.

**Mitigation**: Gast-Spieler-IDs sind UUID, kollidieren nicht mit `auth.users.id`. FR-TEAM-10 bleibt M5+ — `claimed_by_user_id` ist bereits als nullable FK angelegt für späteren Claim-Pfad. Keine M3-Aktion.

### M3.2 — Tournament-Roster

**R-M3.2-1: BR-5-Cross-Tournament-Check als Trigger ist Performance-empfindlich**

Bei jeder Insert in `tournament_roster_slots` läuft ein Lookup ob der `member_user_id` schon in einem anderen Roster desselben Turniers steht. Bei 32-Team-Turnier-Registrierung mit 6 Slots pro Team = 192 Inserts hintereinander. Bei serieller Verarbeitung okay, bei parallelen Registrierungen Trigger-Lock möglich.

**Mitigation**: Trigger nutzt `tournament_participants(tournament_id)`-Index (existiert), Lookup ist O(N) in N=Roster-Slots desselben Turniers. Property-Test mit 32-Team-Setup verifiziert p95 unter 250 ms (siehe `architecture.md` §7 Scale-Impact). Bei Tier-2-Skala kommt zusätzlicher Partial-Index `(member_user_id) WHERE replaced_at IS NULL`.

**R-M3.2-2: `tournament_participants.user_id` nullable bricht bestehende M1-Logik**

Aktuelle M1-RPCs (`tournament_register_single`, `tournament_list_for_caller`, etc.) gehen davon aus, dass `user_id NOT NULL` ist. Nullable machen ohne Anpassung der Reads bricht Listen-Projektionen.

**Mitigation**: Migration `20260615000003` setzt CHECK-Constraint `(team_id IS NULL AND user_id IS NOT NULL) OR (team_id IS NOT NULL)` — bestehende Single-Registrierungen sind weiterhin NOT NULL durch Constraint. M1-RPC-Reads bleiben unverändert für Einzel-Path. Team-Path nutzt separate Read-Helper.

**R-M3.2-3: Roster-Editor-Drag-UI ist neu im Projekt**

Bisheriger Code hat keine Drag-and-Drop-Composition. `ReorderableListView` allein reicht für Reorder, nicht für "aus Pool in Slot ziehen". 

**Mitigation**: Slot-Composition mit Tap-Select statt Drag-and-Drop — der Pool ist scrollbare Liste, Tap auf Pool-Eintrag fragt "Welcher Slot?", Tap auf Slot fragt "Welcher Pool-Eintrag?". Funktional gleichwertig zu Drag, deutlich einfacher zu implementieren und zu testen. Falls Owner Drag-and-Drop will: M3.2-T7 wird L statt M.

**R-M3.2-4: Score-RPCs aus M1 müssen Team-Pfad lernen**

Score-Eingabe-RPC `tournament_propose_set_score` validiert heute `submitter_user_id IN (participant_a.user_id, participant_b.user_id)`. Bei Team-Match ist `user_id` der Captain-am-Anmelden — aber jedes Pool-Mitglied soll Score eintragen können (BR-9).

**Mitigation**: M3.2 fügt eine RPC-Anpassung hinzu — Score-Submitter wird via `EXISTS (... team_memberships WHERE team_id IN (...) AND user_id = submitter_user_id)` validiert. Aufwand: 2–3 Stunden, vermutlich M3.2-T2-Bestandteil.

### M3.3 — Pool-Phase

**R-M3.3-1: plpgsql-Pool-Generator driftet von Dart-Implementation ab**

Wie bei M2 (OD-M2-02): Server-Authority verlangt plpgsql-Spiegelung der `pool_phase_generator.dart`. Zwei Implementationen in zwei Sprachen ist Drift-Quelle.

**Mitigation**: Property-Parität-Tests in M3.3-T7 sind Merge-Gate. Test-Sweep n in {8, 12, 16, 24, 32} × g in {2, 3, 4, 6, 8} = 25 Test-Kombinationen. JSON-Vergleich pro Kombi.

**R-M3.3-2: Snake-Grouping bei ungeradem Verhältnis n / g**

Wenn 14 Teams in 4 Gruppen sollen, bekommen Gruppen ungleiche Grössen (4, 4, 3, 3). Snake-Pattern muss das sauber abbilden — die "kürzeren" Gruppen kriegen weniger Matches, was Standings ungleich macht.

**Mitigation**: Pool-Phase-Validator wirft Warnung wenn `participantCount % groupCount != 0`. Veranstalter muss bestätigen. Standings bekommen pro Gruppe relativen Wert (Quote der gewonnenen Spiele statt Absolut-Anzahl). Property-Tests decken die Edge-Cases ab.

**R-M3.3-3: Cross-Pool-Tiebreaker ohne Direkt-Vergleich**

OD-M3-03-Empfehlung A überspringt `direct_comparison` Cross-Pool. Das macht den Tiebreaker schwächer — bei Tie nach `total_points` und `buchholz` fällt der Pool-Cut auf `wins`, was identisch sein kann.

**Mitigation**: Wenn `pool_cut` einen vollständigen Tie produziert, fällt das System auf OD-M3-05-Empfehlung B (Veranstalter-Override). Pool-Cut-RPC wirft `TIEBREAKER_NEEDS_RESOLUTION`. Frontend zeigt Eskalation. Akzeptabel als Edge-Case.

**R-M3.3-4: Pool-Standings-View bei 8 Gruppen wird unübersichtlich**

8 Gruppen à 4 Teams = 8 Karten auf der Standings-Sicht. Auf Mobile 360 px viel Vertical-Scroll.

**Mitigation**: Karten sind kollabierbar (`ExpansionTile`). Default kollabiert, Veranstalter expandiert was ihn interessiert. Cross-Pool-Übersicht oben zeigt nur Top-N pro Gruppe als kompakte Liste.

### Übergreifend

**R-M3-G1: M3 hängt an drei Owner-Reviews zwischen Sub-Milestones**

Wie M2: drei Sub-Milestones, drei potenzielle Pause-Punkte. Wenn Owner zwischen M3.1 und M3.2 zwei Wochen Pause macht, läuft Cadence aus.

**Mitigation**: M3.1 ist isoliert demobar (Team-CRUD ohne Turnier-Bezug) — kann separat abgenommen werden. M3.2 ohne M3.3 ist ein Team-Turnier ohne Pool-Phase — auch demobar. M3.3 schliesst ab. Owner-Abnahme ideal nach M3.3 mit Zwischen-Checkpoints "approve to proceed".

**R-M3-G2: BR-5-Verletzung ist in der UI schwer vorhersagbar**

Wenn Spieler X bereits in Team A registriert ist und Team B will ihn auch in den Roster setzen — die Pool-Liste in Team B muss vorhersehbar markieren "X ist schon in Turnier T1 registriert". Sonst wirft die RPC nach langem Auswahl-Prozess einen Fehler.

**Mitigation**: Pool-Composition-Screen ruft beim Öffnen einen Read-Endpoint `team_get_pool_with_tournament_conflicts(team_id, tournament_id)` — markiert Pool-Mitglieder mit `conflicted=true` wenn sie in einem anderen Roster desselben Turniers stehen. UI rendert sie als "ausgegraut, nicht wählbar". Aufwand: 1–2 Stunden zusätzlich für M3.2-T7.

**R-M3-G3: Score-Eingabe-UI muss Team-Kontext anzeigen**

Aktuelle Match-Detail-Screen aus M1 zeigt "Participant A" und "Participant B" als Spieler-Namen. Für Team-Matches sollte sie "Team A (Roster: X, Y, Z)" zeigen, mit aktuellem Roster.

**Mitigation**: M3.2-T10 (Tournament-Detail-Anpassung) deckt das mit ab. Match-Detail-Screen-Anpassung ist kleiner Task (~30 LOC), läuft als Teil von M3.2-T10. Bestehende Score-Eingabe-Logik bleibt unverändert.

## Was bewusst auf M4+ verschoben wird

| Bereich | FR | Verschoben auf | Grund |
|---|---|---|---|
| Substitution mid-Set (zwischen Sets erlaubt) | FR-TEAM-13 Erweiterung | M4 oder M5 | Set-State-Tracking auf Match-Ebene fehlt |
| Reservespieler-Konzept (aktiv / Reserve) | FR-TEAM-16 (KANN) | M5+ | OD-M3-04, kein klarer Use-Case in Pilot-Phase |
| Gast-Spieler claimt Account | FR-TEAM-10 (SOLL) | M5+ | Identitäts-Migration-Pfad braucht eigenen Spike |
| Vereins-Modell | FR-CLUB-1..N | nach M5 | Eigener Milestone in Roadmap |
| Liga-Wechsel mid-season (Liga-Admin) | FR-GLB-5..7 | M5 | Liga-System kommt in M5 |
| Liga-Nachweis bei Shared Tournaments | FR-REG-11 | M5+ | Shared Tournaments selbst sind M5+ |
| Team-Statistiken im öffentlichen Profil | FR-PUB-9 vollständig | nach M5 | Hängt an Stats-Refactor OD-03 |
| Logo / Avatar Upload | NFR | M5+ Polish | URL-Feld reicht für Pilot |
| Mehrheits-Bestätigung für Captain-Aktionen | FR-TEAM-5 Schutz | optional M3.4 oder M5 | OD-M3-01, nur wenn Mass-Adoption droht |
| Realtime-Push für Pool-Standings | FR-PUB-11 | M4 | Polling reicht |

## Bekannte Einschränkungen — bleiben aus M1 / M2 erhalten

- **iOS, Web, Linux, Windows-Build**: M3 ist Android-only wie M1 / M2. Web-Spike vor Pool-Standings-Live-Sicht (M4) wird zwingend.
- **Push-Notifications**: nicht in M3. Inbox-Einträge für Team-Invitations sind In-App-Notification, kein FCM. Push kommt M4.
- **Realtime**: weiter Polling. Pool-Standings-Aktualisierung mit ~5 Sek Latenz.
- **Score-Eingabe-Granularität**: per-Match-Result mit per-Set-EKC, keine per-Wurf-Events (ADR-0014, OD-08 Tournament-Foundation).

## Nicht-Risiken (zur Klärung)

- **`teams.dissolved_at` als Soft-Delete statt Hard-Delete**: bewusst. FR-TEAM-20 sagt aufgelöste Teams bleiben sichtbar. Soft-Delete-Pattern ist hier korrekt — kein Risiko, das in der Codebase normalerweise vermieden wird.
- **`tournament_roster_slots` mit `replaced_at` statt separater History-Tabelle**: bewusst. Hält Cross-Tournament-Constraint via Partial-Index `WHERE replaced_at IS NULL` einfach. History-Abfragen sind `WHERE replaced_at IS NOT NULL ORDER BY assigned_at`. Diskussion abgeschlossen.
- **`tournament_participants.user_id` als "wer hat angemeldet" bei Team-Anmeldung**: bewusst. Der Captain-Spieler hat das Anmelde-Privileg, aber Score-Eingabe ist BR-9-konform aller Pool-Mitglieder via Membership-Lookup. `user_id` ist Audit-Spur, kein Recht.
