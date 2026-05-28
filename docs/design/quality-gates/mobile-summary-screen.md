# Quality-Gate: Session-Summary (Mobile)

**Quelle**: `docs/design/ui_kits/app/SummaryScreen.jsx`
**Flutter-Pendant**: `lib/features/training/presentation/summary_screen.dart`
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **AppBar**: Eyebrow `Session beendet`, Title:
   - Sniper (single): `Sniper · {distance} m`
   - Sniper (multi-distance): `Sniper · 8.0 m · 6.5 m · 4.0 m` (alle Distanzen joined)
   - Finisseur: `Finisseur · {config}` (z.B. `7/3`)
2. **Verdict-Card** (Hero):
   - Bg: meadow-500 (Sniper / Finisseur erfolgreich) ODER stone-700 (Finisseur nicht geschafft).
   - Sniper: Big-Num = Trefferquote (`{rate}<small> %</small>`), Sub = "Trefferquote · {total} Wuerfe in {duration}".
   - Finisseur: Tag oben ("Sauber finished" / "Nicht geschafft"), Big-Num = `{sticksUsed}<small> / 6</small>`, Sub = "Stoecke benoetigt · {duration}".
3. **Body**:
   - Sniper Multi-Distance: Section "Pro Distanz" + Liste von `distRow`-Cards (Meters + Rate + Pills fuer hit/miss/heli) + Dauer-Row.
   - Sniper Single: 4 Zeilen (Treffer / Miss / Heli / Dauer).
   - Finisseur: 4 Zeilen (Koenigswurf / Strafkubbs / Heli / Dauer).
4. **Action-Row** (2 Spalten, gleich gross): "Verwerfen" (danger) + "Speichern" (primary).
5. **Restart-Button**: full-width, outline-Style (`bg-raised` + inset line-strong), Plus2-Icon + "Neue Session starten".

### Farben (Tokens)

| Element | Token |
|---|---|
| Verdict-Bg (Erfolg) | `--bk-meadow-500` |
| Verdict-Bg (Misserfolg, Finisseur) | `--bk-stone-700` |
| Verdict-Text | `--bk-chalk-50` |
| DistRow-Bg | `--bk-bg-raised` |
| Pill-Bg | `--bk-bg` (innen) |
| DistRate-Farbe | `--bk-meadow-600` |
| Row-Hit | `--bk-hit` |
| Row-Miss | `--bk-miss` |
| Row-Heli | `--bk-heli` |
| Row-Penalty | `--bk-penalty` |
| Row-Muted | `--bk-fg-muted` |
| Discard-Btn | `--bk-danger` + `--bk-on-danger` |
| Save-Btn | `--bk-primary` + `--bk-on-primary` |
| Restart-Btn | `--bk-bg-raised` + `inset 0 0 0 2px line-strong` |

### Typografie

- Verdict-Tag (Finisseur): 11px weight 600 uppercase tracking 0.08em opacity 0.85.
- Verdict-Big-Num: Display 90px weight 800 lineHeight 0.9 tracking -0.04em `tabular-nums`. Suffix (`%`, `/ 6`) als 40% des Big-Num.
- Verdict-Sub: 13px opacity 0.85.
- Section-Eyebrow: 11px weight 600 uppercase tracking 0.08em fg-muted.
- DistMeters: Display 22px weight 800 `tabular-nums`.
- DistRate: Display 18px weight 700 meadow-600 `tabular-nums`.
- Pill-Lbl: 10px weight 600 uppercase fg-muted.
- Pill-Val: Display 22px weight 800 `tabular-nums`.
- Row-Lbl: 14px fg-muted.
- Row-Val: Display 22px weight 700 `tabular-nums`.
- Row-Mono (Dauer): Mono 17px weight 500 `tabular-nums`.
- Discard/Save-Btn: Display 17px weight 700.
- Restart-Btn: Display 16px weight 700.

### Spacing

- Verdict: `margin 10px 16px 14px`, padding `22px 18px 18px`.
- Body: `padding 4px 16px`, `flex:1, overflow auto`.
- DistList: gap 8.
- DistRow: padding `12px 14px`, gap 10.
- DistNumbers: 3 cols gap 6.
- Pill: padding `8px 6px`, gap 2.
- Row: padding `12px 0`, borderBottom 1px line.
- Actions: gap 10, padding `10px 16px 8px`.
- Restart: `margin 4px 16px 0`, minHeight 54.

