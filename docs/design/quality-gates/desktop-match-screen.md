# Quality-Gate: Match (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/MatchScreen.jsx`
**Flutter-Pendant**: Match-Lobby/Live/Result als Phone-Screens (`lib/features/match/`) — Desktop-Layout FEHLT, Pitch-SVG ist neu
**Tablet/Desktop-Breakpoints**: ab 900 dp Pitch + Right-Column-Split; ab 1280 dp Full-Bleed Score-Strip
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur

Drei **Stages** ueber Stage-Switcher im TopBar-Right-Slot:
- `lobby` — Vor-Match
- `live` — Live-Match (Hauptszene)
- `result` — Nach-Match

#### Lobby
- Body `padding: 24px 32px 32px`, vertikales Layout (`gap: 20`).
- **Lobby-Teams-Block** (`grid-template-columns: 1fr auto 1fr`, gap 24, padding `28px 32px`, `border-radius: 20`, `background: --kc-bg-raised`, `box-shadow: --kc-shadow-1`):
  - Links: TeamCard (linksbuendig).
  - Mitte: VS-Block — `vs.` 64 px display, Meta `Best of 5 · 6 Stoecke` mono, Clock 34 px Meadow-600 (Start-Zeit), Sub `startet · Court 2`.
  - Rechts: TeamCard (rechtsbuendig).
- **TeamCard**: Avatar 80 dp rounded 20 (Team-Color), Team-Name 28 px display, Meta (ELO + Record mono 13 px), Form-Cells (`W`/`L` 22 × 22 dp, 5 px radius), Players-List (Mini-Rows mit Avatar 28 dp + Name + ELO), Ready-Tag mit Green-Dot.
- **Lobby-Grid** (`grid-template-columns: 1.2fr 1fr`, gap 18):
  - Direkter Vergleich (letzte 5 H2H) — Rows mit Date / Home / Score / Away / Win-Badge.
  - Match-Setup — 6 Setup-Rows (Format, Halbsatz-Limit, Heli-Tracking, Strafkubb-Regel, Court, Schiedsrichter) + 2 Buttons (Start, Setup anpassen).

#### Live
- **Score-Strip** (`grid-template-columns: 1fr auto 1fr`, gap 18, padding `18px 24px`, `border-radius: 18`, `background: --kc-stone-900`, color `--kc-chalk-50`):
  - Links: `ScoreSide` mit Avatar 52 dp + Name 22 px + Sub mono 11 px + Score 84 px.
  - Mitte: Halbsatz-Label mono + Time 32 px Wood-400 + State mono "laeuft".
  - Rechts: zweite `ScoreSide`.
- **Live-Split** (`grid-template-columns: 1.1fr 1fr`, gap 18):
  - **Links Pitch-Card**:
    - CardHeader Eyebrow `Wurffeld · Live-Status`, Title `Du wirfst · Stock 4 / 6`, Right-Tag `Aufstellung Standard`.
    - `Pitch` SVG (720 × 240): Pitch-Rect Meadow-50 BG mit Meadow-200 Border, gestrichelte Mittellinie, zwei Baselines, 6 Kubbs auf jeder Baseline (Knocked/Standing-Varianten), 2 Strafkubbs im Mittelfeld, Koenig zentral mit Kronen-Pfad.
    - Legend mit 4 Items (stehend, liegend, Strafkubb, Koenig).
  - **Rechts Right-Column** (Column, gap 16):
    - Counter-Card: Eyebrow `Stock`, Big `4/6` (96 px), Side-Mini-Rows (Stehend / Strafkubb / Koenig), Undo-Btn.
    - Action-Pad (2 × 2): Treffer / Miss / Heli / Strafe (Token-Tones, `border-radius: 14`, padding `18px 20px`, Label display 22 px + Sub 12 px).
    - Live-Throw-Log (Card padding 0): Eyebrow + Round-Tag, dann `ul` mit Rows (Idx mono + Type-Badge + Sub + Time, max-height 260 dp `overflow-y: auto`, Latest-Row mit Meadow-50 BG).
    - End-Row: Primary `Halbsatz beenden` + Ghost `Time-Out`.

#### Result
- Body `padding: 24px 32px 32px`, vertikales Layout.
- **Result-Hero** (Card padding 28):
  - Hero-Row (`display: flex; justify-content: center; gap: 28`): Winner-Side (Name 22 px + Score 160 px Meadow-600 + "SIEG"-Badge Meadow) + Colon 120 px + Loser-Side (opacity 0.55).
  - Result-Stats (`grid-template-columns: repeat(6, 1fr)`): 6 Stat-Cols (Treffer, Trefferrate, Heli erfolgreich, Strafkubbs, Schnellster Halbsatz, ELO-Bewegung) mit Home (Meadow-700 wenn besser) + `·` + Away.
