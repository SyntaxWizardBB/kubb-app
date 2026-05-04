# Design brief — Authentication UI elements

> Owner-blocking. Hand this brief to Claude Design (or your design
> tool of choice). For each entry below, produce a template that the
> M5 implementation tasks can build against. Implementation does not
> start until templates are in hand — this is the project rule from
> `feedback_ui_design_template_first.md`.

> Tokens to honour: `lib/core/ui/theme/kubb_tokens.dart`. New
> components should compose from existing widgets in
> `lib/core/ui/widgets/` (KubbAppBar, KubbBottomSheet, KubbTapPad,
> KubbCounter, KubbIcon) where possible.

> Accessibility floor for every screen: ≥ 48 dp touch targets,
> contrast WCAG AA (≥ 4.5:1 normal text, ≥ 3:1 large text), screen-
> reader navigable in linear order, semantic labels.

> i18n: every visible string needs an ARB key under `auth.*`. Sample
> keys are listed inline; final naming is part of the design step.

---

## 1. SignInScreen (M5-T02)

**User story / AK**: US-1, US-2 / AK-1, AK-2.
**Purpose**: First screen on cold start when there is no cached
session. Lets the user pick OAuth (Google always, Apple iOS-only)
or the anonymous-keypair path. Restore-account is reachable as a
secondary link.

**Required elements**:
- Brand area at top (logo + 1-line tagline; tagline arb key
  `auth.signin.tagline`).
- "Mit Google anmelden" CTA (`auth.signin.google`) — primary, full
  width, with Google logo per Google's brand guidelines.
- "Mit Apple anmelden" CTA (`auth.signin.apple`) — primary, only
  rendered when `Platform.isIOS`.
- "Ohne Konto starten" CTA (`auth.signin.anonymous`) — secondary
  style, leads into the AnonymousSignupFlow.
- Footer link: "Konto wiederherstellen" (`auth.signin.restore`)
  — secondary style, opens restore flow.
- "Verbindung erforderlich" hint when offline (AK-8) — surface as a
  small warning banner above the CTAs (`auth.signin.offline`).

**States to cover**: idle, OAuth-launching (button shows spinner),
anonymous-flow-launching, offline.

---

## 2. AnonymousSignupFlow (M5-T03 + T06 + T07)

**User story / AK**: US-1, US-3, US-19 / AK-1, AK-3, AK-19.
**Purpose**: Three-step PageView wizard that creates the anonymous
keypair account, uploads the encrypted backup, and confirms.

### Step 1 — NicknameStep (M5-T03)
- Header "Wähle einen Spielnamen" (`auth.signup.nickname.title`).
- Single text input with validation message (3–30 chars,
  alphanumeric + `-` `_`); errors via `auth.signup.nickname.error.*`.
- Helper text "Andere Spielerinnen sehen diesen Namen"
  (`auth.signup.nickname.helper`).
- Continue button disabled until valid (`auth.common.continue`).

### Step 2 — DisclaimerAndPassphraseStep (M5-T06)
**Mandatory disclaimer block per AK-19**, three bullet points
(`auth.disclaimer.no_reset`, `auth.disclaimer.password_manager`,
`auth.disclaimer.no_liability`). Block stays visible during entire
step — not a modal that disappears.

Below the block:
- Mandatory checkbox (`auth.disclaimer.acknowledge`); the
  "Account erstellen" button is disabled until it is checked.
