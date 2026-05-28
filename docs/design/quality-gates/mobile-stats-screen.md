# Quality-Gate: Statistik (Mobile)

**Quelle**: `docs/design/ui_kits/app/StatsScreen.jsx`
**Flutter-Pendant**: `lib/features/stats/presentation/stats_screen.dart` (+ widgets: `stats_trend_chart.dart`, `stats_filter_modal.dart`, `stats_aggregate_block.dart`, `active_filter_tags.dart`, `finisseur_stats_tab.dart`, `match_stats_tab.dart`)
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **AppBar**: Eyebrow `Profil`, Title `Statistik`, Back-Button, Right-Slot mit Filter-Icon (`Icon.Filter`).
2. **Tabs** (`tabs`): 2 Tabs in einer Pill-Container (`bg-sunken`, radius 999, padding 3): "Sniper" / "Finisseur". Aktiver Tab `stone-900` + chalk-50.
3. **Body** (je nach Tab):
   - **Graph-Block** (ZUERST): Section-Head + optional Filter-Tag (`{X} / {total} Distanzen`), Sparkline.
   - **Hero-Row** (2 Spalten): Hero-Cards mit grossem `value` + small `unit` + `label`.
   - **Section "Pro Distanz" / "Pro Konfig"**: Detail-Liste.
4. **Filter-Sheet** (modal): pro Tab unterschiedlich:
   - **Sniper-Filter**: Quick-Row (`Alle` / `Stamm 8 m` / `Keine`) + 3-col Grid mit Distanz-Chips (4.0 m, 4.5 m, ... 8.0 m).
   - **Finisseur-Filter**: Quick-Row (`Alle` / `Nur Standard` / `Keine`) + List-Row pro Preset (Built-in + User) mit Checkbox-Indikator.

### Farben (Tokens)

| Element | Token |
|---|---|
| Screen-Bg | `--bk-bg` |
| Tabs-Bg | `--bk-bg-sunken` |
| Tab-On | `--bk-stone-900` + chalk-50 |
| Hero-Bg | `--bk-bg-raised` |
| Hero-Val-Default | `--bk-meadow-600` |
| Hero-Val-Wood | `--bk-wood-500` |
| Hero-Val-Muted | `--bk-fg` |
| DistList-Bg | `--bk-bg-raised` |
| DistTrack-Bg | `--bk-stone-100` |
| DistFill-Sniper | `--bk-meadow-500` |
| DistFill-Finisseur | `--bk-wood-400` |
| Filter-Tag-Bg | `--bk-meadow-100` |
| Filter-Tag-Fg | `--bk-meadow-600` |
| UserBadge-Bg | `--bk-meadow-100` |
| UserBadge-Fg | `--bk-meadow-600` |
| Spark-Stroke (Sniper) | `--bk-meadow-600` |
| Spark-Fill (Sniper) | `--bk-meadow-100` |
| Spark-Stroke (Finisseur) | `--bk-wood-500` |
| Spark-Fill (Finisseur) | `--bk-wood-100` |
| FilterSheet-Backdrop | rgba(12,11,7,0.55) |
| FilterSheet-Bg | `--bk-bg` |
| fChip-Off | `--bk-bg-raised` + inset 1.5px line |
| fChip-On | `--bk-meadow-500` + white |
| fListRow-On | `--bk-meadow-100` + inset meadow-500 |
| fCheck-On | `--bk-meadow-500` + white |

### Typografie

- Tabs: Display 14px weight 600.
- Section-Head: 11px weight 600 uppercase fg-muted.
- Filter-Tag: Mono 10px weight 600 meadow-600 tracking 0.04em.
- Hero-Lbl: 11px weight 600 uppercase fg-muted.
- Hero-Val: Display weight 800 lineHeight 1 tracking -0.03em `tabular-nums`. fontSize:56 (`big`) oder 40.
- DistLbl: Display 13px weight 700.
- DistRatio: Mono 10px fg-muted.
- UserBadge: Mono 9px weight 600 uppercase meadow-600.
- DistTrack-Fill-Width: prozentual zu `rate`.
- DistVal: Display 16px weight 700 right-aligned `tabular-nums`.
- DistMeta: Mono 11px fg-muted right.
- Spark: SVG, 320x96 viewBox.
- SparkRow: Mono 11px fg-muted.
- SheetEyebrow: 11px weight 600 uppercase fg-muted.
- SheetTitle: Display 22px weight 700.
- fQuick: Display 13px weight 600.
- fChip: Display 14px weight 700 `tabular-nums`.
- fListLabel: Display 14px weight 700.
- fListRatio: Mono 12px fg-muted.
- fApply: Display 17px weight 700.

### Spacing

- Tabs: `margin 0 16px 14px`, padding 4, gap 6.
- Body: `padding 0 16px 18px`, gap 14.
- GraphBlock: gap 6.
- HeroRow: 2 cols gap 10.
- Hero-Card: padding `12px 14px`, gap 2.
- DistList: `padding 10px 12px`, gap 6.
- DistRow: padding `4px 0`, Grid `minmax(96px, 1fr) 1.2fr 56px 36px` gap 10.
- DistTrack: height 8.
- Spark-Card: padding `10px 12px`.
- EmptyFilter: padding `14px 12px`, gap 10.
- Sheet: padding `10px 18px 28px`, gap 12.
- fGrid: 3 cols gap 8.
- fChip: minHeight 48, padding `0 6px`.
- fList: gap 6.
- fListRow: minHeight 54, padding `8px 14px`, Grid `1fr auto 28px` gap 10.

