# Quality-Gate: Einstellungen (Drawer-Liste, Mobile)

**Quelle**: `docs/design/ui_kits/app/SettingsScreen.jsx`
**Flutter-Pendant**: `lib/features/settings/presentation/settings_screen.dart`
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **AppBar**: Eyebrow `Menü`, Title `Einstellungen`, Back-Button.
2. **Profile-Block** (`profileBlock`): Avatar 56x56 (meadow-600 Bg, Display 24px Initial) + Name + Meta-Text ("Profil aktiv · seit Apr 2024").
3. **Group 1** (drei NavRows, alle "Settings-Style"):
   - Statistik (`Icon.Stat`) — sub: "Trefferquote, Streaks, Verlauf"
   - Profil (`Icon.Profile`) — sub: "Name, Wurf-Hand, Stamm-Distanz"
   - App-Einstellungen (`Icon.Gear`) — sub: "Sprache, Vibration, Sonneneinheit"
4. **Section "Daten"**.
5. **Group 2** (drei NavRows):
   - Erfolge (`Icon.Trophy`) — sub: "Meilensteine"
   - CSV-Export (`Icon.Download`) — sub: "Sessions als .csv-Datei"
   - Sessions zuruecksetzen (`Icon.Trash`, tone="danger") — sub: "alle gespeicherten Sessions loeschen"
6. **Footer**: zwei Zeilen — `Brosi's Kubb · v0.1.0` (**TODO REBRAND** → `Kubb Club · v0.1.0`) + `Für die Wiese gebaut.`

### Farben (Tokens)

| Element | Token |
|---|---|
| ProfileBlock-Avatar-Bg | `--bk-meadow-600` |
| Section-Header | `--bk-fg-muted` |
| Group-Card | `--bk-bg-raised` |
| Row-Icon-Bg | `--bk-bg-sunken` |
| Row-Label (normal) | `--bk-fg` |
| Row-Label (danger) | `--bk-danger` (#B73A2A) |
| Row-Icon-Color (danger) | `--bk-danger` |
| Chevron | `--bk-fg-muted` |
| Footer | `--bk-fg-muted` |

### Typografie

- Avatar-Initial: Display 24px weight 800.
- ProfileName: Display 18px weight 700 tracking -0.01em.
- ProfileMeta: 12px fg-muted.
- Section: 11px weight 600 uppercase tracking 0.08em fg-muted.
- RowLabel: Display 16px weight 600.
- RowSub: 12px fg-muted.
- Footer-Line: 12px fg-muted lineHeight 1.6.

### Spacing

- ProfileBlock: padding `10px 18px 18px`, gap 14.
- Section: padding `14px 18px 8px`.
- Group: margin `0 16px`, overflow hidden, radius 14.
- Row: padding `14px 16px`, minHeight 64, gap 14, borderBottom 1px line.
- Footer: padding `24px 18px 8px`, textAlign center.

### Border-Radius

- Avatar: 50% (Circle).
- Group: 14.
- Row-Icon-Bg: 10.

### Shadows

- Keine.

### Icons

- `Icon.Stat` (22px) — Statistik.
- `Icon.Profile` (22px) — Profil.
- `Icon.Gear` (22px) — App-Einstellungen.
- `Icon.Trophy` (22px) — Erfolge.
- `Icon.Download` (20px) — CSV-Export.
- `Icon.Trash` (20px) — Sessions zuruecksetzen.
- `Icon.ChevronRight` (20px) — Row-Chevron.

### Brand-Elemente

- Footer-String `Für die Wiese gebaut.` — Brand-Tagline (deutsch, Eigenton).

## Komponenten-Inventar

- `SettingsScreen` — Hauptkomponente.
- `SettingsRow` — Generische Zeile (Icon + Label + Sub + Chevron, optional tone="danger").

## Interaktions-Pattern

- **`onOpen(key)`**: Callback fuer Row-Tap. Keys: `'stats'`, `'profile'`, `'app'`, `'achievements'`, `'export'`, `'reset'`.
- **Tone "danger"**: rot-faerbt Icon + Label, anders aber gleicher Klick-Pfad.

### Loading / Error / Empty-States

- Keine — pure Navigation-Liste.

### Spezifisch fuer diesen Screen

- **Drawer-Style** vs. AppSettingsModal: dieser Screen ist die **vollstaendige Einstellungs-Page** (full-screen), AppSettingsModal ist das **schnelle Bottom-Sheet** mit den haeufigsten Optionen.
- Footer hat das Brand-Statement `Für die Wiese gebaut.` — bleibt im Rebrand erhalten.
- **`onOpen('app')`** fuehrt zu AppSettings — wahrscheinlich zur Modal-Variante.

## Accessibility

- AppBar 48x48 ✅.
- Row: 64dp ✅.
- Touch-Targets durchgehend gross genug.
- `tone="danger"` ist nur Farb-Indikator — Screenreader bekommt kein zusaetzliches Signal. Sollte `aria-describedby="destructive-action"` oder Confirm-Dialog haben.

## Quality-Gate-Checkliste

- [x] Layout dokumentiert.
- [x] Tone "danger" konsistent.
- [x] Touch-Targets ≥ 48dp.
- [ ] **Footer-String `Brosi's Kubb`** muss zu `Kubb Club` (Zeile 35 im JSX).
- [ ] **Danger-Action** sollte einen Confirm-Dialog triggern — im Kit nicht modelliert, aber `onOpen('reset')` ist der Hook dafuer.
- [x] Section-Header-Pattern konsistent mit anderen Screens.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Footer-Rebrand**: `Brosi's Kubb · v0.1.0` muss zu `Kubb Club · v0.1.0`. Aenderung im JSX (Zeile 35) noch ausstehend; Flutter-Pendant ggf. schon ueber `app_de.arb` umgestellt.
2. **`Sonneneinheit`** im App-Einstellungen-Sub-Text ist ungewoehnlich — vermutlich Schreibfehler fuer "Distanz-Einheit" (m / ft, siehe `AppSettingsModal.jsx`). Sollte korrigiert werden zu `Sprache, Vibration, Distanz-Einheit` oder analog.
3. **Reset-Action** (Sessions zuruecksetzen) braucht Confirm-Dialog (siehe `lib/features/settings/presentation/confirm_dialog.dart`).
4. **Erfolge-Screen** existiert noch nicht (AUDIT.md Punkt 4.6) — der NavRow fuehrt ins Leere oder zu Placeholder.
5. **Drawer-Style vs. Modal-Sheet** (siehe `mobile-app-settings-modal.md`): Flutter hat `settings_screen.dart` als full-screen — bleibt das die Drawer-Variante oder ersetzt die Modal-Variante diese?
6. **`Sessions zuruecksetzen`** im Drawer-Style vs. **`Userdaten loeschen` + `Profil loeschen`** im Modal — der Modal ist granularer. Konsolidierung pruefen.
