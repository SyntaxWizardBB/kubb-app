# Kubb Club — App Audit & nächste Schritte

Stand: 25. Mai 2026. Basierend auf einer Durchsicht von `SyntaxWizardBB/kubb-app@main` (Flutter, Supabase, Riverpod, go_router, drift).

Dieses Dokument listet **was schon gut ist**, **was für das Rebrand auf Kubb Club zwingend kommt**, und **was wir empfehlen** — sortiert nach Priorität.

---

## 1. Was schon im Repo steht (gute Basis ✅)

- **Solides Token-System** in `lib/core/ui/theme/kubb_tokens.dart` + Spiegelung in `docs/design/colors_and_type.css`. Wir haben das fast 1:1 übernommen und unter `--kc-*` rebrand'et (Aliases auf `--bk-*` bleiben für die Übergangszeit).
- **9 Screens vollständig prototypisiert** in `docs/design/ui_kits/app/`: Home, Sniper, Finisseur Config + Per-Stick, Summary, Stats, Profile, Settings, AppSettings/Csv Modals.
- **Auth-Flow im Router** angelegt (`AuthRoutes.signIn`, `anonymousSignup`, `restore`, `accountLink`, `deleteAccount`, `onboardingTour`).
- **Tournament-Module** im Router (`list`, `setupWizard`, `registration`, `standings`, `match`, `conflict`, `override`).
- **Match-Modul** für Live-Spiele (`matchConfig`, `lobby`, `result`, `awaitOthers`, `finished`).
- **Social-Features** (Friends, Groups, Inbox).
- **High-Contrast Mode** + Dark Mode bereits als ThemeData-Varianten implementiert.
- **Lokalisierung** über `app_localizations.dart` (DE als Hauptsprache).

---

## 2. Rebrand-Blocker — muss fertig, bevor Kubb Club live geht 🔴

### 2.1 App-Icon Sizes
Die SVG-Logos sind da, aber für iOS/Android werden **rasterized PNGs in diesen Grössen gebraucht**:

| Platform | Größen |
|---|---|
| iOS (Asset Catalog) | 1024, 180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20 |
| Android (mipmap-*dpi*) | 192, 144, 96, 72, 48 — plus **Adaptive Icon**: `ic_launcher_foreground.xml` + `ic_launcher_background.xml` |
| Web (PWA) | 512, 192 + maskable variants |
| Favicon | 16, 32 ICO-multi + apple-touch-icon 180 |

→ Brauchen einen Export-Step (SVG → PNG mit ImageMagick/Sharp). Wir liefern die SVGs als Master.

### 2.2 Launch Screen / Splash
- **iOS**: `LaunchScreen.storyboard` muss neu — bisherige nutzt Flutter-Default. Variante A oder B aus `preview/brand-splash.html` ist Vorlage.
- **Android**: `android/app/src/main/res/drawable/launch_background.xml` aktualisieren auf Meadow-Background + zentriertes K+Crown.
- **Web**: `web/index.html` `<body>` Loader auf Meadow + Mark.

### 2.3 In-App Text-Strings
Im Codebase suchen nach `'Brosi'`, `"Brosi's Kubb"`, App-Title → ersetzen durch `'Kubb Club'`. Hauptstellen:
- `lib/l10n/app_de.arb` (und ggf. `app_en.arb`)
- `pubspec.yaml` → `name: kubb_club` (Package-Rename ist invasiv, optional)
- `android/app/src/main/AndroidManifest.xml` → `android:label`
- `ios/Runner/Info.plist` → `CFBundleDisplayName`
- `web/manifest.json` → `name`, `short_name`

### 2.4 Onboarding-Tour Screens
Router referenziert `AuthRoutes.onboardingTour` aber im Design-Kit fehlen die Visuals. **Vorschlag**: 3–4 Slides mit dem K+Crown als Vignette + ein Satz pro Slide:
1. "Sniper-Training für deine Wurf-Konstanz." (8m Mode erklärt)
2. "Finisseur — das Match-Endspiel üben." (Finisseur erklärt)
3. "Turniere & Ligen, online verfolgt." (Tournament-Modul)
4. "Mit Freunden & Clubs trainieren." (Social-Modul)

---

## 3. Was fehlt visuell — high impact 🟡

Diese Screens **gibt es im Router**, aber **keine Vorlage** in `docs/design/ui_kits/app/`. Sind UX-kritisch:

| Screen | Route | Warum wichtig |
|---|---|---|
| **Sign-In Hub** | `/sign-in` | Erste Berührung — schlechter Eindruck wenn lieblos |
| **Anonymous Signup** | `/sign-in/anonymous` | Conversion-kritisch (niedrige Hürde) |
| **Restore (Mnemonic)** | `/sign-in/restore` | BIP39-Flow — braucht klares Visual |
| **Account Link** | `/sign-in/link` | Anonym → Email upgrade |
| **Edit Profile** | `/profile/edit` | Avatar, Display Name |
| **Inbox** | `/inbox` | Match-Invites, Tournament-Erinnerungen |
| **Friends List** | `/social/friends` | Add by handle, request states |
| **Groups / Clubs** | `/social/groups` | Mitglieder, Rangliste |
| **Match Config / Lobby / Result / Await / Finished** | `/match/*` | Komplettes Live-Match-Flow |
| **Tournament List / Detail / Standings / Bracket** | `/tournament/*` | Saison-Übersicht |
| **Tournament Match Conflict / Override** | `/tournament/.../conflict` | Score-Disput-UI |

→ Wir empfehlen, **mind. die Auth- + Match-Screens** im UI-Kit nachzuziehen, bevor die App ausgerollt wird.

