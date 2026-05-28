# Quality-Gate: Profile (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/ProfileScreen.jsx`
**Flutter-Pendant**: Edit-Profile als Phone-Screen (`lib/features/auth/.../edit_profile`) — Desktop-Two-Column-Layout FEHLT
**Tablet/Desktop-Breakpoints**: ab 900 dp Two-Column (360 / flex); ab 1280 dp Body max-width 1280
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (Master/Detail)
- TopBar: Eyebrow `Account · Profil`, Title `Dein Profil`, Subtitle, Buttons `Verwerfen` + `Speichern`.
- Body `padding: 24px 40px 48px`, `max-width: 1280`.
- Split (`grid-template-columns: 360px 1fr`, gap 20):
  - **LEFT** (Aside, 360 dp): drei Cards untereinander
    - **Avatar-Block** (Card padding 22): Ring mit Gradient (Meadow-500 → Wood-500), Avatar 112 dp Meadow-600 mit Initial `M` (display 48 px), unten Name + Sub `Mitglied seit Apr 2024 · 1283 ELO`, Underlined-Btn `Foto aendern`.
    - **Identity-Card**: Eyebrow `Spielerdaten`, Title `Identitaet`. Felder: Anzeigename (Input), Wurfhand (Seg 3 Optionen: links / rechts / beidhaendig), Stamm-Distanz (Seg: 4 m / 8 m / beides).
    - **Verein-Card**: Field Klub (Input), 2 RowStatics (Mitglied seit / Liga-Punkte).
  - **RIGHT** (Main): vier Cards
    - **Anmeldung & Verknuepfungen** — 3 AuthRows: E-Mail (mit Status-Pill `primaer`, Action `aendern`), Google (status `aktiv` wenn verknuepft, Action `verknuepfen` / `trennen`), Apple.
    - **Sicherheit** — 3 SecRows: Passwort (Action `Passwort aendern`), 2FA (Action `Einrichten`), Aktive Sessions (Action `Alle abmelden`, Danger-Tone).
    - **Sichtbarkeit** — 2 × 2 Grid mit 4 `Vis`-Toggle-Items (Trefferquote in Liga / Trainings teilen / ELO oeffentlich / Standort beim Spiel).
    - **Konto · Gefahrenzone** — Note + Ink-Btn `Profil unwiderruflich loeschen`.

### Modals (im Layer)
- **PasswordModal** (480 dp): Felder Aktuelles PW / Neues PW / Bestaetigen, Show-Toggle, Validation-Hints (min 8 Zeichen, matches, differs).
- **EmailModal** (480 dp): Statische aktuelle Email, neue Email-Input, aktuelles PW, Note + 2 Buttons.

### Farben
- Avatar-Ring: `linear-gradient(135deg, --kc-meadow-500, --kc-wood-500)`.
- Avatar-BG: `--kc-meadow-600`.
- Auth-Row-Container: `--kc-bg-sunken`. AuthIcon-Tile: `--kc-bg-raised`.
- Auth-Status-Pill `aktiv`: Meadow-100/700.
- SecRow-Danger-Action: Border + Color Miss.
- VisRow-On: inset Meadow-500. VisBox-On: Meadow-500 BG.
- Modal-Backdrop: `rgba(12,11,7,0.55)`.
- Hint-Error-Color: Miss.

### Typografie
- AvatarName 22 px display. AvatarSub mono 11 px.
- AuthLbl 14 px ui weight 700. AuthVal 12 px muted.
- ModalTitle 24 px display.
- DangerNote 13 px muted line-height 1.5.

### Spacing
- Split-Gap 20.
- Card-Aside-Gap 16, Main-Gap 16.
- Auth-Row Padding `12px 14px`. AuthList-Gap 8.
- Vis-Grid 2 × 2, gap 8.

### Border-Radius
- Avatar-Ring 50%. Avatar 50%. AuthRow 12. AuthIcon-Tile 10. ModalBox 18. Pills 999. Vis-Box 5.

### Shadows
- Modal `--kc-shadow-3`. Cards Default `--kc-shadow-1`.

### Icons
- Brand-Icons (lokal): MailIcon, LockIcon, GoogleIcon (multi-color), AppleIcon (mono).
- Shared: `DIcon.Bell` (2FA), `DIcon.Users` (Sessions), `DIcon.Chevron` (E-Mail aendern Trigger).

## Komponenten-Inventar

- Shared: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `CardHeader`, `DIcon`.
- Lokal:
  - `Field` (label + child).
  - `Seg` (segmented Buttons, generic).
  - `AuthRow` (icon + label + value + optional status + action).
  - `SecRow` (icon + label + sub + action, tone-aware).
  - `Vis` (toggle-Button mit Check-Box-Style).
  - `ModalBackdrop` (Backdrop + zentrierter Container, esc-to-close ueber Backdrop-Click).
  - `EmailModal`, `PasswordModal` (Forms mit Validation).

