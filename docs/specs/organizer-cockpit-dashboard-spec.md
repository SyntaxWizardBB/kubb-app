# Spec — Veranstalter-Cockpit / Turnier-Steuerung (Dashboard)

**Status:** Verbindliche Implementierungs-Spezifikation & Quality-Gate.
**Geltung:** Das **Cockpit** ist die einzige Veranstalter-Zentrale. Diese Spec legt
fest, was darin liegt, wie die Detail-Sicht vereinheitlicht wird und welche
Veranstalter-Funktionen dazukommen.
**Verwandt:** [vorrunde-ranking-spec.md](./vorrunde-ranking-spec.md),
[stage-seeding-spec.md](./stage-seeding-spec.md).

> **Wording:** „**Cockpit**" = Veranstalter-Zentrale (Turnier-Steuerung).
> „**Mitspieler-View**" = die normale Turnier-Sicht, die jeder Besucher/Spieler sieht.
> „**Match-Kachel**" = eine Match-Zeile in der Steuerung. **MUSS** = harte
> Anforderung, **OFFEN** = ungelöst.

---

## 1. Struktur des Cockpits (MUSS)

Das Cockpit hat **zwei Ebenen** — alles Veranstalter-bezogene lebt hier:

| Ebene | Route | Inhalt |
|---|---|---|
| **Cockpit-Übersicht** | `/tournament/dashboard` | Alle Turniere des Veranstalters als Karten (+ Veranstalterteams). **Übergreifendes** (z. B. Check-in über mehrere Turniere, Einstieg in den Check-in-Screen). |
| **Turnier-Steuerung** | `/tournament/:id/dashboard` | Ein Turnier steuern: Timer, Match-Kacheln, Eskalation, Lifecycle, Check-in dieses Turniers. Reinspringen aus der Übersicht. |

---

## 2. Detail-Sicht vereinheitlichen (MUSS)

**Heute (falsch):** `tournament_detail_screen.dart` ist zwar dieselbe Route für alle,
blendet aber für Veranstalter (`canManage`) **zusätzliche Blöcke inline** ein
(Check-in, Eskalations-Cockpit, Lifecycle-Aktionen, Teilnehmer-Moderation). Dadurch
sieht ein Veranstalter de facto einen anderen Bildschirm als ein Besucher.

**Soll:**
1. Der Detail-Screen zeigt **für alle denselben Mitspieler-View** (Stammdaten,
   Teilnehmer, Anmeldung/Status — ohne Veranstalter-Steuerung).
2. Ein Veranstalter (`canManage`) sieht dort **nur einen zusätzlichen Button
   „→ Dashboard"** (Absprung ins Cockpit / in die Turnier-Steuerung dieses Turniers).
3. **Alle** bisher inline eingeblendeten Veranstalter-Blöcke werden **entfernt** und
   ins Cockpit migriert (§3).

---

## 3. Migration ins Cockpit (MUSS)

Was heute im Detail-Screen hängt und in die Turnier-Steuerung (`/:id/dashboard`)
wandert:
- **Check-in** der bestätigten Teilnehmer (Anwesenheit) — zusätzlich der separate
  Cross-Turnier-Screen (§7).
- **Eskalations-Cockpit** (strittig / überfällig / nicht eingecheckt). *(Existiert im
  Dashboard bereits als Badges — Detail-Variante entfällt.)*
- **Lifecycle-Aktionen** (Turnier starten, bearbeiten-nach-Veröffentlichung,
  Setzliste committen, KO-Phase starten).
- **Teilnehmer-Moderation** (Check-in-Toggle pro Person).

Es darf **keine** Veranstalter-Steuerung mehr im Detail-Screen verbleiben.

---

## 4. Turnier-Steuerung — Match-Kacheln (MUSS)

Jede Match-Kachel in `/tournament/:id/dashboard` zeigt und kann:

- **Pitch-Nummer** (MUSS, neu) — auf **jeder** Kachel sichtbar angeschrieben
  (Quelle: `PitchPlan`/`pitch_assignment.dart`).
