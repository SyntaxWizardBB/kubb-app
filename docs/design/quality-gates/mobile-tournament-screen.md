# Quality-Gate: Tournament (Mobile-Uebersicht) **NEU**

**Quelle**: `docs/design/ui_kits/app/TournamentScreen.jsx` (NEU im Kit)
**Flutter-Pendant**: vorhanden als **mehrere Einzel-Screens** unter `lib/features/tournament/presentation/`:
- `tournament_list_screen.dart`
- `tournament_detail_screen.dart`
- `tournament_standings_screen.dart`
- `tournament_bracket_screen.dart`
- `tournament_match_list_screen.dart`
- `tournament_match_detail_screen.dart`
- `tournament_conflict_screen.dart`
- `tournament_override_screen.dart`
- `tournament_setup_wizard.dart`
- `tournament_seeding_screen.dart`
- `tournament_pool_standings_screen.dart`
- `tournament_live_dashboard_screen.dart`
- `tournament_registration_screen.dart`
- `register_team_screen.dart`
- `roster_editor_screen.dart`

Die Mobile-Spec konsolidiert die Hauptansichten (Liste + Detail + Standings + Bracket + Mein Match + Plan) auf **einen einzigen Screen mit Filter-Chips + Hero + Sub-Tabs + Weitere-Turniere-Liste**.
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **AppBar**: Eyebrow `Turniere · Saison 2025`, Title `Tour & Liga`, Back + Filter-Icon Right.
2. **Filter-Chips-Row** (horizontal scroll): `Alle` / `Anmelden` / `Live` / `Archiv`. Aktiv = stone-900 + chalk-50.
3. **Hero-Card** (aktives Turnier): Inset-Card mit:
   - Head-Zeile: Status-Tag (oder Live-Badge mit rot-blinkendem Dot) + When-Text (`läuft`, `in 12 Tagen`, `archiviert`).
   - Name (Display 20px weight 800).
   - Meta-Row: Datum · Stadt · `{teams} Teams`.
   - Optional: Registration-Indicator ("• angemeldet als Spieler" mit gruenem Dot).
   - **Live-Hero** hat `stone-900` Bg + chalk-50 Text.
4. **Action-Row**: kontextueller CTA:
   - Live: "Mein Match oeffnen" (Target-Icon).
   - Registriert (Upcoming): "Abmelden" (Ghost).
   - Done: "Rueckblick" (Ghost, ChevronRight).
   - Open (nicht registriert): "Anmelden · CHF 25" (Plus2-Icon).
5. **Sub-Tabs**: 4 Tabs (`Tabelle` / `Bracket` / `Mein Match` / `Plan`) im Pill-Container.
6. **Tab-Content**:
   - **Tabelle (`Standings`)**: Inset-Card mit Tabellen-Kopf (`#`, `Team`, `S`, `N`, `Diff`, `Pkt`) + 8 Standings-Rows. You-Row hat meadow-50 Bg. Podium-Plaetze (1-3) haben `wood-400` Rank-Bubble.
   - **Bracket (`BracketView`)**: Horizontal-Scroll-Container mit 3+1 Spalten (R1 / R2 / R3 / Final). Pro Match-Slot Team-Name + Score. Final-Slot mit wood-100 Bg.
   - **Mein Match (`MyMatch`)**: Match-Karte mit Round/Court-Head + 2 Sides + Score + Note + CTA "Match-Lobby oeffnen".
   - **Plan (`Schedule`)**: Liste von 4 Slots (Zeit + Round + Teams + Score + Done/Next-Tag). Next-Slot hat `wood-50` Bg + left-Inset wood-500.
7. **Section "Weitere Turniere"** — Liste von Tiles (gefiltert ohne den aktiven). Jede Tile: When + Status + Name + Sub + optional `angemeldet`/`Ergebnis`.

### Farben (Tokens)

