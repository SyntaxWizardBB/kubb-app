# Quality-Gate: App-Einstellungen Modal (Mobile)

**Quelle**: `docs/design/ui_kits/app/AppSettingsModal.jsx`
**Flutter-Pendant**: unklar — `lib/features/settings/presentation/settings_screen.dart` ist drawer-style. Modal-Variante als BottomSheet ggf. nicht implementiert.
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down) — Bottom-Sheet

1. **Backdrop**: `rgba(12,11,7,0.55)`, klickbar zum Schliessen.
2. **Sheet**: top-radius 24, `bg-bg`, maxHeight 92%, overflowY auto.
3. **Grabber**: 36x4 stone-200 Pill.
4. **Head**: Eyebrow `Menü` + Title `App-Einstellungen` (Display 24px weight 800) — links; Close-Icon-Button rechts.
5. **Section "App"** — Group-Card mit 4 Toggle/Seg-Rows:
   - Sprache: Seg `de-CH` / `de-DE` / `en`
   - Distanz-Einheit: Seg `m` / `ft`
   - Vibration beim Tippen: Toggle (Switch)
   - Theme: Seg `hell` / `dunkel` / `auto`
6. **Section "Daten"** — Group-Card mit 5 NavRows:
   - Statistik (`Icon.Stat`)
   - Erfolge (`Icon.Trophy`)
   - CSV-Export (`Icon.Download`)
   - Userdaten loeschen (`Icon.Trash`, danger) — sub: "alle gespeicherten Sessions & Statistiken"
   - Profil loeschen (`Icon.Trash`, danger) — sub: "Account & alle Daten unwiderruflich entfernen"
7. **Footer**: `Brosi's Kubb · v0.1.0` (**TODO REBRAND**) + `Für die Wiese gebaut.`

### Farben (Tokens)

| Element | Token |
|---|---|
| Backdrop | rgba(12,11,7,0.55) |
| Sheet-Bg | `--bk-bg` |
| Grabber | `--bk-stone-200` |
| Section-Header | `--bk-fg-muted` |
| Group-Card | `--bk-bg-raised` |
| Row-Border | `--bk-line` |
| NavIcon-Bg | `--bk-bg-sunken` |
| NavRow-Danger | `--bk-danger` (Label + Icon) |
| Seg-On | `--bk-stone-900` + chalk-50 |
| Toggle-On | `--bk-meadow-500` |
| Toggle-Off | `--bk-stone-200` |
| Toggle-Knob | `#fff` |

### Typografie

- Eyebrow: 11px weight 600 uppercase tracking 0.08em.
- Title: Display 24px weight 800 tracking -0.02em.
- Section: 11px weight 600 uppercase tracking 0.08em.
- RowLbl: 11px weight 600 uppercase fg-muted.
- NavLbl: Display 15px weight 600.
- NavSub: 12px fg-muted.
- Seg-Btn: Display 13px weight 600.
- Footer: 11px fg-muted.

### Spacing

- Sheet: padding `10px 0 40px`.
- Head: padding `4px 18px 12px`.
- Section: padding `8px 18px 6px`.
- Group: margin `0 16px 6px`, padding `4px 14px`.
- Row (Field): padding `10px 0`, gap 6, borderBottom 1px line.
- NavRow: padding `12px 0`, minHeight 60, gap 14, borderBottom 1px line.
- Footer: padding `14px 18px 6px`, gap 4.

### Border-Radius

- Sheet: top-radius 24.
- Group: 14.
- NavIcon: 10.
- Seg-Container: 999, Inner-Btn 999.
- Toggle: 999, Knob 50%.

### Shadows

- Knob: `0 1px 3px rgba(0,0,0,0.2)`.
- Sheet: kein expliziter Shadow (Backdrop trennt).

### Icons

- `Icon.Close` (22px) — Sheet-Close.
- `Icon.Stat`, `Icon.Trophy`, `Icon.Download`, `Icon.Trash` — Daten-NavRows.
- `Icon.ChevronRight` — Chevron in NavRows.

