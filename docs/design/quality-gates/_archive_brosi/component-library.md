# Quality-Gate: Component-Library

**Quelle**: `docs/design/preview/components-*.html` (HTML-Previews)
**Token-Referenz**: `docs/design/colors_and_type.css`
**Cross-Reference**: `docs/design/ui_kits/app/shared.jsx` (siehe `shared-components.md`)
**Flutter-Pendant**: `lib/core/ui/widgets/`, `lib/core/ui/theme/kubb_tokens.dart`, feature-lokale `widgets/`-Ordner
**Stand**: 2026-05-28

Die Previews unter `docs/design/preview/` zeigen die Bausteine der App in isolierter HTML-Form. Jede Datei ist eine eigenstaendige Mini-Renderung mit Inline-Styles, die auf die CSS-Tokens (`--bk-*`) referenzieren. Dieses Dokument extrahiert daraus wiederverwendbare Widget-Spezifikationen und vergleicht sie mit dem aktuellen Flutter-Inventar.

## Komponenten-Katalog

### 1. Buttons (`components-buttons.html`)

Gemeinsame Basis-Spec aller Button-Varianten:

| Eigenschaft | Wert |
|---|---|
| min-height | 48px (Touch-Floor) |
| horizontal padding | 22px |
| border-radius | 12px (`--bk-radius-lg`) |
| border | keine (jeder Button hat eine sichtbare Flaeche) |
| font-family | `--bk-font-display` (Bricolage Grotesque) |
| font-weight | 600 |
| font-size | 16px |
| gap (Icon+Label) | 8px |
| display | inline-flex, items-center |

#### 1.1 Primary

- Background: `--bk-primary` (`#3A7C2E`, meadow-500)
- Foreground: `--bk-on-primary` (`#FBFAF6`, chalk-50)
- Shadow: `--bk-shadow-1`
- Hover: Background wechselt zu `--bk-primary-hover` (meadow-600)
- Pressed-State (eigene Klasse `btn-pressed`): Background `--bk-primary-press` (meadow-700), Shadow `--bk-shadow-pressed` (inset 0 2px 0 rgba(12,11,7,0.18)), `transform: translateY(1px)`
- Beispiel-Labels: "Session starten", "Speichern"

#### 1.2 Config / Konfigurations-Button

- Background: `--bk-stone-700` (`#232118`)
- Foreground: `--bk-chalk-50`
- Kein expliziter Shadow
- Beispiel-Label: "Konfigurieren"

#### 1.3 Secondary (outlined)

- Background: `--bk-bg-raised` (chalk-0)
- Foreground: `--bk-fg` (stone-900)
- Border via `box-shadow: inset 0 0 0 2px var(--bk-line-strong)` (2px solid stone-900)
- Verwendet fuer benigne, sekundaere Aktionen
- Beispiel-Label: "Uebernehmen"

#### 1.4 Caution — orange

- Background: `--bk-accent` (`#C08A33`, wood-400)
- Foreground: `--bk-on-accent` (stone-900)
- Verwendet fuer "Verwerfen", "Abbrechen", "Zurueck"
- **Wichtig**: Caution ist orange, nicht rot. Rot ist Destruktiv-only.

#### 1.5 Danger — rot

- Background: `--bk-danger` (`#B73A2A`, miss)
- Foreground: `--bk-on-danger` (chalk-50)
- Verwendet ausschliesslich fuer echt zerstoererische Aktionen ("Loeschen")

#### 1.6 Pressed (eigener Demo-State)

- Background: `--bk-primary-press` (meadow-700)
- Shadow: `--bk-shadow-pressed`
- Transform: `translateY(1px)` — visuelles Einsinken

#### Flutter-Pendant — Buttons

Es gibt **keinen** zentralen `KubbButton`. Stattdessen wird Material direkt verwendet:

