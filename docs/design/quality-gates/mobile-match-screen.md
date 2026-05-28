# Quality-Gate: Match (Live-Match Mobile) **NEU**

**Quelle**: `docs/design/ui_kits/app/MatchScreen.jsx` (NEU im Kit)
**Flutter-Pendant**: **FEHLT komplett als konsolidierter Tabbed-Screen.** Aktuell hat Flutter `match_lobby_screen.dart`, `match_config_screen.dart`, `match_result_screen.dart`, `match_await_others_screen.dart`, `match_finished_screen.dart` — fuenf einzelne Screens. Die Mobile-Spec konsolidiert das auf **einen Screen mit 3 Tab-Stages (Lobby / Live / Result)**.
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **AppBar**: Eyebrow + Title kontextabhaengig je Stage:
   - Lobby: `Match · Lobby` + `Marc & Vinz`
   - Live: `Match · LIVE` + `Halbsatz 4 / 5`
   - Result: `Match · Ergebnis` + `Sieg · 3:2`
   - Right-Slot: Stage-Switch-ChevronRight (Demo) — in Flutter durch echte Navigation ersetzen.
2. **Stage-Tabs** (Pill-Container `bg-sunken`, radius 999): `Lobby` / `Live` / `Ergebnis`. Aktiv = stone-900 + chalk-50.
3. **Body** (stagewise):
   - **Lobby**: Hero (Side A vs. Side B mit Avatars + Form-Row + ELO) + VS-Block (Big "vs.", Clock 20:15, Meta "Court 2 · BKC Friday") + Section "Direkter Vergleich" (h2h-Liste 3 Eintraege) + Section "Match-Setup" (4 Rows: Format / Heli-Tracking / Strafkubb / Court) + Start-Button.
   - **Live**: Score-Strip (Dark-Card stone-900 mit 2 Sides + Big-Score `2 : 1`) + Score-Meta ("Halbsatz 4 / 5" + "● LIVE · 4:12") + 4-Action-Pad (Treffer / Miss / Heli / Strafe) + Mini-Counters-Row (4 Mini-Cards) + Section "Per-Wurf Log · Halbsatz 4" + Log-Liste + End-Row mit 2 Buttons.
   - **Result**: Result-Hero (meadow-500 mit "Sieg · Best of 5" + Big-Score `3 : 2` + Teams + Meta) + Section "Halbsatz-Verlauf" (5 Set-Cards mit Win/Loss-Farbe) + Section "Statistik · du vs. Gegner" (StatRow-Liste) + Result-Actions (Revanche + Match teilen).

### Farben (Tokens)

