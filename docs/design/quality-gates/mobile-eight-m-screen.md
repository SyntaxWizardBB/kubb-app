# Quality-Gate: Sniper-Training (8m-Modus, Mobile)

**Quelle**: `docs/design/ui_kits/app/EightMScreen.jsx` (Komponente: `SniperTrainingScreen`; Window-Alias: `EightMScreen` fuer Backward-Compat)
**Flutter-Pendant**: `lib/features/training/presentation/sniper_session_screen.dart` (+ `sniper_config_screen.dart`)
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **AppBar**: Eyebrow `Sniper-Training`, Title `{distance.toFixed(1)} m` (z.B. `8.0 m`), Back-Button, Right-Slot mit zwei Buttons:
   - **Eye-Toggle** (`Icon.Eye` / `Icon.EyeOff`) — blendet Treffer/Miss/Heli aus (User wirft "blind"). NEU im Kit.
   - **Settings-Icon** (`Icon.Settings`) — oeffnet Settings-Sheet.
2. **Counter-Strip**: Grid 3 Spalten — Treffer (hit) / Miss (miss) / Heli (heli). Bei `hideMade=true` zeigen alle drei `—` in `fg-subtle`.
3. **Remaining-Block** (wenn `target` gesetzt): "noch [N] Wuerfe · von [target]". `remainingNum` ist Display 34px.
4. **Hidden-Hint** (wenn `hideMade=true`): Eye-Off-Icon + "Trefferzahl verdeckt — du wirfst blind."
5. **Pad-Grid**: 2 Spalten, 6 Buttons:
   - Hit + / Hit − (ghost)
   - Miss + / Miss − (ghost)
   - Heli + / Heli − (ghost)
6. **End-Button** (Text-Link-Style, underlined): "Session beenden".
7. **Settings-Sheet** (modal): Distanz-Slider 4–8m step 0.5 + Ziel-Wurfzahl-Chips (∞ / 25 / 50 / 100 / 200).

### Farben (Tokens)

| Element | Token | Hex |
|---|---|---|
| Hit-Pad | `--bk-hit` | meadow-600 #2D6324 |
| Miss-Pad | `--bk-miss` | #B73A2A |
| Heli-Pad | `--bk-heli` | wood-400 #C08A33 (text auf stone-900) |
| Ghost-Pad | `--bk-bg-raised` + `inset 0 0 0 2px line` | — |
| Counter-Strip-Hit-Val | `--bk-hit` | — |
| Counter-Strip-Miss-Val | `--bk-miss` | — |
| Counter-Strip-Heli-Val | `--bk-heli` | (muted wenn helis=0) |
| Masked-Val | `--bk-fg-subtle` | stone-400 |
| Apply-Btn | `--bk-primary` | meadow-500 |
| Target-Chip-On | `--bk-stone-900` | #0C0B07 |
| Target-Chip-Off | `--bk-bg-sunken` | chalk-100 |

### Typografie

- AppBar-Title (Distance): Display 28px weight 800, tracking -0.02em, `tabular-nums`.
- Stat-Label: 11px weight 600 uppercase tracking 0.08em.
- Stat-Value: Display 38px weight 800 `tabular-nums` lineHeight 1.
- Remaining: 14px Body + Display 34px `tabular-nums` weight 800.
- Pad-Label: Display 20px weight 700.
- Pad-Sign: Display 36px weight 800.
- Field-Value (Sheet): Display 22px weight 700.
- Tick-Labels: Mono 11px.

### Spacing

- Counter-Strip: `padding 10px 16px 4px`, gap 8.
- Remaining: `padding 12px 16px 0`, gap 10.
- Pad-Grid: `padding 18px 16px 12px`, gap 10, `flex:1, alignContent:center`.
- End-Btn: `margin 0 16px 16px`, minHeight 48.
- Sheet: top-radius 24, padding `10px 18px 32px`.

### Border-Radius

- Pad-Button: 18px
- End-Btn: 12px
- Sheet: top-radius 24px
- Target-Chip: 999px (pill)
- Apply-Btn: 14px
- Stepper-Value/Btn: 14px (im Settings-Sheet)

### Shadows

- Pad-Buttons: kein Shadow (flach, farb-basiert).
- Sheet: kein expliziter Shadow (Backdrop trennt visuell).

### Icons

- `Icon.Eye` / `Icon.EyeOff` (22px) — Hide-Made-Toggle.
- `Icon.Settings` (22px) — Settings-Trigger.
- `Icon.Back` (22px) — AppBar-Back.
- `Icon.Close` (22px) — Sheet-Close.

### Brand-Elemente

Keine Brand-Glyphen — alles funktionale Icons.

## Komponenten-Inventar