| HTML-Variante | Verbreitete Flutter-Loesung |
|---|---|
| btn-primary | `FilledButton` mit `colorScheme.primary` (= `meadow500`) |
| btn-config | `FilledButton.tonal` ODER inline `FilledButton.styleFrom(backgroundColor: KubbTokens.stone700)` |
| btn-secondary | `OutlinedButton` (Border via `BorderSide`, Stroke 2px nicht garantiert) |
| btn-caution | nicht abgebildet — kein dedizierter Caution-Button im Code |
| btn-danger | `FilledButton.styleFrom(backgroundColor: tokens.danger)` oder `OutlinedButton.styleFrom(foregroundColor: tokens.danger)` |
| btn-pressed | Material-Default (kein `translateY`-Einsinken) |

**Beobachtungen**:

- Min-Height 48dp wird durch Material-Default nicht garantiert (FilledButton-Default ist 40dp). Brauchen explizite `minimumSize: Size.fromHeight(48)`.
- Horizontal-Padding 22 abweichend von Material-Default (24/16). Aktuell inkonsistent.
- Caution-orange existiert nicht als eigene Button-Variante. Heute wird stattdessen "primary" oder "outlined danger" verwendet, was das Design-System nicht spiegelt.
- Pressed-Inset-Shadow + Translate-Y ist im Material-Ripple-Default nicht enthalten.

### 2. Chips (`components-chips.html`)

Basis-Spec:

| Eigenschaft | Wert |
|---|---|
| min-height | 36px |
| padding | 6px 14px |
| border-radius | 999px (`--bk-radius-pill`) |
| font-family | `--bk-font-display` |
| font-weight | 600 |
| font-size | 14px |
| gap (Dot+Label) | 6px |
| Default-Background | `--bk-bg-raised` (chalk-0) |
| Default-Foreground | `--bk-fg` (stone-900) |
| Default-Border | `box-shadow: inset 0 0 0 1px var(--bk-line)` (1px stone-200) |

#### 2.1 Filter / Default Chip (off)

- Default-Styling wie oben
- Beispiel-Labels: "7 Feldkubbs", "3 Basiskubbs"

#### 2.2 Choice-Chip (on)

- Background: `--bk-stone-900` (Ink)
- Foreground: `--bk-chalk-50`
- Border: entfernt (`box-shadow: none`)
- Beispiel-Label: "Stock 4 / 6"

#### 2.3 Tone-Chips

Drei Tone-Varianten mit subtilem Background + farbiger Bordure + farbigem Text:

| Tone | Background | Foreground | Border |
|---|---|---|---|
| hit | `--bk-meadow-100` (`#D6EAD0`) | `--bk-meadow-700` (`#234E1C`) | `--bk-meadow-300` inset 1px |
| penalty | `#FBE9EE` (Inline-Hex) | `--bk-penalty` (`#8A1F3D`) | `#E6B3C2` inset 1px |
| king | `#FBF1D6` (Inline-Hex) | `#6B4A0A` (Inline-Hex) | `--bk-wood-300` inset 1px |

Jeder Tone-Chip enthaelt einen 8x8 `.dot`-Indikator in `currentColor` links vor dem Label.

Beispiel-Labels: "8m-Treffer" (hit), "Strafkubb" (penalty), "Koenig oben durch" (king).

#### Flutter-Pendant — Chips

Kein zentraler `KubbChip`. Material-`FilterChip` / `ChoiceChip` werden direkt verwendet (`anonymous_signup_flow.dart`). Tone-Varianten existieren als feature-lokale Klassen:

| HTML-Variante | Flutter-Pendant |
|---|---|
| Filter / Default | `_MetaChip` in `tournament_card.dart`, `_MetaChip` in `match_lobby_screen.dart` — eigenstaendige Re-Implementierungen |
| Choice (on) | `ChoiceChip` mit `selectedColor: stone900` (nicht durchgaengig) |
| Tone-Hit | `_OutcomeChip` (Match-Stats) — teilweise abgedeckt |
| Tone-Penalty / King | nicht als wiederverwendbare Widgets vorhanden |

**Vorschlag**: `KubbChip` zentralisieren mit Varianten `default | choice | tone(hit|miss|heli|penalty|king|neutral)`. Spart die mehrfach implementierten `_MetaChip`-Klassen.

### 3. Counter-Display (`components-counter.html`)

Pattern: Counter-Strip am Top des Training-Screens. CSS-Grid mit 4 gleich breiten Spalten, jede Spalte ein Mini-Stat (Label + grosse Number).

