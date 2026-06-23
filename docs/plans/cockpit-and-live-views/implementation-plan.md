# Implementierungsplan — Cockpit, Live-Views, Match-Entry, Realtime-Frische & Typ-Graph-Editor

**Status:** Entwurf zur Umsetzung (Owner-Entscheide abgenommen).
**Bezug:** die vier Forward-Specs unter `docs/specs/` (cockpit, live-views, match-entry, realtime-sync) + ADR-0029, sowie die abgeschlossene Tournament-Engine (Schoch/Buchholz, Vorrunde-Ranking, Stage-Seeding, Stage-Graph Ebene-2).
**Grundlage:** Spec-gegen-Code-Gap-Analyse (8 Specs). Drei Basis-Specs sind byte-identisch implementiert und entfallen; vier Forward-Specs werden gebaut, eine Engine-Lücke (Typ-Graph-Editor) wird verdrahtet.

---

## 1. Abgenommene Owner-Entscheide

1. **Direkter Punkte-Eintrag (Cockpit §8):** der `tournament_organizer_override`-RPC wird von *creator-only* auf `tournament_caller_can_manage` umgestellt (Creator ODER Club-Owner/Admin/Organizer) — spec-konform und konsistent mit dem Dashboard-Gate (`canAdministerTournamentProvider`). Additive Migration, Security-Review Pflicht.
2. **Typ-Graph-Editor (Stage-Graph §3):** der Ebene-2-Editor wird produktiv verdrahtet (Form/Canvas-Toggle + Route/Wizard-Step), sodass ein Owner `config['type_graph']` über die App schreiben kann. Engine/Validierung/Templates sind bereits fertig und getestet.
3. **Pitch-Nummer:** ein echtes `pitch_number`-Feld (Migration + RPC-Projektion + Wire-Feld) bedient beide Flächen (Cockpit-Match-Kachel + Match-Entry-Header) aus dem `PitchPlan`. Fundament-Task, entsperrt zwei Features.

---

## 2. SKIP — byte-identisch implementiert, kein Scope

| Spec | Begründung |
|---|---|
| `schoch-swiss-pairing-buchholz-spec.md` | Bit-gleich auf main und Doc-Branch. Alle 7 Quality-Gates §7.1–7.5 als Dart-Domain + 222-Assert-SQL-Parität. |
| `vorrunde-ranking-spec.md` | Bit-gleich. Per-Typ-Chain (Gruppe ohne Buchholz, Schoch mit), Shoot-out nur am Cut. |
| `stage-seeding-spec.md` | Bit-gleich. Reproduzierbares LCG-Seeding (plpgsql-Zwilling + Parität), Snake-only, Resolver in Boot+Runner. |

Diese drei Doc-Branch-Versionen sind identisch zu den main-Versionen — keine Drift, nichts zu tun.

---

## 3. Vorbedingung — Forward-Specs auf main holen (Wave 0)

Die vier Forward-Spec-Dokumente + der push-freshness-ADR liegen heute **nur** auf `origin/docs/schoch-buchholz-spec`, nicht auf main:

- `docs/specs/organizer-cockpit-dashboard-spec.md`
- `docs/specs/live-views-and-inbox-spec.md`
- `docs/specs/match-entry-and-home-tile-spec.md`
- `docs/specs/realtime-sync-fixes-spec.md`
- `docs/adr/0035-push-critical-freshness-and-delta-catchup.md`

**ADR-Nummern-Kollision:** main hat bereits `0035-vorrunde-ranking-from-stage-type.md`. Der einkommende push-freshness-ADR wird beim Import auf die nächste freie Nummer **0041** umnummeriert; alle Cross-Referenzen (v.a. in `realtime-sync-fixes-spec.md`) werden mitgezogen. `realtime-sync-fixes` amendiert ADR-0029 (auf main vorhanden) — konsistent.

---

## 4. Wellen-Plan

