# Quality-Gate: AppSettingsModal (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/AppSettingsModal.jsx`
**Flutter-Pendant**: Mobile-Pendant `app/AppSettingsModal.jsx` ist Bottom-Sheet — Desktop-Dialog FEHLT
**Tablet/Desktop-Breakpoints**: Modal-Width fix 520 dp (max 92vw fuer Tablet-Portrait); zentriert
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (Modal)
- Backdrop: `position: absolute; inset: 0`, `rgba(12,11,7,0.55)`, Grid-Center, `z-index: 40`. Click auf Backdrop schliesst.
- Modal-Container: `width: 520`, `max-width: 92vw`, `max-height: 92vh`, `background: --kc-bg-raised`, `border-radius: 18`, `box-shadow: --kc-shadow-4`, `overflow: hidden`.
- **Header** (`padding: 22px 24px 12px`, Bottom-Border): Eyebrow `Menue` + Title `Schnell-Einstellungen` 24 px display. Close-Btn rechts (`×`, 36 dp).
- **Body** (`padding: 8px 16px 18px`, `overflow-y: auto`):
  - Section-Label `App` (mono uppercase).
  - Group-Card Sunken-BG mit 5 Rows:
    - Sprache (Seg: de-CH / de-DE / en).
    - Distanz-Einheit (Seg: m / ft).
    - Theme (Seg: hell / dunkel / auto).
    - Vibration beim Tippen (Toggle).
    - Auto-Speichern (Toggle).
  - Section-Label `Daten`.
  - Group-Card mit 5 NavRows:
    - Statistik (📊, opens Stats).
    - Erfolge (🏆, Backlog).
    - CSV-Export (⬇, opens CsvExportModal).
    - Userdaten loeschen (↺, danger, opens ResetModal).
    - Profil loeschen (✕, danger).
  - Footer-Text (klein, muted, zentriert): `Kubb Club · v0.1.0` + `Fuer die Wiese gebaut.`

### Farben
- Backdrop semi-transparent dark.
- Group-Card-BG: Bg-Sunken. Inner-Rows mit Bottom-Border.
- Seg-Active: Stone-900 + Chalk-50.
- Toggle-On: Meadow-500. Off: Stone-200.
- NavRow-Danger-Lbl: Miss.

### Typografie
- Modal-Title 24 px display weight 700 opsz 72.
- Section-Label mono 11 px uppercase.
- Row-Lbl 14 px ui weight 600. Row-Sub 12 px muted.

### Spacing
- Header-Padding `22px 24px 12px`.
- Body-Padding `8px 16px 18px`.
- Group-Card-Padding `4px 14px`.
- Row-Padding `12px 0`.

### Border-Radius
- Modal 18. Group-Card 14. Pills 999. NavRow-Icon 10. Toggle 999.

### Shadows
- Modal `--kc-shadow-4` (groesste, fuer obersten Layer).

### Icons
- Emoji-Icons im JSX (📊 🏆 ⬇ ↺ ✕). In Flutter: durch echte `DIcon`/SVG-Icons ersetzen — Emoji sind plattform-abhaengig und meist nicht im Brand-Look.

## Komponenten-Inventar

- Lokal:
  - `Row` (label + child).
  - `NavRow` (icon + label + sub + chev + onClick + optional danger-tone).
  - `Seg`, `Toggle` — generic.

**Unterschied Mobile**: Mobile-Pendant `app/AppSettingsModal.jsx` ist ein **Bottom-Sheet** (slide-up von unten), Desktop ist ein **zentrierter Dialog**. Layout-Struktur sonst sehr aehnlich.

**Flutter-Aequivalente**:
- `showDialog` mit `Dialog` Custom-Widget.
- Auf Phone weiterhin `showModalBottomSheet` — Switch via `MediaQuery.sizeOf(context).width >= 900`.
- `SegmentedButton<T>` aus Material 3.
- Material `Switch`.

## Interaktions-Pattern

- **Esc**: schliesst Modal (Pflicht).
- **Backdrop-Click**: schliesst Modal.
- **Close-Btn**: schliesst Modal.
- **Seg-Change**: lokaler State, kein Save-Btn (Auto-Save).
- **Toggle-Change**: lokaler State, Auto-Save.
- **NavRow-Click**:
  - Statistik / Erfolge / Profil-loeschen: navigieren oder oeffnen weitere Flows.
  - CSV-Export: `onOpenExport()` → schliesst dieses Modal, oeffnet CsvExportModal.
  - Reset: `onOpenReset()` → schliesst dieses Modal, oeffnet ResetModal.
- **Loading**: nicht relevant (Settings sind lokal).
- **Error**: bei Sync-Failure Toast nach Auto-Save.

## Accessibility

- **Focus-Trap**: Tab-Navigation darf nicht aus Modal raus. Erstes Element nach Open: Close-Btn oder erstes Seg.
- **Esc-to-Close**: Pflicht.
- **Aria-Modal**: `aria-modal="true"` und `role="dialog"`. In Flutter via `Dialog`-Widget standardmaessig.
- **Close-Btn Aria-Label**: `Schliessen` (im JSX `aria-label="Schliessen"` schon vorhanden, gut).
- **Tab-Order**: Close-Btn → Seg-Buttons → Toggles → NavRows.
- **Min-Window-Width**: kein Min — Modal skaliert auf 92vw.

## Quality-Gate-Checkliste

- [ ] Modal 520 dp, zentriert, Backdrop `rgba(12,11,7,0.55)`.
- [ ] Header mit Eyebrow + Title 24 px + Close-Btn.
- [ ] App-Section: 3 Seg-Rows + 2 Toggle-Rows in Group-Card.
- [ ] Daten-Section: 5 NavRows in Group-Card.
- [ ] NavRow-Danger (Reset, Profil-loeschen) mit Miss-Color.
- [ ] Footer mit Version-Info.
- [ ] Emoji-Icons durch DIcon ersetzt (Stat, Cup, Inbox, Undo, X).
- [ ] Esc + Backdrop-Click schliessen.
- [ ] Focus-Trap aktiv.
- [ ] CSV-Export-Trigger oeffnet CsvExportModal.
- [ ] Reset-Trigger oeffnet ResetModal (siehe SettingsScreen).

## Implementations-Hinweise fuer Flutter

- **Adaptive Modal**: Custom Widget `KCAppSettings.show(context)` waehlt zwischen `showModalBottomSheet` (Phone) und `showDialog` (Tablet/Desktop) basierend auf Breite.
- **Modal-Widget**: `Dialog(child: ConstrainedBox(maxWidth: 520))` mit eigenem Padding-Layout.
- **State**: gleicher `settingsControllerProvider` wie SettingsScreen. Modal ist nur ein anderer Render-Pfad.
- **Auto-Save**: jeder Seg-/Toggle-Change ruft `notifier.set...()` auf, Provider-Notifier persistiert via Drift.
- **NavRow-onClick**: callbacks aus dem Parent (`onOpenExport`, `onOpenReset`) oder direkt via `context.go(...)`.
- **Icons**: Emoji → `DIcon.Stat`, `DIcon.Cup`, `DIcon.Inbox`, `DIcon.Undo`, plus eigenes `X`-Icon (oder Material `Icons.close`).
- **Komplexitaet**: **S-M**. 1 – 2 Tage. Layout ist simpel, Logic ist in Provider, Hauptaufwand sind die Forms-Bindings.
- **Pakete**: keine neuen.