Container:

| Eigenschaft | Wert |
|---|---|
| display | grid (`repeat(4, 1fr)`) |
| gap | 10px |
| background | `--bk-bg-raised` |
| border-radius | 16px (`--bk-radius-xl`) |
| padding | 14px 18px |
| shadow | `--bk-shadow-1` |

Stat-Block:

| Element | Spec |
|---|---|
| Label (`.lbl`) | font-display, 11px, weight 600, `letter-spacing: 0.08em`, `text-transform: uppercase`, `color: --bk-fg-muted` |
| Value (`.val`) | font-display, weight 800, **40px**, `line-height: 1`, `letter-spacing: -0.03em`, **`font-variant-numeric: tabular-nums`** |
| Gap (Label → Value) | 2px |

Tone-Varianten der Value-Number:

- `.val.hit` → `--bk-hit` (`#2D6324`)
- `.val.miss` → `--bk-miss` (`#B73A2A`)
- `.val.heli` → `--bk-heli` (`#C08A33`)
- ohne Tone → `--bk-fg`

Hero-Counter-Stufen aus `colors_and_type.css`:

- `.bk-counter` — 84px (`--bk-text-5xl`), weight 700, `tabular-nums + ss01`
- `.bk-counter-hero` — 120px (`--bk-text-6xl`), weight 800

Verwendung: Strip-Variante (40px) sitzt oben auf dem Sniper-Training-Screen. Die 84px / 120px-Varianten gehoeren in Verdict-Banner und Session-Hero-Number.

#### Flutter-Pendant — Counter

`lib/core/ui/widgets/kubb_counter.dart` — `KubbCounter(label, value, tone, muted, masked)`:

| HTML-Spec | Flutter-Pendant | Status |
|---|---|---|
| Label 11px, 0.08em, uppercase | Identisch (kubb_counter.dart Zeile 33-41) | passt |
| Value 40px, weight 800, tabular-nums | Wert 38px (statt 40), weight 800, `FontFeature.tabularFigures()` | **2px kleiner als HTML-Spec** |
| Tone hit/miss/heli/neutral | `KubbCounterTone.hit/miss/heli/neutral` | passt |
| Value `letter-spacing: -0.03em` | `letterSpacing: -38 * 0.03 = -1.14` | passt |

**Luecken**:

- Kein Hero-Counter-Widget (`bk-counter` 84px, `bk-counter-hero` 120px). Verdict-Banner im Summary baut die grosse Zahl inline.
- Die Container-Strip (`.strip` mit Grid + Padding + Shadow) ist nicht als Wrapper-Widget abgebildet — Sniper-Screen rendert die Strip inline.

**Vorschlag**: `KubbCounterStrip` (Wrapper) + `KubbCounterHero` (Hero/Verdict-Variante) ergaenzen.

### 4. Session-Card (`components-sessioncard.html`)

Pattern: Kompakte Karte fuer "Letzte Session"-Listen — verwendet auf Home und Stats.

Container:

| Eigenschaft | Wert |
|---|---|
| background | `--bk-bg-raised` |
| border-radius | 16px |
| padding | 14px 16px |
| shadow | `--bk-shadow-1` |
| layout | flex-column, gap 6px |

Top-Row (`.top`):

- Pill: Background `--bk-stone-900`, Foreground `--bk-chalk-50`, padding 4px 10px, radius 999, font-display 12px weight 700, `letter-spacing: 0.06em`. Inhalt = "7 / 3" (Feld/Basis-Stock).
- Pill-Variante "warning": Background `--bk-penalty` (`#8A1F3D`) statt stone-900.
- Meta-Text: `--bk-font-mono` 11px, `--bk-fg-muted`. Inhalt "heute · 14:22".

Body-Row (`.row`):

- Layout: flex, baseline-aligned, gap 14px.
- Verdict-Glyph: font-display 32px, weight 800. `✓` = `--bk-meadow-600` (`.ok`); `✗` = `--bk-miss` (`.bad`).
- Number-Slot: font-display 32px, weight 800, `letter-spacing: -0.02em` — die Hauptmetrik der Session.
- Meta (font-mono 11px, muted) — "von 6 Stoecken · sauber" / "Strafkubb · Stock 4".

