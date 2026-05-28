# Quality-Gate: CSV-Export-Modal

**Quelle**: docs/design/ui_kits/app/CsvExportModal.jsx
**Flutter-Pendant**: lib/features/settings/presentation/csv_export_modal.dart
**Stand**: 2026-05-28

## Visual-Spec

- **Layout-Struktur**
  - Bottom-Sheet, slidet von unten, max 92 % der Frame-Hoehe, scrollbar bei Ueberlauf.
  - Reihenfolge: Grabber -> Header (Eyebrow "Daten" + Title "CSV-Export" + Close-Icon) -> Section "Zeitraum" mit Chip-Row -> Section "Modi" mit Checkbox-Rows -> Preview-Block (CSV-Vorschau monospaced) -> primaerer Download-Button.
  - Sheet hat 24 px Top-Corner-Radius, scharfe Bottom-Kante.

- **Farben** (Token-Namen)
  - Sheet-Background: `tokens.bg` (Design) bzw. `tokens.bgRaised` (Flutter aktuell — siehe Abweichungen).
  - Chip-Off: `tokens.bgRaised` mit `lineStrong`-Inset-Border 1.5 dp.
  - Chip-On: `tokens.lineStrong` (Stone 900) mit `chalk50` Textfarbe.
  - Checkbox-Card-Off: `tokens.bgRaised` mit `lineStrong`-Inset-Border.
  - Checkbox-Card-On: gleicher Background, aber 2 dp `meadow500` Inset-Border.
  - Checkbox-Box-Off: transparent mit `lineStrong`-Inset-Border 2 dp.
  - Checkbox-Box-On: `meadow500` solid, weisses Check-Glyph.
  - Preview-Block: `tokens.bgSunken` mit 12 px Radius.
  - Preview-Text: `tokens.fg`, Mono-Font.
  - Preview-Meta ("X Sessions · ~Y kB"): `tokens.fgMuted`.
  - Download-Button: `tokens.primary` mit `tokens.onPrimary` Text.
  - Backdrop: `rgba(12,11,7,0.55)`.

- **Typografie**
  - Title: Display-Font, 24 px, 800, letterSpacing -0.02em.
  - Section-Header: 11 px / 600 / uppercase / 0.08em.
  - Chip-Label: Display-Font, 13 px, FontWeight 600.
  - Checkbox-Label: Display-Font, 15 px, FontWeight 700.
  - Checkbox-Subtitle: 12 px, `fgMuted`.
  - Preview-Head ("Vorschau · sessions.csv"): Mono-Font, 11 px, 0.04em letterSpacing.
  - Preview-Code: Mono-Font, 11 px, lineHeight 1.5.
  - Download-Button: Display-Font, 17 px, FontWeight 700.

- **Spacing** (KubbTokens)
  - Sheet-Padding: 10 px oben / 40 px unten.
  - Header-Padding: 4 px oben / 12 px unten / 18 px seitlich.
  - Section-Header: 8 px oben/unten / 18 px seitlich.
  - Chip-Row: 8 px Gap zwischen Chips, 16 px horizontaler Aussenrand, `flexWrap: wrap`.
  - Chip-Padding: 16 px horizontal, minHeight 40 dp.
  - Checkbox-Card-Gap: 8 px zwischen Cards.
  - Checkbox-Card-Padding: 12 px vertikal / 14 px horizontal, minHeight 60 dp.
  - Preview-Aussenrand: 8 px oben / 6 px unten / 16 px seitlich.
  - Preview-internes Padding: 10 px vertikal / 12 px horizontal.
  - Download-Button-Margin: 14 px oben / 16 px seitlich.
  - Download-Button-MinHeight: 54 dp.

- **Border-Radius**
  - Sheet: 24 px oben.
  - Chip: `radiusPill`.
  - Checkbox-Card: 14 px.
  - Checkbox-Box: 6 px.
  - Preview-Block: 12 px (`radiusLg`).
  - Download-Button: 14 px.

- **Shadows**
  - Keine harten Drop-Shadows. Trennung der Cards erfolgt ueber Inset-Borders.

- **Icons** (Lucide-Set)
  - Close: `LucideIcons.x`.
  - Check (Checkbox-On): `LucideIcons.check`.
  - Download-Button: `LucideIcons.download`.

## Komponenten-Inventar

- `showModalBottomSheet` mit `isScrollControlled: true`, `backgroundColor: Colors.transparent` — bereits in `CsvExportModal.show(context)`.
- Grabber + Header-Zeile (Eyebrow + Title + Close-Icon).
- Section-Header (uppercase Caption).
- Chip-Row mit `ChoiceChip` (Flutter) bzw. Custom-Pill-Buttons (Design): Alle / 30 Tage / 90 Tage / Jahr.
- Checkbox-Cards (Sniper, Finisseur) — Flutter nutzt aktuell `CheckboxListTile`.
- Preview-Block: Mono-Codeblock + Meta-Zeile.
- Filled `Download`-Button mit Icon + Label.
- Empty-State-Hint (`l.csvExportEmpty`), wenn keine Modus-Auswahl getroffen ist.

## Interaktions-Pattern

- **Open**: `CsvExportModal.show(context)` triggert `showModalBottomSheet`.
- **Close**:
  - Tap auf Backdrop -> popt das Modal.
  - Close-Icon -> `Navigator.pop`.
  - Swipe-down via Grabber -> Standard Drag.
- **Filter-Interaktion**
  - Chip-Tap setzt `range` via `notifier.setFilter(...)`. Single-Select-Pattern.
  - Checkbox-Tap toggelt Modi (Sniper / Finisseur).
  - `canExport` ist false, wenn weder Sniper noch Finisseur gewaehlt ist -> Download-Button deaktiviert + Hint sichtbar.
