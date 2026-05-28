# Quality-Gate: Profile Screen

**Quelle**: `docs/design/ui_kits/app/ProfileScreen.jsx`
**Flutter-Pendant (Read-View)**: `lib/features/player/presentation/profile_screen.dart`
**Flutter-Pendant (Edit-View)**: `lib/features/auth/presentation/edit_profile_screen.dart`
**Stand**: 2026-05-28

## Visual-Spec

### Layout-Struktur (top-down)

Der JSX-Screen ist ein **Edit-Profile-Screen mit voller Datenpflege** (Name, Email, Provider, Klubdaten, Sicherheit). Er kombiniert die zwei Flutter-Screens (`ProfileScreen` read-only und `EditProfileScreen`) zu einer Single-Page-Editing-Surface.

1. **AppBar** (shared `AppBar`) — Eyebrow `"Account"`, Title `"Profil"`, Back-Button links, kein Right-Slot.
2. **Avatar-Block** — flex column zentriert, padding `10px 0 18px`, gap 8.
   - **Avatar-Ring**: padding 4, `borderRadius: 50%`, `background: linear-gradient(135deg, var(--bk-meadow-500), var(--bk-wood-500))`.
   - **Avatar-Circle**: 88x88, `borderRadius: 50%`, `background: var(--bk-meadow-600)`, `color: var(--bk-on-primary)`, Initial-Buchstabe Display 36px weight 800.
   - **Avatar-Edit-Button**: text-only, `color: var(--bk-meadow-600)`, Display 13px weight 600, underline mit `textUnderlineOffset: 3`, Label `"Foto aendern"`.
3. **Section "Spielerdaten"** — Section-Header padding `14px 18px 8px`. Group-Container `background: var(--bk-bg-raised)`, `borderRadius: 14`, margin `0 16px`, padding `4px 14px`.
   - **Field "Anzeigename"**: Row `flex-column gap: 6, padding: 10px 0, borderBottom: 1px solid var(--bk-line)`. Label 11px caps muted + Input (minHeight 44, `borderRadius: 10`, `border: 1.5px solid var(--bk-line-strong)`, Body 15px).
   - **Field "Wurfhand"**: Label + Segmented-Control `["links", "rechts", "beidhaendig"]`. Seg-Style: `background: var(--bk-bg-sunken)`, `borderRadius: 999`, padding 3. Buttons `flex: 1, minHeight: 36, borderRadius: 999`, Display 13 weight 600. Aktiv: `background: var(--bk-stone-900)`, `color: var(--bk-chalk-50)`.
   - **Field "Stamm-Distanz"**: Label + Seg `["4 m", "8 m", "beides"]`.
4. **Section "Anmeldung"**:
   - **NavRow "E-Mail"**: `flex row gap: 14, padding: 10px 0, minHeight: 60, borderBottom: 1px line`. IconSlot 36x36 (`bgSunken`, `borderRadius: 10`, muted), Label "E-Mail" Display 15 weight 600 + Sub `email` 12 muted truncated, Chevron rechts.
   - **ProviderRow "Google"**: Icon `Google` + Label `"Google"` + Sub `"verknuepft"`/`"nicht verknuepft"` + Pill-Button rechts `"Trennen"` (muted) / `"Verknuepfen"` (Meadow-100/600 Bg/Text). Pill-Style: Display 12 weight 700, `padding: 6px 12px`, `borderRadius: 999`.
   - **ProviderRow "Apple"** — analog, last row hat `borderBottom: 0`.
5. **Section "Verein"**:
   - **Field "Klub"**: Label + Static-Value (`"Brosi's Kubb"`, Display 15 weight 600).
   - **Field "Mitglied seit"**: Label + Static-Value (`"Apr 2024"`).
6. **Section "Sicherheit"**:
   - **NavRow "Passwort aendern"**: Lock-Icon + Label + Sub `"zuletzt geaendert vor 3 Monaten"` + Chevron.
7. **Save-Button** — margin `18px 16px 0`, `minHeight: 54`, `borderRadius: 14`, `background: var(--bk-primary)`, `color: var(--bk-on-primary)`, Display 17 weight 700, Label `"Speichern"`.
8. **Bottom-Spacer** `24px`.