| Element | Token |
|---|---|
| Stage-Tab-On | `--bk-stone-900` + chalk-50 |
| Stage-Tabs-Bg | `--bk-bg-sunken` |
| Side-Avatar (you) | `--bk-meadow-600` |
| Side-Avatar (opp) | `--bk-stone-900` |
| FormCell-Win | `--bk-meadow-500` + white |
| FormCell-Loss | `--bk-stone-200` + fg-muted |
| VS-Clock | `--bk-meadow-600` |
| H2H-Won-Tag | `--bk-meadow-100` + `--bk-meadow-700` |
| H2H-Lost-Tag | `--bk-stone-100` + `--bk-fg-muted` |
| StartBtn | `--bk-primary` (meadow-500) + chalk-50 |
| Live-Score-Strip-Bg | `--bk-stone-900` (dark inverse) |
| Score-Num (winning) | `--bk-meadow-500` (chalk-50 wenn dark-Strip) |
| Score-Colon | `--bk-stone-400` |
| LiveDot | `--bk-miss` (red) |
| Action-Hit | `--bk-hit` (#fff text) |
| Action-Miss | `--bk-miss` (#fff text) |
| Action-Heli | `--bk-heli` (stone-900 text) |
| Action-Penalty | `--bk-penalty` (#fff text) |
| Mini-Card-Bg | `--bk-bg-raised` |
| TAG-Hit | `meadow-100` + `meadow-700` |
| TAG-Miss | `stone-100` + `fg-muted` |
| TAG-Heli | `wood-100` + `wood-600` |
| TAG-Penalty | `#fae2e6` + `--bk-penalty` |
| LogRow-Latest-Bg | `--bk-meadow-50` |
| EndBtn-Primary | `--bk-primary` |
| EndBtn-Ghost | `transparent` + inset 1.5px line-strong |
| Result-Hero-Bg | `--bk-meadow-500` (chalk-50 text) |
| SetCard-Win | `--bk-meadow-100` + `--bk-meadow-700` |
| SetCard-Loss | `--bk-stone-100` + `--bk-fg-muted` |
| StatRow-Better | `--bk-meadow-700` weight 800 |

### Typografie

- StageTab: Display 12px weight 700.
- AppBar-Title: per BK.AppBar.
- SideName: Display 13px weight 700 tracking -0.01em.
- SideElo: Mono 10px fg-muted.
- VS-Big: Display 28px weight 700 tracking -0.03em.
- VS-Clock: Display 18px weight 800 `tabular-nums`.
- VS-Meta: Mono 9px fg-muted uppercase.
- H2H-Date: Mono 10px fg-muted.
- H2H-Score: Mono 12px weight 700.
- SetupVal: Display 13px weight 700.
- Score-Num: Display 44px weight 800 tracking -0.04em `tabular-nums`.
- Score-Colon: 30px weight 600.
- Score-Meta: Mono 10px uppercase.
- Action-Lbl: Display 20px weight 800 tracking -0.02em.
- Action-Plus: Display 36px weight 800 opacity 0.85.
- Mini-Lbl: 9px weight 600 uppercase fg-muted.
- Mini-Val: Display 20px weight 800 `tabular-nums`.
- LogIdx: Mono 10px fg-muted.
- LogTag: Mono 9px weight 700 tracking 0.06em uppercase.
- LogText: 12px weight 600 lineHeight 1.3.
- LogTime: Mono 10px fg-muted `tabular-nums`.
- Result-Big: Display 88px weight 800 tracking -0.05em lineHeight 0.85.
- Result-Eyebrow: 11px weight 700 uppercase tracking 0.1em.
- ResultMeta: Mono 10px opacity 0.8 uppercase.
- SetCard-Lbl: Mono 9px weight 600 uppercase.
- SetCard-Score: Display 20px weight 800 `tabular-nums`.
- StatVal: Display 14px `tabular-nums`.

### Spacing

- StageTabs: margin `4px 16px 12px`, padding 3, gap 4.
- LobbyHero: Grid `1fr auto 1fr` gap 6, padding `10px 16px 18px`.
- H2H-List: `margin 0 16px`, padding `2px 12px`, Inset-Card.
- H2H-Row: padding `10px 0`, Grid `52px 1fr 40px 36px` gap 8.
- SetupList: `margin 0 16px`, padding `2px 12px`.
- SetupRow: padding `12px 0`.
- StartBtn: margin `18px 16px 0`, minHeight 56.
- ScoreStrip: `margin 0 16px`, padding `10px 16px 4px`, Grid `1fr auto 1fr` gap 8.
- ScoreMeta: padding `6px 22px 10px`.
- ActionGrid: 2 cols gap 8, padding `0 16px 8px`.
- ActionBtn: minHeight 80.
- MiniCounters: 4 cols gap 6, padding `4px 16px 8px`.
- Mini: padding `8px 4px`, gap 2.
- Log: `margin 0 16px`, radius 14, Inset-Card.
- LogRow: padding `10px 12px`, Grid `34px 48px 1fr auto` gap 8.
- EndRow: padding `12px 16px 0`, gap 8.
- ResultHero: padding `20px 16px 18px`, margin `0 16px`, radius 18.
- SetRow: 5 cols gap 6, padding `0 16px`.
- SetCard: padding `10px 4px`, radius 10.
- StatsList: margin `0 16px`, padding `2px 12px`, Inset-Card.
- ResultActions: 2 cols gap 10, padding `14px 16px 0`.

### Border-Radius

- StageTabs: 999 + Inner 999.
- SideAvatar: 12.
- FormCell: 3.
- Hero/Tile: 14 / 18.
- ScoreAvatar: 8.
- ScoreStrip: 14.
- ActionBtn: 16.
- Mini: 10.
- LogRow-Latest: 8.
- ResultHero: 18.
- SetCard: 10.
- EndBtn: 14 / 12 (Ghost).
- EndBtnGhost: 12.

### Shadows

- Hero: `var(--bk-shadow-1)`.
- ActionBtn: `var(--bk-shadow-1)`.

### Icons

- `Icon.Back` (AppBar).
- `Icon.ChevronRight` (StageBtn Demo).
- Keine in Action-Pad (text-only buttons).

### Brand-Elemente

- **Liquid-Glass-ScoreStrip** in Live-Stage: dunkle Inset-Card mit stone-900-Bg simuliert ein Score-Board.
- **ResultHero** in meadow-500 als "Sieg-Card" — emotional positiv.

## Komponenten-Inventar

- `MatchScreen` — Hauptkomponente mit Stage-Tab-State.
- `Lobby` — Lobby-Body.
- `Live` — Live-Body.
- `Result` — Result-Body.
- `Side` — Team-Side-Card (Avatar + Name + ELO + Form).
- `SetupRow` — Setup-Row.
- `Action` — Action-Pad-Button.
- `Mini` — Mini-Counter-Card.
- `StatRow` — Vergleichs-Stat-Zeile.
- Konstante `TAG` — Mapping fuer Log-Tag-Farben.

## Interaktions-Pattern

- **`stage`-State**: `'lobby'` | `'live'` | `'result'`.
- **Stage-Tab-Switch**: setzt Stage direkt.
- **`onStart` (Lobby)**: → Live.
- **`onFinish` (Live)**: → Result.
- **`onRestart` (Result)**: → Lobby.
- **`onOpenMatch`** (Cross-Screen) ist Prop des MatchScreens; ruft ins Live rein.

### Loading / Error / Empty-States

- Mock-Daten im Kit fuer alle Stages.
- Echte Impl muss:
  - Lobby: warten bis beide Sides verbunden (siehe `match_await_others_screen.dart`)
  - Live: Offline-Indicator, Sync-State, Konflikt-Resolution
  - Result: Daten aus Match-Domain laden

### Spezifisch fuer diesen Screen

- **Konsolidierung von 5 Flutter-Screens** in 1 Mobile-Spec mit 3 Tabs. **Designer-Intent**: weniger Navigation, mehr Stage-Awareness.
- **Action-Pad** ist 4 grosse Tap-Targets (Treffer / Miss / Heli / Strafe). Vergleichbar mit Sniper-Screen, aber inkl. Strafkubb.
- **Per-Wurf-Log** mit Inverse-Highlight fuer den neuesten Eintrag (LogRowLatest in meadow-50).
- **H2H-Verlauf** ist neu — zeigt direkte Begegnungen mit Win/Loss-Tag.
- **Live-Score-Strip** ist dunkler Block (stone-900) — bewusster Kontrast zu der hellen App.
- **Result-Hero** in meadow-500 als "Sieger-Card".

## Accessibility

- AppBar 48x48 ✅.
- StageTab: 34dp — **unter 48dp**.
- StartBtn: 56dp ✅.
- ActionBtn: 80dp ✅.
- EndBtn: 54dp / EndBtnGhost: 48dp ✅.
- LogRow-Touch: passiv, aber Tap-Handler waeren denkbar (Wurf-Edit).
- Aria-Labels fehlen weitgehend — Flutter sollte das ueber Semantics nachholen.

## Quality-Gate-Checkliste

- [x] 3 Stages (Lobby / Live / Result) konsolidiert.
- [x] Action-Pad mit 4 Tones (hit/miss/heli/penalty).
- [x] Per-Wurf-Log Pattern definiert.
- [x] H2H + Setup + Standings im Lobby explizit.
- [x] Result-Hero Win/Loss-Variant.
- [ ] **Flutter-Pendant ist 5 Einzel-Screens** — Konsolidierung steht an.
- [ ] **Offline / Sync-Indicator** im Live fehlt im Spec.
- [ ] **Strafe-Button** im Action-Pad ist neu — pruefen, ob Flutter bisher Strafkubb erfassen kann.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **5 → 1 Screen-Konsolidierung**: derzeit hat Flutter die Stages als separate Routen (`/match/config`, `/match/lobby`, `/match/result`, `/match/await-others`, `/match/finished`). Spec sagt: konsolidiert ein Match-Screen mit Stage-Switching. **Strategische Entscheidung erforderlich**: tatsaechlich konsolidieren oder die Stages als Sub-Routen behalten und nur das visuelle Pattern (Stage-Tabs) hinzufuegen?
2. **Action-Pad mit 4 Buttons**: in Flutter typischerweise via `Wrap` / `Grid`. Tones via `KubbTokens.hit/miss/heli/penalty`.
3. **Live-Score-Strip in stone-900**: dunkler Block in heller App — erfordert bewusstes Theme-Handling.
4. **Per-Wurf-Log mit Tags** (TREF/MISS/HELI/STRAF): braucht Match-Event-Model im `match/`-Bounded-Context. Pruefen, ob `MatchEvent`-Stream das schon liefert (laut Memory: `watchMatch(matchId)` ist `Stream.empty()` auf allen Impls — kommt mit M4).
5. **H2H-Verlauf**: erfordert Cross-Match-Aggregat. Pruefen, ob die Tournament-RPCs das liefern oder ob eigener Stats-Query noetig.
6. **ResultHero-`Sieg · Best of 5`**: dynamisch je Format. Flutter sollte das ueber `Match.format` mappen.
7. **Setup-Row mit `Heli-Tracking: ja`**: zeigt Match-Settings. Pruefen, ob Match-Config diese Flags hat.
8. **Stage-Switch ohne Persistenz**: das Kit hat lokalen useState. Echte Impl muss Server-State (oder Lokal-State mit Sync) respektieren.

**Sprint-Implikation** (per AUDIT.md Punkt 6): Match-Flow (Lobby → Live → Result) designen — Mobile-Kit liefert hier die Spec. **Naechster Schritt**: Flutter-Variante als neuer `MatchScreen` mit Tab-Stages oder via Router-Restructuring.
