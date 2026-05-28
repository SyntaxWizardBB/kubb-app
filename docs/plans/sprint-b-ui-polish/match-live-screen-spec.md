# Match-Live-Screen Spec (Sprint B · Wave 5 · T1)

**Status**: Architect-Spike — Owner-Entscheid offen
**Author**: W5-T1 (Architect)
**Datum**: 2026-05-28
**Refs**: `docs/design/AUDIT.md` §6 Pkt 6, `docs/design/quality-gates/mobile-kit-overview.md` Mismatch #3, `docs/design/ui_kits/app/MatchScreen.jsx`
**Folge-Tasks**: W5-T2 / W5-T3 / W5-T4 (Polish, unabhängig vom Entscheid) + W5-T5 (nur falls Option A gewinnt)

---

## TL;DR — Empfehlung

**Option B (Status-quo + Polish + Passive Stage-Indicator)** — nicht Option A.

Drei harte Gründe (Hex-Bullets):

- `0xB1` **Server-State ist Source-of-Truth, nicht Tab-Index.** `MatchStatus` (pendingInvites / active / awaitingResults / finalized / voided) wechselt durch Server-RPCs (`match_propose_result`, `match_finish_play`, organizer override). Ein TabController mit `userScrollable: true` würde Spielern erlauben, "Live" zu öffnen, obwohl der Server noch `pendingInvites` meldet — das produziert leere Action-Pads, race-conditions beim ersten Wurf und Inkonsistenzen mit dem Lamport-Clock. Die aktuellen Screens haben **eine Stage = eine Route = ein State** und das ist ein Feature, kein Bug.
- `0xB2` **Notification-Tap-Routing und Deep-Links funktionieren heute.** Inbox-Kind-Dispatcher und Push-Payloads zeigen auf `MatchRoutes.lobby/:id`, `…/result/:id`, `…/await/:id`, `…/finished/:id`. Konsolidierung zwingt zu `/match/:id?stage=lobby|live|result` + parser-logik, plus alle bestehenden Deep-Links müssen ge-redirected werden. Risiko-Nutzen-Verhältnis ist schlecht für einen reinen Visual-Win.
- `0xB3` **Mobile-Kit ist Visual-Spec, nicht Architektur-Mandat.** `MatchScreen.jsx` ist ein Demo mit `useState`-Stages (kein Server, kein Realtime). Die "Konsolidierung" dort existiert, weil der Designer eine 1-Screen-Story für die Kit-Vorschau brauchte. Den **Visual-Pattern (Stage-Tabs als Pille oben, Score-Strip, Action-Pad, Inset-Cards)** holen wir trotzdem ins Flutter — als **passive Status-Indikator** ohne Switch-Logik, plus Polish pro Screen. Damit haben wir 90 % visuelle Treue zum Kit ohne 100 % Architektur-Refactor.

---

## Kontext-Snapshot

### Mobile-Kit (`MatchScreen.jsx`)

- Single Component, lokaler `stage`-State (`'lobby' | 'live' | 'result'`).
- 3 Pill-Tabs oben, Body-Switch je Stage.
- Lobby: Hero (vs.) + H2H + Match-Setup + Start-Button.
- Live: Dark-Score-Strip + 4-Action-Pad (Treffer/Miss/Heli/Strafe) + Mini-Counters + Per-Wurf-Log.
- Result: meadow-500 Hero + Halbsatz-Karten + Stat-Vergleichszeilen + Revanche/Teilen.

### Flutter (heute)

| Screen | Route | Trigger (Server-Status → UI) |
|---|---|---|
| `MatchConfigScreen` | `/match/new` | Manuell (Mode-Card "Match starten") |
| `MatchLobbyScreen` | `/match/lobby/:id` | `pendingInvites` |
| `MatchResultScreen` | `/match/result/:id` | `active` (auto-promote via `match_finish_play`) + `awaitingResults` |
| `MatchAwaitOthersScreen` | `/match/await/:id` | Nach eigenem Proposal, andere noch offen |
| `MatchFinishedScreen` | `/match/finished/:id` | `finalized` / `voided` |

