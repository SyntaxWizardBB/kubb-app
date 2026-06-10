# Tournament Testing Suite — Manuelles 2-Emulator-Drehbuch (PLAYBOOK)

> **Status:** Doku (Block T-Playbook). **Branch:** `feat/tournament-scheduler-dashboard`.
> **Reines Dokument** — keine Code-/Logik-Änderung, keine Tests, keine Migrationen.
>
> **Quelle der Wahrheit:** [`./SPEC.md`](./SPEC.md)
> (`docs/plans/tournament-testing-suite/SPEC.md`). Jeder Achsen-Wert, jede Steering-
> Regel und jede IS-vs-WISH-Aussage in diesem Drehbuch leitet sich aus der SPEC ab.
> Wo dieses Dokument knapp ist, gilt die SPEC.

---

## 0. Zweck & Abgrenzung

Dieses Drehbuch ist ein **MANUELLES 2-Emulator-Testprotokoll**. Es wird von Hand
auf zwei laufenden App-Instanzen ("Emulatoren") gespielt:

- **Emulator A = Veranstalter/Organizer** — erstellt das Turnier (Setup-Wizard),
  startet/pausiert/skippt die Runde, togglet Check-in, erklärt Forfaits, macht
  Overrides. Account mit Organizer-Rechten (Vereins-`owner/admin/organizer` oder
  Ersteller eines persönlichen Turniers).
- **Emulator B = Spieler/Testaccount** — meldet sich an, trägt Resultate via
  `+/-`-Stepper ein. **Dieser Account ist der gesteuerte TARGET** (siehe §3).

### 0.1 Verhältnis zur Automatisierung (NICHT alle von Hand)

Die **vollständige Kombinatorik** der Konfigurations-Achsen wird von der
**automatisierten pgTAP-Suite** abgedeckt, nicht von Hand:

- **96 Config-Combos** (SPEC §2: `G01–G72` group_phase + `S01–S24` schoch)
- **× 3 Teilnehmer-Größen** `N ∈ {32, 48, 60}` (SPEC §0.3)
- = **288 Lifecycle-Runs**, automatisch über `supabase test db` (SPEC §3, §6.1).

Dieses manuelle Drehbuch spielt **nur repräsentative Szenarien** von Hand
(siehe §5 für die Auswahl-Begründung): jede KO-Modell-Variante (A2) mindestens
einmal, jede Vorrunde-Variante (A1) mindestens einmal, jede Feature-Aktion
mindestens einmal. Es ist **nicht erschöpfend** — die volle Matrix bleibt der
Automatisierung überlassen. Die 8 manuellen Szenarien stehen in §6; die
Abdeckungs-Matrix in §7 beweist, dass nichts Gefordertes fehlt.

### 0.2 IS vs WISH — was hier getestet wird (Verweis SPEC §0.2)

Dieses Drehbuch testet **ausschließlich den IST-Stand** des gebauten Codes. Die
`#`-Kommentare in `humanPlan/MilestoneTournaments.txt` sind **Zukunfts-Wünsche**
und werden hier **NICHT** als zu testendes Verhalten übernommen (SPEC §0.2). Konkret
gilt im gesamten Drehbuch:

- **Teilnehmerzahlen** aus `N ∈ {32, 48, 60}` (≤ Code-Cap 64, `koBracketSizeCap`).
  **Nie 1000** — der 1000er-Wunsch wird nicht getestet.
- **Jedes Turnier hat IMMER eine KO-Phase** (kein "Kein KO").
- **"Spiel um Platz 3" ist fix an** (`with_third_place_playoff = true`, kein Toggle).
- **"Kein Verein (persönlich)"** bleibt so benannt (nicht "Spasstournier"); Diggy-
  Default bleibt **aus**; optionale Stammdaten bleiben optional.

---

## 1. Achsen-Referenz (SPEC §1) — gültige Wizard-Config-Werte

Alle in den Setup-Schritten genannten Werte sind `snake_case`-Achsenwerte aus
**SPEC §1**. Kurzreferenz:

| Achse | Wire-Key | gültige Werte |
|---|---|---|
| **A1** Vorrunde | `vorrunde_type` | `group_phase` (→ `round_robin_then_ko`), `schoch` (→ `swiss_then_ko`) |
| **A2** KO-System | `ko_type` | `single_out` (→ `single_elimination`), `double_out` (→ `double_elimination`), `consolation` (→ `single_elimination` + `consolation_bracket.enabled=true`) |
| **A3** KO-Matchup | `ko_matchup` | `seed_high_vs_low`, `one_vs_two` |
| **A4** KO-Tiebreak | `ko_tiebreak_method` | `classic_kingtoss_removal`, `mighty_finisher_shootout` |
| **A5** Scoring | `scoring` | `ekc`, `classic` |
| **A6** Pool-Strategy | `pool_phase_config.strategy` | `snake`, `seeded`, `random` — **nur bei `group_phase`** |
| **A7** Schoch-Runden | client `_swissRounds` | fix `7` (innerhalb `[5,9]`) — **nur bei `schoch`** |

