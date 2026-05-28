# Quality-Gate: Home Screen (Mobile)

**Quelle**: `docs/design/ui_kits/app/HomeScreen.jsx`
**Flutter-Pendant**: `lib/features/training/presentation/home_screen.dart` (+ `widgets/home_greeting.dart`)
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **Top-Bar** (`topbar`): Hamburger-Icon (Menu) ← → 34x34px Logo-Mark (`../../assets/logo-mark.svg`, alt="Kubb Club") ← → Profil-Icon.
2. **Greet-Block** (`greetBlock`): Eyebrow `Kubb Club` (11px uppercase) + Greeting `Servus, Marc.` (Display 28px, Weight 800).
3. **Tournier-Tile** (`tournierCard`): Primary-Tile, **Wood-Background** (`var(--bk-wood-500)`), Hoehe min 120px, Text + 64x64-Cup-Icon-Block (rgba weiss).
4. **News-Tile** (`newsCard`): Link auf kubbtour.ch, Bg-Raised mit `inset 0 0 0 1px line`, Hoehe 72px, kompakt.
5. **Section-Header**: `Zuletzt` (Eyebrow-Style).
6. **Recent-List** (`recentList`): 3 Zeilen (`RecentRow`), Grid `56px 80px 1fr`, mono-Tag + Display-Rate + Sub-Text.
7. **FAB** (`fab`): Material-3 Position 24/24 (kombiniert mit Screen-Padding ergibt 16/16), Plus2 + "Training", `meadow-600`.

### Farben (Tokens)

| Element | Token | Hex |
|---|---|---|
| Screen-Bg | `--bk-bg` / `KubbTokens.bg` | chalk-50 #FBFAF6 |
| Tile-Tournier | `--bk-wood-500` | #A16F24 |
| Tile-News-Bg | `--bk-bg-raised` | chalk-0 #FFFFFF |
| Tile-News-Eyebrow | `--bk-meadow-600` | #2D6324 |
| Recent-Bad-Rate | `--bk-miss` | #B73A2A |
| FAB-Bg | `--bk-meadow-600` | #2D6324 |
| FAB-Fg | `--bk-on-primary` | chalk-50 |
| Sheet-Backdrop | rgba(12,11,7,0.45) | — |
| Sheet-Bg | `--bk-bg-raised` | — |
| Mode-Card-1 (Sniper) | `--bk-meadow-500` | #3A7C2E |
| Mode-Card-2 (Finisseur) | `--bk-stone-900` | #0C0B07 |

### Typografie

- Greeting: `var(--bk-font-display)` (Bricolage), weight 800, 28px, tracking -0.02em.
- Tournier-Name: Display weight 800, 28px, tracking -0.02em, lineHeight 1.
- Tournier-Eyebrow: 11px, weight 700, uppercase, opacity 0.85.
- News-Title: Display weight 700, 15px.
- Recent-Tag: Mono 11px weight 700 uppercase.
- Recent-Rate: Display weight 700, 18px, `tabular-nums`.
- FAB-Label: Display weight 700, 17px.
- Mode-Name: Display weight 800, 24px.
- Mode-Num: Display weight 800, 36px, `tabular-nums`.

### Spacing (`KubbTokens.space*`)

- Screen-Scroll-Padding: `54px 16px 96px` (54 top fuer Notch, 96 bottom fuer FAB-Clearance).
- Tile-Margin: `marginBottom: 12px` (Tournier) bzw. `6px` (News).
- Section-Header: `marginTop: 14, marginBottom: 8`.
- Sheet-Padding: `10px 18px 32px`.

### Border-Radius

- Tournier-Card: `20px`
- News-Card: `16px`
- Recent-List: `14px`
- Mode-Card im Sheet: `18px`
- Cup-Icon-Block: `16px`
- FAB: `16px`
- Sheet: `top-radius 24px`

### Shadows

- Tournier-Card: `var(--bk-shadow-1)` (subtil)
- FAB: `var(--bk-shadow-2)` (deutlicher)
- News-Card: kein Shadow, dafuer `inset 0 0 0 1px line`
- Mode-Cards: `var(--bk-shadow-1)`

### Icons

- `Icon.Menu` (Hamburger) — 22px, stroke 2.2
- `Icon.Profile` (Avatar) — 22px, stroke 2.0
- `Icon.Cup` (Pokal) — 22px, stroke 2.0, inside 64x64 weisser Block
- `Icon.ChevronRight` (News-Arrow) — 20px
- `Icon.Plus2` (FAB) — 20px
- `Icon.Close` (Sheet) — 22px

### Brand-Elemente

- **Logo-Mark**: `../../assets/logo-mark.svg`, 34x34 in der Top-Bar. **Asset muss das Kubb-Club-Logo sein** (K+Crown-Glyph).
- **Wordmark "Kubb Club"** als Eyebrow im Greet-Block.

## Komponenten-Inventar

