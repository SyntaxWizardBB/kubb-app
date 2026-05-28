# Quality-Gate: iOS Device Frame (Mobile-Kit Renderer)

**Quelle**: `docs/design/ui_kits/app/ios-frame.jsx`
**Flutter-Pendant**: kein direktes Pendant — iOS-System-Chrome rendert der iOS-Build von Flutter; das Kit-Frame ist ein Demo-Renderer.
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Zweck

`ios-frame.jsx` simuliert den iOS-26-Liquid-Glass-Geraeterahmen fuer die `index.html`-Galerie. Es ist nicht Teil der produktiven Flutter-App — es dient nur dazu, die Mobile-Screens im Demo-Renderer in einem iPhone-Frame zu zeigen.

Wichtig fuer Quality-Gate: die Inhalte sind nicht Flutter-relevant. Die Spec beschreibt aber das **Anzeige-Modell** (Safe-Area-Padding, Dynamic-Island-Platz, Home-Indicator), das die Mobile-Screens beruecksichtigen.

## Visual-Spec

### Device-Frame (`IOSDevice`)

```
width:       402px (default — index.html scaliert auf 390)
height:      874px
borderRadius: 48
background:  '#F2F2F7' (light) | '#000' (dark)
boxShadow:   0 40px 80px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.12)
fontFamily:  '-apple-system, system-ui, sans-serif'
```

Innenstruktur:
- **Dynamic-Island**: 126x37px, borderRadius 24, schwarz, zentriert oben (top:11px). z-index:50.
- **Status-Bar**: oben absolut platziert, z-index:10.
- **Content-Bereich**: Flex-Column, `overflow:auto`.
- **Home-Indicator**: 139x5px Pill, position:absolute bottom:0, z-index:60.

### Status-Bar (`IOSStatusBar`)

- Zeit-Anzeige links, mittig (9:41 default), SF Pro 17px / Weight 590.
- Rechts: Signal (4 Balken), Wifi (3 Boegen), Battery (rounded-rect 27x13).
- Padding `21px 24px 19px`.

### Liquid-Glass-Pille (`IOSGlassPill`)

```
height:       44, minWidth: 44
borderRadius: 9999
backdropFilter: blur(12px) saturate(180%)
background:   rgba(255,255,255,0.5) (light) | rgba(120,120,128,0.28) (dark)
shine-inset:  inset 1.5px 1.5px 1px rgba(255,255,255,0.7), inset -1px -1px 1px rgba(255,255,255,0.4)
border:       0.5px solid rgba(0,0,0,0.06) (light) | rgba(255,255,255,0.15) (dark)
shadow:       0 1px 3px rgba(0,0,0,0.07), 0 3px 10px rgba(0,0,0,0.06) (light)
              0 2px 6px rgba(0,0,0,0.35), 0 6px 16px rgba(0,0,0,0.2) (dark)
```

Verwendung in `IOSNavBar` fuer Back-Pille und Trailing-Ellipsis-Pille.

### Nav-Bar (`IOSNavBar`)

- `paddingTop: 62, paddingBottom: 10`.
- Erste Zeile: 2 Pillen (Back + Trailing-Ellipsis), `padding 0 16px`, justify space-between.
- Large-Title: 34px, `fontWeight 700`, `letterSpacing 0.4`, `padding 0 16px`.

### Grouped List (`IOSList` + `IOSListRow`)

```
List:
  background:   '#fff' (light) | '#1C1C1E' (dark)
  borderRadius: 26
  margin:       0 16px
  
Row:
  minHeight: 52
  padding:   0 16px
  font:      -apple-system / 17px / letterSpacing -0.43
  icon:      30x30, borderRadius 7
  separator: 0.5px, position absolute bottom, left aligned to icon-end
```

### Keyboard (`IOSKeyboard`)

iOS-26-Liquid-Glass-Keyboard mit:
- Autocorrect-Bar (3 Vorschlaege, mit Trenner)
- 4 Reihen Tasten, special-keys (shift, del, return) mit Custom-SVG-Icons
- Return-Taste blau (`#08f`)
- Backdrop `blur(12px) saturate(180%)`

## Komponenten-Inventar

- `IOSDevice` — Geraeterahmen + Status-Bar + Nav-Bar + Content + Home-Indicator
- `IOSStatusBar` — Standalone-Status-Bar (Zeit + Icons)
- `IOSNavBar` — Standalone-Nav-Bar mit Pillen + Large-Title
- `IOSGlassPill` — Wiederverwendbare Glass-Pille
- `IOSList` + `IOSListRow` — Inset-Card-Liste im iOS-Style (r:26)
- `IOSKeyboard` — Optional, fuer Keyboard-Demo

Global-Export auf `window`.

## Interaktions-Pattern

- Keine echten Interaktionen — Pure-Display.
- Dark-Prop `dark={true|false}` schaltet Token-Werte um.
- `keyboard={true}` rendert das Keyboard unten.

## Accessibility

Nicht produktiv — kein Accessibility-Audit noetig. Wichtig fuer das Mobile-Kit-Modell:
- Mobile-Screens muessen `paddingTop: 54px` (siehe AppBar-Spec) einhalten, damit der Inhalt unter der Dynamic-Island sichtbar bleibt.
- Bottom-Indicator-Bereich (34px hoch, bottom:0) darf nicht von FAB oder Buttons ueberlappt werden.

## Quality-Gate-Checkliste

- [x] iOS-System-Chrome ist sauber simuliert (Status-Bar, Dynamic-Island, Home-Indicator).
- [x] Safe-Area-Padding-Modell ist konsistent mit den Mobile-Screens (`54px top`, `34px bottom`).
- [x] Light + Dark Mode beide unterstuetzt.
- [x] Keine Asset-Abhaengigkeiten (alles Inline-SVG).
- [N/A] Flutter-Pendant nicht erforderlich — System-Chrome rendert iOS selbst.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Safe-Area in Flutter**: Flutter nutzt `SafeArea` Widget — das System reportet den Top-Inset (zb 47-59px je nach Device). Der Kit-Wert `54px` ist ein guter Default fuer iPhone-15-Klasse-Devices. Flutter-Screens sollten `MediaQuery.viewPaddingOf(context).top` respektieren, nicht hartcodiert `54`.
2. **Android-System-Chrome**: das Kit zeigt nur iOS-Frame. Android-Screens haben einen anderen Status-Bar-Layout (System-UI-Overlay) — Flutter macht das automatisch ueber `AnnotatedRegion<SystemUiOverlayStyle>`. Kein Action-Item, nur Hinweis.
3. **Web/PWA-Build**: hat keinen Frame. Status-Bar entfaellt. Die Mobile-Screens sollten responsiv genug sein, damit sie auch ohne Frame funktionieren.
