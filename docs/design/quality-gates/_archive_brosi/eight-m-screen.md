# Quality-Gate: Sniper-Training (8m-Ticker)

**Quelle**: docs/design/ui_kits/app/EightMScreen.jsx (`window.SniperTrainingScreen` / kompatibler Alias `EightMScreen`)
**Flutter-Pendant**: lib/features/training/presentation/sniper_session_screen.dart (live Session) und lib/features/training/presentation/sniper_config_screen.dart (Distanz/Ziel-Setup)
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (top-down)

1. **AppBar** (gemeinsamer `AppBar` aus `shared.jsx`)
   - Back-Button links (48x48 Tap-Target)
   - Eyebrow `Sniper-Training` (uppercase, letter-spacing 0.08em, 11px)
   - Title: aktuelle Distanz `${distance.toFixed(1)} m` als grosse Display-Zahl (28px, font-weight 800, tabular-nums, letter-spacing -0.02em)
   - Rechts: Eye-Toggle (`Icon.Eye` / `Icon.EyeOff`) und Settings-Icon (`Icon.Settings`)
2. **Counter-Strip**: 3 gleichbreite Spalten (grid `repeat(3, 1fr)`, gap 8) mit Treffer / Miss / Heli; bei `hideMade=true` werden die Werte mit `—` gemaskt und `fgSubtle`-eingefärbt, Heli-Counter im Default-State mit `opacity: 0.45` wenn `helis === 0`
3. **Remaining-Zeile** (nur wenn `target` gesetzt): zentriert, baseline-aligned `noch <38 in Display-Font> Würfe · von 50`
4. **Hidden-Hint** (nur bei `hideMade=true`): kleine Zeile mit `EyeOff`-Icon, "Trefferzahl verdeckt — du wirfst blind."
5. **Tap-Pad-Grid**: 2-Spalten Grid `1fr 1fr` (gap 10, padding 18px 16px 12px), `alignContent: center`, `flex: 1`. 6 Buttons in der Reihenfolge: Hit +, Hit −, Miss +, Miss −, Heli +, Heli −
6. **End-Button**: "Session beenden" — Textlink mit Underline, kein Container, `fgMuted`

### Farben (aus Tokens)

| Verwendung | CSS-Token | KubbTokens |
|---|---|---|
| Bildschirm-Hintergrund | `--bk-bg` | `tokens.bg` (chalk50 hell, stone900 dark) |
| Pad-Container hinter Ghost | `--bk-bg-raised` | `tokens.bgRaised` |
| Hit-Pad-Fläche, Hit-Counter | `--bk-hit` | `KubbTokens.hit` = `#2D6324` (meadow600) |
| Miss-Pad-Fläche, Miss-Counter | `--bk-miss` | `KubbTokens.miss` = `#B73A2A` |
| Heli-Pad-Fläche, Heli-Counter | `--bk-heli` | `KubbTokens.heli` = `#C08A33` (wood400) |
| Pad-Text (Hit/Miss) | `#fff` | hartcodiert `#fff` |
| Pad-Text (Heli) | `--bk-stone-900` | `KubbTokens.stone900` |
| Ghost-Pad Border | `--bk-line` | `tokens.line` |
| Gedimmt / Eyebrow / Counter-Label | `--bk-fg-muted` | `tokens.fgMuted` |
| Gemaskter Wert | `--bk-fg-subtle` | `tokens.fgSubtle` |
| Sheet-Backdrop | `rgba(12,11,7,0.45)` | direkt `stone900` mit 45% Opacity |

### Typografie

