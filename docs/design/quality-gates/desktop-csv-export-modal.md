# Quality-Gate: CsvExportModal (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/CsvExportModal.jsx`
**Flutter-Pendant**: Mobile-Pendant `app/CsvExportModal.jsx` ist Bottom-Sheet — Desktop-Dialog mit Live-Vorschau FEHLT
**Tablet/Desktop-Breakpoints**: Modal-Width fix 880 dp (max 94vw); zentriert
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (Two-Column-Modal)
- Backdrop: identisch zum AppSettingsModal (`rgba(12,11,7,0.55)`, z-index 40).
- Modal-Container: `width: 880`, `max-width: 94vw`, `max-height: 94vh`, `background: --kc-bg-raised`, `border-radius: 18`, `box-shadow: --kc-shadow-4`, `overflow: hidden`, Flex-Column-Layout.
- **Header** (`padding: 22px 28px 14px`, Bottom-Border): Eyebrow `Daten` + Title `CSV-Export` 26 px display. Close-Btn rechts.
- **Body** (`display: grid; grid-template-columns: 1.1fr 1fr; gap: 24; padding: 18px 28px; overflow-y: auto; flex: 1`):
  - **LEFT**:
    - Section `Zeitraum`: Chip-Row mit 5 Pills (Alle / 30 Tage / 90 Tage / Saison 2025 / Eigen…). Aktiv Stone-900.
    - Section `Modi`: 3 Check-Cards (Sniper-Training, Finisseur, Match) mit Checkbox + Label + Sub-Text. On-State Inset Meadow-500 Border + Meadow-500 BG-Box.
    - Section `Spalten`: 2 × 2 Grid mit 4 ColChips (Basis, Helikopter-Tracking, Standort & Pitch, Partner/Gegner). Checkbox-Style aehnlich, aber kompakter.
  - **RIGHT**:
    - Section `Vorschau`:
      - Preview-Box Stone-900 BG mit Header-Row: Filename mono (z.B. `kubbclub_alle_2025-05-28.csv`) + Meta `X Sessions · ~Y kB`.
      - Code-Pre: Mono-Text in Meadow-200 Color, CSV-Sample (5 Datenzeilen + `…  (X weitere Zeilen)`). Spalten dynamisch je nach `cols.helitrack`.
    - Meta-Card Sunken-BG mit 4 MetaRows (Encoding UTF-8 mit BOM / Trennzeichen `,` / Dezimal `.` / Datum ISO 8601).
- **Footer** (`padding: 16px 28px 22px`, Top-Border): Cancel-Btn (Ghost) + Primary-Btn `↓ <filename> herunterladen` (Meadow-600).

### Farben
- Modal-BG Bg-Raised.
- Check-On Inset Meadow-500.
- ColChip-On Inset Meadow-500.
- Preview-Box Stone-900 BG, Filename Chalk-50, Meta Stone-300.
- Code-Text Meadow-200.
- Section-Labels mono uppercase.
- Footer Primary-Btn Meadow-600 BG.

### Typografie
- Modal-Title 26 px display.
- Preview-Filename mono 12 px.
- Code-Text mono 11.5 px line-height 1.7 Meadow-200.
- MetaLbl mono 11 px muted. MetaVal mono 12 px weight 600.
- Check-Lbl 14 px ui weight 700. Check-Sub 12 px muted.

### Spacing
- Body-Padding `18px 28px`.
- Body-Grid-Gap 24.
- Section-Padding `10px 0 8px`.
- Chip-Row gap 6.
- Checks-Stack gap 8.
- ColsGrid gap 6.
- Preview min-height 240.

### Border-Radius
- Modal 18. Pills 999. Check-Cards 12. ColChips 10. Preview 12. Meta 12. CheckBox 6. ColBox 4. Footer-Btn 12.

### Shadows
- Modal `--kc-shadow-4`. Primary-Btn `--kc-shadow-1`.

### Icons
- `↓` Glyphe in Primary-Btn. In Flutter: `Icons.download` oder eigenes Download-SVG.
- `✓` als Check-Glyphe in Boxes — Flutter `Icons.check` 12 / 11 px.

## Komponenten-Inventar

- Lokal:
  - `Check` (label + sub + on + onChange, mit grosser CheckBox 22 dp).
  - `ColChip` (label + on + onChange, mit kleiner ColBox 18 dp).
  - `MetaRow` (label + value).

**Unterschied Mobile**: Mobile-Pendant ist Bottom-Sheet mit Single-Column-Layout, ohne Live-Vorschau (Platzmangel). Desktop hat Two-Column-Layout mit Live-Code-Vorschau, das ist der entscheidende Mehrwert.

**Flutter-Aequivalente**:
- `Dialog` mit `ConstrainedBox(maxWidth: 880)` + `Row(Expanded, Expanded)`.
- `Check` → eigenes `KCCheckCard`-Widget (kein Material `Checkbox` wegen Custom-Layout).
- Code-Preview → `Container` mit `Text` in Monospace + Custom-Color.
- `ColChip` → kleines `InkWell`-Container mit Checkbox.