### Sheets (Modals)

#### Email-Change-Sheet

- Trigger: Tap auf NavRow "E-Mail".
- Eyebrow `"Account"`, Title `"E-Mail aendern"`.
- Step `form`: 3 pwField-Bloecke (`flex-column gap: 6, paddingTop: 8`).
  - Aktuelle E-Mail: Label + Static-Value.
  - Neue E-Mail: Label + Input (type=email). Hint `"ungueltige Adresse"` (`var(--bk-miss)`, 12px) wenn Regex-Mismatch.
  - Aktuelles Passwort: Label + Input (type=password).
- Hint-Text: `"Du erhaeltst eine Bestaetigung an die neue Adresse."` muted 12px.
- Actions-Row: grid `1fr 1fr`, gap 10. Cancel-Button (`bgSunken`, Display 16 weight 700) + Primary "E-Mail aendern" (deaktiviert bis valid).
- Step `done`: Done-Block — 64x64 Circle Meadow-500 mit Check-Icon, Title `"Bestaetigung gesendet"` Display 22 weight 800, Sub-Text `"Oeffne die E-Mail an <b>{next}</b> und bestaetige den Wechsel."`, Primary `"Fertig"`.

#### Password-Change-Sheet

- Trigger: Tap auf NavRow "Passwort aendern".
- Eyebrow `"Sicherheit"`, Title `"Passwort aendern"`.
- Step `form`: 3 PwField-Bloecke (Aktuelles, Neues, Neues Bestaetigen) + Show-Toggle-Row (`flex row gap: 10, padding: 10px 4px`, Checkbox 20x20 mit `border: 1.5px var(--bk-line-strong)`, `borderRadius: 6`, Meadow-600 Haken). Actions Cancel/Primary wie Email-Sheet.
- Validation: `lengthOK ≥ 8`, `matches`, `differs`. Primary disabled bei `!canSubmit`.
- Step `done`: `"Passwort aktualisiert"` + `"Du wurdest auf allen anderen Geraeten abgemeldet."`.

### Farben (Token-Namen)

| Bereich | Token |
|---|---|
| Screen-Background | `tokens.bg` |
| Group-Container | `tokens.bgRaised` |
| Avatar-Background | `KubbTokens.meadow600` |
| Avatar-Ring Gradient | `meadow500 → wood500` (linear 135deg) |
| Avatar-Edit-Link | `KubbTokens.meadow600` |
| Section-Header / Field-Label / Eyebrow | `tokens.fgMuted` |
| Static-Value / Field-Text | `tokens.fg` |
| Input-Border | `tokens.lineStrong` |
| Row-Divider | `tokens.line` |
| NavIcon-Slot Background | `tokens.bgSunken` |
| NavIcon-Color | `tokens.fgMuted` |
| Seg-Background | `tokens.bgSunken` |
| Seg-Active | `KubbTokens.stone900` + `KubbTokens.chalk50` |
| Provider-Pill verknuepft | `KubbTokens.meadow100` Background + `KubbTokens.meadow600` Text |
| Provider-Pill nicht verknuepft | `tokens.bgSunken` Background + `tokens.fgMuted` Text |
| Save-Button | `tokens.primary` / `tokens.onPrimary` |
| Cancel-Button (Sheet) | `tokens.bgSunken` / `tokens.fg` |
| Done-Icon | `KubbTokens.meadow500` + white |
| Sheet-Backdrop | `rgba(12,11,7,0.55)` |
| Sheet-Body | `tokens.bg` |
| Hint-Text | `KubbTokens.miss` (`tokens.danger`) |
| Checkbox-Border | `tokens.lineStrong` |
| Checkbox-Check-Color | `KubbTokens.meadow600` |

### Typografie