**Abgeleitete Invarianten (SPEC §1.1), in jedem Szenario implizit:**
`p_format` aus (A1×A2); `bracket_type` aus A2; `qualifier_count` = Zweierpotenz ≤ N,
gedeckelt auf 64 → **N=32 → 16, N=48 → 32, N=60 → 32**;
`with_third_place_playoff = true`; `seeding_mode = auto`. Für `consolation`:
`consolation_bracket = { enabled:true, source:"early_ko_losers",
main_bracket_size:<next_pow2(qualifier_count)>, direct_count:0,
name:"Sieger der gebrochenen Herzen" }` (+ `consolation_name`). Für `schoch`:
Auto-Einzel-Pool (`pool_phase_config = { group_count:1, strategy:"seeded",
qualifiers_per_group:<qualifier_count> }`); **A6 ist N/A**.

---

## 2. UI-Surfaces (reale Screens/Widgets im Code)

Jeder hier genannte Screen/Widget existiert als Datei unter
`lib/features/tournament/presentation/`:

| Surface | Datei | Rolle/Aktion |
|---|---|---|
| **Registrierung** | `tournament_registration_screen.dart` (Singles `registerSingle`), `register_team_screen.dart` (Teams) | Emulator B meldet sich an / bestätigt |
| **Score-Eingabe** | `tournament_match_detail_screen.dart` + Widget `widgets/tournament_set_input.dart` (`+/-`-Stepper, `LucideIcons.minus`/`plus`) | Emulator B trägt Satz-Resultat ein |
| **Dashboard Start/Pause/Skip** | `organizer_dashboard_screen.dart` + Widget `widgets/schedule_control_bar.dart` (Start/Pause/Resume, SkipForward = irreversibel/Press-and-Hold, SkipBack) | Emulator A treibt den Runden-Takt |
| **Check-in** | `tournament_detail_screen.dart` → `ParticipantCheckinToggle` (Check-in-Fenster) | Emulator A togglet Check-in |
| **Notifications/Inbox** | durable Rows in `public.user_inbox_messages` → Inbox-UI | Emulator B sieht Go-Live/Round-Publish |
| **Turnierdetails** | `tournament_detail_screen.dart` + Widget `widgets/tournament_stammdaten_card.dart` | beide prüfen Stammdaten/Status |
| **Forfait** | `widgets/tournament_forfeit_sheet.dart` (RPC `tournament_match_forfeit`) | Emulator A erklärt Forfait |
| **Override** | `tournament_override_screen.dart` (RPC `tournament_organizer_override_pairing`) | Emulator A überschreibt Pairing/Seeding |

**RPCs/Trigger hinter den Aktionen** (SPEC §0.1, korrekt benannt): `tournament_create`,
`tournament_start` / `tournament_start_stage_graph` / `tournament_start_ko_phase`,
`tournament_pair_round`, `tournament_set_seeding`, `tournament_propose_set_scores`
(Konsens-Pfad der Score-Eingabe), `tournament_match_forfeit`,
`tournament_organizer_override_pairing`, `tournament_organizer_override`,
`tournament_schedule_tick` + `advance_ko_winner`-Trigger (Runden-Advance).

---

## 3. Steering-Strategie "Testaccount erreicht Finale / Trostfinale" (SPEC §5)

Der **TARGET** ist der Account mit dem **niedrigsten `registered_at` = Seed 1**
unter `seeding_mode = auto` (SPEC §5). Emulator B meldet sich **zuerst** an, damit
er Seed 1 wird.

**Steuer-Regel (SPEC §5):**

1. **Target gewinnt jede eigene Begegnung.** In jedem Match, an dem Emulator B
   beteiligt ist, wird das Resultat so eingetragen, dass der Target-Account gewinnt.
2. **Restliche Matches in Seed-Reihenfolge.** Alle anderen Begegnungen einer Runde
   werden deterministisch zugunsten des höher gesetzten Teams (niedrigerer Seed)
   beendet. So bleibt das Bracket vorhersehbar und Target trifft planbar auf
   schwächere Gegner.

Daraus folgen die Endpunkte je KO-Modell (SPEC §5):

- **single_out** (`target_wins`): Target gewinnt jede KO-Runde → landet in
  `phase='final'`. **Ziel: Testaccount im Final.**
- **double_out** (`target_wins`): Target bleibt im Winners-Bracket bis zum
  Grand-Final (nimmt nie die erste Niederlage). **Ziel: Testaccount im Grand-Final
  (Winners-Seite).**
- **consolation** — **beide Endpunkte** (SPEC §4-A6, §5):
  - **Hauptbaum** (`target_wins`): Target gewinnt durch → **Hauptbaum-Final**.
  - **Trostturnier** (`target_to_consolation`): Target wird in einer **frühen
    KO-Runde absichtlich verloren**, der `advance_ko_winner`-Trigger routet ihn
    über `early_ko_losers` ins Trostturnier; danach gewinnt er seine Trost-Matches →
    **Trostfinal** ("Sieger der gebrochenen Herzen"). **Ziel: Testaccount im
    Trostfinal.**
- **schoch** (Vorrunde): Target gewinnt jede Schoch-Paarung → Tabellenführer →
  qualifiziert sicher; ab KO-Phase greift die Steuer-Regel wie oben.

---

## 4. Runden-Takt — "sag wann nächste Runde"