Navigation: jeder Screen `ref.listen`'t `matchDetailProvider` und triggert `context.go(...)` bei Status-Transitions. Polling über `matchPollingProvider` (1 s) hält Detail aktuell.

**Wichtige Beobachtung**: Es gibt **keinen** "Live"-Screen mit Wurf-Erfassung im Flutter. `MatchResultScreen` ist Score-Entry pro Halbsatz, **nicht** Per-Wurf-Tracking. Der "Live"-Tab im Mobile-Kit zeigt ein Feature, das in Flutter noch gar nicht existiert (MatchEvent-Stream, Wurf-Log, 4-Action-Pad). Memory-Note: `watchMatch(matchId)` ist `Stream.empty()` auf allen Impls — kommt mit M4-Realtime-Sprint. **Das verschiebt die "Live"-Stage in eine spätere Milestone**, unabhängig von A/B.

---

## Optionen

### Option A — Konsolidierung auf einen `MatchScreen` mit TabController

**Idee**: Neuer `lib/features/match/presentation/match_screen.dart` mit `DefaultTabController(length: 3)` (oder `PageController`). Routes `/match/:id` mit optionalem `?stage=…`. Bestehende vier Screens werden zu Tab-Body-Widgets (`_LobbyTab`, `_LiveTab`, `_ResultTab`). `MatchFinishedScreen` bleibt separat (terminal, eigener Hero), oder wird als vierter Tab "Beendet" — Variante.

**Pro**:
- 1:1 Mapping zum Mobile-Kit (`MatchScreen.jsx`-Pendant).
- Weniger `context.go(...)`-Boilerplate in jedem Screen.
- Stage-Tabs sind echt klickbar — Spieler können während Pendings den Lobby-Tab nochmal öffnen.
- Einheitlicher State-Container — alle drei Tabs teilen `matchDetailProvider`-Snapshot ohne Re-Navigation.

**Contra / Risiken**:
- **Tab-vs-Status-Synchronisierung**: Was passiert, wenn Spieler auf "Live" tippt, aber `status == pendingInvites`? Drei Sub-Optionen, alle schlecht: (i) Tab blockieren → UX-Reibung, (ii) Tab aktiv aber leere/disabled Body → Verwirrung, (iii) Tab auto-redirected zu "Lobby" → Tab-Tap funktioniert nicht wie erwartet.
- **Back-Stack-Verlust**: Heute landen Inbox-Tap auf `/match/await/:id` und Push-Tap auf `/match/lobby/:id` deterministisch. Mit `/match/:id?stage=…` muss der Stage-Parameter aus Notification-Payloads in einem zusätzlichen Router-Redirect aufgelöst werden. Plus: Back-Button-Verhalten zwischen Tabs ist nicht trivial (TabController hat keinen Back-Stack — die System-Back-Action verlässt den Screen, statt Tab zurück).
- **Realtime-State-Sharing erlaubt heute schon Co-Existenz**: `matchDetailProvider(id)` ist ein Family-Provider — alle drei aktuellen Screens teilen denselben Cache. Konsolidierung bringt hier **keinen Performance-Win**.
- **TabController-Persistenz nach Realtime-Status-Wechsel**: Wenn Server während User in "Lobby"-Tab nach `active` flippt — soll der Tab automatisch wechseln? Wenn ja: User-Interaktion wird unterbrochen ("Wo bin ich gerade?"). Wenn nein: Tab und Status divergieren — der Live-Indikator zeigt LIVE, aber User sieht Setup-Liste.
- **`MatchFinishedScreen` braucht eigene Behandlung** (Hero ist anders, Revanche-Flow ist hier). Konsolidierung wird damit asymmetrisch — 3 Tabs für Lobby/Live/Result, 4. ist Terminal-Screen ohne Tab.
- **`MatchAwaitOthersScreen` passt nicht ins 3-Tab-Modell**. Es ist ein Sub-State von Result. Müsste als Modal/Overlay innerhalb Result-Tab gelöst werden — zusätzliche UI-Komplexität.
- **`MatchConfigScreen` ist Pre-Match** (Match existiert noch nicht!), passt nie in einen `/match/:id`-Container. Bleibt eh separat → auch hier Asymmetrie.
- **Live-Tab ist Vapor-Ware**: Per-Wurf-Log und 4-Action-Pad brauchen MatchEvent-Stream (M4). Bis dahin ist der "Live"-Tab leer oder ein Platzhalter. Konsolidierung jetzt → Skeleton-Tab ohne Content für Wochen.

