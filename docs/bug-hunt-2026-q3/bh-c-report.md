# Bug-Hunter C — Sprint C Mini-Sweep (Achievements + Legal)

Branch: `sprintC-bh-c`
Scope: Achievements-Drift-Persistenz (W4), Badge-Trigger-Wiring (W4),
Privacy/Imprint-Texte + Legal-Routing (W1).
Mode: NUR Analyse, kein Fix.

---

## Befunde

### BH-C-01 — Finisseur-Sessions feuern KEINE Badge-Evaluation
**Severity:** P0
**Datei:** `lib/features/training/application/active_finisseur_notifier.dart:208-215` (`complete()`), `:160-167` (`giveUp()`)
**Eintritt:** Spieler beendet eine Finisseur-Session (Stocks alle, King getroffen,
oder Aufgabe). `complete()` / `giveUp()` rufen ausschließlich
`_repo.markCompleted(...)` und setzen `state = AsyncData(null)`. Es gibt KEINEN
Call auf `badgeUnlockListenerProvider.evaluateAfterSession(...)`.
**Begründung:** Die Badges `first_penalty_kubb` (Trigger:
`ctx.finisseurPenalties >= 1`, `badge_trigger.dart:109-113`) und
`finisseur_ace` (Trigger: `ctx.finisseurSuccesses >= 10`, `:176-180`)
können produktiv NIE freigeschaltet werden. Die einzige Stelle, die
`finisseurPenalties` oder `finisseurSuccesses` befüllen müsste, ist der
fehlende Hook. Sprint-C-W4-Akzeptanzkriterium "Finisseur-Badges
funktional" verletzt.

### BH-C-02 — Trigger-Kontext aus Session-Pfad lässt fast alle Aggregate auf 0
**Severity:** P0
**Datei:** `lib/features/training/application/active_session_notifier.dart:99-104`
**Eintritt:** Beliebige Sniper-Session wird abgeschlossen.
`_fireBadgeEvaluation` baut
`BadgeTriggerContext(sniperHits: …, sniperMaxStreak: …, heliHits: …,
distinctDistances: …)`. Alle anderen Felder (`consecutiveDaysActive`,
`matchesPlayed`, `tournamentWins`, `seasonsParticipated`, `friendsCount`,
`eloRank`, `finisseurPenalties`, `finisseurSuccesses`) bleiben default 0.
**Begründung:** Konsequenz: `konstanz_king` (`consecutiveDaysActive >= 7`,
`badge_trigger.dart:127-131`) wird NIE über den Session-Pfad ausgelöst,
obwohl der Trigger laut Badge-Beschreibung explizit "Trainiere 7 Tage in
Folge" prüft — und der Session-Complete-Hook der einzige Eintrittspunkt
ist. Es existiert in der ganzen App kein Code, der `consecutiveDaysActive`
je auf > 0 setzt → Badge ist Dead-Code. Gleiches gilt für `season_participant`,
`elo_top_100`, `first_tournament_win`, `tournament_veteran`, `first_friend`:
keine Aggregate-Berechnung → keine Trigger-Auslösung.

### BH-C-03 — Privacy-Text enthält keinen Visibility-Hinweis (DSGVO Art. 13 Buchst. e)
**Severity:** P1
**Datei:** `docs/legal/privacy-policy-de.md` (komplett)
**Eintritt:** Datenschutzerklärung wird über `/legal/privacy` aufgerufen.
**Begründung:** Sprint C W2-T2 hat `ProfileVisibility {public, friendsOnly,
private}` implementiert (`packages/kubb_domain/lib/src/profile/profile_visibility.dart`,
Migration `20260601000020_profile_visibility`). Die Privacy-Erklärung
nennt weder die Visibility-Stufen noch die Empfängerkategorien (Public:
weltlesbar; FriendsOnly: bidirektional verifizierte Freunde; Private:
Owner). Der Brief verlangt Konsistenz. DSGVO Art. 13 Abs. 1 lit. e
("Empfänger oder Kategorien von Empfängern") ist damit unvollständig
adressiert.

### BH-C-04 — `LegalMarkdownBody` verschluckt Mixed-Quote-Blocks
**Severity:** P2
**Datei:** `lib/features/legal/presentation/widgets/legal_markdown_body.dart:40-46`
**Eintritt:** Ein Block startet mit `> ` und enthält in nachfolgenden Zeilen
auch Nicht-Quote-Text. Aktuell wird der gesamte Block als Quote
gerendert (Branch trifft auf `block.startsWith('> ')`), aber bei
Quote-Zeilen wird `> ` per `.substring(2)` entfernt, normale Zeilen
bleiben unangetastet — und werden mit ` ` zusammengefügt.
**Begründung:** Akzeptiert man mehrzeilige Quote-Absätze in den
Owner-Eskalation-Blöcken, läuft das heute zufällig durch, weil die
Owner-Sektionen homogen `> `-präfixiert sind. Sobald Lukas eine
Mischzeile (`>` + Nicht-Quote-Folgezeile) ergänzt, wird die Ausgabe
inkonsistent. Keine reine Regression, aber fragile Render-Regel — und
es existiert KEIN Test für `LegalMarkdownBody`.