Der Veranstalter (Emulator A) steuert die Uhr über `schedule_control_bar`:

- **Start** — startet die aktuelle Runde (nur sichtbar wenn noch keine läuft).
- **Pause / Resume** — friert die Runden-Uhr ein bzw. setzt sie fort.
- **Skip forward** — **irreversibel** (forciert sofortigen Runden-Start);
  als **Press-and-Hold** ausgeführt (Hold-Geste in `_HoldToConfirmButton`).
- **Skip back** — re-callt das aktuelle Fenster (plain tap, "reversible-ish").

**Takt-Marke "➡️ SAG WANN NÄCHSTE RUNDE":** Nach jedem vollständigen Eintragen aller
Resultate einer Runde **wartet das Drehbuch auf das explizite Kommando**, bevor
Emulator A die nächste Runde startet/skippt. Diese Marke steht in jedem Szenario
zwischen den Runden. Hinter der Runden-Schaltung steht `tournament_schedule_tick`
+ der `advance_ko_winner`-Trigger, der Sieger/Verlierer in die nächsten
Bracket-Slots propagiert.

---

## 5. Szenario-Auswahl — repräsentativ, nicht erschöpfend (SPEC §2)

Begründung der Auswahl (Abdeckungs-Logik, SPEC §6.4 + §0.1):

- **Jede A2-KO-Variante ≥ 1×:** `single_out` (Szenario 1), `double_out` (2),
  `consolation` mit **beiden** Endpunkten (3 = Hauptbaum, 4 = Trostfinal).
- **Jede A1-Vorrunde ≥ 1×:** `group_phase` (1, 3, 4, 6, 7), `schoch` (2, 5, 8).
- **Jede Feature-Aktion ≥ 1×** (siehe §7-Matrix): Registrierung, Score `+/-`,
  Forfait, Bye, Override, Pause, Skip, Check-in.
- **A3/A5/A6** repräsentativ gestreut: beide A3-Werte, beide A5-Werte, alle drei
  A6-Pool-Strategien (`snake`/`seeded`/`random`) tauchen je mindestens einmal in
  einem `group_phase`-Szenario auf. **A4** ist im manuellen Satz fix auf
  `classic_kingtoss_removal` (die Kombinatorik mit `mighty_finisher_shootout`
  übernimmt die Automatisierung, siehe §7.1).

**8 manuelle Szenarien** (≪ 96, nummeriert, duplikatfrei). Die **vollständige
Kombinatorik bleibt der Automatisierung** überlassen (SPEC §2/§3). Jedes Szenario
ist einer SPEC-Matrix-Zeile (`G..`/`S..`) zugeordnet, sodass nachvollziehbar ist,
welchen Matrix-Bereich es repräsentiert.

| # | Repräsentiert | SPEC-Zeile | N | KO-Endpunkt |
|---|---|---|---|---|
| 1 | group_phase · single_out · snake | **G01** | 32 | Hauptbaum-Final |
| 2 | schoch · single_out · classic | **S06** | 48 | Hauptbaum-Final |
| 3 | group_phase · consolation (Hauptbaum) | **G50** | 32 | Hauptbaum-Final |
| 4 | group_phase · consolation (Trost) · random | **G51** | 32 | **Trostfinal** |
| 5 | schoch · double_out | **S09** | 48 | Grand-Final |
| 6 | group_phase · double_out · random | **G27** | 60 | Grand-Final |
| 7 | group_phase · single_out · seeded (Check-in/Override-Fokus) | **G17** | 32 | Hauptbaum-Final |
| 8 | schoch · consolation (Trost) | **S17** | 60 | **Trostfinal** |

---

## 6. Die Szenarien

> **Jedes Szenario** folgt der einheitlichen Struktur (DoD-08):
> **(1) Setup Emulator A · (2) Aktionen Emulator B · (3) Veranstalter-Aktionen ·
> (4) Erwartetes UI/Ergebnis · (5) Runden-Takt-Marken · (6) Ziel.**
> Emulator B ist immer der TARGET (Seed 1, §3).

---

### Szenario 1 — group_phase · single_out (SPEC-Zeile G01, N=32)

Deckt: A1 `group_phase`, A2 `single_out`, A6 `snake`; Aktionen Registrierung,
Score `+/-`, **Bye**, **Pause**.

**(1) Setup — Emulator A (Veranstalter, `tournament_create`):**
- Wizard Schritt 1 Stammdaten: Turniername frei; **Verein = "Kein Verein
  (persönlich)"** (`club_id = null`, persönliches Turnier — nicht umbenannt, §0.2);
  `scoring = ekc` (A5).
- Schritt 2 Teilnehmer: `max_participants = 32` (N=32, ≤ Cap 64); `team_size = 1`
  (Singles).
- Schritt 3 Format: `vorrunde_type = group_phase` (A1) → `p_format =
  round_robin_then_ko`; `ko_type = single_out` (A2) → `bracket_type =
  single_elimination`; `ko_matchup = seed_high_vs_low` (A3); `ko_tiebreak_method =
  classic_kingtoss_removal` (A4).
- Schritt 4 KO-Config: `qualifier_count = 16` (N=32 → 16, §1.1); `with_third_place_playoff
  = true` (fix); `seeding_mode = auto`.