### Option B — Status-quo + Polish + Passive Stage-Indicator (EMPFOHLEN)

**Idee**: Bestehende Routes/Screens bleiben. Jeder Screen bekommt **oben einen Stage-Indicator-Pill-Row** (analog `MatchScreen.jsx` Stage-Tabs, aber **read-only** — kein onTap-Handler), die den aktuellen `MatchStatus` visualisiert. Polish je Screen gegen das Mobile-Kit (Hero, Inset-Cards, KubbAppBar, KubbButton, KubbChip). Live-Tab (Per-Wurf-Tracking) wird **nicht** in Sprint B angefasst — wartet auf M4-Realtime + MatchEvent-Model.

**Pro**:
- **Keine Routing-Migration**, alle Deep-Links und Notification-Targets bleiben funktional.
- **Server-State bleibt einzige Quelle der Wahrheit** — keine Tab-vs-Status-Drifts.
- **Stage-Indicator** bringt 80 % der visuellen Mobile-Kit-Treue.
- **Inkrementell** — jeder Screen kann unabhängig gepolished werden (parallele Worker W5-T2/T3/T4).
- **M4-Future-Proof**: Wenn Per-Wurf-Live-Tracking dazukommt, ist `match_live_screen.dart` ein **neuer** Screen zwischen `active` und `awaitingResults`, kein Tab-Refactor.
- **`MatchAwaitOthersScreen` + `MatchFinishedScreen` bleiben semantisch klar** — eigene Screens für eigene States.

**Contra**:
- Mobile-Kit-Spec-Treue ist visuell 80 %, nicht 100 % (kein klickbares Stage-Tab).
- 5 Routes statt 1 — mehr Code im Router. Aber: bleibt explizit und debuggbar.
- "Stage-Tab" als read-only Indikator ist ein neues Pattern — könnte Designer-Diskussion auslösen.

---

## Entscheidung

**Option B** — siehe TL;DR. Konkret:

1. Jeder Match-Screen bekommt einen `_MatchStageIndicator`-Header (3 Pills: Lobby / Live / Ergebnis), der **gefärbt ist** nach `MatchStatus`, aber **kein onTap** hat. Variante: optional späterer Touch auf nicht-aktive Pills zeigt SnackBar "Diese Stage ist erst aktiv wenn …" (kein Navigationsversuch).
2. `MatchAwaitOthersScreen` und `MatchFinishedScreen` zeigen denselben Indicator (Indicator-State respektiert Server-Status — "Live"-Pill ist gefüllt während `awaitingResults`, "Ergebnis"-Pill ist gefüllt nach `finalized`).
3. Visual-Polish pro Screen gegen Mobile-Kit (siehe Polish-Punkte unten).
4. **Kein neuer Match-Screen-Container**, keine Routing-Änderungen.

---

## Layout-Sketch (Option B, kondensiert)

