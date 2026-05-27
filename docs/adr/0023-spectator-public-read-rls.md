# ADR-0023: Spectator-View — Public-Read-RLS mit anonymem JWT

- **Status**: Accepted
- **Date**: 2026-05-27
- **Depends on**: ADR-0001 (Supabase als Auth- und Datenbank-Backend), ADR-0003 (Auth + User-Management — anon-Role ist Supabase-Standard), ADR-0014 (Tournament-Match-Coexistence)
- **Bezug**: `docs/plans/m4-realtime-dashboard-offline/architecture.md` §3.3, `open-decisions.md` OD-M4-03, OD-M4-07, FR-PUB-1..-3, FR-PUB-9, FR-PUB-11

## Kontext

M4.2 baut eine öffentliche Spectator-Sicht für Turniere: anonymer Browser öffnet eine URL, sieht Spielplan, Rangliste und Bracket eines laufenden oder abgeschlossenen Turniers. Use-Case ist analog zu Sport-Liveticker — Link teilen, Klick, sehen.

Drei Fragen müssen vor Implementierung beantwortet sein:

1. **Auth-Modell**: anonym (Public-Read-RLS) oder Light-Auth (Magic-Link / Pseudo-Account)?
2. **Welche Daten sind öffentlich**: alle Turnier-Rows oder selektiv?
3. **Wie kontrollieren Veranstalter die Öffentlichkeit**: pauschal oder pro Turnier?

OD-M4-03 hat den Auth-Modus diskutiert; dieser ADR fasst die Entscheidung mit den dazugehörigen RLS-Policies und Spalten-Sichtbarkeits-Regeln zusammen.

## Entscheidung

### 1. Anonymes JWT mit Public-Read-RLS

Spectator-View nutzt den Supabase-Anon-Key (Build-Time-Public, Standard-Supabase-Modell). Keine Login-Hürde, kein Magic-Link, kein Pseudo-Account.

RLS-Policies erlauben anonymen `SELECT`-Zugriff auf öffentlich markierte Turnier-Daten. Anonymes `INSERT` / `UPDATE` / `DELETE` bleibt überall verboten.

**Begründung**:

- Pilot-Zielgruppe (Schweizer Kubb-Szene) erwartet von einer Spectator-URL keinen Login — UX-Norm von kicker.de, FIVB-Liveticker, etc.
- Anon-JWT ist Supabase-Standard, RLS ist die Autoritäts-Schicht. Risiko durch RLS gedeckt, nicht durch JWT-Geheimhaltung.
- Personalisierung ("deine Lieblings-Teams") ist M5+-Roadmap, dann mit echtem Account-Pfad. Pseudo-Accounts erfänden ein drittes Auth-Modell.

### 2. Sichtbare Daten — selektiv über Public-Flag

Neue Spalte `tournaments.public bool NOT NULL DEFAULT true`. Veranstalter kann pro Turnier auf `false` umschalten (Wizard-Flag, Setting im Detail-Screen).

Public-Read-RLS gilt nur für `tournaments.public = true` UND `tournaments.status IN ('published', 'registration_open', 'registration_closed', 'live', 'finalized')` — `draft`-Rows sind nie anonym sichtbar.

Migration `20260701000002_tournaments_public_flag.sql`:

```sql
ALTER TABLE tournaments
  ADD COLUMN public bool NOT NULL DEFAULT true;

CREATE POLICY tournaments_public_read
  ON tournaments
  FOR SELECT
  TO anon
  USING (
    public = true
    AND status IN ('published', 'registration_open', 'registration_closed', 'live', 'finalized')
  );

CREATE POLICY tournament_matches_public_read
  ON tournament_matches
  FOR SELECT
  TO anon
  USING (
    EXISTS (
      SELECT 1 FROM tournaments t
      WHERE t.id = tournament_matches.tournament_id
        AND t.public = true
        AND t.status IN ('published', 'registration_open', 'registration_closed', 'live', 'finalized')
    )
  );

-- analog für tournament_participants, tournament_set_scores
```

