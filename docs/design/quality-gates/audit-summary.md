# Quality-Gate: AUDIT-Essenz (Designer-Audit Kubb Club)

**Quelle**: `docs/design/AUDIT.md` (2026-05-25, Designer-Audit nach Rebrand)
**Cross-Ref**: `docs/design/chats/chat1.md`, `chat2.md`, `chat3.md` (Iterations-Logs)
**Stand**: 2026-05-28

---

## Was schon trägt

- Token-System `lib/core/ui/theme/kubb_tokens.dart` ↔ `docs/design/colors_and_type.css`. Migration auf `--kc-*` Canonical mit `--bk-*`-Aliases ist durchlaufen.
- 9 Mobile-Screens prototypisiert in `docs/design/ui_kits/app/` (Home, Sniper, Finisseur Config + Per-Stick, Summary, Stats, Profile, Settings, AppSettings/Csv Modals). Plus `MatchScreen.jsx` und `TournamentScreen.jsx` aus chat2/3.
- Desktop UI Kit komplett (5 ursprüngliche + 6 nachgezogene Screens für 1:1-Parität, siehe chat3).
- Auth-Routes im Flutter-Router angelegt (`AuthRoutes.signIn`, `anonymousSignup`, `restore`, `accountLink`, `deleteAccount`, `onboardingTour`).
- High-Contrast und Dark-Mode als ThemeData-Varianten.
- Lokalisierung über `AppLocalizations`, DE als Hauptsprache.

## Rebrand-Blocker (zwingend vor MVP-Launch)

### Asset-Export

iOS Asset Catalog: 1024, 180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20 (13 PNGs).
Android mipmap-*dpi*: 192, 144, 96, 72, 48 (5 PNGs) + Adaptive Icon (`ic_launcher_foreground.xml` + `ic_launcher_background.xml`).
Web PWA: 512, 192 (+ maskable Varianten).
Favicon: 16, 32 ICO-multi + apple-touch-icon 180.

→ Export-Step nötig (SVG → PNG). Master-SVGs liegen unter `docs/design/assets/`.

### Launch Screen

- iOS: `LaunchScreen.storyboard` neu auf Meadow-Background + zentriertes K+Crown (Vorlage `preview/brand-splash.html` Variante A oder B).
- Android: `android/app/src/main/res/drawable/launch_background.xml` aktualisieren.
- Web: `web/index.html` `<body>`-Loader auf Meadow + Mark.

### String-Rebrand

- `lib/l10n/app_de.arb` (+ `app_en.arb` falls vorhanden) — alle `Brosi`-Vorkommen ersetzen.
- `pubspec.yaml` `name: kubb_club` (Package-Rename invasiv, optional in Phase 1).
- `android/app/src/main/AndroidManifest.xml` `android:label`.
- `ios/Runner/Info.plist` `CFBundleDisplayName`.
- `web/manifest.json` `name`, `short_name`.
- Footer-Strings in `SettingsScreen.jsx` und `AppSettingsModal.jsx` Mobile-Kit (laut `quality-gates/mobile-kit-overview.md` noch offen).

### Onboarding-Tour

Router referenziert `AuthRoutes.onboardingTour`, Design-Kit liefert keine Visuals.
Vorschlag aus AUDIT (4 Slides):
1. „Sniper-Training für deine Wurf-Konstanz." (8m-Modus)
2. „Finisseur — das Match-Endspiel üben."
3. „Turniere & Ligen, online verfolgt."
4. „Mit Freunden & Clubs trainieren."

Owner-Approval auf die Slide-Texte ist Voraussetzung.

## Visuell fehlend (high impact, im Router aber ohne Design)

| Screen | Route | Warum kritisch |
|---|---|---|
| Sign-In Hub | `/sign-in` | Erster Eindruck |
| Anonymous Signup | `/sign-in/anonymous` | Conversion-kritisch |
| Restore (Mnemonic) | `/sign-in/restore` | BIP39-Flow |
| Account Link | `/sign-in/link` | Anonym → Email Upgrade |
| Edit Profile | `/profile/edit` | Avatar, Display Name |
| Inbox | `/inbox` | Match-Invites, Erinnerungen |
| Friends List | `/social/friends` | Add by Handle, Request-States |
| Groups / Clubs | `/social/groups` | Mitglieder, Rangliste (siehe Owner-Eskalation Sprint A — wird entfernt) |
| Match-Flow (Lobby/Result/Await/Finished) | `/match/*` | Hauptfeature, kein Mobile-Kit-Pendant für konsolidierten Live-Tab |
| Tournament Detail / Standings / Bracket | `/tournament/*` | Saison-Übersicht |
| Tournament Match Conflict / Override | `/tournament/.../conflict` | Score-Disput-UI |

## UX-Lücken (Designer-Empfehlung)

