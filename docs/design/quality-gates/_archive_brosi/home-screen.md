# Quality-Gate: Home Screen

**Quelle**: `docs/design/ui_kits/app/HomeScreen.jsx`
**Flutter-Pendant**: `lib/features/training/presentation/home_screen.dart`
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (top-down)

1. **Top-Bar** — flex row, `space-between`. Links Hamburger (`Icon.Menu`), Mitte Brand-Logo (`logo-mark.svg`, 34x34), rechts Profile-Avatar (`Icon.Profile`). `marginLeft/right: -4`, `paddingBottom: 4` (Buttons sind 48x48, optisch rueckt das die Icons leicht aus dem Rand).
2. **Greet-Block** — Eyebrow `"Brosi's Kubb"` (11px, weight 600, caps, muted) plus Greeting (`"Servus, Marc."`, Display, 28px, weight 800, `letterSpacing: -0.02em`). Padding `8px 0 16px`.
3. **Tournier-Karte** (primary tile) — full-width, `minHeight: 120`, `borderRadius: 20`, `padding: 18px`, `background: var(--bk-wood-500)`, `color: var(--bk-chalk-50)`, `boxShadow: var(--bk-shadow-1)`. Linker Block: Eyebrow `"Tournier"`, Title-Display `"Match-Modus"` (28px, weight 800), Subtitle `"Vollspiel · 6 Stoecke pro Halbsatz"`. Rechter Block: 64x64 Icon-Container mit `Icon.Cup`, `background: rgba(255,255,255,0.18)`, `borderRadius: 16`.
4. **News-Karte** — external link `kubbtour.ch`. `minHeight: 72`, `padding: 12px 14px`, `borderRadius: 16`, `background: var(--bk-bg-raised)`, `boxShadow: inset 0 0 0 1px var(--bk-line)`. Linker Block: Eyebrow in Meadow-600 (`"News · Kubbtour.ch"`), Display-Title 15px, Sub 12px muted. Rechts: ChevronRight muted.
5. **Section-Header** "Zuletzt" (Eyebrow-Pattern).
6. **Recent-List** — Container `borderRadius: 14`, `background: var(--bk-bg-raised)`, `padding: 4px 12px`. Zeilen `grid: 56px 80px 1fr`, `gap: 8`, `padding: 10px 0`, `borderBottom: 1px solid var(--bk-line)`. Spalten: Tag (Mono, 11px, caps, muted), Rate (Display, 18px, weight 700, `tabular-nums`), Sub (13px, muted). Tone `bad` → Rate-Color `var(--bk-miss)`.
7. **FAB "Training"** — Material-3-Position `right: 24, bottom: 24`. `minHeight: 56`, `padding: 0 22px 0 18px`, `borderRadius: 16`, `background: var(--bk-meadow-600)`, `color: var(--bk-on-primary)`. Icon `Plus2` + Label "Training" (Display, 17px, weight 700). `boxShadow: var(--bk-shadow-2)`.

### Training-Sheet (modal von FAB)

- Backdrop: `rgba(12,11,7,0.45)`.
- Sheet: `borderTopRadius: 24`, `background: var(--bk-bg-raised)`, `padding: 10px 18px 32px`, `gap: 10`. Grabber `36x4` Stone-200. Head: Eyebrow `"Neue Session"` + h2 `"Welcher Modus?"` (Display, 22px, weight 700, `letterSpacing: -0.02em`) + Close-Button.
- Mode-Card "Sniper-Training": `background: var(--bk-meadow-500)`, `color: var(--bk-on-primary)`. Name 24px weight 800, Sub 13px, rechts `"8 m"` als Display-Number 36px weight 800.
- Mode-Card "Finisseur": `background: var(--bk-stone-900)`, `color: var(--bk-chalk-50)`. Rechts `"7/3"`.
- Card-Style: `minHeight: 96`, `borderRadius: 18`, `padding: 14px 18px`, `boxShadow: var(--bk-shadow-1)`.

### Farben (Token-Namen)

