# Quality-Gate: Finisseur-Konfiguration (Mobile)

**Quelle**: `docs/design/ui_kits/app/FinisseurConfigScreen.jsx`
**Flutter-Pendant**: `lib/features/training/presentation/finisseur_config_screen.dart`
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **Top-Bar** (eigene Header-Struktur, nicht `AppBar` aus `shared.jsx`): Back-Button ← Title (Eyebrow `Finisseur` + Name `Konfiguration`) → 48-Spacer.
2. **Visual-Preview** (`preview`): Inset-Card mit:
   - Feldkubbs als Reihe kleiner Holz-Rechtecke (14x24px je Kubb).
   - Pitch-Line (horizontal, `line-strong`, Width 80%).
   - Basiskubbs als Reihe groesserer Holz-Rechtecke (18x32px je Kubb).
   - Label unter dem Visual: `{field} / {base}  ·  6 Stoecke` (Display 18px).
3. **Stepper 1** — Feldkubbs (Label "Feldkubbs (eingeworfen)"), 0 bis `maxField` (=10), Default Akzent `meadow-500`.
4. **Stepper 2** — Basiskubbs (Label `Basiskubbs  ·  max {maxBase}`), 0 bis `maxBase` (= min(5, 10-field)), Akzent `wood-400`.
5. **Constraint-Note**: Mono 11px, "Total maximal 10 Kubbs · Basis maximal 5. Aktuell **{field+base} / 10**."
6. **Preset-Block**:
   - Header "Presets" (Eyebrow) + Save-Pill (nur sichtbar, wenn aktuelle f/b-Kombination keinem Preset entspricht).
   - Preset-Chips (Wrap): Built-in (`Standard 7/3`, `5/5`, `10/0`, `Spaet 3/5`) + User-Presets.
   - User-Presets haben Close-Badge (rechts oben, 22x22 stone-900 Circle).
7. **Start-Button**: `margin auto 16px 28px`, Display weight 700, 18px, meadow-500, full-width 60dp.
8. **SavePresetSheet** (modal): Eyebrow "Preset speichern" + `{f}/{b}` Title, Name-Input (placeholder `z. B. Heim-Setup`), Cancel + Save Buttons.

### Farben (Tokens)

| Element | Token |
|---|---|
| Screen-Bg | `--bk-bg` |
| Preview-Bg | `--bk-bg-raised` |
| Kubb-Field-Body | `--bk-wood-400` |
| Kubb-Field-Top | `--bk-wood-600` (2px solid) |
| Kubb-Base-Body | `--bk-wood-300` |
| Kubb-Base-Top | `--bk-wood-500` (2px solid) |
| Pitch-Line | `--bk-line-strong` |
| Stepper-Btn-Bg | `--bk-bg-raised` mit `inset 0 0 0 2px line` |
| Stepper-Value-Ring (Feldkubbs) | `--bk-meadow-500` |
| Stepper-Value-Ring (Basiskubbs) | `--bk-wood-400` |
| Preset-Off | `--bk-bg-raised` mit `inset 0 0 0 1.5px line` |
| Preset-On | `--bk-stone-900` + chalk-50-Text |
| Save-Pill-Outline | `inset 0 0 0 1.5px line-strong` |
| Start-Btn | `--bk-primary` (meadow-500) |
| Save-Btn (Sheet) | `--bk-primary` |
| Cancel-Btn (Sheet) | `--bk-bg-sunken` |

### Typografie

- Top-Eyebrow: 11px weight 600 uppercase tracking 0.08em fg-muted.
- Top-Name: Display 20px weight 700 tracking -0.02em.
- Preview-Label: Display 18px weight 700 tracking -0.02em fg-muted.
- Stepper-Label: 11px weight 600 uppercase fg-muted.
- Stepper-Range: Mono 11px fg-subtle.
- Stepper-Value: Display 36px weight 800 `tabular-nums`.
- Constraint-Note: Mono 11px fg-muted tracking 0.02em.
- Preset-Label: 13px weight 600.
- Preset-Ratio: Mono 11px fg-muted.
- Start-Btn: Display 18px weight 700.
- Sheet-Title: Display 24px weight 700.
- Input: 16px Body.

### Spacing

- Top-Bar: `54px 12px 6px`.
- Preview: `padding 14px 16px 10px`, `margin 8px 16px 14px`, paddingBottom 14.
- Stepper-Container: `padding 10px 16px`.
- Stepper-Row: Grid `64px 1fr 64px`, gap 10.
- Stepper-Btn/Value: minHeight 64.
- Constraint-Note: `padding 2px 18px 6px`.
- Preset-Block: `padding 4px 16px 14px`.
- Preset-Row: flex wrap, gap 8.
- Save-Pill: minHeight 36, padding `0 12px`.

### Border-Radius