- Schritt 5 Pool: `pool_phase_config.strategy = snake` (A6); `group_count = 4`
  (teilt KO-Bracket 16 glatt) → `qualifiers_per_group = 4`.
- Schritt 6 Zusammenfassung → **Anlegen**.

**(2) Aktionen — Emulator B (Spieler/TARGET):**
- **Registrierung** (`tournament_registration_screen` → `registerSingle`): meldet
  sich als **ERSTER** an (niedrigstes `registered_at` → Seed 1, §3).
- (31 weitere Teilnehmer melden sich an; einer kann fehlen, um in einer
  ungeraden Gruppe einen **Bye** zu erzeugen.)
- **Score-Eingabe** (`tournament_match_detail_screen` + `tournament_set_input`):
  trägt in jeder eigenen Begegnung über den **`+/-`-Stepper** das Satz-Resultat
  zugunsten des Target ein (`tournament_propose_set_scores`, Konsens).

**(3) Veranstalter-Aktionen — Emulator A:**
- Vor Start: **Pause** kurz testen (`schedule_control_bar` → Pause/Resume) — Uhr
  friert ein und läuft wieder an.
- **Bye prüfen:** in einer Gruppe mit ungerader Teilnehmerzahl bekommt ein Team ein
  **Freilos**; A prüft, dass der Bye-Slot nicht als offenes Match hängt.
- Start jeder Runde per **Start** an der Takt-Marke.

**(4) Erwartetes UI/Ergebnis:**
- Nach Anlegen: Status `draft`. Nach Start: Vorrunde `live`, Gruppen-Matches sichtbar
  (`tournament_match_list_screen`).
- Inbox/Notifications: Go-Live erzeugt ≥1 `user_inbox_messages`-Row für Teilnehmer.
- Target steht nach Vorrunde oben in seiner Gruppe (`tournament_pool_standings_screen`)
  und qualifiziert (Seed 1 im KO).
- KO single_elim: Rundenzahl `ceil(log2(16)) = 4`; genau ein `phase='final'` + ein
  `phase='third_place'`.

**(5) Runden-Takt:**
`➡️ SAG WANN NÄCHSTE RUNDE` nach jeder Gruppenrunde; danach Cut auf 16; dann
`➡️ SAG WANN NÄCHSTE RUNDE` vor Achtelfinale → Viertelfinale → Halbfinale → Final.

**(6) Ziel:** **Testaccount (Emulator B, Seed 1) erreicht das Finale.** Target
gewinnt jede eigene Begegnung, Rest in Seed-Reihenfolge (§3).

---

### Szenario 2 — schoch · single_out (SPEC-Zeile S06, N=48)

Deckt: A1 `schoch` (A6 N/A), A2 `single_out`, A3 `one_vs_two`; Runden-Takt der
Schoch-Runden; Aktionen Registrierung, Score `+/-`, **Skip forward**.

**(1) Setup — Emulator A:**
- Stammdaten: `scoring = classic` (A5).
- Teilnehmer: `max_participants = 48` (N=48); `team_size = 1`.
- Format: `vorrunde_type = schoch` (A1) → `p_format = swiss_then_ko`;
  `ko_type = single_out` (A2); `ko_matchup = one_vs_two` (A3);
  `ko_tiebreak_method = classic_kingtoss_removal` (A4). **A6 ist N/A** (keine
  Pool-Strategy-Auswahl bei Schoch). Schoch-Runden `_swissRounds = 7` (A7, fix).
- KO-Config: `qualifier_count = 32` (N=48 → 32, §1.1; 16 Non-Qualifier ⇒ Cut);
  `seeding_mode = auto`. Auto-Einzel-Pool (`group_count=1, strategy=seeded,
  qualifiers_per_group=32`, §1.1) wird automatisch gesetzt.

**(2) Aktionen — Emulator B (TARGET):**
- **Registrierung** zuerst (Seed 1).
- **Score-Eingabe** via `+/-`-Stepper: gewinnt jede Schoch-Paarung; ab KO jede
  KO-Begegnung (`tournament_propose_set_scores`).

**(3) Veranstalter-Aktionen — Emulator A:**
- Schoch-Runden: Start jeder Runde an der Takt-Marke; `tournament_pair_round`
  berechnet die nächste Paarung (no-repeat / max-ein-Bye).
- **Skip forward** mindestens einmal demonstrieren (`schedule_control_bar`,
  **Press-and-Hold**): forciert sofortigen Runden-Start. **Hinweis im Drehbuch:
  irreversibel** — nur ausführen, wenn die Runde wirklich vorgezogen werden soll.

**(4) Erwartetes UI/Ergebnis:**
- Eine Schoch-Runde = jedes bestätigte Team hat genau eine Paarung (Gegner oder Bye)
  (SPEC §1.2). Rundenzahl ≤ 7.
- Target führt die Schoch-Tabelle und steht unter den Top 32 (Cut).
- KO single_elim ab `qualifier_count = 32`: `ceil(log2(32)) = 5` Runden;
  ein `phase='final'`.
- Inbox: Round-Publish erzeugt `user_inbox_messages`-Rows.

