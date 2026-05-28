# Quality-Gate: App-Settings-Modal

**Quelle**: docs/design/ui_kits/app/AppSettingsModal.jsx
**Flutter-Pendant**: lib/features/settings/presentation/widgets/app_section.dart (aktuell inline) + Modal-Pendant noch nicht extrahiert
**Stand**: 2026-05-28

## Visual-Spec

- **Layout-Struktur**
  - Bottom-Sheet, das von unten einrastet — Sheet-Hoehe max 92 % der verfuegbaren Frame-Hoehe, scrollbar bei Ueberlauf.
  - Backdrop dunkel (`rgba(12,11,7,0.55)`) ueber den restlichen Frame; Tap auf Backdrop schliesst.
  - Top-Bereich: Grabber-Bar zentriert + Header-Zeile mit Eyebrow ("Menue") + Title ("App-Einstellungen") + Close-Icon-Button rechts.
  - Sektion "App": Row-Liste mit Sprache, Distanz-Einheit, Vibration, Theme — jeweils Label oben, Trailing-Widget (Segmented oder Toggle) darunter.
  - Sektion "Daten": Nav-Rows zu Statistik, Erfolgen, CSV-Export, Userdaten loeschen (danger), Profil loeschen (danger).
  - Footer: zentriert, zweizeilig — Versions-String + Tagline "Fuer die Wiese gebaut.".

- **Farben** (Token-Namen)
  - Sheet-Background: `tokens.bg`.
  - Card-Gruppe (`App` / `Daten`): `tokens.bgRaised` mit 14 px Radius, 16 px horizontaler Aussenrand.
  - Segmented-Control-Track: `tokens.bgSunken`; aktiver Segment: `tokens.lineStrong` mit `chalk50` Textfarbe.
  - Toggle-On: `KubbTokens.meadow500`; Toggle-Off-Track: `tokens.line` (Stone 200).
  - Toggle-Knob: weiss mit dezentem `0 1px 3px rgba(0,0,0,0.2)`-Schatten.
  - Backdrop: `rgba(12,11,7,0.55)` (Stone-900 mit Alpha; entspricht `tokens.bgSunken`-Dark-Aequivalent).
  - Grabber: `tokens.line` (Stone 200), Radius `radiusPill`.
  - Danger-Nav-Row: `tokens.danger` fuer Icon + Label.

- **Typografie**
  - Title: Display-Font, 24 px, FontWeight 800, letterSpacing -0.02em.
  - Eyebrow: 11 px / 600 / uppercase / 0.08em.
  - Row-Label (Form-Row): 11 px / 600 / uppercase / 0.08em — als Caption ueber dem Control.
  - Nav-Row-Label: Display-Font, 15 px, FontWeight 600.
  - Nav-Row-Subtitle: 12 px, `fgMuted`.
  - Segment-Button: Display-Font, 13 px, FontWeight 600.
  - Footer: 11 px, `fgMuted`.

- **Spacing** (KubbTokens)
  - Sheet-Padding: 10 px oben / 40 px unten / horizontal innerhalb Gruppen 18 px.
  - Header-Padding: 4 px oben / 12 px unten / 18 px seitlich.
  - Section-Header: 8 px oben / 6 px unten / 18 px seitlich.
  - Gruppen-Aussenrand: `space4` (16 px) horizontal, 6 px Abstand zur naechsten Gruppe.
  - Form-Row-Padding intern: 10 px oben/unten — entspricht ungefaehr `space2`+`space1`.
  - Nav-Row-Padding intern: 12 px oben/unten, Mindesthoehe 60 dp.

- **Border-Radius**
  - Sheet-Top-Corners: 24 px (zwischen `radiusXl` 16 und Custom 24 — pragmatisch `BorderRadius.vertical(top: Radius.circular(24))`).
  - Gruppen-Card: 14 px.
  - Icon-Wrapper: 10 px (`radiusMd`).
  - Segmented-Track: `radiusPill`.
  - Toggle: `radiusPill`.
  - Close-Icon-Button: 12 px (`radiusLg`).
  - Grabber: `radiusPill`.