**Unterschied Mobile**: Phone-Edit-Profile hat vermutlich Stack-Layout (Avatar oben, dann alle Cards untereinander), Modals als Bottom-Sheet. Desktop trennt Identity (Aside) von Account-Security (Main) — klare Two-Pane-Lesart.

**Flutter-Aequivalente**:
- `Seg` → `SegmentedButton<T>` aus Material 3.
- `Vis` → `CheckboxListTile` mit Custom-Tile-Style (alternativ `Card` + `InkWell` + `Checkbox`).
- `Modal` → `showDialog` mit `AlertDialog` oder Custom `Dialog`.
- Brand-Icons → `flutter_svg` + Asset-SVGs.

## Interaktions-Pattern

- **Seg-Switch**: lokaler State im JSX, in Flutter via Riverpod-Form-State.
- **AuthRow-Action**:
  - E-Mail `aendern` → oeffnet EmailModal (Form mit aktuellem PW als Re-Auth, neue Adresse).
  - Provider `verknuepfen` → OAuth-Flow (Supabase-OAuth). `trennen` → Confirm-Dialog.
- **SecRow-Action**:
  - PW aendern → PasswordModal mit 3 Feldern, Validation live.
  - 2FA Einrichten → Backlog (M5+).
  - Alle abmelden → Confirm-Dialog (danger).
- **Vis-Toggle**: lokal, per Save-Action persistiert.
- **Profil loeschen**: Ink-Btn → fuehrt zu vollem Delete-Account-Flow (`AuthRoutes.deleteAccount`).
- **Save**: TopBar-Primary `Speichern`. Form-Submit via reactive_forms (in Phone-App bereits genutzt).
- **Loading**: Card-Skeletons.
- **Error**: Form-Field-Inline-Hints (Miss-Color, mono 12 px).
- **Empty**: nicht relevant — User existiert immer.

## Accessibility

- **Tab-Order**: Top-Buttons → Avatar-Edit → Anzeigename → Wurfhand-Seg → Stamm-Distanz-Seg → Klub-Input → AuthRows (Mail/Google/Apple) → SecRows (PW/2FA/Sessions) → Vis-Items (4) → Delete-Btn.
- **Focus-Ring**: zwingend auf Inputs und Buttons.
- **Min-Window-Width**: 900 dp fuer Two-Column. Darunter Stack.
- **Modals**: Esc-to-close (Pflicht), Focus-Trap im Modal, Close-Button erreichbar.
- **Form-Validation**: Hint-Errors mit `aria-describedby` (Flutter: `Semantics(hint: ...)`) damit Screen-Reader die Fehler liest.
- **Brand-Icons** (Google/Apple): SVG mit `<title>`-Tag fuer Accessibility, in Flutter via `Semantics(label: 'Google')`.

## Quality-Gate-Checkliste

- [ ] Two-Column-Split 360 / flex, Gap 20.
- [ ] Avatar-Block mit Gradient-Ring (Meadow → Wood) + Avatar 112 dp.
- [ ] Identity-Card mit 3 Feldern (Name / Hand / Stamm).
- [ ] Verein-Card mit Klub-Input + 2 statische Rows.
- [ ] AuthRow Status-Pill `primaer` / `aktiv` mit Meadow-100/700 Tone.
- [ ] SecRow Danger-Action mit Border + Color Miss.
- [ ] Vis-Grid 2 × 2 Toggle-Items mit Check-Box-Style.
- [ ] Danger-Zone Card mit Ink-Btn fuer Profil-Loeschen.
- [ ] EmailModal mit 3 Feldern + Validation (regex), Esc-Close, Re-Auth via PW.
- [ ] PasswordModal mit 3 Feldern + Validation (length, match, differ), Show-Toggle.
- [ ] Save/Verwerfen TopBar-Buttons mit Form-State-Wiring.
- [ ] Profile-Delete-Flow nutzt `AuthRoutes.deleteAccount`.

## Implementations-Hinweise fuer Flutter

- **Form-State**: `reactive_forms` (bereits im Stack) reicht. `FormGroup` mit name / club / hand / stamm / vis_*-Controls.
- **OAuth-Flows**: Supabase-OAuth via `supabase_flutter` — `authClient.signInWithOAuth(...)` fuer Google/Apple. Existiert bereits in Phone-App.
- **Modals als Dialogs**: `showDialog<bool>(...)` mit Future-Result, Form-Confirm-Pattern.
- **Avatar-Ring**: `Container` mit `BoxDecoration(gradient: LinearGradient, shape: BoxShape.circle)`, padding 5, child = Avatar-Container.
- **Brand-Icons**: SVG-Assets unter `assets/icons/google.svg`, `apple.svg`. Verschieben aus Mobile-Kit falls dort schon vorhanden.
- **State**: `userProfileProvider` (existiert), `updateProfileController` (existiert in Phone-App).
- **Komplexitaet**: **M**. 3 – 5 Tage. Hauptaufwand: zwei Modals + Vis-Toggle-Grid + Layout. Logic ist bereits in Phone-App.
- **Pakete**: keine neuen. `reactive_forms` + `flutter_svg` reichen.