#### Flutter-Pendant — Session-Card

Kein zentraler `KubbSessionCard`. Verwandte Patterns existieren:

| HTML-Pattern | Flutter-Aequivalent | Status |
|---|---|---|
| Pill (stone-900 oder penalty) | `TournamentStatusPill`, `MatchStatusPill` — formal aehnlich, semantisch anders | partial |
| Card-Container (raised, radius 16, shadow 1) | inline gebaut in `recent_section.dart`, `tournament_card.dart` | partial |
| Verdict-Glyph + grosse Zahl + Meta | inline in `summary_screen.dart` (`_Verdict`, `_FinisseurVerdict`) | abgewichen |

`stats_session_list.dart` baut Session-Eintraege fuer die Stats-Liste — vermutlich am naechsten zur HTML-Spec, aber nicht als zentrales Widget exportiert.

**Vorschlag**: `KubbSessionCard` mit Slots `pill (status+tone)`, `meta (timestamp)`, `verdict (ok|bad)`, `metric (int)`, `subtitle` ergaenzen. Beide Home-Recent und Stats-Liste konsumieren das gleiche Widget.

### 5. Slider (`components-slider.html`)

Pattern: Distanz-Slider 4.0–8.0m fuer Sniper-/Finisseur-Setup. Im HTML als Custom-Track ohne native `<input type="range">`, also rein visuelle Referenz.

Container (`.wrap`):

| Eigenschaft | Wert |
|---|---|
| background | `--bk-bg-raised` |
| border-radius | 16px |
| padding | 16px |
| shadow | `--bk-shadow-1` |
| max-width | 520px |

Head-Row (`.head`):

- Layout: space-between, baseline.
- Label: font-display 14px, weight 600, `letter-spacing: 0.06em`, uppercase, muted.
- Value: font-display 28px, weight 800, `letter-spacing: -0.02em`, `tabular-nums`. Inhalt "6.5 m".

Track:

- Height 8px, Background `--bk-stone-100`, `border-radius: 999px`.
- Fill: width % (im Demo 60%), Background `--bk-primary`, `border-radius: 999px`.

Ticks-Row:

- font-mono 11px, muted, `space-between` ueber 4.0 / 5.0 / 6.0 / 7.0 / 8.0.

**Spec-Hinweis**: Thumb-Touch-Target ist im HTML-Demo nicht visualisiert. Fuer Outdoor muss der Thumb >= 48dp gross sein (per `--bk-touch-min`).

#### Flutter-Pendant — Slider

`Slider` (Material) direkt verwendet:

- `sniper_config_screen.dart:79` — Distance 4-8, divisions 8
- `swiss_config_section.dart:104` — Swiss-Rounds
- `stats_filter_modal.dart:229` — `RangeSlider` fuer Hit-Rate-Range

Kein zentraler `KubbSlider` / `KubbDistanceSlider`. Die HTML-Spec mit Head-Row (Label + grosse Wert-Number) + Track + Ticks ist nicht abgebildet — Material-Default rendert nur den Track mit Label-Bubble bei Drag.

**Vorschlag**: `KubbDistanceSlider(label, value, min, max, ticks, onChanged)` als Composite-Widget anlegen. Wrappt Material-Slider + Head-Row + Ticks-Strip. Optional `KubbRangeSlider` fuer Stats-Filter analog.

### 6. Tap-Pad-Grid (`components-tappad.html`)

Pattern: 2-Spalten-Grid (Plus/Minus pro Tone), das primaere Eingabe-Element auf dem Sniper-Training-Screen.

Grid-Container:

| Eigenschaft | Wert |
|---|---|
| display | grid (`grid-template-columns: 1fr 1fr`) |
| gap | 10px |
| max-width | 520px |

Pad-Basis:

| Eigenschaft | Wert |
|---|---|
| min-height | **88px** (deutlich ueber dem 48dp-Touch-Floor — Outdoor-Bias) |
| border-radius | 16px (`--bk-radius-xl`) |
| border | 0 (Border nur fuer ghost/minus-Variante via inset-shadow) |
| padding | 0 22px |
| font-family | `--bk-font-display` |
| font-weight | 700 |
| font-size | 22px |
| Sign-Glyph | 36px, weight 800, `line-height: 1` |
| Layout | `space-between`, items-center |

