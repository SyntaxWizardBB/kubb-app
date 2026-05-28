# Quality-Gate: Stats Screen

**Quelle**: `docs/design/ui_kits/app/StatsScreen.jsx`
**Flutter-Pendant**: `lib/features/stats/presentation/stats_screen.dart` + `lib/features/stats/presentation/widgets/*`
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (top-down)

1. **AppBar** (shared `AppBar`) — Eyebrow `"Profil"`, Title `"Statistik"`, Back-Button links, Filter-Icon-Button rechts (48x48 transparent, `borderRadius: 12`). Sticky-Behaviour fuer den Header.
2. **Tab-Bar** — Pillen-Container `gap: 6`, `background: var(--bk-bg-sunken)`, `borderRadius: 999`, `padding: 4`, `margin: 0 16px 14px`. Zwei Tabs `["Sniper", "Finisseur"]`, jeweils `flex: 1`, `minHeight: 44`, Display 14px weight 600. Aktiver Tab: `background: var(--bk-stone-900)`, `color: var(--bk-chalk-50)`. Tab-Wechsel ueber `useState`.
3. **Body** (padding `0 16px 18px`, flex column gap 14):
   - **Graph-Block** ZUERST (`graphBlock` mit `gap: 6`):
     - Section-Header `"Trefferrate · letzte 4 Wochen"` (Sniper) bzw. `"Saubere Rate · letzte 4 Wochen"` (Finisseur), 11px caps muted.
     - Wenn gefiltert: rechts Filter-Tag-Pille (Mono 10px, Meadow-600 auf Meadow-100, `padding: 2px 8px`, `borderRadius: 999`) mit Count `"X / Y Distanzen"` bzw. `"X / Y Konfigs"`.
     - Sparkline (SVG, 320x96): Meadow-500/100 Tone fuer Sniper, Wood-500/100 fuer Finisseur. Area-Fill + Stroke 2.5 + Endpoint-Circle 4px. Container `background: var(--bk-bg-raised)`, `borderRadius: 14`, `padding: 10px 12px`. Caption-Row Mono 11px: `"vor 4 W"` ... `"<rate> %"` (Display weight 700) ... `"heute"`.
     - Wenn keine Selection: `EmptyGraph` — Container in selber Optik mit Center-Text 13px muted `"Keine Daten — bitte mindestens eine Auswahl im Filter aktivieren."`
   - **Empty-Filter-Banner** (wenn `sel.length === 0`) — flex row `gap: 10`, Filter-Icon + Label 13px muted, Background `bgRaised`, `borderRadius: 12`.
   - **Hero-Row** (2 Spalten gleichbreit, gap 10): Hero-Karten `background: var(--bk-bg-raised)`, `borderRadius: 16`, `padding: 12px 14px`. Inhalt: Label (Eyebrow-Pattern), gefolgt von Display-Number 56px weight 800 + 22px Unit fuer `big`, sonst 40px + 16px. Tone-Switch: `big` → `var(--bk-meadow-600)` (Sniper) bzw. `var(--bk-wood-500)` (`tone="wood"`), `muted` → `var(--bk-fg)`.
   - **Section-Header** `"Pro Distanz"` / `"Pro Konfig"`.
   - **Distanz-/Konfig-Liste** — Container `background: var(--bk-bg-raised)`, `borderRadius: 14`, `padding: 10px 12px`, `gap: 6`. Zeile: `grid-template-columns: minmax(96px, 1fr) 1.2fr 56px 36px`, `gap: 10`, `align-items: center`.
     - Spalte 1 (Label): Display 13px weight 700. Fuer Finisseur: Label + Mono-Ratio `"7/3"` + optional User-Badge.
     - Spalte 2 (Progress-Track): Hoehe 8, `background: var(--bk-stone-100)`, `borderRadius: 999`. Fill: Hoehe 100%, `background: var(--bk-meadow-500)` (Sniper) bzw. `var(--bk-wood-400)` (Finisseur), Breite `${rate}%`.
     - Spalte 3 (Wert): Display 16px weight 700, rechtsbuendig, mit `%`-Suffix (11px, opacity 0.6).
     - Spalte 4 (Meta): Mono 11px muted, rechtsbuendig, Anzahl Wuerfe/Sessions.