### Brand-Elemente

- Footer-Tagline `Für die Wiese gebaut.` — Brand-Statement.

## Komponenten-Inventar

- `AppSettingsModal` — Hauptkomponente.
- `Row` — Generische Label-Value-Row.
- `NavRow` — Generische NavRow (Icon + Label + Sub + Chevron + tone).
- `Seg` — Segmented-Control.
- `Toggle` — Switch (Animation via transform translateX).

## Interaktions-Pattern

- **State**: `language`, `vibrate`, `unit`, `theme` lokal via useState.
- **Toggle**: `onClick={() => onChange(!on)}`. Knob bewegt sich via `transform`.
- **Seg-Onchange**: pro Seg-Btn `onClick={() => onChange(o)}`.
- **NavRow-Callbacks**: `onOpenStats`, `onOpenAchievements`, `onOpenExport`, `onOpenReset` als Props.
- **Backdrop-Click**: schliesst Sheet.
- **Sheet-Click**: `e.stopPropagation()` damit Backdrop-Klick nicht durchfaellt.

### Loading / Error / Empty-States

- Keine — alles sofortig.

### Spezifisch fuer diesen Screen

- **Modal-Variant vs. Drawer-Variant**: dieses Modal ist die "Quick-Settings" Variante, die ueber den Hamburger auf Home triggert. Der `SettingsScreen.jsx` ist die separate full-screen Drawer-Variante.
- **2 Danger-Actions**: Userdaten vs. Profil — bewusste Trennung.
- **`Theme: auto`** = System-Default; `hell` / `dunkel` = explicit.
- **`Sprache: de-CH`** als Default (Schweizer-Schwerpunkt).

## Accessibility

- Sheet-Close `aria-label="Schliessen"` ✅.
- NavRow: 60dp ✅.
- Seg-Btn: 34dp — **unter 48dp**, problematisch.
- Toggle: 28dp height × 48dp width — Klick auf Schalter selbst ist 48dp wide ✅.
- Backdrop-Tap als Dismiss ist mobile-typisch ✅.

## Quality-Gate-Checkliste

- [x] Sheet-Pattern (Backdrop + Grabber + Head + Body + Footer) dokumentiert.
- [x] Toggle / Seg / NavRow Komponenten konsistent mit anderen Sheets.
- [x] Danger-NavRows klar markiert.
- [ ] **Footer-String `Brosi's Kubb`** zu `Kubb Club` (Zeile 53).
- [ ] **Seg-Btn 34dp** unter 48dp.
- [ ] **Flutter-Pendant fehlt** evtl. (Modal-Sheet vs. Drawer-Screen).
- [x] Modal triggert NavRow-Callbacks fuer weiterfuehrende Screens.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Modal-Variant existiert in Flutter ggf. nicht** — `settings_screen.dart` ist full-screen. Pruefen, ob ein BottomSheet-Variant via `showModalBottomSheet` auf Home gebraucht wird.
2. **Theme-Switch** in Flutter laeuft ueber `theme_choice.dart` (`KubbTheme.light/dark/highContrast`). Pruefen, ob `auto` als ThemeMode.system gemappt ist.
3. **Sprache-Switch** triggert `AppLocalizations`-Rebuild. Phase 1 hat nur `de` — `en` ist Stub.
4. **2 Danger-Actions** (Userdaten + Profil): Flutter sollte beide auseinanderhalten — `confirm_dialog.dart` existiert, aber unklar ob 2 verschiedene Flows.
5. **Vibration-Toggle** muss von Sniper/Match-Screens respektiert werden (`navigator.vibrate` → bei Flutter `HapticFeedback.lightImpact()` nur wenn Setting an).
6. **Footer-Rebrand** ist offen.
7. **CSV-Export-NavRow** triggert `onOpenExport` — fuehrt typischerweise zu `CsvExportModal` (siehe `mobile-csv-export-modal.md`).
