# Quality-Gate: Training (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/TrainingScreen.jsx`
**Flutter-Pendant**: Sniper/Finisseur als Phone-Screens (`lib/features/training/`) — Desktop-Live-Session FEHLT
**Tablet/Desktop-Breakpoints**: ab 900 dp Two-Column-Split (340 dp / flex); auf Phone bleibt bestehende Single-Column-View
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (Master/Detail)
- TopBar: Eyebrow `Sniper-Training · live` oder `Finisseur · live`, Title z.B. `8.0 m Distanz`, Subtitle mit Session-Status. Right-Slot mit `Undo / Pause-or-Blind / Stop` Actions.
- Body Split (`grid-template-columns: 340px 1fr`, gap 20, `padding: 24px 32px 32px`, height calc(100% - 130px)).
- **LEFT** (Aside, 340 dp, `overflow-y: auto`):
  - Card "Modus" — 2 Chips (Sniper / Finisseur), aktiv = `--kc-stone-900` Ink.
  - Card "Distanz" (Sniper) oder "Konfiguration" (Finisseur):
    - Sniper: Range-Slider 4 – 8 m step 0.5, 5 Tick-Labels darunter (aktive Distanz fett `--kc-fg`).
    - Finisseur: Chip-Row mit Configs (`7/3`, `5/5`, `10/0`, `3/5`, `Eigen…`) + Halbsatz-Limit Chips (`4`, `5`, `6`, `8`).
  - Card "Aktueller Lauf" — Strip aus 37 kleinen Cells (20 cols), Tone hit/miss/heli, plus Legend (3 farbige Dots).
- **RIGHT** (Main, flex):
  - Counter-Strip (`grid-template-columns: 1.6fr 1fr 1fr 1fr`, gap 14): Trefferrate (gross, 96 px) / Treffer / Miss / Heli (jeweils 72 px). Tones: hit `--kc-hit`, miss `--kc-miss`, heli `--kc-heli`, Heli muted wenn 0.
  - Optional "Verbleibend"-Bar: `noch X Wuerfe von Y` + Progress-Track 8 dp.
  - Optional "Hidden"-Hint Dark-Card mit Bell-Icon (Blind-Modus).
  - **Tap-Pad-Grid** (`grid-template-columns: repeat(3, 1fr)`, 2 Rows, gap 14): 3 grosse Plus-Buttons (`min-height: 160`, Treffer / Miss / Heli) + 3 kleine Minus-Buttons (`min-height: 80`, Ghost-Tone).
  - Foot-Row: Meta (Wuerfe / Minuten / Live-Quote in mono 13 px muted) + Pause + Abbrechen-Buttons.

### Farben
- Sniper-Mode: Action-Backgrounds `--kc-hit`, `--kc-miss`, `--kc-heli`. Counter-Vals farblich gleich.
- Hidden-Hint: `--kc-stone-900` Background, `--kc-chalk-50` Text.
- Modus-Chip Off: `--kc-bg-sunken`. On: `--kc-stone-900` + `--kc-chalk-50`.
- Chips: `--kc-bg-sunken` (off), `--kc-stone-900` (on).
- Progress-Fill: `--kc-meadow-500`.

### Typografie
- Counter-Big: 96 px ui weight 800 line-height 0.9 letter-spacing -0.04em tabular-nums.
- Counter-Small: 72 px ui.
- Counter-Unit (`%`): 24 px weight 600 muted.
- Pad-Big-Label: 28 px display weight 700 opsz 36.
- Pad-Sign (`+` / `−`): 64 px ui weight 800.
- Pad-Hint (kbd-Style): mono 11 px, opacity 0.8.

### Spacing
- Body-Padding `24px 32px 32px`, Split-Gap 20.
- Counter-Strip Padding `14px 20px`, Pad-Gap 14.
- Aside-Cards Padding 18.

### Border-Radius
- Counter-Cards 16, Pad-Buttons 18, Hidden-Hint 12, Progress-Track 999, Range-Tick implizit.

### Shadows
- Counter-Cards `--kc-shadow-1`, Pad-Buttons `--kc-shadow-1`.

### Icons
- `DIcon.Undo` (Letzten Wurf rueckgaengig), `DIcon.Pause`, `DIcon.Stop`, `DIcon.Target` (Sniper-Chip), `DIcon.King` (Finisseur-Chip), `DIcon.Bell` (Hidden-Hint).

## Komponenten-Inventar

- Shared: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `DIcon`.
- Lokal: `CounterCell` (Label + Big-Val + optional Unit), `PadCell` (Label + Hint + Sign + Tone-Switch).
- State (lokal): `mode`, `distance`, `target`, `hits`, `misses`, `helis`, `hidden`.

**Unterschied Mobile**: Mobile-`EightMScreen.jsx` zeigt vermutlich nur die Counter + 1-Tap-Pad, ohne Aside und ohne History-Strip. Desktop zeigt **alles gleichzeitig** — Konfig, History, Counter, Pad-Grid.

