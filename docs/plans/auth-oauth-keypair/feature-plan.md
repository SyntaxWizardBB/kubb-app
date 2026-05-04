# Feature-Plan: Authentication — OAuth + anonymous keypair

> Skeleton, das durch die drei Planungs-Schritte (PO → Architect → Scrum-Master) verfeinert wird. Jede `[ ]`-Checkbox ist ein Akzeptanzkriterium für die Owner-Abnahme.

---

## Meta

- **Slug:** auth-oauth-keypair
- **Beschreibung (Owner):**
  > Authentication with OAuth (Google/Apple) and anonymous Ed25519 keypair accounts per ADR-0010, against locally-hosted Supabase in Docker for development. Account upgrade path anonymous-to-OAuth. Passphrase-based encrypted server backup for keypair accounts (Argon2id KDF, XChaCha20-Poly1305 ciphertext). Local profile (player feature) stays offline-first; cloud user_profiles is created additively on login. Scope: AuthController, sign-in screen with both paths, OAuth callback handling, keypair-challenge flow, encrypted backup upload/restore, logout in settings, drift schema for cached auth state. Out of scope for this feature: tournament-lifecycle, applications, organizer-only flows.
- **Erstellt:** 2026-05-04
- **Status:** sprint-done
- **Plan-Verzeichnis:** docs/plans/auth-oauth-keypair/
- **Temp-Verzeichnis (ephemer):** /tmp/kubb_app/auth-oauth-keypair/
- **Branch:** feature/auth-oauth-keypair

---

## Bounded-Context-Zuordnung

- [ ] match (full hexagonal)
- [ ] tournament (hexagonal-light)
- [ ] training (pragmatisch)
- [x] player / team (pragmatisches CRUD) — bestehender lokaler Profile-Code bleibt offline-first, wird additiv erweitert
- [x] core / infrastructure (drift, supabase, theme) — neue Cached-Auth-State-Tabelle in drift, Supabase-Client-Setup
- [ ] **NEU**: `auth/` (pragmatisch) — neuer Bounded Context für Auth-Logik, Sign-In-Flows, Keypair-Crypto

---

## Backlog (Step 1 — Product Owner)

> Wird vom `/agents/product-owner`-Lauf befüllt. Volldokument: `po-output.md`.

### User Stories

(pending)

### Akzeptanzkriterien (Headline)

(pending)

### Implizite Anforderungen

(pending)

### Owner-Abnahme

- [x] Backlog akzeptiert am 2026-05-04 (alle 7 offenen Fragen geklärt, US-19 Disclaimer + US-20 Onboarding ergänzt)

---

## Architektur (Step 2 — Architect)

> Wird vom `/agents/architect`-Lauf befüllt. Volldokument: `architecture.md`.

### Komponenten-Delta

(pending)

### Schnittstellen-Delta

(pending)

### Daten-Modell-Delta

(pending — erwartet: `user_credentials`, `user_keypair_backups` Tabellen lt. ADR-0010)

### Neue ADRs

(keine erwartet — ADR-0009 und ADR-0010 sind bereits accepted)

### Owner-Abnahme

- [ ] Architektur akzeptiert am <Datum>
- [ ] ADR(s) akzeptiert am <Datum>

---

## Sprint-Plan (Step 3 — Scrum Master)

> Wird vom `/agents/scrum-master`-Lauf befüllt. Volldokumente: `sprint-plan.md` und `tasks.md`.

### Milestones

(pending)

### Ausführungsreihenfolge

(pending)

### Owner-Abnahme

- [ ] Plan akzeptiert am <Datum>

---

## Fortschritt

(wird nach Sprint-Plan-Abnahme initialisiert)

---

## Final-Review

- [ ] Security-Checker durchgelaufen — kein BLOCKING
- [ ] Tech-Lead durchgelaufen — `flutter analyze` clean, Tests grün
- [ ] Commit-History clean (kein AI-Trace)
- [ ] Push erfolgt am <Datum>

---

## Eskalationen

(leer)

---

## Risiken

| # | Risiko | Wahrscheinlichkeit | Impact | Mitigation |
|---|---|---|---|---|
| 1 | Supabase Self-Hosted-Setup lokal noch nicht vorhanden — Auth-Code kann nur gegen Mocks getestet werden bis VPS steht | Hoch | Mittel | Docker-Compose-Spike als erster Task; Auth-Adapter sauber gegen Port-Interface, damit Mock-Tests reichen |
| 2 | OAuth (Google/Apple) braucht Provider-Credentials und Callback-URL-Konfiguration — kann lokal nur eingeschränkt getestet werden | Mittel | Mittel | OAuth-Pfad in Sub-Tasks isolieren; Akzeptanzkriterien lokal mit Stub-Provider, echtes Setup als Owner-Task im Hetzner-Schritt |
| 3 | Argon2id + XChaCha20-Poly1305 in Dart — `cryptography`-Package muss alle Plattformen unterstützen (Android, Linux, Web) | Mittel | Mittel | Library-Spike als erster Task: kleine Verify-App, Algorithmen auf allen Ziel-Plattformen prüfen |
| 4 | Local-Profile (F2) vs Cloud-Profile-Sync-Logik kann zu Inkonsistenzen führen (Nickname-Konflikte, Avatar-Pfad-Differenz) | Niedrig | Mittel | Klare Sync-Regel in Architecture-Phase: lokales Profile ist Source-of-Truth solange offline; bei erstem Login wird Cloud-Profile additiv angelegt; bei Konflikt gewinnt lokales |
