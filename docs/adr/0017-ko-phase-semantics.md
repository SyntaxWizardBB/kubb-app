# ADR-0017: KO-Phase-Semantik (`round_robin_then_ko` + Spiel-um-Platz-3 + Wildcard-Slots)

- **Status**: Proposed
- **Date**: 2026-05-25
- **Bezug**: `docs/plans/m2-ko-bracket/architecture.md` §3.2, §5.2, §5.3, OD-M2-04, OD-M2-05, OD-M2-06, ADR-0014, ADR-0007

## Entscheidung

Für M2 gelten folgende KO-Phasen-Semantiken:

### 1. Phasenwechsel-Status

Die `tournaments.status`-Spalte bekommt **keinen** zusätzlichen `ko_phase`-Status. Stattdessen wird die Phase **pro Match** in `tournament_matches.phase` (`group` | `ko` | `third_place` | `final`) ausgedrückt. `tournaments.status` bleibt auf `live`, solange irgendein Match offen ist; geht auf `finalized` wenn alle Matches (über alle Phasen) finalisiert sind.

Begründung: Status-Explosion vermeiden. Die Frage "läuft gerade Vorrunde oder KO?" beantwortet sich aus den Matches direkt.

### 2. Voraussetzung für `tournament_start_ko_phase`

Strikt (OD-M2-06 Empfehlung C): Der Aufruf wirft 422 `PHASE_NOT_COMPLETE` wenn auch nur ein Vorrunden-Match nicht `finalized` oder `overridden` ist. Disputed-Matches müssen zuerst per Veranstalter-Override geschlossen werden.

Begründung: Datenintegrität. Bracket-Generation aus unvollständigen Standings führt zu falschem Seeding und ist später schwer rückgängig zu machen.

### 3. Qualifier-Count

Beliebige Anzahl Qualifier zugelassen (OD-M2-05 Empfehlung B), inklusive Nicht-Zweierpotenzen. Bei nicht-2^n wird das Bracket auf die nächste Zweierpotenz aufgefüllt — BYEs gehen an die höchsten Seeds gemäss FR-FMT-11.

Beispiele:
- 4 Qualifier → 2 Halbfinals, 1 Finale (+ optional Spiel-um-Platz-3). Keine BYEs.
- 6 Qualifier → 8-Slot-Bracket, Seeds 1+2 bekommen BYE in Runde 1. Runde 1 hat 2 Matches (Seeds 3v6, 4v5), Runde 2 hat 4 Matches (2 davon mit BYE-Sieger), Runde 3 ist Finale.
- 5 Qualifier → 8-Slot-Bracket, Seeds 1+2+3 bekommen BYE. Runde 1: 1 Match (Seeds 4v5). Runde 2: 4 Matches.

Begründung: FR-FMT-11 ist explizit, BYE-Auffüllung ist bereits in `Bracket.singleElimination` korrekt implementiert.

### 4. Spiel-um-Platz-3 — Optionalität und Default

Pro Turnier konfigurierbar via `KoPhaseConfig.withThirdPlacePlayoff` (OD-M2-04 Empfehlung A). Default = **false**.

Wenn aktiviert: zwei zusätzliche Matches werden bei der KO-Phase-Inbetriebnahme erzeugt:
- Das `third_place`-Match mit `participant_a` und `participant_b` initial `NULL`.
- Werden vom `tournament_advance_ko_winner`-Trigger befüllt, wenn die Halbfinals abgeschlossen sind: Verlierer Halbfinale 1 → `participant_a`, Verlierer Halbfinale 2 → `participant_b`.

Das `third_place`-Match darf parallel zum Finale gespielt werden (eigene Pitch-Zuteilung). Es zählt in M2 noch nicht für Liga-Punkte (kommt M5), aber es trägt zur Endrangliste bei (Sieger = Platz 3, Verlierer = Platz 4).

Begründung: Default-Aus ist defensiver — Veranstalter aktivieren das aktiv, wenn sie es brauchen. Schweizer-Liga-Default lässt sich später per `[domain]`-OD anpassen, wenn nötig.

### 5. Sieger-Fortschreibung — Trigger-basiert

`tournament_advance_ko_winner` läuft als `AFTER UPDATE`-Trigger auf `tournament_matches`. Bedingung: `OLD.status NOT IN ('finalized','overridden') AND NEW.status IN ('finalized','overridden') AND NEW.phase IN ('ko','third_place','final')`.

Trigger-Logik:
1. Lies `NEW.winner_participant`.
2. Berechne Folge-Match-Position: `next_round = NEW.round_number + 1`, `next_position = ceil(NEW.bracket_position / 2)`.
3. Falls Folge-Match existiert (`phase='ko'` oder `phase='final'`):
   - Wenn `NEW.bracket_position` ungerade → schreibe Sieger in `participant_a`.
   - Wenn gerade → schreibe Sieger in `participant_b`.
4. Falls aktuelles Match ein Halbfinale ist UND `tournaments.ko_config->>'with_third_place_playoff' = 'true'`:
   - Berechne Verlierer (`participant_a` oder `participant_b`, je nach `winner_participant`).
   - Schreibe Verlierer ins `third_place`-Match (analoge `participant_a`/`participant_b`-Logik).
5. Falls beide Slots eines Matches gefüllt sind → setze `status = 'awaiting_results'` von `scheduled`.

Begründung: Trigger ist die richtige Ebene für Datenmodell-Invarianten. Client-Roundtrip vermeidet weiteren RPC, ist atomar mit der Konsens-RPC-Transaktion.

### 6. Pairing-Override (FR-PAIR-7)