**(5) Runden-Takt:**
`➡️ SAG WANN NÄCHSTE RUNDE` nach jeder Schoch-Runde (bis Cut entschieden, ≤ 7);
danach `➡️ SAG WANN NÄCHSTE RUNDE` durch die 5 KO-Runden bis Final.

**(6) Ziel:** **Testaccount erreicht das Finale** (single_out, `target_wins`, §3/§5).

---

### Szenario 3 — group_phase · consolation, Hauptbaum-Pfad (SPEC-Zeile G50, N=32)

Deckt: A2 `consolation` **Hauptbaum-Endpunkt** (`target_wins`); A6 `seeded`;
Aktion **Forfait**.

**(1) Setup — Emulator A:**
- Stammdaten: `scoring = ekc` (A5).
- Teilnehmer: `max_participants = 32` (N=32); `team_size = 1`.
- Format: `vorrunde_type = group_phase` (A1); `ko_type = consolation` (A2) →
  `bracket_type = single_elimination` + `consolation_bracket.enabled = true`;
  `ko_matchup = seed_high_vs_low` (A3); `ko_tiebreak_method =
  classic_kingtoss_removal` (A4).
- KO-Config: `qualifier_count = 16`; `consolation_name = "Sieger der gebrochenen
  Herzen"` (required, gesetzt); `consolation_main_bracket_size = next_pow2(16) = 16`,
  `consolation_direct_count = 0`.
- Pool: `strategy = seeded` (A6); `group_count = 4`.

**(2) Aktionen — Emulator B (TARGET):**
- **Registrierung** zuerst (Seed 1).
- **Score-Eingabe** via `+/-`: gewinnt jede eigene Begegnung im **Hauptbaum**.

**(3) Veranstalter-Aktionen — Emulator A:**
- **Forfait** (`tournament_forfeit_sheet` → `tournament_match_forfeit`): in einer
  Begegnung zweier Nicht-Target-Teams erklärt A einen Forfait (z. B. No-Show). Das
  beendet das Match per Walkover, der gewertete Gegner zieht weiter.
- Start je Runde an der Takt-Marke.

**(4) Erwartetes UI/Ergebnis:**
- `consolation_bracket.enabled` sichtbar; Haupt-Bracket-Größe 16; früh
  ausgeschiedene Verlierer werden via `early_ko_losers` ins Trostturnier geroutet
  (hier nicht der Target — der gewinnt durch).
- Forfait-Match erscheint als terminal (Walkover); kein offenes Match bleibt hängen.
- Target steht im **Hauptbaum-Final**.

**(5) Runden-Takt:**
`➡️ SAG WANN NÄCHSTE RUNDE` nach jeder Gruppenrunde, dann durch alle KO-Runden des
Hauptbaums bis Final.

**(6) Ziel:** **Testaccount erreicht den Hauptbaum-Final** (consolation `target_wins`,
§5). (Der Trost-Endpunkt wird in Szenario 4 gespielt.)

---

### Szenario 4 — group_phase · consolation, Trost-Pfad (SPEC-Zeile G51, N=32)

Deckt: A2 `consolation` **Trostturnier-Endpunkt** (`target_to_consolation`); A6
`random`; Aktion **Bye** (im Trostturnier).

**(1) Setup — Emulator A:** gleicher consolation-Block wie Szenario 3, aber die
`random`-Variante (SPEC-Zeile **G51**, N=32) — `consolation`, `qualifier_count = 16`,
`consolation_name = "Sieger der gebrochenen Herzen"`, `consolation_main_bracket_size
= 16`, `consolation_direct_count = 0` — **mit Pool `strategy = random`** (A6;
`random_seed` gesetzt für Determinismus). Szenario 3 deckt damit G50 (`seeded`),
Szenario 4 die distinkte Zeile G51 (`random`) ab.

**(2) Aktionen — Emulator B (TARGET):**
- **Registrierung** zuerst (Seed 1).
- **Score-Eingabe** via `+/-`: gewinnt die Vorrunde und qualifiziert. Dann
  **absichtlich früh im Hauptbaum verlieren** (z. B. erste KO-Runde): trägt das
  Resultat zu seinen Ungunsten ein. Der `advance_ko_winner`-Trigger routet den
  Target über `early_ko_losers` ins **Trostturnier**.
- Danach **gewinnt der Target seine Trost-Matches** via `+/-` durch bis zum
  Trostfinal.

**(3) Veranstalter-Aktionen — Emulator A:**
- **Bye prüfen** im Trostturnier: je nach Anzahl früher KO-Verlierer kann ein
  Trost-Slot ein **Freilos** erhalten; A prüft, dass der Bye sauber gewertet ist und
  kein Match offen bleibt.
- Start je Runde an der Takt-Marke.

**(4) Erwartetes UI/Ergebnis:**
- Nach dem absichtlichen Verlust erscheint der Target im **Trostbaum** (Titel oben
  zeigt den Trost-Namen "Sieger der gebrochenen Herzen").
- Trostturnier hat einen finalisierbaren `consolation`-Final.
- Dense Placement: Ränge unterhalb des Hauptbaums werden vom Trost-Bracket gefüllt
  (SPEC §4-A1).

