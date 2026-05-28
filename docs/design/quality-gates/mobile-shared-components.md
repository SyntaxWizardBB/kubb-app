# Quality-Gate: Shared Components (Mobile)

**Quelle**: `docs/design/ui_kits/app/shared.jsx`
**Flutter-Pendant**: `lib/core/ui/icons.dart` (Icon-Mapping) + keine zentrale AppBar (inline pro Screen)
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Zweck

`shared.jsx` ist das Komponenten-Inventar fuer das Mobile-Kit. Definiert das Icon-Set (`BK.Icon.*`) und die `BK.AppBar`-Komponente — beide werden von allen anderen Screens importiert.

## Visual-Spec

### Icons

Inline-SVG, `viewBox="0 0 24 24"` (Standard) oder Detail-spezifisch.

| Name | Groesse | StrokeWidth | Verwendung |
|---|---|---|---|
| Plus / Minus | 24x24 | 2.5 | Stepper, Pad-Add/Remove |
| Plus2 | 20x20 | 2.2 | FAB-Icon, Save-Pill |
| Close / X | 22x22 | 2.2-2.5 | Sheet-Close, Preset-Remove |
| Back | 22x22 | 2.2 | AppBar-Back |
| Check | 22x22 | 2.5 | Checkbox-On, Done-State |
| Settings / Gear | 22x22 | 2.0 | Gear-Icon (zwei Varianten, gleicher Pfad) |
| Eye / EyeOff | 22x22 | 2.0 | Hide-Made-Toggle im Sniper |
| Heli | 22x22 | 2.0 | Helikopter-Glyph (Stab + Rotor-Linien) |
| Trophy / Cup | 22x22 | 2.0 | Pokal (Trophy ist Vollform, Cup ist offene Schale) |
| King | 22x22 | 2.0 | Krone (4 Spitzen, Basis-Linie) |
| Target | 22x22 | 2.0 | Konzentrische Kreise (Stamm-Distanz) |
| Stat | 22x22 | 2.0 | Bar-Chart |
| Flame | 22x22 | 2.0 | Streak |
| Star | 22x22 | 2.0 | Favorit |
| Profile | 22x22 | 2.0 | Avatar-Icon |
| Menu | 22x22 | 2.2 | Hamburger |
| Mail / Lock | 20x20 | 2.0 | Auth-Felder |
| ChevronRight | 20x20 | 2.0 | Listen-Chevron |
| Trash / Download | 20x20 | 2.0 | Settings-Actions |
| Filter | 22x22 | 2.0 | Stats-Filter-Trigger |
| Google (mehrfarbig) | 20x20 | — | Provider-Verknuepfung |
| Apple (filled) | 20x20 | — | Provider-Verknuepfung |

Tinting: alle Stroke-Icons nutzen `stroke="currentColor"` — Farbsteuerung via `color`-CSS-Property des Buttons. `Google` ist hartcodiert mehrfarbig (`#EA4335` etc.).

### AppBar (`BK.AppBar`)

Signatur: `AppBar({ eyebrow, title, onBack, right, sticky })`.

```
header: {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  gap: 6,
  padding: '54px 12px 6px',     // top = Safe-Area-Padding fuer iOS-Notch
  background: 'var(--bk-bg)',
  // sticky-Option: position:sticky, top:0, zIndex:10
}

iconBtn: {
  width: 48, height: 48,
  display: 'grid', placeItems: 'center',
  background: 'transparent',
  border: 0,
  borderRadius: 12,
  color: 'var(--bk-fg)',
  cursor: 'pointer',
  flexShrink: 0,
}

title: {
  textAlign: 'center',
  flex: 1, minWidth: 0,
}

eyebrow: {
  fontSize: 11,
  fontWeight: 600,
  letterSpacing: '0.08em',
  textTransform: 'uppercase',
  color: 'var(--bk-fg-muted)',
}

name: {
  fontFamily: 'var(--bk-font-display)',
  fontWeight: 700,
  fontSize: 18,
  letterSpacing: '-0.02em',
  whiteSpace: 'nowrap',
  overflow: 'hidden',
  textOverflow: 'ellipsis',
}

rightSlot: {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'flex-end',
  minWidth: 48,
}
```

Verhalten: wenn `onBack` fehlt → leerer 48-Spacer links (haelt das Layout symmetrisch).

## Komponenten-Inventar

- `Icon` — Sammlung Inline-SVG-Komponenten.
- `AppBar` — Top-Bar mit Eyebrow + Title + Back + Right-Slot.

Beide werden auf `window.BK = { Icon, AppBar }` exportiert; jeder Screen mit `const { Icon, AppBar } = BK;` importiert.

## Interaktions-Pattern

- Icon-Buttons sind immer 48x48 (Touch-Target-Floor per `--bk-touch-min`).
- AppBar-Back-Button: `onBack` Callback, sonst Spacer.
- Right-Slot nimmt entweder ein Icon-Button oder ein `<div>` mit mehreren Buttons (Stats-Filter, Sniper-Settings).
- Sticky-Option fuer Scrollverhalten — wird im Mobile-Kit aktuell nicht aktiviert (alle Screens nutzen `position:relative`-AppBar).

## Accessibility

- Alle Icon-Buttons haben `aria-label` (Screens binden das ein, `AppBar` selbst nicht).
- Touch-Target 48dp eingehalten (`width:48, height:48`).
- Eyebrow vor Title sorgt fuer Screenreader-Kontext (eyebrow als visuell kleiner, aber im DOM zuerst).
- `Icon.Google` ist nicht semantisch markiert — bei Verwendung muss der Button ein `aria-label="Mit Google verknuepfen"` o.ae. tragen.

## Quality-Gate-Checkliste

- [x] Icon-Set vollstaendig dokumentiert (24 Icons).
- [x] AppBar-Pattern definiert (Padding, Tokens, Slots).
- [x] Touch-Targets ≥ 48dp.
- [ ] Flutter hat **keine** zentrale `KubbAppBar`-Widget-Klasse — Inkonsistenz-Risiko bei Eyebrow-Padding, Back-Icon-Groesse. **TODO**: Widget einziehen.
- [ ] Brand-Glyphen (`Heli`, `King`, `Cup`, `Target`) in Flutter sind Lucide-Stubs (`lib/core/ui/icons.dart`) — nicht die hoelzernen Originale. AUDIT.md Punkt 5 + Sprint-Empfehlung 8.
- [x] Token-Referenzen (`--bk-fg`, `--bk-fg-muted`, `--bk-font-display`) zeigen via Alias auf `--kc-*` — kompatibel mit Rebrand.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **`KubbAppBar`-Widget fehlt**. Jeder Screen baut die Top-Bar selbst — leichte Drift bei Padding (`54px 12px 6px` vs. SliverAppBar-Defaults) ist sichtbar.
2. **Lucide statt Brand-Glyphen**: `Icon.Heli → wind`, `Icon.King → crown`, `Icon.Cup → trophy`. Funktional OK, visuell aber generisch.
3. **`Icon.Eye` / `Icon.EyeOff`** (Hide-Made-Toggle im Sniper) ist im Mobile-Kit definiert — pruefen, ob Flutter `Icons.visibility` / `visibility_off` nutzt oder einen Custom-Eye-Glyph.
4. **`Icon.Google` / `Icon.Apple`** sind mehrfarbig (Markenfarben). In Flutter typischerweise via Asset-Vector (SVG-Picture oder `flutter_svg`) — pruefen, ob das Markenrichtlinien-konform abgebildet ist.