- **Result-Split** (`grid-template-columns: 1.4fr 1fr`, gap 18):
  - Halbsatz-Verlauf — 5 Set-Cards (Won = Meadow-100, Lost = Stone-100, Label + Score 28 px + Time).
  - Liga-Tabelle Impact — 2 Rows (Marc & Vinz / United A) mit Rank + Team + Pkt-Veraenderung + Delta (up/down).
  - 3 Buttons: Primary `Zur Tabelle`, Default `Revanche`, Ghost `Match teilen`.

### Farben
- Score-Strip Dark-Mode (`--kc-stone-900` BG).
- ScoreAvatar: You = `--kc-meadow-600`, Other = `--kc-stone-900`.
- Time-Color Live: `--kc-wood-400`.
- Action-Tones: hit / miss / heli / penalty (Token-direkt).
- Log-Type-Tones: hit (Meadow-100/700), miss (Stone-100/Fg-Muted), heli (Wood-100/600), penalty (`#fae2e6` / `--kc-penalty`), king (`#fbe9c2` / `--kc-wood-600`).
- Result-Hero Winner-Score: 160 px Meadow-600. Loser: muted.

### Typografie
- Lobby VsBig: 64 px display. Score-Num live: 84 px ui weight 800. Result-Big: 160 px ui weight 800. Counter-Big: 96 px.
- TeamName: 28 px display opsz 72.
- Action-Label: 22 px display.
- Log-Sub: 13 px ui. Log-Time: 11 px mono.

### Spacing
- Lobby-Teams-Block gap 24, Lobby-Grid gap 18.
- Live-Split gap 18, Right-Column gap 16.
- Result-Stats gap 14, Set-Row gap 10.

### Border-Radius
- Score-Strip 18, Counter/Action-Cards 14 – 16, Set-Cards 12, Avatar-Boxes 14 – 20, Score-Avatar 14, Team-Avatar 20.

### Shadows
- Lobby-Teams-Block `--kc-shadow-1`, Action-Buttons `--kc-shadow-1`.

### Icons
- `DIcon.Target` (Match starten), `DIcon.Stop` (Halbsatz beenden), `DIcon.Pause` (Time-Out), `DIcon.Undo` (Letzten Wurf zurueck), `DIcon.Chevron` (Zur Tabelle).

## Komponenten-Inventar

- Shared: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `CardHeader`, `DIcon`.
- Lokal:
  - `Lobby`, `Live`, `Result` (drei Stages).
  - `TeamCard` (side-aware, Avatar + Name + Meta + Form + Players + Ready-Tag).
  - `SetupRow` (label + value + optional tone).
  - `ScoreSide` (live-score-side, you-prop fuer Highlight).
  - `Pitch` (SVG, 720 × 240, Pitch-Rect + Lines + Kubbs + Koenig).
  - `Kubb` (rect, knocked-Variante als flacher Stone-Rect, penalty/home Tones).
  - `ActionBtn` (label + sub + tone).
  - `Stat` (label + home + away + homeBetter-Flag).

**Unterschied Mobile**: 
- Mobile-`MatchScreen.jsx` (`docs/design/ui_kits/app/`) zeigt vermutlich keinen Pitch (Platzmangel), nur Counter + Action-Buttons. Throw-Log evtl. als Bottom-Sheet.
- Stage-Switch (Lobby/Live/Result) ist auf Phone eher eigene Routes — auf Desktop wird per Pill-Switcher umgeschaltet.
- TeamCards auf Phone sehr klein, auf Desktop riesig.
- Result-Hero mit 160 px Score-Number ist Desktop-Exclusive.

**Flutter-Aequivalente**:
- `Pitch` → `CustomPainter` (kein flutter_svg fuer interaktives Live-Update). Geschaetzt 100 – 150 LOC mit Tests.
- Stage-Switcher → `SegmentedButton` (Material 3) oder eigenes Pill-Widget.
- Action-Pad → `GridView.count(crossAxisCount: 2, childAspectRatio: 2.5)`.

## Interaktions-Pattern

- **Stage-Switch**: nur Demo-State im JSX. In Flutter ist es Server-driven (Match-Status: `pending` / `live` / `finished`). Switcher dann disabled wenn Status nicht erlaubt — oder nicht sichtbar.
- **Lobby Start-Button**: `PrimaryBtn "Match starten"` mit Target-Icon. Setzt Match-Status `live`.
- **Live Action-Buttons**: jede Aktion (Treffer / Miss / Heli / Strafe) erzeugt einen MatchEvent. Lamport-Clock, Sync ueber Supabase Realtime (kommt mit M4).
- **Live Undo**: nimmt letzten Event zurueck (Compensation-Event, kein Delete im Event-Log per ADR-0007).
- **Halbsatz beenden**: validiert Halbsatz-Ende-Bedingung (alle Basekubbs gefallen + Koenig getroffen, oder Strafkubb-Limit), schreibt `SetCompleted`-Event.
- **Result-Buttons**: Zur Tabelle navigiert zum Tournament-Standings, Revanche oeffnet neue Lobby mit gleichen Teams, Match teilen → Share-Sheet (Backlog).
- **Loading**: Pitch-Refresh mit Skeleton (alle Kubbs grau).
- **Error**: bei Sync-Konflikt → Toast + Conflict-Screen (siehe Tournament-Match-Conflict).
- **Empty**: Live-Log am Anfang leer → "Noch keine Wuerfe protokolliert" Hint.