Tone-Varianten:

| Tone | Background | Foreground | Border |
|---|---|---|---|
| hit | `--bk-hit` (`#2D6324`, meadow-600) | `#fff` | — |
| miss | `--bk-miss` (`#B73A2A`) | `#fff` | — |
| heli | `--bk-heli` (`#C08A33`, wood-400) | `--bk-stone-900` | — |
| minus / ghost | `--bk-bg-raised` | `--bk-fg` | `inset 0 0 0 2px --bk-line`, font-weight 600 (statt 700) |

Beispiel-Grid:

```
[ Hit  + ]  [ Hit  − ]
[ Miss + ]  [ Miss − ]
[ Heli + ]  [ Heli − ]
```

Sign-Glyph (`.sign`) ist 36px gross, rechts im Pad, mit `line-height: 1`.

#### Flutter-Pendant — Tap-Pad

`lib/core/ui/widgets/kubb_tap_pad.dart` — `KubbTapPad(label, sign, tone, onTap)`:

| HTML-Spec | Flutter-Pendant | Status |
|---|---|---|
| min-height 88px | `minHeight = 84` | **4px niedriger als HTML** |
| border-radius 16 | `KubbTokens.radiusXl` (16) | passt |
| Tone hit | `KubbTapPadTone.hit` → `KubbTokens.hit` Background, `Colors.white` | passt |
| Tone miss | `KubbTapPadTone.miss` → `KubbTokens.miss`, `Colors.white` | passt |
| Tone heli | `KubbTapPadTone.heli` → `KubbTokens.heli`, `KubbTokens.stone900` | passt |
| Tone ghost (minus) | `KubbTapPadTone.ghost` → `tokens.bgRaised`, `tokens.fg`, Border 2px `tokens.line` | passt |
| Font label 22px weight 700 | 20px weight 700 | **2px kleiner als HTML** |
| Sign 36px weight 800 | 36px weight 800 | passt |
| Layout space-between | `MainAxisAlignment.spaceBetween` | passt |
| Padding horizontal 22 | 22 | passt |

**Pressed-State**: HTML zeigt keinen expliziten Pressed-State fuer Tap-Pad (waere wahrscheinlich Inset-Shadow analog zu Button). Flutter nutzt Material-`InkWell`-Ripple — semantisch passend, visuell nicht 1:1 zur Brand-Spec.

**Vorschlag**: Pad-min-height auf 88 anheben (Outdoor-Konsistenz), Label-Font auf 22 anpassen. Optional dedizierten Pressed-Inset-Shadow-State definieren.

---

## Flutter-Mapping-Audit (Komplett-Sicht)

### Existierende Widgets (Mapping zu HTML-Previews)

| HTML-Preview | Flutter-Pendant | Pfad |
|---|---|---|
| components-counter | `KubbCounter` | `lib/core/ui/widgets/kubb_counter.dart` |
| components-tappad | `KubbTapPad` | `lib/core/ui/widgets/kubb_tap_pad.dart` |
| components-buttons (Material default) | `FilledButton` / `OutlinedButton` direkt | quer durch alle Screens |
| components-sessioncard (partial) | `_RecentTile` / `TournamentCard` / `stats_session_list` | feature-lokal, nicht zentral |
| components-chips (partial) | `_MetaChip` (Tournament-Card), `_MetaChip` (Match-Lobby), `_OutcomeChip` (Match-Stats), `ChoiceChip` (Material) | feature-lokal |
| components-slider | `Slider` (Material) | direkt in Configs |

### Fehlende Widgets (HTML-Spec ohne Flutter-Pendant)