Reihenfolge nach Hebel: erst die billige Realtime-Korrektheit (fundamentiert die Live-Views), dann Daten-Fundament + Quick-Wins, dann die config-adaptiven Views, dann der grosse Cockpit-Block, parallel der Editor.

### Wave 0 — Spec-Import + Fundament
- **W0-1** Forward-Specs + push-freshness-ADR (→ **0041**, Cross-Refs gefixt) auf main importieren. *(docs, S)*
- **W0-2** `pitch_number`-Fundament: Migration auf `tournament_matches` + Projektion in `tournament_match_get/list` + `TournamentMatchRef`-Wire-Feld, gespeist aus dem `PitchPlan`. Entsperrt W2 + W4-Pitch. *(data, M)*
- **W0-3** Override-RPC-Gate: `tournament_organizer_override` von creator-only auf `tournament_caller_can_manage` (additive Migration + pgTAP: Club-Organizer darf, Fremder 42501). *(data/security, S)*

### Wave 1 — Realtime-Korrektheit (`realtime-sync-fixes` + ADR-0041)
Billig, hoher spürbarer Effekt, Fundament für Live-Views. Reihenfolge der Spec folgend:
- **W1-1** Robustheits-Guards (§4): disposed-Guard vor `changeController.add`, isClosed-Guard im Fallback-emit, Backoff-Reset bei manuellem Close, refCount-Cleanup im Fehlerpfad. *(S)*
- **W1-2** Standings-Realtime-Invalidator (§1.1): Provider analog `tournamentMatchListRealtimeProvider`, Watch auf Live-/Standings-Screen. Grösster Effekt, Muster existiert 5×. *(S)*
- **W1-3** Catch-up-Refetch (§1.2): Invalidate-Hook bei Rejoin (`pushState joined`) + App-Resume; v1 = Voll-Refetch. *(M)*
- **W1-4** Participants/Check-in-Fallback-Poller (§3.1) gegated auf `realtimeFallbackProvider`. *(S)*
- **W1-5** Offline-/Stale-Banner (§3.2) auf Live- + Standings-Screen. *(S)*
- **W1-6** Kritikalitäts-Tier + engere Fallback-Kadenz (§2) — laut Spec zuletzt. *(S)*

### Wave 2 — Match-Entry Quick-Wins (`match-entry-and-home-tile`)
- **W2-1** Satzanzahl aus `matchFormatConfig` (`max_sets`/`sets_to_win`) statt fix 3 — `_maxSetsFor`-Helper, 3 Callsites. Höchster Korrektheitsgewinn. *(S)*
- **W2-2** Back-Button canPop-Fallback (+ optional origin-Param für Deep-Links). *(S)*
- **W2-3** Match-Clock in die Kachel ziehen + Pre-Start-Gate lockern; Pitch-Header aus W0-2. *(S)*
- **W2-4** Grüne Home-Kachel: `PitchCallBanner` cross-tournament-tauglich, in `home_screen`; `_OngoingMatchCard`/Platzhalter entfernen. *(M)*

### Wave 3 — Live-Views config-adaptiv (`live-views-and-inbox`)
Baut auf W1 (Realtime) + W2 (Daten).
- **W3-1** Tiebreak-Kette aus `tiebreakerOrder` in `tournamentStandingsProvider` durchreichen (String→`TiebreakerCriterion`) statt hart codiert. *(M)*
- **W3-2** `qualifiersPerGroup` aus Config statt Default 2 + formatabhängige Header-Bezeichnung. *(S)*
- **W3-3** Gruppen-Label auf `TournamentMatchRef` ergänzen (kleiner Wire-/RPC-Zusatz) + Match-Liste rendern. *(S)*
- **W3-4** Live-Screen config-adaptiv: Format/Phase aus `tournamentDetailProvider`; Rangliste-Reiter flach↔gruppiert; Übersicht bei aktiver KO-Phase Bracket statt Rundenliste. *(M)*
- **W3-5** `InboxBell` auf Live-Sicht + ~4 Nicht-Eingabe-Screens. *(S)*

