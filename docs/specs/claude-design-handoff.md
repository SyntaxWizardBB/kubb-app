# Kubb-App · Claude Design Handoff (v0.1)

> **Adressat:** Claude Design
>
> **Zweck:** Dieses Dokument fasst alle UI-Anforderungen der Kubb-App aus den vorhandenen Spezifikationen so zusammen, dass daraus Wireframes, Screen-Designs und ein visuelles Konzept abgeleitet werden können. Es ist ein **Brief**, keine vollständige Design-Spec – es zeigt **was** gebaut werden muss und **welche Anforderungen** dabei einzuhalten sind.
>
> **Bezugsdokumente:**
> - `tournament-mode-spec.md` v0.4 (Anforderungs-Spec Turniermodus)
> - `score-input-conflict-spec.md` v0.2 (Detail-Spec Score-Eingabe)
>
> **Stand:** 2026-05-24

---

## Inhaltsverzeichnis

1. [Produkt-Übersicht](#1-produkt-übersicht)
2. [Zielgruppe und Personas](#2-zielgruppe-und-personas)
3. [Designziele und Prinzipien](#3-designziele-und-prinzipien)
4. [Plattform und technische Rahmenbedingungen](#4-plattform-und-technische-rahmenbedingungen)
5. [Informations-Architektur](#5-informations-architektur)
6. [Screen-Inventar](#6-screen-inventar)
7. [Detail-Briefs für Schlüssel-Screens](#7-detail-briefs-für-schlüssel-screens)
8. [Wiederkehrende Komponenten](#8-wiederkehrende-komponenten)
9. [Interaktions-Patterns](#9-interaktions-patterns)
10. [Accessibility-Anforderungen](#10-accessibility-anforderungen)
11. [Branding und visuelle Sprache](#11-branding-und-visuelle-sprache)
12. [Offene Design-Fragen](#12-offene-design-fragen)

---

## 1. Produkt-Übersicht

Die Kubb-App ist eine Plattform für das Schweizer Wikingerschach (Kubb). Sie ergänzt einen bereits bestehenden Trainingsmodus um einen vollständigen Turniermodus. Der Turniermodus richtet sich an die Schweizer Kubb-Szene und soll mittelfristig zur zentralen Plattform für Turnierausschreibung, -anmeldung, -durchführung und Saisonwertung werden.

Die App ersetzt einen bestehenden WordPress-basierten Tournament Manager (kubb.live), den die meisten Schweizer Turniere derzeit nutzen. Sie übernimmt dessen Funktionalität und differenziert sich durch:
- Mobile-First-Bedienung am Pitch (statt Desktop-Schreiber in der Turnierzentrale).
- Beidseitige Score-Eingabe durch die Teams selbst, mit automatischer Konfliktauflösung.
- Live-Updates für Zuschauer ohne Reload.
- Integriertes Liga-System, Vereinskonzept und Spielerprofile.
- Trainingsmodus, der mit Turnierhistorie verknüpft ist.

---

## 2. Zielgruppe und Personas

### Persona 1: Der Spieler am Pitch („Marco, 32, Liga B")

Marco kommt zum Turnier, steht am Pitch in der Sonne, hat schmutzige Finger vom Kubb-Werfen und will:
- Sehen, wo sein nächstes Match stattfindet.
- Den Score nach dem Match in unter 30 Sekunden eintragen.
- Sehen, ob er noch in der Wertung liegt.
- Bei Konflikten schnell Klarheit bekommen.

Marco nutzt sein Smartphone, hat manchmal schlechten Netzempfang, ist nicht technikaffin.

### Persona 2: Der Veranstalter („Sandra, 45, Vereinspräsidentin")

Sandra organisiert das Saisonturnier ihres Vereins. Sie will:
- Das Turnier in unter 5 Minuten anlegen.
- Anmeldungen verwalten.
- Am Turniertag von einem Tablet aus alles steuern: Runden starten, Konflikte lösen, Pitches umorganisieren.
- Live sehen, wo es klemmt.
- Am Ende ohne Aufwand die Saisonwertung berechnet bekommen.

Sandra nutzt ein Tablet auf dem Veranstalter-Tisch, oft mit einem Co-Veranstalter daneben.

### Persona 3: Der Zuschauer / Familienangehörige („Lena, 38, Marcos Frau")

Lena schaut zu, will wissen, wann ihr Mann wieder am Pitch ist, wie es um seine Platzierung steht, und wo der nächste Pitch ist.

Lena hat kein Konto und navigiert die öffentliche Sicht ohne Anmeldung.

### Persona 4: Der Liga-Administrator („Thomas, 52, langjähriger Funktionär")

Thomas ist vom Plattform-Administrator als Liga-Admin der Liga A eingesetzt. Seine einzige Aufgabe: mid-season-Liga-Wechsel autorisieren. Er nutzt die App selten, aber wenn, dann gezielt.

### Persona 5: Der Plattform-Administrator („Lukas, 29, App-Verantwortlicher")

Lukas verwaltet die App technisch und inhaltlich. Konfiguriert Saisons, gibt Turnier-Faktoren frei, legt Vereine und Liga-Admins an. Nutzt Desktop, gern auch CLI.

---

## 3. Designziele und Prinzipien

| Prinzip | Ausprägung |
|---|---|
| **Mobile-First, Pitch-tauglich** | Primäres Gerät ist das Smartphone, häufig draußen, in der Sonne, mit nassen oder schmutzigen Fingern bedient. Touch-Ziele groß, Kontrast hoch, Tap-Pfade kurz. |
| **Schnelligkeit über Schönheit** | Score-Eingabe in 30 Sekunden ist wichtiger als perfekte Animation. Reduktion ist Programm. |
| **Klarheit bei Konflikten** | Wenn es schwierig wird (Konflikt, Eskalation, Override), muss die UI besonders deutlich machen, was passiert und was als nächstes zu tun ist. |
| **Live-Charakter** | Was sich ändert, muss sich sichtbar ändern. Runden-Clock, Rangliste, Match-Status – alles aktualisiert sich ohne Reload. |
| **Vertraute Sprache** | Kubb-Terminologie aus der Schweizer Szene (Schochmodus, Basekubbs, König, EKC) ohne Verfremdung übernehmen. |
| **Privatsphäre als Default** | Trainingsdaten sind privat, Turnierdaten sind öffentlich. Diese Trennung muss in der UI sichtbar sein. |
| **Drei-Tier-Architektur in der Ansprache** | Spieler, Veranstalter, Administrator brauchen jeweils andere Tiefe. Die UI soll dasselbe Konzept in drei Detailstufen zeigen können. |

---

## 4. Plattform und technische Rahmenbedingungen

- **Primäre Plattformen:** Smartphone (iOS, Android), Tablet (Veranstalter-Setup), Browser (Desktop für Plattform-Admin und Zuschauer).
- **Bildschirmgrößen:** Smartphone ab 360 px Breite, Tablet bis 1024 px, Desktop responsive.
- **Außenlicht-Tauglichkeit:** Hoher Kontrast, keine grellen Hover-Effekte, keine grauen Texte auf grauem Hintergrund.
- **Offline-Anzeige:** Persistenter Banner bei Verbindungsverlust.
- **Sprache:** Deutsch (Schweizer Hochdeutsch) als Default, Französisch und Englisch als weitere Sprachen.
- **Echtzeit:** Wichtige Sichten (Rangliste, Match-Status, Runden-Clock) aktualisieren sich automatisch.

---

## 5. Informations-Architektur

### 5.1 Hauptbereiche der App

```
┌──────────────────────────────────────────────────────────────┐
│                       Kubb-App                                │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐ │
│  │   ÖFFENTLICH   │  │    SPIELER     │  │  VERANSTALTER  │ │
│  │    (alle)      │  │  (eingeloggt)  │  │   (Rolle X)    │ │
│  └────────────────┘  └────────────────┘  └────────────────┘ │
│                                                              │
│  • Turnier-Liste     • Eigenes Profil   • Eigene Turniere   │
│  • Liga-Tabellen     • Eigene Teams     • Live-Dashboard    │
│  • Spielerprofile    • Trainingsmodus   • Anmeldungs-Mgmt   │
│  • Vereinsprofile    • Match-Historie   • Konflikt-Auflösg. │
│  • Live-Sicht        • Liga-Wechsel     • Bewertungen       │
│                                                              │
│  ┌────────────────┐  ┌────────────────────────────────────┐  │
│  │  LIGA-ADMIN    │  │       PLATTFORM-ADMIN              │  │
│  │ (Sonderrolle)  │  │       (Master-Rolle)               │  │
│  └────────────────┘  └────────────────────────────────────┘  │
│                                                              │
│  • Liga-Mgmt         • Saisons, Faktoren, Vereine           │
│  • Mid-season-       • Liga-Admins ernennen                 │
│    Wechsel           • Turnier-Freigaben                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 5.2 Haupt-Navigation (für eingeloggte Spieler)

| Tab | Inhalt |
|---|---|
| **Heim** | Persönlicher Feed: nächstes Match, anstehende Turniere, Liga-Stand, ungelesene Nachrichten. |
| **Turniere** | Liste laufender und kommender Turniere, Filter (Liga, Region, Verein). |
| **Liga** | Saisontabellen pro Liga, eigene Position. |
| **Training** | Bestehender Trainingsmodus, eigene Statistiken. |
| **Profil** | Eigenes Profil, eigene Teams, Einstellungen. |

### 5.3 Globale Elemente

- **Suchleiste** (Spieler, Team, Verein, Turnier) – erreichbar von überall.
- **Benachrichtigungs-Glocke** mit In-App-Postfach.
- **Status-Banner offline** (oben, persistent bei Verbindungsverlust).
- **Profil-Icon** mit Wechsel zwischen Rollen (falls jemand z. B. gleichzeitig Veranstalter ist).

---

## 6. Screen-Inventar

Die folgenden Screens sind aus den Anforderungen ableitbar. Sie sind grob nach Bereich gruppiert. Die Liste ist nicht abschließend, deckt aber alle in den Specs benannten Funktionen ab.

### 6.1 Onboarding und Login (5 Screens)

1. Splash / App-Start
2. Login (Google-OAuth-Button)
3. Erstes Profil anlegen (Anzeigename, Heimatverein, Land, Avatar)
4. Datenschutz-Einstellungen (Profil-Sichtbarkeit, Push-Kategorien)
5. Erste Schritte / kurzer Onboarding-Walkthrough

### 6.2 Eigenes Profil und Einstellungen (8 Screens)

6. Eigenes Profil – Übersicht
7. Profil bearbeiten
8. Eigene Teams (Liste mit Pool-Mitgliedern)
9. Eigene Turnierhistorie
10. Eigene Match-Historie
11. Head-to-Head-Statistiken
12. Liga-Historie (welche Liga in welcher Saison)
13. Einstellungen (Push-Kategorien, Sichtbarkeit, Sprache, Konto-Aktionen, Datenexport)

### 6.3 Freundschaften und Social (4 Screens)

14. Freundesliste
15. Freundschaftsanfragen
16. Spielerprofil eines anderen Nutzers (Public-Sicht)
17. Block- / Melde-Funktion

### 6.4 Team-Management (8 Screens)

18. Team-Übersicht (eines bestimmten eigenen Teams)
19. Team gründen (Stammdaten, initiale Liga)
20. Team-Stammdaten bearbeiten (Name, Logo, Heimatverein)
21. Pool-Mitglieder verwalten (Liste, einladen, entfernen)
22. Mitglied einladen (Suche, Auswahl)
23. Gast-Spieler hinzufügen
24. Team-Profil öffentlich (Public-Sicht)
25. Team auflösen (mit Mehrheits- oder Letzter-Member-Bestätigung)

### 6.5 Turnier-Discovery und -Detail (öffentlich) (10 Screens)

26. Turnier-Liste (Filter, Karte, Liste)
27. Turnier-Detailseite öffentlich
28. Turnier-Anmeldeformular für Einzel
29. Turnier-Anmeldeformular für Team mit Roster-Auswahl
30. Live-Rangliste (öffentlich)
31. Aktuelle Runde (öffentlich, mit Runden-Clock)
32. Alle Runden (Archiv)
33. Bracket-Visualisierung
34. Lageplan
35. Vollbild-Streaming-Sicht (KANN)

### 6.6 Spielerprofil öffentlich, Vereinsprofil (3 Screens)

36. Spielerprofil öffentlich (Stammdaten, Statistiken, Liga-Stand)
37. Vereinsprofil öffentlich
38. Liste der Vereine

### 6.7 Spieler – während eines Turniers (8 Screens)

39. „Heim"-Tab mit nächstem Match (prominent)
40. Match-Detail-Seite mit Score-Eingabe (kritischer Screen, siehe 7.1)
41. Konflikt-Anzeige (drei Versuche, Differenzen)
42. Manuelle-Eskalations-Dialog
43. Live-Rangliste meine Sicht
44. „Meine Matches"-Liste innerhalb eines Turniers
45. Roster mid-Turnier anpassen
46. Match-Detail nach Abschluss (Read-only)

### 6.8 Veranstalter – Turnier erstellen und verwalten (12 Screens)

47. „Meine Turniere"-Übersicht
48. Turnier-Erstellungs-Assistent Schritt 1 (Stammdaten)
49. Turnier-Erstellungs-Assistent Schritt 2 (Format, Match-Format)
50. Turnier-Erstellungs-Assistent Schritt 3 (Punkte-Konfiguration: Globale Formel vs. Eigene Punkte)
51. Turnier-Erstellungs-Assistent Schritt 4 (Tiebreaker, Pitches, BYE, Forfeit)
52. Turnier-Erstellungs-Assistent Schritt 5 (Liga-Zuordnung, Anmeldefenster, Lageplan)
53. Turnier-Entwurf (Vorschau)
54. Turnier-Veröffentlichung (mit Antrag auf Faktor-Freigabe falls nötig)
55. Anmeldungs-Management (Liste, bestätigen, ablehnen, Warteliste)
56. Check-In am Turniertag
57. Seeding-Tool
58. Co-Veranstalter einladen

### 6.9 Veranstalter – Live-Dashboard (10 Screens)

59. Live-Dashboard (alle Pitches im Überblick)
60. Pitch-Detail mit Match-Status
61. Runden-Management (Runde starten, Clock starten, pausieren)
62. Match-Konflikt-Auflösung („Strittig-Ansicht")
63. Score-Override
64. Match verschieben (Drag-and-Drop)
65. Forfeit erklären
66. Match abbrechen
67. Turnier-Abbruch
68. Nächste Runde generieren

### 6.10 Veranstalter – Turnierabschluss (3 Screens)

69. Final-Rangliste-Prüfung
70. Turnier abschließen
71. Aggregierte Veranstalter-Bewertung (eigenes Profil)

### 6.11 Bewertungen (2 Screens)

72. Veranstalter bewerten (nach Turnier)
73. Bewertung melden

### 6.12 Liga und Saison (5 Screens)

74. Liga-Saisontabelle pro Liga (mit Saisonfilter)
75. Einzelranking-Saisontabelle
76. Liga wechseln (off-season)
77. Liga-Wechsel-Antrag-Bestätigung
78. Liga-Wechsel-Historie (im eigenen Profil)

### 6.13 Liga-Administrator (3 Screens)

79. Liga-Admin-Dashboard (Liste Teams und Spieler der eigenen Liga)
80. Mid-season-Wechsel auslösen
81. Mid-season-Wechsel-Bestätigung mit Warnung

### 6.14 Plattform-Administrator (10 Screens)

82. Admin-Dashboard
83. Saisons verwalten
84. Punkte-Formel und Stufungs-Bonus konfigurieren
85. Turnier-Faktoren konfigurieren
86. Liga-Faktoren konfigurieren
87. Liga-Admins ernennen
88. Vereine verwalten und Vereinsadmins ernennen
89. Turnier-Faktor-Antrag prüfen
90. Custom-Punkte-Freigabe-Antrag prüfen
91. Missbräuchliche Inhalte moderieren

### 6.15 Vereinsadministrator (3 Screens)

92. Vereinsadmin-Dashboard
93. Vereinsmitglieder verwalten und Rollen vergeben
94. Verein-Turnier ausrichten (führt in 6.8 ein)

### 6.16 Querschnittsbereiche (5 Screens)

95. In-App-Postfach
96. Suchergebnisse
97. Offline-Status / Synchronisations-Status (Outbox-Anzeige)
98. Fehler- und Leerzustände
99. Hilfe / Glossar (Kubb-Begriffe erklärt)

---

**Gesamt: rund 99 Screens.** Viele davon teilen Komponenten (siehe Sektion 8), die Anzahl unterschiedlicher visueller Templates ist deutlich geringer (geschätzt 20–25 wiederverwendbare Layouts).

---

## 7. Detail-Briefs für Schlüssel-Screens

Folgende Screens sind kritisch für den Produkterfolg und brauchen besonders gut durchdachtes Design.

### 7.1 Match-Detail-Seite mit Score-Eingabe (Screen 40)

**Wichtigste Funktion der gesamten App.** Wenn diese in 30 Sekunden bedienbar ist, fühlt sich die App schnell an.

Anforderungen:
- Mobile-First, eine Hand bedienbar.
- Eingabe pro Satz: Basekubb-Zahl pro Team (Stepper 0 bis 5 oder Tastatur), König-Schalter („Mein Team", „Gegner", „Keiner / Zeitablauf").
- Live-Vorschau des Match-Scores während der Eingabe.
- Klare Trennung zwischen „Mein Team" und „Gegner".
- Status-Banner mit aktuellem Match-Zustand.
- Bestätigungs-Dialog vor Absenden.
- Hinweis falls anderes Team-Mitglied bereits eingetragen hat.

Siehe `score-input-conflict-spec.md` Sektion 14 für vollständige Anforderungen.

### 7.2 Konflikt-Anzeige (Screen 41)

**Differenziert die App vom WordPress-Plugin.**

Anforderungen:
- Vergleich der eigenen und gegnerischen Eingabe nebeneinander.
- Abweichende Felder farblich (rot) hervorgehoben.
- Versuchs-Zähler („Versuch 2 von 3").
- Buttons „Erneut eintragen" und „Veranstalter hinzuziehen".
- Bei Versuch 3: explizite Warnung, dass dies der letzte Versuch ist.

### 7.3 Veranstalter Live-Dashboard (Screen 59)

**Kommandozentrale am Turniertag.**

Anforderungen:
- Tablet-optimiert (1024 px), aber auch auf Smartphone bedienbar.
- Alle Pitches auf einen Blick, farbcodiert nach Status (läuft, wartet auf Eingabe, strittig, abgeschlossen).
- Runden-Clock zentral, mit Pause/Verlängerung/Beenden.
- Offene Konflikte und Eingaben prominent (z. B. roter Badge).
- Drag-and-Drop für Match-Verschiebungen.
- Schnellzugriff auf „Runde abschließen", „Nächste Runde generieren".
- Push-Benachrichtigungen über Konflikte mit direktem Sprung zum Match.

### 7.4 Strittig-Ansicht für Veranstalter (Screen 62)

**Der schwierigste Moment für den Veranstalter.**

Anforderungen:
- Tabelle aller Versuche, beide Seiten nebeneinander, mit submittenden Mitgliedern.
- Abweichungen visuell hervorgehoben.
- Eingabe-Maske für finalen Score (identisch zur Team-Eingabe).
- Live-Vorschau: Wie wirkt sich der Score auf die Rangliste aus?
- Optionale Begründung als Freitext.
- Klare Aktion „Entscheidung speichern".

### 7.5 Turnier-Erstellungs-Assistent (Screens 48–54)

**Tor zur Plattform für Veranstalter.**

Anforderungen:
- Schritt-für-Schritt, mit Fortschrittsanzeige.
- Jeder Schritt einzeln speicherbar (Entwurf).
- Vernünftige Defaults: Standard-Punkte-System (EKC), Standard-Faktor (1.0), 8 Pitches, Schochmodus.
- Kontextuelle Erklärungen für komplexe Felder (z. B. „Was sind Tiebreaker?").
- Vorschau am Ende.
- Bei Antrag auf höheren Faktor: klare Hinweise, dass das vom Plattform-Admin geprüft werden muss.

### 7.6 Team-Pool-Verwaltung (Screen 21)

**Neuartig im Vergleich zu klassischen Turnier-Tools.**

Anforderungen:
- Klare Liste aller Pool-Mitglieder (registriert + Gast).
- Visuelle Trennung registriert / Gast (Symbol oder Label).
- Aktionen pro Mitglied: entfernen (nur registriert), bearbeiten (nur Gast).
- Einladen-Button prominent.
- Hinweis: „Alle registrierten Mitglieder haben gleiche Rechte."
- Gründer-Information dezent angezeigt (z. B. „Gegründet von X am Y").

### 7.7 Roster-Auswahl bei Turnier-Anmeldung (Screen 29)

**Neuartig.** Bei Anmeldung zu einem 3vs3-Turnier muss aus dem Pool genau 3 Mitglieder ausgewählt werden.

Anforderungen:
- Liste aller Pool-Mitglieder mit Checkbox.
- Counter: „2 von 3 ausgewählt".
- Disable, wenn die korrekte Anzahl nicht erreicht ist.
- Bei Mehrfach-Team-Mitgliedschaft des einladenden Nutzers: zusätzlicher Schritt davor (welches Team anmelden).
- Validierung: mindestens ein registriertes Mitglied im Roster.

### 7.8 Live-Rangliste (Screen 30, 43)

**Wichtig für Spieler und Zuschauer.**

Anforderungen:
- Sortiert nach Total Points, dann Tiebreaker.
- Eigene Position hervorgehoben (für eingeloggte Spieler).
- Spalten: Rang, Name (Team oder Spieler), Total Points, Tiebreaker-Werte.
- Bei Shared Tournament: Filter „alle Ligen", „nur Liga A", „nur Liga B".
- Echtzeit-Update.
- Sticky-Header beim Scrollen.

### 7.9 Liga-Saisontabelle (Screen 74)

Anforderungen:
- Eine Liga, eine Saison als Standard-Filter.
- Spalten: Rang, Team (oder Spieler im Einzelranking), aktuelle Saisonpunkte, Anzahl gewerteter Turniere, Trend.
- Hinweis auf mid-season-Wechsel falls vorhanden (Tooltip oder Symbol).
- Wechsel-Filter zwischen Ligen.

### 7.10 Mid-season-Wechsel-Dialog (Screen 81)

**Hohes Risiko, klare UI nötig.**

Anforderungen:
- Auswahl des betroffenen Teams oder Spielers.
- Auswahl der Ziel-Liga.
- Pflichtfeld Begründung.
- **Klare Warnung mit den Konsequenzen** in Hervorhebung:
  - „Punkte in der aktuellen Liga bleiben eingefroren und werden weiterhin in der Liga-X-Saisontabelle gezeigt."
  - „Team/Spieler startet in der neuen Liga mit 0 Punkten ab dem heutigen Tag."
- Zwei-Stufen-Bestätigung („Bist du sicher?").

---

## 8. Wiederkehrende Komponenten

Folgende Komponenten erscheinen in mehreren Screens. Sie sollten als Bausteine der Design-Bibliothek behandelt werden.

| Komponente | Verwendung |
|---|---|
| **Team-Avatar mit Liga-Badge** | Überall, wo ein Team genannt wird. |
| **Spieler-Avatar mit Rang-Badge** | Überall, wo ein Spieler genannt wird. |
| **Match-Karte** | Übersicht eines Matches: Teams, Score, Status, Pitch, Zeit. |
| **Runden-Clock-Anzeige** | Countdown mit Pause-Indikator, prominent platzierbar. |
| **Status-Banner** | Farbcodiert (grün abgeschlossen, gelb wartend, rot strittig). |
| **Stufungs-Stepper** | Für Basekubbs-Eingabe (0 bis 5). |
| **Liga-Filter-Dropdown** | Für Ranglisten und Tabellen. |
| **Bestätigungs-Dialog** | Mit zwei klaren Aktionen (Primär / Sekundär), bei kritischen Aktionen Zwei-Stufen-Bestätigung. |
| **Rolle-Switcher** | Im Profil-Icon, falls Nutzer mehrere Rollen hat (z. B. Spieler + Veranstalter). |
| **Push-Glocke mit Counter** | Globaler Header. |
| **Offline-Banner** | Persistent oben, bei Verbindungsverlust. |
| **Schritt-für-Schritt-Anzeige** | Im Turnier-Erstellungs-Assistenten und ähnlichen mehrstufigen Flows. |
| **Tab-Navigation** | Hauptnavigation (Heim / Turniere / Liga / Training / Profil). |
| **Listen-Card mit Aktion** | Z. B. Team-Mitglied mit „Entfernen"-Button. |
| **Vergleichs-Tabelle (zwei Spalten)** | Für Konfliktauflösung der Score-Eingabe. |
| **Diff-Highlight** | Rot oder farbiger Rahmen für abweichende Felder. |
| **Vorschau-Karte** | Live-Vorschau von Punkten, Score, Ranglisten-Auswirkung. |

---

## 9. Interaktions-Patterns

### 9.1 Score-Eingabe

- Pro Satz: ein Stepper für eigene Basekubbs, einer für gegnerische, ein Schalter für König.
- Vorschau aktualisiert sich live.
- Eingabe lokal gespeichert (Entwurf), überlebt App-Neustart.
- Absenden: Bestätigungs-Dialog, dann Server (oder Outbox).

### 9.2 Konflikt-Auflösung

- Drei Versuche, jeder Versuch öffnet die Eingabe-Maske mit den eigenen vorherigen Werten als Default.
- Vergleich nach jedem Versuch sichtbar.
- Manuelle Eskalation jederzeit per Button verfügbar.
- Nach Versuch 3 oder manueller Eskalation: Übergang zu „warten auf Veranstalter".

### 9.3 Runden-Clock

- Wird vom Veranstalter gestartet und gestoppt.
- Allen Teilnehmern und Zuschauern in Echtzeit sichtbar.
- Pausierbar.
- Beim Ablauf: konfiguriertes Verhalten (z. B. „letzte Wurfsequenz beenden, dann fertig").

### 9.4 Push-Benachrichtigungen

- Kategorisiert: Eingabe-Erinnerung, Konflikt, Match-Abschluss, Turnier-Status.
- Pro Kategorie an-/abschaltbar.
- Hochpriorisierte Pushs (Strittig, Override) ignorieren Stummschaltung.
- Wiederholende Erinnerungs-Pushs alle 5 Minuten, bis die Aktion erfolgt ist.

### 9.5 Drag-and-Drop für Pitch-Zuteilung

- Auf Veranstalter-Dashboard, idealerweise Tablet.
- Match-Karte per Long-Press greifen, auf anderen Pitch ziehen.
- Mit Feedback (Hervorhebung des Ziel-Pitches).
- Reversible (Undo-Option für 30 Sekunden).

### 9.6 Suche

- Eine globale Suchleiste, durchsucht Spieler, Teams, Vereine, Turniere.
- Live-Vorschläge während des Tippens.
- Filter zur Eingrenzung.

### 9.7 Offline-Verhalten

- Banner sichtbar bei Verbindungsverlust.
- Eingaben werden lokal gespeichert und beim Reconnect synchronisiert.
- Offline-Status separat einsehbar (Synchronisations-Status-Screen mit Outbox-Liste).

---

## 10. Accessibility-Anforderungen

- **Kontrast:** WCAG 2.1 AA, mindestens 4.5:1 für Texte. Sonnenlicht-tauglich heißt im Zweifel: höher als das Minimum.
- **Touch-Ziele:** Mindestens 44×44 px, am Pitch eher 60×60 px.
- **Schriftgröße:** Mindestens 16 px Body, skalierbar.
- **Screenreader:** Alle interaktiven Elemente mit Labels.
- **Tastatur-Navigation:** Auf Desktop voll bedienbar.
- **Farbcodierung nie alleine:** Status („strittig" rot) wird zusätzlich textlich oder mit Symbol kommuniziert.
- **Sprache:** Deutsch (Schweiz), Französisch, Englisch.
- **Reduce-Motion:** Wenn das System es signalisiert, Animationen abschalten.

---

## 11. Branding und visuelle Sprache

> **Status:** Noch offen. Folgende Aspekte sollten in der ersten Design-Iteration vom Designer vorgeschlagen werden, danach mit dem Auftraggeber abgestimmt.

- **Farbpalette:** Vorschlag erwünscht, mit Bezug zur Kubb-Welt (Holz, Wiese, Natur) oder modern-sportlich. Wichtig: hoher Kontrast für Außennutzung.
- **Typografie:** Eine Schrift für die ganze App, klar lesbar in Sonnenlicht. Sans-Serif bevorzugt.
- **Icon-Set:** Konsistent, möglichst aus einer Quelle (z. B. Phosphor, Lucide, eigene).
- **Logo:** Noch nicht erstellt.
- **Bildsprache:** Echte Kubb-Fotos für Inspiration, in der UI selbst eher zurückhaltend.
- **Animationen:** Minimal, funktional. Hauptsächlich für Status-Übergänge und Live-Updates.

---

## 12. Offene Design-Fragen

Folgende Punkte sind aus den Specs noch nicht abschließend entschieden und sollten im Design-Prozess geklärt werden.

1. **Branding gesamt:** Farbe, Typografie, Logo, Tonalität – noch offen.
2. **Tablet-Layout des Veranstalter-Dashboards:** Wie sieht das ideale Live-Dashboard auf einem 10"-Tablet im Querformat aus?
3. **Mobile vs. Tablet vs. Desktop:** Für welche Screens lohnt sich ein separates Tablet-Layout, welche bleiben mobile-zentriert mit Skalierung?
4. **Bracket-Visualisierung:** Wie zeigt man ein KO-Bracket auf Smartphone-Bildschirm? (Horizontal scrollbar? Vertikales Tree-Layout? Phasenweise Navigation?)
5. **Score-Eingabe-UX:** Stepper oder Tastatur oder beides? Welche Variante bei welcher Bildschirmgröße?
6. **Karten oder Liste für Turnier-Discovery:** Hauptdarstellung Karten oder Liste? Mit oder ohne Karte (Schweizkarte als Filter)?
7. **Drag-and-Drop auf Smartphone:** Wie löst man Pitch-Verschiebungen auf einem kleinen Bildschirm, falls der Veranstalter nur ein Smartphone hat?
8. **Echtzeit-Anzeige der Rangliste:** Wie zeigt man Veränderungen (Rangsprünge) visuell an, ohne aufdringlich zu wirken?
9. **Konflikt-Anzeige bei vielen Sätzen:** Wenn ein Match Best-of-5 hat und in mehreren Sätzen Abweichungen sind, wird die Vergleichs-Tabelle eng. Wie skaliert die Darstellung?
10. **Roster-Auswahl bei großen Pools:** Wenn ein Team-Pool 30 Mitglieder hat, wie scrollt und sucht man darin effizient?
11. **Liga-Wechsel-Warnung-Stärke:** Welche visuelle Sprache für „kritische Aktion mit irreversiblen Folgen"? Modal? Inline-Banner? Zweistufige Bestätigung mit Texteingabe?
12. **Live-Updates ohne Reload:** Welche Indikatoren („Pulse"-Animation, „neu seit Sekunde X"-Badge) ohne nervig zu werden?

---

*Ende des Claude Design Handoff v0.1.*
