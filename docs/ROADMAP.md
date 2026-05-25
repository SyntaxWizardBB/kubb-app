# kubb_app — Roadmap

Stand: 2026-05-25. Diese Datei ist der einzige Ort, an dem die Modul-Reihenfolge gepflegt wird. Wenn sich etwas ändert, wird hier upgedatet — nicht in `CLAUDE.md`, nicht in einer ADR.

## Stand

### Shipped auf `main`

**Training & Solo-Match** (vor M0):
- F1 Sniper-Training MVP, F2 Profile + Avatar, F3 Stats Screen, F4 Finisseur, F5 CSV-Export + Settings
- Auth (OAuth + Keypair)
- Friends + Groups
- Solo-Match (Server-shaped per ADR-0013) inkl. Match-Stats-Tab im StatsScreen

**Tournament-Foundation M0 + M1** (2026-05-25):
- **M0 Domain**: Bracket-Gen (recursive standard + linear opt-in), Round-Robin-Pool, Pairing-Strategy, Tiebreaker-Chain (7 Kriterien), EKC-Score, Standings — alles in `packages/kubb_domain/lib/src/tournament/`, glados Property-Tests
- **M1 Backend**: 5 SQL-Migrations (`20260525000001..5_tournament_*.sql`) — Schema (5 Tables, RLS) + 18 RPCs (Lifecycle, Discovery, Registration, Score-Consensus, Override)
- **M1 UI**: 9 Screens — Setup-Wizard, Liste, Detail, Registration, Match-Liste, Match-Detail (per-Set-Score-Eingabe + EKC-Live-Vorschau + Konsens-Retry-Handling), Conflict, Override, Standings
- **M1 Polish**: Drift v5 lokale Score-Drafts, Router komplett verdrahtet, Home-Tournament-Tile, e2e Integration-Tests gegen FakeTournamentRemote
- ADRs 0000–0015 alle Accepted

### Hotfixes vor M2

1. `TournamentRepository.getTournament` crasht gegen echtes Backend (Worker-Befund M1-W4-C). Fix-Pfad: alle Detail-Aufrufe auf den Port-gelifteten `getTournamentDetail` umstellen, `getTournament` für Listen-Projektion neu parsen.
2. Match-Detail-Screen pushed nicht auf Conflict-Screen bei consensus_round-Bump (nur SnackBar). Soll-Verhalten: `context.push(TournamentRoutes.conflict(...))`.
3. Supabase-Migrations `20260525000001..5_tournament_*.sql` auf Live-DB spielen.

### In Flight nach M1

- Kein aktiver In-Flight-Branch. M1 ist auf main, demobar nach SB-Migration.

### Reihenfolge nach M1

1. **M2 — KO-Bracket + Setup-Wizard-Polish** (8-10 Tage Senior-Tempo)
   - Bracket-Visualisierung (CustomPainter oder Lib → ADR fällig)
   - Seeding aus Standings, manuelle Override
   - KO-Phase nach Round-Robin
   - Spiel um Platz 3 als Option
   - Bündel-Bezug: B1 + B8 + B9 (Format-Erweiterung)
2. **M3 — Teams + Pool + Roster** (10-14 Tage)
   - Team-Tabellen, Pool-Mitglieder, Captain-Rechte (FR-TEAM-1..20)
   - Roster-Auswahl beim Anmelden (Teamgrösse 2/3/6)
   - Mid-Turnier-Roster-Swap
   - Bündel-Bezug: B2 + B7
3. **M4 — Realtime + Live-Dashboard + Offline** (8-10 Tage)
   - Supabase Realtime statt Polling (ADR fällig)
   - Veranstalter Live-Dashboard mit Pitch-Status
   - Runden-Clock
   - Score-Outbox (FCM/APNs Push)
4. **M5 — Schweizer System + Liga-Punkte + Saisontabelle** (10-14 Tage)
   - Schochmodus + Schweizer System als Paarungsstrategien
   - Liga-Punkte-Formel (FR-POINTS)
   - Saison-Tabellen
   - Mid-Season-Wechsel durch Liga-Admin
5. **Veranstalter-Rollen + Anmelde-Flow** — Verifizierung von Veranstaltern, Rollen pro Tournier (Spieler / Organizer / Helfer). Bündel: B10 + B11.
6. **Post-M5** — Vereine (FR-CLUB), Veranstalter-Bewertung (FR-FEEDBACK), Lageplan (FR-MAP), Shared Tournament mit Liga-Split, Double Elimination, FR + EN, QR-Check-In. Bündel: B5, B13, B15, B14, B12, B4, B6.

### Warum diese Reihenfolge

- M0 + M1 (8-Spieler-RR Einzelturnier e2e) hat die Match-Engine + Score-Konsens + Override-Pfad gehärtet. M2 baut sauber drauf auf mit KO-Phase und Bracket-Visualisierung.
- M3 (Teams) muss vor M4 (Realtime), weil Realtime sinnvoll auf den Team-Roster-Modus angewandt wird — ein Einzelturnier von 8 ist polling-tauglich.
- M5 (Liga-Punkte + Saisontabelle) schliesst die Schweizer-Kubbverband-Spec-Kompatibilität ab.
- Veranstalter-Verifizierung und Vereine kommen später — Owner-Hosting reicht für die nächsten Iterationen.

## Block-Übersicht (B1–B15)

Jeder Block kommt aus den rohen Owner-Notizen unten und wird hier eingeordnet.

