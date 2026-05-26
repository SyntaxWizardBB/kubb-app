# ADR-0020: Roster-Substitution-Regeln (BR-5, Mid-Tournament-Swap, Audit)

- **Status**: Proposed
- **Date**: 2026-05-26
- **Depends on**: ADR-0018 (Team-Modell), ADR-0001 (Tech-Stack), ADR-0014 (Tournament-Match-Pfad-Trennung)
- **Bezug**: `docs/plans/m3-teams-pools-roster/architecture.md` §3.3, §4.3, `docs/specs/tournament-mode-spec.md` FR-TEAM-12..16, FR-REG-12, BR-5, BR-9, BR-29, OD-M3-07

## Context

M3.2 baut den Roster-Pfad: jedes Team meldet sich mit einer Auswahl seines Pools an, das Roster kann während des Turniers von jedem Pool-Mitglied geändert werden. Drei Aspekte brauchen explizite Regeln:

1. **Roster-Auswahl bei Anmeldung** — Mindest-Anforderungen (FR-REG-12: min 1 registriertes Mitglied), Slot-Anzahl (= `tournaments.team_size`), Mehrfach-Roster-Sperre (BR-5).
2. **Mid-Tournament-Substitution** — wann ist sie erlaubt, wer darf sie auslösen, was wird im Audit-Trail festgehalten?
3. **Score-Eingabe-Berechtigung** — wer eines Team-Pools darf Match-Scores eingeben (BR-9)?

Die Spec deckt das in §3.7.3 und Kapitel 6 (BR-5, BR-9, BR-29) ab, lässt aber den Substitutions-Zeitpunkt mehrdeutig: "während des Turniers" — heisst das auch mitten in einem Match? OD-M3-07 ist die offene Frage.

## Decision

### 1. Roster-Slots Datenmodell

Pro Team-Participant eine Roster-Liste in `tournament_roster_slots` (siehe ADR-0018 plus M3.2-Migration):

```sql
CREATE TABLE public.tournament_roster_slots (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_id    uuid NOT NULL REFERENCES public.tournament_participants(id) ON DELETE CASCADE,
  slot_index        smallint NOT NULL CHECK (slot_index BETWEEN 1 AND 6),
  member_user_id    uuid NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  guest_player_id   uuid NULL REFERENCES public.team_guest_players(id) ON DELETE RESTRICT,
  assigned_at       timestamptz NOT NULL DEFAULT now(),
  assigned_by       uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET DEFAULT,
  replaced_at       timestamptz NULL,
  replaced_by       uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reason            text NULL,
  CONSTRAINT roster_slot_xor
    CHECK ((member_user_id IS NULL) <> (guest_player_id IS NULL))
);

-- Aktive Belegung ist eindeutig pro Slot.
CREATE UNIQUE INDEX tournament_roster_slots_active_unique
  ON public.tournament_roster_slots (participant_id, slot_index)
  WHERE replaced_at IS NULL;

-- Cross-Tournament-Lookup für BR-5 (Performance).
CREATE INDEX tournament_roster_slots_member_active_idx
  ON public.tournament_roster_slots (member_user_id)
  WHERE replaced_at IS NULL AND member_user_id IS NOT NULL;
```

Aktive Roster-Slots haben `replaced_at IS NULL`. History entsteht implizit: alte Slot-Zeilen bleiben mit `replaced_at` gesetzt.

### 2. Roster-Auswahl bei Anmeldung

`tournament_register_team(p_tournament_id, p_team_id, p_roster jsonb)` validiert serverseitig:

1. **Pool-Mitgliedschaft**: jedes `member_user_id` und `guest_player_id` im Roster muss im Pool von `p_team_id` sein (`team_memberships.removed_at IS NULL` bzw. `team_guest_players.removed_at IS NULL`).
2. **Slot-Anzahl**: `cardinality(p_roster) = tournaments.team_size`.
3. **FR-REG-12**: mindestens ein Eintrag mit `member_user_id IS NOT NULL` (min 1 registriertes Mitglied).
4. **BR-5**: kein `member_user_id` darf bereits in einem aktiven Roster-Slot eines anderen Participants desselben Turniers stehen. Check via:

```sql
SELECT 1 FROM public.tournament_roster_slots trs
  JOIN public.tournament_participants tp ON tp.id = trs.participant_id
  WHERE tp.tournament_id = p_tournament_id
    AND trs.member_user_id = ANY(SELECT (e->>'member_user_id')::uuid FROM jsonb_array_elements(p_roster) AS e WHERE e->>'member_user_id' IS NOT NULL)
    AND trs.replaced_at IS NULL;
-- Wenn EXISTS → RAISE EXCEPTION 'BR_5_VIOLATION'
```

5. **Aufrufer-Berechtigung**: `auth.uid()` muss aktives Pool-Mitglied von `p_team_id` sein (FR-REG-2).

Bei Erfolg: Insert `tournament_participants` mit `team_id=p_team_id`, `user_id=auth.uid()`, plus N Inserts in `tournament_roster_slots`. Audit-Event `team_registered` mit Roster-Snapshot im Payload.

### 3. Mid-Tournament-Substitution

`tournament_roster_replace(p_participant_id, p_slot_index, p_new_member_user_id, p_new_guest_player_id, p_reason)` validiert:

1. **Aufrufer-Berechtigung**: `auth.uid()` muss aktives Pool-Mitglied im Team des Participants sein (BR-29).
2. **Roster-Lock**: `tournament_participants.roster_locked_at IS NULL` und `tournaments.status != 'finalized'` (FR-TEAM-15).
3. **Pool-Mitgliedschaft des Ersatzes**: analog zur Anmeldung.
4. **BR-5**: der neue Spieler darf nicht in einem anderen aktiven Roster desselben Turniers stehen.
5. **Substitution-Zeitpunkt** (OD-M3-07 Empfehlung A): Substitution ist nur erlaubt wenn das Team-Participant aktuell kein Match mit Status `awaiting_results` hat. Check:

```sql
IF EXISTS (
  SELECT 1 FROM public.tournament_matches
  WHERE (participant_a = p_participant_id OR participant_b = p_participant_id)
    AND status = 'awaiting_results'
) THEN
  RAISE EXCEPTION 'MATCH_IN_PROGRESS'
    USING ERRCODE = '40001',
          HINT = 'Substitution only allowed between matches, not during';
END IF;
```

Bei Erfolg:

- UPDATE der alten Slot-Zeile: `replaced_at = now()`, `replaced_by = auth.uid()`, `reason = p_reason`.
- INSERT der neuen Slot-Zeile mit gleicher `slot_index`, neuer Occupant, `assigned_by = auth.uid()`.
- Audit-Event `roster_slot_replaced` mit Payload `{slot_index, old_occupant, new_occupant, reason}`.

### 4. Score-Eingabe-Berechtigung (BR-9)

Bestehende M1-RPCs (`tournament_propose_set_score`) prüfen heute `submitter_user_id IN (participant_a.user_id, participant_b.user_id)`. M3 erweitert das auf Team-Matches:

```sql
-- Submitter muss aktives Pool-Mitglied eines der beiden Match-Teams sein.
IF NOT EXISTS (
  SELECT 1 FROM public.tournament_participants tp
  JOIN public.team_memberships tm ON tm.team_id = tp.team_id
  WHERE (tp.id = match.participant_a OR tp.id = match.participant_b)
    AND tm.user_id = auth.uid()
    AND tm.removed_at IS NULL
    AND tp.team_id IS NOT NULL
) THEN
  -- Falls Einzelturnier: alter Check
  IF NOT EXISTS (
    SELECT 1 FROM public.tournament_participants tp
    WHERE (tp.id = match.participant_a OR tp.id = match.participant_b)
      AND tp.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'NOT_MATCH_PARTICIPANT' USING ERRCODE = '42501';
  END IF;
END IF;
```

Die zwei-Pfade-Logik ist bewusst — Einzelturniere bleiben unverändert (M1-Verhalten), Team-Turniere bekommen den Pool-Membership-Check. Kein Refactor von M1-Code, additiv.

### 5. Roster-Lock nach Turnierende (FR-TEAM-15)

Wenn `tournaments.status` auf `finalized` geht (durch RPC `tournament_finalize` aus M1), wird in derselben Transaktion für jeden `tournament_participants`-Row gesetzt:

```sql
UPDATE public.tournament_participants
  SET roster_locked_at = now()
  WHERE tournament_id = p_tournament_id;
```

Nach Lock sind `tournament_roster_replace`-Aufrufe blockiert. History bleibt sichtbar.

### 6. Audit-Trail-Vollständigkeit (FR-TEAM-14, NFR-AUDIT-3)

Drei Audit-Events leben im `tournament_audit_events`-Stream (nicht `team_audit_events` — die Events sind tournament-spezifisch):