- Teilnehmer A vs. B + aktueller Score (oder „—").
- **Aktionen pro Kachel:**
  - **„Punkte eintragen"** (MUSS, neu) — Veranstalter trägt das **normale Resultat
    direkt** ein (§5).
  - **Forfeit** (existiert) — Wertung bei No-Show.
  - **Override** (existiert) — für strittige Matches.

---

## 5. Direkter Punkte-Eintrag (MUSS)

- Der Veranstalter kann für **jedes** Match die Punkte **direkt** setzen — **ohne**
  Spieler-Validierung, **ohne** Konsens-/Zwei-Seiten-Flow.
- Das Ergebnis wird **sofort hochgesynced** (autoritativ, gilt als final).
- **Editor:** derselbe Satz-Editor wie beim Override (Basekubbs + König pro Satz,
  Live-Vorschau), nur **ohne** „strittig"-Kontext und ohne Pflicht-Begründung.
- **Implementierung:** baut auf dem bestehenden direkten Schreibweg auf
  (`tournament_override_controller.submit`, organizer-autoritativ) — generalisiert auf
  beliebige (auch nicht-strittige) Matches.

---

## 6. Timer (MUSS)

In der Turnier-Steuerung (`/tournament/:id/dashboard`):
- **Pause / Weiter** (existiert).
- **Rundenzeit verlängern UND verkürzen** (MUSS, neu) — Zeit auf die laufende Runde
  drauflegen oder abziehen, per **+/- Schritten UND direkter Zahleneingabe**.
- **Statusanzeige (MUSS):** zeigt immer, **was gerade läuft**, mit der Zeit darunter:
  - z. B. **„Pause"** + Restzeit/Dauer darunter,
  - oder **„Runde 6"** + laufende Restzeit darunter.
- Bestehende Skip-vor/-zurück-Aktionen bleiben.

---

## 7. Cross-Turnier-Check-in (eigener Screen, MUSS)

- **Eigener Screen**, erreichbar aus der **Cockpit-Übersicht** (`/tournament/dashboard`).
- **Suchfeld:** sucht das richtige **Team / den Spieler** (über alle Turniere des
  Veranstalters).
- Ein Treffer zeigt, **für welches Turnier** sich Team/Spieler angemeldet hat.
- Von dort wird **eingecheckt** — auch turnierübergreifend an einem Ort (ein
  Helfer am Eingang checkt alle ein, egal welches Turnier).
- **Scope (MUSS):** der Screen umfasst **nur** Turniere, die (a) **aktuell in der
  Check-in-Phase** sind UND (b) **vom selben Veranstalter publiziert** wurden.

---

## 8. Berechtigungen (MUSS)

- Veranstalter-Sichten (Cockpit, Steuerung, „→ Dashboard"-Button, Cross-Check-in)
  nur für `canManage`/`canAdminister` (Creator oder Owner/Admin/Organizer des
  Turniers bzw. Veranstalterteams).
- Ohne Berechtigung: kein „→ Dashboard"-Button, normaler Mitspieler-View; die
  Steuerungs-Routen sind serverseitig gegatet (Fail-closed).

---

## 9. Akzeptanzkriterien / Quality-Gates (nachprüfbar)

**9.1 Einheitliche Detail-Sicht:** Besucher, Spieler und Veranstalter sehen am
Turnier-Detail **denselben** Mitspieler-View; der Veranstalter hat dort **nur**
zusätzlich den Button „→ Dashboard". Keine inline Veranstalter-Blöcke mehr.

**9.2 Migration vollständig:** Check-in, Eskalation, Lifecycle, Teilnehmer-Moderation
sind aus dem Detail-Screen verschwunden und im Cockpit erreichbar.

**9.3 Pitch sichtbar:** Jede Match-Kachel zeigt ihre Pitch-Nummer.

**9.4 Direkter Score:** Veranstalter trägt für ein nicht-strittiges Match Punkte ein
→ sofort final, kein Spieler-Konsens nötig, sofort gesynced.

**9.5 Timer:** Veranstalter kann pausieren/fortsetzen **und** die laufende Rundenzeit
verlängern/verkürzen (per +/- **und** direkter Zahleneingabe); die Statusanzeige zeigt
aktuellen Zustand (Pause/Runde N) + Zeit.

**9.6 Cross-Check-in:** Über den Such-Screen findet der Veranstalter ein Team/Spieler,
sieht dessen Turnier-Anmeldung und checkt ein. Der Screen listet **nur** Turniere in
der Check-in-Phase, die der Veranstalter **selbst publiziert** hat.

**9.7 Berechtigung:** Ohne Manage-Recht kein Dashboard-Zugang und kein Absprung-Button.

---

## 10. Ist-Zustand / Mapping (Code)

- **Detail-Screen:** `tournament_detail_screen.dart` — `canManage`-Blöcke (Check-in ~Z.187,
  Eskalation D5 ~Z.251, Lifecycle ~Z.547–642) **entfernen** + Absprung-Button setzen.
- **Cockpit-Übersicht:** `organizer_dashboard_screen.dart` (`/tournament/dashboard`).
- **Turnier-Steuerung:** `organizer_dashboard_detail_screen.dart`
  (`/tournament/:id/dashboard`) — ScheduleControlBar, Eskalations-Badges, Match-Liste
  mit Override/Forfeit; **erweitern** um Pitch-Nr, „Punkte eintragen", Timer-Verstellen,
  Check-in.
- **Direkter Score:** `tournament_override_controller.dart` (`submit`) als Schreibweg.
- **Pitch:** `packages/kubb_domain/.../pitch_assignment.dart` (`PitchPlan`).
- **Timer/Schedule:** `TournamentRoundScheduleProvider` + ScheduleControlBar.

---

## 11. Geklärte Entscheide & Implementierungs-Hinweise

- **Timer-Verstellen (geklärt):** Rundenzeit per **+/- Schritten UND direkter
  Zahleneingabe** veränderbar. Implementierung: additiver Schreibweg auf die laufende
  Runde, skew-konforme Anzeige auf allen Clients (Messaging-Framework, kein Polling).
- **Direkter Score (geklärt):** **keine Begründung** verlangt. Wird im Audit-Log
  protokolliert (wer/wann/wert).
- **Cross-Check-in Scope (geklärt):** der Such-Screen umfasst **nur** Turniere, die
  (a) **aktuell in der Check-in-Phase** sind UND (b) **vom selben Veranstalter
  publiziert** wurden.