- **Download-Trigger**
  - `notifier.trigger()` produziert die CSV und teilt sie ueber `share_plus` oder speichert sie als Datei.
  - Bei Erfolg: Modal popt sich selbst und Snackbar zeigt `l.csvExportSavedTo(path)`.
  - Bei `null`-Result: Modal popt sich auch, keine Snackbar (Share-Sheet hat ggf. eigenen Cancel).
- **Loading/Error-States**
  - `csvExportProvider.when(loading, error, data)` — Loading zeigt 200 dp hohen Spinner zentriert; Error zeigt Fehlertext in `tokens.danger`.
- **Confirm-Dialogs**
  - Kein Confirm vor Export — Export ist nicht-destruktiv, also direkter Trigger ist OK.
  - Wenn spaeter ein "Export inklusive personenbezogener Daten"-Dialog dazukommt: muss als Confirm-Dialog vor `trigger()` rein.

## Accessibility

- Tap-Targets
  - Close-Button 48 dp x 48 dp.
  - Chips minHeight 40 dp -> Quality-Gate-Warnung: in Flutter auf 44+ dp ziehen via `materialTapTargetSize: MaterialTapTargetSize.padded` oder `VisualDensity`.
  - Checkbox-Card: 60 dp Mindesthoehe, also klar ueber `touchMin`.
  - Download-Button: 54 dp.
- Modal-Dismissibility: Backdrop-Tap, Close-Icon, Drag-Down — alle drei muessen funktionieren.
- **Keyboard-Verhalten (Maengel #2.4!)**
  - `padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)` ist bereits im aktuellen Flutter-Code vorhanden — gut.
  - `SafeArea(top: false)` schuetzt Home-Indicator-Bereich.
  - Falls in Zukunft ein Text-Field (z.B. Custom-Datum) dazukommt: dann `SingleChildScrollView` um den Body wickeln, damit der Preview-Block beim Keyboard-Open scrollbar bleibt.
- Preview-Block: monospaced + horizontal scrollbar (`overflow: 'auto'`), damit lange Zeilen abgebildet werden ohne den Sheet-Layout zu sprengen.

## Quality-Gate-Checkliste

- [ ] Layout-Struktur 1:1 zum Design (Grabber -> Header -> Zeitraum -> Modi -> Preview -> Download-Button).
- [ ] Sheet-Radius 24 px oben.
- [ ] Chip-On-State: dunkler Background (Stone 900) + helles Label, Inset-Border verschwindet.
- [ ] Checkbox-Card-On-State: 2 dp `meadow500` Inset-Border.
- [ ] Alle Farben/Spacings aus `KubbTokens`.
- [ ] Modal mit Keyboard scrollable (`viewInsets.bottom`-Padding bereits im Code — bleibt Pflicht; siehe Maengel #2.4).
- [ ] `isScrollControlled: true` + `SafeArea(top: false)`.
- [ ] Touch-Targets >= 48 dp (Chips ggf. via `VisualDensity` anheben).
- [ ] Download-Button >= 54 dp Hoehe, voller Sheet-Breite minus 16 px Aussenrand.
- [ ] `canExport`-Logik korrekt: false, wenn keine Modi gewaehlt.
- [ ] Snackbar-Pfad nach Speichern: `l.csvExportSavedTo(path)` ueber `ScaffoldMessenger` des Parents.
- [ ] i18n via `AppLocalizations` (csvExportTitle, csvExportRangeLabel, csvExportRangeAll/30/90/Year, csvExportModesLabel, csvExportModeSniper/Finisseur, csvExportCount, csvExportDownload, csvExportEmpty, csvExportSavedTo).
- [ ] Preview-Block mit Mono-Font (JetBrains Mono) und 11 px Schrift.

## Bekannte Abweichungen (Flutter aktuell vs. Design)

- **Preview-Block fehlt komplett** im aktuellen Flutter-Code. Stattdessen wird nur `l.csvExportCount(state.count)` als Zeile angezeigt. Quality-Gate-Backlog: Preview-Codeblock (Mono-Font, erste 3–5 Sample-Zeilen aus dem Export, klein gehalten) hinzufuegen — gibt Vertrauen vor dem Download.
- **Sheet-Background**. Aktuell `tokens.bgRaised`, Design `tokens.bg`. Quality-Gate-Entscheidung: `bg` ist konsistenter mit `AppSettingsModal` und sollte angeglichen werden.
- **Chip-Style**. Flutter nutzt Material `ChoiceChip` mit Default-Look. Design-Spec: vollflaechiger Pill mit `lineStrong` Inset-Border im Off-State und solidem dunklen Background im On-State. Quality-Gate-Empfehlung: entweder `ChoiceChip.style` ueberschreiben oder einen Custom-`KubbChoiceChip` ableiten.
- **Checkbox-Cards** verwenden aktuell `CheckboxListTile` (Material-Default). Design-Spec: vollflaechige Card mit Inset-Border, individuell gestaltete Check-Box. Polish-Task — Material-Default ist akzeptabel fuer den ersten Wurf, aber nicht visual-spec-konform.
- **Distanz-/Datum-Range-Picker fehlt**. Design bietet nur die vier Presets (Alle / 30 / 90 / Jahr) — Flutter macht dasselbe, also kein Delta hier.
- **Modus-Counts ("187 Sessions", "119 Sessions")** als Subtitle pro Checkbox-Card fehlen im Flutter-Code. Aktuell wird nur `l.csvExportCount(state.count)` als Gesamtzahl unten angezeigt. Quality-Gate-Vorschlag: pro-Modus-Count im `csvExportProvider` exposen und als Subtitle pro Checkbox einbauen.
- **Grabber-Bar** ist im Flutter-Code vorhanden (`Container(width: 36, height: 4, ...)`).
