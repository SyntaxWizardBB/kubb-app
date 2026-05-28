# Quality-Gate: Settings-Screen

**Quelle**: docs/design/ui_kits/app/SettingsScreen.jsx
**Flutter-Pendant**: lib/features/settings/presentation/settings_screen.dart
**Stand**: 2026-05-28

## Visual-Spec

- **Layout-Struktur**
  - Scrollender Single-Column-Screen, kein Tab-Strip.
  - Vertikale Folge: AppBar (mit Back-Button) → Profile-Block (Avatar + Name + Meta) → Gruppen-Card mit Statistik/Profil/App-Einstellungen → Section-Header "Daten" → Gruppen-Card mit Erfolgen/CSV-Export/Sessions-Reset → Footer mit Version und Tagline.
  - Gruppen sind als "Inset-Card" gestaltet: 16 px horizontaler Aussenrand, 14 px Border-Radius, `bgRaised` als Fläche, `overflow: hidden` damit die Row-Borders innen sauber abschneiden.
  - Rows innerhalb einer Gruppe sind durch eine `1 px`-Linie (`tokens.line`) getrennt; letzte Row hat keinen Trenner.
  - Screen-Padding unten: 32 px (`space8`), damit die letzte Row nicht am Bottom klebt.

- **Farben** (Token-Namen)
  - Background: `tokens.bg` (Chalk 50 light / Stone 900 dark).
  - Card-Flaeche: `tokens.bgRaised`.
  - Icon-Wrapper-Fill: `tokens.bgSunken`.
  - Avatar-Fill: `KubbTokens.meadow600` (light) bzw. dark-Aequivalent.
  - Avatar-Text: `tokens.onPrimary`.
  - Row-Label: `tokens.fg`; im `danger`-Modus `tokens.danger`.
  - Row-Subtitle und Chevron: `tokens.fgMuted`.
  - Trenn-Linie: `tokens.line`.
  - Section-Header (z.B. "DATEN"): `tokens.fgMuted`, uppercase.

- **Typografie**
  - Profile-Name: Display-Font, 18 px, FontWeight 700, letterSpacing -0.01em.
  - Profile-Meta: 12 px, `fgMuted`.
  - Section-Header: 11 px, FontWeight 600, letterSpacing 0.08em, uppercase.
  - Row-Label: Display-Font, 16 px, FontWeight 600.
  - Row-Subtitle: 12 px, `fgMuted`.
  - Footer: 12 px, `fgMuted`, lineHeight 1.6.

- **Spacing** (KubbTokens)
  - Card-Aussenrand horizontal: `space4` (16 px).
  - Row-Padding: 14 px vertikal x 16 px horizontal — entspricht `space3` x `space4`.
  - Row-Icon-zu-Text-Gap: 14 px (~`space3`).
  - Section-Header-Padding: 14 px oben / 8 px unten / 18 px seitlich.
  - Profile-Block-Padding: 10 px oben / 18 px unten / 18 px seitlich.
  - Footer-Padding: 24 px oben.
  - Screen-Padding unten: `space8`.

- **Border-Radius**
  - Gruppen-Card: 14 px (zwischen `radiusLg` 12 und `radiusXl` 16 — pragmatisch via `BorderRadius.circular(14)` oder `radiusLg`-Anlehnung).
  - Icon-Wrapper: 10 px (~`radiusMd`).
  - Avatar: voller Kreis (`radiusPill` / `BorderRadius.circular(28)`).

- **Shadows**
  - Keine. Settings-Screen ist Shadow-frei; Trennung wird ueber Background-Kontrast und Inset-Cards erreicht.

- **Icons** (Lucide-Set)
  - Statistik: `LucideIcons.barChart3` (Design: `Icon.Stat`).
  - Profil: `LucideIcons.user` / passendes Profile-Glyph (Design: `Icon.Profile`).
  - App-Einstellungen: `LucideIcons.settings` (Design: `Icon.Gear`).
  - Erfolge: `LucideIcons.trophy` (Design: `Icon.Trophy`).
  - CSV-Export: `LucideIcons.download` (Design: `Icon.Download`).
  - Sessions-Reset / Trash: `LucideIcons.eraser` (aktuell verwendet) oder `LucideIcons.trash2` (Design: `Icon.Trash`).
  - Chevron: `LucideIcons.chevronRight`.

## Komponenten-Inventar

- `KubbAppBar` (aus `lib/core/ui/widgets/kubb_app_bar.dart`) — Eyebrow "Menue" + Title "Einstellungen" + Back-Button. Single Source of Truth fuer Header-Pattern (Pendant zu `AppBar` in `shared.jsx`).
- Profile-Block — Avatar-Kreis 56 dp + Name/Meta-Spalte. Aktuell als `AccountSection` realisiert.
- `SettingsSection` — Wrapper, der Section-Header und die Card-Gruppe kombiniert.
- `SettingsRow` — Reusable Row mit Icon-Wrapper, Label, Subtitle, Chevron, optionalem `danger`-Tone.
- `SettingsAppBlock` — eingebettetes App-Settings-Sub-Widget (Sprache, Theme, Switches, Privacy-Block, Version-Row). Sieht im Design wie eine separate Modal-Sheet aus (`AppSettingsModal.jsx`), wurde aber inline in den Screen integriert.
- Footer-Block — zentrierte Version-/Tagline-Anzeige (im Code: `Center(Text(...))` mit `_VersionRow` aus `app_section.dart`).