Schreib-Zugriff bleibt für `anon` überall verboten — keine `FOR INSERT/UPDATE/DELETE TO anon`-Policy wird angelegt. RLS ist deny-by-default, eine fehlende Policy ist eine Sperre.

### 3. Spalten-Sichtbarkeit über View statt direkte Tabellen-Reads

Spectator liest **nicht direkt** aus `team_memberships` oder `auth.users`. Stattdessen eine View `public_tournament_roster_view`:

```sql
CREATE VIEW public_tournament_roster_view AS
SELECT
  trs.participant_id,
  trs.slot_index,
  COALESCE(p.display_name, gp.display_name, 'Unbekannt') AS display_name,
  trs.assigned_at
FROM tournament_roster_slots trs
LEFT JOIN team_memberships tm ON tm.user_id = trs.member_user_id
LEFT JOIN profiles p ON p.user_id = tm.user_id
LEFT JOIN team_guest_players gp ON gp.id = trs.guest_player_id
WHERE trs.replaced_at IS NULL;
```

Projiziert nur `display_name`, keine User-IDs, keine E-Mails, keine Liga-Zugehörigkeit aus `team_memberships` (Letzteres ist nur auf Team-Ebene öffentlich, nicht pro-Spieler).

Optional Wizard-Toggle `tournaments.public_anonymize_roster bool DEFAULT false`: wenn true, projiziert die View nur `"Team X (3 Spieler)"` ohne Namen. Für Veranstalter mit Datenschutz-Sensibilität (Vereine, junge Spieler). Default-AUS — FR-PUB-9 sagt Pool-Mitglieder-Namen sind sichtbar.

## Anonymes JWT auf dem Client

Supabase-Client wird mit Anon-Key initialisiert (bereits in M1 so eingerichtet). Beim Bootup wird einmalig eine anonyme Session geholt (`supabase.auth.signInAnonymously()` oder Default-Anon-JWT aus `flutter_dotenv` o.ä.).

Für die Realtime-Subscribes auf Public-Channels (M4.2-T9 Live-Modus-Toggle) wird die Anon-JWT mitgegeben. Supabase Realtime verlangt eine gültige JWT auch für anonyme Sessions.

## Alternativen

### A — Light-Auth via Magic-Link

**Verworfen** wegen Friktion. 80 % der Spectator klicken den E-Mail-Link nicht. Liveticker-UX-Norm ist No-Auth.

### B — Pseudo-Account (Nickname + Geräte-ID)

**Verworfen**: erfindet ein drittes Auth-Modell neben "User mit Magic-Link" und "anon". Komplexität. Edge-Cases bei späterer Migration zu echtem Account.

### C — ChannelAuthToken statt RLS

**Verworfen** per ADR-0021: M4 hat keine Channel-Schreib-Komponente, RLS ist die Wahrheit. Token wäre Redundanz.

### D — Pauschale `public`-Sicht ohne Per-Turnier-Toggle

**Verworfen**: Veranstalter haben legitime Use-Cases für nicht-öffentliche Turniere (interne Trainings-Turniere, Probe-Turniere, vertrauliche Liga-Vorrunden). Toggle ist günstig (eine Spalte) und gibt dem Veranstalter Souveränität.

## Konsequenzen

### Positiv

- Spectator-Link funktioniert ohne Login — Viralität ist möglich.
- Anonymous-Realtime-Subscribe geht (mit anon-JWT), Public-Channels funktionieren.
- Veranstalter behält Kontrolle pro Turnier (public-Toggle, optional Roster-Anonymisierung).
- View-basierte Spalten-Projektion ist sauberer Privacy-Anker — kein E-Mail-Leak möglich, weil die View die Spalte gar nicht hat.
- RLS ist deny-by-default — fehlende Policy = Sperre. Kein Risiko durch vergessene Negativ-Constraints.