**(5) Runden-Takt:**
`➡️ SAG WANN NÄCHSTE RUNDE` nach Vorrunde; dann erste KO-Runde (Target verliert
absichtlich); dann `➡️ SAG WANN NÄCHSTE RUNDE` durch die Trost-Runden bis Trostfinal.

**(6) Ziel:** **Testaccount erreicht den Trostfinal** (consolation
`target_to_consolation`, §5). Zusammen mit Szenario 3 sind **beide** consolation-
Endpunkte abgedeckt (SPEC §4-A6/§5).

---

### Szenario 5 — schoch · double_out (SPEC-Zeile S09, N=48)

Deckt: A1 `schoch`, A2 `double_out`; Aktion **Override**.

**(1) Setup — Emulator A:**
- Stammdaten: `scoring = ekc` (A5).
- Teilnehmer: `max_participants = 48` (N=48); `team_size = 1`.
- Format: `vorrunde_type = schoch` (A1) → `swiss_then_ko`; `ko_type = double_out`
  (A2) → `bracket_type = double_elimination`; `ko_matchup = seed_high_vs_low` (A3);
  `ko_tiebreak_method = classic_kingtoss_removal` (A4). `_swissRounds = 7` (A7).
- KO-Config: `qualifier_count = 32` (N=48 → 32); Auto-Einzel-Pool wie §1.1.

**(2) Aktionen — Emulator B (TARGET):**
- **Registrierung** zuerst (Seed 1).
- **Score-Eingabe** via `+/-`: gewinnt jede Schoch-Paarung und jede Winners-Bracket-
  Begegnung (nimmt **nie** die erste Niederlage).

**(3) Veranstalter-Aktionen — Emulator A:**
- **Override** (`tournament_override_screen` → `tournament_organizer_override_pairing`):
  korrigiert eine konkrete KO-Paarung/Setzung manuell (z. B. zwei Nicht-Target-Teams
  tauschen). A prüft, dass das überschriebene Pairing übernommen wird.
- Start je Runde an der Takt-Marke.

**(4) Erwartetes UI/Ergebnis:**
- Double-Elim: ein **Winners-** und ein **Losers-Bracket** existieren; der
  Grand-Final-Feeder kommt aus beiden; **kein Team ist vor zwei Niederlagen
  eliminiert** (SPEC §4-A2).
- Target erreicht den Grand-Final von der **Winners-Seite** (kein Loser-Bracket-
  Umweg).

**(5) Runden-Takt:**
`➡️ SAG WANN NÄCHSTE RUNDE` nach jeder Schoch-Runde (≤ 7); dann durch Winners-/
Losers-Runden bis Grand-Final.

**(6) Ziel:** **Testaccount erreicht den Grand-Final (Winners-Seite)** (double_out
`target_wins`, §5).

---

### Szenario 6 — group_phase · double_out · random (SPEC-Zeile G27, N=60)

Deckt: A2 `double_out`, A6 `random`, größte getestete N (60, nahe Cap); Aktion
**Skip back** + Bye in der Gruppenphase.

**(1) Setup — Emulator A:**
- Stammdaten: `scoring = ekc` (A5).
- Teilnehmer: `max_participants = 60` (N=60, ≤ Cap 64); `team_size = 1`.
- Format: `vorrunde_type = group_phase` (A1); `ko_type = double_out` (A2) →
  `double_elimination`; `ko_matchup = seed_high_vs_low` (A3); `ko_tiebreak_method =
  classic_kingtoss_removal` (A4).
- KO-Config: `qualifier_count = 32` (N=60 → 32; 28 Non-Qualifier); `seeding_mode =
  auto`.
- Pool: `strategy = random` (A6, `random_seed` gesetzt); `group_count = 8` (teilt 32
  glatt) → `qualifiers_per_group = 4`. Bei 60 auf 8 Gruppen ⇒ ungleiche Füllung ⇒
  **Byes** in der Gruppenphase.

**(2) Aktionen — Emulator B (TARGET):**
- **Registrierung** zuerst (Seed 1).
- **Score-Eingabe** via `+/-`: gewinnt Vorrunde + Winners-Bracket durch.

**(3) Veranstalter-Aktionen — Emulator A:**
- **Skip back** (`schedule_control_bar`, plain tap): re-callt das aktuelle Fenster
  einer Runde (reversible) — Gegenprobe zum irreversiblen Skip forward aus Szenario 2.
- **Bye prüfen** in der Gruppenphase (ungerade Gruppenfüllung bei N=60).
- Start je Runde an der Takt-Marke.

**(4) Erwartetes UI/Ergebnis:**
- Gruppen mit Bye werden korrekt gewertet; kein offenes Bye-Match.
- Double-Elim wie Szenario 5: Winners-/Losers-Bracket, Grand-Final-Feeder aus beiden.
- Target im Grand-Final (Winners-Seite).

**(5) Runden-Takt:**
`➡️ SAG WANN NÄCHSTE RUNDE` nach jeder Gruppenrunde; dann durch Winners-/Losers-
Runden bis Grand-Final.

**(6) Ziel:** **Testaccount erreicht den Grand-Final (Winners-Seite)** (§5).

---

### Szenario 7 — group_phase · single_out · seeded, Check-in-Fokus (SPEC-Zeile G17, N=32)

