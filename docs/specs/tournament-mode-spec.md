# Kubb-App · Anforderungsspezifikation Turniermodus (v0.4)

> **Status:** Vierter Wurf · **Stand:** 2026-05-24
>
> **Zweck:** Dieses Dokument beschreibt **was** der Turniermodus der Kubb-App können muss und **wie die Prozesse aus Nutzersicht ablaufen sollen**. Es macht **keine Vorgaben zur technischen Umsetzung**.
>
> **Notation:**
> - **MUSS** = zwingend erforderlich für die erste Version (Must-Have)
> - **SOLL** = wichtig, aber zur Not verschiebbar (Should-Have)
> - **KANN** = nice-to-have für spätere Versionen (Could-Have)
>
> **Änderungen gegenüber v0.3:**
> - Team-Struktur grundlegend überarbeitet: Team = offener Pool mit unbegrenzten Mitgliedern, alle Mitglieder mit Captain-Rechten
> - Turnier-Roster als neues Konzept: aus dem Pool wird pro Turnier eine Teilnehmer-Auswahl getroffen, mid-Turnier anpassbar
> - Liga-Administrator als neue Rolle eingeführt: autorisiert mid-season-Wechsel
> - Liga-Wechsel mid-season vs. off-season klar getrennt; mid-season nur durch Liga-Administrator
> - Liga-Wechsel-Punkte-Regel präzisiert: Punkte bleiben in alter Liga eingefroren, neue Liga startet bei 0
> - Kompensation für Organisatoren entfernt (User-Entscheidung)
> - Einzelranking als eigene Liste ohne Liga-Unterteilung und ohne Masters festgeschrieben

---

## Inhaltsverzeichnis