- Reusable `passphrase_input` widget (see #4 below).
- "Account erstellen" button (`auth.signup.submit`) — disabled
  until checkbox is checked AND passphrase is ≥ 12 chars.

### Step 3 — BackupConfirmationStep (M5-T07)
- Success icon + "Account angelegt"
  (`auth.signup.success.title`).
- Reminder "Speichere deine Passphrase im Passwort-Manager"
  (`auth.signup.success.reminder`).
- "Weiter zur Tour" button (`auth.signup.success.continue`) — leads
  into OnboardingTour.

**States to cover** for the whole flow: empty, typing, validation
errors, submitting (KDF + upload — can take 2–4 s on mid-range
Android, must show progress), failure (inline error banner).

---

## 3. DisclaimerBlock (M5-T04)

**Reusable widget**. Used both in step 2 of the signup flow and on
the OnboardingTour reminder slide. Three-bullet AK-19 disclaimer:
- "Diese Passphrase kann nicht zurückgesetzt werden." — bold lead-in
- "Wir empfehlen dringend einen Passwort-Manager."
- "Die App-Betreiber haften nicht."

Visual treatment should be alarming-but-not-scary (yellow-tinted
warning panel, iconography, bold first sentence). Screen-reader text
must read in the order: title, three bullets, checkbox label.

---

## 4. PassphraseInput (M5-T05)

**Reusable widget**. Shared by signup, restore, change-passphrase.
- Text field with show/hide eye-icon toggle.
- Strength indicator below — three states (weak / medium / strong)
  driven by zxcvbn-light. Indicator is BOTH colour AND text/symbol
  (per accessibility requirement: never colour alone).
- Validation: 12 character minimum. Error message below indicator.
- Variant: with vs. without strength indicator (restore + change
  use it without).

**States**: empty, hidden, visible, weak, medium, strong, error.

---

## 5. RestoreFlow (M5-T08)

**User story / AK**: US-4 / AK-4.
**Purpose**: Two-step flow to restore an account on a fresh device.

- Step 1 — Nickname input (validation as in signup).
- Step 2 — Passphrase input (without strength indicator).
- "Konto entsperren" button (`auth.restore.submit`).
- Cooldown badge displayed when in cooldown state — "Bitte warte X
  Sekunden" (`auth.restore.cooldown`) with countdown.
- Generic error message that does NOT reveal whether the nickname
  exists: "Wiederherstellung fehlgeschlagen" (`auth.restore.error`).

**States**: idle, restoring (spinner), cooldown (locked + countdown),
error.

---

## 6. AccountLinkScreen (M5-T09)

**User story / AK**: US-5 / AK-5.
**Purpose**: Anonymous-keypair user upgrades to OAuth. Reached from
SettingsScreen → "Konto verknüpfen".

- Explanation block "Verknüpfe dein Konto für sichereres Backup"
  (`auth.link.explanation`).
- Provider buttons (same Google + Apple-on-iOS as SignInScreen).
- Note "Dein bisheriger Zugang bleibt als Backup erhalten"
  (`auth.link.fallback_kept`).
- Back button (`auth.common.back`).

**States**: idle, linking, error, success → auto-dismiss back to
settings.

---

## 7. PassphraseChangeScreen (M5-T10)

**User story / AK**: US-12.
- Three input fields stacked: old passphrase, new passphrase (with
  strength indicator), confirm new passphrase.
- "Speichern" button — disabled until old non-empty, new ≥ 12 chars,
  confirm matches new.
- Generic error on wrong old passphrase
  (`auth.passphrase.change.error`).
- Success → auto-dismiss with snackbar
  (`auth.passphrase.change.success`).

---

## 8. DeleteAccountScreen (M5-T11)

**User story / AK**: US-13 / AK-13.
**Purpose**: Two-step destructive UI.

- Page 1 — Warning text, list of consequences, "Weiter" button
  (`auth.delete.continue_to_confirm`).
- Page 2 — Final confirmation: required checkbox "Ich verstehe dass
  alle Daten dauerhaft gelöscht werden" + "Konto endgültig löschen"
  button — destructive style (red).
- Optional toggle "Auch lokales Trainings-Profil löschen" (default
  ON) — controls the cleanup of the player-feature display data
  alongside the cloud cascade.

**States**: page-1, page-2-checkbox-empty, page-2-confirmable,
deleting, error.

---

## 9. OnboardingTour (M5-T12)

**User story / AK**: US-20 / AK-20.
**Purpose**: 4-slide PageView shown once after the first sign-in.

- Slide 1 — Welcome + account-status badge (anonym vs OAuth) with
  visual distinction.
- Slide 2 — Trainingsmodi-Übersicht (Sniper, Finisseur, künftig
  4m-Linie) with one-line description each.
- Slide 3 — "Tournaments + Friend-Match — kommen bald" placeholder.
- Slide 4 — Anonymous-only reminder slide that re-uses the
  DisclaimerBlock with a "Hast du deine Passphrase im
  Password-Manager gespeichert?" prompt.
- Skip + finish controls in the AppBar.

**States**: per-slide, last-slide (Finish CTA replaces Next).

---

## 10. OAuthProviderButton (M5-T13)

**Reusable widget**. Renders the brand-correct button for Google
and Apple. Conditionally hides Apple when not on iOS. Variants:
primary (used on SignInScreen), secondary (used on
AccountLinkScreen).

---

## 11. AccountSection (M5-T14)

**Purpose**: New section at the top of SettingsScreen.
- Display row: avatar + nickname + provider badge (Anonym / Google /
  Apple).
- "Konto verknüpfen" entry (only when anonymous) →
  AccountLinkScreen.
- "Passphrase ändern" entry (only when keypair) →
  PassphraseChangeScreen.
- "Abmelden" entry → confirmation dialog → AuthController.signOut.
- "Konto löschen" entry → DeleteAccountScreen.

States: anonymous-keypair, OAuth-only, OAuth-with-keypair-fallback.

---

## 12. EditProfileScreen (M5-T15)

**Purpose**: Replaces the F2 profile edit-mode. Read+edit nickname
and avatar colour for the cloud profile.

- Nickname input (validation as in signup).
- Avatar colour picker (existing component from `lib/core/ui/`).
- "Speichern" button — disabled until something changed.

States: idle, saving, error, success → snackbar + dismiss.

---

## 13. AccountStatusBadge (M7-T01)

**Reusable widget**. Small badge for the AppBar showing "Anonym"
(with lock icon) / "Google" / "Apple" (with provider logo). Tap
opens AccountSection in settings.

---

## 14. BackupWarningSurface (M7-T02)

**Embedded in AccountSection**. Yellow warning panel shown when the
user is on a keypair account without a server backup, OR with a
backup older than 90 days. Includes "Backup einrichten" button.

---

## Hand-off checklist

Per template, deliver:
- [ ] Layout for phone portrait + tablet landscape (designs that
  scale gracefully, not strict pixel grids).
- [ ] All states listed.
- [ ] ARB-key list confirmed.
- [ ] Accessibility annotations (semantic labels, focus order).
- [ ] Motion / transition notes.
- [ ] Sample copy in German for all user-facing strings.

When templates are ready, signal "M5 templates done" and the
implementation loop resumes from M5-T02.