| Bereich | Font | Groesse | Weight |
|---|---|---|---|
| Avatar-Initial | Display | 36 | 800 |
| Avatar-Edit-Link | Display | 13 | 600 (underline) |
| Section-Header | Body | 11 | 600 (caps, 0.08em) |
| Field-Label / Row-Label | Body | 11 | 600 (caps) |
| Static-Value / NavLbl | Display | 15 | 600 |
| NavSub | Body | 12 | — (muted) |
| Provider-Pill | Display | 12 | 700 (caps 0.04em) |
| Input | Body | 15 | — |
| Seg-Button | Display | 13 | 600 |
| Save-Btn / Primary-Btn | Display | 17 | 700 |
| Cancel-Btn | Display | 16 | 700 |
| Sheet-Title | Display | 22 | 700 (-0.02em) |
| Done-Title | Display | 22 | 800 |
| Done-Sub | Body | 14 | — (muted, centered) |
| Hint (Error) | Body | 12 | — |
| Hint (Info muted) | Body | 12 | — (muted) |

### Spacing

- Section-Header padding `14px 18px 8px`
- Group-Container margin `0 16px`, padding `4px 14px`
- Row padding `10px 0` mit `borderBottom: 1px solid line` als Divider
- Save-Button margin `18px 16px 0`
- Sheet padding `10px 18px 32px`, gap 10
- Sheet-Actions grid 1fr/1fr gap 10
- Avatar-Block padding `10px 0 18px`, gap 8

### Border-Radius

- Avatar-Circle / Ring: 50% (full)
- Group-Container: 14
- Input: 10 (`radiusMd`-ish)
- Seg / Provider-Pill: 999 (`radiusPill`)
- NavIcon-Slot: 10
- Save-Button / Primary-Btn: 14
- Done-Icon: 50%
- Sheet top corners: 24
- Checkbox: 6

### Shadows

- Keine Shadows; nur Border-Lines.

### Icons

- `Icon.Mail` (20px) — E-Mail-NavRow
- `Icon.Lock` (20px) — Passwort-NavRow
- `Icon.Google` (20px farbig) — Provider-Row
- `Icon.Apple` (20px) — Provider-Row
- `Icon.ChevronRight` (20px) — NavRow-Affordance
- `Icon.Close` (22px) — Sheet-Close
- `Icon.Check` (22px) — Done-Block

## Komponenten-Inventar

| Sub-Komponente | Aufgabe | Wiederverwendbar | Props |
|---|---|---|---|
| `ProfileScreen` | Screen-Root | nein | `onBack` |
| `ProviderRow` | OAuth-Provider-Zeile mit Pill-CTA | inline | `icon, label, connected, onClick, last?` |
| `EmailChangeSheet` | Email-Aenderung Modal | inline | `email, setEmail, onClose` |
| `PasswordChangeSheet` | Passwort-Aenderung Modal | inline | `onClose` |
| `PwField` | Label + Password-Input + Hint | inline | `label, value, setValue, show, hint?` |
| `Field` | Generic Label-Plus-Children-Row | inline (Kandidat fuer shared) | `label, children` |
| `Seg` | Segmented-Control | inline (Kandidat fuer shared) | `value, options, onChange` |

**Kandidaten fuer geteilte Widgets**:
- `KubbFieldRow` (Field-Pattern: Label + Value/Input mit Divider)
- `KubbSegmentedControl<T>` (Seg-Pattern)
- `KubbNavRow` (NavRow-Pattern: Icon + Label + Sub + Affordance)
- `KubbProviderRow` (spezialisiert auf OAuth-Provider mit Pill-CTA)
- `KubbDoneBlock` (Check-Icon + Title + Sub + Primary-Btn — Sheet-Success-Pattern)
- `KubbBottomSheetActions` (Cancel + Primary, grid 1fr/1fr)

## Interaktions-Pattern

- **Tap-Targets**: NavRows minHeight 60, Seg-Buttons 36 (knapp unter 48), Provider-Pills 32 (Pill-Padding), Save-Btn 54, Sheet-Buttons 54. **Seg-Buttons 36 unter `touchMin: 48`** — entweder Padding hochziehen oder den Container so dimensionieren, dass die effektive Tap-Area ≥ 48.
- **Hover/Pressed-States**: keine expliziten States im JSX.
- **Loading-States**: keine im JSX — Save-Submit ist synchron. Flutter `_save()` zeigt `_saving` Spinner im `AuthPrimaryButton`.
- **Empty-States**: nicht relevant — alle Felder haben Defaults.
- **Error-States**:
  - Save-Fehler: JSX hat keine explizite Error-Surface; Flutter zeigt `_Banner(tone: error, message: l10n.authEditProfileError)`. Pruefen, ob das im Design vorgesehen war.
  - Email-Validierung: inline Hint `"ungueltige Adresse"` in Miss-Farbe.
  - Password-Mismatch: inline Hint `"stimmt nicht ueberein"`.
