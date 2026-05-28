# Quality-Gate: Profil (Mobile)

**Quelle**: `docs/design/ui_kits/app/ProfileScreen.jsx`
**Flutter-Pendant**: `lib/features/player/presentation/profile_screen.dart`
**Stand**: 2026-05-28 (Rebrand zu Kubb Club)

---

## Visual-Spec

### Layout (top-down)

1. **AppBar**: Eyebrow `Account`, Title `Profil`, Back-Button.
2. **Avatar-Block**: Ring (linearGradient meadow→wood) um Avatar-Circle 88dp (meadow-600 Bg, Display 36px Initial). Darunter Text-Link "Foto aendern".
3. **Section "Spielerdaten"**:
   - Group-Card mit 3 Field-Rows:
     - Anzeigename (Input)
     - Wurfhand (Segmented: links / rechts / beidhaendig)
     - Stamm-Distanz (Segmented: 4 m / 8 m / beides)
4. **Section "Anmeldung"**:
   - Group-Card mit 3 NavRows:
     - E-Mail (Mail-Icon + email + Chevron)
     - Google (Provider-Row mit Verknuepfen/Trennen-Pill)
     - Apple (Provider-Row, last)
5. **Section "Verein"**:
   - Group-Card mit 2 statischen Fields:
     - Klub (z.B. "Brosi's Kubb" — Mock-Wert, Eigenname)
     - Mitglied seit (z.B. "Apr 2024")
6. **Section "Sicherheit"**:
   - Group-Card mit 1 NavRow: Passwort aendern (Lock-Icon + Sub "zuletzt geaendert vor 3 Monaten" + Chevron).
7. **Save-Button**: full-width meadow primary, Display 17px weight 700.

### Bottom-Sheets (modal)

- **PasswordChangeSheet**: 3 PwField-Inputs (aktuell / neu / bestaetigen), "Passwoerter anzeigen"-Checkbox, Cancel + Submit. Submit nur enabled wenn Validation OK. Done-State zeigt Check-Icon + "Passwort aktualisiert".
- **EmailChangeSheet**: aktuelle Email (statisch) + neue Email-Input + Aktuelles-Passwort-Input. Submit nur wenn email-valid && unterschiedlich && pw>=4. Done-State: "Bestaetigung gesendet".

### Farben (Tokens)

| Element | Token |
|---|---|
| Avatar-Ring | linear-gradient(135deg, meadow-500, wood-500) |
| Avatar-Bg | `--bk-meadow-600` |
| Avatar-Edit-Link | `--bk-meadow-600` underline |
| Section-Header | `--bk-fg-muted` |
| Group-Card | `--bk-bg-raised` |
| Row-Border | `--bk-line` |
| NavIcon-Bg | `--bk-bg-sunken` |
| NavIcon-Fg | `--bk-fg-muted` |
| Provider-On-Pill | `--bk-meadow-100` Bg + `--bk-meadow-600` Fg |
| Provider-Off-Pill | `--bk-bg-sunken` Bg + `--bk-fg-muted` Fg |
| Input-Border | `--bk-line-strong` |
| Seg-On | `--bk-stone-900` + chalk-50 |
| Save-Btn | `--bk-primary` |
| Sheet-Bg | `--bk-bg` |
| Cancel-Btn | `--bk-bg-sunken` |
| Hint (Fehler) | `--bk-miss` |
| Done-Icon-Bg | `--bk-meadow-500` |

### Typografie

- Avatar-Initial: Display 36px weight 800.
- Avatar-Edit: Display 13px weight 600 underline.
- Section: 11px weight 600 uppercase tracking 0.08em.
- StaticVal: Display 15px weight 600.
- NavLbl: Display 15px weight 600.
- NavSub: 12px fg-muted (ellipsis, nowrap).
- Provider-Pill-Label: Display 12px weight 700 uppercase tracking 0.04em.
- Input: 15px Body.
- Seg-Btn: Display 13px weight 600.
- SaveBtn: Display 17px weight 700.
- SheetTitle: Display 22px weight 700.
- DoneTitle: Display 22px weight 800.
- DoneSub: 14px fg-muted center.
- PwField-Lbl: 11px weight 600 uppercase.
- Hint: 12px miss.

### Spacing

- AvatarBlock: padding `10px 0 18px`, gap 8.
- Section: padding `14px 18px 8px`.
- Group: margin `0 16px`, padding `4px 14px`, radius 14.
- Row (Field): padding `10px 0`, gap 6, borderBottom 1px line.
- NavRow: padding `10px 0`, minHeight 60, gap 14, borderBottom 1px line.
- SaveBtn: margin `18px 16px 0`, minHeight 54.
- Sheet: padding `10px 18px 32px`, gap 10.
- SheetActions: gap 10.
- PwField: gap 6, paddingTop 8.
- DoneBlock: gap 10, padding `18px 8px 6px`.

### Border-Radius

- Avatar: 50% (Circle).
- Avatar-Ring: 50%.
- Group-Card: 14.
- NavIcon: 10.
- Provider-Pill: 999.
- Input: 10 (Profil) / 12 (Sheet).
- Seg-Container: 999, Inner-Btn 999.
- SaveBtn: 14.
- Sheet: top-radius 24.
- Cancel/Primary-Btn: 14.
- Done-Icon: 50% (Circle), 64x64.
- Checkbox: 6.

### Shadows

- Keine — alles flat.

### Icons