4. **Filter-Sheet** (modal, abhaengig vom aktiven Tab):
   - Backdrop `rgba(12,11,7,0.55)`, sheet bgColor `var(--bk-bg)`, top corners 24, `padding: 10px 18px 28px`, `maxHeight: 92%`, scrollable.
   - Head: Grabber + Eyebrow + h2 + Close-Button.
   - **Sniper-Filter**: Quick-Row mit Pills (`"Alle" / "Stamm 8 m" / "Keine"`), Grid 3-spaltig mit Chips fuer alle 9 Distanzen `4.0–8.0` (Display 14px weight 700, `tabular-nums`, `minHeight: 48`, `borderRadius: 12`). Aktiv: Meadow-500 + white, inaktiv: `bgRaised` + 1.5px Line-Inset.
   - **Finisseur-Filter**: Quick-Row `"Alle" / "Nur Standard" / "Keine"`. Liste von Konfig-Zeilen — `grid: 1fr auto 28px`, `minHeight: 54`, `padding: 8px 14px`, `borderRadius: 12`, Background `bgRaised` + 1.5px Line-Inset; aktiv: `meadow100` + 1.5px `meadow500`-Inset. Inhalt: Label + Mono-Ratio + Check-Box-Slot (24x24, `borderRadius: 6`). Active Check-Box: `meadow500` Background, `color: white`.
   - **Apply-Button** unten: full-width, `minHeight: 54`, `borderRadius: 14`, Primary-Background, Display 17px weight 700, Label `"Uebernehmen"`.

### Farben (Token-Namen)

| Bereich | Token |
|---|---|
| Screen Background | `tokens.bg` |
| Tab-Container | `tokens.bgSunken` |
| Tab aktiv | `KubbTokens.stone900` + `KubbTokens.chalk50` |
| Hero-Karten / Distance-List / Sparkline-Container | `tokens.bgRaised` |
| Hero-Number Sniper `big` | `KubbTokens.meadow600` |
| Hero-Number Finisseur `big` | `KubbTokens.wood500` |
| Filter-Tag Background | `KubbTokens.meadow100` |
| Filter-Tag Text | `KubbTokens.meadow600` |
| User-Badge | `KubbTokens.meadow100` / `meadow600` |
| Progress-Fill Sniper | `KubbTokens.meadow500` |
| Progress-Fill Finisseur | `KubbTokens.wood400` |
| Progress-Track | `KubbTokens.stone100` |
| Sparkline Area Sniper | `KubbTokens.meadow100` |
| Sparkline Stroke Sniper | `KubbTokens.meadow600` |
| Sparkline Area Finisseur | `KubbTokens.wood100` |
| Sparkline Stroke Finisseur | `KubbTokens.wood500` |
| Chip aktiv (Sniper-Filter) | `KubbTokens.meadow500` + white |
| Chip inaktiv | `tokens.bgRaised` + 1.5px `tokens.line` |
| Filter-Sheet bg | `tokens.bg` |
| Filter-Sheet Apply-Btn | `tokens.primary` / `tokens.onPrimary` |
| Quick-Filter-Pille | `tokens.bgSunken` |
| Eyebrow / Meta | `tokens.fgMuted` |

### Typografie