- **Navigation-Pfade**:
  - Back → vorheriger Screen.
  - Avatar-Edit-Button → Foto-Picker (out-of-scope im JSX, kein Sheet definiert). Flutter `EditProfileScreen` hat stattdessen Farb-Picker (`_ColorDot`).
  - NavRow "E-Mail" → EmailChangeSheet.
  - NavRow "Passwort" → PasswordChangeSheet.
  - Save-Button → `onBack()` (zurueck).
- **Form-Validation**:
  - Email: `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`, `next !== email`, `pw.length >= 4`.
  - Password: `current.length >= 4`, `next.length >= 8`, `next === confirm`, `current !== next`.
  - Anzeigename: nicht im JSX validiert. Flutter validiert `3 ≤ length ≤ 30, /^[A-Za-z0-9_-]+$/`.

## Accessibility-Hinweise

- **Kontrast**:
  - Avatar Meadow-600 + white: ~7:1.
  - Avatar-Edit-Link Meadow-600 auf `bgRaised`: ~6:1, underline-only — Schrift-Color reicht knapp; Underline ist zusaetzlicher Indikator (gut).
  - Provider-Pill verknuepft Meadow-600 auf Meadow-100: ~4.4:1 (AA fuer kleinen Text knapp). Pruefen.
  - Provider-Pill nicht-verknuepft Muted auf `bgSunken`: ~4.5:1.
  - Save-Btn Primary-Combo: AA.
- **Touch-Targets**:
  - Seg-Buttons (36) und Avatar-Edit-Link (Pill-Padding) sind klein. In Flutter mit ausreichend Padding auf ≥ 48 effektive Tap-Area bringen.
  - NavRows haben minHeight 60 — gut.
- **Reader-Labels**:
  - Sheet-Close: `aria-label="Schliessen"`.
  - Form-Inputs haben jeweils `<label>` — Flutter braucht Semantics-Label.
  - Provider-Status muss als Text vorhanden sein, nicht nur via Farbe.

## Quality-Gate-Checkliste (pruefbar gegen Flutter-Impl)

- [ ] AppBar mit Eyebrow `"Account"`, Title `"Profil"`, Back-Button. — Flutter `EditProfileScreen` nutzt `AuthAppBar`; `ProfileScreen` nutzt Material `AppBar`. **Inkonsistent**.
- [ ] Avatar mit Gradient-Ring (`meadow500 → wood500`), 88x88 Circle, Initial-Buchstabe Display 36 weight 800. — Flutter `EditProfileScreen` hat 104x104 ohne Ring; `ProfileScreen` hat `AvatarCircle`-Widget (Groesse pruefen).
- [ ] Avatar-Edit-Button als underlined Text-Link `"Foto aendern"`. — Flutter hat **kein Foto-Picker**, stattdessen Farb-Picker (`_avatarPalette`). Aenderung gegenueber Design.
- [ ] Section `"Spielerdaten"` mit Anzeigename + Wurfhand + Stamm-Distanz.
  - Anzeigename: Input. — Flutter hat das.
  - Wurfhand: Segmented `["links", "rechts", "beidhaendig"]`. — **Fehlt in Flutter**.
  - Stamm-Distanz: Segmented `["4 m", "8 m", "beides"]`. — **Fehlt in Flutter**.