```
┌─────────────────────────────────────┐
│  ← Match · Lobby            (Spec) │  ← KubbAppBar (W2-T3)
├─────────────────────────────────────┤
│  ┌──────┐┌──────┐┌─────────┐         │
│  │Lobby ││ Live ││ Ergebnis│         │  ← _MatchStageIndicator (read-only)
│  │ ✓ON  ││  …   ││   …     │         │     gefärbt aus MatchStatus
│  └──────┘└──────┘└─────────┘         │
├─────────────────────────────────────┤
│                                     │
│   [ Screen-spezifischer Body ]       │  ← MatchLobbyScreen / MatchResultScreen
│                                     │     / MatchAwaitOthersScreen / MatchFinishedScreen
│                                     │
└─────────────────────────────────────┘
```

`_MatchStageIndicator` ist ein neues `widgets/`-Widget:

```
// Pseudo-Spec (kein Code in diesem Doc):
//   - drei Pills nebeneinander, gerade gleich breit, radius 999
//   - bg-sunken Container, padding 3, gap 4 — wie MatchScreen.jsx StageTabs
//   - "active"-Pill: stone-900 + chalk-50 (wie Kit)
//   - "inactive"-Pill: transparent + fg-muted
//   - Mapping:
//       pendingInvites          → Lobby aktiv
//       active                  → Live aktiv (Mock — bis M4 zeigt es "Score-Entry")
//       awaitingResults         → Live aktiv ODER Ergebnis aktiv (UX-Entscheid: Ergebnis)
//       finalized / voided      → Ergebnis aktiv
//   - onTap = no-op (oder leichte SnackBar)
```

Sync mit Realtime-Match-Status: Indicator liest `matchDetailProvider(matchId)` direkt — derselbe Provider, der ohnehin schon in jedem Screen läuft. Kein zusätzlicher State.

---

## Risiko-Analyse

| Risiko | Option A | Option B |
|---|---|---|
| Tab/Status-Drift | Hoch (Tab-User-Aktion kollidiert mit Server-State) | Kein (Indicator ist read-only) |
| Back-Stack-Verlust | Mittel (TabController kennt keinen Back-Stack) | Kein (normale GoRouter-Back-Semantik bleibt) |
| Notification-Tap-Routing | Mittel (Deep-Link-Redirect-Layer nötig) | Kein (alle Routes existieren weiter) |
| Realtime-State-Sharing | Kein extra Risiko (Provider sind familienbasiert) | Kein |
| Tab-Persistenz nach Status-Wechsel | Hoch (UX-Entscheid: auto-switch ja/nein, beide schlecht) | Kein (kein Tab → kein Sync-Problem) |
| Live-Stage ohne Content (M4 fehlt) | Hoch (leerer Tab über Wochen) | Kein (Live-Tracking kommt als neuer Screen) |
| Designer-Spec-Drift | Mittel (3-Tab-Pattern → 4-Screen-Pattern) | Niedrig (Visual-Pattern wird übernommen, nur Interaktion nicht) |

---

## Task-Schnitt — Folge-Worker

### Falls Option B (empfohlen — **Standard-Flow**)

| Task | Scope | LOC | Files |
|---|---|---|---|
| **W5-T2** | MatchLobbyScreen-Polish + `_MatchStageIndicator` einbauen | ~80 | `match_lobby_screen.dart`, ggf. `widgets/match_stage_indicator.dart` (neu, ~50 LOC) |
| **W5-T3** | MatchResultScreen-Polish + Indicator | ~80 | `match_result_screen.dart` |
| **W5-T4** | MatchAwaitOthers + MatchFinished Polish + Indicator | ~90 | `match_await_others_screen.dart`, `match_finished_screen.dart` |
| **W5-T5** | **entfällt** | — | — |

Empfohlene Reihenfolge: **W5-T2 zuerst** (führt `_MatchStageIndicator` ein); W5-T3/T4 nutzen das fertige Widget. T3 und T4 sind parallelisierbar nach T2.

`_MatchStageIndicator` als geteilter Widget: idealerweise in `lib/features/match/presentation/widgets/match_stage_indicator.dart`. Wenn W5-T2 das Widget ausliefert, sind T3+T4 nur noch Drop-In. Falls T2 zeitlich knapp wird, kann das Indicator-Widget auch in einer Pre-Task W5-T2a (Worker `coder`, ~50 LOC) extrahiert werden.