| Bereich | Font | Groesse | Weight |
|---|---|---|---|
| Tab-Label | Display | 14 | 600 |
| Section-Header | Body | 11 | 600 (caps, 0.08em) |
| Filter-Tag | Mono | 10 | 600 |
| Hero-Label | Body | 11 | 600 (caps) |
| Hero-Value `big` | Display | 56 | 800 (-0.03em, tabular-nums) |
| Hero-Value default | Display | 40 | 800 |
| Hero-Unit `big` | Display | 22 | 600 muted |
| Dist-Label | Display | 13 | 700 |
| Dist-Ratio | Mono | 10 | — (muted) |
| User-Badge | Mono | 9 | 600 (caps) |
| Dist-Value | Display | 16 | 700 (tabular-nums) |
| Dist-Meta | Mono | 11 | — (muted) |
| Sparkline-Caption | Mono | 11 | — (muted) |
| Quick-Filter-Pille | Display | 13 | 600 |
| Chip | Display | 14 | 700 (tabular-nums) |
| Filter-List-Label | Display | 14 | 700 |
| Filter-List-Ratio | Mono | 12 | — (muted) |
| Sheet-Title | Display | 22 | 700 (-0.02em) |
| Apply-Button | Display | 17 | 700 |
| Empty-Filter | Body | 13 | — (muted) |

### Spacing

- Body padding: `0 16px 18px`, internes gap 14
- Tab-Container margin `0 16px 14px`
- Distanz-Liste padding `10px 12px`, internes gap 6
- Filter-Sheet padding `10px 18px 28px`, internes gap 12
- Chip-Grid gap 8
- Hero-Row gap 10

### Border-Radius

- Tab-Container, Quick-Pille, Progress-Track, Progress-Fill, Filter-Tag, Provider-Badge: `radiusPill` (999)
- Hero-Karten: `radiusXl` (16)
- Distanz-Liste / Sparkline: 14
- Chip / Filter-List-Row: `radiusLg` (12)
- Sheet top corners: 24
- Apply-Button: 14

### Shadows

- Keine harten Shadows; nur `inset 0 0 0 1.5px var(--bk-line)` als Border-Ersatz fuer Chips.

### Icons

- `Icon.Filter` (22px) — AppBar-Right & Empty-Filter-Banner
- `Icon.Back` (in shared `AppBar`)
- `Icon.Close` (Sheet-Header, 22px)

## Komponenten-Inventar

| Sub-Komponente | Aufgabe | Wiederverwendbar | Props |
|---|---|---|---|
| `StatsScreen` | Screen-Root | nein | `onBack, userPresets` |
| `SniperStats` | Sniper-Body | nein (inline) | `selection: Set<string>` |
| `FinisseurStats` | Finisseur-Body | nein (inline) | `selection, userPresets` |
| `SniperFilterSheet` | Sniper-Filter | nein | `selection, setSelection, onClose` |
| `FinisseurFilterSheet` | Finisseur-Filter | nein | `selection, setSelection, userPresets, onClose` |
| `FilterSheet` | Generic-Sheet-Wrapper | ja (intern) | `title, eyebrow, onClose, children` |
| `Hero` | Hero-Number-Block | ja (Kandidat fuer shared) | `label, value, unit, big?, tone?` |
| `Sparkline` | SVG-Trend-Chart | ja | `points: number[], tone?: 'wood'` |
| `EmptyGraph` | Leerer Graph-Placeholder | inline | — |
| `EmptyFilter` | Leerer-Filter-Banner | inline | `label` |
| Dist-Row | Eine Zeile in Distance-/Konfig-Liste | inline | — |
| Chip / Filter-List-Row | Filter-Sheet-Item | inline | — |

**Wiederverwendbar im Sinne der `shared.jsx`**: `Hero` + `Sparkline` sind die zwei reuse-kandidaten — sie tauchen 1:1 fuer beide Tabs auf.

## Interaktions-Pattern