| # | Block | Inhalt | Bucket |
|---|-------|--------|--------|
| B1 | Turnier-Modi & Bracket-Stufen | Schweizer / Gruppenphase / 32tel–4tel-Final | Tournament-Foundation |
| B2 | Gruppen / Teams | Gruppen-Mitgliedschaft 1–6 Player, n Gruppen pro User | in flight |
| B3 | Regelwerke | Turnier-, Landes-, Matchregeln (best-of-x, Tie-Break, Wertung) | Tournament-Foundation |
| B4 | Turnier-Infos | Spielpläne, Felder-Übersicht, Regel-Anzeige | später |
| B5 | Erweiterungen / Orga | Food, Drinks, Toiletten, Schlafplatz, Schiri-Call | später |
| B6 | Strukturelle Features | Onboarding, Wizard, AdminDashboard, Rollen, Anmeldung | teilweise in B9/B10, Rest später |
| B7 | Solo / Friend-Match | Gruppen-Bildung, Solo-Match best-of-x, Statistik-Page | in flight |
| B8 | Home-Screen-Logik | Overview Turniere, „Current Tournament"-Button | Tournament-Foundation |
| B9 | Tournament-Configure-UI | Anzahl Spieler, Modus, Regeln, Doppel-KO, Bracket-Stufen, Startpositionen, Spieler/Team | Tournament-Foundation |
| B10 | Veranstalter-Verifikation & Rollen | Verifizierung, Organizer/Helfer-Rollen pro Tournier | Veranstalter-Rollen + Anmelde-Flow |
| B11 | Anmelde-Flow | Gruppenbildung + Tournieranmeldung wenn ausgeschrieben | Veranstalter-Rollen + Anmelde-Flow |
| B12 | Infrastruktur / DevOps | Prod / Test / Dev, CI/CD, e2e, Testsuite vervollständigen | später |
| B13 | Turnier-Laufzeit | Zeit konfigurieren, Pushups während Turnier | später |
| B14 | Monetarisierung & Community | Sponsoring, Feature-Request, Bug-Report | später |
| B15 | Hilfestellungen & Social | Info-Buttons, Messen mit Freunden, Freundschaftsanfragen | später |

## Lose Enden aus früheren Notizen

| Punkt | Wo es jetzt landet |
|-------|---------------------|
| Multiplayer Friend-Match | subsumiert in B7 (Solo-Match), Variante mit eigenem Lightweight-Kontext ohne Bracket |
| Mobile/Desktop-Differenzierung | später, kommt mit der Owner-Design-Session — `docs/feature-notes/responsive-mobile-desktop.md` |
| Rule-Set-Viewer (CH 1.11 in-App) | später, fällt mit B3 zusammen — Regelwerk wird über Tournament-Configure exposed |
| Stats-Erweiterungen (Liga A/B/C) | später, Phase 2 per ADR-0004 |
| i18n (EN als zweite Sprache) | später |
| iOS-Build | später, braucht Codemagic oder macOS |

## Anhang — rohe Owner-Notizen (1:1, unverändert)

Quelle: Roadmap-Refinement-Session am 2026-05-05. Diese Notizen sind die Basis der Block-Aufteilung B1–B15. Sie bleiben hier stehen, damit beim späteren Sortieren nichts unter den Tisch fällt.

```text
Big picture:

Turnier modis:
-schoch
-Gruppenphase

32tel final
16tel final
8tel final
6tel final
4tel final

Gruppen management:
1-6 player

Tounier regeln

Landes regeln

Tournier infos
- spielpläne
- übersicht über die felder?
- tournier regeln?

Dann
Matchregeln, best of x
(1-5)
Tie break, wertung, pro satz punkte(pro kubb1 und könig 3)


erweiterung:
Turnier:
- organisatorisches, food, drinks toiletten schlafplatz etc?
- call schiri?

Das heisst:
onboarding screens signIn etc.
Wizzard?
Match modus + group mgnt
Turnament setup
Tournament modis
AdminDashboard
Rollemanagement pro tournier
Tournament anmeldung, registrierung etc.

Hilfestellungen? Also info buttons.
Messen mit freunden und freundschaftsanfragen auch noch als feature

Nächster schritt nach auth:

User müssen zusammen gruppen bilden können, dass heisst ein user kann mitglied von n gruppen sein, aus diesen kann er wieder austreten und er soll da auch immer wieder eintreten können eine gruppe besteht aus n usern.
dann dein solo match mode:
Ein user macht mit n leuten ein match also ein best of x dazu kann er auch manuell leute hinzufügen, die leute die aktiv accounts haben sollen das ganze alles in einer weiteren statistik page sehen die neben den stats von sniper und finiseur angesiedelt werden.
Dann beginnt das tournierzeugs...

Also overview turnaments im home screen

Current turnament (nur wenn man angemeldet ist an einem) der button soll einem dann auch zum aktuellen match oder upcoming match führen andem der angemeldete spieler partizipiert.

Configure turnamemt:
Anzahl spieler?
Gruppenphase oder schoch?
Tournierregeln.
Doppel ko?
1/4 final 1/8 final 16/final 32final 64 final?
Startpositionen setzen der teams
Wieviele spieler pro team? (1-6)



Turnoerveranstalter müssen verifziert werden. Und dann mit rollen vergeben für andere spieler/organizer/helfer im tournier.

Gruppenbildung, tournieranmeldung wenn ein tournier ausgeschrieben ist, wie gehen wir da vor?

Prod, test & dev envirement. CiCd pipeline, e2e tests automatisiert, testsuite verfollständigen.
Zeit im tournier konfigurieren
Pushups währen tournier
Sponsern einrichten
Request a feature
Bug report
```
