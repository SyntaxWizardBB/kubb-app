# Spec — Match-Eingabe-Screen & Home-Match-Kachel

**Status:** Verbindliche Implementierungs-Spezifikation & Quality-Gate.
**Geltung:** Der Spieler-Match-/Score-Eingabe-Screen
(`tournament_match_detail_screen.dart`) und die zugehörige Kachel im Kubb-Club
Home-Hub (`home_screen.dart`).
**Verwandt:** [organizer-cockpit-dashboard-spec.md](./organizer-cockpit-dashboard-spec.md)
(Pitch, direkter Score), [vorrunde-ranking-spec.md](./vorrunde-ranking-spec.md).

> **MUSS** = harte Anforderung. **Ist-Zustand** in §6 mit Datei:Zeile.

---

## 1. Zurück-Button (MUSS)

- **Heute (falsch):** Der Zurück-Button macht `context.go(TournamentRoutes.matchesFor(id))`
  (`tournament_match_detail_screen.dart:463-466`) → feste Route zur Match-Liste,
  unabhängig davon, woher man kam.
- **Soll:** Zurück führt **dorthin zurück, woher man gekommen ist** (`context.pop()`
  bzw. Herkunft tracken). Kommt man aus Rangliste/Bracket/Live/Home, landet man dort
  wieder — **nicht** in der Match-Liste.

---

## 2. Zweite Kachel: Pitch statt „Spiel" + Match-Clock (MUSS)

- **Heute:** Die Kopf-Kachel (`_Header`, `:829-868`) zeigt wörtlich
  **„Runde X — Spiel Y"** + Status-Chip. **Keine Pitch-Nummer, keine Clock** darin.
- **Soll:**
  - **„Spiel" entfällt** → stattdessen die **Pitch-Nummer** anzeigen (Runde X · Pitch N).
  - In/an dieser Kachel läuft die **Match-Clock** (Countdown der laufenden Runde).
  - Die Clock existiert bereits als `RoundPhaseCountdown` (`:586-631`), heute aber nur
    separat und nur wenn `match.startedAt != null` — sie MUSS hier prominent laufen
    (inkl. sinnvollem „wartet auf Start"-Zustand).

---

## 3. Anzahl Sätze aus Config (MUSS)

- **Heute (falsch):** `static const int _maxSets = 3` (`:74`), hartkodiert; Add-Button
  sperrt bei `>= 3` (`:180-182`, `:681`). Die Veranstalter-Konfiguration wird **nicht**
  gelesen.
- **Soll:** Die maximale Satzanzahl kommt aus der **Veranstalter-Konfiguration der
  Runde/Phase** (`matchFormatConfig['max_sets']` / `sets_to_win`) — analog zum
  Override-Screen (`tournament_override_screen.dart:75`, `cfg['max_sets']`). Helper
  `_maxSetsFor(round/phase)` wie `_maxBasekubbsFor()`.
- Minimum bleibt 1 Satz.

---

## 4. Grüne Match-Kachel im Home-Hub (MUSS)

- Die **grüne Kachel** vom Match-Screen (`PitchCallBanner`, `pitch_call_banner.dart`,
  meadow500, zeigt Pitch + Gegner + Play) wird **gleich** in den **Home-Hub**
  übernommen.
- Sie **ersetzt** die Platzhalter-Kachel **„Match-Modus / In Vorbereitung"**
  (`home_screen.dart:~125-130`, `homeTournierTitle`/`homeTournierComingSoon`).
- **Conditional:** nur sichtbar, wenn es für den Account **wirklich ein eintragbares
  Match** gibt — gleiche Bedingung wie heute „Laufendes Match"
  (`myActiveTournamentMatchProvider`, Status ∈ {scheduled, awaitingResults},
  fail-closed). Kein Match → keine Kachel.
- **Tap** → Match-Eingabe-Screen (Score-Eingabe).
- Die separate **„Laufendes Match"-Kachel entfällt** (`_OngoingMatchCard`,
  `home_screen.dart:60-64 / 121-124 / 201-232`) — sie wird durch die grüne Kachel
  ersetzt (eine Kachel, nicht zwei).

---

## 5. Akzeptanzkriterien / Quality-Gates (nachprüfbar)

**5.1 Zurück:** Vom Match-Screen aus Rangliste/Bracket/Live/Home aufgerufen → Zurück
landet wieder **in der Herkunft**, nicht in der Match-Liste.

**5.2 Kachel-Inhalt:** Die Kopf-Kachel zeigt **Pitch-Nummer** (kein „Spiel") und eine
**laufende Match-Clock**.

**5.3 Sätze:** Bei einer Runde mit „Best of 3" sind max. 3 Sätze eingebbar, bei
„Best of 5" max. 5 — gemäß Veranstalter-Config, **nicht** fix 3.

**5.4 Home-Kachel:** Bei einem eintragbaren Match erscheint **eine** grüne Match-Kachel
(statt „Match-Modus/In Vorbereitung"); Tap → Score-Eingabe. Ohne Match: keine Kachel.
Die alte „Laufendes Match"-Kachel ist entfernt.

---

## 6. Ist-Zustand / Mapping (Code)

- `tournament_match_detail_screen.dart` — Zurück `:463-466`, `_Header` `:829-868`,
  `RoundPhaseCountdown` `:586-631`, `_maxSets` `:74` / `:180-182` / `:681`.
- `widgets/pitch_call_banner.dart` — die grüne Kachel (meadow500, Pitch+Gegner+Play).
- `home_screen.dart` — „Match-Modus/In Vorbereitung" `:~125-130`; „Laufendes Match"
  `:60-64 / 121-124 / 201-232`.
- `tournament/application/my_active_match_provider.dart` —
  `myActiveTournamentMatchProvider` (Conditional-Quelle).
- `tournament_override_screen.dart:75` — Vorlage für config-basiertes `max_sets`.

---

## 7. Offene Punkte

- **OFFEN-1 (Herkunft-Tracking):** Falls `context.pop()` nicht reicht (Deep-Link ohne
  Stack), wie wird die Herkunft sonst bestimmt (Fallback-Route)?