## Accessibility

- **Tab-Order**: Stage-Switcher → Score-Strip (statisch) → Pitch-Card (statisch, evtl. fokussierbar) → Counter-Card → Action-Buttons (4 in Reading-Order) → Log (skip) → End-Row.
- **Focus-Ring**: zwingend auf Action-Buttons sichtbar.
- **Keyboard-Shortcuts** (Vorschlag, im Kit nicht modelliert): `1` Treffer, `2` Miss, `3` Heli, `4` Strafe, `Backspace` Undo.
- **Min-Window-Width**: 1280 dp damit Pitch + Right-Column gut nebeneinander passen. Darunter Stack-Layout (Pitch ueber Right-Column).
- **Kontrast Pitch-Labels**: SVG-Texte sind in `--kc-fg-muted` (Stone-500) auf Meadow-50 — pruefen, evtl. Stone-700.
- **Score-Strip Dark**: `--kc-chalk-50` auf `--kc-stone-900` ist sehr hoher Kontrast (16:1+), kein Problem.

## Quality-Gate-Checkliste

- [ ] Stage-Switch im TopBar-Right (3 Pill-Buttons).
- [ ] Lobby-Teams-Block 3-Col-Grid (Team / VS / Team) mit korrekten Avatar/Name/Form-Cells.
- [ ] H2H-Liste mit 5 Rows (Date / Home / Score / Away / Win-Badge).
- [ ] Setup-Card mit 6 Rows + Start + Setup-Anpassen-Buttons.
- [ ] Live Score-Strip Dark `--kc-stone-900` mit Score-Num 84 px tabular.
- [ ] Pitch-SVG 720 × 240, 12 Kubbs auf Baselines + 2 Strafkubbs + Koenig, Knocked/Standing-Toggle.
- [ ] Pitch-Legend mit 4 Items.
- [ ] Counter-Card mit Big 4/6 + Side-Rows (Stehend / Strafkubb / Koenig).
- [ ] Action-Pad 2 × 2 mit Token-Tones (hit / miss / heli / penalty).
- [ ] Live-Log mit Latest-Row Highlight + max-height 260 + scroll.
- [ ] Result-Hero mit Score 160 px + Loser muted.
- [ ] Result-Stats 6-Spalten mit homeBetter-Highlight.
- [ ] Set-Cards Won (Meadow) vs. Lost (Stone) klar getrennt.
- [ ] Liga-Impact-Block mit Pkt-Veraenderung.
- [ ] Alle Routes: tournament, restart-lobby, match-share.

## Implementations-Hinweise fuer Flutter

- **Pitch als CustomPainter**: das ist der grosse Move. Eigener `KubbPitchPainter` mit:
  - `Rect` fuer Pitch-BG.
  - `Path` fuer Mittellinie (dashed) + Baselines.
  - 12 Kubb-Rects (Knocked als flacher Stone, Standing als hoher Meadow-Square).
  - 2 Penalty-Kubbs im Mittelfeld.
  - Koenig als `Circle` + Krone-`Path`.
  - Hover/Tap-Hit-Test (`hitTest` overriden) damit User auf einzelne Kubbs tippen kann (Backlog: pro-Kubb-Status-Anzeige).
- **CustomPainter** ist die einzige sinnvolle Loesung — `flutter_svg` ist zu statisch fuer Live-Updates.
- **Stage-Switcher**: `SegmentedButton<MatchStage>` aus Material 3, Tones via Theme.
- **Live-Log**: `ListView.builder` mit `reverse: true`, latest-Item-Animation (`AnimatedContainer` mit Meadow-50 BG die nach 2 s fadet).
- **Score-Strip**: `Material(color: kcStone900)` + drei `Expanded`-Children.
- **State**: `matchControllerProvider` aus `lib/features/match/` muss erweitert werden um Throw-Log-Stream (Realtime). Lobby + Result existieren bereits, Live ist der grosse neue Screen.
- **Realtime**: blockiert auf M4 (Supabase Realtime, ADR pending). Bis dahin Demo-Daten oder Polling alle 2 s.
- **Pakete**: keine neuen. CustomPainter aus Standard-Flutter.
- **Komplexitaet**: **L**. 6 – 10 Tage. Hauptaufwand: Pitch-Painter + Live-Log + Realtime-Integration. Ohne Realtime: 5 – 6 Tage statisch lauffaehig.
