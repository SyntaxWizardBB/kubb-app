# Quality-Gate: CSV-Export Modal (Mobile)

**Quelle**: `docs/design/ui_kits/app/CsvExportModal.jsx`
**Flutter-Pendant**: `lib/features/settings/presentation/csv_export_modal.dart` (+ Data-Layer in `lib/features/settings/data/`)
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down) — Bottom-Sheet

1. **Backdrop**: `rgba(12,11,7,0.55)`.
2. **Sheet**: top-radius 24, `bg-bg`, maxHeight 92%.
3. **Grabber + Head**: Eyebrow `Daten` + Title `CSV-Export` (Display 24px weight 800), Close-Icon-Button.
4. **Section "Zeitraum"** — Chip-Row (4 Chips): `Alle` / `30 Tage` / `90 Tage` / `Jahr`. Aktiver Chip stone-900 + chalk-50.
5. **Section "Modi"** — 2 Check-Cards untereinander:
   - Sniper-Training — Sub "187 Sessions"
   - Finisseur — Sub "119 Sessions"
   - Aktive Card hat `inset 0 0 0 2px meadow-500` Border; CheckBox-Bg `meadow-500` + Check-Icon.
6. **Preview-Block**: Inset-Card mit `bg-sunken` + Mono-Code-Preview (`sessions.csv` Vorschau, 4 Beispiel-Zeilen) + Meta `{total} Sessions · ~{kb} kB`.
7. **Download-Button**: full-width primary, Display 17px weight 700, Icon.Download + "Herunterladen".

### Farben (Tokens)

| Element | Token |
|---|---|
| Backdrop | rgba(12,11,7,0.55) |
| Sheet-Bg | `--bk-bg` |
| Section-Header | `--bk-fg-muted` |
| Chip-Off | `--bk-bg-raised` + inset 1.5px line |
| Chip-On | `--bk-stone-900` + chalk-50 |
| Check-Card-Bg | `--bk-bg-raised` |
| Check-Card-Inactive-Border | `inset 0 0 0 1.5px line` |
| Check-Card-Active-Border | `inset 0 0 0 2px meadow-500` |
| CheckBox-Off | `transparent` + inset 2px line-strong |
| CheckBox-On | `--bk-meadow-500` + white check |
| Preview-Bg | `--bk-bg-sunken` |
| Preview-Code-Fg | `--bk-fg` |
| Preview-Meta | `--bk-fg-muted` |
| DownloadBtn | `--bk-primary` + chalk-50 |

### Typografie

- Eyebrow: 11px weight 600 uppercase.
- Title: Display 24px weight 800 tracking -0.02em.
- Section: 11px weight 600 uppercase.
- Chip: Display 13px weight 600.
- CheckLbl: Display 15px weight 700.
- CheckSub: 12px fg-muted.
- Preview-Head: Mono 11px fg-muted tracking 0.04em.
- Preview-Code: Mono 11px lineHeight 1.5, `white-space: pre`.
- Preview-Meta: Mono 11px fg-muted.
- DownloadBtn: Display 17px weight 700.

### Spacing

- Sheet: padding `10px 0 40px`.
- Head: padding `4px 18px 12px`.
- Section: padding `8px 18px 8px`.
- ChipRow: padding `0 16px 6px`, gap 8.
- Chip: minHeight 40, padding `0 16px`.
- Checks: padding `0 16px 6px`, gap 8.
- Check: padding `12px 14px`, minHeight 60, gap 12.
- Preview: margin `8px 16px 6px`, padding `10px 12px`.
- DownloadBtn: margin `14px 16px 0`, minHeight 54.

### Border-Radius

- Sheet: top-radius 24.
- Chip: 999 (pill).
- Check: 14.
- CheckBox: 6.
- Preview: 12.
- DownloadBtn: 14.

### Shadows

- Keine.

### Icons

- `Icon.Close` (22px) — Sheet-Close.
- `Icon.Check` (22px) — CheckBox-On + Download-Btn.
- `Icon.Download` (20px) — Download-Button.

### Brand-Elemente

Keine — funktional.

## Komponenten-Inventar

- `CsvExportModal` — Hauptkomponente.
- `Check` — Custom-Checkbox-Card (Icon + Label + Sub, on-state).

## Interaktions-Pattern

- **State**: `range` (default `'all'`), `modes` ({ sniper:true, finisseur:true }).
- **`total`-Berechnung**: `(modes.sniper ? 187 : 0) + (modes.finisseur ? 119 : 0)`.
- **kB-Schaetzung**: `Math.max(2, Math.round(total*0.4))` — grob (~0.4 KB pro Session).
- **Download**: Demo-Code ruft `onClose`. Echte Implementierung muss File erzeugen + share/save.

### Loading / Error / Empty-States

- **Vorschau zeigt immer 4 Zeilen**. Wenn beide Modi ausgeschaltet: `total=0`, Vorschau bleibt aber gleich (Demo). Echte Impl muss Empty-State zeigen.
- Keine Error-States im Kit.

### Spezifisch fuer diesen Screen

- **Range-Chips** sind exklusiv (Single-Select).
- **Mode-Checks** sind multi-Select.
- **Preview-Block** ist statisch — zeigt Beispiel-Zeilen, nicht echte Daten.
- **CSV-Format** im Header: `datum,modus,distanz,wuerfe,treffer,heli,ergebnis`. Sollte Flutter spiegeln.

## Accessibility

- Sheet-Close 48x48 ✅.
- Chip: 40dp — **knapp unter 48dp**.
- Check-Card: 60dp ✅.
- DownloadBtn: 54dp ✅.
- Code-Preview hat `aria-label` nicht — sollte als `pre` mit `aria-label="CSV-Vorschau"` markiert sein.
- Tabular-Nums in Meta ✅ (impliziert ueber Mono).

## Quality-Gate-Checkliste

- [x] Range + Modi Multi-Select-Pattern dokumentiert.
- [x] CSV-Format-Header dokumentiert.
- [x] Preview-Block-Tokens (bg-sunken, mono) konsistent.
- [ ] **Chip 40dp** unter 48dp.
- [ ] **Echte File-Generation + Share** ist Flutter-Aufgabe (`share_plus` + Storage). Demo-Code im Kit nur `onClose`.
- [x] Total + kB-Schaetzung sichtbar fuer User.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **CSV-Format** `datum,modus,distanz,wuerfe,treffer,heli,ergebnis` — pruefen, ob `csv_exporter.dart` denselben Header liefert.
2. **Range-Filter** in Flutter ueber `csv_export_filter.dart`. Pruefen, ob die 4 Optionen (all/30/90/year) abgedeckt sind.
3. **Sniper + Finisseur als Multi-Select** — Flutter sollte beide Modi unabhaengig flaggen koennen.
4. **Live-Preview**: das Kit zeigt statische Beispiel-Zeilen. Echtes Flutter kann via `csv_export_repository` die ersten 3-5 Zeilen aus den realen Sessions ziehen — Quality-Plus.
5. **kB-Schaetzung** ist im Kit hartcodiert (`total*0.4`). Flutter koennte die echte Byte-Groesse zeigen (genauer).
6. **Share vs. Download** in Flutter via `csv_share_service.dart` — pruefen, ob auf iOS `Files` und Android `Downloads` korrekt landen.
7. **Empty-State** (beide Modi off): Mobile-Kit modelliert es nicht — Flutter sollte Download-Btn disablen, wenn `total === 0`.