| Bereich | Font | Grösse | Weight | Sonderregeln |
|---|---|---|---|---|
| AppBar Eyebrow | body | 11px | 600 | uppercase, letter-spacing 0.08em |
| AppBar Distanz-Title | display | 28px | 800 | line-height 1, letter-spacing -0.02em, tabular-nums |
| Counter-Label | body | 11px | 600 | uppercase, letter-spacing 0.08em |
| Counter-Value | display | 38px | 800 | line-height 1, letter-spacing -0.03em, tabular-nums |
| Remaining-Begleittext | body | 14px | 400 | baseline-aligned |
| Remaining-Zahl | display | 34px | 800 | letter-spacing -0.02em, tabular-nums |
| Pad-Label | display | 20px | 700 | — |
| Pad-Sign (+/−) | display | 36px | 800 | line-height 1 |
| End-Button | display | 15px | 600 | underline, underline-offset 4px |
| Sheet-Title | display | 22px | 700 | letter-spacing -0.02em |
| Field-Value (Sheet) | display | 22px | 700 | tabular-nums |
| Tick-Marks (Distanz-Slider) | mono | 11px | — | — |

### Spacing

- Counter-Strip Padding: `10px 16px 4px` (top/bottom mit `space2`/`space3`-Nuancen, horizontal `space4`)
- Pad-Grid Padding: `18px 16px 12px`, Gap 10px (zwischen `space2` und `space3`)
- Remaining-Zeile Padding: `12px 16px 0`
- End-Button Margin: `0 16px 16px` (`space4`)
- Settings-Sheet Padding: `10px 18px 32px`
- Sheet-Gap zwischen Feldern: 10px

### Border-Radius

- Pad-Buttons: 18px (nicht in KubbTokens — eigene Konstante, am nächsten zu `radiusXl`=16)
- Icon-Buttons in AppBar: 12px (`radiusLg`)
- Settings-Sheet Top-Corners: 24px (kein direkter Token-Match)
- Sheet-Grabber: 999 (`radiusPill`)
- Target-Chips: 999 (`radiusPill`)
- Apply-Button: 14px (kein direkter Token-Match)

### Shadows

- Keine Box-Shadows auf Pads (flat Design)
- Ghost-Pad nutzt `inset 0 0 0 2px var(--bk-line)` als Border-Ersatz
- Sheet hat keinen expliziten Shadow, lebt nur vom Backdrop

### Icons (Lucide-Äquivalente)

| Design (`shared.jsx`) | Lucide-Icon (Flutter) | Grösse |
|---|---|---|
| `Icon.Back` | `LucideIcons.arrowLeft` | 22px |
| `Icon.Eye` | `LucideIcons.eye` | 22px |
| `Icon.EyeOff` | `LucideIcons.eyeOff` | 22px |
| `Icon.Settings` | `LucideIcons.settings` | 22px |
| `Icon.Close` | `LucideIcons.x` | 22px |

### Trainings-spezifisch

- **Hit-Pad-Layout**: 2 Spalten x 3 Reihen (Hit+/Hit-, Miss+/Miss-, Heli+/Heli-). Tap-Targets 84px Mindesthöhe — deutlich über den 48dp WCAG-Floor.
- **Streak-Indikator**: im Design **nicht vorhanden**, nur Treffer / Miss / Heli-Counter und "noch X Würfe"-Anzeige. Streaks tauchen erst im Summary-Screen auf.
- **Distanz-Slider**: lebt im `SettingsSheet` (Bottom-Sheet), Range 4.0–8.0 in 0.5er-Schritten, Tickmarks `4.0 5.0 6.0 7.0 8.0` mono-spaced. Aktiver Wert eingefärbt in `fg`, andere `fgMuted`.
- **King-Throw**: nicht Teil des Sniper-Screens (gehört zum Finisseur).
- **Eye-Toggle (Hide-Made)**: blendet Counter-Werte aus, behält Distanz und Remaining sichtbar. "Blind-Training"-Modus.

## Komponenten-Inventar

- `SniperTrainingScreen` — Top-Level
- `AppBar` (aus `shared.jsx`)
- `Stat` (lokal) — Counter-Zelle mit `tone` (hit/miss/heli)
- `PadButton` (lokal) — Tap-Pad mit `tone` (hit/miss/heli/ghost)
- `SettingsSheet` (lokal) — Distanz-Slider + Ziel-Chips
- `Icon.*` (aus `shared.jsx`)