- Background: `tokens.bg` (`chalk50`)
- Primary surface (Tournier-Tile): `KubbTokens.wood500`
- Secondary surface (Mode-Sniper): `KubbTokens.meadow500`
- Secondary surface (Mode-Finisseur): `KubbTokens.stone900`
- FAB: `KubbTokens.meadow600` mit `tokens.onPrimary` Text
- News-Card surface: `tokens.bgRaised` + 1px `tokens.line` Inset
- Eyebrow / Sub: `tokens.fgMuted`
- News-Eyebrow Accent: `KubbTokens.meadow600`
- Bad-Tone Rate: `tokens.danger` (`KubbTokens.miss`)

### Typografie

| Bereich | Font | Groesse | Weight | Letter-Spacing |
|---|---|---|---|---|
| Greeting | Display | 28 | 800 | -0.02em |
| Tournier-Name | Display | 28 | 800 | -0.02em |
| Mode-Name | Display | 24 | 800 | -0.02em |
| Sheet-Title | Display | 22 | 700 | -0.02em |
| Mode-Num | Display | 36 | 800 | -0.03em |
| FAB-Label | Display | 17 | 700 | — |
| Recent-Rate | Display | 18 | 700 | — |
| News-Title | Display | 15 | 700 | -0.01em |
| Tournier-Sub / Mode-Sub | Body | 13 | 400 | — |
| Recent-Sub | Body | 13 | 400 | — |
| News-Sub | Body | 12 | 400 | — |
| Recent-Tag | Mono | 11 | 700 | 0.06em caps |
| Eyebrow | Body | 11 | 600 | 0.08em caps |

### Spacing

- Outer scroll padding: `54px 16px 96px` (top 54 = Notch/Status-Bar, bottom 96 = FAB-Clearance)
- Section-Gap: `marginTop: 14, marginBottom: 8` zwischen Section-Header und Liste
- Karten-Gap: 12 (`KubbTokens.space3`) zwischen Tournier und News
- News -> Section "Zuletzt": 14

### Border-Radius

- Tournier-Card: 20 (zwischen `radiusXl` 16 und custom)
- Mode-Card: 18
- News-Card: 16 (`radiusXl`)
- Recent-List Container: 14
- Section-Buttons / Icon-Slot: 12 (`radiusLg`)
- FAB: 16 (`radiusXl`)
- Sheet: 24 top corners

### Shadows

- Tournier-Card, Mode-Card: `--bk-shadow-1` (medium elevation)
- FAB: `--bk-shadow-2` (high elevation)

### Icons

- `Icon.Menu` (Hamburger, 22px), `Icon.Profile` (22px), `Icon.Cup` (in 64x64 Slot), `Icon.ChevronRight` (20px), `Icon.Plus2` (FAB, 20px), `Icon.Close` (Sheet, 22px)
- Brand-Logo: `logo-mark.svg` 34x34 als `<img>` — Flutter sollte denselben SVG-Asset rendern (z.B. `SvgPicture.asset`).

## Komponenten-Inventar

| Sub-Komponente | Aufgabe | Wiederverwendbar | Props |
|---|---|---|---|
| `HomeScreen` | Screen-Root | nein | `onPick, onOpenAppSettings, onOpenProfile` |
| `RecentRow` | Eine Zeile in Recent-List | inline-only | `tag, rate, sub, tone?` |
| `TrainingSheet` | Mode-Auswahl-Sheet | inline-only | `onPick(mode), onClose` |
| Top-Bar | flex row mit Buttons + Brand | nein (inline) | — |
| Tournier-Card | Primary CTA-Tile | ja (vgl. Flutter `TournierCard`) | `eyebrow, title, subtitle, onTap` |
| News-Card | sekundaere Link-Tile | ja (vgl. Flutter `NewsCard`) | `eyebrow, title, subtitle, onTap` |
| Recent-Section | Container fuer Recent-Liste | ja (vgl. Flutter `RecentSection`) | `title, items` |
| FAB | Extended-FAB "Neue Session" | Material-3-Standard | `onPressed` |

**Mode-Cards im Sheet**: derzeit inline-styled, sollte als `KubbModeCard`-Widget extrahiert werden (Pattern: full-width, links Title/Sub, rechts Display-Number, einfaerbbar).

## Interaktions-Pattern