- [ ] Section `"Anmeldung"` mit Email-NavRow + Provider-Rows fuer Google + Apple. — **Fehlt komplett in Flutter Edit-Screen**. ProfileScreen zeigt nur `_ProviderBadge` ohne Verknuepf-Funktion.
- [ ] Section `"Verein"` mit Klub + Mitglied-seit (Static-Values). — **Fehlt in Flutter**.
- [ ] Section `"Sicherheit"` mit Passwort-NavRow. — **Fehlt in Flutter**.
- [ ] Save-Button unten als Primary-Btn. — Flutter hat das (`AuthPrimaryButton`).
- [ ] EmailChangeSheet als Bottom-Sheet mit Form + Validation + Done-Step. — **Fehlt in Flutter**.
- [ ] PasswordChangeSheet als Bottom-Sheet mit 3 PwFields + Show-Toggle + Validation + Done-Step. — **Fehlt in Flutter**.
- [ ] Sheets: Backdrop `rgba(12,11,7,0.55)`, top corners 24, Grabber 36x4.
- [ ] Group-Container `bgRaised` + `borderRadius: 14`.
- [ ] Field-Rows mit `borderBottom: 1px line`.
- [ ] NavRows mit IconSlot 36x36 + Chevron rechts.
- [ ] Provider-Pill `"Trennen"`/`"Verknuepfen"` rechts.
- [ ] Alle Tokens aus `KubbTokens`.
- [ ] Touch-Targets ≥ 48dp.
- [ ] Keine UUID-Substrings.
- [ ] i18n via `AppLocalizations`.

## Bekannte Abweichungen (Flutter aktuell vs. Design)

Der Profile-Screen ist die **groesste Luecke** zwischen Design und aktuellem Flutter-Code. Aktueller Stand:

1. **Zwei Flutter-Screens vs. ein JSX-Screen**: Flutter trennt Read-View (`profile_screen.dart`) und Edit-View (`edit_profile_screen.dart`). JSX zeigt alles auf einem Screen. **Konsolidierungs-Entscheidung** noetig.
2. **Farb-Picker statt Foto-Picker**: Flutter hat eine 8-Farben-Palette (`_avatarPalette`) zur Avatar-Personalisierung. JSX zeigt einen `"Foto aendern"`-Link, der einen Image-Picker oeffnen wuerde. **Design-Mismatch**: Phase-1-Domain hat keinen Photo-Upload (siehe ADR-0004 — Avatare nicht prioritaer). Empfehlung: Farb-Picker beibehalten, JSX-Spec anpassen.
3. **Wurfhand- und Stamm-Distanz-Settings fehlen** in Flutter. Im JSX sind das zwei Pflicht-Felder fuer einen Spieler-Account. **Implementierungs-Luecke** — Felder am `display_profile`-Model + Drift-Schema fehlen vermutlich noch.
4. **Anmeldung-Section fehlt**: Email-Aenderung, Google/Apple-Verknuepfung sind nicht ueber UI editierbar. Flutter `ProfileScreen` zeigt nur ein einzelnes Provider-Badge (read-only). **Implementierungs-Luecke**.
5. **Verein-Section fehlt**: Klub-Mitgliedschaft ist nicht im Datenmodell. Phase-1-Scope unklar; eventuell Phase-2-Feature.
6. **Sicherheit-Section fehlt**: Passwort-Aenderung-Sheet ist nicht implementiert. Phase-1 nutzt OAuth (siehe ADR-0010 — Identity-OAuth+Keypair), Passwort-Aenderung waere Magic-Link/Email-Flow. Implementierungs-Aufwand klaeren.
7. **Avatar-Ring (Gradient)**: Flutter hat keinen Gradient-Ring um den Avatar.
8. **AppBar-Inkonsistenz**: Read-View nutzt Material `AppBar`, Edit-View `AuthAppBar`. Beide sollten `KubbAppBar` mit Eyebrow `"Account"` nutzen.
9. **Static-Value-Pattern fehlt**: `"Brosi's Kubb"`, `"Apr 2024"` als read-only Values im Group-Container — kein Pendant in Flutter.
10. **Save-Button im Edit-Screen** ist disabled wenn `!_canSave` (kein dirty oder invalid). JSX hat keine Disabled-Logik fuer Save — der Button speichert immer und navigiert zurueck. Flutter-Verhalten ist robuster; beibehalten.
11. **Provider-Pill-Toggle**: JSX togglet lokal state (`providers.google`, `providers.apple`). Real-App-Behaviour erfordert OAuth-Linking via Supabase — pruefen mit ADR-0010, ob Multi-Provider-Linking Phase-1 ist.
