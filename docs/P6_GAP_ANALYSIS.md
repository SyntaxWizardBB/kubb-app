# P6 Setup-Wizard — Gap-Analyse

> Audit-Stand: 2026-06-01. Konsolidiert aus dem P6-Setup-Audit über fünf Bereiche:
> `screen1_stammdaten`, `screen2_vorrunde_pitches`, `screen3_bracket_ko`,
> `data_model_persistence`, `rules_conformance` — plus dem Lifecycle-Audit (Phase 4–6).
> Referenz für die verbindlichen Entscheidungen: `P6_RULES_DECISIONS.md` (§A–§I).

---

## 1. Executive Summary

### Gesamtbild Setup-Wizard

Der **3-Screen-Setup-Wizard ist im Kern weit fortgeschritten**, aber an genau den
Stellen, die P6 zur Hauptsache macht (Gruppenphase/Schoch als Vorrunde, KO-Ausführung,
Persistenz der Phasen-Konfiguration), gibt es harte Lücken.

Auszählung der auditierten Items (66 gesamt über die fünf Setup-/Rules-Bereiche):

| Status | Anzahl | Anteil |
| --- | --- | --- |
| `done` | 39 | ~59 % |
| `partial` | 16 | ~24 % |
| `missing` | 8 | ~12 % |
| `incorrect` | 3 | ~5 % |

**Grobe Reife-Einschätzung:** Stammdaten (Screen 1) sind nahezu vollständig
(~90 % funktional). Screen 2 (Vorrunde/Pitches) und Screen 3 (KO/Bracket) sind als
**UI-Hüllen** vorhanden, aber die zentralen Modi sind entweder gesperrt
(Gruppenphase/Schoch nicht wählbar), reine Persistenz-Flags ohne Ausführungslogik
(Double-KO, `one_vs_two`, Mighty-Finisher, Consolation) oder werden beim Speichern
verworfen (Pool- und KO-Phasen-Config). **Effektiv konfigurier- UND ausführbar ist
heute nur ein Single-Stage Round-Robin/Swiss-Turnier.**

### Die grössten Lücken (Blocker)

1. **Vorrunden-Typ Gruppenphase/Schoch ist im Wizard nicht wählbar** — nur
   `roundRobin` und `swiss` sind `enabled`; `schoch`, `*_then_ko` sind als „Folgt in M2+"
   gesperrt. Damit ist die P6-Kernfrage „Gruppenphase oder Schoch?" praktisch nicht
   beantwortbar.
2. **Group→Pitch-Zuteilung fehlt komplett** in der UI (Domain-Feld
   `PitchPlan.groupAssignment` existiert, wird aber nie gesetzt).
3. **Pool- und KO-Phasen-Konfiguration werden beim Anlegen verworfen** —
   `poolPhaseConfig` und `koConfig` werden im Wizard erfasst, aber von `toSetupConfig()`
   nie serialisiert und haben keine DB-Spalte. Die Gruppenanzahl, Durchgänge und die
   gesamte KO-Tiefe gehen beim Create-RPC verloren.
4. **Double-Elimination ist nur ein Setup-Flag** — es gibt keine WB/LB/Grand-Final-
   Struktur in `bracket.dart` und keine Server-Phasen `wb/lb/grand_final`. Die Auswahl
   „Doppel-KO" erzeugt einen identischen Single-Elim-Lauf.

### Wiederkehrendes Strukturmuster

Mehrere `partial`-Items teilen denselben Fehlertyp: **UI + Domain-Primitive existieren,
aber sind nie verdrahtet** — `KoMatchup.one_vs_two` setzt nie
`BracketSeedingPattern.linear`; `PitchSortStrategy.manual` ändert nie `PitchPlan.order`.
Diese Punkte sind günstig zu schliessen (eine Verdrahtungs-Stelle), liefern aber heute
„stille No-Ops".

### Regelkonformität (Rules)

