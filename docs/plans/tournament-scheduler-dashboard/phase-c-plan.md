# Phase C — Notifications bei Schedule-Events

**Bezug:** ADR-0031, README.md (K2 Notify-Helper-Body in `…242`, K3 RPC-Bodies, K8 E-Naht).
**Migrationsband ab `20261260000000`.** Durable Kern (E1/E5/E6/E9) ist **ohne Phase A/E lauffähig**;
getaktete Events (E2/E4/E7/E8) werden in C vorbereitet und vom **E-Tick** gefeuert.

## Gefundene Gaps (Code-verifiziert)
1. `_tournament_notify_participants` ist **Broadcast an alle** — kein per-Empfänger-Pitch → neue
   per-recipient-Fan-out-Funktion nötig.
2. `tournament_generate_stage_matches` (Stage-Runner) **notifiziert heute nicht** → Stage-Graph-Runden
   stumm; Hook ergänzen.
3. **Kein** Local-Notification-Package im pubspec → In-App-Local-Notifications = NEUE Dependency,
   **out of scope** (Inbox + CDC-Foreground-Wake genügt; echtes Push am Push-Milestone).

## Notify-Matrix
| # | Event | kind (wire) | Trigger-Ort | durable/getaktet | Empfänger |
|---|---|---|---|---|---|
| E1 | Runde N publiziert | `tournament_round` (`action_payload.kind='round_published'`) | A-RPCs + **generate_stage_matches** | durable | per Empfänger (Pitch) |
| E2 | Match „läuft jetzt" (call→running) | `…kind='match_running'` | **E-Tick** | getaktet | per Empfänger |
| E5 | Turnier pausiert | `…kind='paused'` | **B2 `tournament_pause`** | durable | alle (Broadcast) |
| E6 | Resume | `…kind='resumed'` | **B2 `tournament_resume`** | durable | alle |
| E7 | überfällig (ends_at, Resultat fehlt) | `…kind='awaiting_results'` | **E-Tick** | getaktet | per Empfänger m. offenem Match |
| E8 | Tiebreak-Hold | `…kind='tiebreak_hold'` | **E-Tick** | getaktet | per Empfänger |
| E9 | Turnier finalisiert | `tournament_finished` | **bestehender Trigger** (`…242`) | durable, EXISTIERT | alle |

Privacy: Payload nur `tournament_id, round_number, phase, starts_at, pitch_number, kind` — **keine**
Namen/User-IDs (Gegner client-seitig aus CDC). Push-Seam (`…233`) wird gratis gespeist (no-op heute).

## Bau-Reihenfolge (Server → Client)
> **Re-Base-Pflicht (K2/K3):** Helper + kind-CHECK auf `20261242000000`; Materialisierungs-RPCs auf
> `…032`/`…247` (bzw. A-Version falls A gelandet). Vor C prüfen, ob A gemergt ist.

- **C0** `20261260000000_schedule_notify_helpers.sql`: kind-CHECK re-basen (16 kinds, **keine neuen
  wire-kinds** — alle fahren auf `tournament_round` + `action_payload.kind`, wie Shootout); neuer
  `_tournament_notify_round_per_pitch(...)` (per-Empfänger Match→Pitch, Body „… — Pitch X, Start HH:MM",
  Idempotenz-`NOT EXISTS`-Guard). **Tests:** Helper schreibt 1 Zeile/Empfänger, Pitch korrekt,
  Team-Roster-Auflösung, Idempotenz, kind-CHECK.
- **C1** `20261261000000_round_publish_notify.sql`: per-Pitch-Notify in die 5 Materialisierungs-RPCs
  (inkl. **Gap-Close generate_stage_matches**). `starts_at` aus A's Schedule-Zeile; **Fallback ohne A**:
  Body ohne „Start HH:MM" (Pitch bleibt) → C nicht hart von A abhängig. **Tests:** `golive_inbox_test.sql`-
  Erweiterung (per-Empfänger-Zeile mit Pitch; Stage-Runner notifiziert).