- Preview: 16
- Stepper-Btn/Value: 14
- Preset: 14
- Save-Pill: 999 (pill)
- Start-Btn: 16
- Sheet: top-radius 24
- Input: 12
- Cancel/Save-Btn: 14
- Preset-Remove-Badge: 50% (Circle)

### Shadows

- Keine prominenten Shadows; alle Cards nutzen `inset ... line` als Begrenzung.
- Preset-Remove-Badge: `0 1px 2px rgba(0,0,0,0.2)`.

### Icons

- `Icon.Back` (22px) — AppBar-Back.
- `Icon.Plus2` (20px) — Save-Pill-Icon.
- `Icon.Close` (22px) — Sheet-Close + Preset-Remove-Badge.
- `Icon.Plus` (24px) / `Icon.Minus` (24px) — Stepper.

### Brand-Elemente

- **Holz-Kubb-Visualisierung** im Preview — funktionale Mini-Grafiken, kein Logo. Nutzt Wood-Tokens fuer authentischen Look.

## Komponenten-Inventar

- `FinisseurConfigScreen` — Hauptkomponente.
- `Stepper` — generischer Stepper-Block (Label + Range + +/- Buttons).
- `SavePresetSheet` — modal fuer Preset-Speichern.
- Konstante `BUILTIN_PRESETS` — 4 Default-Presets.

## Interaktions-Pattern

- **Constraints**:
  - `field + base <= 10` (Total Kubbs)
  - `base <= 5` (Basiskubb-Max)
  - `maxBase = min(5, 10 - field)`
  - `maxField = 10`
- **Setter-Clamping**:
  - `setFieldClamped(v)`: clamp auf [0..10]; danach Basis nach unten ziehen, wenn ueber neuem maxBase.
  - `setBaseClamped(v)`: clamp auf [0..maxBase].
- **Preset-Tap**: setzt `field` und `base` direkt.
- **Save-Pill**: nur sichtbar wenn `matchesExisting === false`. Oeffnet `SavePresetSheet`.
- **Preset-Remove**: Built-in-Presets haben kein Remove-Badge; nur User-Presets.
- **Start-Button**: ruft `onStart({ field, base })` auf.

### Loading / Error / Empty-States

- Keine async-States — alles lokal.
- User-Preset-Liste startet mit einem Demo-Preset `{ id:'p-clean', label:'Sauber', f:6, b:4 }`. Im echten Code: aus Persistence laden.

### Spezifisch fuer diesen Screen

- **Visual-Stack-Preview** ist das markante Element. Kubbs werden gezeichnet als kleine vertikale Rechtecke mit dunklerem Top-Border (simuliert Stirnseite).
- **Preset-Save** nutzt entweder den User-Input-Namen oder `{f}/{b}` als Fallback.
- **6 Stoecke** ist im Preview-Label hartcodiert — Spec-konform fuer Finisseur (das ist die Standard-Stocks-pro-Halbsatz-Zahl).

## Accessibility

- Top-Bar-Buttons: 48x48 ✅.
- Stepper-Buttons: 64x64 ✅.
- Preset-Buttons: minHeight 48 ✅.
- Preset-Remove-Badge: 22x22 — **unter 48dp**, problematisch. Sollte ggf. auf 36x36 (auch wenn visuell groesser) oder via expanded hit-area.
- `aria-label="Preset ... entfernen"` ist gesetzt.
- Input hat `autoFocus` — fuer Tastatur-User OK.
- Tabular-Nums auf Stepper-Value und Constraint-Note ✅.

## Quality-Gate-Checkliste

- [x] Constraints (field+base <= 10, base <= 5) explizit dokumentiert.
- [x] Preset-Pattern (Built-in vs. User, Remove-Badge nur fuer User) klar.
- [x] Visual-Preview-Tokens (`wood-300/400/500/600`) konsistent.
- [x] Tabular-Nums.
- [ ] **Preset-Remove-Badge 22x22 < 48dp** — Touch-Target-Problem.
- [ ] **Sheet hat keine onKey-Handler** (Escape zum Schliessen) im Kit. Flutter sollte `barrierDismissible: true` ohnehin liefern.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Visual-Preview** mit Kubb-Mini-Rechtecken: pruefen, ob Flutter denselben Look hat oder eine simpler Text-Variante (`7/3`).
2. **`SavePresetSheet`** als Bottom-Sheet: Flutter sollte `showModalBottomSheet` + Form mit `TextFormField` nutzen.
3. **Preset-Persistierung**: das Kit hat `useState` (transient). Flutter muss auf drift-Persistenz mappen — Preset-Tabelle existiert vermutlich noch nicht, ggf. nachziehen.
4. **Stepper-Akzent unterschiedlich** (meadow fuer Feld, wood fuer Basis) — visuelle Konvention. Pruefen, ob Flutter das spiegelt.
5. **Save-Pill ist Outline** (nicht solid). Flutter `OutlinedButton.icon` ist passend.