### Falls Option A (entgegen Empfehlung)

| Task | Scope | LOC | Files |
|---|---|---|---|
| **W5-T2** | MatchLobby-Polish (Body-Block-vorbereitet als Stand-Alone-Widget) | ~80 | `match_lobby_screen.dart` |
| **W5-T3** | MatchResult-Polish (Body-Block stand-alone) | ~80 | `match_result_screen.dart` |
| **W5-T4** | MatchAwaitOthers + MatchFinished Polish | ~90 | beide Screens |
| **W5-T5** | Neuer `MatchScreen` Tabbed-Container | ~100+ (sicher Splitting) | `match_screen.dart` (neu), `lib/app/router.dart`, `match_routes.dart`, Inbox-Kind-Dispatcher, Push-Payload-Parser |
| **W5-T5a** | Notification-Deep-Link-Redirect-Layer | ~50 | Router-redirect + Tests |
| **W5-T5b** | Tab-State-Persistenz-Logik (Tab vs. Status) | ~60 | `match_screen.dart` + Tests |

Option-A-Total: 460+ LOC, mind. 3 zusätzliche Tests-Surfaces (TabController-Sync, Deep-Link, Status-Drift), 2 Routing-Migrationen — deutlich über Senior-Limit von "max 100 LOC, max 3 Files, max 1 h".

---

## Polish-Punkte pro Screen (gilt unabhängig von A/B)

### MatchLobbyScreen (`match_lobby_screen.dart` → W5-T2)

Quelle: `MatchScreen.jsx` Lobby-Block.

- [ ] `AppBar` → `KubbAppBar` (W2-T3-Widget) mit Eyebrow `Match · Lobby` + Title aus Team-Namen.
- [ ] **`_MatchStageIndicator`** unter AppBar (read-only Pill-Row).
- [ ] **Hero-Block** in Inset-Card: Side A vs. VS-Spalte (Big "vs." + Clock + Court-Meta) vs. Side B. Avatars (radius 12), Form-Row (4 Mini-Pills W/L) — **erste Version**: ELO + Form-Row mit Daten "—" falls Match-Domain noch keine Wins/Losses liefert (Mockup-fähig).
- [ ] **"Direkter Vergleich"-Section** mit H2H-Liste 3 Einträge. **Falls H2H-Query nicht verfügbar** (Cross-Match-Aggregat fehlt im Backend): Section-Header zeigen + Empty-State-Card ("Noch keine direkten Vergleiche").
- [ ] **"Match-Setup"-Section**: Format (`BO5`), Heli-Tracking (`ja/nein`), Strafkubb (`schwedisch`), Court (`Court 2`). Datenquellen: `MatchFormat`, `MatchConfigDraft`-Felder.
- [ ] **Start-Button** unten: `KubbButton.primary`, "Match starten" — nur sichtbar wenn `canCancel`-Flag aktiv (Creator + pendingInvites). Sonst nur Cancel-Button.
- [ ] Status-Pille → `KubbStatusChip.match(...)` ist bereits da (W3-T4), nur Position/Layout angleichen.

### MatchResultScreen (`match_result_screen.dart` → W5-T3)

Quelle: `MatchScreen.jsx` Result-Block + Live-Block (für Score-Strip).

- [ ] `AppBar` → `KubbAppBar` (ist schon partiell migriert — laut Kommentar im `match_finished_screen.dart` schon, im Result noch nicht prüfen).
- [ ] **`_MatchStageIndicator`** unter AppBar — Pill "Live" aktiv während `active`, "Ergebnis" aktiv während `awaitingResults`.
- [ ] **Score-Strip** (dark `stone-900` Block) oben: aktuelle Halbsatz-Summe + LIVE-Dot. Realer Live-Indikator kommt erst mit M4, vorerst: nur Score + Halbsatz-Counter.
- [ ] **Halbsatz-Verlauf**: Liste der bisherigen Runden in Inset-Card.
- [ ] **Score-Entry-Pad**: aktuelle Zahleneingabe migrieren auf größere Tap-Targets (vergleiche Action-Pad-Tones, aber: nur Number-Stepper, kein 4-Action-Pad — das ist Live-Future).
- [ ] **"Bekannt geben"-Button** als `KubbButton.primary`, 56dp minHeight.

