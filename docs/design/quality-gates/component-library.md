# Quality-Gate: Component-Library (Kubb Club)

**Quelle**: `docs/design/preview/components-*.html` (8 Previews)
**Flutter-Pendant**: `lib/core/ui/widgets/` plus feature-lokale Widgets unter `lib/features/*/presentation/widgets/`
**Stand**: 2026-05-28 (Rebrand `--bk-*` → `--kc-*`, Kubb Club)
**Cross-Reference**: `docs/design/ui_kits/app/shared.jsx` (Mobile), `docs/design/ui_kits/desktop/shared.jsx` (Desktop), `docs/design/AUDIT.md` §1, §3, §5

---

## Komponenten-Katalog

### 1. AppBar **NEU**

**Visual-Spec** (`components-appbar.html`)
- Höhe: ~88 dp inkl. Status-Area
- Layout: `[ Back 48dp ] [ Title-Block flex ] [ Right-Slot 48dp ]`
- Title-Block zentriert, zweizeilig:
  - Eyebrow: 11 px, weight 600, letter-spacing 0.08em, uppercase, `--kc-fg-muted`
  - Title: 18 px, weight 700, letter-spacing −0.02em, `--kc-fg`
- Icons: 22 px, stroke 2.2, Lucide-Look
- Touch-Target Back/Action: 48 × 48 dp
- Bottom: 1 px Hairline `--kc-line` (Preview), Flutter aktuell ohne Hairline

**Varianten**
- A — Standard Subpage: Eyebrow + Title + Back + optional Right-Slot (`components-appbar.html`)
- B — Home: kein Back, Right-Slot ist Settings-Icon, Logo-Mark im Title-Block (kommt mit Brand-Pflicht — siehe `brand-assets.md`)
- C — Profile/Account: Avatar im Right-Slot statt Icon (siehe `_archive_brosi/profile-screen.md`)

**Flutter-Pendant**: `lib/core/ui/widgets/kubb_app_bar.dart` → `KubbAppBar`
- Status: **sauber abgebildet**, nutzt `KubbTokens.touchMin` (48 dp), korrekte Typographie (18 px, 11 px eyebrow), `--kc-*` Theme-Extension aktiv.
- **Drift**: keine Hairline-Bottom-Line wie im Preview. Klein, optional Sprint-B-Polish.
- **Logo-Slot fehlt**: Home-Variante muss noch verdrahtet werden — siehe `brand-assets.md` Pflicht.

---

### 2. Buttons

**Visual-Spec** (`components-buttons.html`)
- Min-Height 48 dp, Radius 12 px, Padding 0 18 px, Gap 8 px, Weight 700, 15 px
- Varianten:
  - **Primary**: `--kc-meadow-500` Background, `--kc-on-primary` Foreground, Shadow `--kc-shadow-1`. Hover → `--kc-meadow-600`
  - **Secondary**: Transparent, Inset-Border 1.5 px `--kc-stone-900`, `--kc-fg`
  - **Ghost**: Transparent, kein Border, `--kc-fg`
  - **Danger**: `--kc-miss` Background, `--kc-on-danger`
  - **Accent (Match)**: `--kc-stone-900` Background, `--kc-chalk-50` Foreground
  - **FAB Training**: Min-Height 56 dp, Padding 0 22px 0 18px, Radius 16 px, `--kc-meadow-600`, Shadow `--kc-shadow-2`, 17 px

**States (Pflicht für jede Variante)**
- Default / Hover / Pressed (Ripple via Material) / Disabled (50 % Opacity) / Loading (CircularProgressIndicator 18 dp anstelle des Labels)

**Flutter-Pendant**: **kein `KubbButton`** — aktueller Stand nutzt rohes Material-`FilledButton`/`OutlinedButton`/`TextButton` plus feature-lokale Wrapper (`auth_primary_button.dart`, `auth_secondary_button.dart`).
- **Status: Komponente ohne zentrales Pendant.** Auth-Wrapper sind kein vollständiger Ersatz.
- **Vorschlag Sprint-B**: `lib/core/ui/widgets/kubb_button.dart` mit `KubbButtonStyle.primary/secondary/ghost/danger/accent` + `KubbFab.training`. Auth-Wrapper darauf umbiegen.

---

### 3. Chips

