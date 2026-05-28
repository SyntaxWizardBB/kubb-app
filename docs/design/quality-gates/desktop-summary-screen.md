# Quality-Gate: Summary (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/SummaryScreen.jsx`
**Flutter-Pendant**: Training-Summary als Phone-Screen (`lib/features/training/.../summary`) — Desktop-Hero-Verdict FEHLT
**Tablet/Desktop-Breakpoints**: ab 900 dp Verdict-Hero + Split; ab 1280 dp Full-Bleed Verdict bis 1280 dp Max
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur
- TopBar: Eyebrow `Session beendet · gerade eben`, Title je nach Kind (Sniper / Finisseur), Subtitle mit Distanz / Konfig / Wuerfe / Dauer. Right-Slot: Kind-Switcher (Pill Sniper / Finisseur).
- Body `padding: 24px 40px 48px`, `max-width: 1280`, Layout-Gap 20.
- **Verdict-Hero-Strip** (`border-radius: 20`, `padding: 28px 32px`, `min-height: 180`, `background` Meadow-600 oder Stone-700 wenn finisseur-fail):
  - Links (`flex: 1`): Eyebrow + Verdict-Big (128 px ui weight 800, line-height 0.85, tabular) + Sub mit Wurf-Aufschluesselung.
  - Rechts (Column, min-width 200): 3 Mini-Rows (Dauer / Start / Wuerfe-Min oder ELO), Border-Top zwischen Rows in `rgba(255,255,255,0.18)`.
- **Split** (`grid-template-columns: 1.6fr 1fr`, gap 18):
  - **Linke Spalte** (Column gap 18):
    - **Sniper**: Card "Pro Distanz" Tabelle (Distanz / Quote-Bar mit Overlay-Rate / Treffer / Miss / Heli / Wuerfe), letzte Row "Gesamt" mit Sunken-BG.
    - **Finisseur**: Card "Per-Stick Log" (6 Sticks, jede Row: Idx / Pip / Label / Time, Skipped-Sticks mit opacity 0.4).
    - Card "Statistik aktualisiert" — Impact-Grid 2 × 2 mit before → after-Veraenderungen + Delta-Up.
  - **Rechte Spalte** (Column gap 18):
    - Card "Aktionen": Primary `Speichern & weiter`, Secondary `Speichern + neue Session`, Ghost `Zu deiner Statistik`, ThinLine, Ghost `Letzten Wurf bearbeiten`, Discard-Button (underlined Miss-Color).
    - Card "Teilen": Note + Share-Chips (3 Personen-Avatare + BKC-Chip in Stone-900).

### Farben
- Verdict-Hero Sniper: Meadow-600 BG, Chalk-50 Text.
- Verdict-Hero Finisseur-Success: Meadow-600.
- Verdict-Hero Finisseur-Fail: Stone-700.
- Distanz-Track-Overlay-Rate: `mix-blend-mode: difference; filter: invert(1)` — Trick fuer Lesbarkeit auf jedem Hintergrund.
- Track-Fill: Meadow-400 → 600 Gradient.
- Pip-Color: hit Meadow-500, heli Heli-Token, penalty Penalty-Token, king King-Token, skipped Stone-200.
- Impact-Before: muted mono, After: 22 px ui weight 800.
- Discard-Button: transparent BG, Miss-Color, underline.

### Typografie
- Verdict-Big 128 px ui weight 800 line-height 0.85 tabular.
- Verdict-Unit (`%` oder `/ 6`) 32 px weight 600 opacity 0.7.
- Distanz-Meters 18 px ui weight 700 tabular.
- Impact-After 22 px ui weight 800.
- Stick-Label 14 px ui weight 600.
- Share-Note 13 px muted.

### Spacing
- Body-Gap 20.
- Verdict-Padding `28px 32px`. Mini-Rows Padding `8px 0`.
- Table Th `8px 22px`, Td `12px 22px`.
- Impact-Grid gap 12, padding `12px 14px` per Item.

### Border-Radius
- Verdict-Hero 20. Cards 16. Impact-Items 12. Share-Chips 999. Discard-Button text-only.

### Shadows
- Cards Default `--kc-shadow-1`. Verdict-Hero kein Shadow.

### Icons
- `DIcon.Plus` (Speichern & weiter, Speichern + neue), `DIcon.Undo` (Letzten Wurf bearbeiten).

## Komponenten-Inventar

- Shared: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `CardHeader`, `DIcon`.
- Lokal:
  - `Impact` (label + before → after + delta).
  - `PIP`-Map (hit / heli / penalty / king / skipped).