### BH-C-05 — Sign-In-Screen verlinkt nicht zu `/legal/privacy` und `/legal/imprint`
**Severity:** P1
**Datei:** `lib/features/auth/presentation/` (gesamter Sign-In-Flow)
**Eintritt:** Suche `grep -rn "legal|/legal/|Datenschutz|Impressum"
lib/features/auth/presentation/` liefert nichts.
**Begründung:** Der Router-Whitelist enthält `/legal/privacy` und
`/legal/imprint` (`lib/app/router.dart:85-86`) gerade deshalb, damit
Pre-Sign-Up- und Store-Review-User die Texte sehen. In den Settings
sind beide Links vorhanden (`app_section.dart:174,183,187`), im
Sign-In-/Onboarding-Flow fehlen sie aber komplett. Damit ist die
Disclosure-Pflicht zum Erst-Hinweis (Art. 13 DSGVO "zum Zeitpunkt
der Erhebung") UI-seitig nicht erfüllt — der Whitelist-Eintrag bleibt
ohne UI-Anker tot.

### BH-C-06 — Router-Redirect lässt JEDES `/legal/*` durch, nicht nur die zwei
**Severity:** P2
**Datei:** `lib/app/router.dart:118-120`
**Eintritt:** Browser-Navigation auf `/legal/foobar` (nicht definierte
Sub-Route).
**Begründung:**
```dart
if (state.matchedLocation.startsWith('/legal/')) {
  return null;
}
```
Die Whitelist `_publicRoutes` enthält explizit nur `/legal/privacy` und
`/legal/imprint`. Der `startsWith('/legal/')`-Guard ist breiter und
umgeht den exakten Whitelist-Check. Heute folgenlos (keine weitere
Route definiert → 404 von GoRouter), aber inkonsistent: alle anderen
Public-Routes laufen über `_publicRoutes.contains(loc)`. Drift in der
Whitelist-Disziplin (R20-F-04).

### BH-C-07 — Pin-Test fehlt `score_submission_outbox`-Tabelle
**Severity:** P2
**Datei:** `test/core/data/app_database_test.dart:41-51`
**Eintritt:** Pin-Test "all expected tables exist after migration".
**Begründung:** Set enthält `players, sessions, session_events,
app_settings_table, finisseur_stick_events, cached_auth_session,
tournament_score_drafts, inbox_messages, badge_unlocks`. Fehlt:
`score_submission_outbox` (in `app_database.dart:11` und
v6-Migration `:94-96`). Eine versehentliche Entfernung der Tabelle
würde der Pin-Test nicht fangen. Schema-Version (8) und
`badge_unlocks` sind korrekt — Sprint-C-W4-Drift-Tabelle ist also
korrekt gepinnt; nur die ältere Outbox ist Lücke.

### BH-C-08 — `_fireBadgeEvaluation` im Match-Pfad blockiert `proposeResult`-Return
**Severity:** P2
**Datei:** `lib/features/match/application/match_providers.dart:124-127`
**Eintritt:** Spieler bestätigt das Match-Ergebnis. `proposeResult`-Future
`await`tet `_fireBadgeEvaluation`, das selbst `listForCaller()` (RPC
Roundtrip) + `listUnlocksFor` (DB) + ggf. `recordUnlock` (DB) tut.
**Begründung:** Der try/catch-Wrapper schützt nur vor Exceptions, NICHT
vor Slow-Path-Blocking. Bei flakey Supabase-RPC hängt die UI auf dem
Ergebnis-Bestätigen-Button bis Timeout. Brief verlangt explizit
"kein Block bei Fehler" — Exceptions sind abgedeckt, Latenz aber nicht.
Mit `unawaited(...)` oder `Future.microtask` als Fire-and-Forget
hätte man das Trigger-Wiring außerhalb des kritischen Pfads.
ActiveSessionNotifier hat dieselbe Struktur (`await
_fireBadgeEvaluation(s)` in `complete()`, `active_session_notifier.dart:73`).

### BH-C-09 — Trigger-Kontext aus Match-Pfad ignoriert Tournament/Friend/Elo-Counter
**Severity:** P1
**Datei:** `lib/features/match/application/match_providers.dart:139-149`
**Eintritt:** Jede Match-Finalisierung.
**Begründung:** `_fireBadgeEvaluation` setzt nur `matchesPlayed` und
`matchesWon`. Damit funktionieren nur `first_match` und `matches_50`.
`elo_top_100`, `first_tournament_win`, `tournament_veteran`,
`first_friend`, `season_participant` haben keinen Aggregate-Provider
und können NIE ausgelöst werden. Verwandt mit BH-C-02, hier explizit
für den Match-Pfad. Effekt: 5 von 15 Badges produktiv nicht erreichbar
über den im Sprint vorhandenen Triggerpfad.

### BH-C-10 — `PrivacyPolicyScreen.loaderOverride` ist statisch-mutable, Cross-Test-Leak möglich
**Severity:** P2
**Datei:** `lib/features/legal/presentation/privacy_policy_screen.dart:16`
(und symmetrisch `imprint_screen.dart`)
**Eintritt:** Test überschreibt `loaderOverride`, vergisst Reset in
`tearDown`. Folgender Test sieht weiterhin den Fake.
**Begründung:** `static Future<String> Function() loaderOverride =
loadPrivacyPolicyDe;` ist Prozess-global. Korrekter wäre ein
DI-Loader (Provider / Constructor-Injection). Für die Auslieferung
unkritisch, für Test-Stabilität fragil — und der StatelessWidget-Konvention
widersprechend ("widget-config über Konstruktor, nicht Statics").

### BH-C-11 — `BadgeUnlockListener._evaluate` zwingt `sourceSessionId` zu Non-Null
**Severity:** P3
**Datei:** `lib/features/achievements/application/badge_unlock_listener.dart:57-87`
**Eintritt:** Hook für ein Aggregate-Badge ohne Session-Bindung (laut
`Badge.sourceSessionId`-Doc bewusst nullable, z. B. Saisonteilnehmer).
**Begründung:** `BadgeMatchSummary.sourceMatchId` und
`BadgeSessionSummary.sourceSessionId` sind `String` (non-null). Der
Listener-Parameter `sourceSessionId: String` (Zeile 59) erzwingt
ebenfalls non-null. Die Drift-Spalte und das Domain-Model (`badge.dart:83`)
sind aber nullable und kommentieren explizit "nicht jeder Badge ist an
eine Session gebunden". Architektonische Inkonsistenz — heute nicht
ausgelöst, da nur Match/Session-Hooks existieren, aber bei
Saison/Friend-Aggregaten kein Hook-Pfad möglich (man müsste eine
Dummy-Id setzen).

### BH-C-12 — `BadgeCatalog.triggerFor` ohne Default-Pfad-Test gegen Catalog-Drift
**Severity:** P3
**Datei:** `packages/kubb_domain/lib/src/achievements/badge_catalog.dart:159-194`
**Eintritt:** Neue Badge-Definition wird in `all` ergänzt, in
`triggerFor`-Switch aber vergessen.
**Begründung:** `BadgeCatalog.evaluate` (`:148-149`) tut
`if (trigger == null) continue;` — die fehlende Verdrahtung führt zu
einem stillen Drop, NICHT zu einem Test-Failure. Es gibt im Repo
keinen Pin-Test à la "for every Badge in BadgeCatalog.all, triggerFor
liefert nicht null". Risiko für künftige Wave: stilles Dead-Badge.

### BH-C-13 — `wipeAll` löscht Achievements bei Sign-Out NICHT (nur bei Account-Deletion)
**Severity:** P3
**Datei:** `lib/features/auth/application/auth_controller.dart:229-246`
**Eintritt:** User A signed out → User B signed in auf gleichem Device.
**Begründung:** `signOut()` löscht nur `_dao.clear()` (CachedAuthSession)
und Keypair. `badge_unlocks`-Rows bleiben. DAO scopt korrekt per
`userId.equals(userId)` (`badge_unlocks_dao.dart:36, 46`), also kein
Cross-User-Leak in der Anzeige. Aber: wenn User A wieder signed in,
sieht er seine Badges sofort wieder — was vermutlich gewollt ist
(Inventar überlebt Sign-Out). Brief fragt "Cross-User-Leak möglich?" —
**Antwort: nein**, aber dokumentiere die Strategie. Die DAO-Doc-Comment
(`:11-12`) sagt wörtlich "the wipe-on-sign-out path runs against the
whole database", was so nicht stimmt: `wipeAll` läuft NUR bei
`AccountDeletionController` (`account_deletion_controller.dart:54`),
NICHT bei Sign-Out. Doc-Drift gegenüber Implementation.

---

## Summary

**Anzahl Befunde:** 13 (P0: 2, P1: 3, P2: 5, P3: 3)

**P0-Liste:**
- BH-C-01 — Finisseur-Sessions feuern keine Badge-Evaluation
  (`active_finisseur_notifier.dart:160-215`). 2 Badges
  (`first_penalty_kubb`, `finisseur_ace`) sind Dead-Code.
- BH-C-02 — Session-Trigger-Context lässt `consecutiveDaysActive` &
  Co. auf 0; `konstanz_king` und weitere Aggregate-Badges nie ausgelöst
  (`active_session_notifier.dart:99-104`).

**Top-3 P1:**
- BH-C-09 — Match-Trigger-Context ignoriert Tournament/Friend/Elo-Counter
  → 5/15 Badges nicht erreichbar (`match_providers.dart:139-149`).
- BH-C-03 — Privacy-Text fehlt Visibility-Hinweis (W2-T2-Drift).
- BH-C-05 — Sign-In-Flow verlinkt nicht zu Privacy/Imprint trotz
  Whitelist-Eintrag.