In Flutter umgesetzt durch:
- `KubbAppBar` (`lib/core/ui/widgets/kubb_app_bar.dart`)
- `KubbCounter` (`lib/core/ui/widgets/kubb_counter.dart`)
- `KubbTapPad` (`lib/core/ui/widgets/kubb_tap_pad.dart`)
- `SniperConfigScreen` als eigener Screen statt Bottom-Sheet

## Interaktions-Pattern

- **1-Tap-Eingabe**: Jeder Wurf ist ein einzelner Pad-Tap. Hit/Miss/Heli getrennt — kein Mode-Switch nötig.
- **Undo via Minus-Pad**: nicht Long-Press, sondern separater `−`-Button pro Kategorie. Symmetrie zum `+`-Pad.
- **Doppel-Tap-Race**: Im JSX nur via `navigator.vibrate(8)` ohne Lock — Flutter-Pendant `ActiveSessionNotifier._serialize` bietet In-Flight-Lock pro Mutation (Pad-Tap blockt nachfolgende Taps bis DB-Write zurück). Lock wird vom Notifier intern gehalten, der `KubbTapPad` selber zeigt das im Default noch nicht visuell.
- **Tap-Feedback**: Haptic `navigator.vibrate(8)` im Design; Flutter nutzt `HapticFeedback.lightImpact()` aus `flutter/services.dart`, einstellbar via `AppSettings.vibration`.
- **Settings-Sheet**: Tap auf Backdrop schliesst; Apply-Button übernimmt und schliesst. In Flutter ist das aktuell ein eigener Screen (`SniperConfigScreen`), das Sheet-Pattern existiert noch nicht.
- **Session-Lifecycle**: Start → Live (Pad-Eingabe) → "Session beenden" → Summary. Flutter zusätzlich: "Abbrechen"-Pfad mit `AbortDialog`, Crash-Recovery via `crash_recovery_provider`.
- **Empty/Loading**: Beim Erstaufruf der Flutter-Session zeigt `CircularProgressIndicator`, bis `activeSessionProvider` einen Wert liefert (`session == null`).
- **Error-State**: kein expliziter Error-State im Design; Flutter zeigt aktuell nur Loading-Spinner.
- **Eye-Toggle persistiert**: im JSX lokal pro Screen-Instanz, in Flutter über `appSettingsProvider.sniperEyeToggleHidden` Session-übergreifend.

## Accessibility-Hinweise