- **Tap-Targets**: alle Icon-Buttons 48x48; FAB 56 Hoehe; Tournier/News/Mode-Cards Full-Tile-Tap (> 72-120 Hoehe). Konform mit `KubbTokens.touchMin`.
- **Hover/Pressed-States**: JSX hat keine expliziten `:hover`/`:active`-States (Mobile-First). Flutter sollte `InkWell`-Ripple oder `Material` Hover/Press-Ueberlay nutzen.
- **Loading-States**: Recent-Liste muss Loading-Skeleton zeigen (Greeting kann ohne Profil rendern → `homeGreetingFallback`). Flutter rendert recent-leer als `if (recent.isNotEmpty)` — explizites Loading/Skeleton fehlt aktuell.
- **Empty-States**: Recent-Liste leer → komplette Section wird im Flutter weggelassen. JSX zeigt im Demo immer 3 Eintraege. Empfehlung: leere Section mit Empty-Hinweis ("Noch keine Sessions") oder ganz weglassen — Flutter-Verhalten passt zum Pragmatismus.
- **Error-States**: Recent-Provider-Error → Flutter aktuell `orElse: () => const <RecentSessionView>[]`, schluckt Fehler still. Pruefen ob das beabsichtigt ist.
- **Navigation-Pfade**:
  - Hamburger → Settings (`/settings`)
  - Profile-Avatar → Player-Hub-Sheet (oeffnet bottom-sheet; JSX setzt das auf eine eigene `ProfileScreen`-Route — Flutter weicht ab, oeffnet PlayerHub)
  - Tournier-Card → `TournamentRoutes.list`
  - News-Card → external URL `kubbtour.ch` via `launchUrl`
  - FAB → `TrainingSheet` modal
  - Sheet "Sniper" (`'8m'`) → `/training/sniper/config` (ueber TrainingSheet.show-Logik)
  - Sheet "Finisseur" → `/training/finisseur/config`
  - Recent-Zeile → derzeit kein Tap-Target im JSX (informativ). Flutter aktuell ebenfalls passiv.

**Mismatches Flutter vs. JSX**:
- Flutter hat eine **zusaetzliche Teams-Card** zwischen Tournier und News (`NewsCard(eyebrow: teamListTitle, ...)`). Das ist im JSX-Design nicht vorgesehen.
- Profile-Avatar oeffnet `PlayerHubSheet`, nicht eine `ProfileScreen`-Route.
- Brand-Logo (34x34 SVG) zwischen Hamburger und Avatar fehlt in der Flutter-Top-Bar — Flutter nutzt nur Title-Text `"Brosi's Kubb"` ueber den `KubbAppBar`-Slot.

## Accessibility-Hinweise

- **Kontrast**: Tournier-Card (`wood500` `#A16F24` + `chalk50` `#FBFAF6`) Kontrast ~4.3:1 — gerade so AA. Mode-Card Meadow-500 + chalk50: ~4.6:1. Mode-Card Stone-900 + chalk50: ~16:1. Recent-Rate auf bgRaised: hoch (Stone-900 auf white). News-Eyebrow Meadow-600 auf chalk0: ~5:1.
- **Touch-Targets**: alle Buttons ≥ 48dp (`iconBtn: 48x48`, FAB 56, Cards ≥ 72).
- **Reader-Labels**:
  - Hamburger: `aria-label="Menue"` → Flutter `tooltip: l.settingsTitle`
  - Profile-Avatar: `aria-label="Profil"` → Flutter `tooltip: l.profileTitle`
  - FAB: `aria-label="Neue Trainings-Session starten"` → Flutter `Text(l.homeFabLabel)`
  - Sheet-Close: `aria-label="Schliessen"`
- **Reduced-Motion**: keine expliziten Animationen — passt.
- **Screen-Reader-Reihenfolge**: TopBar → Greeting → Tournier → News → Recent → FAB. Flutter erzwingt diese Reihenfolge via Column-Order; passt.

## Quality-Gate-Checkliste (pruefbar gegen Flutter-Impl)