| Element | Token |
|---|---|
| FilterChip-Off | `--bk-bg-raised` + inset 1.5px line |
| FilterChip-On | `--bk-stone-900` + chalk-50 |
| Hero-Default | `--bk-bg-raised` |
| Hero-Live | `--bk-stone-900` + chalk-50 |
| LiveBadge-Fg | `--bk-miss` (rot) |
| LiveBlink-Dot | `--bk-miss` |
| StatusTag-Upcoming | `--bk-meadow-100` + `--bk-meadow-700` |
| StatusTag-Open | `--bk-wood-100` + `--bk-wood-600` |
| StatusTag-Live | `--bk-stone-900` + chalk-50 |
| StatusTag-Done | `--bk-stone-100` + fg-muted |
| GreenDot (registered) | `--bk-meadow-400` |
| HeroReg-Text | `--bk-meadow-300` |
| CTA-Primary | `--bk-primary` |
| CTA-Ghost | transparent + inset line-strong |
| Tab-On | `--bk-stone-900` + chalk-50 |
| ContentBox | `--bk-bg-raised` |
| TableRowYou | `--bk-meadow-50` |
| RankBubble-Default | `--bk-stone-100` + fg-muted |
| RankBubble-Podium | `--bk-wood-400` + white |
| YouTag | `--bk-meadow-100` + `--bk-meadow-700` |
| Diff-Plus | `--bk-meadow-600` |
| Diff-Minus | `--bk-miss` |
| Bracket-Match | `--bk-bg-sunken` |
| Bracket-Final | `--bk-wood-100` + inset 1.5px `--bk-wood-400` |
| MyMatchAv | `--bk-stone-900` + chalk-50 |
| MyMatchClock | `--bk-wood-600` |
| SchedRowNext | `--bk-wood-50` + inset 3px wood-500 left |
| SchedDone | `--bk-meadow-600` |
| SchedNext-Tag | `--bk-wood-600` |
| Tile | `--bk-bg-raised` + inset 1px line |
| TileReg | `--bk-meadow-700` |

### Typografie

- FilterChip: Display 12px weight 600.
- HeroWhen: Mono 10px opacity 0.7 tracking 0.04em.
- LiveBadge: Mono 10px weight 700 uppercase tracking 0.1em.
- HeroName: Display 20px weight 800 tracking -0.02em lineHeight 1.15.
- HeroMeta: 11px opacity 0.78.
- HeroReg: Mono 10px meadow-300.
- CTA: Display 14-15px weight 600-700.
- Tab: Display 12px weight 700.
- TableHead: Mono 9px weight 600 uppercase tracking 0.06em fg-muted.
- TableRow: Display 13px right-aligned.
- TeamCol: weight 700 left-aligned.
- YouTag: Mono 8px weight 700 uppercase.
- NumCell: Mono 11px weight 600 `tabular-nums`.
- PtsCell: Display 14px weight 800 `tabular-nums`.
- BracketHead: Mono 10px weight 600 uppercase fg-muted.
- BracketSlot: Display 11px weight 600.
- MyMatchRound: Mono 10px weight 600 uppercase fg-muted.
- MyMatchClock: Display 13px weight 700 wood-600.
- MyMatchName: Display 13px weight 700 lineHeight 1.1.
- MyMatchSub: 11px fg-muted.
- MyMatchScore: Display 22px weight 800 `tabular-nums`.
- MyMatchNote: 12px fg-muted lineHeight 1.4.
- SchedTime: Mono 13px weight 700 `tabular-nums`.
- SchedRound: Mono 9px fg-muted tracking 0.04em.
- SchedTeams: Display 12px weight 600 lineHeight 1.2.
- SchedScore: Mono 12px weight 700 `tabular-nums`.
- SchedNext: Mono 9px weight 700 uppercase wood-600.
- TileWhen: Mono 10px fg-muted.
- TileName: Display 15px weight 700 tracking -0.015em.
- TileSub: 11px fg-muted.
- TileResult: Mono 11px fg-muted.
- Tag (status): Mono 9px weight 700 uppercase tracking 0.06em.

### Spacing