- **Outdoor-Kontrast**: Pad-Farben (`hit` #2D6324 auf weissem Text, `miss` #B73A2A auf weiss, `heli` #C08A33 auf stone900-Text) sind ausreichend kontrastreich für sonnenlesbar. Das High-Contrast-Theme (`KubbTokens.highContrast`) hebt Primary auf `#0F4A08` mit reinem Schwarz für Linien.
- **Touch-Target am Pitch**: Pads sind 84px hoch (`minHeight: 84`) — deutlich über `touchComfortable` (64px) und WCAG (48px). Wichtig: in Flutter aktuell `childAspectRatio: 2.2` im `GridView.count` → bei schmaleren Phones potenziell unterhalb 84px Höhe.
- **Mask-Mode**: bei `hideMade=true` ist die Maske als `—` mit `fgSubtle` gerendert. Stellt sicher dass keine Hit-Information ausserhalb des Toggles leakt.
- **Aria-Labels**: Eye-Toggle hat `aria-pressed`, Settings-Icon hat `aria-label="Einstellungen"`. In Flutter via `Tooltip` und `IconButton.tooltip` umgesetzt.

## Quality-Gate-Checkliste

- [ ] Layout-Struktur 1:1 (AppBar → Counter-Strip → Remaining → Hint → Pad-Grid → End-Button)
- [ ] Pad-Reihenfolge: Hit+, Hit−, Miss+, Miss−, Heli+, Heli− (2-spaltig)
- [ ] Pad-Höhe >= 84px (Design-Vorgabe), Mindestens `touchComfortable` (64px)
- [ ] Pad-Farben aus `KubbTokens.hit/miss/heli`, kein hartcodierter Hex
- [ ] Counter-Value 38px display, tabular-nums, Farbe je nach Tone
- [ ] Counter im Default Heli muted bei `helis == 0` (opacity 0.45)
- [ ] Eye-Toggle maskiert Counter mit `—` und färbt `fgSubtle`
- [ ] Eye-Toggle persistiert via `appSettingsProvider`
- [ ] Remaining-Zeile nur sichtbar wenn `throwTarget != null`
- [ ] Hidden-Hint Text "Trefferzahl verdeckt — du wirfst blind." aus AppLocalizations
- [ ] Distanz-Format `${distance.toStringAsFixed(1)} m`
- [ ] Distanz-Slider 4.0–8.0 in 0.5er-Schritten (Flutter: divisions=8 auf Range 4..8)
- [ ] Ziel-Presets `[null, 25, 50, 100, 200]`, ∞ für null
- [ ] Tap-Feedback via `HapticFeedback.lightImpact()`, einstellbar
- [ ] In-Flight-Lock im `ActiveSessionNotifier` greift bei Doppel-Tap
- [ ] Undo via Minus-Pad funktioniert (keine Long-Press-Geste)
- [ ] Session-Ende-Pfad: Tap "Session beenden" → `complete()` → Summary-Screen
- [ ] Abort-Pfad: System-Back oder Abort-Dialog → `abortAndDelete()` → Config-Screen
- [ ] Crash-Recovery: `resumeFromCrash(sessionId)` rehydriert aus drift
- [ ] i18n: alle Strings via `AppLocalizations` (`sniperConfigEyebrow`, `sniperCounterHit/Miss/Heli`, `sniperRemaining`, `sniperBlindHint`, `sniperEndButton`, `sniperAbortButton`)
- [ ] Domain-Begriffe deutsch: "Treffer", "Miss", "Heli", "Wurf", "Sniper-Training", "Sniper" als Eigenname
- [ ] Counter-Strip respektiert `settings.heliTracking` (Heli-Spalte ausblendbar)
- [ ] Settings-Eintrag in AppBar führt entweder zum Sheet (Design) oder zum Config-Screen (Flutter aktuell)

## Bekannte Abweichungen (Flutter aktuell vs. Design)

1. **Settings als eigener Screen statt Bottom-Sheet**: Das Design zeigt Distanz und Ziel-Würfe in einem `SettingsSheet` (Bottom-Sheet) während der Live-Session. Flutter routet stattdessen zurück auf `SniperConfigScreen` als eigenen Screen vor Session-Start. Mid-Session-Anpassung der Distanz ist aktuell nicht möglich.
2. **Pad-Grid `childAspectRatio: 2.2`** statt fixer Mindesthöhe 84px: bei Phones unter ca 380dp Breite kann die Pad-Höhe unter 84 fallen. Design sieht hartes `minHeight:84` vor.
3. **Ziel-Eingabe**: Design zeigt nur Preset-Chips `[null, 25, 50, 100, 200]`. Flutter ergänzt ein freies Number-Input via `TextField`. Erweiterung, keine Abweichung in die andere Richtung.
4. **Heli-Counter im Default-State**: Design dimmt `helis === 0` auf `opacity:0.45` — die Flutter-`KubbCounter`-Komponente bekommt zwar ein `muted`-Flag, müsste auf identische Opacity geprüft werden.
5. **Border-Radius der Pads**: Design 18px, Flutter wahrscheinlich `radiusXl` (16) oder anders gerundet — Audit nötig.
6. **End-Button im Design ein Textlink mit Underline**, in Flutter aktuell `TextButton` ohne explizite Underline-Style.
7. **Abort-Pfad**: Flutter hat einen separaten `TextButton` "Abort" mit `AbortDialog`, im Design gibt es nur "Session beenden". Erweiterung in Flutter.
8. **Sticky-AppBar**: `AppBar`-Komponente unterstützt `sticky` Prop, Sniper-Screen nutzt es im Design nicht. Flutter verwendet Standard `Scaffold.appBar` (de facto sticky).