### Wave 4 — Cockpit-Steuerung (`organizer-cockpit-dashboard`, grösster Block)
- **W4-1** Timer-Statusanzeige (Runde N / Pause + Restzeit) in `ScheduleControlBar` — State wird bereits gelesen, nur Darstellung. *(S)*
- **W4-2** Pitch-Nummer auf der Dashboard-Match-Kachel (`_MatchRow`), aus W0-2. *(S)*
- **W4-3** Direkter Punkte-Eintrag: „Punkte eintragen"-Einstieg auf jeder Kachel + begründungsfreier Submit-Pfad (`reason` optional) im `TournamentOverrideController`; nutzt das W0-3-Gate. *(M)*
- **W4-4** Timer extend/shorten: additiver Schreibweg-RPC auf die laufende Runde + skew-konforme Push-Anzeige + UI mit +/− und Direkteingabe. Echtes net-new. *(L)*
- **W4-5** Cross-Turnier-Check-in: Such-RPC (Scope = eigene + publizierte + Check-in-Phase), Such-Screen, Einstieg aus der Cockpit-Übersicht. *(L)*
- **W4-6** Detail-Screen-Entkernung: zuerst die noch fehlenden Funktionen (Check-in-Liste, Lifecycle-Aktionen, Teilnehmer-Moderation) vollständig ins Cockpit-Detail migrieren, **dann** alle `canManage`-Blöcke aus `tournament_detail_screen` entfernen + „→ Dashboard"-Button. **Muss zuletzt**, sonst Funktionslücken. *(L)*

### Wave 5 — Typ-Graph-Editor verdrahten (`stage-graph`, parallelisierbar)
- **W5-1** `StageTypeGraphBuilderBody` um Form/Canvas-Toggle + `isCanvasAvailable`-Gating (wie Ebene-1 `StageGraphBuilderBody`); Editor über Route/Wizard-Step erreichbar, sodass `config['type_graph']` produktiv geschrieben wird. *(M)*

---

## 5. Aufwand (grob)

~6–9 Personentage netto: 3× L (Timer extend, Cross-Check-in, Detail-Entkernung) + ~4× M + viele S. Wave 1 + 2 sind die schnellsten Hebel; Wave 4 trägt den grössten Anteil.

---

## 6. Risiken

- **Detail-Entkernung (W4-6)** darf erst laufen, wenn alle Veranstalter-Funktionen vollständig im Cockpit angekommen sind — sonst Funktionslücken für Organizer. Harte Reihenfolge-Abhängigkeit.
- **Override-Gate (W0-3)** ist ein RLS/Security-Touch — Security-Review + pgTAP (Club-Organizer darf, Fremder/Spieler nicht), EKC-Schreibweg byte-identisch.
- **Realtime-Catch-up (W1-3)** v1 = Voll-Refetch; bei Skalierung später delta-catchup (ADR-0041) nachziehen — bewusst v1-pragmatisch.
- **Pitch-Fundament (W0-2)** ist additiv; bestehende Pitch-Stand-in-Nutzung (`PitchCallBanner`) auf das echte Feld umstellen ohne Regression.
- Jede Migration additiv/abwärtskompatibel; voller pgTAP-Harness muss `PASS` bleiben (Stand: 70 Files / 2396 Tests).

---

## 7. Nicht in diesem Plan

- **Prod-Deploy** der bestehenden ~24 Migrationen (Owner, backup-first `db push --db-url`).
- **Mängel #6** (Keypair-/Publication-Grants) — deferred bis Owner-Prod-Check.
- Per-Wave atomare Senior-Task-Zerlegung (≤100 LOC/3 Dateien) erfolgt jeweils zu Wave-Beginn nach diesem Wellen-Schnitt.