- `HomeScreen` — Hauptkomponente
- `RecentRow` — eine Zeile in der Recent-List
- `TrainingSheet` — Bottom-Sheet mit Modus-Auswahl (Sniper / Finisseur)
- Importiert: `BK.Icon`

Inline-Helfer:
- Tones via `tone === 'bad'` Switch in `RecentRow`.

## Interaktions-Pattern

- **Tap-Targets**: alle Icon-Buttons 48x48 (Hamburger, Profil, Sheet-Close); FAB 56dp hoch; Tiles full-width Buttons.
- **`onPick(mode)`**: Callback fuer Modus-Auswahl. `'tournier'` aus Tournament-Tile, `'8m'` aus Sniper-Mode-Card, `'finisseur'` aus Finisseur-Mode-Card.
- **`onOpenAppSettings`**: oeffnet `AppSettingsModal` (siehe `mobile-app-settings-modal.md`).
- **`onOpenProfile`**: navigiert zu Profil (siehe `mobile-profile-screen.md`).
- **Training-Sheet**: oeffnet ueber FAB, schliesst durch Tap auf Backdrop oder Close-Button.
- **News-Tile**: externer Link `https://kubbtour.ch`, `target="_blank"`, `rel="noopener noreferrer"`.

### Loading / Error / Empty-States

- Recent-List zeigt 3 Mock-Eintraege im Kit. **Empty-State** ("Noch keine Sessions") **fehlt** — AUDIT.md Punkt 4.2 flaggt das.
- Tournament-Tile: zeigt immer Mock-Daten ("Match-Modus"). Echter Flutter-Code muss zwischen "kein aktives Turnier" vs. "naechstes Turnier am ..." unterscheiden.
- News-Tile: statischer Link, kein Loading-State.

### Navigation

- Vorwaertsnavigation:
  - Hamburger → AppSettings-Modal (bottom sheet)
  - Profil-Icon → ProfileScreen (push)
  - Tournament-Tile → Tournament-Liste (push)
  - News-Tile → externer Browser
  - FAB → TrainingSheet (modal) → Sniper / Finisseur-Konfig (push)

## Accessibility

- Hamburger: `aria-label="Menue"` (Spec sagt "Menü", Umlaut OK).
- Profil: `aria-label="Profil"`.
- FAB: `aria-label="Neue Trainings-Session starten"`.
- Sheet-Close: `aria-label="Schliessen"`.
- News-Link: `rel="noopener noreferrer"` ist gesetzt.
- Logo-Mark: `alt="Kubb Club"` ✅ rebrand-konsistent.
- Touch-Targets ≥ 48dp ✅.
- Kontrast: Wood-Tile weisser Text auf `#A16F24` — laut WCAG-Quick-Check ~5:1 (AA fuer normalen Text bestanden).

## Quality-Gate-Checkliste

- [x] Layout-Struktur dokumentiert.
- [x] Alle Tokens benannt (kein magischer Hex-Wert).
- [x] Touch-Targets ≥ 48dp.
- [x] Rebrand-Strings durchgezogen (`Kubb Club` als Eyebrow + Logo-Alt).
- [x] Tabular-Nums auf Recent-Rates.
- [ ] **Empty-State Recent** fehlt im Design — AUDIT.md 4.2.
- [ ] **Loading/Skeleton** fehlt — AUDIT.md 4.3.
- [ ] **Offline-Indicator** fehlt — AUDIT.md 4.4.
- [ ] Logo-Asset `logo-mark.svg` muss als Kubb-Club-Variante existieren.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **`home_screen.dart`** im Repo nutzt `home_greeting.dart` als Sub-Widget. Pruefen, ob Greeting-Eyebrow den neuen `Kubb Club`-Text traegt.
2. **Tournament-Tile** auf Home: laut Memory-File ist die Tile "aktiv" nach M1. Pruefen, ob die Wood-Background-Variant uebernommen ist oder noch das alte Design.
3. **News-Tile (kubbtour.ch)** ist neu im Mobile-Kit — Flutter-Pendant existiert vermutlich noch nicht. Implementierung als Tap-Karte mit `url_launcher` faellig.
4. **FAB-Position**: Material-3 sagt 16/16 vom Container-Edge. Mobile-Kit nutzt `right:24, bottom:24` weil das Screen-Inset bereits 16 ist (24-16=8 effektiv, nicht ganz Spec-konform). Flutter sollte konsistent 16/16 vom physischen Edge nutzen (`Padding(padding: EdgeInsets.only(right: 16, bottom: 16), child: FloatingActionButton.extended(...))`).
5. **TrainingSheet** mit nur 2 Cards (Sniper + Finisseur). Memory-File sagt: "Training-Sheet hat 4. Modus-Card" (4m-Linie war geplant) — pruefen, ob das aktuelle Design absichtlich nur 2 zeigt (Phase-1-Scope) oder ob der Memory-Stand veraltet ist.
6. **Greeting-Text** im Kit ist hartcodiert `Servus, Marc.`. Flutter-Variant zieht den Display-Name aus Auth-Profile.