Nur **vor** Match-Start (Status `scheduled`) möglich. RPC `tournament_organizer_override_pairing(match_id, participant_a, participant_b, reason)`:
- Validiert `tournament_matches.status = 'scheduled'`.
- Validiert beide Teilnehmer sind valide Turnier-Teilnehmer.
- Validiert keine andere KO-Match-Row in derselben Runde verwendet einen der beiden Teilnehmer.
- Schreibt `participant_a` und `participant_b` neu, `reason` ist Pflicht.
- Audit-Event `kind='pairing_overridden'` mit alten und neuen Teilnehmer-IDs plus Reason im Payload.

Begründung: Vermeidet, dass ein gestartetes Match nachträglich verändert wird (Match-Status-Maschine bleibt sauber). Audit-Trail-Pflicht analog zu Score-Override aus M1.

### 7. Bracket-Generation — Server vs. Client

**Status**: Erwartet wartet auf OD-M2-02 Entscheidung. Vorläufige Empfehlung: **Client-Authority mit Server-Plausibilitätsprüfung** (Option B).

`tournament_start_ko_phase(p_tournament_id, p_matches jsonb)` erwartet das vorgenerierte Match-Set vom Client. Server validiert:
- Anzahl Matches entspricht der nötigen Anzahl für die gegebene Qualifier-Zahl (mit BYE-Auffüllung).
- Jeder qualifizierte Teilnehmer ist in genau einem Match in Runde 1 (oder per BYE durchgewunken).
- Bracket-Strukturkonsistenz: für jedes Runde-N-Match existieren die zwei Vorgänger-Matches in Runde N-1 mit korrekten `bracket_position`s.
- Seeding-Tabelle (`tournament_seeding_overrides`) wird respektiert.

Race-Condition zwischen zwei parallelen Veranstalter-Geräten: in M2 unrealistisch (nur ein Veranstalter pro Turnier per RLS-Check `tournaments.created_by = auth.uid()`). Co-Veranstalter-Rollen kommen erst M5+ — dann Re-Visit dieser ADR mit Optimistic-Lock-Token.

## Kontext

M1 hat den Round-Robin-Pfad gebaut. M2 fügt die KO-Phase hinzu, sowohl als reines `single_elimination` als auch als Anschluss-Phase nach Round-Robin (`round_robin_then_ko`). Dabei tauchen mehrere semantische Entscheidungen auf, die nicht aus dem M1-Modell ableitbar sind:

- Wo lebt die Phasen-Information (pro Turnier oder pro Match)?
- Wer baut das Bracket (Client oder Server)?
- Wie wird das Spiel-um-Platz-3 modelliert (in derselben Runden-Linie oder als separates Konzept)?
- Wie wird der Sieger eines KO-Matches automatisch in das Folge-Match übernommen?

Diese ADR fixiert die Antworten, damit die Implementierungs-Tasks in M2.1 (Pure Domain), M2.2 (Server + RPCs) und M2.3 (UI) ohne Rückfragen losgehen können.

## Alternativen

### Alternative zu §1 (Status pro Turnier statt pro Match)

`tournaments.status` bekommt `ko_phase`-Wert zusätzlich zu `live`. Vor der KO-Phase: `live`, nach Phasenwechsel: `ko_phase`, nach Finale: `finalized`.

Verworfen weil: Status-Explosion (Status-Werte verdoppeln sich bei jeder neuen Phase), Frage "läuft KO?" ist aus Match-Phase ableitbar.

### Alternative zu §4 (Spiel-um-Platz-3 als zusätzliche Runde am Ende)

Das `third_place`-Match wird in `round_number = N+1` einsortiert (also nach dem Finale). Trigger und Folge-Logik wären gleicher Pfad wie alle KO-Matches.

Verworfen weil: Spiel-um-Platz-3 wird **vor** oder **parallel** zum Finale gespielt, nicht danach. Das Modell mit `phase='third_place'` ist semantisch korrekter und entkoppelt von `round_number`.

### Alternative zu §6 (Pairing-Override auch nach Match-Start)

Veranstalter kann Pairing auch nach Match-Start ändern, alle eingegangenen Score-Proposals werden verworfen.

Verworfen weil: bricht die Score-Konsens-State-Machine aus ADR-0007, eröffnet Audit-Lücken.

## Konsequenzen

- Datenmodell: Phase-Information lebt auf Match-Ebene, nicht auf Turnier-Ebene. Sauber und erweiterbar.
- Datenbank-Trigger ist die zentrale Stelle für Sieger-Fortschreibung — pgTAP-Tests sind Pflicht (M2.2-T6).
- Spiel-um-Platz-3 als optionales Feature mit klarem Datenmodell-Slot. Liga-Punkte-Anbindung in M5 ist trivial.
- Strikte Phasenwechsel-Validierung (Bedingung 2) kostet Veranstalter potenziell einen Zwischen-Schritt (Disputed-Match überschreiben), erhält aber Datenintegrität.
- Client-Authority für Bracket-Generation hält Server-Code schlank. Späterer Wechsel zu Server-Authority bei OD-M2-02 → A erfordert plpgsql-Spiegelung — ist isoliert in einer RPC und damit überschaubar.
- Co-Veranstalter-Rollen brauchen ab M5+ Re-Visit der Race-Condition-Annahme in §7.

## Status / Tracking

Wartet auf:
- OD-M2-02 (Server- vs. Client-Authority) — Klärung sperrt §7.
- OD-M2-04 (Spiel-um-Platz-3 Default) — Owner-Abnahme sperrt §4.
- OD-M2-05 (Qualifier-Count Constraint) — Domain-Klärung kann §3 beeinflussen.
- OD-M2-06 (Strikt vs. Force-Override Phasenwechsel) — kann §2 beeinflussen.

Nach Klärung dieser ODs: Owner-Acceptance dieser ADR.