**Visual-Spec** (`components-chips.html`)
- Min-Height 32 dp, Radius 999 (pill), Padding 0 14 px, 13 px / weight 600
- Tone-Pairs:
  - Sniper: `--kc-meadow-100` bg / `--kc-meadow-700` fg
  - Finisseur: `--kc-wood-100` / `--kc-wood-700`
  - Match: `--kc-stone-100` / `--kc-stone-700`
  - Solid (aktiv): `--kc-meadow-500` / `#fbfaf6`
  - Outline (Standard-Wert): Inset 1.5 px `--kc-stone-900`
  - Toggle (Heli ein): `--kc-stone-900` / `#fbfaf6`
  - Bad (Strafkubb): `#f8e2dd` / `#7a2517`
  - Heli passiv: `--kc-wood-100` / `--kc-wood-700`

**Flutter-Pendant**: kein zentraler `KubbChip`. Mehrere Insellösungen:
- `team_slot_chip.dart` (Match)
- `_BigChip`, `_NumChip`, `_RangeChip`, `_OutcomeChip`, `_QualifierChip`, `_SoonChip` (feature-lokal, private, dupliziert)
- Direkt `ChoiceChip` in `anonymous_signup_flow.dart`, `csv_export_modal.dart`
- **Status: Drift.** Pro-Feature-Duplikation widerspricht dem Preview-Token-Set.
- **Vorschlag Sprint-B**: `lib/core/ui/widgets/kubb_chip.dart` mit `KubbChipTone.sniper/finisseur/match/solid/outline/toggle/bad/heli` und optionalem `selected`-Boolean. Bestehende `_*Chip`-Klassen sukzessive ablösen.

---

### 4. Counter (Sniper/Finisseur Hero + Strip)

**Visual-Spec** (`components-counter.html`)
- Hero-Counter: 120 px, weight 800, line-height 0.85, letter-spacing −0.05em, tabular-nums, `--kc-fg`
- Strip-Counter (Würfe gesamt / Miss / Heli / Quote): Label 10 px mono uppercase muted, Value 32 px weight 700 letter-spacing −0.02em, Tone via `--kc-hit`/`--kc-miss`/`--kc-heli`
- Quote-Suffix `%` ist 18 px weight 600 inline am Value

**Flutter-Pendant**: `lib/core/ui/widgets/kubb_counter.dart` → `KubbCounter`
- Status: **abgebildet, aber nur als Strip-Variante** (Label 11 px, Value 38 px). Hero-Counter (120 px) ist im Sniper-Screen vermutlich inline; lohnt Verlagerung in `KubbCounter.hero(...)`.
- **Drift**: Strip-Value 38 px statt 32 px im Preview — bewusst grösser, beibehalten.
- **Vorschlag Sprint-B**: `factory KubbCounter.hero({...})` ergänzen, Sniper-Screen darauf umstellen.

---

### 5. ModeCard **NEU**

**Visual-Spec** (`components-modecard.html`)
- Tile 200 × ≥128 dp, Radius 18, Padding 16, Shadow `--kc-shadow-1`, Foreground `#fbfaf6`
- Layout: Eyebrow (mono 10 px uppercase, opacity 0.85) → Name (22 px weight 800) → Sub (12 px opacity 0.85) → Num (32 px weight 800 tabular-nums, bottom-right)
- Tone-Switch über Background:
  - Sniper → `--kc-meadow-500`, Num "8 m"
  - Finisseur → `--kc-stone-900` (ink), Num "7/3"
  - Match → `--kc-wood-500` (wood), Num "▶"
- (Tournament-Modus folgt analog — Tone offen, evtl. ein zweiter Wood-Ton)

**Flutter-Pendant**: `_ModeCard` in `lib/features/training/presentation/widgets/training_sheet.dart` (private, feature-lokal).
- **Status: nicht zentral, nur Sheet-intern.** Home-Screen nutzt `TournierCard` als separaten Card-Typ.
- **Vorschlag Sprint-B**: `lib/core/ui/widgets/kubb_mode_card.dart` mit `KubbModeTone.sniperMeadow/finisseurInk/matchWood/tournamentWood`. Sheet + Home gemeinsam darauf umstellen, `TournierCard` ablösen.

---

### 6. SessionCard

