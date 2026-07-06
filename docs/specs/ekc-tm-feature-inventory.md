# EKC Tournament Manager — Funktions-Inventar & Gap-Analyse

**Zweck:** Clean-Room-Funktionsspezifikation des WordPress-Plugins
[ekc-tournament-manager](https://github.com/LukasHuser/ekc-tournament-manager)
(v2.5.1, GPL v3) als Grundlage, um dessen kompletten Funktionsumfang in der
Kubb-App eigenständig nachzubauen.

**Lizenz-Hinweis (wichtig):** Dieses Dokument beschreibt ausschließlich
*beobachtetes fachliches Verhalten* (Regeln, Felder, Semantik, Abläufe) aus
Doku, Changelog und Verhaltensanalyse. Es enthält **keinen Code, keine
Code-Struktur, keine Übernahme von Ausdrucksformen** aus dem GPL-Quelltext.
Funktionalität und Ideen sind nicht urheberrechtlich geschützt; die
Implementierung erfolgt vollständig eigenständig in unserer bestehenden
Architektur (Postgres-RPCs + kubb_domain + Flutter). Es wird kein GPL-Code
portiert → kein Copyleft.

**Stand:** 2026-07-06. Ist-Stand-Referenzen beziehen sich auf main.

---

## Teil A — Funktionsumfang des ekc-tournament-manager

### A1. Turnier-Konfiguration

Stammdaten:

| Einstellung | Semantik |
|---|---|
| Name | Anzeigename |
| Code-Name | kurzer, systemweit eindeutiger technischer Identifier (Referenz in allen Einbettungen) |
| Owner | Besitzer; Basis der Berechtigungsprüfung |
| Teamgröße | `1vs1, 2vs2, 2+vs2+, 3vs3, 3+vs3+, 6vs6` („+" = Mindestbesetzung plus optionale Ersatzspieler) |
| Turniersystem | `elimination` (nur KO) · `group+elimination` · `swiss+elimination` |
| Datum | Turnierdatum |
| Max. Teams | Kapazität |
| Warteliste | an/aus |
| Check-in | an/aus (Funktion freigeschaltet) + separates Laufzeit-Flag „Self-Check-in aktiv" |
| Spielernamen Pflicht | steuert Sichtbarkeit/Pflicht der Spielerfelder (Anzahl abhängig von Teamgröße; Spieler 1 = Captain; bei 1vs1 wird Teamname aus Spielername gebildet) |
| Auto-Backup | automatisches JSON-Backup nach jedem Runden-/Bracket-Speichern |

KO-Konfiguration:

| Einstellung | Semantik |
|---|---|
| Gold-Bracket-Größe | Halbfinale / Viertelfinale / Achtelfinale (Ro16) / Ro32 / Ro64 |
| Silber-Bracket-Größe | optionales zweites Bracket; eigene Größe unabhängig vom Gold-Bracket |
| Punkte pro Runde (KO) | Score-Obergrenze pro Match (Eingabe-Validierung) |

Vorrunden-Konfiguration (Swiss):

| Einstellung | Semantik |
|---|---|
| Anzahl Runden | reguläre Swiss-Runden |
| Punkte pro Runde | Score-Obergrenze pro Match; Validierung: Summe beider Scores ≤ Limit |
| Slide-Pairing-Runden | für die ersten n Runden Slide-Pairing, danach Top-Down-Pairing (s. A3) |
| Zusatzrunden | Platzierungsrunden NACH Start des KO-Brackets (s. A5) |
| Punkte für BYE | Gutschrift bei Freilos; Match wird damit vorbefüllt |
| Punkte für virtuelles Ergebnis | Punktwert der virtuellen Ergebnisse in Zusatzrunden (Default 1) |
| Zeitlimit Runde | Minuten; aktiviert Runden-Timer |
| Tie-Break-Zeit | Minuten ab Rundenstart, ab denen der Tie-Break beginnt (eigener Countdown, Anzeige „seit X Min" max. 30 Min) |
| Start-Feldnummer | erste Pitch-Nummer (für parallel laufende Turniere auf durchnummerierten Feldern) |
| Verfügbare Felder | aktiviert den Pitch-Limit-Modus (s. A6) |

### A2. Team-/Spieler-/Ergebnis-Modell

**Team:** Name, Land (ISO-2, Flaggen), Verein/Stadt, aktiv/inaktiv, E-Mail,
Telefon, Anmeldezeitpunkt, Camping-/Frühstücks-Anzahl (Logistik),
**Startgeld-bezahlt-Flag**, **Wartelisten-Flag**, **registration_order**
(Dezimalzahl → manuelles Einsortieren zwischen zwei Positionen),
**checked_in**, **seeding_score**, **initial_score**, **virtual_rank**,
**shareable_link_id** (geheimes Token), **external_id** (Fremd-ID für
CSV-Upsert), Spieler 0–6 (Vorname/Nachname/Land/Captain-Flag).

**Ergebnis** (= 1 Match): Turnier, Stage (`swiss`, `group`, `elimination`,
`elimination-silver`), Rundennummer, Bracket-Positions-Schlüssel (KO),
Team 1/2 (nullable), **Platzhalter-Text je Seite** („Sieger HF 1" solange Team
unbekannt), Score 1/2, **Pitch**, virtuelles-Ergebnis-Flag.
BYE ist ein reserviertes Pseudo-Team.

**Ergebnis-Protokoll:** jede *Team-Selbstmeldung* (nicht Admin-Änderungen)
wird mit Zeitstempel, meldendem Team und Scores geloggt → Audit + Basis des
4-Stunden-Fensters.

### A3. Swiss-Pairing (Kern)

- **Verfahren:** vollständiger Graph über das aktuelle Ranking, Kantengewicht
  aus Rang-Distanz, **Minimum-Weight-Perfect-Matching** (Blossom;
  max-cardinality → jedes Team wird gepaart).
- **Gewicht = Distanz²** (nichtlinear): bevorzugt viele kleine Abweichungen
  gegenüber einer großen → Paarungen bleiben eng am Ranking, Lösung eindeutiger.
- **Rematch-Vermeidung:** bereits gespielte Paarung → Strafgewicht 10⁸
  (dominiert alles; Rematches nur wenn unvermeidbar). Gilt auch für BYE →
  niemand bekommt zweimal ein Freilos, solange vermeidbar.
- **Top-Down-Pairing** (Standard): Gewicht = Rang-Abstand² → Nachbarn im
  Ranking spielen gegeneinander (1-2, 3-4, …).
- **Slide-Pairing** (erste n Runden): Teams werden in **Score-Gruppen**
  geteilt (ungerade Gruppen ziehen das Top-Team der nächsttieferen Gruppe
  hoch, bis gerade). Ideal-Paarung innerhalb der Gruppe: obere Hälfte gegen
  untere Hälfte (Rang i gegen Rang i + Gruppengröße/2, Gewicht 0), Abweichung
  wird quadratisch teurer. Gruppenübergreifende Fallback-Kanten mit hohem
  Aufschlag, damit sie nur greifen, wenn innerhalb der Gruppe keine
  rematchfreie Zuordnung existiert.
- **BYE bei ungerader Zahl:** Pseudo-Team wird am Ranking-Ende angehängt und
  nimmt normal am Matching teil (Freilos wandert dank Rematch-Strafe).

### A4. Ranking & Tiebreaks

Sortierung (absteigend):
1. **virtual_rank** (gesetzte Werte zuerst, aufsteigend) — manueller
   Endplatzierungs-Override für Teams, die ins Bracket „ausgelagert" wurden;
2. **Total-Score = Spielpunkte + initial_score**;
3. **Opponent-Score**: Σ über alle Gegner von
   (Gesamtscore des Gegners − Punkte, die der Gegner im direkten Duell gegen
   mich erzielte) — Buchholz-Variante ohne Direktbegegnungs-Beitrag
   (≙ unserer live.kubb-Formel);
4. **seeding_score** (letzter Tiebreak).

Vor Runde 1: virtual_rank → initial_score → seeding_score → stabile ID.

**Scores mit Sonderrolle:**
- `initial_score` = Startbonus („Accelerated Swiss": starke Teams treffen
  sich früher);
- `seeding_score` = Setzwert; manuell, per CSV oder **zufällig generierbar**
  (Permutation 1..N, nur vor Runde 1); zusätzlich Schutzkriterium im
  Pitch-Limit-Modus;
- `virtual_rank` = Ranking-Override + Ausschluss vom regulären Pairing in
  Zusatzrunden.

**Admin-Ranking-Seite:** Rang, Team, Total-Score, Opponent-Score (read-only)
+ **editierbar: seeding_score, initial_score, virtual_rank**; Aktionen
„Random-Seeding erzeugen" (vor Runde 1) und „Team aus Turnier entfernen"
(inaktiv setzen + Ergebnisse löschen).

### A5. Runden-Lifecycle & Zusatzrunden

- **Runde starten:** nur wenn für die Zielrunde noch keine Ergebnisse
  existieren; **fehlende Ergebnisse blockieren** den Start (Liste der
  fehlenden Matches wird angezeigt). Runde 1 nutzt nur aktive Teams
  (Warteliste vorher deaktivieren).
- **Ergebnisse:** ganze Runde speichern oder **einzelnes Ergebnis** (AJAX);
  fehlende Ergebnisse werden visuell markiert; 0:0 wird gelb markiert;
  BYE-Matches werden mit den konfigurierten BYE-Punkten vorbefüllt.
- **Runde löschen:** nur die aktuelle/letzte (inkl. Log + Timer-Reset) —
  Rettung bei zu früh gestarteter Runde.
- **Zusatzrunden (virtuelle Ergebnisse):** Nach KO-Start spielen die
  verbliebenen Teams weiter um die Plätze. Die ins Bracket ausgelagerten
  Teams (virtual_rank gesetzt) werden paarweise als **virtuelle Matches**
  verbucht; beide erhalten den konfigurierten Punktwert (≙ Unentschieden).
  Zweck: Der Opponent-Score der zurückgebliebenen Teams, die früher gegen
  diese Top-Teams gespielt haben, wächst weiter fair mit.

### A6. Pitch-Verwaltung

- Fortlaufende Feldnummern ab konfigurierbarer Start-Nummer; KO-Brackets
  vergeben Pitches ab `1 + Offset/2` (Silber startet hinter Gold).
- **Pitch-Limit-Modus** (Teams > 2×Felder+1): pro Runde müssen
  `Teams − 2×Felder` Teams aussetzen (BYE). Regeln:
  - Gültigkeit: `Teams ≥ BYEs/Runde × Runden`, sonst Start blockiert;
  - die **Top-Seeds** (Anzahl = Teams − BYEs/Runde × Runden, nach
    seeding_score) bekommen **nie** ein BYE;
  - pro Runde erhalten die obersten Nicht-Geschützten, die **noch nie** ein
    BYE hatten, das Freilos (mit BYE-Punkten, Pitch „–").

### A7. Timer

Rein informativ (keine Automatik): Admin startet/resettet den Runden-Timer
(Zeitstempel je Runde). Anzeige: „Runde X: Y Minuten übrig" / „Runde beendet";
Tie-Break: „beginnt in X Min" / „seit X Min" (max. 30 Min nach Eintritt).
Öffentlich einbettbar und auf Team-Seiten sichtbar.

### A8. KO-Bracket

- **Größen:** 4–64 Teilnehmer. Finale-Container enthält **Finale + Spiel um
  Platz 3**.
- **Gold + Silber:** Silber = zweites Bracket, befüllt mit den auf das
  Gold-Bracket **folgenden Ranglisten-Rängen** (Offset = Gold-Größe; z. B.
  Gold Ro16 → Silber startet bei Rang 17). Eigene Größe, eigener Stage.
- **Seeding aus Swiss-Ranking** („populate from ranking", nur solange keine
  KO-Ergebnisse existieren): feste Standard-Seeding-Positionen, sodass sich
  Topgesetzte spätestmöglich treffen. Paarungen der 1. Runde (Ränge):
  - 4er: (1,4) (3,2)
  - 8er: (1,8) (5,4) (3,6) (7,2)
  - 16er: (1,16) (9,8) (5,12) (13,4) (3,14) (11,6) (7,10) (15,2)
  - 32er: (1,32) (17,16) (9,24) (25,8) (5,28) (21,12) (13,20) (29,4) (3,30)
    (19,14) (11,22) (27,6) (7,26) (23,10) (15,18) (31,2)
  - 64er: (1,64) (33,32) (17,48) (49,16) (9,56) (41,24) (25,40) (57,8)
    (5,60) (37,28) (21,44) (53,12) (13,52) (45,20) (29,36) (61,4) (3,62)
    (35,30) (19,46) (51,14) (11,54) (43,22) (27,38) (59,6) (7,58) (39,26)
    (23,42) (55,10) (15,50) (47,18) (31,34) (63,2)
  - Ränge ohne Team → leerer Slot (teilgefüllte Brackets sind zulässig).
- **Betrieb:** Ergebnisse pro Match (Scores, Pitch, Platzhalter-Texte);
  Team-Auswahl je Slot; „**Team in nächste Runde übernehmen**"-Aktion
  (bis inkl. Viertelfinale automatisch zugeordnet; HF→Finale/Platz 3 manuell);
  „alle Ergebnisse dieser Stage löschen"; in der Admin-Ansicht werden in der
  ersten Runde die Seeding-Ränge angezeigt.
- **Podium:** Gold-/Silber-Punkt am Finale, Bronze am Platz-3-Spiel;
  Verlierer ausgegraut.

### A9. Zuschauer-/Web-Einbettung (Shortcodes)

Alle referenzieren das Turnier über den Code-Namen; einbettbar in beliebige
Website-Seiten:
- **Teams-Liste** (limit/all, auf-/absteigend nach Anmeldung, Warteliste
  separat einblendbar, Flaggen-/Club-Spalten schaltbar, „bezahlt"-Punkt);
- **Team-Zähler** (aktuell vs. Maximum; raw-Zahl für animierte Counter);
- **Swiss-Ansicht** (Rangliste ODER letzte n Runden/alle; Timer-Zeile);
- **KO-Bracket** (Gold/Silber);
- **Team-Link-Seiten** (s. A10); **Nation Trophy** (s. A11);
- **Auto-Refresh** über URL-Parameter `refresh=<Sekunden>`.

### A10. Shareable Links (Team-Self-Service ohne Login)

- Pro Team ein geheimer Link (Team-ID + 20 Zufallszeichen); URL-Präfix pro
  Turnier; Regenerieren ersetzt den Link. Erzeugung einzeln oder für alle
  aktiven Teams.
- **Team-Seite** zeigt: eigenen Namen, Runden-Timer, **alle eigenen
  Ergebnisse aller Runden**; für die **aktuelle Runde** darf das Team das
  Ergebnis selbst **melden/ändern**:
  - Validierung: Scores 0..Max, Summe ≤ Max/Runde;
  - **4-Stunden-Fenster:** ab der ersten Meldung irgendeines Ergebnisses der
    Runde bleibt die Eingabe 4 h offen, danach read-only (verhindert späte
    Manipulation, v. a. letzte Runde);
  - jede Meldung landet im Ergebnis-Protokoll (wer/wann/was).
- **Self-Check-in** über dieselbe Seite (nur solange Turnier noch ohne
  Ergebnisse und Self-Check-in aktiv geschaltet).
- **E-Mail-Versand** der Links: HTML-Template mit Platzhaltern (`${team}`,
  `${url}`), konfigurierbarer Absender; einzeln/alle;
  **Batch-Scheduling** (alle 5 Min ein Batch konfigurierbarer Größe,
  Auswahl nach Status neu/gesendet/fehlgeschlagen) mit **Status-Seite**
  (new/scheduled/sent/failed, Nachrichten-ID, Fehlermeldung, Aktionen
  Senden/Abbrechen/Erneut senden; kein Auto-Retry).

### A11. Nation Trophy (Event-Wertung über 3 Turniere)

- Aggregiert je Event die **Gold-Bracket-Ergebnisse** dreier Turniere
  (1vs1, 3vs3, 6vs6) zu einer Länderwertung (Land = Team-Attribut).
- Punkte je bestem erreichten Resultat: Sieger 1000, Finale verloren 700,
  Platz 3 500, Platz 4 400, Viertelfinal-Aus 300, Achtelfinal-Aus 200
  (tiefere Runden zählen nicht). **3vs3 zählt doppelt** (2000/1400/…).
- Pro Land zählen: bestes Team (6vs6) bzw. beste drei Teams (1vs1, 3vs3);
  Summe über alle drei Turniere; überzählige Teams sichtbar mit „–".
- Ausgabe: aufklappbare Tabelle Rang/Flagge/Land→Teams/Station/Score,
  absteigend nach Landessumme.

### A12. Betrieb & Verwaltung

- **Check-in-Seite:** Zusammenfassung (total/aktiv/eingecheckt/bezahlt),
  Tabelle mit Filtern (aktiv/Check-in/bezahlt/Warteliste/Land), Aktionen je
  Team: aktivieren, ein-/auschecken, bezahlt-Toggle, Warteliste-Toggle,
  Link erzeugen/senden; Schalter „Self-Check-in aktiv".
- **Teams-Seite:** CRUD, Aktiv-/Bezahlt-/Wartelisten-Toggles, Filter,
  Sortierung, **CSV-Export** (fester Spaltensatz inkl. 6 Spielern) und
  **CSV-Import mit Upsert** (Matching über team_id, sonst external_id, sonst
  Neuanlage; nicht enthaltene Spalten überschreiben nichts; Semikolon/Tab;
  Header-Pflicht; Spaltenreihenfolge frei; seeding_score importierbar).
- **Ergebnis-Protokoll-Seite:** alle Team-Selbstmeldungen (Zeit, Teams,
  Ergebnis, Stage, „geändert von").
- **Backup:** JSON-Export/-Import ganzer Turniere (Turnier + Teams inkl.
  Link-IDs + alle Ergebnisse; Datenmodell-versioniert; Import ersetzt
  Turnier mit gleichem Code-Namen und remappt IDs); Auto-Backup nach jedem
  Speichern; Verwaltungs-Seite (Download/Delete/Import/Upload ≤ 5 MB).
- **Registrierungs-Integrationen:** Formular-Plugins (Contact Form 7,
  Elementor) schreiben Anmeldungen direkt in die Turnier-DB
  (Team-/Spielerfelder, aktiv-/Wartelisten-Steuerung per verstecktem Feld);
  animiertes Counter-Widget speisbar aus dem Team-Zähler.
- **Rollen:** Administrator / Tournament-Administrator (alles, auch fremde
  Turniere) / Tournament-Director (nur eigene Turniere); Capabilities
  getrennt nach read/edit/manage/delete (+ „others"-Varianten) und Backups.
  „Template-Seiten"-Konzept + Seiten-Duplizierung fürs schnelle Aufsetzen.

---

## Teil B — Gap-Analyse gegen die Kubb-App

Legende: ✅ vorhanden (ggf. besser) · 🟡 teilweise / anders gelöst ·
❌ fehlt · ➖ bewusst nicht relevant (WordPress-/Web-spezifisch, andere
Architektur-Entscheidung).

### B1. Wo wir bereits stärker sind

| ekc-tm | Kubb-App |
|---|---|
| Ergebnis-Meldung per Link, 4h-Fenster | ✅ Consensus-Modell beider Teams + Disagreement-Statemachine + Organizer-Override mit Begründung + Offline-Outbox |
| manueller Advance, HF→Finale sogar komplett manuell | ✅ automatische Bracket-Progression (Trigger), Double-Elim, Consolation, Shootout |
| Timer rein informativ, manuell gestartet | ✅ Schedule-Engine: Runden-Autostart, Pausen, Skip, server-synchronisierte Uhr, pg_cron-Tick |
| Auto-Refresh-Polling (refresh=20) | ✅ Realtime (CDC + Broadcast), Push-Notifications |
| E-Mail-Versand + Scheduling + Statusseite | ➖ bei uns Inbox + FCM-Push (kein E-Mail-Kanal nötig) |
| nur Swiss + Single-KO(+Silber) | ✅ zusätzlich Gruppenphase mit Pools, Double-Elim, Trostturnier, Stufen-Graph-Framework, EKC-/klassische Wertung, Regelvarianten, SKV-Punkte, ELO |
| Rollen auf WordPress-Ebene | ✅ Veranstalterteams mit owner/admin/referee + App-Admin |
| kein Teilnehmer-Konto | ✅ Spieler-Accounts, Team-Roster, Achievements, Saison |

### B2. Echte Lücken (Feature in ekc-tm, bei uns fehlend)

**Vorrunde / Pairing / Ranking**
1. ❌ **Slide-Pairing** (Score-Gruppen, obere vs. untere Hälfte) als
   wählbares Verfahren für frühe Runden (Anzahl konfigurierbar); wir haben
   nur Monrad-Nachbarpaarung.
2. ❌ **Optimales Matching** (Minimum-Weight-Perfect-Matching mit
   Distanz²-Gewicht + Rematch-Strafe) statt Greedy+Backtracking — relevant,
   wenn Rematch-Vermeidung global optimal sein soll.
3. ❌ **Accelerated Swiss** (initial_score als Startbonus, fließt in
   Total-Score).
4. ❌ **Seeding-Score als Tiebreak** + **Random-Seeding-Generator**
   (wir: ELO-Auto-Seeding/manuell, aber kein Seeding-Tiebreak in der
   Vorrunden-Rangliste, kein Zufalls-Seed).
5. ❌ **virtual_rank / manueller Ranking-Override** (Endplatzierung von
   Bracket-Teams in der Gesamtrangliste fixieren).
6. ❌ **Zusatz-/Platzierungsrunden nach KO-Start** inkl.
   **virtueller Ergebnisse** (Buchholz-Fairness für Zurückgebliebene).
   Über Stufen-Graph teilweise abbildbar, Virtual-Results-Mechanik fehlt.
7. ❌ **Admin-Ranking-Editierseite** (seeding/initial/virtual je Team
   editieren, Team aus Turnier entfernen inkl. Ergebnis-Bereinigung).
8. ❌ **Runde löschen/zurücksetzen** (letzte Runde verwerfen bei Fehlstart).
9. ❌ **Konfigurierbare BYE-Punkte** + Vorbefüllung von BYE-Matches.
10. ❌ **Pitch-Limit-Modus** (mehr Teams als Felder: systematische
    BYE-Rotation, Top-Seed-Schutz, kein doppeltes Freilos,
    Machbarkeits-Check `Teams ≥ BYEs×Runden`).
11. 🟡 **Tie-Break-Zeitpunkt innerhalb der Runde** (eigener Countdown
    „Tie-Break ab Minute X") — wir haben Tiebreak-Regeln je KO-Runde, aber
    keinen Vorrunden-Tiebreak-Timer.

**KO**
12. 🟡 **Silber-Bracket** = zweites Bracket für das nächste
    Ranglisten-**Band** (Rang N+1…N+M) mit eigener Größe. Unser
    Consolation-Modell speist sich aus KO-Verlierern; das Band-Modell
    (direkt aus der Vorrunden-Rangliste) ist konzeptionell im Stufen-Graph
    vorgesehen (`prelim_rank_band`), aber nicht ausgebaut.
13. 🟡 **Standard-Seeding-Positionstabellen** bis Ro64 (1v16, 9v8, …) —
    prüfen, ob unsere `bracket_placement`-Logik dieselben kanonischen
    Positionen erzeugt; Ro64-Support?
14. ❌ **Platzhalter-Texte je Bracket-Slot** („Sieger HF 1") als frei
    editierbares Feld.
15. 🟡 **Seeding-Rang-Anzeige** in der ersten Bracket-Runde (UI-Detail).

**Teilnehmer-Management**
16. ❌ **Startgeld-Bezahlt-Tracking pro Team** (Toggle, Filter, Anzeige,
    öffentlicher „bezahlt"-Punkt) — wir haben nur Startgeld-Metadaten.
17. ❌ **Manuelle Anmelde-Reihenfolge** (registration_order, dezimal
    einsortierbar) für Anmelde-/Warteliste.
18. 🟡 **Team-Waitlist** vollständig (bei uns Single-Waitlist ok,
    Team-Routing offen) + Warteliste öffentlich einsehbar.
19. ❌ **CSV-Import mit Upsert** (external_id/Fremd-ID-Matching,
    partial-column-Semantik, Tab/Semikolon) + **CSV-Export** der
    Teilnehmer inkl. seeding_score-Import.
20. ➖/🟡 Land pro Team/Spieler + Flaggen (für SKV egal, für
    internationale Turniere später).
21. ➖ Camping-/Frühstücks-Zähler (Logistik-Metadaten) — bei Bedarf als
    freie Zusatzfelder denkbar.

**Betrieb / Sonstiges**
22. 🟡 **Ergebnis-Änderungsprotokoll als Veranstalter-UI** (wer hat wann
    welches Ergebnis gemeldet/geändert) — Serverdaten existieren teils
    (Override-Begründung, Lamport-Drafts), aber keine Log-Ansicht.
23. ❌ **Turnier-Export/-Import** (JSON-Backup inkl. Wiederherstellung,
    Auto-Backup) — als Datenportabilität/Archiv nice-to-have; Cloud-Backups
    ersetzen das nur teilweise (kein Veranstalter-Selbstbedienung).
24. ❌ **Nation-/Verbands-Trophy**: Multi-Turnier-Event-Wertung nach
    Land/Verein (Punkteschema nach erreichter KO-Station, Top-k-Teams pro
    Einheit, Disziplin-Gewichtung). Analogon bei uns: Vereinswertung über
    ein SKV-Event. SKV-Saisonpunkte existieren, aber keine
    Event-Länder-/Vereinswertung.
25. 🟡 **Web-Einbettung für Vereins-Websites** (Teams-Liste, Zähler,
    Rangliste, Bracket, Timer als einbettbare Widgets/Links mit
    Auto-Refresh). Wir haben Public-Screens in der App + Public-Link;
    einbettbare Web-Ansichten (iframe/Widget) fehlen.
26. ❌ **No-Login-Team-Self-Service** (geheimer Link statt Account): für
    Teams ohne App-Konto Ergebnis melden/Check-in. Bewusste
    Architektur-Frage: wir sind App-first mit Consensus; ein
    Link-Fallback wäre ein eigenes Feature.
27. ➖ Formular-Integrationen (CF7/Elementor), Shortcodes,
    Seiten-Duplizierung, Template-Pages: WordPress-spezifisch — Bedarf ist
    bei uns durch In-App-Anmeldung gedeckt.

### B3. Empfohlene Bündelung (Diskussionsvorschlag)

- **Paket 1 „Vorrunden-Parität"** (höchster fachlicher Wert):
  Slide-Pairing + optimales Matching, BYE-Punkte, Pitch-Limit-Modus,
  Accelerated Swiss + Seeding-Tiebreak + Random-Seed,
  Runde-löschen, Admin-Ranking-Editor, virtuelle Zusatzrunden + virtual_rank.
- **Paket 2 „KO-Parität"**: Silber-Bracket als Ranglisten-Band
  (prelim_rank_band ausbauen), Seeding-Positions-Verifikation + Ro64,
  Platzhalter-Texte, Seeding-Rang-Anzeige.
- **Paket 3 „Teilnehmer-Ops"**: Fee-Tracking, registration_order,
  Team-Waitlist fertig, CSV-Import/Export.
- **Paket 4 „Betrieb"**: Result-Log-UI, Turnier-Export/Backup,
  Vereins-/Event-Trophy.
- **Paket 5 „Reichweite"** (strategisch zu entscheiden): Web-Embeds,
  No-Login-Team-Links.