- `team_registered` — bei `tournament_register_team`-Erfolg. Payload: `{team_id, roster: [...]}`.
- `roster_slot_replaced` — bei `tournament_roster_replace`. Payload: `{participant_id, slot_index, old: {member_user_id?, guest_player_id?}, new: {...}, reason}`.
- `roster_locked` — bei Tournament-Finalize. Payload: `{participant_id, locked_at}`.

Append-only, nie editierbar. Eingebunden in die Audit-Tail-Sicht der M1-Tournament-Detail.

## Alternatives considered

### A) Substitution mid-Set erlaubt (OD-M3-07 Option B oder C)

Verworfen für M3. Mid-Set-Substitution würde Set-State-Tracking auf Match-Ebene erfordern (aktuell trackt das Score-Spec nur per-Set-Proposals). Aufwand: zusätzliche `tournament_match_set_state`-Tabelle plus Score-Spec-Anpassung. Kann M5+ kommen wenn Schweizer Liga-Reglemente das explizit fordern.

### B) Hard-Delete der ersetzten Roster-Slots

Verworfen. NFR-AUDIT-3 fordert Roster-Änderungen protokolliert. Soft-Delete via `replaced_at` plus History-Sichtbarkeit ist Standard-Pattern, konsistent mit `team_memberships.removed_at`.

### C) Reservespieler-Konzept (OD-M3-04 Option B oder C)

Verworfen für M3 (Empfehlung A). FR-TEAM-16 ist KANN-Erweiterung. Keine konkrete Schweizer-Praxis für aktiv / Reserve im Pilot-Zeitraum. Bei Bedarf kommt es M5+ ohne Migration.

### D) BR-5 nur clientseitig prüfen

Verworfen. Clientseitige Prüfung ist Usability-Feature (Pool-Liste markiert ausgegraut), nicht Sicherheit. Serverseitige Validierung mit `tournament_roster_replace`-Trigger ist zwingend.

### E) Roster als JSON-Array in `tournament_participants.roster jsonb`

Verworfen. Eigene Tabelle ist nötig für (a) History via `replaced_at`, (b) BR-5-Index, (c) Audit-Trail per Row. JSON-Array würde alle drei Punkte verkomplizieren.

### F) Substitution nur durch Captain (statt jedem Pool-Mitglied)

Verworfen. FR-TEAM-5 plus BR-27 sind explizit: alle Pool-Mitglieder haben gleichberechtigte Captain-Rechte. Ein "Lead-Captain" existiert nicht. Substitution-Berechtigung folgt diesem Modell.

## Consequences

### Was einfacher wird

- Audit-Trail ist vollständig in der bestehenden `tournament_audit_events`-Tabelle — keine zusätzliche Audit-Infrastruktur.
- BR-5-Check ist ein einziger Query-Pattern mit Partial-Index, performant bis Tier 1.
- Mid-Tournament-Substitution ist eine atomare RPC mit klaren Pre-Conditions — keine multi-step UI nötig.
- Score-Eingabe-Berechtigung für Teams erweitert die M1-Logik additiv, ohne Refactor.

### Was teurer wird

- BR-5-Trigger ist Performance-empfindlich bei hoher Roster-Insert-Rate. Tier-2-Skala braucht Partial-Index auf `member_user_id`. Aktuell (Tier 0) kein Index nötig, aber Scale-Impact-Notiz im Plan.
- Match-In-Progress-Check kostet einen zusätzlichen Query-Roundtrip pro Substitution. Akzeptabel — Substitutionen sind selten.
- Substitution ist nur zwischen Matches möglich. Bei akuter Verletzung mid-Set muss das Match per Forfeit / Voided geschlossen werden — Logik dafür kommt erst in M4 (Live-Management-Erweiterung). M3 dokumentiert die Lücke in `risks-and-deferrals.md`.

### Nicht-Konsequenzen

- Score-Eingabe-Granularität bleibt per-Match plus per-Set (per ADR-0014). Substitution-Tracking pro Wurf ist explizit ausgeschlossen.
- Gast-Spieler im Roster können kein Score eingeben — sie haben keinen Auth-Account. Score-Eingabe-RPC verlangt `auth.uid()`. Das ist konsistent mit BR-9 und BR-27.
- Reservespieler-Konzept bleibt offen. Bei Bedarf kommt eine `tournament_match_lineups`-Tabelle in M5+.