**Visual-Spec** (`components-sessioncard.html`)
- Row-Layout `56 dp tag | 80 dp rate | 1fr sub | auto chevron`
- Background `--kc-bg-raised`, Radius 14, Padding 12 14, Shadow `--kc-shadow-1`
- Tag: 11 px mono uppercase muted (z.B. "Sniper", "Fin")
- Rate: 18 px weight 700 tabular-nums (z.B. "64 %", "✓ 5/6", "✗ 6/6" mit `--kc-miss`)
- Sub: 13 px muted, Format "8.0 m · 36 Würfe · gestern"
- Chevron: 24 dp muted

**Flutter-Pendant**: Listen-Widgets im Stats-Tab (`stats_session_list.dart`), `recent_section.dart` als Home-Variante.
- **Status: vorhanden, aber kein wiederverwendbarer `KubbSessionCard`** — beide Listen rendern selbst.
- **Drift**: Rate-Spalte zeigt im Stats-Tab teils nur Numerik, kein `✓/✗`-Glyph wie im Preview.
- **Vorschlag Sprint-B**: `lib/core/ui/widgets/kubb_session_card.dart` mit `KubbSessionTone.sniper/finisseur/match` + optional `outcome: passed/failed`. Beide Callsites darauf konsolidieren.

---

### 7. Slider (Distanz + Range)

**Visual-Spec** (`components-slider.html`)
- Track 8 px, Background `--kc-stone-100`, Radius pill
- Fill: `--kc-meadow-500`
- Thumb: 24 dp, weiss, 2 px Border `--kc-meadow-500`, Shadow `--kc-shadow-2`
- Label-Spalte 90 dp mono 10 px uppercase muted
- Value-Spalte ≥ 64 dp, 18 px weight 700, Format "7.0 m" / "6 / 10" / "3 / 9"
- Optional: Ticks (6 Stück verteilt) via `--kc-stone-200`
- Range-Slider: zwei Thumbs, doppelter Fill-Bereich

**Flutter-Pendant**: nur Material-`Slider` (z.B. `swiss_config_section.dart` Z. 104) und `RangeSlider` (`stats_filter_modal.dart` Z. 229) — kein eigener Look.
- **Status: kein KubbSlider — visueller Drift.** Material-Defaults haben keinen 24-dp-Thumb mit Border und keinen Pill-Track in der Brand-Meadow-Farbe.
- **Vorschlag Sprint-B**: `lib/core/ui/widgets/kubb_slider.dart` als Wrapper um `SliderTheme` + `Slider`/`RangeSlider`. Label/Value-Spalten optional als Parameter.

---

### 8. TapPad-Grid (Sniper/Finisseur)

**Visual-Spec** (`components-tappad.html`)
- Pad: min-height 96 dp, Radius 18, Padding 12 16, Layout Label-left/Sign-right (+/−)
- Tone:
  - Hit → `--kc-hit` Background, `#fbfaf6` Foreground
  - Miss → `--kc-miss`
  - Heli → `--kc-heli` Background, `#0c0b07` Foreground (gelb!)
  - Ghost (Decrement) → `--kc-bg-raised`, Inset-Border `--kc-stone-200`
- Sign-Button: 42 × 42 dp Pill mit Background `rgba(white,0.18)` (Hit/Miss) bzw. `rgba(black,0.18)` (Heli) bzw. `--kc-stone-100` (Ghost), Icon 22 dp stroke 2.5

**Flutter-Pendant**: `lib/core/ui/widgets/kubb_tap_pad.dart` → `KubbTapPad`
- Status: **sauber abgebildet** für Hit/Miss/Heli/Ghost-Tone, Brand-Colors korrekt.
- **Drift**: kein expliziter Sign-Button-Pill (Plus/Minus als 42-dp-Kreis) — der Sign wird als reiner Text (`+`/`−`) gerendert. Nicht-blockierend, aber Preview hat den Pill-Knopf.
- **Vorschlag Sprint-B (klein)**: Sign-Pill als optionales `KubbTapPadSign.button` ergänzen, dann kann das Pad auch Tap-Targets für Decrement bekommen.

---

## Flutter-Mapping-Audit (gesamt)

### Bereits sauber abgebildet

| Komponente | Flutter-Pendant | Bemerkung |
|---|---|---|
| AppBar | `KubbAppBar` | bis auf Home-Logo-Slot komplett |
| Counter (Strip) | `KubbCounter` | Hero-Variante fehlt |
| TapPad-Grid | `KubbTapPad` | Sign-Pill als Polish offen |

### Komponenten ohne Flutter-Pendant