- **Tap-Targets**: Filter-Btn 48x48, Tabs `minHeight: 44`, Chips 48 (Sniper), Filter-List-Rows 54 (Finisseur), Quick-Pillen 36. Tab-Hoehe 44 ist **unter** `KubbTokens.touchMin` (48) — pruefen, ob die Pillen-Tabs noch erreichbar sind.
- **Filter-Toggle**: Tap auf Chip / Konfig-Zeile toggelt Set-Membership. Quick-Buttons setzen Multi-Selection.
- **Tab-Wechsel**: Filter-State pro Tab separat gehalten (`sniperSel`, `finSel`). Filter-Sheet wird je nach `tab` mit Sniper- oder Finisseur-Variante geoeffnet.
- **Loading-States**: JSX zeigt Mock-Daten direkt — Flutter muss `StatsAggregateProvider` AsyncValue handhaben (`loading → CircularProgressIndicator`, `error → Text`). Bereits in `_SniperTab` umgesetzt.
- **Empty-States**:
  - Keine Sessions: Flutter `_EmptyState` mit Titel/Body. JSX hat keinen aequivalenten "noch keine Trainings"-State — der Mock-Datensatz zeigt immer Werte. Empfehlung: Flutter-Empty-State beibehalten.
  - Filter leert Selection: JSX zeigt `EmptyFilter` + `EmptyGraph`. Flutter `ActiveFilterTags` + Filter-Sheet sollte gleich behandeln.
- **Error-States**: JSX hat keine. Flutter rendert `Center(child: Text(e.toString()))` — verbesserungswuerdig (mit Retry-Button).
- **Navigation-Pfade**:
  - Back → Vorgaenger-Screen (Home oder Settings, Flutter haendelt das mit `canPop`-Fallback auf `/`).
  - Filter-Button → Filter-Sheet (modal, dismissable via Backdrop).
  - Tab-Wechsel: interner State, kein Routing.
  - Apply-Button: schliesst Sheet ohne separate Submission (State ist bereits live).

## Accessibility-Hinweise

- **Kontrast**:
  - Tab aktiv `stone900 / chalk50` ~16:1 (sehr gut).
  - Hero-Number Meadow-600 auf bgRaised: ~6:1 (AA fuer grossen Text easy).
  - Filter-Tag Meadow-600 auf Meadow-100: ~4.4:1 — gerade so AA fuer 10px (knapp). Pruefen mit Tool.
  - Progress-Fill Meadow-500 auf Stone-100: gut.
  - User-Badge Meadow-600 auf Meadow-100 ist informativ 4.4:1.
- **Touch-Targets**: alle ≥ 36–48dp. Tab-Hoehe 44 → in Flutter mit Padding auf ≥ 48 anheben.
- **Reader-Labels**:
  - Filter-Btn: `aria-label="Filter"` → Flutter `tooltip: l.statsFilterTitle`
  - Sheet-Close: `aria-label="Schliessen"`
  - Tab-Labels lesbar (Display-Font).
- **Tabular Numerals**: Mehrfach via `fontVariantNumeric: tabular-nums` → Flutter `FontFeature.tabularFigures()`. Pruefen ob alle numerischen Felder das setzen (Hero-Value, Dist-Value, Chip-Label).

## Quality-Gate-Checkliste (pruefbar gegen Flutter-Impl)

- [ ] AppBar mit Eyebrow `"Profil"`, Title `"Statistik"`, Back + Filter-Action.
- [ ] Tab-Bar: 2 Tabs (Sniper, Finisseur) — JSX hat **nur diese zwei**. Flutter hat aktuell 3 Tabs (Sniper, Finisseur, Match). Match-Tab ist Phase-1-Erweiterung — Entscheidung dokumentieren.
- [ ] Tab-Bar Pillen-Style mit `bgSunken` Container und `stone900` aktivem Tab (Flutter aktuell `Material TabBar` — visual mismatch).
- [ ] Graph-Block IMMER zuerst (Sparkline oder EmptyGraph), dann Heros, dann Liste.
- [ ] Sparkline mit `area + stroke + endpoint-circle`, tonal differenziert (Sniper Meadow vs. Finisseur Wood).
- [ ] Hero-Row mit 2 Karten `1fr 1fr`, Display-Number 56px (`big`) + 22px Unit, sekundaere Hero `40 / 16`.
- [ ] Pro-Distanz-Liste mit 4-Spalten-Grid und Progress-Track-Visualisierung.
- [ ] Pro-Konfig-Liste analog, mit User-Badge fuer eigene Presets.
- [ ] Filter-Sheet als Modal (Bottom-Sheet) mit Quick-Row + Grid/List + Apply-Btn.
- [ ] Sniper-Filter: Quick-Buttons `"Alle / Stamm 8 m / Keine"`.
- [ ] Finisseur-Filter: Quick-Buttons `"Alle / Nur Standard / Keine"`, Liste mit Built-in + User-Presets.
- [ ] Filter-Tag-Pille im Graph-Header wenn gefiltert.
- [ ] EmptyGraph / EmptyFilter Banner bei leerer Selection.
- [ ] Alle Tokens aus `KubbTokens` (keine inline Hex).
- [ ] Tabular-Numerals fuer alle numerischen Display-Felder.
- [ ] Touch-Targets ≥ 48dp (Tabs anheben).
- [ ] Loading + Error States: explizit gerendert (mit Retry-Button bei Error).
- [ ] Keine UUID-Substrings (Distanz-Label "4.0 m" statt internal ID; User-Preset-Label `p.label`).
- [ ] i18n via `AppLocalizations`.

