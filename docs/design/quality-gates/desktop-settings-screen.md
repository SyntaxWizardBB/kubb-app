# Quality-Gate: Settings (Desktop)

**Quelle**: `docs/design/ui_kits/desktop/SettingsScreen.jsx`
**Flutter-Pendant**: Settings als Phone-Screen (`lib/features/settings/`) — Desktop-3-Spalten-Layout FEHLT
**Tablet/Desktop-Breakpoints**: ab 900 dp mindestens Two-Column (Nav + Content), ab 1280 dp Three-Column mit Right-Aside
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (3 Spalten)
- TopBar: Eyebrow `Menue · Einstellungen`, Title `Einstellungen`, Subtitle, Buttons `CSV-Export…` + `Schnell-Einstellungen…`.
- Body Split (`grid-template-columns: 260px 1fr 300px`, gap 18, `padding: 24px 32px 32px`):
  - **LEFT** (Aside-Nav, 260 dp):
    - User-Card (Avatar 40 dp Meadow-600 + Name + Sub + Profil-Btn).
    - Nav-List (7 Sektionen: Konto / App-Einstellungen / Spielregeln / Benachrichtigungen / Daten & Export / Integrationen / Ueber):
      - Active-State: `--kc-bg-sunken` BG + `--kc-fg` Color + inset 2 px Meadow-500 left-Border + Active-Dot rechts.
  - **CENTER** (Main, Card padding 26):
    - Section-Head (Eyebrow + Title 30 px display) mit Bottom-Border.
    - Section-Content je Sektion:
      - **AccountSection**: 5 SettingRows.
      - **AppSection**: 3 RowSeg (Sprache / Distanz-Einheit / Theme) + 3 RowToggle (Vibration / Auto-Speichern / Grosse Outdoor-Schrift).
      - **PlaySection**: 3 RowSeg (Format / Stöcke / Strafkubb-Regel) + 1 RowToggle (Helikopter-Tracking) + 2 RowStatic (Koenig-Mass / Pitch-Mass).
      - **NotifSection**: 4 RowToggle.
      - **DataSection**: 4 RowAction.
      - **IntegrationsSection**: 4 Rows mit ToggleSwitch (Kubbtour, Apple Health, Strava, Discord).
      - **AboutSection**: About-Hero + 4 RowAction.
  - **RIGHT** (Aside, 300 dp):
    - Quickzugriff-Card mit 5 Quick-Buttons (Stat / Inbox / Profile / Cup / Reset-danger).
    - Status-Card mit 4 Status-Rows (Speicher / Sync / Backup / Version).
    - Footer-Text (klein, muted, zentriert).

### Modals
- **AppSettingsModal** (siehe eigener Quality-Gate): Schnell-Einstellungen, oeffnet via TopBar oder Right-Quickzugriff.
- **CsvExportModal** (siehe eigener Quality-Gate): CSV-Export, oeffnet via TopBar oder DataSection.
- **ResetModal**: Two-Step Reset-Confirm (`warn` step mit Type-`ZURUECKSETZEN` Check, dann `done` step mit Check-Icon).

### Farben
- Sidebar-Aside Stone-Neutral.
- Nav-Active: Bg-Sunken + inset Meadow-500.
- Nav-Dot: Meadow-500.
- Switch-On: Meadow-500. Switch-Off: Stone-200.
- Quick-Reset-Danger-Color: Miss.
- Status-Ok-Tone: Meadow-700.
- Reset-Modal warn-text: Fg-Muted.
- Done-Icon: Meadow-500 BG, weiss Check.
- Danger-Btn: Miss BG, weiss.

### Typografie
- Section-Title 30 px display weight 700.
- RowLbl 14 px ui weight 700. RowSub 12 px muted.
- Modal-Title 22 px display.

### Spacing
- Body-Split-Gap 18.
- Card-Padding 26 (Center), 18 (Aside-Cards).
- Row-Padding `16px 0` mit Top-Border.
- Section-Head Padding-Bottom 14 mit Border-Bottom.

### Border-Radius
- Cards 16. Nav-Items 10. RowAction-Buttons 8. Switch 999. Modal 18.

### Shadows
- User-Card `--kc-shadow-1`. Cards Default `--kc-shadow-1`. Modal `--kc-shadow-3`.

### Icons
- Sidebar-Nav-Icons aus `DIcon`: Profile, Gear, Target, Bell, Inbox, Users, Chevron.
- Quick-Icons: Stat, Inbox, Profile, Cup, Undo.

## Komponenten-Inventar

- Shared: `TopBar`, `PrimaryBtn`, `SecondaryBtn`, `Card`, `DIcon`, `AppSettingsModal`, `CsvExportModal`.
- Lokal:
  - `AccountSection`, `AppSection`, `PlaySection`, `NotifSection`, `DataSection`, `IntegrationsSection`, `AboutSection`.
  - `SettingRow`, `RowSeg`, `RowToggle`, `RowStatic`, `RowAction` — Row-Primitives.
  - `ToggleSwitch` (controlled oder uncontrolled).
  - `Status` (label + value + optional tone + mono).
  - `ResetModal` (Step-Machine warn → done).