### Negativ

- Anon-JWT muss bei Web-Build korrekt eingebunden werden — `supabase_flutter` Web-Build hat hier historische Bugs (R-M4.1-3 in Risk-Doku).
- Spectator-Channel-Skalierung: viraler Turnier-Link kann Free-Tier-Realtime-Limit reissen. Mitigation: Live-Modus-Toggle Default-AUS für Spectator (siehe ADR-0021).
- Veranstalter muss `public=false` explizit setzen wenn er internes Turnier will. Default-true ist Schweizer-Liga-konform aber überrascht möglicherweise einzelne Veranstalter — UX-Hinweis im Wizard nötig.
- pgTAP-Tests sind merge-blocking — RLS-Bug leakt sonst private Daten.

### Neutral

- Sentry-Telemetrie auf Public-Routes wirft eigene Datenschutz-Frage auf (was wird über anonyme Spectator gespeichert). Wird in der Sentry-Integration-Task adressiert, kein separater ADR.
- Wenn Owner später echte Spectator-Identität will (Voting für Best-Match, Vote-for-Player-of-the-Tournament), kann ein "optionaler Anmeldung" Pfad zusätzlich oben drauf — dieser ADR sperrt das nicht.

## Test-Strategie

**pgTAP** (M4.2-T2, merge-blocking):

- anon kann `SELECT` auf `tournaments WHERE public=true AND status='live'`.
- anon kann **nicht** `SELECT` auf `tournaments WHERE public=false`.
- anon kann **nicht** `SELECT` auf `tournaments WHERE status='draft'`.
- anon kann **nicht** `UPDATE` / `INSERT` / `DELETE` auf irgendeiner Tabelle.
- anon kann `SELECT` auf `public_tournament_roster_view`, sieht nur `display_name` (keine User-IDs).
- Wenn `public_anonymize_roster=true`, sieht anon nur "Team X (N Spieler)" ohne Namen.

**Curl-Smoke** (optional, vor Pilot-Demo):

- Mit anon-JWT-Header GET `/rest/v1/tournaments?id=eq.<public-id>` → 200 mit Daten.
- Mit anon-JWT-Header GET `/rest/v1/tournaments?id=eq.<draft-id>` → 200 mit leerem Array (RLS-gefiltert, kein 403 — Supabase-Standard-Verhalten).
- Mit anon-JWT-Header POST `/rest/v1/rpc/tournament_propose_set_score` → 401 / 403.

## Folgepunkte

- **M4.2-T1, T2** implementieren die Policies und pgTAP-Tests.
- **M4.2-T6, T8** binden die Public-Routes in go_router an, mit Anon-Session-Bootstrap beim Public-Route-Hit.
- **Wizard-Erweiterung** in M4.2: `public`-Toggle als Wizard-Feld (Default true), `public_anonymize_roster`-Toggle als Setting im Detail-Screen.
- **Mit M4.5 Push-Notifications** wird neu bewertet, ob anonyme Spectator Push subscriben können (z.B. "Benachrichtige mich wenn Halbfinale beginnt"). Heute klare Sperre.
- **Mit M5 Liga-System** kann ein "öffentliches Liga-Liveticker"-Aggregator-Pfad oben drauf — diese ADR-Sperre bleibt darunter aktiv.

## Status-Notiz

Am 2026-05-27 vom Owner per Mandat (autonom bis nach M5) auf "Accepted" gehoben. OD-M4-03 ist in `open-decisions.md` resolved — Architect-Empfehlung 1:1 übernommen:

- OD-M4-03 → Anonymes JWT mit Public-Read-RLS, `tournaments.public bool DEFAULT true` als Per-Turnier-Toggle.
- Veranstalter-Override via Wizard-Flag bzw. Detail-Screen-Setting (`public=false` für interne Turniere).
- pgTAP-Tests in M4.2-T2 sind merge-blocking, weil RLS-Bug private Daten leaken würde.