**Flutter-Aequivalente**: 
- Range-Slider → Material `Slider` mit Custom-Tick-Labels darunter (eigene `Row` mit `Text`s).
- History-Strip → einfaches `Wrap` oder `GridView.count(crossAxisCount: 20)` mit kleinen `Container`s.
- Tap-Pad → `GridView.builder` (3 × 2) mit `InkWell` + Token-Backgrounds.

## Interaktions-Pattern

- **Mouse-Click**: jeder Pad-Button registriert einen Wurf (+1) bzw. einen Undo (-1).
- **Keyboard**: laut `padHint` sind `space` / `1` fuer Treffer, `m` / `2` fuer Miss, `h` / `3` fuer Heli vorgesehen. **Pflicht-Implementierung** auf Desktop fuer schnelle Live-Eingabe.
- **Undo**: TopBar-Button + theoretisch `Ctrl+Z`.
- **Blind-Modus**: Toggle versteckt alle Live-Counter-Werte (`—`), zeigt Hidden-Hint-Dark-Card. Bleibt bis Session-Ende.
- **Pause**: hat keinen modellierten Effect im JSX — Backlog-Item.
- **Mode-Wechsel**: Wechsel zwischen Sniper / Finisseur sollte den laufenden Session-State wahrscheinlich resetten oder unterscheiden — im JSX nicht gesichert.
- **Loading**: Session-Save passiert nach jedem Wurf (siehe Phone-App), Loading nicht sichtbar.
- **Error**: keine Error-States modelliert.
- **Empty**: vor erstem Wurf zeigt Counter-Strip Nullen, "Verbleibend"-Bar `0 / target`.

## Accessibility

- **Tab-Order**: Modus-Chips → Distanz-Slider → Ziel-Chips → History (skip) → Counter (statisch) → Pad-Buttons (in Reading-Order) → Foot-Buttons.
- **Focus-Ring**: zwingend sichtbar — Pad-Buttons sind die primaere Interaktion, Keyboard-Nutzer brauchen klare Hervorhebung.
- **Min-Window-Width**: 1024 dp damit Aside-Cards lesbar und Pad-Buttons gross genug bleiben.
- **Keyboard-Hints in der UI**: `padHint` zeigt die Keys (`space · 1`, `m · 2`, `h · 3`). Tatsaechliche Tastatur-Listener muessen im Flutter-Pendant existieren (`Focus` + `RawKeyboardListener`).
- **Counter-Kontrast**: `--kc-hit` (Meadow-600) auf weiss ist AA, `--kc-heli` (Wood-400) auf weiss grenzwertig — Token-Sheet pruefen.

## Quality-Gate-Checkliste

- [ ] Two-Column-Split 340 / flex, Gap 20.
- [ ] Modus-Chips wechseln Aside-Card (Sniper Range-Slider vs. Finisseur Config-Chips).
- [ ] Range-Slider 4 – 8 m step 0.5, 5 Tick-Labels.
- [ ] History-Strip 20-Spalten-Grid, 3 Tones (hit/miss/heli).
- [ ] Counter-Strip 1.6/1/1/1, Big-Val 96 px Trefferrate, 72 px Sub-Counter.
- [ ] Verbleibend-Bar mit Progress-Track wenn `target` gesetzt.
- [ ] Hidden-Hint Dark-Card mit Bell + Hint-Text wenn blind.
- [ ] Pad-Grid 3 × 2, oben 3 Big-Pads mit Token-Tones, unten 3 Ghost-Minus.
- [ ] Keyboard-Shortcuts (`space`/`1` Hit, `m`/`2` Miss, `h`/`3` Heli, `Ctrl+Z` Undo).
- [ ] TopBar-Stop-Button schliesst Session und navigiert zu `summary`.
- [ ] Session-Save persistiert nach jedem Wurf (Drift, wie Phone-App).

## Implementations-Hinweise fuer Flutter

- **State**: bestehender `trainingSessionControllerProvider` aus `lib/features/training/` kann wiederverwendet werden — er kennt Sniper- und Finisseur-Sessions. Desktop ist eine andere View auf denselben State.
- **Layout**: `Row` mit `SizedBox(width: 340)` (Aside) + `Expanded` (Main). Main = `Column` aus Counter-Strip + Verbleibend + optional Hidden-Hint + Pad-Grid + Foot-Row.
- **Pad-Grid**: `GridView.count(crossAxisCount: 3, childAspectRatio: 2.0)` reicht; Big/Small-Height-Differenz ueber `aspectRatio` regeln oder manuell `Row` + `Expanded`.
- **Range-Slider**: Material `Slider` + Custom `SliderTheme` mit Token-Farben. Tick-Labels per `Row` darunter.
- **Keyboard-Listener**: `Focus` mit `onKeyEvent`, mappt Keys auf Provider-Actions.
- **History-Strip**: `Wrap` mit 20-Cell-Grid, jede Cell ein `Container` mit Tone-Farbe. Update nach jedem Wurf via Provider-Stream.
- **Komplexitaet**: **M**. 4 – 6 Tage. Hauptaufwand: Keyboard-Bindings + History-Strip + Range-Slider-Styling. Logic ist bereits in den Providern.
- **Pakete**: keine neuen. `flutter_riverpod` + Material 3 reichen.
