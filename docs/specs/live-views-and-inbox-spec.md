# Spec — Live-Sicht (config-adaptiv) & globales Postfach

**Status:** Verbindliche Implementierungs-Spezifikation & Quality-Gate.
**Geltung:** Die Spieler-**Live-Sicht** (3 Reiter: Mein Match / Übersicht / Rangliste)
und der **globale Postfach-Zugang**.
**Verwandt:** [vorrunde-ranking-spec.md](./vorrunde-ranking-spec.md),
[stage-graph-and-stage-type-modeling-spec.md](./stage-graph-and-stage-type-modeling-spec.md),
[stage-seeding-spec.md](./stage-seeding-spec.md).

> **MUSS** = harte Anforderung. **Ist-Zustand** in §5 mit Datei:Zeile.

---

## 1. Drei-Reiter-Struktur (bleibt)

Die Live-Sicht mit **Mein Match / Übersicht / Rangliste** ist grundsätzlich gut und
bleibt. **Aber Übersicht und Rangliste MÜSSEN sich an die Turnier-Config anpassen** —
ein Gruppenphasen-Turnier ist nicht dasselbe wie ein Schoch-Turnier.

---

## 2. Rangliste & Übersicht dynamisch auf die Config (MUSS)

**Heute (falsch):** Keinerlei Format-Anpassung. `TournamentStandingsView` rendert
**immer** eine **flache Liste** mit hart verdrahteter Tiebreak-Kette
(totalPoints→wins→buchholzMinusH2H→kubbDifference); die konfigurierte
`tiebreakerOrder` wird ignoriert. Gruppen-Standings sind ein **separater** Screen
(`tournament_pool_standings_screen.dart`) mit hart kodierten **2** Qualifikanten/Gruppe.
Die Match-Liste gruppiert nur nach Rundennummer — **kein** Gruppen-Label (bei
Gruppenphase erscheint „Runde 1" mehrfach, ohne „Gruppe A").

**Soll — die Live-Reiter richten sich nach dem Vorrunden-Typ:**