- **Shadows**
  - Keine harten Schatten auf der Sheet selbst — Trennung vom Backdrop wird ueber das `bg`-vs-Backdrop-Kontrast erreicht.
  - Toggle-Knob: leichter Drop-Shadow `0 1px 3px rgba(0,0,0,0.2)`.

- **Icons** (Lucide-Set)
  - Close: `LucideIcons.x` (Design: `Icon.Close`).
  - Nav-Rows verwenden dieselben Icons wie der Settings-Screen (siehe `settings-screen.md`).

## Komponenten-Inventar

- `showModalBottomSheet` mit `isScrollControlled: true` und `backgroundColor: Colors.transparent` — Standard-Flutter-Sheet-Pattern (siehe `CsvExportModal.show`).
- Grabber-Widget — 36 dp x 4 dp Pill, zentriert.
- Header-Zeile mit Eyebrow + Title + Close-Button.
- Section-Header-Text (uppercase Caption).
- Card-Gruppe (`bgRaised`, 14 px Radius, internes Padding).
- `Row`-Widget (Form-Row): Label oben + Trailing-Control darunter, Border-Bottom als Trenner.
- `NavRow`-Widget: Icon + Label + Subtitle + Chevron, optional `tone="danger"`.
- `Seg`-Widget (Segmented-Control): Pill-Container mit `flex:1`-Buttons; aktiver State = `lineStrong` Background.
- `Toggle`-Widget: Pill 48 x 28 dp mit animiertem Knob; entspricht Material `Switch`.
- Footer-Block: zwei zentrierte 11 px Texte uebereinander.

## Interaktions-Pattern

- **Open**: `showModalBottomSheet` slidet von unten ein (Material-Default-Curve ~250 ms ease-out).
- **Close**:
  - Tap auf Backdrop -> `Navigator.of(context).pop()` (entspricht `onClose` im JSX).
  - Tap auf Close-Icon -> `Navigator.pop`.
  - Swipe-down auf Grabber/Sheet -> Standard `enableDrag: true` reicht aus.
  - System-Back -> popt das Modal, nicht den Parent-Screen.
- **Settings-Row-Pattern**
  - Form-Row mit `Seg` (Sprache, Theme, Distanz-Einheit) -> direkte State-Mutation via `notifier.setX(...)`.
  - Form-Row mit `Toggle` (Vibration, Heli-Tracking) -> Switch toggelt sofort, keine Confirm-Stufe.
  - Nav-Row mit Chevron -> oeffnet Sub-Screen oder ein weiteres Modal.
  - Danger-Nav-Row (`Userdaten loeschen`, `Profil loeschen`) -> Confirm-Dialog vor Aktion, niemals Direkt-Loesch.
- **Loading/Error-States**
  - `appSettingsProvider.when(loading, error, data)` haendelt die drei Faelle; im Modal-Body wird `CircularProgressIndicator` zentriert.
  - Error-State: Text in `tokens.danger`, kein Close-Trigger automatisch.
- **Confirm-Dialogs**
  - `Userdaten loeschen` und `Profil loeschen` rufen `showDangerConfirm(...)` mit explizitem zweistufigem Bestaetigen.
  - Snackbar nach Erfolg ueber den parent `ScaffoldMessenger` (Modal popt sich vorher selbst).

## Accessibility

- Tap-Targets
  - Close-Icon-Button: 48 dp x 48 dp.
  - Toggle: 48 dp Breite x 28 dp Hoehe — die Hitbox sollte auf >= 48 dp vergroessert werden (Material Switch macht das per Default).
  - Segmented-Buttons: minHeight 34 dp -> aktuell unter dem 48-dp-Floor. Quality-Gate-Warnung: in Flutter-Implementation auf 44+ dp aufstocken oder Padding aufweiten.
- Modal-Dismissibility
  - `barrierDismissible: true` und Grabber-Drag muessen beide funktionieren.
  - Close-Icon sichtbar im Header, kein "verstecktes" Dismissal noetig.