## Interaktions-Pattern

- **Row-Tap**: `InkWell`-Splash, navigiert via `context.push('/<route>')` oder oeffnet ein Modal (`CsvExportModal.show`).
- **Danger-Row**: `tokens.danger` faerbt Icon und Label rot. Tap oeffnet immer einen Confirm-Dialog (`showDangerConfirm`), kein Direkt-Trigger.
- **Confirm-Dialog**: Standard-Material-`AlertDialog` mit zweistufigem Bestaetigen — verhindert versehentliches Loeschen von Sessions.
- **Loading/Error-States**
  - `AccountSection` und `SettingsAppBlock` zeigen `CircularProgressIndicator` waehrend Settings-Load.
  - Error-State zeigt Fehlermeldung in `tokens.danger`.
- **Snackbar nach Reset**: nach erfolgreichem `resetSessions()` wird `l.settingsResetDoneSnack` als `SnackBar` angezeigt.

## Accessibility

- Tap-Targets: jede Row hat `minHeight: 64` (Design) bzw. effektives Padding, das die `touchMin: 48` aus `KubbTokens` ueberschreitet.
- Icon-Wrapper sind 36 dp gross, aber die gesamte Row ist tappbar (kein 36-dp-Hitbox-Problem).
- Back-Button: `tooltip: MaterialLocalizations.of(context).backButtonTooltip` (siehe `KubbAppBar`).
- Danger-Row: Farbe allein ist kein einziger Informationstraeger — Confirm-Dialog liefert den expliziten Hinweis.
- Screen ist scrollbar (`ListView`), damit auch bei kleinerer Display-Hoehe alle Rows erreichbar bleiben.

## Quality-Gate-Checkliste

- [ ] Layout-Struktur 1:1 zum Design (AppBar -> Profile -> Gruppe -> Daten-Section -> Footer).
- [ ] Inset-Card-Pattern: 16 px Aussenrand, 14 px Radius, `bgRaised` Flaeche, ueberlappende Borders abgeschnitten.
- [ ] Alle Farben aus `KubbTokens` — keine Hardcodes.
- [ ] Section-Header-Typo: 11 px / 600 / 0.08em / uppercase.
- [ ] Row-Icon im 36 dp Square mit `bgSunken` + `radiusMd`.
- [ ] Touch-Targets >= 48 dp (Row-Hoehe >= 60 dp).
- [ ] Lucide-Icons matchen Design-Inventar.
- [ ] Danger-Row hat Confirm-Dialog vor Aktion.
- [ ] i18n via `AppLocalizations` (settingsScreenEyebrow, settingsTitle, settingsRow*, settingsFooterTagline, etc.).
- [ ] Footer-Tagline `l.settingsFooterTagline` zentriert.
- [ ] Version-Row laedt via `package_info_plus` und faellt auf "—" zurueck, wenn Channel nicht verfuegbar.

## Bekannte Abweichungen (Flutter aktuell vs. Design)

- **App-Einstellungen sind inline statt Modal**. Das Design (`AppSettingsModal.jsx`) zeigt App-Settings als Bottom-Sheet, die aktuelle Flutter-Implementation rendert `SettingsAppBlock` inline im Settings-Screen. Quality-Gate-Entscheidung: bleibt vorerst inline, weil eine Sub-Modal-Hierarchie (Settings -> App-Settings-Modal) den Navigation-Stack ueberlaedt. Modal-Pattern ist trotzdem als eigenes Quality-Gate dokumentiert (`app-settings-modal.md`).
- **Erfolge-Row fehlt**. Das Design listet "Erfolge" als zweite Daten-Row. Aktuell ist keine `/achievements`-Route verdrahtet. To-Do im Backlog.
- **Profile-Row als separater Eintrag fehlt**. Das Design hat eine "Profil"-Row in der ersten Gruppe. Aktuell wird das Profil ueber `AccountSection` direkt im Block oben angezeigt — die Sub-Navigation zu einem dedizierten Profil-Screen ist nicht im Settings-Stack verdrahtet (Profile-Screen existiert separat).
- **Section-Header-Reihenfolge weicht ab**. Aktuell: AccountSection -> "Daten" -> "App". Design: Profile-Block -> Gruppe (Stats/Profil/App) -> "Daten"-Header -> Gruppe (Erfolge/Export/Reset). Eine Reorder-Pass-Task ist sinnvoll, wenn das Achievements-Feature wieder aufgenommen wird.
- **Sessions-Reset-Icon weicht ab**. Design nennt `Icon.Trash`, aktuell verwendet wird `LucideIcons.eraser`. Semantisch passend, aber Glyph anders — bei naechstem Polish-Pass auf `LucideIcons.trash2` vereinheitlichen.