1. [Glossar](#1-glossar)
2. [Stakeholder und Rollen](#2-stakeholder-und-rollen)
3. [Funktionale Anforderungen](#3-funktionale-anforderungen)
   - 3.1 [Authentifizierung und Profile (FR-AUTH)](#31-authentifizierung-und-profile-fr-auth)
   - 3.2 [Vereine (FR-CLUB)](#32-vereine-fr-club)
   - 3.3 [Freundschaften und Privatsphäre (FR-SOCIAL)](#33-freundschaften-und-privatsphäre-fr-social)
   - 3.4 [Erweitertes Spielerprofil (FR-PROFILE)](#34-erweitertes-spielerprofil-fr-profile)
   - 3.5 [Turnier-Konfiguration durch Veranstalter (FR-CFG)](#35-turnier-konfiguration-durch-veranstalter-fr-cfg)
   - 3.6 [Anmeldung (FR-REG)](#36-anmeldung-fr-reg)
   - 3.7 [Teams und Team-Mitgliedschaft (FR-TEAM)](#37-teams-und-team-mitgliedschaft-fr-team)
   - 3.8 [Turnierformate (FR-FMT)](#38-turnierformate-fr-fmt)
   - 3.9 [Paarungsgenerierung (FR-PAIR)](#39-paarungsgenerierung-fr-pair)
   - 3.10 [Match-Durchführung (FR-MATCH)](#310-match-durchführung-fr-match)
   - 3.11 [Score-Eingabe (FR-SCORE)](#311-score-eingabe-fr-score)
   - 3.12 [Konfliktauflösung (FR-CONF)](#312-konfliktauflösung-fr-conf)
   - 3.13 [Turnier-Rangliste (FR-RANK)](#313-turnier-rangliste-fr-rank)
   - 3.14 [Liga-Punkte-System (FR-POINTS)](#314-liga-punkte-system-fr-points)
   - 3.15 [Globales Ranking und Liga-System (FR-GLB)](#315-globales-ranking-und-liga-system-fr-glb)
   - 3.16 [Benachrichtigungen (FR-NOT)](#316-benachrichtigungen-fr-not)
   - 3.17 [Öffentliche Sichten (FR-PUB)](#317-öffentliche-sichten-fr-pub)
   - 3.18 [Live-Management während des Turniers (FR-LIVE)](#318-live-management-während-des-turniers-fr-live)
   - 3.19 [Lageplan (FR-MAP)](#319-lageplan-fr-map)
   - 3.20 [Veranstalter-Bewertung (FR-FEEDBACK)](#320-veranstalter-bewertung-fr-feedback)
   - 3.21 [Administration (FR-ADM)](#321-administration-fr-adm)
4. [Nicht-funktionale Anforderungen](#4-nicht-funktionale-anforderungen)
5. [Hauptprozesse](#5-hauptprozesse)
6. [Geschäftsregeln](#6-geschäftsregeln)
7. [Offene Punkte](#7-offene-punkte)

---

## 1. Glossar

| Begriff | Definition |
|---|---|
| **Turnier** | Ein einzelner Wettbewerb mit eigenem Format, eigener Rangliste, eigener Teilnehmerliste und eigenem Veranstalter. |
| **Runde** | Ein Spielabschnitt innerhalb der Vorrunde oder eine Stufe der KO-Phase. |
| **Match** | Ein einzelnes Aufeinandertreffen zweier Teilnehmer. |
| **Satz** | Ein Spielabschnitt innerhalb eines Matches. |
| **Pitch** | Ein physischer Spielplatz mit einer Nummer, dem Matches zugeteilt werden. |
| **Teilnehmer** | Ein einzelner Spieler (im Einzelturnier) oder ein Team (im Teamturnier). |
| **Spieler** | Eine Person, die an Matches teilnimmt. Entweder ein registrierter Nutzer oder ein Gast-Spieler. |
| **Gast-Spieler** | Eine vom Team erfasste Person ohne eigenes Nutzerkonto. |
| **Team** | Eine permanente Gruppe registrierter Spieler und Gast-Spieler, die gemeinsam an Turnieren teilnehmen. Hat einen offenen Pool von Mitgliedern. |
| **Team-Pool** | Die Gesamtheit aller Mitglieder eines Teams. Unbegrenzte Größe. |
| **Team-Mitglied** | Ein registrierter Spieler oder Gast-Spieler im Pool eines Teams. Alle registrierten Mitglieder haben Captain-Rechte (siehe Captain-Rechte). |
| **Captain-Rechte** | Berechtigung zur Verwaltung eines Teams: Mitglieder einladen oder entfernen, Team zu Turnieren anmelden, Roster festlegen, Scores eintragen, Liga-Wechsel beantragen. |
| **Gründer** | Der Spieler, der ein Team angelegt hat. Im aktuellen Modell hat der Gründer keine Sonderrechte gegenüber anderen Team-Mitgliedern (offener Punkt 1). |
| **Roster** | Die für ein konkretes Turnier ausgewählte Untermenge des Team-Pools. Der Roster hat die durch die Teamgröße des Turniers festgelegte Anzahl Spieler. |
| **Aktiver Spieler** | Ein Mitglied des Rosters, das in einem konkreten Match auf dem Pitch steht. |
| **Veranstalter** | Person, die ein Turnier erstellt und verwaltet. |
| **Verein** | Organisierte Gruppe von Spielern. Hat eigene Mitglieder, Rollen und ggf. eigene Turniere. |
| **Liga** | Klassifizierung der Spielstärke. Standardmäßig Liga A, B und C. |
| **Liga-Administrator** | Vom Plattform-Administrator ernannte Rolle. Autorisiert mid-season-Liga-Wechsel. |
| **Wechselfenster** | Zeitraum zwischen Dezember und Anfang April, in dem reguläre off-season-Liga-Wechsel beantragt werden können. |
| **Shared Tournament** | Ein Turnier, in dem mehrere Ligen gemeinsam spielen. Die Platzierung im Turnier folgt der reinen Leistung, die Liga-Wertung wird pro Liga getrennt geführt. |
| **Schochmodus** | Schweizer Variante des Schweizer Systems, in der Gewinner gegen Gewinner und Verlierer gegen Verlierer spielen. |
| **EKC-Punktesystem** | Score-System mit einem Punkt pro getroffenem Basekubb und drei Punkten für den Satzgewinn. |
| **Basekubb** | Ein auf der Grundlinie stehender Kubb. |
| **BYE / Freilos** | Bei ungerader Teilnehmerzahl spielt ein Teilnehmer pro Runde nicht und bekommt einen konfigurierten Score gutgeschrieben. |
| **Forfeit** | Eine Wertung zugunsten des anwesenden Gegners, wenn der andere Teilnehmer nicht erscheint oder ausfällt. |
| **Buchholz-Wertung** | Tiebreaker, der die Stärke der bestrittenen Gegner misst. |
| **Runden-Clock** | Zentraler Zeitgeber pro Runde. Der Veranstalter startet und stoppt ihn. |
| **Trainingsmodus** | Bestehender App-Bereich für persönliches Üben mit Trainingsstatistiken. Daten sind nicht öffentlich. |
| **Match-Score** | Punktzahl, die ein Teilnehmer innerhalb eines Matches erzielt (z. B. „16:5"). |
| **Liga-Punkte** | Punktzahl, die ein Teilnehmer aufgrund seiner Platzierung in einem Turnier für die Saisonwertung erhält. |
| **Turnier-Faktor** | Multiplikator für Liga-Punkte, der die Bedeutung eines Turniers ausdrückt (z. B. 1.0 Standard, 1.5 Meisterschaft). |

---

## 2. Stakeholder und Rollen

| Rolle | Beschreibung |
|---|---|
| **Plattform-Administrator** | Betreut die App plattformweit, pflegt globale Stammdaten (Vereine, Ligen, Punkte-Skalen, Turnier-Faktor-Freigaben). Ernennt Liga-Administratoren und Vereinsadministratoren. |
| **Liga-Administrator** | Vom Plattform-Administrator pro Liga ernannt (eine oder mehrere Personen pro Liga). Einzige Rolle, die mid-season-Liga-Wechsel autorisieren darf. Hat sonst keine Sonderrechte. |
| **Veranstalter** | Erstellt Turniere, verwaltet Anmeldungen, führt das Turnier am Spieltag durch. Kann eine Privatperson oder ein Verein sein. |
| **Co-Veranstalter** | Vom Hauptveranstalter eingeladen, kann Live-Management-Aufgaben übernehmen. |
| **Vereinsadministrator** | Vom Plattform-Administrator für einen Verein bestimmt. Verwaltet Vereinsmitglieder, vergibt vereinsinterne Rollen, kann Turniere im Namen des Vereins ausrichten. |
| **Vereinsmitglied** | Spieler, der einem Verein angehört, mit optionaler vereinsinterner Rolle. |
| **Team-Mitglied** | Spieler im Pool eines Teams. Registrierte Team-Mitglieder haben Captain-Rechte; Gast-Spieler im Pool haben nur Spielrechte, keine Verwaltungsrechte. |
| **Spieler (registriert)** | Nutzer mit eigenem Konto. |
| **Gast-Spieler** | Wird von einem Team-Mitglied ohne eigenes Konto erfasst. |
| **Zuschauer** | Person ohne Konto, die öffentliche Turnierinformationen ansieht. |

---

## 3. Funktionale Anforderungen

### 3.1 Authentifizierung und Profile (FR-AUTH)

- **FR-AUTH-1 (MUSS):** Nutzer können sich mit Google-OAuth registrieren und anmelden. *Bereits umgesetzt.*
- **FR-AUTH-2 (MUSS):** Jeder Nutzer hat ein Profil mit Anzeigename (Nickname), optional Vorname/Nachname, Heimatverein, Landeskennung und Avatar.
- **FR-AUTH-3 (MUSS):** Nutzer können ihren Anzeigenamen jederzeit ändern.
- **FR-AUTH-4 (MUSS):** Nutzer können ihr Konto und ihre Daten löschen lassen.
- **FR-AUTH-5 (MUSS):** Nutzer können ihre Sichtbarkeits-Einstellungen pro Datenkategorie festlegen.
- **FR-AUTH-6 (KANN):** Nutzer können ihre Daten als Datei exportieren.

### 3.2 Vereine (FR-CLUB)

- **FR-CLUB-1 (MUSS):** Vereine werden vom Plattform-Administrator angelegt und gepflegt.
- **FR-CLUB-2 (MUSS):** Jeder Verein hat: Name, optional Logo, Beschreibung, Heimatort, Gründungsjahr.
- **FR-CLUB-3 (MUSS):** Der Plattform-Administrator bestimmt für jeden Verein einen oder mehrere Vereinsadministratoren.
- **FR-CLUB-4 (MUSS):** Vereinsadministratoren können Mitglieder verwalten, Rollen vergeben und Turniere im Namen des Vereins ausrichten.
- **FR-CLUB-5 (MUSS):** Spieler können einem oder mehreren Vereinen angehören. Vereinsmitgliedschaft wird auf Einladung erstellt und vom Spieler bestätigt.
- **FR-CLUB-6 (MUSS):** Ein Veranstalter kann „im eigenen Namen" oder „im Namen eines Vereins" auftreten, sofern er Vereinsadministrator dieses Vereins ist.
- **FR-CLUB-7 (MUSS):** Vereine haben eine öffentliche Profilseite mit Mitgliedern und ausgerichteten Turnieren.
- **FR-CLUB-8 (KANN):** Vereinsadministratoren können vereinsinterne Beiträge oder Nachrichten verfassen.

### 3.3 Freundschaften und Privatsphäre (FR-SOCIAL)

- **FR-SOCIAL-1 (MUSS):** Spieler können anderen Spielern Freundschaftsanfragen senden.
- **FR-SOCIAL-2 (MUSS):** Freundschaften werden erst nach beidseitiger Bestätigung gültig.
- **FR-SOCIAL-3 (MUSS):** Spieler können Freundschaften jederzeit auflösen.
- **FR-SOCIAL-4 (MUSS):** Trainingsstatistiken sind ausschließlich für bestätigte Freunde einsehbar.
- **FR-SOCIAL-5 (MUSS):** Turnierstatistiken sind standardmäßig öffentlich sichtbar.
- **FR-SOCIAL-6 (SOLL):** Spieler können andere Spieler blockieren.

### 3.4 Erweitertes Spielerprofil (FR-PROFILE)

- **FR-PROFILE-1 (MUSS):** Das öffentliche Profil zeigt Anzeigename, Avatar, Heimatverein, Land, aktuelle globale Platzierung, aktuelle Liga-Zugehörigkeit, aktuelle Team-Mitgliedschaften.
- **FR-PROFILE-2 (MUSS):** Das Profil zeigt aggregierte Turnier-Statistiken.
- **FR-PROFILE-3 (MUSS):** Das Profil zeigt die Turnierhistorie, filterbar nach Saison, Liga und Turnierformat.
- **FR-PROFILE-4 (MUSS):** Das Profil zeigt die Match-Historie, filterbar nach Gegner, Turnier, Format und Ergebnis.
- **FR-PROFILE-5 (MUSS):** Das Profil zeigt Head-to-Head-Statistiken.
- **FR-PROFILE-6 (SOLL):** Rating-Verlauf als Diagramm.
- **FR-PROFILE-7 (MUSS):** Trainingsstatistiken sind nur für bestätigte Freunde sichtbar.
- **FR-PROFILE-8 (MUSS):** Das Profil zeigt die Liga-Historie (in welcher Liga das Team/der Spieler pro Saison spielte).

### 3.5 Turnier-Konfiguration durch Veranstalter (FR-CFG)

- **FR-CFG-1 (MUSS):** Teamgröße (1 = Einzel, 2, 3, 6 oder benutzerdefiniert).
- **FR-CFG-2 (MUSS):** Minimal- und Maximal-Teilnehmerzahl.
- **FR-CFG-3 (MUSS):** Anmeldefenster mit Öffnungs- und Schließdatum.
- **FR-CFG-4 (MUSS):** Sichtbarkeit der Anmeldung (öffentlich oder nur per Einladung).
- **FR-CFG-5 (MUSS):** Auswahl des Turnierformats (siehe FR-FMT).
- **FR-CFG-6 (MUSS):** Score-System (EKC oder klassisch, mit anpassbaren Parametern).
- **FR-CFG-7 (MUSS):** Match-Format der Vorrunde: Anzahl Sätze, Rundenzeit, Verhalten bei Zeitablauf.
- **FR-CFG-8 (MUSS):** Match-Format der KO-Phase: separate Konfiguration von der Vorrunde.
- **FR-CFG-9 (MUSS):** Anzahl Pitches, optional mit Namen oder Sponsoren pro Pitch.
- **FR-CFG-10 (MUSS):** BYE-Score.
- **FR-CFG-11 (MUSS):** Forfeit-Score.
- **FR-CFG-12 (MUSS):** Forfeit-Buchholz-Verhalten.
- **FR-CFG-13 (MUSS):** Reihenfolge der Tiebreaker-Kriterien.
- **FR-CFG-14 (MUSS):** Anspielregel.
- **FR-CFG-15 (MUSS):** Liga-Zuordnung – welche Ligen am Turnier teilnehmen dürfen (eine oder mehrere; bei mehreren handelt es sich um ein Shared Tournament).
- **FR-CFG-16 (MUSS):** Saison-Zuordnung.
- **FR-CFG-17 (MUSS):** Veranstalter-Auftritt: „im eigenen Namen" oder „im Namen eines Vereins".
- **FR-CFG-18 (MUSS):** Liga-Punkte-Konfiguration (siehe FR-POINTS):
  - Modus: „Globale Formel" oder „Eigene Punkte".
  - Bei „Globale Formel": gewünschter Turnier-Faktor (vom Plattform-Administrator freizugeben).
  - Bei „Eigene Punkte": Punkte-Stufung und optionale Einzelplatz-Überschreibungen.
  - Zählt das Turnier für das globale Ranking: ja/nein.
- **FR-CFG-19 (SOLL):** Vorlagen für häufige Turniertypen.
- **FR-CFG-20 (MUSS):** Solange das Turnier den Status „Entwurf" hat, kann jede Einstellung geändert werden.
- **FR-CFG-21 (MUSS):** Nach Veröffentlichung sind Format, Scoring und Punkte-Konfiguration eingefroren.

### 3.6 Anmeldung (FR-REG)

- **FR-REG-1 (MUSS):** Spieler können sich zu Einzelturnieren anmelden.
- **FR-REG-2 (MUSS):** Jedes registrierte Team-Mitglied kann sein Team zu einem Teamturnier anmelden. Es bestimmt dabei das Roster aus dem Team-Pool.
- **FR-REG-3 (MUSS):** Anmeldungen sind nur im konfigurierten Anmeldefenster möglich.
- **FR-REG-4 (MUSS):** Bei Erreichen der Obergrenze landen weitere Anmeldungen auf einer Warteliste.
- **FR-REG-5 (MUSS):** Bei Rücktritt rückt der oberste auf der Warteliste nach.
- **FR-REG-6 (MUSS):** Der Veranstalter kann Anmeldungen bestätigen, ablehnen, in die Warteliste verschieben oder zurückziehen.
- **FR-REG-7 (MUSS):** Anmeldungen können bis zum konfigurierten Cutoff zurückgezogen werden. Auch das Zurückziehen kann durch jedes Team-Mitglied erfolgen.
- **FR-REG-8 (MUSS):** Am Turniertag können Teilnehmer eingecheckt werden.
- **FR-REG-9 (SOLL):** Self-Check-In via QR-Code.
- **FR-REG-10 (SOLL):** Anmeldeliste exportierbar.
- **FR-REG-11 (MUSS):** Bei Shared Tournaments muss jedes Team bei der Anmeldung seine aktuelle Liga-Zugehörigkeit nachweisen. Diese wird aus dem System gelesen und ist nicht selbst wählbar.
- **FR-REG-12 (MUSS):** Beim Anmelden eines Teams zu einem Turnier mit Teamgröße N wählt das anmeldende Mitglied N Spieler aus dem Pool als Roster aus. Mindestens ein Mitglied des Rosters muss registriert sein (kein reines Gast-Roster).

### 3.7 Teams und Team-Mitgliedschaft (FR-TEAM)

#### 3.7.1 Team-Pool

- **FR-TEAM-1 (MUSS):** Jeder registrierte Nutzer kann ein Team gründen. Der gründende Nutzer wird automatisch erstes Mitglied des Pools.
- **FR-TEAM-2 (MUSS):** Ein Team hat: Name, optional Logo, Heimatverein, Land, Liga-Zugehörigkeit.
- **FR-TEAM-3 (MUSS):** Der Pool eines Teams hat keine Obergrenze für die Anzahl Mitglieder.
- **FR-TEAM-4 (MUSS):** Mitglieder des Pools sind registrierte Nutzer oder Gast-Spieler.

#### 3.7.2 Captain-Rechte aller Mitglieder

- **FR-TEAM-5 (MUSS):** Alle registrierten Mitglieder eines Team-Pools haben Captain-Rechte. Es gibt keinen einzelnen „Lead-Captain" oder „Haupt-Captain". Captain-Rechte umfassen:
  - Andere registrierte Spieler in den Pool einladen.
  - Gast-Spieler in den Pool aufnehmen.
  - Mitglieder aus dem Pool entfernen (offener Punkt 1: Schutz gegen Missbrauch).
  - Team-Stammdaten ändern (Name, Logo, Heimatverein).
  - Team zu Turnieren anmelden (FR-REG-2).
  - Roster für ein angemeldetes Turnier festlegen und anpassen (siehe 3.7.3).
  - Liga-Wechsel beantragen (siehe FR-GLB-11).
  - Scores für Matches eintragen (siehe FR-SCORE).
- **FR-TEAM-6 (MUSS):** Gast-Spieler im Pool haben keine Captain-Rechte. Sie können nur als Spieler im Roster eingesetzt werden.
- **FR-TEAM-7 (MUSS):** Der Gründer eines Teams hat keine Sonderrechte gegenüber anderen registrierten Mitgliedern. Seine Identität wird historisch dokumentiert (im Audit-Log und im Team-Profil).
- **FR-TEAM-8 (MUSS):** Einladungen in den Pool müssen vom eingeladenen Nutzer bestätigt werden, bevor die Mitgliedschaft wirksam wird.
- **FR-TEAM-9 (MUSS):** Gast-Spieler werden mit Anzeigenamen erfasst; das einladende Mitglied bestätigt das Einverständnis des Gast-Spielers.
- **FR-TEAM-10 (SOLL):** Gast-Spieler können später ihren Eintrag „beanspruchen" und in einen registrierten Account überführen.
- **FR-TEAM-11 (MUSS):** Ein registrierter Nutzer kann gleichzeitig im Pool mehrerer Teams sein. Er kann aber nicht im Roster zweier Teams desselben Turniers stehen.

#### 3.7.3 Roster pro Turnier

- **FR-TEAM-12 (MUSS):** Beim Anmelden zu einem Turnier wird aus dem Pool ein Roster gebildet, das genau der konfigurierten Teamgröße entspricht.
- **FR-TEAM-13 (MUSS):** Das Roster kann während des Turniers durch jedes Team-Mitglied (mit Captain-Rechten) angepasst werden, um Ausfälle (Krankheit, Verletzung) zu kompensieren.
- **FR-TEAM-14 (MUSS):** Jede Roster-Änderung wird im Audit-Log mit Zeitstempel, durchführendem Mitglied und Grund (optional) festgehalten.
- **FR-TEAM-15 (MUSS):** Ein Roster-Wechsel ist bis zum Ende des Turniers möglich; nach Turnierabschluss ist das Roster eingefroren.
- **FR-TEAM-16 (MUSS):** Pro Match wird automatisch das aktuelle Roster als Match-Teilnehmer übernommen. Eine zusätzliche per-Match-Auswahl der aktiven Spieler ist nicht zwingend, kann aber als KANN-Erweiterung (z. B. „Reservespieler") vorgesehen werden (offener Punkt 2).

#### 3.7.4 Liga-Zugehörigkeit

- **FR-TEAM-17 (MUSS):** Jedes Team hat eine Liga-Zugehörigkeit, die von den Liga-Zuordnungen seiner Spieler unabhängig ist.
- **FR-TEAM-18 (MUSS):** Beim Gründen eines Teams wählt das gründende Mitglied die initiale Liga (Default-Vorschlag: Liga B für Haupt-Tour, Liga C für Neben-Tour, gemäß Schweizer Modell).

#### 3.7.5 Team auflösen

- **FR-TEAM-19 (MUSS):** Ein Team kann nur aufgelöst werden, wenn alle aktuell registrierten Mitglieder zustimmen, oder wenn das Team keine registrierten Mitglieder mehr hat (das letzte registrierte Mitglied verlässt das Team).
- **FR-TEAM-20 (MUSS):** Aufgelöste Teams bleiben in den Archiven sichtbar (Historie). Sie können nicht reaktiviert werden.

### 3.8 Turnierformate (FR-FMT)

- **FR-FMT-1 (MUSS):** Reines KO (Single Elimination), mit oder ohne Spiel um Platz 3.
- **FR-FMT-2 (MUSS):** Round Robin.
- **FR-FMT-3 (MUSS):** Schochmodus.
- **FR-FMT-4 (MUSS):** Schweizer System.
- **FR-FMT-5 (MUSS):** Gruppenphase + KO.
- **FR-FMT-6 (MUSS):** Schoch + KO.
- **FR-FMT-7 (MUSS):** Schweizer System + KO.
- **FR-FMT-8 (MUSS):** Shared Tournament mit Split nach Vorrunde (Top X % ins Hauptbracket, Rest ins Sekundärbracket).
- **FR-FMT-9 (KANN):** Double Elimination (späterer Ausbau).
- **FR-FMT-10 (MUSS):** Bracket-Seedung erfolgt automatisch nach Vorrunden-Rangliste, manuell überschreibbar.
- **FR-FMT-11 (MUSS):** Byes in KO-Runde 1 werden höher gesetzten Teilnehmern zugeteilt.

### 3.9 Paarungsgenerierung (FR-PAIR)

- **FR-PAIR-1 (MUSS):** System generiert Paarungen automatisch.
- **FR-PAIR-2 (MUSS):** Paarungsstrategie konfigurierbar: „1 gegen 2", „Top gegen Bottom", „Dänisches System".
- **FR-PAIR-3 (MUSS):** Standard: keine Wiederholungen in der Vorrunde, abschaltbar.
- **FR-PAIR-4 (MUSS):** Pro Turnier maximal ein BYE pro Teilnehmer.
- **FR-PAIR-5 (MUSS):** BYE bevorzugt für schwächste verbleibende Teilnehmer ohne bisherigen BYE.
- **FR-PAIR-6 (MUSS):** Bei nicht-auflösbaren Konflikten Hinweis an Veranstalter.
- **FR-PAIR-7 (MUSS):** Veranstalter kann Paarungen vor Rundenstart manuell ändern.
- **FR-PAIR-8 (MUSS):** Initialpaarung: zufällig, nach Liga-Ranking oder manuell.

### 3.10 Match-Durchführung (FR-MATCH)

- **FR-MATCH-1 (MUSS):** Jedes Match einem Pitch zugewiesen.
- **FR-MATCH-2 (MUSS):** Veranstalter kann Matches per Drag-and-Drop verschieben.
- **FR-MATCH-3 (MUSS):** Match-Zustände gemäß Detail-Spec „Score-Eingabe und Konfliktauflösung".
- **FR-MATCH-4 (MUSS):** Matches einer Runde starten gleichzeitig mit der Runden-Clock.
- **FR-MATCH-5 (MUSS):** Veranstalter kann Match verzögern oder abbrechen.
- **FR-MATCH-6 (MUSS):** Bei Turnier-Abbruch: kein Zwischenzustand, Turnier ist „in_progress" oder „abgebrochen".
- **FR-MATCH-7 (MUSS):** Bei No-Show Forfeit-Wertung gemäß FR-CFG-11.
- **FR-MATCH-8 (MUSS):** Ausfall mid-Turnier: alle nachfolgenden Matches automatisch Forfeit zugunsten der Gegner mit Max-Score.
- **FR-MATCH-9 (MUSS):** Forfeit-Verhalten in Buchholz gemäß FR-CFG-12.

### 3.11 Score-Eingabe (FR-SCORE)

> **Detaillierung:** siehe Detail-Spezifikation „Score-Eingabe und Konfliktauflösung".

- **FR-SCORE-1 (MUSS):** Jedes registrierte Team-Mitglied kann für Matches seines Teams Scores eintragen. Die zuletzt vor Versuchs-Abschluss eingegangene Eingabe gilt als Team-Eingabe.
- **FR-SCORE-2 (MUSS):** Eingabe pro Satz: Basekubbs und Königsstoß.
- **FR-SCORE-3 (MUSS):** Live-Vorschau des Match-Scores.
- **FR-SCORE-4 (MUSS):** Plausibilitätsprüfung.
- **FR-SCORE-5 (MUSS):** Automatischer Score bei BYE.
- **FR-SCORE-6 (MUSS):** Automatischer Score bei Forfeit.
- **FR-SCORE-7 (MUSS):** Veranstalter kann Scores manuell setzen (mit Audit-Log).
- **FR-SCORE-8 (SOLL):** Mitlauf-Modus während des Spiels.

### 3.12 Konfliktauflösung (FR-CONF)

> **Detaillierung:** siehe Detail-Spezifikation „Score-Eingabe und Konfliktauflösung".

- **FR-CONF-1 (MUSS):** Übereinstimmende Eingaben → Match abgeschlossen.
- **FR-CONF-2 (MUSS):** Drei Versuche bei Abweichung.
- **FR-CONF-3 (MUSS):** Nach drei Fehlversuchen → Strittig, Veranstalter benachrichtigt und trägt finalen Score selbst ein.
- **FR-CONF-4 (MUSS):** Manuelle Eskalation an den Veranstalter durch ein Team-Mitglied ist jederzeit vor Versuch 3 möglich.
- **FR-CONF-5 (MUSS):** Erinnerung bei einseitiger Eingabe wiederholend alle 5 Minuten, bis beide Seiten eingetragen haben oder die Eskalation an den Veranstalter erfolgt.
- **FR-CONF-6 (MUSS):** Alle Versuche bleiben nachvollziehbar.
- **FR-CONF-7 (MUSS):** Differenz wird beiden Seiten genau angezeigt.

### 3.13 Turnier-Rangliste (FR-RANK)

- **FR-RANK-1 (MUSS):** Rangliste jederzeit live abrufbar.
- **FR-RANK-2 (MUSS):** Berechnung nur auf Basis bestätigter Matches.
- **FR-RANK-3 (MUSS):** Primärkriterium: Summe der eigenen Match-Punkte.
- **FR-RANK-4 (MUSS):** Tiebreaker in konfigurierbarer Reihenfolge. Verfügbare Tiebreaker:

  | Bezeichner | Definition |
  |---|---|
  | **Total Points** | Summe aller Match-Punkte. |
  | **Buchholz minus H2H** | Summe der Gegnerpunkte minus direktem Vergleich. |
  | **Median-Buchholz** | Buchholz ohne besten und schlechtesten Gegner. |
  | **Kubb-Differenz** | Getroffene minus erhaltene Basekubbs. |
  | **Direkter Vergleich** | Wer hat das direkte Match gewonnen. |
  | **Anzahl Siege** | Anzahl gewonnener Matches. |
  | **Zufall** | Auslosung. |

- **FR-RANK-5 (MUSS):** Tiebreaker-Werte transparent für jeden Teilnehmer angezeigt.
- **FR-RANK-6 (MUSS):** Rangliste nach Liga filterbar (bei Shared Tournaments).
- **FR-RANK-7 (MUSS):** Forfeit-Wertung gemäß FR-CFG-11 und FR-CFG-12.

### 3.14 Liga-Punkte-System (FR-POINTS)

Dieses Kapitel beschreibt, wie aus einer Turnier-Platzierung Liga-Punkte für die Saisonwertung berechnet werden.

#### 3.14.1 Globale Punkte-Formel

- **FR-POINTS-1 (MUSS):** Die Standard-Formel berechnet sich nach dem Schema:

  ```
  Basispunkte = (Teilnehmerzahl − eigene Platzierung + 1) + Stufungs-Bonus
  
  Stufungs-Bonus (kumuliert von hinten nach vorne):
    Plätze ab 33 abwärts (letzter Platz):  je Rang +0 Bonus (nur Grundabstand 1)
    Plätze 17 bis 32:                       je Rang +1 Bonus (insgesamt 2 pro Rang)
    Plätze 9 bis 16:                        je Rang +2 Bonus (insgesamt 3 pro Rang)
    Plätze 5 bis 8:                         je Rang +3 Bonus (insgesamt 4 pro Rang)
    Plätze 1 bis 4:                         je Rang +4 Bonus (insgesamt 5 pro Rang)
  
  Endpunkte = Basispunkte × Turnier-Faktor × Liga-Faktor
  ```

- **FR-POINTS-2 (MUSS):** Die Formel-Parameter (Stufungs-Bonus-Schwellen und -Werte) sind vom Plattform-Administrator konfigurierbar.

#### 3.14.2 Turnier-Faktoren

- **FR-POINTS-3 (MUSS):** Es gibt mehrere Turnier-Kategorien mit unterschiedlichen Faktoren:

  | Kategorie | Default-Faktor | Beispiel |
  |---|---|---|
  | Standard | 1.0 | Lokales Liga-Turnier |
  | Premium | 1.25 | Etablierte Tour-Turniere |
  | Meisterschaft | 1.5 | Schweizer Meisterschaft, Masters |
  | International | 2.0 | EKC, WM (falls geführt) |

- **FR-POINTS-4 (MUSS):** Die Kategorien und Faktoren sind vom Plattform-Administrator konfigurierbar.
- **FR-POINTS-5 (MUSS):** Bei der Turnier-Erstellung wählt der Veranstalter eine gewünschte Kategorie aus. Bei jeder Kategorie außer „Standard" muss der Plattform-Administrator die Zuordnung freigeben, bevor das Turnier veröffentlicht werden kann.

#### 3.14.3 Liga-Faktoren

- **FR-POINTS-6 (MUSS):** Jede Liga hat einen Liga-Faktor, der vom Plattform-Administrator gepflegt wird. Default ist 1.0 für alle Ligen.
- **FR-POINTS-7 (MUSS):** Der Liga-Faktor wird in der Formel von FR-POINTS-1 angewendet.

#### 3.14.4 Punkte-Modi pro Turnier

- **FR-POINTS-8 (MUSS):** Bei der Turnier-Erstellung wählt der Veranstalter einen der folgenden Modi:

  **Modus A – „Globale Formel":** Das Turnier folgt der Standard-Formel (FR-POINTS-1) mit dem freigegebenen Turnier-Faktor.

  **Modus B – „Eigene Punkte":** Der Veranstalter definiert eine eigene Stufungs-Formel. Zusätzlich kann er einzelne Plätze überschreiben (z. B. Platz 1 = 250, Platz 2 = 200, sonst nach Stufungs-Formel).

- **FR-POINTS-9 (MUSS):** Im Modus „Eigene Punkte" zählt das Turnier standardmäßig nur für die Turnier-interne Wertung, nicht für das offizielle Liga-Ranking.
- **FR-POINTS-10 (MUSS):** Der Veranstalter kann im Modus „Eigene Punkte" beim Plattform-Administrator beantragen, dass die Custom-Punkte trotzdem für das globale Ranking zählen.
- **FR-POINTS-11 (MUSS):** Der Plattform-Administrator prüft Anträge auf Custom-Punkte-Freigabe und entscheidet darüber. Bei Freigabe wird das Turnier offiziell für das globale Ranking gezählt.
- **FR-POINTS-12 (MUSS):** Im Modus „Eigene Punkte" ist der Turnier-Faktor nicht anwendbar; die definierten Punkte sind absolut. Liga-Faktoren werden trotzdem angewendet, sofern das Turnier offiziell freigegeben ist.
- **FR-POINTS-13 (MUSS):** Wenn ein Custom-Punkte-Turnier nachträglich freigegeben wird, werden die Punkte rückwirkend in die laufende Saison eingebucht. Bei bereits abgeschlossener Saison ist keine rückwirkende Einbuchung möglich.

#### 3.14.5 Punkte-Vergabe bei Shared Tournaments

- **FR-POINTS-14 (MUSS):** In einem Shared Tournament wird die Turnier-Platzierung allein nach Leistung vergeben. Ein Liga-B-Team kann das Turnier gewinnen.
- **FR-POINTS-15 (MUSS):** Die Liga-Punkte werden pro Liga getrennt berechnet. Jedes Team erhält Punkte für seine eigene Liga-Saisontabelle, basierend auf seiner Platzierung **innerhalb der Teams seiner Liga** im Turnier.
  - Beispiel: Ein Liga-B-Team wird Gesamt-Erster eines A+B-Shared-Tournaments. Es ist gleichzeitig das beste Liga-B-Team und erhält die Liga-B-Punkte für „Platz 1 der Liga B".
  - Ein Liga-A-Team wird Gesamt-Dritter und ist gleichzeitig das beste Liga-A-Team. Es erhält die Liga-A-Punkte für „Platz 1 der Liga A".

#### 3.14.6 Einzelturniere

- **FR-POINTS-16 (MUSS):** Einzelturniere folgen derselben Basisformel (FR-POINTS-1), werden aber in einer separaten Einzelranking-Liste geführt.
- **FR-POINTS-17 (MUSS):** Die Einzelranking-Liste ist eine einzige globale Liste ohne Liga-Unterteilung.
- **FR-POINTS-18 (MUSS):** Für die Einzelranking-Saisonwertung zählen die besten N Resultate (Default 6, konfigurierbar). Es gibt kein Masters-Turnier-Bonus für die Einzelwertung.

### 3.15 Globales Ranking und Liga-System (FR-GLB)

- **FR-GLB-1 (MUSS):** Globales Ranking pro Liga, basierend auf Liga-Punkten gemäß FR-POINTS.
- **FR-GLB-2 (MUSS):** Standardmäßig drei Ligen: A, B, C. Plattform-Administrator kann zusätzliche Ligen anlegen.
- **FR-GLB-3 (MUSS):** Jeder Spieler und jedes Team gehört einer Liga an.
- **FR-GLB-4 (MUSS):** Saisonwertung berücksichtigt eine konfigurierbare Anzahl der besten Resultate pro Saison und Liga. Default:

  | Liga / Wertung | Anzahl gewerteter Resultate |
  |---|---|
  | Liga A (Team) | Top 9 plus Masters |
  | Liga B (Team) | Top 9 plus Masters |
  | Liga C (Team) | Top 6 plus Masters |
  | Einzelranking (gesamt) | Top 6, kein Masters |

- **FR-GLB-5 (MUSS):** Saisonzeitraum: typischerweise Mai bis Oktober. Genaues Datum konfigurierbar pro Saison.
- **FR-GLB-6 (MUSS):** Nach Saisonende wird die Saison-Rangliste eingefroren und archiviert.
- **FR-GLB-7 (MUSS):** Gast-Spieler werden im globalen Ranking nicht geführt.

#### 3.15.1 Liga-Zuordnung neuer Teams und Spieler

- **FR-GLB-8 (MUSS):** Beim ersten Eintrag eines neuen Teams in der App wählt das gründende Mitglied die initiale Liga (Default-Vorschlag basierend auf Turnier-Typ: Liga B bei erstem Hauptturnier, Liga C bei erstem Nebenturnier).
- **FR-GLB-9 (MUSS):** Bei Einzelturnieren startet ein Spieler ohne Vor-Historie in der niedrigsten Einstufung; bei vorhandener Team-Historie wird die Einstufung als Default vorgeschlagen.

#### 3.15.2 Off-season-Liga-Wechsel

- **FR-GLB-10 (MUSS):** Das reguläre Wechselfenster ist zwischen Dezember und Anfang April (genauer Zeitraum pro Saison konfigurierbar).
- **FR-GLB-11 (MUSS):** Off-season-Liga-Wechsel werden von einem Team-Mitglied (für Teams) oder vom Spieler selbst (für Einzelspieler) beantragt. Sie sind ohne Genehmigung wirksam, sobald sie innerhalb des Wechselfensters bestätigt werden.
- **FR-GLB-12 (MUSS):** Ein off-season-Wechsel kann zu jeder Zeit innerhalb des Wechselfensters erfolgen, gilt aber erst ab Beginn der nächsten Saison.
- **FR-GLB-13 (MUSS):** Bis zum Saisonbeginn kann der Wechsel ohne Begründung rückgängig gemacht werden, sofern das Wechselfenster noch offen ist.

#### 3.15.3 Mid-season-Liga-Wechsel

- **FR-GLB-14 (MUSS):** Mid-season-Liga-Wechsel (außerhalb des Wechselfensters) sind ausschließlich durch einen Liga-Administrator durchführbar.
- **FR-GLB-15 (MUSS):** Ein mid-season-Wechsel wird vom Liga-Administrator manuell ausgelöst, üblicherweise nach Rücksprache mit dem Team oder Spieler.
- **FR-GLB-16 (MUSS):** Ein mid-season-Wechsel ist sofort nach Durchführung wirksam.

#### 3.15.4 Behandlung der Liga-Punkte bei Wechsel

- **FR-GLB-17 (MUSS):** Liga-Punkte sind liga-spezifisch und saison-spezifisch. Sie werden nie zwischen Ligen oder zwischen Saisons übertragen, auch nicht bei Verbleib in derselben Liga.
- **FR-GLB-18 (MUSS):** Bei einem off-season-Wechsel (FR-GLB-11) beginnt das Team/der Spieler in der ersten Saison nach dem Wechsel mit 0 Punkten in der neuen Liga.
- **FR-GLB-19 (MUSS):** Bei einem mid-season-Wechsel (FR-GLB-14) bleiben die in der aktuellen Saison bereits gesammelten Liga-Punkte in der alten Liga-Saisontabelle eingefroren. Das Team/der Spieler erscheint mit diesen Punkten weiterhin in der eingefrorenen Saisontabelle der alten Liga. Ab dem Zeitpunkt des Wechsels startet er mit 0 Punkten in der neuen Liga-Saisontabelle.
- **FR-GLB-20 (MUSS):** Die Liga-Historie eines Teams oder Spielers (welche Liga in welcher Saison, inkl. mid-season-Wechseln) ist im jeweiligen Profil öffentlich einsehbar.

#### 3.15.5 Minimalgröße für Liga-Trennung in Turnieren

- **FR-GLB-21 (MUSS):** Eine Trennung zwischen Liga A und Liga B in der Saisonwertung eines Turniers kommt nur zustande, wenn mindestens 8 Teams pro Liga angemeldet sind. Diese Schwelle ist vom Plattform-Administrator konfigurierbar.
- **FR-GLB-22 (MUSS):** Wird die Schwelle nicht erreicht, werden die Liga-B-Teams in die Liga-A-Wertung dieses Turniers integriert (oder umgekehrt, je nach Konfiguration). Diese Sonderregelung gilt nur für die Saisonwertung des betreffenden Turniers; die Liga-Zugehörigkeit der Teams bleibt unverändert.

### 3.16 Benachrichtigungen (FR-NOT)

- **FR-NOT-1 (MUSS):** Push bei Start der Runden-Clock.
- **FR-NOT-2 (MUSS):** Benachrichtigungen für jedes Team-Mitglied bei Anmelde-Status, Konflikten, Verzögerungen.
- **FR-NOT-3 (MUSS):** Veranstalter bei eskalierten Konflikten.
- **FR-NOT-4 (MUSS):** Bei Absage oder Abbruch alle Teilnehmer per Push und In-App-Postfach.
- **FR-NOT-5 (MUSS):** Kategorien an-/abschaltbar.
- **FR-NOT-6 (MUSS):** Eskalations-Pushs ignorieren Stummschaltung.
- **FR-NOT-7 (MUSS):** Internes In-App-Postfach.
- **FR-NOT-8 (MUSS):** Keine E-Mails.
- **FR-NOT-9 (MUSS):** Erinnerung an Liga-Wechselfenster: Push und In-App-Postfach im Dezember an alle Teams/Spieler.
- **FR-NOT-10 (MUSS):** Liga-Administrator wird per Push informiert, wenn ein mid-season-Wechsel von einem Team beantragt wird (siehe Hauptprozess 5.13.2).

### 3.17 Öffentliche Sichten (FR-PUB)

- **FR-PUB-1 (MUSS):** Öffentliche Übersichtsseite pro Turnier.
- **FR-PUB-2 (MUSS):** Übersichtsseite mit Stammdaten, Status, Anmelde-Button, Lageplan.
- **FR-PUB-3 (MUSS):** Öffentliche Live-Rangliste, bei Shared Tournament filterbar nach Liga.
- **FR-PUB-4 (MUSS):** „Aktuelle Runde"-Sicht mit laufender Runden-Clock.
- **FR-PUB-5 (MUSS):** „Alle Runden"-Archiv.
- **FR-PUB-6 (MUSS):** Bracket-Visualisierung in KO-Phase.
- **FR-PUB-7 (MUSS):** Spieler-Profile gemäß Privatsphäre-Einstellungen.
- **FR-PUB-8 (MUSS):** Vereins-Profile.
- **FR-PUB-9 (MUSS):** Team-Profile mit Pool-Mitgliedern, Liga-Historie und Turnier-Statistiken.
- **FR-PUB-10 (SOLL):** Vollbild-Streaming-Sicht.
- **FR-PUB-11 (MUSS):** Echtzeit-Aktualisierung ohne Reload.
- **FR-PUB-12 (MUSS):** Öffentliche Liga-Saisontabellen pro Liga, mit Filtern nach Saison. Einzelranking als eigene öffentliche Saisontabelle.

### 3.18 Live-Management während des Turniers (FR-LIVE)

- **FR-LIVE-1 (MUSS):** Veranstalter-Dashboard mit farbcodiertem Pitch-Status.
- **FR-LIVE-2 (MUSS):** Offene Konflikte und Eingaben prominent sichtbar.
- **FR-LIVE-3 (MUSS):** Runde manuell als beendet markierbar.
- **FR-LIVE-4 (MUSS):** Nächste Runde erst nach Abschluss der aktuellen.
- **FR-LIVE-5 (MUSS):** Runden-Clock, vom Veranstalter gestartet.
- **FR-LIVE-6 (MUSS):** Clock auf allen Sichten als Countdown.
- **FR-LIVE-7 (MUSS):** Pause, Verlängerung, vorzeitiges Ende durch Veranstalter.
- **FR-LIVE-8 (MUSS):** Konfiguriertes Zeitablauf-Verhalten.
- **FR-LIVE-9 (MUSS):** Globale Pause zwischen Runden.
- **FR-LIVE-10 (MUSS):** Turnierabbruch jederzeit möglich.

### 3.19 Lageplan (FR-MAP)

- **FR-MAP-1 (MUSS):** Upload als PNG oder JPEG.
- **FR-MAP-2 (MUSS):** Anzeige auf öffentlicher Übersichtsseite.
- **FR-MAP-3 (MUSS):** Jederzeit ersetz- oder löschbar.
- **FR-MAP-4 (MUSS):** Auch im Match-View einsehbar.
- **FR-MAP-5 (KANN):** Interaktive Marker (späterer Ausbau).

### 3.20 Veranstalter-Bewertung (FR-FEEDBACK)

- **FR-FEEDBACK-1 (MUSS):** Bewertung 1–5 Sterne nach Turnier-Ende.
- **FR-FEEDBACK-2 (MUSS):** Optionaler Textkommentar (max. 500 Zeichen).
- **FR-FEEDBACK-3 (MUSS):** Nur bestätigte Teilnehmer dürfen bewerten.
- **FR-FEEDBACK-4 (MUSS):** Bewertungsfenster 7 Tage nach Turnier-Ende.
- **FR-FEEDBACK-5 (MUSS):** Aggregierte Bewertung im Veranstalter-Profil.
- **FR-FEEDBACK-6 (MUSS):** Anonyme Bewertungen möglich.
- **FR-FEEDBACK-7 (MUSS):** Melde- und Lösch-Funktion für unangemessene Kommentare.

### 3.21 Administration (FR-ADM)

#### 3.21.1 Plattform-Administrator

- **FR-ADM-1 (MUSS):** Punkte-Formel, Stufungs-Bonus, Turnier-Faktoren konfigurierbar.
- **FR-ADM-2 (MUSS):** Liga-Faktoren pro Liga konfigurierbar.
- **FR-ADM-3 (MUSS):** Saisons öffnen, schließen, archivieren; Saisonzeitraum und Wechselfenster konfigurierbar.
- **FR-ADM-4 (MUSS):** Anzahl gewerteter Resultate pro Liga und für Einzelranking konfigurierbar.
- **FR-ADM-5 (MUSS):** Mindestgröße für Liga-Trennung konfigurierbar.
- **FR-ADM-6 (MUSS):** Vereine anlegen, bearbeiten, löschen; Vereinsadministratoren bestimmen.
- **FR-ADM-7 (MUSS):** Liga-Administratoren ernennen und entfernen.
- **FR-ADM-8 (MUSS):** Liga-Zugehörigkeiten von Spielern und Teams setzen (Sonderfall, normalerweise erfolgt das über die Selbst-Zuordnung oder Liga-Admin).
- **FR-ADM-9 (MUSS):** Turnier-Faktor-Anträge prüfen und freigeben.
- **FR-ADM-10 (MUSS):** Custom-Punkte-Freigabe-Anträge prüfen und freigeben.
- **FR-ADM-11 (MUSS):** Missbräuchliche Inhalte entfernen.
- **FR-ADM-12 (MUSS):** Admin-Dashboard für die genannten Aufgaben (CLI-Zugang akzeptabel).
- **FR-ADM-13 (SOLL):** Veranstalter-Berechtigungen vergeben oder entziehen.

#### 3.21.2 Liga-Administrator

- **FR-ADM-14 (MUSS):** Liga-Administrator sieht eine Liste der Teams und Einzelspieler in seiner Liga.
- **FR-ADM-15 (MUSS):** Liga-Administrator kann mid-season-Liga-Wechsel auslösen (FR-GLB-14).
- **FR-ADM-16 (MUSS):** Jeder mid-season-Wechsel wird mit Zeitstempel, ausführendem Liga-Administrator, betroffenem Team/Spieler, alter Liga, neuer Liga und optionaler Begründung im Audit-Log gespeichert.
- **FR-ADM-17 (MUSS):** Liga-Administrator hat keine Berechtigung für andere Verwaltungsaufgaben (keine Liga-Faktoren ändern, keine Turniere freigeben).

---

## 4. Nicht-funktionale Anforderungen

### 4.1 Performance (NFR-PERF)

- **NFR-PERF-1:** Rangliste mit bis zu 200 Teilnehmern unter 2 Sekunden.
- **NFR-PERF-2:** Aktualisierung der öffentlichen Rangliste nach Score-Bestätigung unter 2 Sekunden.
- **NFR-PERF-3:** Paarungsgenerierung bei 200 Teilnehmern unter 5 Sekunden.
- **NFR-PERF-4:** App-Start unter 3 Sekunden auf Mittelklasse-Smartphone.
- **NFR-PERF-5:** Runden-Clock-Abweichung maximal 1 Sekunde zwischen Clients.
- **NFR-PERF-6:** Berechnung der Liga-Saisontabelle nach Turnierabschluss unter 5 Sekunden, auch bei 500 Teams in der Liga.

### 4.2 Verfügbarkeit und Stabilität (NFR-AVAIL)

- **NFR-AVAIL-1:** Während laufender Turniere 99,9 % Zielverfügbarkeit.
- **NFR-AVAIL-2:** Keine verlorenen Score-Eingaben bei Verbindungsabbruch.
- **NFR-AVAIL-3:** Reconnect ohne Datenverlust.
- **NFR-AVAIL-4:** Wartungsfenster nicht in der Hauptsaison.

### 4.3 Offline-Toleranz (NFR-OFFLINE)

- **NFR-OFFLINE-1:** Match-Detailseite offline anzeigbar.
- **NFR-OFFLINE-2:** Score-Eingabe offline möglich (inkl. lokaler Zwischenspeicherung von noch nicht abgeschickten Entwürfen).
- **NFR-OFFLINE-3:** Offline-Anzeige sichtbar.
- **NFR-OFFLINE-4:** Keine Doppel-Übermittlung.
- **NFR-OFFLINE-5:** Geladene öffentliche Sichten offline einsehbar.
- **NFR-OFFLINE-6:** Runden-Clock läuft lokal weiter.

### 4.4 Sicherheit (NFR-SEC)

- **NFR-SEC-1:** TLS-Verschlüsselung.
- **NFR-SEC-2:** Score-Eingabe nur durch registrierte Team-Mitglieder des betreffenden Teams.
- **NFR-SEC-3:** Turnier-Änderungen nur durch Veranstalter.
- **NFR-SEC-4:** Keine Klartext-Speicherung von Passwörtern oder Tokens.
- **NFR-SEC-5:** Manipulationsversuche werden geloggt.

### 4.5 Datenschutz (NFR-PRIV)

- **NFR-PRIV-1:** Erfüllt DSG und DSGVO.
- **NFR-PRIV-2:** Gast-Spieler nur mit dokumentierter Zustimmung.
- **NFR-PRIV-3:** Recht auf Datenexport und Löschung.
- **NFR-PRIV-4:** Keine Klarnamen/E-Mail im öffentlichen Profil ohne Zustimmung.
- **NFR-PRIV-5:** Trainingsstatistiken nur für Freunde.
- **NFR-PRIV-6:** Konfigurierbare Profil-Sichtbarkeit.

### 4.6 Usability (NFR-UX)

- **NFR-UX-1:** Score-Eingabe in unter 30 Sekunden, robust gegen nasse Finger.
- **NFR-UX-2:** Sonnenlicht-tauglicher Kontrast.
- **NFR-UX-3:** Standard-Turnier in unter 5 Minuten anlegbar.
- **NFR-UX-4:** Smartphone, Tablet und Browser.
- **NFR-UX-5:** Häufige Aktionen in maximal 3 Taps.
- **NFR-UX-6:** Verständliche Fehlermeldungen.
- **NFR-UX-7:** Runden-Clock prominent sichtbar.

### 4.7 Skalierbarkeit (NFR-SCALE)

- **NFR-SCALE-1:** Turniere mit bis zu 500 Teilnehmern.
- **NFR-SCALE-2:** Mehrere parallele Turniere.
- **NFR-SCALE-3:** Lastspitzen bei populären Turnierstarts.

### 4.8 Lokalisierung (NFR-I18N)

- **NFR-I18N-1:** Deutsch als Default.
- **NFR-I18N-2:** Französisch und Englisch.
- **NFR-I18N-3:** Regionale Datums- und Zahlenformate.

### 4.9 Auditierbarkeit (NFR-AUDIT)

- **NFR-AUDIT-1:** Score-Änderungen protokolliert.
- **NFR-AUDIT-2:** Status-Wechsel protokolliert.
- **NFR-AUDIT-3:** Roster-Änderungen protokolliert.
- **NFR-AUDIT-4:** Liga-Wechsel protokolliert mit Zeitstempel, ursprünglicher Liga, neuer Liga, ausführender Person und Begründung (sofern vorhanden).
- **NFR-AUDIT-5:** Mitgliedschaftsänderungen im Team-Pool protokolliert (wer eingeladen, wer entfernt, wann).
- **NFR-AUDIT-6:** Audit-Log für Veranstalter und Plattform-Admin einsehbar.

---

## 5. Hauptprozesse

### 5.1 Prozess: Verein anlegen (Plattform-Administrator)

1. Plattform-Administrator öffnet Admin-Dashboard oder CLI.
2. Erfasst Vereinsdaten (Name, Logo, Heimatort, Gründungsjahr).
3. Bestimmt einen oder mehrere Vereinsadministratoren.
4. Ernannte Vereinsadministratoren werden per Push informiert.
5. Verein ist öffentlich sichtbar.

### 5.2 Prozess: Team gründen und Mitglieder einladen

1. Registrierter Nutzer wählt „Team gründen".
2. Erfasst Team-Stammdaten (Name, Logo, Heimatverein, initiale Liga).
3. Wird automatisch erstes Mitglied des Pools.
4. Lädt weitere Mitglieder per Suchfunktion oder Einladungs-Link ein.
5. Eingeladene Nutzer bestätigen die Einladung; danach sind sie Mitglieder mit Captain-Rechten.
6. Optional fügt jedes Mitglied Gast-Spieler in den Pool ein.

### 5.3 Prozess: Turnier ausschreiben

1. Veranstalter wählt „Neues Turnier".
2. Wählt zwischen Eigen-Auftritt oder Verein.
3. Durchläuft Konfigurations-Assistenten:
   - Stammdaten
   - Format und Match-Format
   - Punkte-Konfiguration (Globale Formel mit Faktor X, oder Eigene Punkte)
   - Tiebreaker, Pitches, BYE, Forfeit
   - Liga-Zuordnung
   - Anmeldefenster
   - Lageplan optional
4. Falls Turnier-Faktor über Standard oder Modus „Eigene Punkte" mit Ranking-Anspruch: System sendet Freigabe-Antrag an Plattform-Administrator.
5. Plattform-Administrator prüft und gibt frei (oder lehnt mit Begründung ab).
6. Bei Freigabe oder Standard-Konfiguration kann der Veranstalter veröffentlichen.

### 5.4 Prozess: Team-Mitglied meldet Team zu einem Turnier an

1. Ein registriertes Team-Mitglied öffnet die Turnier-Detailseite.
2. Bei offenem Anmeldefenster: „Anmelden"-Button aktiv.
3. Wählt aus mehreren Teams des Mitglieds (sofern es in mehreren Teams ist) das anzumeldende Team aus.
4. Bei Shared Tournament wird die aktuelle Liga-Zugehörigkeit des Teams automatisch übernommen.
5. Wählt das Roster aus dem Team-Pool: Anzahl der ausgewählten Spieler muss der Teamgröße entsprechen.
6. Anmeldung wird gesendet.
7. Alle Team-Mitglieder werden über die Anmeldung per Push informiert.
8. Veranstalter bestätigt, lehnt ab oder verschiebt auf Warteliste.

### 5.5 Prozess: Roster mid-Turnier anpassen (z. B. wegen Krankheit)

1. Ein Team-Mitglied erkennt, dass ein Roster-Spieler kurzfristig ausfällt.
2. Öffnet die Team-Sicht des laufenden Turniers.
3. Wählt „Roster anpassen".
4. Ersetzt ausfallenden Spieler durch anderen Pool-Spieler.
5. Optional: trägt Begründung ein.
6. Bestätigt; Änderung ist sofort wirksam.
7. Veranstalter und Turniergegner werden informiert.
8. Audit-Log dokumentiert die Änderung.

### 5.6 Prozess: Turnier starten

1. Anmeldefenster schließen.
2. Seeding durchführen (automatisch oder manuell).
3. Check-In am Turniertag.
4. No-Show-Teilnehmer entfernen.
5. Turnier starten, erste Runde generieren.

### 5.7 Prozess: Runde spielen mit Runden-Clock

1. Veranstalter sieht Paarungen, ruft „Runde starten".
2. Alle Team-Mitglieder bekommen Push mit Pitch-Nummer.
3. Roster-Spieler gehen an die Pitches.
4. Veranstalter startet Runden-Clock.
5. Alle Matches starten gleichzeitig.
6. Bei Ablauf: konfiguriertes Verhalten.
7. Veranstalter kann pausieren, verlängern, früher beenden.

### 5.8 Prozess: Score eintragen (Übersicht)

1. Match endet.
2. Ein Team-Mitglied jedes Teams trägt die Sätze ein.
3. App zeigt Live-Vorschau.
4. Bei Übereinstimmung: Match abgeschlossen.
5. Bei Abweichung: Konflikt-Flow (siehe Detail-Spec).
6. Bei BYE oder Forfeit: automatisch.

### 5.9 Prozess: Score-Konflikt auflösen (Übersicht)

1. Drei Versuche bei Abweichung; manuelle Eskalation jederzeit möglich.
2. Bei drei Fehlversuchen oder manueller Eskalation: Strittig.
3. Veranstalter wird hochpriorisiert benachrichtigt.
4. Veranstalter trägt finalen Score selbst ein.
5. Detail siehe Detail-Spec „Score-Eingabe und Konfliktauflösung".

### 5.10 Prozess: Teilnehmer fällt während des Turniers aus

Zwei Fälle:

**A) Roster-Spieler fällt aus, Team kann mit anderem Pool-Spieler weiterspielen:**
1. Team-Mitglied passt das Roster an (siehe 5.5).
2. Turnier läuft weiter.

**B) Ganzes Team kann nicht weiterspielen:**
1. Team-Mitglied oder Veranstalter meldet Ausfall.
2. Veranstalter bestätigt.
3. Alle nachfolgenden Matches dieses Teams automatisch Forfeit mit Max-Score zugunsten der Gegner.

### 5.11 Prozess: Runde abschließen und nächste generieren

1. Alle Matches bestätigt.
2. Veranstalter klickt „Nächste Runde generieren".
3. System generiert Paarungen und Pitch-Zuteilung.
4. Push an alle Team-Mitglieder.

### 5.12 Prozess: Übergang Vorrunde zu KO-Phase

1. System berechnet Endrangliste der Vorrunde.
2. **Bei Standard-Format:** Cut der Top-N.
3. **Bei Shared Tournament mit Split:** Teilnehmerfeld nach Quote geteilt.
4. System schlägt Bracket-Seedung vor.
5. Veranstalter kann manuell anpassen.
6. KO-Phase starten.

### 5.13 Prozess: Turnier abschließen

1. Letztes Match abgeschlossen.
2. Veranstalter prüft finale Rangliste.
3. Rangliste eingefroren.
4. System berechnet Liga-Punkte gemäß FR-POINTS:
   - Pro Teilnehmer und Liga wird die Punktzahl gemäß Modus und Konfiguration berechnet.
   - Bei Shared Tournament: Liga-Punkte pro Liga getrennt berechnet (FR-POINTS-15).
5. Liga-Saisontabellen aktualisieren sich.
6. Bewertungsfenster öffnet sich.
7. Nach 30 Tagen Archivierung.

### 5.14 Prozess: Veranstalter bewerten

1. Push an Teilnehmer nach Turnier-Ende.
2. Bewertung mit Sternen und optionalem Kommentar.
3. Optional anonym.
4. Aggregation im Veranstalter-Profil.

### 5.15 Prozess: Off-season-Liga-Wechsel

1. Im Dezember bekommt jedes Team und jeder Einzelspieler einen Push mit Hinweis auf das Wechselfenster.
2. Ein Team-Mitglied (für Teams) oder der Spieler selbst (für Einzelspieler) öffnet das Team- oder Spielerprofil und wählt „Liga wechseln".
3. Aktuelle Liga und Ziel-Liga werden angezeigt; das Mitglied bestätigt den Wechselwunsch.
4. Bestätigung ist sofort als „beantragter Wechsel" wirksam, gilt aber erst ab Beginn der nächsten Saison.
5. System bestätigt den Wechsel und zeigt einen Hinweis, dass Punkte aus früheren Saisons nicht übertragen werden.
6. Bis zum Saisonbeginn kann der Wechsel ohne Begründung rückgängig gemacht werden, sofern das Wechselfenster noch offen ist.
7. Mit Beginn der neuen Saison wird das Team/der Spieler in der neuen Liga geführt; die Saison startet mit 0 Punkten.
8. Die Liga-Historie wird im Profil dokumentiert.

### 5.16 Prozess: Mid-season-Liga-Wechsel durch Liga-Administrator

1. Team-Mitglied oder Spieler kontaktiert den Liga-Administrator (außerhalb der App oder über In-App-Postfach) und bittet um einen mid-season-Wechsel.
2. Liga-Administrator öffnet sein Liga-Administrator-Dashboard.
3. Wählt das betroffene Team oder den Spieler aus der Liste.
4. Wählt „Mid-season-Wechsel auslösen".
5. Wählt die Ziel-Liga.
6. Erfasst eine Begründung (Pflichtfeld).
7. System zeigt eine Warnung mit den Konsequenzen:
   - Punkte in der aktuellen Liga-Saisontabelle bleiben eingefroren.
   - Team/Spieler startet in der neuen Liga mit 0 Punkten.
8. Liga-Administrator bestätigt.
9. Wechsel ist sofort wirksam.
10. Betroffene Team-Mitglieder bzw. Spieler werden per Push informiert.
11. Audit-Log dokumentiert den Wechsel.

### 5.17 Prozess: Saison-Abschluss (Plattform-Administrator)

1. Am Saison-Enddatum prüft der Administrator alle laufenden Turniere.
2. Sobald alle Turniere abgeschlossen sind, wird die Saison gesperrt.
3. Liga-Saisontabellen werden eingefroren und archiviert.
4. System bereitet die neue Saison vor und informiert alle Nutzer über den Beginn des Wechselfensters.
5. Im April endet das Wechselfenster automatisch; bis dahin angemeldete Wechsel werden mit Saisonstart wirksam.

---

## 6. Geschäftsregeln

| ID | Regel |
|---|---|
| **BR-1** | Ein Match ist erst dann abgeschlossen, wenn beide Seiten übereinstimmend einen Score eingetragen haben oder der Veranstalter manuell entschieden hat. |
| **BR-2** | Die Buchholz-Wertung wird ausschließlich auf Basis bestätigter Match-Ergebnisse berechnet. |
| **BR-3** | Zwei Teilnehmer dürfen in der Vorrunde nicht zweimal aufeinandertreffen, außer der Veranstalter hebt diese Sperre auf. |
| **BR-4** | Ein Teilnehmer kann pro Turnier nur einmal einen BYE bekommen, solange Alternativen verfügbar sind. |
| **BR-5** | Ein registrierter Spieler kann nicht gleichzeitig im Roster zweier Teams desselben Turniers sein, auch wenn er Mitglied beider Team-Pools ist. |
| **BR-6** | Gast-Spieler zählen nicht für das globale Ranking. |
| **BR-7** | Nach dem Veröffentlichen eines Turniers sind Format, Punktesystem und Tiebreaker eingefroren. |
| **BR-8** | Veranstalter dürfen nur ihre eigenen Turniere ändern. |
| **BR-9** | Score-Eingaben sind nur durch registrierte Mitglieder des betreffenden Team-Pools zulässig. |
| **BR-10** | Manuelle Score-Änderungen werden im Audit-Log protokolliert. |
| **BR-11** | Eine Anmeldung kann bis zum konfigurierten Cutoff zurückgezogen werden. |
| **BR-12** | Ein abgesagtes oder abgebrochenes Turnier kann nicht wieder aktiviert werden. |
| **BR-13** | Saison-Punkte werden erst dann gutgeschrieben, wenn das Turnier den Status „Abgeschlossen" erreicht. |
| **BR-14** | Bei Ausfall eines Teams während des Turniers werden alle nachfolgenden Matches des Teams als Forfeit gewertet. |
| **BR-15** | In einem Shared Tournament zählt die Turnier-Platzierung allein nach Leistung; Liga-Punkte werden pro Liga getrennt vergeben. |
| **BR-16** | Trainingsstatistiken sind nicht öffentlich und nur für bestätigte Freunde einsehbar. |
| **BR-17** | Eine Veranstalter-Bewertung kann nur von Spielern abgegeben werden, deren Anmeldung am Turnier bestätigt war. |
| **BR-18** | Ein Veranstalter kann nur dann „im Namen eines Vereins" auftreten, wenn er Vereinsadministrator dieses Vereins ist. |
| **BR-19** | Liga-Punkte sind liga-spezifisch und saison-spezifisch. Sie werden bei einem Liga-Wechsel oder Saisonwechsel nicht übertragen, auch nicht bei Verbleib in derselben Liga. |
| **BR-20** | Off-season-Liga-Wechsel sind nur im Wechselfenster (Dezember bis Anfang April) möglich und werden erst zur nächsten Saison wirksam. |
| **BR-21** | Mid-season-Liga-Wechsel sind ausschließlich durch einen Liga-Administrator durchführbar und sofort wirksam. |
| **BR-22** | Bei einem mid-season-Wechsel bleiben die bereits gesammelten Saison-Punkte in der alten Liga-Saisontabelle eingefroren; in der neuen Liga startet das Team/der Spieler mit 0 Punkten. |
| **BR-23** | Im Modus „Eigene Punkte" zählt ein Turnier standardmäßig nicht für das globale Ranking, es sei denn der Plattform-Administrator hat eine explizite Freigabe erteilt. |
| **BR-24** | Bei nachträglicher Freigabe von Custom-Punkten werden die Punkte rückwirkend in die laufende Saison eingebucht. |
| **BR-25** | Turnier-Faktoren über dem Default („Standard") müssen vom Plattform-Administrator vor Turnier-Veröffentlichung freigegeben werden. |
| **BR-26** | Eine Liga-Trennung zwischen A und B in der Saisonwertung eines Turniers kommt nur zustande, wenn die konfigurierte Mindestanzahl pro Liga erreicht ist (Default 8 Teams). |
| **BR-27** | Alle registrierten Mitglieder eines Team-Pools haben identische Captain-Rechte. Der Gründer hat keine Sonderstellung. |
| **BR-28** | Ein Team kann nur aufgelöst werden, wenn alle registrierten Mitglieder zustimmen oder das letzte registrierte Mitglied es verlässt. |
| **BR-29** | Das Roster eines Teams für ein Turnier kann von jedem Team-Mitglied bis zum Turnierende angepasst werden. |
| **BR-30** | Das Einzelranking ist eine einzige Liste ohne Liga-Unterteilung und ohne Masters-Bonus. |

---

## 7. Offene Punkte

1. **Schutz gegen Missbrauch der gleichberechtigten Captain-Rechte:** Aktuell kann jedes Team-Mitglied jeden anderen aus dem Pool entfernen oder Team-Stammdaten ändern. Soll es Schutzmechanismen geben (Cooldown, Mehrheits-Bestätigung für kritische Aktionen, Benachrichtigung an alle Mitglieder bei kritischen Aktionen)?
2. **Reservespieler im Roster:** Soll das Roster zwischen „aktiv für aktuelles Match" und „Reserve" unterscheiden, oder reicht es, dass das Roster aus dem Pool gewählt wird und mid-Turnier anpassbar bleibt?
3. **Auto-Auf-/Abstiegsregeln zwischen Ligen am Saisonende:** Aktuell ist nur der Wechsel über das Wechselfenster oder durch Liga-Administrator geregelt. Falls es zusätzliche automatische Regeln basierend auf der Saisonperformance geben soll (z. B. „Top-3 aus Liga B steigen automatisch in Liga A auf"), muss das noch spezifiziert werden.
4. **Anti-Cheat und Sanktionen:** Beschwerdefunktion, Account-Sperre, Punkteabzug noch nicht detailliert.
5. **Achievements und Badges:** Geplant für spätere Version.
6. **Anmeldegebühren und Bezahlung:** Aus Scope ausgeklammert.
7. **Foto- und Medien-Upload pro Match:** Nice-to-have.
8. **Live-Streaming-Integration.**
9. **Öffentliche Schnittstelle für Drittsysteme.**
10. **Mehrsprachige Turnier-Beschreibungen.**
11. **Vereinsbeiträge:** Inhalte und Nachrichten von Vereinen.
12. **Verhalten bei nicht-auflösbaren Paarungs-Konflikten:** Fallback noch zu beschreiben.
13. **Interaktive Marker auf Lagepläne.**

---

*Ende der Anforderungsspezifikation v0.4.*
