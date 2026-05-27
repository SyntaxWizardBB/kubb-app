# M5 — Schweizer System + Liga-Punkte + Saisontabelle — Risiken und Deferrals

> Status: Entwurf, wartet auf Abnahme
> Datum: 2026-05-27

## Risiken pro Sub-Milestone

### M5.1 — Domain

**R-M5.1-1: Schweizer-Pairing bei ungerader Spielerzahl — Bye-Punkte-Regelung**

Ungerade Spielerzahl in einer Runde verlangt einen Bye-Slot. Spec FR-PAIR-5 sagt "schwächste verbleibende Teilnehmer ohne bisherigen BYE". Offen bleibt: bekommt der Bye-Empfänger einen halben Punkt (FIDE-Schach-Tradition), einen vollen Punkt (Kubb-WM-Praxis), oder keinen Punkt (Sit-Out)?

**Mitigation**: Entscheidung wird in OD-M5-01 / OD-M5-02 mit-eskaliert. Default-Empfehlung: voller Match-Punkt für Bye-Empfänger (3 bei 3-1-0-Schema, 1 bei 1-1-1), wegen Konsistenz mit Kubb-WM-Praxis. Konfigurierbar pro Turnier via `tournament_config.bye_award_points` (numeric, Default 3.0). Property-Test stellt sicher: für ungerade n erzeugt jede Runde genau ein Bye, kein Spieler zwei Byes.

**Severity**: MAJOR — falsche Punkt-Vergabe bricht Liga-Vertrauen.

**R-M5.1-2: Wiederholungs-Vermeidung im Backtracking — Sackgassen-Fall**

Bei n=8 und 4 Runden mit Schwerpunkt-Buckets (alle Top-Score-Spieler treffen sich) kann es Konstellationen geben, wo keine wiederholungsfreie Pairing-Lösung existiert. Backtracking Tiefe ≤3 wird dann eine bereits-gespielte Paarung wiederholen müssen.

**Mitigation**: Bei erkannter Sackgasse: erlaubte Wiederholung mit `repeated: true`-Marker im `PlannedPairing`. UI zeigt Warn-Indikator ("Diese Paarung wurde bereits in Runde X gespielt"), Veranstalter kann manuell eingreifen (FR-PAIR-7). Property-Test mit n∈{6,7,8,9,16} stellt sicher, dass Algorithmus terminiert (auch bei Sackgasse) und nicht hängenbleibt.

**Severity**: MINOR — Wiederholung ist akzeptabel mit Marker, fachlich nicht falsch.

### M5.2 — Backend

**R-M5.2-1: Saison-Migration auf bestehenden Turnieren — Backfill-Strategie**

Bestehende M1–M4-Turniere haben kein Saison-Bezug. Migration `20260801000002_season_schema.sql` erzeugt leere `season_*`-Tabellen. Wenn der Owner alte Turniere nachträglich einer Saison zuordnen will, muss Punkte-Sink-Adapter manuell re-triggert werden — automatisches Backfill ist riskant (alte Turniere haben evtl. abweichende Stufungs-Bonus-Werte).

**Mitigation**: M5 macht **kein automatisches Backfill**. CLI-Tool `scripts/backfill_season_awards.dart` als Folge-Task (M5.4 oder M6) ermöglicht Liga-Admin gezielt einzelne alte Turniere zur Saison hinzuzufügen. Migration ist additiv, kein Daten-Eingriff in bestehende `tournaments`-Tabelle. Bei Pilot-Live-Daten: Owner-Mandat erforderlich, bevor altes Turnier nach-eingebucht wird.

**Severity**: MINOR — manueller Backfill ist akzeptabel, weil M1–M4-Bestand klein ist (Pilot-Phase).

**R-M5.2-2: Pairing-Validation als Trust-Boundary — RPC-Side-Effort**

Per OD-M5-04-Empfehlung läuft Pairing-Algorithmus Client-seitig. RPC `tournament_pair_round` muss daher validieren, dass das gepostete Pairing legal ist (alle Teilnehmer enthalten, keine Doppel-Zuordnung, kein verbotenes Repeat). Falls Validation unvollständig: bösartiger Client kann gewünschte Match-Ups erzwingen.

**Mitigation**: pgTAP-Test-Suite in M5.2-T4 hat mindestens 4 negative Test-Cases (fehlender Teilnehmer / Doppel-Zuordnung / unbekanntes Repeat / Bye für falschen Spieler). Validation wird in einer einzigen PL/pgSQL-Funktion `validate_swiss_pairing(p_tournament_id, p_pairings jsonb)` zentralisiert. Bei Security-Sweep durch Tech-Lead pre-merge: explizit auf diese Funktion zielen.

**Severity**: MAJOR — Trust-Boundary-Lücke ist sicherheitskritisch, aber adressierbar mit klarer Test-Strategie.

### M5.3 — UI + Demo

**R-M5.3-1: Saison-Tabellen-Komplexität bei 50+ Teilnehmern**

Ein Pilot-Liga-Szenario mit 50 Spielern und 10 Turnieren bedeutet 500 Award-Rows, View-SUM über `participant_id` ist trivial. UI muss aber Scrolling, Filter, Suche bieten — Standard-`DataTable` skaliert auf Mobile schlecht (Rendering-Lag ab ~200 Rows).

**Mitigation**: `season_standings_screen` nutzt `ListView.builder` mit Lazy-Render plus Such-Filter im Header. Performance-Smoke-Test mit 200 synthetischen Rows in M5.3-T6. Bei Bedarf: Pagination ab >100 Rows.