## Bekannte Abweichungen (Flutter aktuell vs. Design)

1. **Dritter Tab "Match"**: Flutter hat Sniper/Finisseur/Match — JSX hat nur Sniper/Finisseur. Match-Tab ist eine Phase-1-Erweiterung (Tournament-Foundation). Im Quality-Gate dokumentieren, dass das Design das nicht abdeckt; Match-Tab uebernimmt aequivalentes Layout.
2. **TabBar-Visual**: Flutter nutzt das Material-3 `TabBar`-Widget mit Indikator-Line. JSX zeigt Pillen-Tabs mit `bgSunken` Container und vollflaechig aktivem Tab — visueller Mismatch. Entscheidung: Pillen-Style einbauen (Custom-Tabs) oder Material-TabBar belassen.
3. **AppBar-Title-Alignment**: shared-Component-Notiz; pruefen.
4. **Graph-Order**: Sparkline muss **vor** den Hero-Karten kommen (per JSX-Spec — siehe Header-Comment "GRAPH ZUERST"). Flutter `_Body` rendert die Reihenfolge: `StatsTrendChart` → `StatsAggregateBlock` → `_BestsBlock` → `_SectionHead("Sessions")` → `StatsSessionList`. **Mismatch**: Flutter hat `_BestsBlock` (Bestleistungen) + `StatsSessionList` (Session-History) als zusaetzliche Sektionen, die JSX nicht hat. JSX hat dafuer "Pro Distanz"-Liste mit Progress-Tracks. Entscheidung treffen — die JSX-Variante ist die "Soll"-Spec.
5. **Pro-Distanz-Liste fehlt im Flutter**: die Distanz-Auflistung mit Progress-Track ist eine der **Kern-Visualisierungen** der JSX-Spec. Aktuell Flutter zeigt `_BestsBlock` und `StatsSessionList`, was eine andere Information-Hierarchie ist.
6. **Filter-System**: JSX-Filter hat Quick-Buttons (`Alle / Stamm 8 m / Keine`) und Chip-Grid (`4.0 m – 8.0 m`). Flutter-Pendant `stats_filter_modal.dart` pruefen — vermutlich vorhanden, aber Detail-Mismatch moeglich.
7. **Filter-Tag-Pille im Graph-Header** zeigt "X / Y Distanzen" bei aktivem Filter — pruefen ob `ActiveFilterTags` das macht.
8. **`_BestsBlock`** (Beste Hit-Rate, Streak, Day) ist Flutter-only. Entweder ins Design uebernehmen (Design-Issue) oder aus Flutter entfernen (Code-Issue). Entscheidung dokumentieren.
9. **Tab-State**: Flutter nutzt `TabController` mit drei Tabs; JSX nutzt `useState('8m' | 'finisseur')`. Logik identisch, nur Widget-Wahl unterschiedlich.
10. **Mock-Daten vs. echte Aggregate**: JSX hat hardcoded Mock-Daten — der Flutter-Code ruft `statsAggregateProvider` auf. Beim Visual-Vergleich darauf achten, dass die Aggregate-Struktur (per Distanz, per Konfig, gewichteter Trend) abgebildet ist.
