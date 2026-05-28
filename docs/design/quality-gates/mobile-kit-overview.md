# Quality-Gate: Mobile-Kit Overview (Kubb Club Rebrand)

**Quelle**: `docs/design/ui_kits/app/` (14 Files inkl. `index.html`)
**Token-SSoT**: `docs/design/colors_and_type.css` (`--kc-*` Canonical, `--bk-*` Backward-Compat)
**Flutter-Mapping**: `lib/core/ui/theme/kubb_tokens.dart`
**Stand**: 2026-05-28 (Rebrand Brosi's Kubb → Kubb Club)

---

## Zweck

Index-Dokument fuer die 13 Screen-/Komponenten-Specs im Mobile-Kit. Beschreibt Kit-weite Patterns, listet alle Screens mit Flutter-Pendant-Status und verweist auf die Sprint-Priorisierung aus `docs/design/AUDIT.md`.

Pro-Screen-Details liegen in den separaten `mobile-*.md` Files in diesem Verzeichnis.

---

## Screen-Inventar (Mobile)

| # | Screen | Kit-File | Flutter-Pendant | Lueckenstatus |
|---|---|---|---|---|
| 1 | Shared Components (Icons, AppBar) | `shared.jsx` | `lib/core/ui/icons.dart`, AppBar inline pro Screen | Brand-Glyphen sind Lucide-Stubs; AppBar nicht zentralisiert |
| 2 | iOS Device Frame | `ios-frame.jsx` | nicht 1:1 portiert (Demo-Renderer) | nur fuer das Kit, nicht fuer die Flutter-App |
| 3 | Home | `HomeScreen.jsx` | `lib/features/training/presentation/home_screen.dart` | Logo-Asset + Greeting-Tile (Tournament/News) muessen aktualisiert werden |
| 4 | Sniper-Training (vormals 8m) | `EightMScreen.jsx` | `lib/features/training/presentation/sniper_session_screen.dart` + `sniper_config_screen.dart` | Eye-Toggle (Trefferzahl verdecken) ist neu; Settings-Sheet pattern OK |
| 5 | Finisseur-Konfiguration | `FinisseurConfigScreen.jsx` | `lib/features/training/presentation/finisseur_config_screen.dart` | Visual-Stack-Preview + Constraint-Note (max 10 Kubbs) abgleichen |
| 6 | Finisseur Per-Stick | `FinisseurStickScreen.jsx` | `lib/features/training/presentation/finisseur_stick_screen.dart` | Strafkubb-Doppelwurf-Pattern ist neu; Stick-Pip-Farbtonung pruefen |
| 7 | Session-Summary | `SummaryScreen.jsx` | `lib/features/training/presentation/summary_screen.dart` | Multi-Distanz-Breakdown ist neu im Spec |
| 8 | Statistik | `StatsScreen.jsx` | `lib/features/stats/presentation/stats_screen.dart` | Sparkline + Filter-Sheet pro Tab abgleichen |
| 9 | Profil | `ProfileScreen.jsx` | `lib/features/player/presentation/profile_screen.dart` | Provider-Zeile (Google/Apple) inkl. Trennen-Pille |
| 10 | Einstellungen (Drawer-Liste) | `SettingsScreen.jsx` | `lib/features/settings/presentation/settings_screen.dart` | Footer-String `Brosi's Kubb · v0.1.0` ersetzen |
| 11 | App-Einstellungen Modal | `AppSettingsModal.jsx` | nicht klar im Repo — Settings-Screen ist drawer-style | Modal-Variant fehlt evtl. als Bottom-Sheet |
| 12 | CSV-Export Modal | `CsvExportModal.jsx` | `lib/features/settings/presentation/csv_export_modal.dart` | Vorschau-Code-Block + Mode-Checks abgleichen |
| 13 | **Match (Live)** | `MatchScreen.jsx` **NEU** | `lib/features/match/presentation/match_lobby_screen.dart` + `match_config_screen.dart` + `match_result_screen.dart` + `match_await_others_screen.dart` + `match_finished_screen.dart` | **Single-Tab-Live-Screen mit 4-Action-Pad fehlt komplett** — Flutter hat nur Lobby/Result/Await/Finished, aber kein konsolidiertes Live-Tabbed-Screen |
| 14 | **Tournament (Mobile-Uebersicht)** | `TournamentScreen.jsx` **NEU** | `lib/features/tournament/presentation/tournament_list_screen.dart` + `tournament_detail_screen.dart` + `tournament_standings_screen.dart` + `tournament_bracket_screen.dart` + 7 weitere | Flutter hat die Einzel-Screens; **die konsolidierte Hero-Tile + Sub-Tab-Mobile-Variante mit Filter-Chips ist neu** |

**Total**: 12 Mobile-Screens + 2 Infrastruktur-Files (shared + iOS-Frame). Index-Demo `index.html` ist Renderer fuer das Kit, kein eigenes Quality-Gate-Subjekt.

---

## Kit-weite Patterns

### Inset-Card (Surface-Card)

```
background:   var(--bk-bg-raised)  ==  KubbTokens.bgRaised  ==  #FFFFFF (light)
border-radius:14px (Listen) | 16-18px (Hero/Tiles) | 20-24px (Sheets/Verdict)
padding:      10-14px innen
shadow:       inset 0 0 0 1px var(--bk-line)  ODER  var(--bk-shadow-1)
margin:       0 16px  (Screen-Inset)
```

Variants:
- `bg-raised` als Default
- `bg-sunken` (`KubbTokens.bgSunken`, `#F4F1E8`) fuer Segmented-Backgrounds und Code-Vorschauen
- `stone-900`-Inverse fuer Live-Score-Strip und aktive Pill-States

### Section-Header (Eyebrow)

```
fontSize:       11px
fontWeight:     600
letterSpacing:  0.08em
textTransform:  uppercase
color:          var(--bk-fg-muted)  ==  KubbTokens.fgMuted  ==  stone-500
padding:        14px 18px 8px  (typisch)
```

Verwendung: jeder Screen mit `<div style={section}>Zuletzt</div>`-artigem Block.

### AppBar (`BK.AppBar`)

Definiert in `shared.jsx`:
- Padding `54px 12px 6px` (top = Safe-Area)
- Linker Slot: Back-Icon-Button 48x48 oder leerer 48-Spacer
- Mitte: Eyebrow (11px uppercase) + Title (Display 18px / Bold)
- Rechter Slot: optional Icon-Button 48x48
- Background `var(--bk-bg)`, sticky-Option vorhanden

**Mismatch zu Flutter**: keine zentrale `KubbAppBar`-Widget-Klasse — jeder Screen baut AppBar inline. Fuer Konsistenz: zentrales Widget einziehen.

### FAB (Material 3)

```
position:  absolute, right:24, bottom:24
minHeight: 56
padding:   0 22px 0 18px
gap:       10
background: var(--bk-meadow-600)  // meadow-600 = #2D6324
color:      var(--bk-on-primary)
fontFamily: var(--bk-font-display)
fontWeight: 700
shadow:     var(--bk-shadow-2)
```

Nur Home nutzt FAB. Andere Screens verwenden Bottom-Buttons (`saveBtn`, `nextBtn`, `applyBtn`).

### Bottom-Sheet Backdrop

```
position:   absolute, inset:0
background: rgba(12,11,7,0.45-0.55)
zIndex:     10-30 (kontextabhaengig)
sheet:      width:100%, maxHeight:92%, overflowY:auto
            borderTopLeftRadius:24, borderTopRightRadius:24
            background:var(--bk-bg) oder var(--bk-bg-raised)
grabber:    36x4 px, stone-200, alignSelf:center
```

### Stat-Tones (semantic colors)

| Tone | Token | Verwendung |
|---|---|---|
| hit | `--bk-hit` / `KubbTokens.hit` (meadow-600 #2D6324) | Treffer, Sieg-Tag |
| miss | `--bk-miss` / `KubbTokens.miss` (#B73A2A) | Fehlwurf, LIVE-Badge, Danger-Button |
| heli | `--bk-heli` / `KubbTokens.heli` (wood-400 #C08A33) | Helikopter (caution) |
| penalty | `--bk-penalty` / `KubbTokens.penalty` (#8A1F3D) | Strafkubb |
| king | `--bk-king` / `KubbTokens.king` (#C89B3D) | Koenigswurf |

### Typografie-Stack

| Rolle | Variable | Family | Verwendung |
|---|---|---|---|
| Display | `--bk-font-display` ≡ `--kc-font-ui` | Bricolage Grotesque (mobile bleibt darauf — siehe CSS-Kommentar Zeile 104-106) | Hero-Zahlen, Section-Titles |
| Body | `--bk-font-body` | Bricolage Grotesque | Fliesstext |
| Mono | `--bk-font-mono` | JetBrains Mono | Tabular-Nums, Logs, Code-Vorschau |

`fontVariantNumeric: tabular-nums` ist Pflicht bei jedem Zahlen-Readout (Score, Counter, Distanz).

**Hinweis**: Die Desktop-Surfaces nutzen Fraunces als Display (`--kc-font-display`). Im Mobile-Kit ist `--bk-font-display` legacy-aliased auf `--kc-font-ui` (Bricolage) — bleibt also bei Bricolage. Wenn Flutter die `--kc-*`-Mapping uebernimmt, **muss** der Mobile-Theme weiterhin Bricolage als Display fuehren, nicht Fraunces, sonst kippt das Mobile-Look.

---

## Rebrand-Aenderungen (Brosi's Kubb → Kubb Club)

### String-Ersetzungen im Mobile-Kit

| Wo | Alt | Neu |
|---|---|---|
| `HomeScreen.jsx` Top-Logo-Alt | `Brosi's Kubb` | `Kubb Club` (siehe Zeile 21) ✅ schon aktualisiert |
| `HomeScreen.jsx` Eyebrow | (war "Brosi's Kubb") | `Kubb Club` (Zeile 27) ✅ |
| `ProfileScreen.jsx` Klub-Field | `Brosi's Kubb` (Zeile 67) | offene Frage — bleibt das ein Eigenname als Beispiel-Klub, oder wird's `Kubb Club`? Spec sagt: bleibt als Beispielname stehen, ist Mock |
| `SettingsScreen.jsx` Footer | `Brosi's Kubb · v0.1.0` (Zeile 35) | `Kubb Club · v0.1.0` — **TODO im Kit** |
| `AppSettingsModal.jsx` Footer | `Brosi's Kubb · v0.1.0` (Zeile 53) | `Kubb Club · v0.1.0` — **TODO im Kit** |
| `index.html` `<title>` | (Demo) | `Kubb Club — Mobile UI Kit` ✅ |

### Asset-Wechsel

- `HomeScreen.jsx` referenziert `../../assets/logo-mark.svg`. Das File liegt unter `docs/design/assets/logo-mark.svg`. Inhalt muss das Kubb-Club-Logomark (K+Crown-Glyph) sein, nicht mehr das Brosi-Logo.
- `index.html` favicon: `../../assets/logo-monogram.svg`.

### Token-Migration

- Token-File ist auf `--kc-*` umgezogen (siehe `colors_and_type.css`).
- `--bk-*` Aliases bleiben durch die Migration aktiv (Zeile 363-416 in `colors_and_type.css`).
- Alle Mobile-Screens nutzen weiterhin `--bk-*` Variablen — der Effekt ist 1:1 durch das Alias-Block aufgeloest.
- **Cut-over-Pfad**: Mobile-Kit darf auf `--bk-*` bleiben, solange `KubbTokens.dart` die Werte spiegelt. Sobald Flutter `--kc-*` direkt mappt, kann der Mobile-Kit nachgezogen werden.

### Brand-Glyphen — Mobile vs. Desktop

Die Mobile-Kit-Icons (`shared.jsx` Zeilen 7-37) sind **Inline-SVG-Stroke-Icons** mit `viewBox="0 0 24 24"`, `strokeWidth=2-2.5`. Brand-Spezifika:
- `Icon.Heli` — vertikales Helikopter-Glyph (Stab + Rotor-Linien). Eigenstaendiges Design.
- `Icon.Trophy` / `Icon.Cup` — beide vorhanden; Home nutzt `Cup`.
- `Icon.King` — Krone aus 4 Spitzen mit `M3 18h18` Basis-Linie.
- `Icon.Target` — konzentrische Kreise (Stamm-Distanz-Icon).
- `Icon.Google` / `Icon.Apple` — Mehrfarbig, fuer Provider-Verknuepfung.

**Flutter-Stand** (`lib/core/ui/icons.dart`): Lucide-Stellvertreter (`heli → wind`, `king → crown`, `cup → trophy`). Per AUDIT.md Punkt 5 ist der CustomPainter-Pass mit hoelzernen Brand-Glyphen ein zukuenftiger Task.

**Differenz Mobile-Kit ↔ Desktop-Kit (relevant fuer die Kit-Sammlung)**: Mobile-Kit ist scharf-stroke (Outline) im Lucide-Stil. Falls das Desktop-Kit auf hoelzerne / engraved Brand-Glyphen wechselt, muss der Mobile-Kit nachziehen — momentan tut er das nicht. AUDIT-Empfehlung Punkt 8 deckt das ab.

---

## Sprint-Priorisierung (per AUDIT.md)

### Rebrand-MVP (Punkt 1-5 aus AUDIT)

1. App-Icon-Export-Pipeline (SVG→PNG aller Groessen)
2. Sign-In + Anonymous Signup Screens (**nicht im Mobile-Kit** — siehe AUDIT 3.0)
3. Launch Screen iOS/Android/Web
4. Brand-Strings in `app_de.arb`
5. Onboarding-Tour (3-4 Slides, fehlt im Kit)

**Im Mobile-Kit selbst** zu erledigen:
- Footer-Strings in `SettingsScreen.jsx` und `AppSettingsModal.jsx` umbiegen.
- `ProfileScreen.jsx` Klub-Field: Mock-Wert behalten, da Beispiel-Klub-Name.

### Make-it-shine (Punkt 6-10 aus AUDIT)

6. Match-Flow (Lobby → Live → Result) — **MatchScreen.jsx ist die Mobile-Spec, Flutter hat aber kein konsolidiertes Live-Screen** → siehe `mobile-match-screen.md`.
7. Tablet/Desktop-Layout (Master/Detail) — nicht Sache des Mobile-Kits, aber relevant fuer TournamentScreen.
8. Custom Brand-Glyphen (Heli, King, Cup, Crown) als CustomPainter.
9. Achievements-Screen + Badge-Inventar — Trigger im Mobile-Kit existiert (`AppSettingsModal.jsx` `onOpenAchievements`), Screen fehlt.
10. Empty / Loading / Offline States systematisch.

### Was im Mobile-Kit fehlt, aber Router/AUDIT erwartet

Aus AUDIT.md Punkt 3 (high impact):
- Sign-In Hub, Anonymous Signup, Restore (Mnemonic), Account Link, Edit Profile (`/profile/edit` — getrennt vom Profil-View), Inbox, Friends List, Groups/Clubs, Tournament Match Conflict/Override (Mobile).

Mobile-Kit Status: **noch nicht designed**. Quality-Gates dafuer entstehen nach Designer-Pass.

---

## Cross-Reference

| Thema | Dokument |
|---|---|
| Sprint-Prio + Repo-Mismatch | `docs/design/AUDIT.md` |
| Rebrand-Anleitung (komplette Brand-Migration) | `docs/design/REBRAND_README.md` |
| Token-SSoT (CSS) | `docs/design/colors_and_type.css` |
| Token-Spiegelung (Flutter) | `lib/core/ui/theme/kubb_tokens.dart` |
| Theme-Choice (Light/Dark/HC) | `lib/core/ui/theme/theme_choice.dart` |

---

## Quality-Gate-Checkliste (Kit-Ebene)

- [x] Alle 12 Screens haben ein Mobile-Pendant im Repo identifiziert oder als FEHLT markiert.
- [x] Token-Stack (CSS `--kc-*` ↔ Flutter `KubbTokens`) ist konsistent.
- [ ] Brand-Glyphen sind im Mobile-Kit definiert, im Flutter aber Lucide-Stubs — **offen** (CustomPainter-Task).
- [ ] Rebrand-String-Sweep: 2 Footer-Strings im Kit noch auf "Brosi's Kubb" — **offen**.
- [x] AppBar-Pattern dokumentiert (zentral in `shared.jsx`).
- [ ] Flutter hat keinen zentralen `KubbAppBar`-Widget — **offen** (Konsistenz-Task).
- [x] Sprint-Reihenfolge aus AUDIT.md referenziert.

## Bekannte Abweichungen Flutter aktuell vs. Mobile-Kit (Kit-Ebene)

1. **AppBar nicht zentralisiert** in Flutter. Jeder Screen baut SliverAppBar/AppBar inline mit unterschiedlichen Paddings.
2. **Brand-Glyphen** sind in `lib/core/ui/icons.dart` Lucide-Mappings, nicht die hoelzernen Originale.
3. **MatchScreen Live-Tab-Konsolidierung** fehlt komplett (siehe `mobile-match-screen.md`).
4. **TournamentScreen Mobile-Hero+SubTab-Variante** fehlt (siehe `mobile-tournament-screen.md`).
5. **Eye-Toggle** im Sniper-Screen (Trefferzahl verdecken) ist neu im Mobile-Kit — siehe `mobile-eight-m-screen.md`.
6. **Multi-Distanz-Breakdown** in Summary ist neu (siehe `mobile-summary-screen.md`).
7. **Strafkubb-Doppelwurf-Pattern** (`p1` + `p2`, Summe ≤ base) in Finisseur-Per-Stick ist neu (siehe `mobile-finisseur-stick-screen.md`).
8. **AppSettings-Modal als Bottom-Sheet** existiert im Kit, im Flutter ist Settings ein eigenes Screen (drawer-style). Zu klaeren, ob Flutter ein Modal-Variant braucht.