### MatchAwaitOthersScreen (`match_await_others_screen.dart` → W5-T4)

- [ ] `AppBar` → `KubbAppBar` (TODO-Kommentar zeigt das).
- [ ] **`_MatchStageIndicator`**.
- [ ] **Header-Block**: "Warten auf andere Spieler" als Eyebrow + Liste der pending Participants (Avatar + Name + Status-Icon). Visuell wie Lobby-Side-Pattern.
- [ ] **Loading-Indicator** stylisch (Lottie / Kit-konformer Spinner).
- [ ] **Polling-State sichtbar**: kleiner "Aktualisiert vor 3 s"-Hinweis.

### MatchFinishedScreen (`match_finished_screen.dart` → W5-T4)

Quelle: `MatchScreen.jsx` Result-Hero + Stats-Block.

- [ ] **`_MatchStageIndicator`** mit "Ergebnis"-Pill aktiv.
- [ ] **Result-Hero** in `meadow-500` (Sieg) bzw. `stone-400` (Voided/Tie): Big-Score (88px Display), Teams unten, Meta-Zeile (Dauer · Würfe · ELO-Delta).
- [ ] **Halbsatz-Verlauf** als Set-Card-Row (5 Karten, win/loss-coloriert).
- [ ] **Statistik-Vergleich** (du vs. Gegner): StatRow-Pattern, `meadow-700` weight 800 wenn "homeBetter".
- [ ] **Action-Row**: "Revanche" (Ghost) + "Match teilen" (Primary). Revanche-Flow ist neuer Hook (siehe `MatchActions.createMatch` mit dupliziertem Config); Teilen kann initial nur SnackBar "Coming soon".

### MatchConfigScreen (`match_config_screen.dart` → out of scope für W5)

Nicht im Mobile-Kit `MatchScreen.jsx` enthalten (das ist post-config). Wird in einem späteren Polish-Pass behandelt.

---

## Acceptance fuer Owner-Abnahme

- [x] Klare Empfehlung (Option B mit drei Hex-Bullet-Gründen).
- [x] Beide Optionen mit Pro/Contra explizit.
- [x] Risiko-Tabelle mit Vergleich.
- [x] Task-Schnitt für W5-T2/T3/T4 (Option B) + W5-T5 (Option A, falls Owner Option A erzwingt).
- [x] Polish-Punkte pro Screen (gelten unabhängig vom Entscheid).
- [x] Stage-Indicator-Widget-Skizze (Pseudo-Spec, kein Code).

Owner-Entscheid binnen 5 Minuten möglich: ja oder nein zu Option B. Wenn ja → W5-T2/T3/T4 starten. Wenn nein (→ Option A) → W5-T5/T5a/T5b zusätzlich planen, Senior-Limit-Splitting beachten.

---

## Offene Fragen (für Owner, optional)

1. Soll `_MatchStageIndicator` einen Tap-Handler haben (mit SnackBar-Hinweis), oder echt rein dekorativ? Architect-Vorschlag: rein dekorativ, max. Tooltip / Semantics-Label.
2. `awaitingResults` — soll der Indicator "Live" oder "Ergebnis" als aktiv markieren? Architect-Vorschlag: "Ergebnis" (semantisch — User ist beim Score-Entry).
3. Revanche-Flow: existiert `MatchActions.duplicate(matchId)` oder müsste das neu? Architect-Vorschlag: in W5-T4 erst SnackBar "Coming soon", Domain-Erweiterung in eigenem Ticket.