**Unterschied Mobile**: Phone-Settings ist eine flache Liste oder Drawer. Desktop hat 3 Spalten + nested Sektionen + dedizierte Quick-Actions-Aside. Wesentlich reicher visualisiert.

**Flutter-Aequivalente**:
- Nav-List → eigenes Widget `KCSettingsNav` mit `NavigationRail`-Style.
- ToggleSwitch → Material `Switch` mit Theme-Override.
- RowSeg → `SegmentedButton`.
- ResetModal → `showDialog` mit Step-State (`StatefulBuilder`).

## Interaktions-Pattern

- **Section-Switch**: lokaler `section`-State, wechselt Center-Card-Content.
- **TopBar-Btns**: oeffnen Modals (App-Settings, CSV-Export).
- **Quick-Btn-Reset**: oeffnet ResetModal.
- **Quick-Btn-Stats/Profile/Inbox**: `onRoute(...)`.
- **Toggles**: lokal, Save-on-Change (kein dedizierter Save-Button).
- **RowAction-Buttons**: Section-spezifisch.
- **ResetModal-Confirm**: User muss `ZURUECKSETZEN` exakt tippen, dann Btn aktiv. Nach Click → Done-Step.
- **Loading**: Sektionen unabhaengig laden — Center-Card mit Skeleton-Rows.
- **Error**: Toast bei Backend-Sync-Fehler.
- **Empty**: nie leer.

## Accessibility

- **Tab-Order**: TopBar-Btns → User-Card-Profil-Btn → Nav-Items (vertikal) → Center-Card (Row-Interactions in Reading-Order) → Right-Quick-Buttons → Status (statisch).
- **Focus-Ring**: zwingend auf Nav-Items + Toggles + Action-Buttons.
- **Min-Window-Width**: 1280 dp fuer Three-Column. Bei 900 – 1279 dp: Right-Aside einklappen, Two-Column. Unter 900 dp: Phone-Layout (Drawer + Content).
- **Reset-Modal-Confirm**: Type-To-Confirm-Pattern ist gute UX, aber Screen-Reader sollte den Input mit `aria-label` markieren.
- **Toggle-States**: aria-checked korrekt setzen (Flutter: `Switch.value`).
- **Danger-Tone**: nicht nur Farbe — auch Icon oder Text-Verstaerkung ("loeschen").

## Quality-Gate-Checkliste

- [ ] Three-Column-Split 260 / flex / 300, Gap 18.
- [ ] User-Card mit Avatar 40 dp + Name + Sub + Profil-Btn.
- [ ] Nav-List 7 Sektionen, Active-State mit Bg-Sunken + Inset-Border + Active-Dot.
- [ ] Section-Head mit Section-Title 30 px + Bottom-Border.
- [ ] AccountSection 5 SettingRows (Name / Mail / PW / Anmeldungen / Profil-Loeschen).
- [ ] AppSection mit 3 Seg + 3 Toggle.
- [ ] PlaySection mit 3 Seg + 1 Toggle + 2 Static.
- [ ] NotifSection 4 Toggles.
- [ ] DataSection 4 Action-Rows mit Danger-Tone fuer Reset.
- [ ] IntegrationsSection 4 Rows mit Switch.
- [ ] AboutSection mit Hero-Logo + 4 Action-Rows.
- [ ] Right-Quickzugriff 5 Buttons, Status-Card mit 4 Rows, Footer-Text.
- [ ] ResetModal Two-Step mit Type-To-Confirm.
- [ ] App-Settings-Modal + CSV-Export-Modal oeffnen sich aus TopBar + Quick + DataSection.

## Implementations-Hinweise fuer Flutter

- **State**: `settingsControllerProvider` (existiert in Phone-App). Erweiterung um `activeSection`-State (lokal in Desktop-View).
- **Section-Switch**: einfacher Riverpod-`StateProvider<SettingsSection>` oder lokaler `useState` mit `flutter_hooks` (nicht im Stack — also Riverpod-StateProvider).
- **Layout**: `Row(children: [SizedBox(260), Expanded(content), SizedBox(300)])`. Bei kleineren Breiten: `LayoutBuilder` mit conditional rendering.
- **Nav-List**: `Column` mit `ListTile`-aehnlichen Buttons. Active-Inset-Border via `BoxDecoration`.
- **Forms-Persist**: Toggles speichern direkt via Provider; kein Save-Button noetig. `await ref.read(settingsControllerProvider.notifier).setVibrate(true);`.
- **ResetModal-Type-Confirm**: `TextField` mit `onChanged` der `_canReset = value == 'ZURUECKSETZEN'` setzt. Btn `enabled` Property.
- **Komplexitaet**: **M-L**. 5 – 7 Tage. Hauptaufwand: drei Section-Sub-Screens + ResetModal + Layout-Robustheit bei verschiedenen Breakpoints.
- **Pakete**: keine zwingend neuen.