**Unterschied Mobile**: Phone-Summary hat vermutlich vertikalen Hero (kein 128 px Verdict), keine Share-Section seitlich (eher Bottom-Sheet), Aktionen als Stack.

**Flutter-Aequivalente**:
- Verdict-Hero → `Container(decoration: BoxDecoration(borderRadius, color))`.
- Tabelle → `DataTable` mit Custom-Cell fuer den Quote-Bar (Stack mit Overlay-Text).
- Stick-Log → `Column` mit `Row`s.
- Share-Chips → `Wrap` mit Custom-Chips.

## Interaktions-Pattern

- **Kind-Switcher**: Pill-Switcher im TopBar. Wechselt Datenquelle Sniper vs. Finisseur (im JSX nur Demo, real ist Kind by Session-Type fix).
- **Discard-Btn**: navigiert ohne Save zurueck. Sollte Confirm-Dialog haben.
- **Speichern & weiter**: persistiert Session + navigiert zurueck zu Dashboard.
- **Letzten Wurf bearbeiten**: oeffnet Edit-Modal (im JSX nicht modelliert).
- **Share-Chips**: Click → Share-Action (`InviteUser`-RPC oder OS-Share-Sheet).
- **Loading**: Verdict-Hero kann sofort gerendert werden (Save-State ist lokal); Impact-Grid braucht Aggregation-Refresh.
- **Empty**: nie leer (Summary nur nach abgeschlossener Session).

## Accessibility

- **Tab-Order**: Kind-Switcher → Hero (statisch) → Sub-Tabelle/Stick-Log (Headers fokussierbar) → Impact-Grid (statisch) → Aktionen-Buttons in Reihenfolge → Discard (separater Focus, sollte vor Confirm landen) → Share-Chips.
- **Discard-Confirmation**: Pflicht, da destruktive Aktion.
- **Min-Window-Width**: 1024 dp fuer Split. Darunter Stack: Hero → Linke Spalte → Rechte Spalte.
- **Kontrast Verdict**: Chalk-50 auf Meadow-600 = sehr hoher Kontrast (AAA), passt.
- **Distanz-Bar-Overlay**: `mix-blend-mode: difference` ist CSS-only — in Flutter via `Stack` mit `Text` und `BlendMode.difference` auf `ColorFiltered` Layer. Alternative: Text immer auf hellem Track ueber dem Fill positionieren (saubere Loesung).

## Quality-Gate-Checkliste

- [ ] Verdict-Hero 128 px Big-Number, korrektes BG je nach Success/Failure.
- [ ] Mini-Rows mit Border-Top rgba(255,255,255,0.18) im Hero.
- [ ] Sniper-Tabelle 6 Spalten + Gesamt-Row Sunken-BG.
- [ ] Quote-Bar mit Overlay-Rate (Lesbarkeit auf hellem + dunklem Teil).
- [ ] Finisseur Stick-Log 6 Sticks mit Pip-Tone-Mapping.
- [ ] Skipped-Sticks opacity 0.4.
- [ ] Impact-Grid 2 × 2 mit before → after.
- [ ] Aktionen-Card: Primary + 2 Secondary + ThinLine + Edit + Discard.
- [ ] Discard-Button mit Confirmation-Dialog.
- [ ] Teilen-Card mit 3 Personen-Chips + BKC-Chip.
- [ ] Body max-width 1280.
- [ ] Save persistiert Drift + ggf. Supabase-Sync.

## Implementations-Hinweise fuer Flutter

- **Verdict-Hero**: einfacher `Container` mit `BoxDecoration` (Meadow-600 oder Stone-700 je nach Success). Token-direkt.
- **Quote-Bar-Overlay**: `Stack` mit `LinearProgressIndicator` (custom) + zentriertem `Text`. `BlendMode.difference` via `ColorFiltered` ist moeglich aber komplex. Empfehlung: **immer hellen Text auf dunklem Fill UND dunklen Text auf hellem Track, mit `Visibility` per Schwellwert** — simpler.
- **Tabelle**: Material `DataTable` mit `DataCell(rowChild)` fuer den Quote-Bar.
- **Stick-Log**: `Column` von `Row`s; Pip ist `Container(width: 10, height: 10)` mit Token-Color.
- **Discard-Confirm**: `showDialog` mit Two-Button-Dialog ("Verwerfen" / "Abbrechen").
- **State**: `summaryProvider(sessionId)` liefert die ganze Aggregat-View. Save-Action via `trainingSessionRepository.persist(...)`.
- **Komplexitaet**: **M**. 3 – 5 Tage. Logik bereits in Phone-Pendant, Desktop ist Layout-Variante.
- **Pakete**: keine neuen.