- `Icon.Mail` (20px) — Email-NavRow.
- `Icon.Lock` (20px) — Passwort-NavRow.
- `Icon.ChevronRight` (20px) — Chevron in NavRows.
- `Icon.Google` / `Icon.Apple` (20px) — Provider-Rows.
- `Icon.Close` (22px) — Sheet-Close.
- `Icon.Check` (22px) — Done-State + Checkbox.

### Brand-Elemente

- **Avatar-Ring-Gradient** (meadow → wood): symbolisiert die beiden Brand-Farben, einzige Brand-Geste auf diesem Screen.

## Komponenten-Inventar

- `ProfileScreen` — Hauptkomponente.
- `ProviderRow` — Auth-Provider-Zeile (Google/Apple) mit Verknuepfen/Trennen-Pill.
- `EmailChangeSheet` — Modal mit Form + Confirm-State.
- `PasswordChangeSheet` — Modal mit 3 PwFields + Confirm-State.
- `PwField` — Generisches Passwort-Input (toggle visibility).
- `Field` — Generische Label-Value-Row.
- `Seg` — Segmented-Control.

## Interaktions-Pattern

- **State**: lokales `useState` fuer `name`, `email`, `hand`, `stamm`, `providers`.
- **`toggleProvider(k)`**: schaltet Google/Apple-Verknuepfung um.
- **Email-Change-Validation**:
  - `valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(next)`
  - `canSubmit = valid && next !== email && pw.length >= 4`
- **Password-Change-Validation**:
  - `lengthOK = next.length >= 8`
  - `matches = next === confirm`
  - `differs = current !== next`
  - `canSubmit = current.length >= 4 && lengthOK && matches && differs`
- **Submit-Disabled-Look**: `opacity: canSubmit ? 1 : 0.4, pointerEvents: canSubmit ? 'auto' : 'none'`.
- **Sheet-State `step`**: `'form'` → `'done'`.
- **Show-Password-Toggle**: gemeinsame Checkbox fuer alle 3 PwFields.

### Loading / Error / Empty-States

- Hints unter Inputs zeigen Validation-Fehler ("stimmt nicht ueberein", "ungueltige Adresse", `mindestens 8 Zeichen`).
- Done-State pro Sheet (Check-Icon + Title + Sub + Fertig-Button).
- Keine Loading-State im Kit — Submit ist sofortig (Mock).

### Spezifisch fuer diesen Screen

- **Stamm-Distanz: 4m / 8m / beides** — Spec-Entscheidung. "beides" als Schweizer-Style-Option, der Spieler beide Stamm-Distanzen trainiert.
- **Provider-Pills "Verknuepfen" / "Trennen"**: visuelle Differenzierung statt Toggle-Switch — Klick fuehrt Action aus.
- **Klub-Field statisch**: aktueller Mock-Wert `Brosi's Kubb`. Das ist im Rebrand-Kontext ein Eigenname (Beispiel-Klub), nicht das App-Brand. **OK lassen** — App heisst Kubb Club, der Beispiel-Klub ist eigenstaendig.
- **EmailChangeSheet hat 3 Felder**: aktuelle E-Mail (read-only Display), neue E-Mail, aktuelles Passwort (Security).

## Accessibility

- AppBar 48x48 ✅.
- NavRow: 60dp ✅.
- Save-Btn: 54dp ✅.
- Input: 44dp — knapp unter 48dp Standard.
- Seg-Btn: 36dp — **unter 48dp**.
- Provider-Pill: `padding 6px 12px` = ~30dp Hoehe — **unter 48dp**, aber Pill-Klick-Target koennte ueber den umliegenden Button vergroessert werden.
- Sheet-Close `aria-label="Schliessen"` ✅.

## Quality-Gate-Checkliste

- [x] Section-Struktur (Spielerdaten / Anmeldung / Verein / Sicherheit) dokumentiert.
- [x] Validation-Logik (Email + Password) explizit.
- [x] Provider-Verknuepfen-Pattern (Pill-Action) dokumentiert.
- [ ] **Seg-Btn 36dp + Input 44dp + Provider-Pill ~30dp** unter 48dp.
- [ ] **Avatar-Edit "Foto aendern"** ist nur Text-Link — kein Image-Upload-Flow im Kit.
- [ ] **Klub-Field statisch** — kein Editier-Flow.
- [x] Rebrand: `Brosi's Kubb` als Klub-Mock-Wert bleibt — Eigenname.

## Bekannte Abweichungen Flutter aktuell vs. Design

1. **Email/Password-Change-Sheets**: Flutter sollte das ueber `reactive_forms` (Auth-Konvention) loesen — vs. das hier-modellierte direkte State-Setting.
2. **Provider-Verknuepfung**: Flutter muss echten OAuth-Flow triggern (Supabase + native). Nicht nur Toggle.
3. **Avatar-Foto-Upload**: im Kit nur Text-Link "Foto aendern" — Flutter braucht `image_picker` + Supabase Storage Path.
4. **Stamm-Distanz "beides"**: Spec-relevant. Pruefen, ob das im Player-Model so persistiert ist (`SignaturePlayerProfile.stammDistanz`).
5. **Wurfhand**: 3 Optionen (links / rechts / beidhaendig) — Flutter sollte das als Enum mit Localized-Labels haben.
6. **`/profile/edit`-Route** (per AUDIT.md): Mobile-Kit ist hier sowohl Edit als auch View. Pruefen, ob Flutter zwischen "Profile-View" und "Profile-Edit" trennt.