| Turnier-Typ / Phase | Rangliste-Reiter | Übersicht-Reiter |
|---|---|---|
| **Gruppenphase** | **gruppierte** Rangliste (eine Tabelle pro Gruppe), **kein Buchholz** (Punkte → Kubb-Differenz, Vorrunde-Spec); Qualifikanten gemäß Config | Match-Liste mit **Gruppen-Label** (z. B. „Gruppe A · Runde 1") |
| **Schoch** | eine Rangliste mit Schoch-Tiebreak (Punkte → **Buchholz**, Vorrunde-Spec) | Match-Liste nach Runde |
| **Jeder-gegen-jeden** | eine Rangliste (Punkte → Kubb-Differenz, Vorrunde-Spec) | Match-Liste nach Runde |
| **KO-Phase** | KO-/Endsicht | **KO-Baum (Bracket)** statt Match-Liste |

**MUSS konkret:**
- **Gruppenphase → gruppierte Rangliste** direkt im Live-Reiter (nicht nur im
  separaten Pool-Screen), **ohne Buchholz** (der ist in Gruppen sinnlos — Vorrunde-Spec).
- **KO-Phase → Bracket:** sobald die KO-Phase läuft, zeigt die **Übersicht** den
  **KO-Baum** (bestehende `tournament_bracket_screen`-Sicht wiederverwenden) statt der
  Rundenliste.
- **Tiebreak-Kette aus der Config** lesen (nicht hart verdrahten); pro Vorrunden-Typ
  die richtige Kette (siehe Vorrunde-/Seeding-Specs).
- **Qualifikanten pro Gruppe aus der Config** (nicht fix 2).
- **Übersicht** zeigt bei Gruppenphase das **Gruppen-Label** je Match.

---

## 3. Korrekte Bezeichnungen (MUSS)

- **Heute:** Header hart `tournamentStandingsPlayer = 'Spieler'` für **alle** Formate;
  keine Unterscheidung Einzel/Team/Gruppe.
- **Soll:** Bezeichnung passt zum Turnier:
  - **Einzel** → „Spieler", **Team-Turnier** → „Team".
  - **Gruppenphase** → Gruppen-Struktur (Gruppe A/B …), nicht eine generische
    „Spieler"-Flachliste.

---

## 4. Globales Postfach (MUSS)

- **Heute:** Postfach-Bell (`InboxBellAction`, `→ /inbox`) auf 27 Screens + Drawer.
  **Fehlt** u. a. auf Profil, Achievements, Freunde, Team-Listen, „Meine Trainings".
  Match-Eingabe-/Config-/Wizard-Screens haben (korrekt) **keine** Bell.
- **Soll:** Das Postfach ist auf **jedem** Screen erreichbar — **außer** auf
  **Config-/Setup-Screens** und **Eingabe-Screens** (Score-Eingabe, Match-Lobby/Config,
  Wizard). Insbesondere ist die Bell auf der **Live-Sicht** vorhanden.
- **Ergänzen** auf den nicht-Eingabe-Screens, denen sie heute fehlt (Profil,
  Achievements, Freunde, Team-Listen, „Meine Trainings", …).

---

## 5. Akzeptanzkriterien / Quality-Gates (nachprüfbar)

**5.1 Gruppenphase-Rangliste:** Im Live-„Rangliste"-Reiter eines Gruppenphasen-Turniers
erscheint eine **gruppierte** Tabelle (pro Gruppe), keine Flachliste.

**5.2 Übersicht-Label:** Im „Übersicht"-Reiter eines Gruppenphasen-Turniers sind Matches
mit **Gruppen-Label** versehen (nicht nur „Runde 1").

**5.3 Tiebreak aus Config:** Die Rangliste verwendet die zum Vorrunden-Typ passende
Tiebreak-Kette aus der Config (Schoch: Punkte→Buchholz; Gruppe/J-g-j:
Punkte→Kubb-Differenz), nicht eine hart verdrahtete.

**5.4 Bezeichnung:** Team-Turnier zeigt „Team", Einzel „Spieler"; Gruppen-Turnier zeigt
Gruppen-Struktur.

**5.5 Postfach:** Bell ist auf der Live-Sicht und allen Nicht-Eingabe/Config-Screens
vorhanden; auf Eingabe-/Config-Screens fehlt sie (gewollt).

**5.6 KO-Bracket:** Sobald die KO-Phase läuft, zeigt die „Übersicht" den KO-Baum
(Bracket) statt der Rundenliste.

---

## 6. Ist-Zustand / Mapping (Code)

- `tournament_live_screen.dart` — 3 Reiter; Reiter „Rangliste" = `TournamentStandingsView`,
  „Übersicht" = `TournamentMatchListView`.
- `tournament_standings_screen.dart` — flache Liste, Header „Spieler" `:202`, hart
  Tiebreak `:177-182`.
- `tournament_pool_standings_screen.dart` — gruppierte Standings (separat),
  Qualifikanten hart =2 `:72`.
- `tournament_match_list_screen.dart` — Gruppierung nur nach Runde, kein Gruppen-Label
  `:125-129`; `match.phase` (group/ko) vorhanden, aber nicht gerendert.
- `tournament_match_providers.dart:143-184` — Standings-Provider, ignoriert
  `tiebreakerOrder`.
- `core/ui/widgets/inbox_bell_action.dart` — die Bell; `kubb_drawer.dart` Postfach-Eintrag.

---

## 7. Geklärte Entscheide

- **Hybrid-Phasenwechsel (geklärt):** Bei Gruppenphase→KO zeigt während der KO-Phase
  die **Übersicht** den **KO-Baum (Bracket)**, die **Rangliste** die KO-/Endsicht. Die
  Vorrunden-Rangliste (gruppiert bzw. Schoch) gilt während der Vorrunde; mit Start der
  KO-Phase schaltet die Sicht phasen-bewusst um.