Deckt: A3 `one_vs_two`, A5 `classic`, A6 `seeded`; Aktionen **Check-in**, Override,
Turnierdetails.

**(1) Setup — Emulator A:**
- Stammdaten: `scoring = classic` (A5); **`checkin_until` gesetzt** (Check-in-Fenster
  aktiv).
- Teilnehmer: `max_participants = 32` (N=32); `team_size = 1`.
- Format: `vorrunde_type = group_phase` (A1); `ko_type = single_out` (A2);
  `ko_matchup = one_vs_two` (A3); `ko_tiebreak_method = classic_kingtoss_removal`
  (A4).
- KO-Config: `qualifier_count = 16`; `seeding_mode = auto`.
- Pool: `strategy = seeded` (A6); `group_count = 4`.

**(2) Aktionen — Emulator B (TARGET):**
- **Registrierung** zuerst (Seed 1).
- **Turnierdetails prüfen** (`tournament_detail_screen` + `tournament_stammdaten_card`):
  B sieht alle gesetzten Stammdaten (Scoring `classic`, Check-in-Fenster, Format).
- **Score-Eingabe** via `+/-`: gewinnt jede eigene Begegnung.

**(3) Veranstalter-Aktionen — Emulator A:**
- **Check-in** (`tournament_detail_screen` → `ParticipantCheckinToggle`): **innerhalb
  des Check-in-Fensters** (`checkin_until`) togglet A den Check-in einzelner
  Teilnehmer. A prüft, dass der Check-in-Status korrekt umschaltet.
- **Override** (`tournament_override_screen`): eine KO-Paarung manuell korrigieren
  (`tournament_organizer_override_pairing`).
- Start je Runde an der Takt-Marke.

**(4) Erwartetes UI/Ergebnis:**
- Check-in-Toggle nur im Fenster wirksam; Status pro Teilnehmer sichtbar.
- Turnierdetails zeigen alle gesetzten Stammdaten verdichtet
  (`TournamentStammdatenCard`).
- KO single_elim (16): 4 Runden, ein Final + ein Third-Place.

**(5) Runden-Takt:**
`➡️ SAG WANN NÄCHSTE RUNDE` nach jeder Gruppenrunde; dann durch 4 KO-Runden bis
Final.

**(6) Ziel:** **Testaccount erreicht das Finale** (single_out `target_wins`, §5).

---

### Szenario 8 — schoch · consolation, Trost-Pfad (SPEC-Zeile S17, N=60)

Deckt: A1 `schoch` + A2 `consolation` **Trost-Endpunkt** (`target_to_consolation`)
in der Schoch-Welt; Aktionen Forfait + Notifications/Inbox.

**(1) Setup — Emulator A:**
- Stammdaten: `scoring = ekc` (A5).
- Teilnehmer: `max_participants = 60` (N=60); `team_size = 1`.
- Format: `vorrunde_type = schoch` (A1) → `swiss_then_ko`; `ko_type = consolation`
  (A2) → `single_elimination` + `consolation_bracket.enabled = true`; `ko_matchup =
  seed_high_vs_low` (A3); `ko_tiebreak_method = classic_kingtoss_removal` (A4).
  `_swissRounds = 7` (A7); **A6 N/A**.
- KO-Config: `qualifier_count = 32` (N=60 → 32); `consolation_name = "Sieger der
  gebrochenen Herzen"`; `consolation_main_bracket_size = next_pow2(32) = 32`,
  `consolation_direct_count = 0`. Auto-Einzel-Pool wie §1.1.

**(2) Aktionen — Emulator B (TARGET):**
- **Registrierung** zuerst (Seed 1).
- **Score-Eingabe** via `+/-`: gewinnt jede Schoch-Paarung und qualifiziert. Dann
  **absichtlich früh im Hauptbaum verlieren** → Routing über `early_ko_losers` ins
  Trostturnier; danach Trost-Matches gewinnen bis Trostfinal.
- **Inbox prüfen:** B sieht Go-Live- und Round-Publish-Notifications in der Inbox
  (`user_inbox_messages`).

**(3) Veranstalter-Aktionen — Emulator A:**
- **Forfait** (`tournament_forfeit_sheet`): in einer Schoch- oder KO-Begegnung
  zweier Nicht-Target-Teams einen Forfait erklären.
- Start je Runde an der Takt-Marke.

**(4) Erwartetes UI/Ergebnis:**
- Schoch-Vorrunde qualifiziert Target sicher; consolation-Bracket aktiv (Haupt 32).
- Nach absichtlichem Verlust: Target im Trostbaum ("Sieger der gebrochenen Herzen").
- Inbox enthält ≥1 Notification-Row pro publizierter Runde (SPEC §4-A4).

**(5) Runden-Takt:**
`➡️ SAG WANN NÄCHSTE RUNDE` nach jeder Schoch-Runde (≤ 7); dann erste KO-Runde
(Target verliert absichtlich); dann durch die Trost-Runden bis Trostfinal.

**(6) Ziel:** **Testaccount erreicht den Trostfinal** (consolation
`target_to_consolation`, §5).

---

## 7. Abdeckungs-/Traceability-Matrix

Jede repräsentative Achsen-Ausprägung (A1–A6) und jede der **8 Feature-Aktionen** ist
mindestens einem Szenario zugeordnet. **Keine leere Zelle** für eine geforderte
Abdeckung.