### Border-Radius

- Verdict-Card: 20
- DistRow: 14
- Pill: 10
- Action-Buttons: 14
- Restart-Btn: 14

### Shadows

- Keine — Verdict-Card ist farb-getrieben, andere Cards bewusst flat.

### Icons

- `Icon.Back` (22px) — AppBar.
- `Icon.Plus2` (20px) — Restart-Button (Neue Session).

### Brand-Elemente

Keine Brand-Glyphen — Verdict ist farbgetrieben (meadow / stone).

## Komponenten-Inventar

- `SummaryScreen` — Hauptkomponente, `kind` Prop steuert `'8m'` vs. `'finisseur'`.
- `Row` — generische Label-Value-Zeile mit Tone.
- `Pill` — kompakte 3-Spalten-Cell in der Distanz-Liste (label + value + tone).

## Interaktions-Pattern

- **`onSave` / `onDiscard`**: Action-Buttons.
- **`onRestart`**: Restart-Button → neue Session.
- **`onBack`**: AppBar → zurueck.
- **Multi-Distance-Detection**: `kind === '8m' && d.breakdown && d.breakdown.length > 1`.
- **Aggregate-Berechnung**: throws-weighted hit-rate ueber alle Distanzen.

### Loading / Error / Empty-States

- Keine async-States — Daten kommen als Prop.
- Default-Sample im Kit fuer Demo.

### Spezifisch fuer diesen Screen

- **Multi-Distance-Breakdown** ist NEU im Mobile-Kit. Eine Session kann ueber mehrere Distanzen gehen (z.B. 8m → 6.5m → 4m), Summary listet jede einzeln auf mit eigener Rate.
- **Verdict-Bg-Color** unterscheidet bei Finisseur zwischen `success` (meadow) und `fail` (stone-700). Bei Sniper immer meadow (keine "Fail"-Logik in Trefferquote).
- **Suffix** im Big-Num (z.B. ` %` oder ` / 6`) ist 40% der Big-Num-Groesse — visuelle Hierarchie.

## Accessibility

- AppBar 48x48 ✅.
- Tap-Targets: Action-Buttons 54dp, Restart 54dp ✅.
- Tabular-Nums durchgehend ✅.
- Kontrast: chalk-50 auf meadow-500 (#3A7C2E) — ~7:1 (AAA).

## Quality-Gate-Checkliste

- [x] Sniper- und Finisseur-Varianten dokumentiert.
- [x] Multi-Distance-Breakdown-Pfad explizit.
- [x] Tabular-Nums.
- [x] Touch-Targets ≥ 48dp.
- [ ] **Aggregate-Trend ueber Multi-Distance** ist in `StatsScreen.jsx` modelliert — Summary zeigt nur Snapshot, kein Trend. Konsistenz ist OK.
- [ ] **Empty-Verdict** (z.B. Session abgebrochen mit 0 Wuerfen) ist nicht modelliert — soll ueber `onDiscard` direkt von der Session-Screen aufgerufen werden, bevor Summary erscheint.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Multi-Distance-Breakdown** ist neu — pruefen, ob `summary_screen.dart` das schon kann oder ob Erweiterung noetig.
2. **Verdict-Tag** (Finisseur "Sauber finished" / "Nicht geschafft") ist hartcodiert deutsch — sollte ueber `AppLocalizations` laufen.
3. **Suffix-Skalierung** (40% des Big-Num) ist eine CSS-Detail — Flutter `RichText` mit `TextSpan + WidgetSpan` oder `Text.rich` faellig.
4. **Restart-Button als Ghost-Style** (inset border) — Flutter `OutlinedButton` mit thick border.
5. **`d.breakdown`-Schema** ist hier informell: `[{ distance, hits, misses, helis }]`. Flutter sollte das als `SniperDistanceBreakdown` Value-Object modellieren.
6. **Dauer-Format**: `14:32` (mm:ss) bzw. `4:12`. Mono-Schriftart konsistent.
