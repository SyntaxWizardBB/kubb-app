# PO-Output — Profile Edit + Avatar (F2)

## User Stories

### US-1 (MUST) — Avatar im Profil
Als Spieler möchte ich auf meinem Profilbildschirm ein Avatar-Bild sehen, damit der Screen visuell verankert ist.

```
Given ein bestehendes Profil mit Namen "Lukas"
When  ich den ProfileScreen öffne
Then  sehe ich oben einen runden Avatar mit dem Buchstaben "L" auf einer Farbe aus dem Token-System
```

### US-2 (MUST) — Name editieren
Als Spieler möchte ich meinen Anzeigenamen ändern können, ohne das Profil löschen zu müssen.

```
Given ich bin auf dem ProfileScreen im Read-Mode
When  ich auf "Bearbeiten" tippe
Then  wird der Name zum TextField, und Save/Cancel-Buttons erscheinen

Given ich tippe einen neuen, gültigen Namen
When  ich Save tippe
Then  wird der Name persistiert und der Screen kehrt in den Read-Mode mit dem neuen Namen zurück

Given ich tippe Save mit leerem oder whitespace-only Namen
Then  ist der Save-Button deaktiviert
```

### US-3 (SHOULD) — Avatar-Farbe wählen
Als Spieler möchte ich aus einer kleinen Palette eine Avatar-Farbe wählen, um meinen Avatar zu personalisieren.

```
Given ich bin im Edit-Mode auf dem ProfileScreen
When  ich eine andere Farbe aus der Palette antippe
Then  wird die Avatar-Vorschau sofort in der neuen Farbe gerendert

Given ich tippe Save
Then  wird die Farbe als Hex-String in der avatarColor-Spalte persistiert
```

### US-4 (SHOULD) — Avatar-Vorschau im Onboarding
Als neuer User möchte ich beim Eintippen meines Namens schon den Avatar sehen, damit ich erlebe, was am Ende rauskommt.

```
Given ich bin auf dem OnboardingScreen
When  ich Buchstaben eintippe
Then  zeigt eine Vorschau-AvatarCircle den Anfangsbuchstaben in einer Default-Farbe
```

### US-5 (MUST, implizit) — Schema-Migration
Als Bestands-User möchte ich nach einem App-Update mein Profil weiter sehen, ohne dass die Migration meine Daten zerstört.

```
Given die Datenbank ist auf schemaVersion 1 (ohne avatarColor)
When  die App auf schemaVersion 2 hochmigriert
Then  ist die Spalte avatarColor in players hinzugefügt (NULL für Bestandsdaten)
And   alle bestehenden Profilrows sind unverändert lesbar
```

## MoSCoW

| Story | Priorität |
|---|---|
| US-1 Avatar anzeigen | MUST |
| US-2 Name editieren | MUST |
| US-3 Color-Picker | SHOULD |
| US-4 Onboarding-Vorschau | SHOULD |
| US-5 Migration | MUST |

## Offene Fragen

Keine — Owner hat alle Architektur-Defaults schon vorgegeben.