- **`KubbButton`** als zentrale Komponente mit Varianten `primary | secondary | config | caution | danger`. Aktuell verteilte FilledButton/OutlinedButton-Aufrufe ohne garantierte Min-Height 48 und ohne Caution-orange.
- **`KubbChip`** zentral mit Varianten `default | choice | tone(hit|miss|heli|penalty|king|neutral)`. Aktuell zwei Re-Implementierungen von `_MetaChip`.
- **`KubbDistanceSlider`** mit Head-Row + Ticks. Aktuell rohes Material `Slider`.
- **`KubbCounterStrip`** als Wrapper fuer den Counter-Strip am Top des Sniper-Screens.
- **`KubbCounterHero`** fuer Verdict-Banner und Hero-Numbers (84px / 120px).
- **`KubbSessionCard`** mit Slots Pill + Meta + Verdict + Metric + Subtitle.
- **`KubbVerdictBanner`** (siehe `shared-components.md` 3.8).

### Abweichende Implementierungen

| Komponente | Abweichung | Schaerfegrad |
|---|---|---|
| `KubbTapPad` | min-height 84 statt 88, Label-Font 20 statt 22 | LOW |
| `KubbCounter` | Value 38 statt 40 px | LOW |
| Material-Buttons | min-height 40 statt 48; Caution-orange fehlt | MEDIUM |
| Session-Card-Patterns | mehrfach inline implementiert ohne gemeinsame Card-Basis | MEDIUM |
| `Slider` (Material) | weder Head-Row noch Ticks; Distanz-Markers fehlen | MEDIUM |

---

## Quality-Gate-Checkliste

### Buttons

- [ ] `KubbButton(variant: primary|secondary|config|caution|danger, label, icon?)` Widget existiert.
- [ ] Alle Varianten haben `minHeight >= 48`, `horizontalPadding == 22`, `borderRadius == 12`.
- [ ] Primary nutzt `meadow500/600/700` fuer Default/Hover/Press.
- [ ] Caution nutzt `wood400` (orange) — nicht rot.
- [ ] Danger nutzt `miss` und ist visuell klar abgesetzt von Caution.
- [ ] Pressed-State: `translateY` oder Inset-Shadow als Brand-spezifischer Press-Indicator (oder dokumentierte Abweichung zu Material-Default).
- [ ] Alle Screens haben kein inline `FilledButton.styleFrom(backgroundColor: ...)` mehr.

### Chips

- [ ] `KubbChip(label, variant, tone?, selected?)` Widget existiert.
- [ ] Min-Height 36, Padding 6/14, Radius 999.
- [ ] Default-Border via inset-shadow / `Border.all(width: 1, color: line)`.
- [ ] Tone-Varianten Hit / Penalty / King mit korrekten Background+Foreground+Border-Trios.
- [ ] Choice-Variante (Ink-Background) ersetzt `ChoiceChip` an allen Aufrufstellen.
- [ ] Tone-Chips mit `.dot`-Indikator (8x8) als optionales Leading-Element.

### Counter-Display

- [ ] `KubbCounter` Value-Font auf 40px (statt 38).
- [ ] `KubbCounterStrip(stats: List<({label, value, tone?})>)` Container-Widget existiert.
- [ ] `KubbCounterHero(value, tone)` fuer 84px / 120px Hero-Number existiert.
- [ ] `tabular-nums` ist auf allen Counter-Varianten aktiv.

### Session-Card

- [ ] `KubbSessionCard(pill, pillTone, timestamp, verdict, metric, subtitle, onTap, onLongPress?)` Widget existiert.
- [ ] Pill-Tone `default | warning(penalty)`.
- [ ] Verdict-Glyph `ok (meadow600 ✓) | bad (miss ✗)`.
- [ ] Empty-State ("Noch keine Session") definiert.
- [ ] Container Shadow `bk-shadow-1` (mind. Material-Elevation 1).

### Slider

- [ ] `KubbDistanceSlider(label, value, min, max, ticks, onChanged, suffix?)` Widget existiert.
- [ ] Head-Row mit Label (uppercase muted) und grossem Value (28px, tabular-nums) rechts.
- [ ] Track-Height 8, Background `stone100`, Fill `primary`.
- [ ] Ticks-Strip optional, mono 11px muted.
- [ ] Thumb-Touch-Target >= 48dp (Material-Default ist klein, Overlay vergroessern).
- [ ] `KubbRangeSlider`-Pendant fuer Stats-Filter.

### Tap-Pad