- FilterRow: padding `4px 16px 10px`, gap 6, horizontal scroll.
- Hero: margin `0 16px`, padding `14px 16px`, gap 6.
- ActionRow: padding `10px 16px 4px`.
- CTA: minHeight 50, full-width.
- Tabs: margin `14px 16px 8px`, padding 3, gap 4.
- ContentBox: margin `0 16px`, padding `4px 12px`.
- TableHead/Row: Grid `26px 1fr 24px 24px 38px 32px` gap 6.
- TableRowYou: extended margin `-6px` + padding `6px`.
- RankBubble: 22x22.
- BracketScroll: gap 10, padding `10px 0`, overflowX auto.
- BracketCol: gap 6, minWidth 120.
- BracketMatch: padding `6px 8px`.
- MyMatchHead: padding `10px 0 8px`.
- MyMatchTeams: padding `14px 0`.
- MyMatchAv: 36x36.
- Section: padding `18px 18px 8px` (vor "Weitere Turniere").
- List: padding `0 16px`, gap 8.
- Tile: padding `12px 14px`, gap 4.

### Border-Radius

- FilterChip: 999.
- Hero: 18.
- CTA / CTA-Ghost: 14.
- Tabs / Tab-Btn: 999.
- ContentBox: 14.
- RankBubble: 999.
- BracketMatch: 8.
- MyMatchAv: 10.
- Tile: 14.
- Tag (status): 4.
- LiveBadge: 4.
- YouTag: 3.

### Shadows

- Hero: `var(--bk-shadow-1)`.

### Icons

- `Icon.Filter` (22px) — AppBar.
- `Icon.Target` (22px) — CTA "Mein Match oeffnen".
- `Icon.ChevronRight` (20px) — CTA "Rueckblick".
- `Icon.Plus2` (20px) — CTA "Anmelden".

### Brand-Elemente

- **LiveBlink-Dot** in `--bk-miss` (rot) — universelles "live"-Signal.
- **Wood-Tones** auf Bracket-Final + Schedule-Next-Slot + Podium-Rank-Bubble — verstaerkt Tournament-Charakter.

## Komponenten-Inventar

- `TournamentScreen` — Hauptkomponente mit Filter-State + Active-State + Tab-State.
- `StatusTag` — Status-Pill mit 4 Varianten (upcoming/open/live/done).
- `Standings` — Tabellen-View.
- `BracketView` — Bracket-Horizontal-Scroll.
- `MyMatch` — Mein-Match-Karte.
- `Schedule` — Spielplan-Liste.
- Konstante `TOURNAMENTS` — 5 Mock-Tournaments mit unterschiedlichen Stati.
- Konstante `STANDINGS` — 8 Standings-Eintraege mit `you:true` auf Rang 3.

## Interaktions-Pattern

- **Filter-Chips**: exklusive Single-Select. `all` zeigt alle; `open` filtert auf Status `open` || (upcoming && !registered); `live` filtert auf `live:true`; `done` auf `status=='done'`.
- **Hero-Active**: erstes Item nach Filter (default Sortierung), kann durch Tap auf Tile gewechselt werden.
- **Sub-Tabs**: rendern unterschiedliche Sub-Views.
- **CTA-Switch**: je nach Status des aktiven Tournaments.
- **`onOpenMatch`**: Cross-Screen-Callback ins MatchScreen.

### Loading / Error / Empty-States

- Filter ohne Treffer: aktuell zeigt Liste nichts, kein Empty-State im Kit.
- Bracket leer (Phase 1): nicht modelliert.
- AUDIT.md 4.2 flaggt Empty-State-Defizit auch hier.

### Spezifisch fuer diesen Screen

- **Konsolidierung**: 1 Mobile-Screen = Liste + Detail + Standings + Bracket + Match + Plan. Strategie: alles in einer Ansicht erreichbar, statt Deep-Navigation.
- **Hero ist tappable** (changes active) — aber zeigt aktuell `onClick={() => {}}`. Echte Impl muss aktives Tournament wechseln.
- **Bracket scrollt horizontal** — Mobile-Friendly Pattern.
- **Plan zeigt Next-Match prominent** mit wood-Inset-Border.