## Interaktions-Pattern

- **Esc / Backdrop / Close-Btn**: schliesst Modal (kein Save).
- **Chip-Click (Zeitraum)**: setzt `range`-State, aktualisiert Preview-Meta + Filename.
- **Check-Click (Modi)**: toggelt Modus, aktualisiert `total`-Sessions-Count und Preview.
- **ColChip-Click (Spalten)**: toggelt Spalte, aktualisiert Code-Vorschau (z.B. `heli`-Spalte verschwindet/erscheint).
- **`Eigen…`-Chip**: oeffnet Date-Range-Picker (im JSX nicht implementiert — Backlog).
- **Herunterladen-Btn**: triggert CSV-Generation + Download. Auf Web/Desktop: Browser-Save-Dialog. Auf Mobile/Tablet: Share-Sheet.
- **Loading**: bei grossen Datasets evtl. Spinner waehrend Generation.
- **Error**: bei Backend-Failure Toast.
- **Empty**: wenn `total === 0` (keine Modi gewaehlt) → Primary-Btn disabled mit Hint "Mindestens einen Modus waehlen".

## Accessibility

- **Focus-Trap**: Tab-Navigation im Modal.
- **Esc-to-Close**: Pflicht.
- **Tab-Order**: Close-Btn → Zeitraum-Chips → Modi-Checks → Spalten-ColChips → Cancel → Primary.
- **Aria-Modal + role=dialog**: standard.
- **Check-Boxen mit `aria-checked`**.
- **Code-Preview**: per `<pre>` semantisch korrekt; in Flutter via `SelectableText` damit User Code copy-pasten kann.
- **Min-Window-Width**: 880 dp. Auf kleineren Geraeten wird Modal auf 94vw skaliert; Two-Column wird zu Stack (Body `flex-direction: column`).

## Quality-Gate-Checkliste

- [ ] Modal 880 dp, zentriert, Backdrop dark.
- [ ] Header mit Eyebrow + Title 26 px + Close.
- [ ] Body Two-Column 1.1fr / 1fr.
- [ ] Zeitraum-Chips 5 Pills, aktiv Stone-900.
- [ ] Modi-Checks 3 grosse Check-Cards mit Inset-Border-On.
- [ ] Spalten-ColChips 2 × 2 Grid, kleinere Boxes.
- [ ] Preview-Box Stone-900 BG, Code in Meadow-200 mono.
- [ ] Code-Sample 5 Datenzeilen, Spalten dynamisch (helitrack on/off).
- [ ] Filename live aus range + Datum gebaut.
- [ ] Meta-Card mit 4 Rows (Encoding / Trennzeichen / Dezimal / Datum).
- [ ] Footer mit Cancel + Primary (Meadow-600).
- [ ] Primary-Btn enthaelt Filename live.
- [ ] Disabled-State wenn keine Modi gewaehlt.

## Implementations-Hinweise fuer Flutter

- **Adaptive Modal**: gleiches Pattern wie AppSettingsModal — `showDialog` (Desktop) vs. `showModalBottomSheet` (Phone). Two-Column nur auf Desktop, sonst Stack.
- **CSV-Generation**:
  - Domain-Layer: pure-Dart Funktion `String generateCsv(SessionExport input)` in `kubb_domain`.
  - Daten-Layer: `sessionExportRepository.queryForExport(filters)` liefert die Rohdaten.
  - Download:
    - **Desktop/Web**: `package:file_saver` o.ae., oder `dart:html` (web-only) `Blob` + `<a download>` click. ADR-Kandidat.
    - **Android/iOS**: `share_plus` + temporary File.
- **Live-Preview**: nimmt erste 5 Rows aus `queryForExport(filters).take(5)` und rendert sie. Aktualisiert bei jedem Filter-Change (`ref.watch`).
- **State**: `csvExportFiltersProvider` (neu) — Notifier mit `range`, `modes`, `cols`. Provider-Methoden setzen jeweilige Felder.
- **Filename-Builder**: pure-Dart Funktion in `kubb_domain` `String buildExportFilename(range, today)`.
- **Layout**: `Row(children: [Expanded(flex: 11, ...left), SizedBox(width: 24), Expanded(flex: 10, ...right)])`.
- **Komplexitaet**: **M**. 2 – 4 Tage. Hauptaufwand: CSV-Generation + Download-Strategie. Layout selbst ist einfach.
- **Pakete**: `file_saver` oder `share_plus` (plattformabhaengig). ADR fuer Cross-Platform-Download.
- **Sicherheit**: keine sensitiven Daten im Export (User-Daten gehoeren dem User, kein PII anderer Personen). RLS-konformitaet bei Cloud-Export pruefen.