- [ ] `KubbTapPad.minHeight` auf 88 erhoeht.
- [ ] Label-Font 22 (statt 20).
- [ ] Pressed-State definiert (Inset-Shadow oder dokumentierte Material-Ripple-Akzeptanz).
- [ ] Grid-Wrapper `KubbTapPadGrid(rows: 3, columns: 2)` als optionaler Convenience.
- [ ] Haptic-Feedback auf Tap (Brand-Konsistenz mit "outdoor primary input").

### Token-Hygiene

- [ ] `KubbTokens.shadow1 / shadow2` als `List<BoxShadow>`-Konstanten ergaenzt (heute fehlend — siehe `shared-components.md`).
- [ ] Inline-Hex-Werte in den HTML-Tone-Chips (`#FBE9EE`, `#FBF1D6`, `#E6B3C2`, `#6B4A0A`) als Token-Erweiterung in `KubbTokens` ergaenzen (`penaltyBg`, `penaltyBorder`, `kingBg`, `kingFg`) — sonst leben sie als magic numbers in `KubbChip`.

---

## Bekannte Abweichungen / Folge-Actions

1. **Kein zentraler `KubbButton`**. Material-Direct-Use macht Caution-orange unmoeglich und garantiert keine 48dp-Min-Height. Priorisiert fuer Sprint-B-Polish.
2. **Tap-Pad min-height 84 vs. Spec 88** und **Label-Font 20 vs. Spec 22**. Beides klein, aber addiert sich auf der primaeren Eingabe-Flaeche im Outdoor-Kontext.
3. **`KubbCounter`-Value 38 vs. Spec 40**. Konsistenz-Fix.
4. **Counter-Strip-Container fehlt**. Sniper-Screen rendert die Strip inline statt ueber ein Wrapper-Widget.
5. **Hero-Counter (84px / 120px) fehlt** — Verdict-Banner ist heute Custom-Code in `summary_screen.dart`.
6. **`KubbSessionCard` fehlt** — drei aehnliche Cards (Home-Recent, Stats-Liste, Tournament-Liste) teilen den Aufbau nicht.
7. **`KubbDistanceSlider` fehlt** — Material `Slider` zeigt keinen 28px-Value und keine Ticks-Strip.
8. **Tone-Chips Penalty/King fehlen** als Widgets — Inline-Hex-Werte (`#FBE9EE`, `#FBF1D6`) sind unbenutzt.
9. **Pressed-State `translateY(1px)` + Inset-Shadow** ist auf keinem Flutter-Widget abgebildet — Material-Ripple-Akzeptanz als ADR dokumentieren oder Brand-Press selbst bauen.
10. **Tap-Pad-Grid-Pressed-Haptic**: nicht definiert, aber sinnvoll fuer Outdoor (Bestaetigung ohne Blickkontakt).

### Hinweise zu HTML-only / nicht in `shared.jsx`

Alle sechs Preview-Komponenten leben **nur** als HTML-Previews. `shared.jsx` exportiert ausschliesslich `Icon` + `AppBar` (siehe `shared-components.md` Sektion "Inventar wiederverwendbarer Komponenten"). Die Komponenten Buttons / Chips / Counter / Session-Card / Slider / Tap-Pad sind also nicht in der App-JSX zentralisiert, sondern werden in den einzelnen Screen-JSX-Dateien inline gebaut. Konsequenz fuer Flutter: das Design-System steht "next-level" — Sprint-B-Polish konsolidiert das gleichzeitig fuer JSX-Demo und Flutter-Implementierung.

### Sprint-B-Polish — Top-3-Empfehlung

1. **`KubbButton`** mit allen 5 Varianten — touchsicher, Caution-orange korrekt, ersetzt 60+ inline `FilledButton.styleFrom(...)`-Aufrufe. Hoher visueller Impact, fuehrt zu konsistenter Touch-Min-Height.
2. **`KubbSessionCard`** — vereinheitlicht Home-Recent, Stats-Liste und (optional) Tournament-Liste. Reduziert drei parallel gepflegte Card-Implementierungen auf eine.
3. **`KubbDistanceSlider`** + Hero-Counter — verbessert die zwei zentralen Sniper-Flow-Touchpoints (Setup + Verdict). Spuerbar im UX-Test.