### Border-Radius

- Tabs: 999 + Inner-Btn 999.
- Hero: 16.
- DistList: 14.
- DistTrack/DistFill: 999.
- Spark: 14.
- EmptyFilter: 12.
- Sheet: top-radius 24.
- fChip: 12.
- fListRow: 12.
- fCheck: 6.
- fApply: 14.

### Shadows

- Keine prominenten Shadows; alles flat mit Inset-Borders.

### Icons

- `Icon.Filter` (22px) — AppBar Right + Empty-Filter-Hint.
- `Icon.Close` (22px) — Filter-Sheet-Close.

### Brand-Elemente

Keine Brand-Glyphen — Daten-fokussiert.

## Komponenten-Inventar

- `StatsScreen` — Hauptkomponente mit Tab-State.
- `SniperStats` — Render Sniper-Body (Graph + Hero + Liste).
- `FinisseurStats` — Render Finisseur-Body (Graph + Hero + Liste).
- `SniperFilterSheet` — Distanz-Filter mit Chips.
- `FinisseurFilterSheet` — Preset-Filter mit List-Rows.
- `FilterSheet` — generischer Sheet-Wrapper mit Title + Eyebrow.
- `Hero` — Hero-Card (label + value + unit, optional `big` und `tone`).
- `Sparkline` — SVG-Sparkline (Polygon-Fill + Line + End-Dot).
- `EmptyGraph` — Placeholder wenn keine Daten ausgewaehlt.
- `EmptyFilter` — Hinweis wenn Filter alle Selections entfernt.

## Interaktions-Pattern

- **Tab-Switch**: setzt `tab` State, rendert SniperStats/FinisseurStats.
- **Filter-Trigger**: AppBar Filter-Icon → Sheet (pro Tab).
- **Selection-Set** (Sniper): `Set` von Distanz-Strings (`'8.0'`, `'7.5'`, ...).
- **Selection-Set** (Finisseur): `Set` von Preset-IDs (`'std'`, `'5x5'`, ...).
- **Quick-Actions** im Sheet: `Alle`, `Stamm 8 m` (nur 8m), `Nur Standard`, `Keine`.
- **Aggregate-Berechnung**:
  - Sniper: throws-weighted hit-rate ueber Selection.
  - Finisseur: session-count-weighted clean-rate.
  - Trend: per-Index weighted average ueber Selection.
- **Empty-Filter**: wenn `sel.length === 0`, zeigt EmptyFilter + EmptyGraph.

### Loading / Error / Empty-States

- Empty-State explizit modelliert (EmptyFilter + EmptyGraph).
- **Skeleton-Loading** fehlt — AUDIT.md 4.3 flaggt das.

### Spezifisch fuer diesen Screen

- **Sparkline IMMER zuerst** unter der AppBar — bewusste Spec-Entscheidung (siehe Header-Kommentar).
- **Tabs sind genau 2** (`8m` / `finisseur`). Memory-File spricht von "Stats hat Tab Sniper/Finisseur/Match" — moeglicherweise ist Match ein eigener Tab im Flutter. Das Mobile-Kit hat nur 2.
- **Stamm 8 m** als Default-Stamm-Distanz (siehe `SniperFilterSheet`).
- **UserBadge "eigen"** auf User-Presets in der Liste.

## Accessibility

- AppBar 48x48 ✅.
- Tabs: 44dp ✅.
- fChip: 48dp ✅.
- fListRow: 54dp ✅.
- fQuick: 36dp — **knapp unter 48dp**, sollte 44+ sein.
- Spark: SVG ohne `aria-label` / `role="img"` — Flutter sollte das via `Semantics(label: "Trefferrate-Trend...")` ergaenzen.
- Tabular-Nums durchgehend ✅.

## Quality-Gate-Checkliste

- [x] Sparkline-Position (zuerst) explizit.
- [x] Filter-Sheet pro Tab dokumentiert (Distanz-Chips vs. Preset-List).
- [x] Aggregate-Berechnungslogik (throws-weighted) klar.
- [x] Empty-States vorhanden.
- [ ] **Match-Tab** in Flutter aber nicht im Mobile-Kit — pruefen, ob bewusst entfernt.
- [ ] **Skeleton-Loading** fehlt.
- [ ] **`fQuick` 36dp** unter Touch-Standard.
- [x] Tabular-Nums durchgehend.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Match-Tab in Flutter** (siehe `match_stats_tab.dart`): Mobile-Kit hat den nicht. Pruefen, ob das aus dem aktuellen Design entfernt wurde oder ob das Mobile-Kit unvollstaendig ist.
2. **Filter-Sheet** in Flutter ist via `stats_filter_modal.dart` realisiert — pruefen, ob die Quick-Actions (`Alle`, `Stamm 8 m`) abgedeckt sind.
3. **Sparkline-Implementierung**: Flutter typischerweise via `CustomPainter` oder `fl_chart`. Mobile-Kit nutzt SVG direkt.
4. **UserBadge "eigen"**: Flutter sollte die User-Presets visuell vom Built-in trennen — Pruefen via `stats_session_list.dart`.
5. **Aggregate-Trend-Berechnung** (per-Index weighted average) ist Spec-Detail — pruefen, ob Flutter denselben Algorithmus liefert.
6. **`active_filter_tags.dart`** existiert im Flutter — pruefen, ob das ein zusaetzlicher UI-Block ist, der im Mobile-Kit fehlt.