**Severity**: MINOR — Pilot-Phase erreicht nicht 50+ Teilnehmer, Vorsorge ist zeit-billig.

**R-M5.3-2: Wizard-Komplexität wächst — neue Steps "Liga & Saison" + "Punkte-Modus"**

Tournament-Setup-Wizard hatte in M1 5 Steps, in M3 7 Steps (Pools/Teams). M5 fügt potenziell 2 weitere Steps hinzu. Ab 9 Steps wird der Wizard verwirrend, Veranstalter brechen ab.

**Mitigation**: Liga-/Saison-Step und Punkte-Modus-Step werden in einen kombinierten Step "Liga & Punkte" gepackt (1 Step total, nicht 2). Default-Auswahl ist "Globale Formel + aktuelle Saison vorausgewählt" — Veranstalter klickt "Weiter" wenn nichts Spezielles. Wizard-UX-Review im M5.3-T6 Akzeptanz-Schritt.

**Severity**: MINOR.

### Übergreifende Risiken

**R-M5-G1: Phase-1-Scope-Creep — Liga-System ist ein eigenständiges Sub-Produkt**

Liga-Punkte, Saisontabelle, Schweizer System sind drei orthogonale Feature-Komplexe. Spec §3.14 + §3.15 + §3.6 umfassen zusammen ~30 FR-Punkte. Wenn alle in M5 — was die Architecture-Plan-Skizze suggeriert — passieren sollen, wird M5 zu gross. Die Spec selbst legt nahe, dass Liga-Wechsel (FR-GLB-11), Plattform-Administrator-Workflows (FR-POINTS-10..-13), Liga-Administrator-Rolle (Glossar §2) eigene Sub-Produkte sind.

**Mitigation**: M5-Scope ist **bewusst geschnitten** auf Schweizer System + Liga-Punkte-Engine + Saison-Aggregation. **Explizit ausgeschlossen** (siehe `architecture.md` §7): Liga-Wechsel-Workflow (FR-GLB-11), Custom-Punkte-Freigabe-Workflow (FR-POINTS-10/-11), globale Cross-Liga-Rangliste, Schweizer+KO-Hybrid (FR-FMT-7), Schochmodus (FR-FMT-3). Diese werden auf M6+ verschoben. Owner-Mandat-Frage: M5 liefert das "Demo-fähige Liga-Skelett"; weitere Liga-Workflows folgen iterativ.

**Severity**: BLOCKER ohne explizite Scope-Disziplin — wird MINOR mit klarem Scope-Schnitt wie oben.

**R-M5-G2: Pairing-Algorithmus-Performance bei n>64**

Per `architecture.md` §6 ist Backtracking O(n²) und mit n=64 binnen <50 ms. Bei n=128 (Schweizer-Meisterschaft-Szenario, möglich in Tier-2) wird Backtracking schnell zum Problem. Heuristik-Fallback (Round-Robin-Variante ohne Backtracking) ist nicht in M5-Scope.

**Mitigation**: M5 dokumentiert das n=64-Limit prominent in UI (Wizard-Validierung: Warnung bei n>64, Hinweis "Schweizer System ist auf 64 Teilnehmer optimiert"). Heuristik-Fallback wird als Folge-Task in M6 erfasst. Property-Test misst Laufzeit, CI bricht bei p99>200 ms ab.

**Severity**: MINOR (in Pilot), MAJOR ab Tier-2.

**R-M5-G3: Saison-Punkte-Audit nach Re-Open eines Turniers**

Wenn ein Turnier auf `finalized` steht und Punkte gebucht sind, dann re-opened (Score-Korrektur via M1-Veranstalter-Override), müssen die Punkte rückgängig und neu gebucht werden. Spec FR-POINTS-13 erwähnt "rückwirkende Einbuchung bei laufender Saison".

**Mitigation**: Per OD-M5-07-Empfehlung: append-only-Ledger mit Reversal-Rows. Beim Turnier-Re-Open: alle bestehenden `season_standings_awards`-Rows bekommen Reversal-Counterpart, beim erneuten Finalize werden neue Awards geschrieben. View `v_season_standings` summiert sauber. Test in M5.2-T4 deckt diesen Workflow ab.

**Severity**: MAJOR — falsch implementiert bedeutet Punkte-Manipulation.

## Bewusste Deferrals (out of M5)

- **Schochmodus (FR-FMT-3)** — Variante des Schweizer Systems, eigener Pairing-Algorithmus. M6.
- **Schweizer + KO-Hybrid (FR-FMT-7)** — komponiert SwissSystem mit M2-KO. M6.
- **Liga-Wechsel-Workflow (FR-GLB-11, Liga-Administrator-Rolle)** — eigenes Sub-Produkt. M6/M7.
- **Custom-Punkte-Freigabe (FR-POINTS-10/-11, Plattform-Administrator-UI)** — M5 implementiert nur die Daten-Felder. UI-Workflow ist Folge-Milestone.
- **Globale Cross-Liga-Rangliste (FR-GLB-Übergreifend)** — M5 macht Saison pro Liga. Cross-Liga-Aggregation ist eigener Read-Path.
- **Pairing-Heuristik-Fallback für n>64** — siehe R-M5-G2.
- **Automatisches Backfill bestehender Turniere in neue Saisons** — siehe R-M5.2-1.