- `SniperTrainingScreen` — Haupt-Komponente, exportiert auch als `EightMScreen` (legacy).
- `Stat` — eine Spalte in der Counter-Strip (label + value, masked-Support).
- `PadButton` — ein Tap-Pad (Label + Sign + tone-Color).
- `SettingsSheet` — Distanz-Slider + Ziel-Chips.
- Importiert: `BK.Icon, BK.AppBar`.

## Interaktions-Pattern

- **`tap(setter, delta, min=0)`**: Curry-Pattern; bei jedem Tap +/- 1 auf den Counter, optional Vibration via `navigator.vibrate(8)`.
- **Eye-Toggle**: setzt `hideMade` State. Counter-Strip zeigt `—`, Remaining bleibt sichtbar.
- **Settings-Sheet**: lokaler State `d` (distance) + `t` (target) wird beim `Übernehmen`-Tap propagiert.
- **Distance-Range-Slider**: `min=4, max=8, step=0.5`. Tick-Row darunter zeigt 4.0, 5.0, 6.0, 7.0, 8.0 — aktiver Wert als `--bk-fg`, andere als `--bk-fg-muted`.
- **Target-Chips**: `null` (∞) / 25 / 50 / 100 / 200. Aktiver Chip ist `stone-900` + chalk-50-Text.
- **Vibration**: nur wenn `navigator.vibrate` verfuegbar. Flutter-Pendant: `HapticFeedback.lightImpact()`.

### Loading / Error / Empty-States

- Keine Loading-States — alles lokaler State, kein async.
- Empty-State entfaellt (Counter starten bei 0 oder Mock-Werten).

### Spezifisch fuer diesen Screen

- **Eye-Toggle ist neu im Mobile-Kit**. Use-Case: User will mental rechnen, ohne dass die laufenden Counter ihn beeinflussen.
- **Heli-Counter ist immer sichtbar**, aber `opacity 0.45` wenn 0 (`muted`).
- **Distance bleibt im AppBar-Title** sichtbar, auch wenn der Eye-Toggle die Counter ausblendet — Spec ist explizit: "Distanz, eingestellte Zielzahl und remaining bleiben sichtbar".
- **End-Button** ist Text-Link-Style (unterstrichen, kein Hintergrund) — bewusst zurueckhaltend, damit User nicht versehentlich beendet.

## Accessibility

- Eye-Toggle: `aria-pressed={hideMade}`, dynamisches `aria-label` ("Treffer einblenden" / "Treffer ausblenden").
- Settings-Button: `aria-label="Einstellungen"`.
- Touch-Targets: Pad-Buttons sind `minHeight:84` (deutlich ueber 48dp), Icon-Buttons 48x48.
- Tabular-Nums auf allen Zaehlern und Remaining ✅.
- Slider hat keinen `aria-label` im Kit — sollte in Flutter via `Semantics(label: "Distanz")` ergaenzt werden.

## Quality-Gate-Checkliste

- [x] Layout dokumentiert.
- [x] Tones (hit/miss/heli) konsistent.
- [x] Eye-Toggle neu definiert mit aria-pressed.
- [x] Touch-Targets ≥ 48dp (Pads sogar 84).
- [x] Tabular-Nums auf Counter und Remaining.
- [ ] **Eye-Toggle** in Flutter — pruefen, ob im Sniper-Screen vorhanden oder neu zu bauen.
- [ ] **Multi-Distance-Session**: das Kit zeigt eine einzelne Distanz pro Session. SummaryScreen hat aber Multi-Distance-Breakdown — pruefen, wie der Wechsel der Distanz mitten in einer Session ablaeuft (vermutlich: Distanz-Aenderung startet implizit eine neue Distanz-Phase innerhalb derselben Session).

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Eye-Toggle (`hideMade`)** ist neu im Mobile-Kit. Flutter-`sniper_session_screen.dart` hat das vermutlich nicht — Implementierung erforderlich.
2. **Pad-Layout**: Mobile-Kit hat 2 Spalten × 3 Reihen (Hit+/Hit-, Miss+/Miss-, Heli+/Heli-). Flutter-Variante koennte abweichen (z.B. Hit/Miss/Heli + Long-Press fuer Decrement).
3. **Target-Chips** im Settings-Sheet: 5 Optionen inkl. `∞`. Flutter sollte denselben Set anbieten.
4. **Distance-Slider** Range 4–8 m, step 0.5. Pruefen, ob Flutter denselben Range nutzt.
5. **End-Button** unterstrichen statt solid — Flutter koennte einen prominenten Button haben. Mobile-Kit ist explizit zurueckhaltend.
6. **`navigator.vibrate(8)`** → Flutter `HapticFeedback.lightImpact()` mapping. Pruefen, ob Settings-`Vibration`-Toggle (siehe `mobile-app-settings-modal.md`) das deaktiviert respektiert.