## 4. UX & System-Lücken die wir empfehlen 🟢

### 4.1 Tablet / Desktop Layout
Die App ist Flutter — kann iPad/Tablet/Web liefern. Die bisherigen Designs sind aber **nur Phone-Layouts** (390×844). Empfehlung: **Master/Detail-Pattern auf Tablet**:
- Linke Spalte (340 dp): Navigation + Session-Liste
- Rechte Spalte (flex): Detail-View

Das **Desktop UI Kit in diesem Projekt** (`ui_kits/desktop/`) baut genau das nach — kann als Referenz für Flutter dienen.

### 4.2 Empty States
Aktuelle Designs zeigen immer befüllte Listen. Es fehlt:
- "Noch keine Sessions" auf Home (Erst-Nutzer)
- "Keine Freunde" auf Friends
- "Keine Turniere" auf Tournament List
- "Inbox leer"
- "Keine Statistiken — spiel 5 Sessions"

→ Jede leere Liste sollte einen **kleinen K+Crown vignette + ein Satz Action-CTA** haben.

### 4.3 Loading / Skeleton States
Die Splash deckt nur den Boot ab. Innerhalb der App passiert beim Routenwechsel oder Datenladen ein leerer Frame. **Vorschlag**: Skeleton-Cards für:
- Session-Liste (Recent Rows mit grauen Bars)
- Stats Charts (graue Wellen)
- Tournament Standings (graue Tabellenzeilen)

### 4.4 Offline / Connection State
Die App nutzt Supabase + drift (lokal). Wenn das Netz weg ist:
- **Top-Bar Status-Pille**: "Offline · letzte Sync 2 min" (klein, gelb)
- Sessions weiterhin lokal speicherbar
- Sync-Indikator wenn wieder online

### 4.5 Notifications & Match-Invites
Wenn jemand zum Match einlädt — wie sieht das aus?
- Push Notification copy (DE): "Marc will mit dir spielen. ✋"
- In-App Banner top
- Inbox-Liste-Item (Avatar + "Match-Einladung · Sniper · vor 5 min")

### 4.6 Achievements / Badges
Im `AppSettingsModal.jsx` ist `onOpenAchievements` schon verdrahtet, aber kein Screen.
**Vorschlag**: 12–15 Badges, alle mit eigenem hölzernen Glyph + Gold-Akzent:
- 100 Hits · 1000 Hits · Erster Strafkubb · 10× Streak · Heli-Master · Konstanz-King · Saisonteilnehmer · Top 100 ELO · ...

### 4.7 Share / Match-Link
Tournament & Match haben `share_plus`-Dependency in `pubspec.yaml` — aber kein UI dazu. **Vorschlag**: Share-Sheet-Trigger im AppBar-Right-Slot mit:
- Pre-rendered "Match-Karte" als PNG (Mark + Score + "Du wurdest eingeladen")

### 4.8 Heli-Toggle UX
Heli-Tracking ist Opt-In über Settings. Aber der Toggle-Path ist 3 Screens tief. **Vorschlag**: Wenn ein User zum 3. Mal "Hit" tappt während ein Wind-Heli passieren würde, ein subtiler Hint-Banner: "Helikopter-Würfe tracken? → Settings".

---

## 5. Tech-/Code-Anmerkungen die wir während des Audits gesehen haben 🔵

- `lib/core/ui/icons.dart` nutzt `lucide_icons: ^0.257.0` und mapt Marken-Glyphs auf Lucide-Substitutes (`heli → wind`, `king → crown`, `cup → trophy`). Kommentar im File sagt: "*CustomPainter implementation of the Brosi design glyphs is a future task*" — d.h. die **Heli/King/Cup-Icons sind nur Stellvertreter**. Für eine polierte App lohnt sich der CustomPainter-Pass mit den hölzernen Brand-Glyphen (Krone aus dem Logo etc.).
- `--dart-define=SUPABASE_URL` + `SUPABASE_ANON_KEY` sind hardcoded-at-build. Für Release-Stage / Staging / Prod **drei Flavors** anlegen.
- Keine Sentry/Crashlytics-Integration ersichtlich. Erste Release will man Crashes sehen.
- `pubspec.yaml` nutzt `google_fonts: ^8.1.0` für Bricolage. **Für offline-fähige App** den Font lokal bundeln (kostet ~250 KB, spart erste-Start Netzlatenz).
- `freezed` + `riverpod_generator` + `drift_dev` sind aktiv — Code-Gen-Step (`dart run build_runner build`) ist nicht in CI dokumentiert. Vor Release sicherstellen.

---

## 6. Empfehlung: Reihenfolge fürs nächste Sprint

1. **App-Icon-Export-Pipeline** (SVG → PNG aller Grössen) — blockiert TestFlight + Play Console Submission.
2. **Sign-In + Anonymous Signup Screens** designen — erster App-Eindruck.
3. **Launch Screen** in iOS/Android/Web einbinden.
4. **Brand-Strings** in `app_de.arb` ersetzen.
5. **Onboarding-Tour** (3–4 Slides) designen.
6. **Match-Flow** (Lobby → Live → Result) designen — Hauptfeature.
7. **Tablet/Desktop-Layout** für die Top-3-Screens (Home, Stats, Match).
8. Custom Brand-Glyphen (Heli, King, Cup, Crown) als CustomPainter.
9. Achievements-Screen + Badge-Inventar.
10. Empty / Loading / Offline States systematisch.

Punkt 1–5 = Rebrand-MVP. Punkt 6–10 = "Make it shine".
