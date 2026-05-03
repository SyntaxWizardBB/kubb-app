# PO-Output: F5 — CSV Export + SettingsScreen

## User Stories

### US-1 (MUST) — CSV-Export starten

**Als** Spieler
**möchte ich** alle meine Trainings-Sessions als CSV-Datei exportieren können
**damit** ich sie ausserhalb der App weiterverarbeiten kann (Tabellenkalk, Backup).

#### Akzeptanzkriterien

```
Given ich habe mind. eine abgeschlossene Sniper- oder Finisseur-Session
When  ich im SettingsScreen "CSV-Export" tippe
Then  öffnet sich der CsvExportModal mit Filter-Chips Zeitraum (Alle / 30 Tage / 90 Tage / Jahr)
And   Modus-Checkboxen (Sniper / Finisseur, beide initial an)
And   einer Vorschau-Tabelle mit Header und 2-3 Beispiel-Zeilen
And   einem aktiven "Herunterladen"-Button
```

```
Given der CsvExportModal ist offen mit Default-Filter
When  ich "Herunterladen" tippe
Then  wird ein CSV-String generiert mit allen Sessions im Filter
And   auf Android/iOS öffnet sich der System-Share-Dialog mit dem CSV-File
And   auf Linux/Web wird die Datei lokal gespeichert und ein SnackBar zeigt den Pfad
```

### US-2 (MUST) — Leerer Export-Filter wird verhindert

**Als** Spieler
**möchte ich** keinen leeren Export auslösen können
**damit** ich nicht aus Versehen eine 0-Byte-Datei generiere.

#### Akzeptanzkriterien

```
Given ich habe nur Sniper-Sessions, keine Finisseur-Sessions
When  ich im CsvExportModal beide Modi abwähle ODER "nur Finisseur" wähle
Then  ist der "Herunterladen"-Button disabled
And   ein Hinweis "Keine Sessions zum Exportieren" wird gezeigt
```

### US-3 (MUST) — SettingsScreen anstelle des Modals

**Als** Spieler
**möchte ich** alle Einstellungen in einem aufgeräumten Screen sehen
**damit** ich Account, Daten und App-Einstellungen klar getrennt finde.

#### Akzeptanzkriterien

```
Given ich bin auf dem HomeScreen
When  ich auf das Hamburger-Menü tippe
Then  navigiere ich zu /settings (kein Bottomsheet mehr)
And   sehe Sektionen Account / Daten / App
And   sehe Footer mit Version und Buildnummer
```

```
Given ich bin auf /settings
When  ich Theme, Heli-Tracking oder Vibration ändere
Then  wird die Änderung persistiert (gleiche Wirkung wie altes Modal)
```

### US-4 (MUST) — Profil löschen mit Bestätigung

**Als** Spieler
**möchte ich** mein Profil löschen können
**damit** ich die App komplett zurücksetzen kann.

#### Akzeptanzkriterien

```
Given ich bin auf /settings
When  ich "Profil löschen" tippe
Then  öffnet sich ein Bestätigungs-Dialog mit klarer Warnung
And   die Aktionen "Abbrechen" und "Löschen" sind sichtbar
```

```
Given der Bestätigungs-Dialog ist offen
When  ich "Löschen" bestätige
Then  werden alle Sessions des Profils gelöscht
And   das Profil selbst gelöscht
And   ich werde auf /onboarding weitergeleitet (via redirect)
```

### US-5 (MUST) — Sessions löschen mit Bestätigung

**Als** Spieler
**möchte ich** alle meine Sessions löschen können, ohne mein Profil zu verlieren
**damit** ich frisch starten kann ohne Onboarding nochmal zu durchlaufen.

#### Akzeptanzkriterien

```
Given ich bin auf /settings
When  ich "Sessions zurücksetzen" tippe
And   im Dialog "Löschen" bestätige
Then  werden alle Sessions des aktuellen Profils gelöscht
And   FK-Cascade entfernt zugehörige Events
And   das Profil bleibt erhalten
And   ich bleibe auf /settings
```

### US-6 (SHOULD) — Account-Sektion mit DeviceId

**Als** Spieler
**möchte ich** im Settings meine DeviceId sehen
**damit** ich bei Support-Anfragen nicht raten muss.

#### Akzeptanzkriterien

```
Given ich bin auf /settings
Then  sehe ich in der Account-Sektion meinen Profilnamen (Tap → /profile)
And   meine DeviceId in Mono-Schrift (read-only)
```

### US-7 (SHOULD) — Sprache und Privacy in App-Sektion

**Als** Spieler
**möchte ich** Sprache und einen kurzen Privacy-Hinweis sehen
**damit** ich weiss, was die App tut.

#### Akzeptanzkriterien

```
Given ich bin auf /settings
Then  sehe ich in der App-Sektion "Sprache: Deutsch" (read-only)
And   einen kurzen statischen Privacy-Hinweis (Daten bleiben lokal)
```

## MoSCoW

| Story | Priority |
|---|---|
| US-1 CSV-Export starten | MUST |
| US-2 Leerer Export verhindert | MUST |
| US-3 SettingsScreen statt Modal | MUST |
| US-4 Profil löschen mit Bestätigung | MUST |
| US-5 Sessions löschen mit Bestätigung | MUST |
| US-6 Account-Sektion mit DeviceId | SHOULD |
| US-7 Sprache + Privacy in App-Sektion | SHOULD |

## Offene Fragen

Keine — alle Architektur-Entscheidungen vom Owner explizit vorgegeben (Hamburger → Screen, Modal abschaffen, share_plus, Confirmation-Dialoge Pflicht).