- **C2** `20261262000000_pause_resume_notify.sql`: `_tournament_notify_paused(uuid, p_resumed bool)`
  (Broadcast genügt). **Naht zu B2** (OD-2): wenn B vor C, hier `PERFORM` in die B2-RPCs einsetzen;
  sonst B2 ruft die Funktion. **Tests:** paused/resumed-Zeile pro Empfänger.
- **C3** `20261263000000_timed_notify_functions.sql`: `_tournament_notify_match_running(...)`,
  `_tournament_notify_awaiting(...)` (nur Empfänger mit offenem Match; Tiebreak→`tiebreak_hold`),
  beide idempotent. **KEIN Aufruf hier** — der sitzt im E-Tick (`tournament_schedule_tick`). **Tests:**
  per-Pitch/Idempotenz. (Kein End-to-End-Tick-Test in C.)
- **C4** Client: `inbox_message.dart` `fromWire` disambiguiert `tournament_round` über
  `action_payload.kind` → **ein Sammelkind `tournamentSchedule`** (Label/Icon aus Payload-Tag, OD-1);
  `inbox_screen.dart` `_kindBg`/`_kindLabel`/`_MessageDetail`-CTA „Zum Match" (Pitch/Gegner live aus
  `myActiveMatchProvider`, PII-frei). l10n + `gen-l10n`. **Tests:** `inbox_message_test.dart`,
  `inbox_screen_*_test.dart`.
- **C5 (optional)** PitchCallBanner-Kopplung: `TournamentMatchRef.pitchNumber` aus CDC-Row ergänzen,
  `pitchLabel = pitchNumber ?? matchNumberInRound`. **Nur wenn `pitch_plan`-Turniere im Scope** (OD-3).

## Risiken
Doppel-Notify-cron (Idempotenz-Guard `tournament_id+round_number+kind+user_id`); Fan-out-Last 30–60
Spieler (ein Set-INSERT, keine 60 Calls; E3/E4/E8 als Sub-Events gedeckt; Push-Seam no-op);
Payload-Privacy (Whitelist); Stale-Body (Diff vs `…242`/`…032`/`…247`); `pitch_number`=1 ohne Plan
(„Pitch X" nur wenn >1 / Plan); E-Abhängigkeit (durable Kern ohne E vollständig; getaktet = Komfort);
kind-CHECK-Re-Add strippt keine kinds (alle 16 verbatim).

## Offene Entscheidungen
- **OD-1:** Sammelkind `tournamentSchedule` client-seitig (Empf.; DB-CHECK stabil).
- **OD-2:** Pause-Notify-Naht — C liefert Funktion, B2 ruft (analog A↔E).
- **OD-3:** per-Pitch + Banner nur bei pitch_plan-Bedarf; „Pitch X" konditional.
- **OD-4 (verbindlich):** E2/E4/E7/E8 scharf erst mit pg_cron (E); durable Kern E1/E5/E6/E9 erfüllt
  „Notify bei Publikation" zu 100% ohne E.
- **OD-5:** Local In-App-Notifications NICHT in C (neue Dependency; Inbox+CDC genügt; OS-Push = Milestone).

## Verifikation je Block
C0 `migration up`/pgTAP/**Helper-Diff vs `…242`** · C1 `migration up`/**5× RPC-Diff**/pgTAP · C2 `migration
up`/pgTAP/ggf. B2-Diff · C3 `migration up`/pgTAP (kein Tick-Aufruf) · C4 `flutter analyze`+Tests/Design · C5 analyze.

### Critical Files
`20261242000000_tournament_finished_inbox_round_time.sql` (Helper+kind-CHECK RE-BASE) ·
`20261201000010_tournament_golive_inbox.sql` (Materialisierungs-RPCs/Notify-Muster) ·
`20261247000000_stage_generate_de_cons_swiss.sql` (`generate_stage_matches`, Gap-Close) ·
`lib/features/inbox/data/inbox_message.dart` · `lib/features/inbox/presentation/inbox_screen.dart`.