- **Tablet/Desktop-Layout**: Bisherige Designs sind Phone-only (390×844). Empfehlung Master/Detail auf Tablet (340dp Navi + Flex-Detail). Desktop UI Kit ist die Referenz. Eigener Sprint nach Sprint B.
- **Empty States**: Home (Erst-Nutzer), Friends, Tournament-Liste, Inbox, Stats. Jede leere Liste mit K+Crown-Vignette + Satz-CTA.
- **Skeleton-Loading**: Session-Liste, Stats-Charts, Tournament-Standings.
- **Offline-Banner**: „Offline · letzte Sync 2 min" gelbe Pille top.
- **Notifications / Match-Invites**: Push-Copy + In-App-Banner + Inbox-Item.
- **Achievements**: `AppSettingsModal.jsx` `onOpenAchievements` ist verdrahtet, Screen fehlt. 12–15 Badges (100 Hits, 1000 Hits, Erster Strafkubb, 10× Streak, Heli-Master, Konstanz-King, Saisonteilnehmer, Top-100-ELO, …).
- **Share / Match-Link**: `share_plus` in `pubspec.yaml`, kein UI. Share-Sheet im AppBar-Right-Slot mit Pre-Rendered Match-Karte.
- **Heli-Toggle**: Aktuell 3 Screens tief in Settings. Hint-Banner beim 3. „Hit"-Tap mit Heli-Bedingung.

## Tech-Anmerkungen aus dem Audit

- `lib/core/ui/icons.dart` mapped `heli → wind`, `king → crown`, `cup → trophy` über Lucide. Kommentar nennt CustomPainter als Future-Task — die Brand-Glyphen sind aktuell Stellvertreter.
- `--dart-define=SUPABASE_URL` + `SUPABASE_ANON_KEY` hardcoded-at-build → drei Flavors (Dev/Staging/Prod) anlegen.
- Keine Sentry/Crashlytics-Integration. Release ohne Crash-Reporting ist riskant.
- `google_fonts: ^8.1.0` lädt online — für Offline-First lokal bundeln (~250 KB).
- `freezed` + `riverpod_generator` + `drift_dev` Codegen-Schritt nicht in CI dokumentiert. Vor Release sicherstellen.

## Reihenfolge (AUDIT §6 — Primärquelle für Sprint B)

1. App-Icon-Export-Pipeline — blockiert TestFlight + Play Console.
2. Sign-In + Anonymous Signup designen.
3. Launch Screen iOS/Android/Web.
4. Brand-Strings in `app_de.arb`.
5. Onboarding-Tour (3–4 Slides).
6. Match-Flow Lobby → Live → Result.
7. Tablet/Desktop-Layout für Top-3 (Home, Stats, Match).
8. Custom Brand-Glyphen als CustomPainter.
9. Achievements-Screen + Badge-Inventar.
10. Empty / Loading / Offline States systematisch.

**Punkt 1–5 = Rebrand-MVP. Punkt 6–10 = Polish.**

## Design-Decisions aus den Chats (kondensiert)

### chat1 — Logo-Refinement (521 Zeilen)

- **Variante A „Meadow Badge"** ist Primary App-Icon. Grünes Squircle mit hölzernem K + goldener Krone. Wood-Maserung + Astknoten sichtbar, K bleibt über der Pitch-Line.
- Drei weitere Logo-Varianten: B „Chalk Sign" (Cremepapier, Gras-Striche), C „Ink Crest" (Dark-Mode Schwarz + grüner Glow + Goldring), D „Roundel Crest" (Medaillen-Format mit „KUBB · CLUB"-Umlauf + EST. 2025).
- Wordmark: K+Crown-Mark links, „Kubb Club." in Fraunces, EST. 2025 · DACH mit gilded Hairline darunter.
- Splash-Screen 5 Varianten (`preview/brand-splash.html`): A Meadow + Wordmark, B Mark Only, C Chalk Daytime, D Ink Dusk, E Web/Tablet.
- AUDIT.md wurde am Ende dieses Chats geschrieben (`AUDIT.md`).

### chat2 — Desktop UI Kit (116 Zeilen)

- 5 Master/Detail-Screens auf 1440×920 im Browser-Frame mit Sidebar-Nav, Dark-Toggle, Pill-Switch.
- Dashboard, Training (Sniper + Finisseur), Statistik (Sparkline-Hero + Heatmap), Turniere (Liste + Detail + Sub-Tabs), Match (Lobby/Live/Result).
- Tablet-Variante = Desktop (Owner-Entscheid).

### chat3 — 1:1-Parität Desktop ↔ Mobile (240 Zeilen)

- **Owner-Entscheid**: jeder Screen muss Mobile und Desktop haben.
- Neu auf Desktop: `FinisseurStickScreen`, `SummaryScreen`, `ProfileScreen`, `SettingsScreen`, `AppSettingsModal`, `CsvExportModal`.
- Neu auf Mobile: `MatchScreen`, `TournamentScreen`.
- Mapping-Tabelle für alle 12 Flows in beiden Kits.

## Cross-Reference

| Thema | Datei |
|---|---|
| Rebrand-Walk-Through | `docs/design/REBRAND_README.md` |
| Mobile-Kit-Inventar | `docs/design/quality-gates/mobile-kit-overview.md` |
| Bug-Hunt-Sweep | `docs/bug-hunt-2026-q3/master-report.md` Sektion End-of-Sweep |
| Mängel-Report (Lukas) | `docs/MAENGEL_REPORT_2026-05-25.md` |
| Sprint-B-Plan | `docs/plans/sprint-b-ui-polish/sprint-plan.md` |