Drei `incorrect`-Befunde betreffen verbindliche Entscheidungen: die **Schoch-Runden-
Default-Formel** (§G: `clamp(ceil(log2(n))+3,5,9)`, Default 8 — implementiert ist
`clamp(ceil(log2(n)),3,9)`, also systematisch zu wenig Runden), die **Prelim-Tiebreaker-
Kette** (§H endet auf `mighty_finisher_shootout`, das es im Enum gar nicht gibt — 4.
Kriterium ist fälschlich `wins`) und die **`time_limit:0 = ohne Limit`**-Option (§A
erlaubt, Code verbietet `< 60s`).

---

## 2. Offene Punkte (sortiert nach Severity)

> Alle Items mit Status `missing` / `incorrect` / `partial`. Blocker zuerst.

### Blocker

| Bereich | Item | Status | Detail (Kurz) | Vorgeschlagener Task |
| --- | --- | --- | --- | --- |
| screen2 | Vorrunde-Typ Gruppenphase vs Schoch wählbar | missing | Nur `roundRobin`/`swiss` `enabled`; `schoch`/`*_then_ko` gesperrt (wizard:1316-1317). Kernfrage P6 nicht beantwortbar. | `schoch` und `roundRobinThenKo`/`schochThenKo` in `_StepFormat` freischalten; Labels „Gruppenphase"/„Schoch" statt „Round Robin"/„Schweizer System". |
| screen2 | Schoch/Gruppen-Formate tatsächlich wählbar | missing | Dieselbe Gate-Logik sperrt alle Hybrid-Formate; Domain+Pairing (`swiss_system.dart`) vorhanden. | Gemeinsam mit obigem Task die Gate-Liste entfernen und End-to-End testen. |
| screen2 | Group→Pitch-Zuteilung | missing | `PitchPlan.groupAssignment` existiert, wird von `_PitchPlanSection` nie gesetzt (Kommentar „later slice"). | UI für Pitch-pro-Gruppe-Zuteilung bauen; `_currentPlan()` erweitern, `groupAssignment` füllen. |
| screen3 | Double-Elim vollständig gebaut (WB+LB+GF) | missing | Nur `SingleEliminationBracket` in `bracket.dart`; keine `wb/lb/grand_final`-Phasen serverseitig; RPC schreibt nur den String. | `DoubleEliminationBracket` (WB/LB/GF + Bracket-Reset) implementieren + Server-Advance-Trigger für neue Phasen; sonst Auswahl deaktivieren. |
| data_model | Pool-Phase-Config persistieren | missing | `poolPhaseConfig` (groupCount, qualifiersPerGroup, Durchgänge) wird nie serialisiert, keine Spalte. Inputs werden verworfen. | `toSetupConfig()` um `pool_phase` erweitern, DB-Spalte + RPC-Insert ergänzen. |
| data_model | KO-Phase-Config (`koConfig`) persistieren | missing | `koConfig` + `bracketSeedingMode` werden erfasst, aber nie emittiert; keine Spalte. KO-Tiefe geht verloren. | `ko_config` JSONB serialisieren/persistieren; Round-Trip-Test. |
| lifecycle | `tournament_start` unterstützt konfiguriertes Format | incorrect | `tournament_start` lehnt alles ausser `round_robin` ab (`0A000`), obwohl Create Schoch/Pool/`*_then_ko` akzeptiert. „Go live" wirft für P6-Formate. | Start-RPC auf Schoch/Pool/Single-Elim erweitern bzw. Detail-Screen-„Go live" je Format auf die passende Bootstrap-RPC routen. |
| lifecycle | Phase 6 (Live-Start gesamt) | missing | `round_robin`-only, `pitch_number=1` hardcodiert, generische RR-Byes, kein Push/Timer/Vibration, kein Round-Gate. | Eigenes Phase-6-Arbeitspaket (siehe Abschnitt 3). |

### High

| Bereich | Item | Status | Detail (Kurz) | Vorgeschlagener Task |
| --- | --- | --- | --- | --- |
| screen1 | On-site Check-in-Deadline (`checkinUntil`) | missing | `draft.checkinUntil` existiert end-to-end, aber kein `_DateField` und kein `setCheckinUntil`. Feld bleibt immer `null`. RuleSets fordern Speakerpult-Cutoff. | `_DateField` in `_StepStammdaten` + `setCheckinUntil` im Controller ergänzen. |
| screen2 | Pitches manuell sortieren | partial | Sort-Chip „Manuell" vorhanden, aber keine UI zum Anordnen; `_currentPlan()` setzt `order` nie. | Drag-Reorder-UI ergänzen, `PitchPlan.order` füllen. |
| screen2 | Anzahl Gruppen (bei Gruppenphase) | partial | `groupCount` nur im separaten `WizardPoolConfigStep`, gebunden an gesperrte Hybrid-Formate → unerreichbar. | Mit Format-Freischaltung koppeln; Pool-Step nach Gruppenphase-Wahl erreichbar machen. |
| screen2 | Schoch: Anzahl Durchgänge | partial | `SwissConfigSection`-Slider nur bei `swiss` sichtbar, nicht bei `schoch`. Default falsch (§G, siehe Rules). | Section auch für `schoch` einblenden; Default-Formel korrigieren (siehe §G). |
| screen3 | Double-Elim sperrt Spiel-um-Platz-3 (§D) | missing | Bronze-Switch reagiert nicht auf `bracketType`; `with_bracket_reset` gar nicht exponiert. | Bei `doubleElimination` Bronze auf `false`+locked; `with_bracket_reset` (Default true) als Control ergänzen. |
| screen3 | Matchup `one_vs_two` (§C) | partial | UI+Enum da, aber nie mit `BracketSeedingPattern` verdrahtet → `one_vs_two` ohne Wirkung. | `KoMatchup` → `BracketSeedingPattern` mappen und beim Bracket-Build übergeben. |
| data_model | Consolation Wire-Shape vs §E | incorrect | Kein `source`-Enum, kein `rank_from/rank_to`; `prelim_rank_band` nicht darstellbar. | Modell um `source`+Band-Felder erweitern; CHECK auf `consolation_bracket`. |
| data_model | Mighty-Finisher-Quali Wire-Key/`pool` | incorrect | `source='group_runner_ups'` statt §F `pool='group_runners_up'`; `rank_band` fehlt. | Feld in `pool` umbenennen, Enum `{group_runners_up, rank_band}`, Wire-Token korrigieren. |
| rules | §G Schoch-Parameter (Default 8, Bo2, ekc) | incorrect | Default `clamp(ceil(log2(n)),3,9)` statt `+3,5,9`; Bo2/ekc nicht erzwungen. | `defaultRounds`-Formel fixen; bei Schoch Bo2 + `scoring=ekc` locken. |
| rules | §H Prelim-Tiebreaker-Kette | incorrect | 4. Kriterium `wins` statt `mighty_finisher_shootout`; Enum kennt Shootout nicht. | `mightyFinisherShootout` zu `TiebreakerCriterion` hinzufügen; Default-Kette + Presets anpassen. |
| rules | §A Per-Round KO-Ruleset | partial | Nur ein `MatchFormatSpec` für ganzes KO; keine Pro-Runde-Profile. | Per-Round-Modell (`KoRoundRuleset`) einführen + Quick-Picks. |
| rules | §B Mighty-Finisher als KO-Decider angeboten | partial | UI bietet `mightyFinisherShootout` als Match-Tiebreak — §B verbietet das. | Shootout-Option im KO-Match-Tiebreak entfernen/sperren (nur `classic`). |
| rules | §I Auto-Seeding-Quelle (ELO) | missing | Kein `seed_source`/`team_rating_mode`/`elo_default`. §I config-seitig unimplementiert. | `seed_source {elo,manual,random}` + Team-Aggregation + `elo_default 1200` modellieren. |
| lifecycle | Per-Tile Anmelden/Abmelden-Button | partial | `TournamentCard` hat nur ein Tap-Target (Detail); Register/Withdraw nur im Detail. | Zweiten Button (anmelden/abmelden) auf der Kachel ergänzen. |
| lifecycle | Team-Anmeldung benachrichtigt Mitglieder | missing | `tournament_register_team` enqueued keine Inbox/Notif für Roster. | Inbox-Enqueue je Roster-Mitglied im Team-Register-RPC. |
| lifecycle | Phase-5 Pre-Start-Ranking + ELO-Seeding | incorrect / missing | Seeding-Screen ist KO-Bracket-Seeding aus Standings, kein Pre-Start-Ranking; `seed` = Registrierungsreihenfolge. | Eigener Pre-Start-Ranking-Step + ELO-Seeding (§I). |
| lifecycle | Start: Pitch-Zuteilung in Range | incorrect | `tournament_start` hardcodiert `pitch_number=1`. | Pitch-Range/Group-Assignment im Start-RPC anwenden, High-Seed→Low-Pitch. |
| lifecycle | BYE-Fill an schlechtest-gerankte Spieler | incorrect | Nur generische RR-Byes, kein seed-aware KO-BYE-Fill (`next_pow2`). | Seed-basierte BYE-Verteilung im Start-RPC (Domain `bracket.dart` verdrahten). |
| lifecycle | Per-Device Match-Timer | missing | Kein Timer; `time_limit` nur statischer Text. | `started_at`-basierten Countdown auf dem Spielergerät bauen. |
| lifecycle | Go-Live Push an Teilnehmer | missing | Keine Push-Infra (kein `firebase_messaging`). | Push/Inbox-Infra + Go-Live-Trigger in `tournament_start`. |
| lifecycle | Vibration bei Zeitablauf | missing | Kein Haptics-Plugin, Timer fehlt ohnehin. | `HapticFeedback` bei Timer-Ende (nach Timer-Bau). |
| lifecycle | KO-Tiebreak/Mighty-Finisher Rückmeldung | missing | Kein Channel für Tiebreak-/Shootout-Ergebnis an Organizer. | Report-Back-Flow + Runtime-Repräsentation (§B/§F). |
| lifecycle | Gated Round-Progression | missing | RR materialisiert alle Runden vorab; Swiss-Pairing prüft Vorrunde nicht. | „Alle Ergebnisse drin → nächste Runde"-Gate je Format. |
| lifecycle | Phase 4 (Registrierung + Notif + Team-Waitlist) | partial | Tile-Button, Member-Notif, Team-Waitlist-Routing fehlen. | Siehe einzelne High-Items oben. |

### Medium

| Bereich | Item | Status | Detail (Kurz) | Vorgeschlagener Task |
| --- | --- | --- | --- | --- |
| screen1 | 2-4-6 Anspielregel als Variant-Toggle | missing | `RuleVariants.openingRule` existiert, aber kein UI-Control / `setOpeningRule`. Meistzitierte Regel. | Control in `_StepStammdaten` + `setOpeningRule`. |
| screen1 | Warteliste bei ausgebucht (Setup) | missing | Kein Waitlist-Flag im Draft/`_StepStammdaten`. | Kapazitäts-/Waitlist-Toggle im Setup (oder als Runtime-Feature dokumentieren). |
| screen2 | Tiebreak-Regeln (Methode) für Vorrunde | missing | Nur on/off + Zeit; keine Methodenwahl für Prelim. | Prelim-Tiebreak-Methode-Auswahl ergänzen. |
| screen2 | Max. Teilnehmerzahl Cap 64 | partial | Hard-Cap 64, Mails gehen bis 128 (Bâton d'Or). | `participantsHardMax` auf 128 erhöhen/konfigurierbar. |
| screen2 | Schoch: max 8 Punkte/Satz | missing | Keine Anzeige/Einstellung; `basekubbsPerSide` ohne UI. | Hinweistext + ggf. `basekubbsPerSide`-Control im Schoch-Kontext. |
| screen3 | Single vs Double KO Selector | partial | Auswahl end-to-end gebaut, aber Double-Verhalten fehlt (siehe Blocker). | Mit Double-Elim-Implementierung schliessen. |
| screen3 | KO-Tiebreak on/off + Zeit (§A) | partial | Nur `setsToWin`/Zeit/`finalNoTiebreak`; kein expliziter TB-Toggle/`tiebreakAfter`-Editor. | TB-on/off + `tiebreakAfterSeconds`-Editor exponieren. |
| screen3 | Mighty-Finisher-Quali (§F) | partial | `pool` als Freitext, kein `rank_band`, keine `slots<pool_size`-Validierung. | Enum + Validierung (siehe data_model-Item). |
| screen3 | Consolation Bracket (§E) | partial | Kein `source`-Enum, `sourceRounds` nicht editierbar, keine Generierung. | Modell+UI erweitern; Generierung serverseitig. |
| data_model | Prelim-Tiebreak/Break-Spalten | partial | Im JSONB-Blob, keine DB-CHECK (`tiebreak_after < round_time`). | DB-CHECK oder RPC-Validierung ergänzen. |
| data_model | Fun/Spass-Turnier-Flag | missing | Kein `is_fun`/`excluded_from_ranking` (P7/P8). | Spalte + Draft-Feld (P7/P8-Scope). |
| rules | §A `finish_current_set_then_decider` | missing | Flag (immer true im KO) nicht im Modell. | Feld in `MatchFormatSpec` + Wire ergänzen. |
| rules | §A `time_limit:0 = ohne Limit` | incorrect | `issues()` lehnt `< 60s` ab; Wasserschloss-Unlimited unmöglich. | `0` als „kein Limit" erlauben; Stepper-Clamp anpassen. |
| rules | §F Mighty-Finisher faithful repr. | partial | Shootout-Mechanik (8m-Sudden-Death) nicht im Value-Object; Wire-Token-Mismatch. | Mechanik-Felder + Token korrigieren. |
| rules | §E Consolation-Default-Ruleset | partial | `matchFormat` default null → erbt KO-Format statt §E Bo3/30; `prelim_rank_band` fehlt. | §E-Default vorbefüllen + zweite Source-Variante. |
| lifecycle | Single-Waitlist vs Team-Waitlist | partial | Capacity/Waitlist nur für Single-Registrierung. | Capacity-Check in `tournament_register_team`. |

### Low

| Bereich | Item | Status | Detail (Kurz) | Vorgeschlagener Task |
| --- | --- | --- | --- | --- |
| screen1 | Entry fee currency hardcoded `CHF` | partial | Kein Currency-Selector/`setCurrency`. Für CH-RuleSets ok. | Optional: Currency-Selector (niedrige Prio). |
| screen2 | Pitch-Sortierung relativ zu Seeding | done* | Funktional, aber nur als Flag (keine sichtbare Vorschau). | Optional: Vorschau der Pitch-Reihenfolge. |
| screen2 | Pitch-Plan Pflicht/Optional konsistent | partial | Screen 2 auch ohne Pitches valide; Range-Pflicht nicht erzwungen. | Range-Pflicht pro Parallel-Turnier erzwingen (optional). |
| screen3 | KO-Stage-Picker (64tel/…/4tel) | partial | Freie Qualifier-Count statt diskreter Stage-Namen. Superset, aber L105 streng nur teilweise. | Optional: Stage-Namen anzeigen. |
| screen3 | Seeding-Mode auto/manual | partial | Funktioniert; hardcodierte deutsche Strings (i18n-Inkonsistenz). | Strings nach l10n auslagern. |
| data_model | `pitch_plan` Round-Trip/CHECK | partial | Round-Trips ok; kein DB-CHECK auf `mode`/`sort_strategy`. | CHECK oder RPC-Validierung. |
| rules | §A `max_sets` Optionen {1,2,3,5} | partial | Stepper nur ungerade `max_sets`; Bo2 (`max_sets:2`) im KO nicht erreichbar. | Quick-Picks; `max_sets:2` erlauben. |

\* als „done" auditiert, hier zur Vollständigkeit der Partial-Nuancen gelistet.

---

## 3. Lifecycle (Phase 4–6) — noch nicht gebaut

> Dieser Abschnitt ist bewusst getrennt: Es ist **grössere Downstream-Arbeit jenseits
> des Setup-Wizards**. Der Wizard kann ein Turnier konfigurieren — aber der Betrieb
> (Registrierung mit Benachrichtigung, Pre-Start-Ranking, Live-Start) ist nur teilweise
> bzw. gar nicht vorhanden.

### Phase 4 — Registrierung (teilweise gebaut)

Vorhanden: Discovery, Single- + Team-Registrierung, Single-Waitlist, Organizer
Approve/Reject, Withdraw. **Fehlt:**

- Per-Tile **Anmelden/Abmelden-Button** (heute nur Navigation zum Detail).
- **Member-Benachrichtigung** bei Team-Anmeldung (kein Inbox-Enqueue im
  `tournament_register_team`).
- **Team-Waitlist-Routing** (Capacity-Check existiert nur für Single-Registrierung).

### Phase 5 — Pre-Start-Ranking + ELO-Seeding (nicht gebaut)

- Es gibt **keinen** Organizer-Ranking-Schritt zwischen Anmeldeschluss und Start.
- Der vorhandene Seeding-Screen ist **KO-Bracket-Seeding aus Prelim-Standings**, nicht
  das Pre-Start-Ranking.
- **ELO-basiertes Auto-Seeding (§I) ist komplett unimplementiert**: `seed` ist reine
  Registrierungsreihenfolge; kein `seed_source`, `team_rating_mode`, `elo_default 1200`,
  keine ELO-Summen-Aggregation für Teams.

### Phase 6 — Live-Start (Blocker, am wenigsten reif)

- `tournament_start` **funktioniert nur für `round_robin`** und lehnt Schoch/Pool/
  `*_then_ko` mit `0A000 „format not yet supported"` ab → blockiert genau die P6-Formate.
- **Pitch-Zuteilung hardcodiert `pitch_number=1`** für jedes Match; keine Range-/
  Group-Assignment, kein High-Seed→Low-Pitch.
- **BYE-Fill** ist generischer RR-Bye, nicht seed-aware (kein `next_pow2`, BYEs gehen
  nicht an schlechtest-gerankte Spieler).
- **Kein Go-Live-Push/Inbox** an Teilnehmer (keine `firebase_messaging`/
  `flutter_local_notifications` in `pubspec.yaml`).
- **Kein Per-Device Match-Timer** (`started_at`-basierter Countdown fehlt vollständig).
- **Keine Vibration** bei Zeitablauf (kein Haptics-Plugin; Timer fehlt ohnehin).
- **Kein KO-Tiebreak/Mighty-Finisher Report-Back-Channel** an den Organizer.
- **Kein gated Round-Progression** („alle Ergebnisse drin → nächste Runde"): RR
  materialisiert alle Runden vorab, Swiss-Pairing prüft Vorrunden-Vollständigkeit nicht.

**Empfohlene Reihenfolge:** Erst `tournament_start` für die P6-Formate öffnen +
Pool-/KO-Config persistieren (sonst hat der Start nichts zu lesen), dann Pitch-/BYE-/
Seeding-Logik, danach Push/Timer/Vibration und gated Progression.