- [ ] Layout-Struktur 1:1 zum Design: TopBar (3 Slots inkl. Brand-Logo), Greeting-Block, Tournier-Card, News-Card, Recent-Section, FAB.
- [ ] Brand-Logo (34x34 SVG) in der Mitte der TopBar gerendert.
- [ ] Tournier-Card mit `wood500` Background, 64x64 Icon-Slot mit `Icon.Cup`, Subtitle `"Vollspiel · 6 Stoecke pro Halbsatz"`.
- [ ] News-Card mit `bgRaised` + 1px `line` Inset und Meadow-600 Eyebrow.
- [ ] Recent-Liste mit 3-Spalten-Grid `56px / 80px / 1fr`.
- [ ] FAB rechts unten, 24/24 vom Rand, `meadow600` mit Plus-Icon + Text-Label.
- [ ] TrainingSheet als bottom sheet mit Grabber + Eyebrow + h2 + 2 Mode-Cards.
- [ ] Mode-Card Sniper: `meadow500` Background, `8 m` Display-Number.
- [ ] Mode-Card Finisseur: `stone900` Background, `7/3` Display-Number.
- [ ] Alle Tokens aus `KubbTokens` referenziert (keine Hex-Hardcodes ausser logo-svg).
- [ ] Spacing-System `space3/4/5/6` konsistent.
- [ ] Empty-State Recent: stille Auslassung oder Empty-Hinweis (Entscheidung treffen).
- [ ] Loading-State Recent: Skeleton (Sekundaer-Priorisierung).
- [ ] Error-State Recent: nicht still schlucken — pruefen.
- [ ] Touch-Targets >= 48dp.
- [ ] Keine UUID-Substrings im UI (Recent-Tag muss "Sniper" / "Fin" sein, nicht eine Session-ID).
- [ ] i18n via `AppLocalizations` (Greeting, Eyebrow, Tournier-Title/Sub, News-Title/Sub, Section-Header, FAB-Label, Sheet-Title).
- [ ] Brand-Logo-Asset (`assets/logo-mark.svg` o.ae.) im Flutter-Asset-Pfad registriert.
- [ ] FAB-Position respektiert SafeArea/Notch (Flutter `FloatingActionButton` default ok).

## Bekannte Abweichungen (Flutter aktuell vs. Design)

1. **Teams-Card** zwischen Tournier und News ist Flutter-only (`NewsCard` mit `teamListTitle` / `teamListTabMine`). Im JSX-Design nicht vorhanden. Entscheidung: drinlassen (Phase-1-Workflow braucht den Einstieg) oder verschieben/entfernen.
2. **Brand-Logo in TopBar fehlt**. Flutter rendert nur den `KubbAppBar` mit Title-Text "Brosi's Kubb"; das 34x34 Logo aus dem JSX ist nicht eingebaut.
3. **AppBar-Komponente**: Flutter nutzt `KubbAppBar` (mit `automaticallyImplyLeading: false`), der JSX nutzt eine eigene Top-Bar (kein zentraler Title sondern Logo). Pruefen ob Home-Top-Bar als eigene Komponente (`HomeTopBar`) sinnvoller ist als der gepatchte `KubbAppBar`.
4. **Profile-Avatar oeffnet PlayerHubSheet**, nicht eine eigene ProfileScreen-Route wie im JSX vorgesehen (`onOpenProfile` → naviger zu Profil).
5. **News-Card Eyebrow** in Flutter ist `l.homeNewsEyebrow` — Wert pruefen ob "News · Kubbtour.ch" enthaelt.
6. **Mode-Sheet** (TrainingSheet): Flutter hat das bereits, aber Vergleich der visual specs (Mode-Card-Hoehe 96, Display-Number 36px, Color-Variants) noch nicht gegen-validiert.
7. **Greeting**: Flutter zeigt `homeGreeting(profile.displayName)` ohne Punkt — JSX zeigt `"Servus, Marc."` mit Punkt. Konsistenz pruefen.
8. **Shadows**: Tournier-Card und FAB sollten `shadow1` / `shadow2` haben — `KubbTokens` hat keine Shadow-Konstanten, Flutter-Implementierung pruefen.
9. **News-Card Affordance**: ChevronRight rechts; pruefen ob `NewsCard`-Widget das rendert.