| Komponente | Konsequenz |
|---|---|
| **Buttons** | Material-Defaults + Auth-Wrapper. Kein Brand-Button überall. |
| **Chips** | 5 + private `_*Chip`-Klassen, alle dupliziert. |
| **ModeCard** | Nur Sheet-intern als private `_ModeCard`. Home hat eigene `TournierCard`. |
| **SessionCard** | Eigene Listen-Implementierungen pro Feature. |
| **Slider** | Roh-Material, keine Meadow-Token, kein Brand-Thumb. |

### Komponenten mit visuellem Drift

- **AppBar**: Bottom-Hairline fehlt, Home-Logo-Slot fehlt.
- **Counter**: Strip 38 px statt 32 px (bewusst grösser — OK).
- **TapPad**: Sign als Text statt Pill-Button.
- **Slider**: Material-Default statt Brand-Styling — der grösste sichtbare Drift.

---

## Sprint-B-Empfehlung

Der grösste UI-Quality-Gain pro Aufwand ergibt sich aus dem Zentralisieren der drei meist-replizierten Komponenten:

1. **`KubbChip`** — löst 6 private `_*Chip`-Klassen ab, schliesst den Drift bei Sniper/Finisseur/Match-Tagging über alle Screens.
2. **`KubbModeCard`** — vereint `_ModeCard` (Sheet) und `TournierCard` (Home), zieht den Brand-Tone-Switch Sniper/Finisseur/Match/Tournament konsistent durch.
3. **`KubbSlider`** — der Material-Default-Look auf Distanz- und Range-Slidern bricht das Brand am stärksten. Wrapper um `SliderTheme` ist 30-50 LOC.

Nice-to-have danach: `KubbButton` (mit Loading/Disabled-States) und `KubbSessionCard`.

---

## Quality-Gate-Checkliste pro Komponente

Pro Komponente vor Sprint-B-Abnahme abhaken:

- [ ] **AppBar**
  - [ ] Home-Variante mit Logo-Slot (Mark links statt Back-Button) implementiert
  - [ ] Bottom-Hairline optional als Boolean-Flag (`showDivider`)
- [ ] **Buttons**
  - [ ] `KubbButton` mit 5 Tones (primary/secondary/ghost/danger/accent) + FAB
  - [ ] Loading-State (Spinner) und Disabled-State (50 %)
  - [ ] Auth-Wrapper auf `KubbButton` umgebogen
- [ ] **Chips**
  - [ ] `KubbChip` mit 8 Tones aus Preview
  - [ ] `selected`-Boolean (für ChoiceChip-Ersatz)
  - [ ] Bestehende `_*Chip`-Klassen migriert
- [ ] **Counter**
  - [ ] `KubbCounter.hero(120px)` ergänzt
  - [ ] Sniper-Screen auf Hero umgebogen
- [ ] **ModeCard**
  - [ ] `KubbModeCard` mit 4 Tones (Sniper/Finisseur/Match/Tournament)
  - [ ] Sheet + Home gemeinsam migriert
- [ ] **SessionCard**
  - [ ] `KubbSessionCard` mit Tone + Outcome (passed/failed)
  - [ ] Stats-Liste + Home-Recent darauf umgestellt
- [ ] **Slider**
  - [ ] `KubbSlider` (Single) + `KubbRangeSlider`
  - [ ] Brand-Thumb (24 dp, 2 px Border, Shadow)
  - [ ] Label-/Value-Spalten optional
  - [ ] `stats_filter_modal` und `swiss_config_section` migriert
- [ ] **TapPad**
  - [ ] Sign-Pill als optionales Element

---

## Bekannte Abweichungen / Folge-Actions

- **Counter-Hero (120 px)** — der Sniper-Live-Counter ist im aktuellen Code wahrscheinlich inline gestylt; vor Sprint-B prüfen, ob die Migration auf `KubbCounter.hero` ohne Layout-Bruch geht.
- **TournierCard vs. ModeCard** — der Home-Screen hat zwei Card-Typen (TournierCard + News). Die Tournament-Mode-Card aus dem Preview ist die Konsolidierungs-Basis. `NewsCard` bleibt separat.
- **Onboarding `_SoonChip`** — in `onboarding_tour.dart` als private Klasse. Lässt sich gegen `KubbChip(tone: outline)` ersetzen.
- **Auth-Buttons** — `auth_primary_button.dart` / `auth_secondary_button.dart` haben eigene Logik (Wizard-Header-Integration). Migration vorsichtig, möglich aber nicht erste Priorität.