## Accessibility

- AppBar 48x48 ✅.
- FilterChip: 32dp — **unter 48dp**. Pruefen, ob Padding ausreicht.
- CTA: 50dp ✅.
- Tab-Btn: 32dp — **unter 48dp**.
- TableRow: ~30-40dp implicit — Daten-Row, Touch-Target sekundaer.
- Tile-Touch: implizit ueber Button, ~80dp.
- LiveBlink ohne `aria-label` — sollte als `Semantics(label: "Live")` markiert sein.

## Quality-Gate-Checkliste

- [x] Filter / Hero / Sub-Tabs / Weitere-Liste Pattern dokumentiert.
- [x] CTA-Switch je Status klar.
- [x] StatusTag-Varianten (upcoming/open/live/done) konsistent.
- [x] You-Row in Standings hervorgehoben.
- [x] Tabular-Nums auf allen Zahlen.
- [ ] **FilterChip + Tab-Btn 32dp** unter 48dp.
- [ ] **Empty-Filter-State** fehlt.
- [ ] **Konsolidierung** vs. **Einzel-Screens**: strategische Entscheidung erforderlich.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Strategische Entscheidung Konsolidierung**: Flutter hat ~15 Tournament-Screens. Mobile-Kit konsolidiert auf 1 Screen mit Sub-Tabs. **Optionen**:
   - A) Mobile-Screen als zusaetzliche Uebersicht, die zu den existierenden Detail-Screens deeplinkt (statt sie zu ersetzen).
   - B) Konsolidierung der Detail-Views (Standings, Bracket, MyMatch, Schedule) als Sub-Tabs eines einzelnen `TournamentDetailScreen`, plus separate Liste.
   - C) Vollkonsolidierung (radikal, vermutlich nicht praktikabel mit allen Edge-Flows wie Setup-Wizard, Override, Conflict).
2. **Bracket-Visualisierung**: M2-Task gemaess Memory-File. Mobile-Spec zeigt horizontal-scroll-Spalten — Flutter braucht eine eigene `BracketWidget`-Implementierung (CustomPainter oder Lib — ADR faellig).
3. **Standings-Tabelle** zeigt 6 Spalten: #, Team, S, N, Diff, Pkt. Flutter `tournament_standings_screen.dart` muss dieselbe Spalten-Layout abdecken; You-Highlight per `you`-Flag.
4. **Live-Badge mit Blink**: Pulsing-Animation. Flutter via `AnimatedOpacity` oder `RepaintBoundary` mit Timer.
5. **CHF 25 Anmelde-Gebuehr**: hartcodiert im Kit. Flutter muss das aus dem Tournament-Model ziehen (`fee_chf`).
6. **Filter `Anmelden`** kombiniert Status (`open` oder `upcoming && !registered`) — Flutter-Filter-Logik muss das spiegeln.
7. **Setup-Wizard nicht Teil der Mobile-Spec**: `tournament_setup_wizard.dart` ist eigener Flow (Organizer-Pfad). Mobile-Spec ist Spieler-Pfad.
8. **Conflict / Override nicht Teil der Mobile-Spec**: existieren in Flutter (`tournament_conflict_screen.dart`, `tournament_override_screen.dart`) und sind weiterhin als Deep-Routen erforderlich (siehe Memory: Conflict-Screen Wiring fehlt noch).
9. **`Tournament-Match Detail`** triggert ins MatchScreen via `onOpenMatch`. Pruefen, ob Match-Flow (siehe `mobile-match-screen.md`) den Tournament-Context kennt.
10. **Mock-Daten** im Kit (BKC Friday League, Marc & Vinz auf Rang 3 etc.) — sind Demo, nicht Spec. Echte Daten aus `TournamentRepository`.

**Sprint-Implikation**: Mobile-Spec ist **Polish-Pass** (AUDIT Empfehlung Punkt 6-7) — Konsolidierung der Tournament-Uebersicht nach M2-KO-Bracket Implementation. Strategische ADR ueber Konsolidierungs-Pfad faellig.
