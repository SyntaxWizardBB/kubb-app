# Feature-Plan: Sniper-Training MVP

---

## Meta

- **Slug:** sniper-training-mvp
- **Beschreibung (Owner):** Sniper-Training MVP — Distanz 4-8m konfigurierbar in 0.5er-Schritten, drei Counter (Hit/Miss/Heli — Heli ausschaltbar in App-Settings), je Counter ein +/- Tap-Pad-Paar (also bis zu 6 Pads, 4 wenn Heli aus), optional Ziel-Wurfzahl mit Countdown ("noch X Würfe"), Eye-Toggle für Blind-Training (Counter verbergen), Vibration bei Tap, Session in drift speichern (anonym pro Spieler-Profil), Crash-Recovery beim App-Start (offene Session → fortsetzen/speichern/verwerfen), Abbruch-Button mit Bestätigungs-Dialog, SummaryScreen am Ende. Plus minimales Spieler-Profil (Name beim ersten App-Start abfragen, lokal in drift, einfacher ProfileScreen zur Anzeige) und HomeScreen mit FAB "Training" → Sheet mit Modus-Auswahl, Recent-Sessions-Liste (max 3), Tournier-Karte als Coming-Soon-Placeholder ("In Vorbereitung"), News-Karte mit Link zu kubbtour.ch, AppSettings-Modal über Hamburger (Sprache de fix, Theme Light/Dark/HighContrast, Heli-Tracking on/off, Vibration on/off). Implementierung gemäss Design-System in docs/design/. Finisseur, Match, Stats, CSV-Export sind NICHT Teil dieses Features.
- **Erstellt:** 2026-05-02
- **Status:** drafting
- **Plan-Verzeichnis:** docs/plans/sniper-training-mvp/
- **Temp-Verzeichnis (ephemer):** /tmp/kubb_app/sniper-training-mvp/
- **Branch:** feature/sniper-training-mvp

---

## Bounded-Context-Zuordnung

- [x] training (pragmatisch) — primärer Context
- [x] player (pragmatisches CRUD) — minimales Profil
- [x] core / infrastructure (drift, theme) — Design-System aus ADR-0008, drift-Schema neu
- [ ] match (full hexagonal)
- [ ] tournament (hexagonal-light)

---

## Backlog (Step 1 — Product Owner)

> Wird durch `/agents/product-owner` befüllt. Volldokument: `po-output.md`.

### User Stories

_pending_

### Akzeptanzkriterien (Headline)

_pending_

### Implizite Anforderungen

_pending_

### Owner-Abnahme

- [ ] Backlog akzeptiert am _pending_

---

## Architektur (Step 2 — Architect)

> Wird durch `/agents/architect` befüllt. Volldokument: `architecture.md`. Eventuell neuer ADR.

### Komponenten-Delta

_pending_

### Schnittstellen-Delta

_pending_

### Daten-Modell-Delta

_pending_

### Neue ADRs

_pending — möglicherweise keine, da ADR-0008 das Design-System bereits abdeckt_

### Owner-Abnahme

- [ ] Architektur akzeptiert am _pending_
- [ ] ADR(s) akzeptiert am _pending_

---

## Sprint-Plan (Step 3 — Scrum Master)

> Wird durch `/agents/scrum-master` befüllt. Volldokumente: `sprint-plan.md` und `tasks.md`.

### Milestones

_pending_

### Ausführungsreihenfolge

_pending_

### Owner-Abnahme

- [ ] Plan akzeptiert am _pending_

---

## Fortschritt

| Milestone | Done | In Progress | Blocked | Pending | Total |
|---|---|---|---|---|---|
| _pending_ | 0 | 0 | 0 | 0 | 0 |

---

## Final-Review

- [ ] Security-Checker durchgelaufen — kein BLOCKING
- [ ] Tech-Lead durchgelaufen — `flutter analyze` clean, Tests grün
- [ ] Commit-History clean (kein AI-Trace)
- [ ] Push erfolgt am _pending_

---

## Eskalationen

| ESC-ID | Step | Frage | Antwort |
|---|---|---|---|

_keine bisher_

---

## Risiken

| # | Risiko | Wahrscheinlichkeit | Impact | Mitigation |
|---|---|---|---|---|
| 1 | drift-Schema-Migration noch nie gelaufen — erste DB | Niedrig | Mittel | Schema-Test in M1, frische DB-Erzeugung |
| 2 | Bricolage Grotesque Webfont-Loading bei schlechter Verbindung | Mittel | Niedrig | google_fonts package macht Caching, Fallback auf system-ui |
| 3 | Crash-Recovery-Logik komplex (App-Lifecycle + drift-State) | Mittel | Mittel | Eigener Test-Block, eventuell als Spike vorab |
| 4 | High-Contrast-Theme noch nicht in Material 3 verfügbar | Niedrig | Niedrig | Custom ThemeData-Variante, manuell |