- **Keyboard-Verhalten (Maengel #2.4!)**
  - Falls Sub-Forms (z.B. Profil-Name-Edit oder Distanz-Wert-Input) ins Modal kommen: `padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)` ist Pflicht.
  - Sheet muss `isScrollControlled: true` haben, sonst clipping bei aufpoppender Tastatur.
  - Body in `SingleChildScrollView` oder `ListView` wrappen, damit der Sheet-Content beim Keyboard-Open scrollbar bleibt.
  - Aktuell hat dieses Modal keine Free-Text-Inputs — wenn welche dazukommen, muss der Keyboard-Overflow-Check erneut erfolgen.
- Fokus-Reihenfolge: Header -> Sektion App -> Sektion Daten -> Footer. Screen-Reader liest Section-Header als Caption.

## Quality-Gate-Checkliste

- [ ] Layout-Struktur 1:1 zum Design (Grabber -> Header -> App-Section -> Daten-Section -> Footer).
- [ ] Sheet-Radius 24 px oben, scharfe Kante unten.
- [ ] Alle Farben und Spacings aus `KubbTokens`.
- [ ] Backdrop semitransparent (~ 55 % Alpha auf Stone 900).
- [ ] Modal mit Keyboard scrollable (`viewInsets.bottom`-Padding + `isScrollControlled: true`) — siehe Maengel #2.4.
- [ ] Touch-Targets >= 48 dp (Close-Button, Toggle-Hitbox, Segmented-Buttons).
- [ ] Toggle-Animation 120 ms ease (entspricht Material `Switch`).
- [ ] Danger-Nav-Rows fuehren immer in einen Confirm-Dialog.
- [ ] Privacy-Block (sofern im Modal) zeigt aktuellen, ehrlichen Privacy-Text — kein Stub.
- [ ] i18n via `AppLocalizations` (settingsLanguage, settingsTheme, settingsVibration, settingsHeli, settingsAllowContinue, etc.).
- [ ] Footer-Tagline und Versions-String aus `package_info_plus`.

## Bekannte Abweichungen (Flutter aktuell vs. Design)

- **Modal-Pattern noch nicht extrahiert**. Aktuell lebt der App-Settings-Inhalt als `SettingsAppBlock` direkt im Settings-Screen. Ein dediziertes `AppSettingsModal`-Widget (das `showModalBottomSheet` triggert) existiert nicht. Quality-Gate-Empfehlung: nur extrahieren, wenn das Modal von einer zweiten Stelle (z.B. Home-Hamburger) aufgerufen werden soll. Solange Settings-Screen die einzige Quelle ist, bleibt der Inline-Pfad korrekt.
- **Segmented-Buttons fuer Sprache/Distanz fehlen**. Aktuell ist Sprache nur als statischer `Text` und Distanz-Einheit gar nicht implementiert. Quality-Gate-Backlog: ein `SegmentedButton<Locale>` mit `de-CH`, `de-DE`, `en`-Optionen sobald i18n-Phase-1+ aktiv ist.
- **Theme-Segmented-Button**. Aktuell `SegmentedButton<ThemeChoice>` mit `light/dark/highContrast`. Design nennt `hell/dunkel/auto` — `auto` mappt nicht 1:1 auf `highContrast`. Owner-Klarstellung noetig: ist Theme `auto` ein eigener Mode (folgt System) oder bleibt es bei der dreigeteilten Variante.
- **Profil-Loeschen-Row fehlt**. Design listet `Profil loeschen` als zweite Danger-Row. Sprint-C-Compliance-Block.
- **Vibration-Toggle** ist im Flutter-Code vorhanden — entspricht Design.
- **Heli-/Long-Dubbie-/Penalty-/Kingthrow-Toggles** sind im Flutter-Code zusaetzlich (Finisseur-Sektion). Design erwaehnt sie unter "App" nicht — die Erweiterung ist sinnvoll und mit eigenem Section-Header sichtbar getrennt.
- **Privacy-Block am Modal-Footer**. Aktuell zeigt der Flutter-Code `settingsPrivacyHeader` + `settingsPrivacyBody`. Sprint-C hat den "Privacy-Luege"-Eintrag offen — der Text muss faktisch korrekt sein, sonst Compliance-Risk.