### 7.1 Achsen-Abdeckung

| Achse | Ausprägung | Szenarien |
|---|---|---|
| **A1** Vorrunde | `group_phase` | 1, 3, 4, 6, 7 |
| | `schoch` | 2, 5, 8 |
| **A2** KO | `single_out` | 1, 2, 7 |
| | `double_out` | 5, 6 |
| | `consolation` (Hauptbaum) | 3 |
| | `consolation` (Trost) | 4, 8 |
| **A3** Matchup | `seed_high_vs_low` | 1, 3, 5, 6, 8 |
| | `one_vs_two` | 2, 7 |
| **A4** Tiebreak | `classic_kingtoss_removal` | 1–8 |
| | `mighty_finisher_shootout` | (Automatisierung, SPEC §2 — nicht im manuellen Repräsentativ-Satz nötig) |
| **A5** Scoring | `ekc` | 1, 3, 5, 6, 8 |
| | `classic` | 2, 7 |
| **A6** Pool-Strategy | `snake` | 1 |
| | `seeded` | 3, 7 |
| | `random` | 4, 6 |
| | (N/A bei `schoch`) | 2, 5, 8 |

> A4 `mighty_finisher_shootout` ist eine reine Tiebreak-Entscheider-Methode ohne
> eigene UI-Surface; ihre Kombinatorik deckt die Automatisierung (SPEC §2, Zeilen mit
> `mighty_finisher_shootout`). Der manuelle Repräsentativ-Satz fixiert A4 auf
> `classic_kingtoss_removal`, um die UI-Surfaces nicht zu verwässern.

### 7.2 Feature-Aktions-Abdeckung (8 Aktionen)

| # | Aktion | Surface | Szenarien |
|---|---|---|---|
| a | **Registrierung/Anmeldung** (Emulator B) | `tournament_registration_screen` / `register_team_screen` | 1–8 (jeweils Schritt 2) |
| b | **Score-Eingabe via `+/-`-Stepper** (Emulator B) | `tournament_match_detail_screen` + `tournament_set_input` | 1–8 (jeweils Schritt 2) |
| c | **Forfait** (Emulator A) | `tournament_forfeit_sheet` | 3, 8 |
| d | **Bye prüfen (Freilos)** | Match-Listen | 1, 4, 6 |
| e | **Override** (Emulator A) | `tournament_override_screen` | 5, 7 |
| f | **Pause** (Emulator A) | `schedule_control_bar` | 1 |
| g | **Skip** (forward irreversibel / back) | `schedule_control_bar` | 2 (forward, Hold), 6 (back) |
| h | **Check-in** (Emulator A) | `tournament_detail_screen` → `ParticipantCheckinToggle` | 7 |

### 7.3 UI-Surface-Abdeckung (6 Brief-Surfaces)

| Surface | Szenarien |
|---|---|
| Registrierung | 1–8 |
| Score-Eingabe | 1–8 |
| Dashboard Start/Pause/Skip | 1 (Pause), 2 (Skip fwd), 6 (Skip back), alle (Start) |
| Check-in | 7 |
| Notifications/Inbox | 1, 2, 8 (explizit), alle (Go-Live/Round-Publish) |
| Turnierdetails | 7 (explizit `tournament_stammdaten_card`), alle |

---

## 8. Interne Konsistenz & Referenzen

- **Szenario-Nummerierung 1–8**, lückenlos und duplikatfrei.
- Jedes Szenario trägt eine **SPEC-Zeilen-ID** (`G01`, `S06`, `G50`, `G51`, `S09`,
  `G27`, `G17`, `S17`) aus SPEC §2; alle genannten IDs existieren dort und passen je
  zum Achsen-Tupel des Szenarios (Sz2 = `classic` → S06; Sz3 = `seeded` → G50, Sz4 =
  `random` → G51).
- **Config-Werte** ausschließlich aus SPEC §1 (`snake_case`); `qualifier_count`
  konsistent zur N-Ableitung (32→16, 48/60→32); Pool-Strategy nur in `group_phase`-
  Szenarien; `consolation` immer mit `consolation_name`.
- **ko_type ↔ bracket_type** konsistent: `single_out`/`consolation` →
  `single_elimination`, `double_out` → `double_elimination` (keine Widersprüche).
- **Sprache:** deutsche User-Drehbuch-Sprache, englische Code-/RPC-/Wire-Identifier
  (Repo-Konvention).
- **RPC-/Trigger-Namen** real (Abgleich SPEC §0.1 / `supabase/migrations`):
  `tournament_create`, `tournament_start*`, `tournament_pair_round`,
  `tournament_propose_set_scores`, `tournament_match_forfeit`,
  `tournament_organizer_override_pairing`, `tournament_schedule_tick`,
  `advance_ko_winner`.
- **IS vs WISH:** keine Teilnehmerzahl 1000 als Ziel; alle N ∈ {32,48,60} (≤ 64);
  "Spiel um Platz 3" fix an; jedes Turnier mit KO; "Kein Verein (persönlich)" so
  benannt; Diggy-Default aus; keine erzwungenen Required-Wünsche (Verweis SPEC §0.2).
