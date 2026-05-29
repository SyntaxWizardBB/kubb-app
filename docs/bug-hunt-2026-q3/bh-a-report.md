# Sprint-C Bug-Hunter A — Mini-Sweep Report

Scope: Sprint C Wave 2–4 — Visibility-Migration + RLS, Visibility-Settings-Picker,
Account-Delete-Wipe, Inbox-Cache + Stream, ADR-0010 / Account-Link, Bounded-Context /
PII / Test-Substanz.

Branch: `sprintC-bh-a` (read-only).

---

## BH-A-01 — Inbox-Cache wird beim signOut NICHT pro User entleert (Privacy/GDPR)
- **Severity:** P1
- **Datei:Zeile:** `lib/features/auth/application/auth_controller.dart:229–245` (signOut)
  + `lib/features/inbox/data/dao/inbox_messages_dao.dart:54` (`deleteForUser` definiert, aber kein Aufrufer)
- **Eintritt:** User A signiert ein, lädt Inbox-Cache, signiert aus; User B signiert anschließend auf demselben Gerät ein.
- **Begründung:** `InboxMessagesDao.deleteForUser` ist definiert, getestet, und in den DAO-Docs als
  "called on sign-out so the next account that signs in on the same device cannot see the previous
  user's messages through the local cache" beschrieben — wird aber nirgends im Production-Code
  aufgerufen (`grep -rn deleteForUser lib | grep -v dao_test` ist leer außer Test/Plan). `AuthController.signOut`
  räumt nur `cached_auth_session` und `keypairStorage` ab; die `inbox_messages`-Drift-Tabelle behält die
  alten Rows. Der Stream filtert per `userId.equals(...)`, also sieht B nichts; trotzdem liegen A's
  Subjects/Bodies auf Disk weiter, was bei einem User-Wechsel auf einem geteilten Gerät DSGVO Art. 17/25
  konterkariert (und bei einem Re-Sign-In von A stale Rows zeigt, die der Server zwischenzeitlich
  archiviert/gelöscht haben kann — siehe BH-A-05).

## BH-A-02 — `refreshFromRemote` reconciliert keine server-seitigen Löschungen/Archivierungen
- **Severity:** P1
- **Datei:Zeile:** `lib/features/inbox/data/inbox_repository.dart:71–79`
- **Eintritt:** Eine Inbox-Nachricht wird auf Gerät 2 archiviert (oder ein Friend Request via
  `friend_request_reject` gelöscht). Auf Gerät 1 öffnet der User die Inbox.
- **Begründung:** `refreshFromRemote` macht ausschließlich `upsertMany(messages)`. Es gibt KEIN
  `delete(... NOT IN (server_ids))`. Folge: Nachrichten, die der lokale Cache aus einer früheren
  Synchronisation kennt, aber die der Server (Filter `archived_at is null`) inzwischen ausschließt
  oder gelöscht hat, bleiben in `inbox_messages` und tauchen weiter im `watchByUser`-Stream auf
  (incl. unread-Badge via `inboxUnreadCountProvider`). Stale Friend-Request-Aufforderungen können so
  ewig im Inbox-Screen kleben. Tests in `inbox_repository_test.dart` decken den Stale-Row-Reconciliation-
  Fall nicht ab — sie testen nur Hydrate aus dem Cache und Cross-User-Filter.

## BH-A-03 — Visibility-Picker: Save schluckt fehlende Profile-Row stillschweigend, kein UI-Feedback
- **Severity:** P2
- **Datei:Zeile:** `lib/features/settings/presentation/widgets/profile_visibility_section.dart:87–93`
- **Eintritt:** User öffnet Settings, bevor sein `user_profiles`-Row angelegt ist (z.B. Anonymous-Keypair
  vor Account-Setup, oder Provider-Cache leer wegen ungültiger Session) und tippt eine Tier-Option.
- **Begründung:** `if (profile == null) return;` macht stillen No-Op — kein Snack, kein Error, keine
  Log-Zeile. UX-Lüge: Sheet schließt, Subtitle bleibt unverändert, User glaubt seine Wahl wurde
  übernommen. Mindestens ein Info-Snack ("Profil noch nicht angelegt …") oder ein
  Telemetrie-Event sollte feuern.

## BH-A-04 — Visibility-Picker: Optimistische Snackbar ohne `context.mounted`-Check nach await
- **Severity:** P3
- **Datei:Zeile:** `lib/features/settings/presentation/widgets/profile_visibility_section.dart:79–108`
- **Eintritt:** User selektiert eine Tier, navigiert noch während `repo.updateProfile`
  läuft per Hardware-Back/Push-Notification zurück, Widget wird unmountet.
- **Begründung:** `_save` cached `messenger` korrekt vor dem `await`, aber prüft nirgends
  `context.mounted` zwischen `await repo.updateProfile(...)` und `messenger.showSnackBar(...)`.
  Bei einem disposeten ScaffoldMessenger ist das in der Praxis tolerant (Messenger-Ref hält
  State), aber strikt nach Flutter-Pattern fehlt der Mounted-Check. Tests bestehen, weil
  `pumpAndSettle` nie unmountet.

## BH-A-05 — Inbox-Stream zeigt Nachrichten, die der Server bereits gelöscht hat (cross-device delete)
- **Severity:** P2
- **Datei:Zeile:** `lib/features/inbox/data/inbox_repository.dart:71–79` + `application/inbox_controller.dart:13–29`
- **Eintritt:** Friend Request wird vom Sender via `friend_request_reject` → DELETE entfernt
  (siehe `supabase/migrations/20260507000001_social_graph.sql:275–278`); auf dem Empfänger-Gerät
  hängt das `verification_request`-Inbox-Item weiter im Cache.
- **Begründung:** Siehe BH-A-02 — Refresh ist additiv. Server löscht die `friendships`-Row (und damit
  semantisch die Anfrage), aber das passende `user_inbox_messages`-Row wird bei Reject gar nicht
  serverseitig gelöscht (kein `DELETE FROM user_inbox_messages` in `friend_request_reject`). Auch
  ein archivierter Status würde im aktuellen Refresh-Pfad nicht durchschlagen. UX-Folge: der
  Empfänger sieht weiter eine "Annehmen/Ablehnen"-Aufforderung für eine nicht mehr existente
  Friendship → Server-Roundtrip beim Tap würde mit "no pending request" failen.

## BH-A-06 — Inbox-Polling: 1 s Timer ohne Debounce/In-Flight-Guard
- **Severity:** P2
- **Datei:Zeile:** `lib/features/inbox/application/inbox_controller.dart:39–50`
- **Eintritt:** Inbox-Screen offen, schwache Netzverbindung; `refreshFromRemote` dauert > 1 s.
- **Begründung:** `Timer.periodic(Duration(seconds: 1), …)` feuert unkonditional. Jeder Tick
  triggert einen frischen `refreshFromRemote(userId)`, unabhängig davon ob der vorige noch in
  flight ist. Folge: Burst von parallelen SELECTs auf `user_inbox_messages` + parallele
  drift-`upsertMany`-Batches. Bei einer 5-s-RTT akkumuliert man 5 In-Flight-Requests pro Open.
  Ist außerdem laut Doc explizit als "no provider invalidation involved" beworben — das ist
  korrekt, aber kostspielig. P1-Kandidat wenn man Server-Last bewertet.

## BH-A-07 — `ProfileVisibility.fromWire` fällt bei unbekanntem/null Wert auf `friendsOnly` statt `private`
- **Severity:** P1
- **Datei:Zeile:** `packages/kubb_domain/lib/src/profile/profile_visibility.dart:34–39`
- **Eintritt:** Server liefert eine neue (zukünftige) Tier ('public_friends'-Variante o.ä.) oder
  die Antwort enthält `profile_visibility: null` (z.B. wegen Cache-Race im PostgREST-Layer);
  Client zeigt "Nur Freunde" obwohl der echte Wert evtl. permissiver ist.
- **Begründung:** Defensive-Default-Direction ist falsch herum. Der Kommentar erklärt das Motiv
  ("client robust against a server-side migration adding a new tier") — aber die Privacy-Floor-
  Annahme aus dem User-Profile-Picker-Widget (line 42–48: "the friends-only floor so the UI
  never implies public") wird konterkariert, wenn der echte Server-Wert `public` war. Der
  defensive Default für eine UNBEKANNTE Tier muss `private` sein (most-restrictive), nicht
  `friendsOnly`. Sonst suggeriert die UI einen engeren Kreis als tatsächlich gesetzt ist —
  Hidden Privacy-Downgrade.

## BH-A-08 — Account-Link-Screen entspricht NICHT ADR-0010 (keine Credential-Liste, kein "missing"-Gating)
- **Severity:** P2
- **Datei:Zeile:** `lib/features/auth/presentation/account_link_screen.dart:33–123`
  + ADR-0010: `docs/adr/0010-identity-and-auth.md:64`
- **Eintritt:** User hat bereits Google verknüpft, öffnet den Account-Link-Screen.
- **Begründung:** ADR-0010 spezifiziert klar: "lists every linked credential for the current user,
  grouped by kind (Google, Apple, keypair). Each row shows the provider, the linked-at
  timestamp, and the credential's account hint" und "'Link Google' / 'Link Apple' actions are
  visible whenever the corresponding `user_credentials` row is missing for the active user".
  Der Screen rendert weder eine Credential-Liste, noch versteckt er den "Link Google"-Button
  wenn Google bereits verknüpft ist — ein zweiter Klick auf "Link Google" startet einfach
  einen redundanten `linkIdentity`-Flow, der serverseitig in einen Conflict läuft. Doku ↔ Code-Drift.

## BH-A-09 — `AccountUpgradeController.linkOAuth` macht keine Wire-Session-Pre-Check
- **Severity:** P2
- **Datei:Zeile:** `lib/features/auth/application/account_upgrade_controller.dart:26–45`
- **Eintritt:** Anonymous-Keypair-User, dessen Wire-JWT abgelaufen ist (z.B. nach Cold Start ohne
  `ensureWireSession`), klickt "Link Google".
- **Begründung:** Der Controller läuft `adapter.linkOAuthToCurrentUser(...)` ohne vorher
  `ensureWireSession`/`refreshSession` zu erzwingen. `linkIdentity` braucht die laufende Session;
  ohne JWT fehlt der `Authorization`-Header → linkIdentity returnt erfolgreich (öffnet OAuth-Web
  ohne Bindung) und die Anonymous-Identity wird stattdessen verworfen, was zu einem neuen
  `auth.users`-Row führen kann (ADR-0010 "Sign-in collision rule"). User-Daten droht zu fragmentieren.

## BH-A-10 — `account_deletion_controller.delete()` setzt State nicht zurück nach `done`, navigiert nicht aktiv
- **Severity:** P2
- **Datei:Zeile:** `lib/features/auth/application/account_deletion_controller.dart:18–62`
  + `lib/features/auth/presentation/delete_account_screen.dart:42–44`
- **Eintritt:** User löscht Account, der Router redirected via `authControllerProvider` zu `/sign-in`.
  User legt anschließend neuen Anonymous-Account an.
- **Begründung:** (a) `accountDeletionControllerProvider` ist `NotifierProvider` (kein autoDispose),
  d.h. der State bleibt auf `done()` über Sign-Outs hinweg im Container. (b) Der Screen hat keinen
  expliziten `GoRouter.go(AuthRoutes.signIn)`-Aufruf nach `done()` — die Navigation hängt einzig
  am Router-Refresh-Listener, der aus `authControllerProvider` propagiert. Wenn die Adapter-Stream-
  Propagation aus irgendeinem Grund verzögert oder gar nicht kommt (siehe BH-A-13), bleibt der User
  auf dem Delete-Screen mit "done"-State sitzen, ohne klares Re-Direct-Signal.

## BH-A-11 — `AccountDeletionController.delete()` verschluckt verstaute Server-Reaktion bei partial-fail
- **Severity:** P2
- **Datei:Zeile:** `lib/features/auth/application/account_deletion_controller.dart:52–61`
  + `lib/features/auth/data/supabase_auth_adapter_impl.dart:197–205`
- **Eintritt:** `fn_delete_current_account()` läuft erfolgreich (auth.users-Row weg), aber
  `_client.auth.signOut()` wirft danach (Netzwerk weg / SSL handshake fail beim global-signOut).
- **Begründung:** `deleteCurrentAccount` ruft erst die RPC, dann signOut. Wirft signOut, läuft der
  Catch-Block der Controller-`delete()`-Funktion → state = failed → Drift bleibt unangetastet (gut),
  aber der Server-Account ist DENNOCH WEG. User sieht "Fehler" und kann nicht mehr signIn-en (Account
  existiert nicht mehr), kann aber auch nicht retry (server schon down). Tests in
  `account_deletion_controller_test.dart` testen den Fail vor dem RPC, nicht den Fail
  zwischen RPC und drift-wipe. Mindestens müsste signOut hier in einen try/catch und die
  drift-wipe-Phase auch dann laufen, wenn signOut fehlschlägt — sonst hat der User einen
  toten Server-Account + lebenden lokalen Cache + intaktem privaten Schlüssel.

## BH-A-12 — `wipeAll()` läuft Reverse über `allTables`, aber FK-Order ist nicht garantiert
- **Severity:** P3
- **Datei:Zeile:** `lib/core/data/app_database.dart:125–131`
- **Eintritt:** Wenn jemand künftig eine neue Tabelle mit FK zu einer existierenden Drift-Tabelle
  hinzufügt UND `allTables` sie nach der Parent-Tabelle ausliefert.
- **Begründung:** Der Kommentar versichert "reverse order matters … child tables reference
  sessions which references players, and a restrict-action FK would refuse the delete". Aber
  `allTables` ist eine Drift-interne Reihenfolge, die nicht garantiert sortiert ist nach
  FK-Topologie — sie ist eher die Insertion-Order in `tables:`. Die jetzige `tables:`-Liste
  funktioniert per Zufall (players steht vor sessions, sessions vor session_events). Eine
  künftige Umsortierung der `tables:`-Liste killt den Wipe schweigend. Es gibt KEINEN
  `PRAGMA foreign_keys = ON`-Test im Test-File, nur ein "every drift-owned table is empty"-Assert,
  das auch bei Reihenfolgefehlern grün wäre, wenn keine FK-CHECKs aktiv sind. P3 weil SQLite
  per default foreign_keys = OFF hat — kann sich aber bei einer künftigen Default-Änderung
  zu P1 entwickeln.

## BH-A-13 — `delete()` lässt AuthController-Listener gegen `wipeAll`-Transaktion racen
- **Severity:** P2
- **Datei:Zeile:** `lib/features/auth/application/account_deletion_controller.dart:52–58`
  + `lib/features/auth/application/auth_controller.dart:302–332`
- **Eintritt:** `adapter.deleteCurrentAccount` ruft `_client.auth.signOut()` → emitted signed-out
  Event → `AuthController._onAdapterState` async-handler triggered → ruft `_dao.clear()`
  (=`delete from cached_auth_session`). Gleichzeitig läuft `database.wipeAll()` mit
  globaler Transaktion über alle Tables.
- **Begründung:** Drift serialisiert i.d.R. Transaktionen, aber zwischen einer outer
  transaction (`wipeAll`) und einem konkurrenten DAO-write gibt es keine explizite Lock-
  Ordering. Im schlimmsten Fall blockt die DAO-clear() bis wipeAll fertig ist, schreibt
  dann eine clear-Mutation auf eine Tabelle, die gerade leer ist → kein Datenverlust, aber
  ein zusätzlicher No-Op-Write. Kein Bug per se, aber die Architektur-Annahme "wir kontrollieren
  die Reihenfolge selbst" stimmt nicht: der AuthController reagiert AUTONOM auf den Auth-State-
  Event. Sauber wäre, AuthController.signOut() explizit VOR adapter.deleteCurrentAccount()
  auszurufen und dort die generation zu bumpen, statt sich auf die Stream-Propagation zu
  verlassen.

## BH-A-14 — `markRead` zerreißt Server-Timestamp und Local-Timestamp
- **Severity:** P3
- **Datei:Zeile:** `lib/features/inbox/data/inbox_repository.dart:85–94`
- **Eintritt:** Slow network: User markiert Nachricht als gelesen, Server-`now()` läuft um
  T+50ms, Client schreibt sich `DateTime.now().toUtc()` lokal mit dem Wert nach dem await ein.
- **Begründung:** Der Server-Update bekommt `DateTime.now().toUtc().toIso8601String()` (vor await),
  der lokale Stamp `DateTime.now().toUtc()` (nach await). Werte können bis zu Sekunden auseinander
  liegen. Subtil: der Server kann via `filter('read_at', 'is', null)` no-op'en (Idempotenz);
  in dem Fall hat der Server einen ALTEN `read_at`-Wert, der lokale Mirror den NEUEN.
  Bei einer späteren Reconcile-Logik (siehe BH-A-02) zerschießt das die Sortierung.

## BH-A-15 — `archive` löscht lokal vor der Server-Bestätigung gegen Konsistenz
- **Severity:** P3
- **Datei:Zeile:** `lib/features/inbox/data/inbox_repository.dart:101–109`
- **Eintritt:** User archiviert, Server-Update wirft (Netz weg) → `_dao.deleteById(id)` läuft
  trotzdem (kein guard).
- **Begründung:** Sequenz ist `await _client.from(...).update(...); await _dao.deleteById(id);` —
  wenn der `update` ein Future mit `Exception` zurückgibt, springt der throw raus und
  `deleteById` läuft nicht. Soweit OK. ABER: PostgrestException werden in einigen Pfaden
  als HTTP-200-mit-error-body ausgeliefert, je nach Supabase-Client-Version. Best-Practice
  ist explizites Error-Handling + Rollback. Kein Rollback existiert (kein Re-Insert bei
  späterem Refresh-Reconcile-Bug, siehe BH-A-02). P3, weil heutiger supabase_flutter Client
  PostgrestException als wirft.

## BH-A-16 — Account-Delete telemetry-emit verwendet User-ID-Prefix nur 8 Chars (gut), aber Stack-Traces im failed-State leaken `Exception.toString()`
- **Severity:** P3
- **Datei:Zeile:** `lib/features/auth/application/account_deletion_controller.dart:60` +
  `lib/features/auth/application/account_upgrade_controller.dart:43`
- **Eintritt:** Server returns Error mit Message wie `permission denied for user 'lukas-uuid…'`.
- **Begründung:** `AccountDeletionState.failed(reason: e.toString())` und
  `AccountUpgradeState.failed(reason: e.toString())` lassen die unbearbeitete Exception-Message
  in den State (und damit potenziell ins UI-Banner) durch. Supabase-Fehler enthalten
  manchmal user-Identifiers (E-Mail, OAuth subject). Die AuthTelemetry scrubt zwar — aber
  hier umgeht der UI-Pfad das Scrubbing komplett. P3, weil die Wahrscheinlichkeit gering ist
  und das UI-Banner ein generisches "Try again"-Label rendert, aber der State-Snapshot ist
  ein leaky Layer.

## BH-A-17 — Visibility-Update geht via UPDATE direkt auf `user_profiles` — Trigger / Cascade-Logic übersprungen
- **Severity:** P2
- **Datei:Zeile:** `lib/features/auth/data/cloud_profile_repository_impl.dart:74–87`
- **Eintritt:** Künftige Erweiterung des `user_profiles`-Updates um einen After-Update-Trigger
  (z.B. Audit-Log oder Match-Stats-Cache-Invalidation für friends-only-Listings).
- **Begründung:** Der Kommentar in `cloud_profile_repository_impl.dart:68–72` rechtfertigt
  den Direct-UPDATE damit, dass das Hash-Atom nichts mit Visibility zu tun hat. Korrekt — aber
  damit umgeht die Visibility-Änderung jegliche Trigger-Logic, die auf
  `fn_profile_update_with_hash` oder einer separaten RPC sitzen würde. Da es heute keine
  Trigger gibt, ist das kein aktiver Bug; ADR-0026 (Strategie A) sieht aber Cache-Invalidation
  für `public_*`-RPCs vor (siehe Migration-Header), und wenn die irgendwann an einen
  Visibility-Wechsel hängen müsste, ist der direkte UPDATE die falsche Stelle.

## BH-A-18 — `accountDeletionControllerProvider`-State persistiert über Sign-Outs hinweg
- **Severity:** P3
- **Datei:Zeile:** `lib/features/auth/application/account_deletion_controller.dart:18–20`
- **Eintritt:** User1 löscht Account → State = `done()`. User2 macht Anonymous-Signup,
  navigiert irgendwann zum Delete-Screen.
- **Begründung:** Provider ist `NotifierProvider`, kein `autoDispose`. Initial state in `build()`
  ist `idle()` — also beim erstem Build OK — aber wenn der Container weiterlebt (in der
  echten App: ja, ProviderScope ist app-global), bleibt der `done()`-State über sign-out
  hinweg. Der DeleteAccountScreen rendert `_ConfirmPage(hasError: false, deleting: false)`
  korrekt, der State wird nirgends gelesen, der einzige Effekt: `done()`-Branch aus
  `state.maybeWhen` zeigt nichts → der Screen bietet einen aktiven Delete-Button für User2,
  selbst wenn die Drift-DB von User1 nie korrekt gewipte wurde (siehe BH-A-13). State-Leak.

## BH-A-19 — `inbox_repository_test.dart` testet KEINE refresh-Reconcile-Pfade (Smoke-Tests, fehlt der wichtige Assert)
- **Severity:** P2
- **Datei:Zeile:** `test/features/inbox/data/inbox_repository_test.dart:39–157`
- **Eintritt:** N/A — Test-Substanz-Lücke.
- **Begründung:** Die Repository-Tests decken NUR den Hydrate-Pfad (`loadFromCache`,
  `watchForUser`, JSON-Roundtrip) ab. Sie testen NICHT:
  - `refreshFromRemote` mit zwischenzeitlich serverseitig gelöschten/archivierten Rows (BH-A-02).
  - User-Switch-Szenario: nach `deleteForUser('A')` werden A's Stream-Emissions korrekt leer.
  - `markRead`/`archive`/`reply` write-through-Konsistenz (kein Test).
  - Race-Test zwischen Hydrate-on-Open und Refresh-Concurrent (BH-A-06).
  Alle Mutate-Methoden des Repos sind ungetestet → der `_MockSupabaseClient` would-fail-on-any-
  access pattern erkauft strukturelle Garantie für den Read-Pfad, lässt den Write-Pfad blind.

## BH-A-20 — RLS-Policy `user_profiles_visibility_aware_read` checkt nur `auth.uid()` (nicht role) — anon bypass theoretisch denkbar
- **Severity:** P3
- **Datei:Zeile:** `supabase/migrations/20260601000020_profile_visibility.sql:51–71`
- **Eintritt:** Edge-Case wenn eine Service-Role-Connection ohne `TO authenticated`-Filter
  einen Anon-Token mit eingestelltem `sub` durchschleust.
- **Begründung:** Die Policy ist `TO authenticated`, also greift sie nur für den
  `authenticated`-Role. Anon wird nicht durch diese Policy gelassen, aber es gibt KEINE
  explizite Deny-Policy für `anon` — wenn künftig eine andere Policy versehentlich `TO
  authenticated, anon` erweitert würde, wäre die Visibility-Constraint wirkungslos. Der
  Test `profile_visibility_rls_test.sql:219–230` deckt den anon-Pfad explizit ab — gut, aber
  beobachtungspflichtig.

## BH-A-21 — Friend-Request-Reject räumt das Inbox-Item nicht ab (server-seitig)
- **Severity:** P2
- **Datei:Zeile:** `supabase/migrations/20260507000001_social_graph.sql:254–284`
- **Eintritt:** A sendet Friend-Request an B (Inbox-Row für B angelegt). A retracted oder B rejected.
- **Begründung:** Sowohl `friend_request_reject` als auch `friend_remove` löschen NUR die
  `friendships`-Row. Das `verification_request`-Inbox-Item für den jeweils anderen Seite
  bleibt im Server-Cache `user_inbox_messages` UND im Local-Cache. Der Empfänger sieht weiter
  die "Annehmen/Ablehnen"-Aufforderung. Verstärkt BH-A-05 — und ist ein eigenständiger
  Datenkonsistenz-Bug auf der Server-Seite (Sprint-C-W2-T?).

## BH-A-22 — `_ADIdle`/`_ADDone` Freezed states im Catch-Block: nach einem fail-Case fehlt der Recovery-Pfad
- **Severity:** P3
- **Datei:Zeile:** `lib/features/auth/application/account_deletion_controller.dart:44–62`
- **Eintritt:** User retried nach einem failed state.
- **Begründung:** Es gibt keine Methode, die den State explizit zurück nach `idle()` setzt
  (außer dem Reset durch einen NEUEN `delete()`-Call, der wieder bei `deleting()` startet).
  Im DeleteAccountScreen wechselt der User zwischen pages — wenn beim Klick auf Confirm
  ein Fail kommt, bleibt `failed.reason` im State; geht der User zurück zu `_Page.warning`
  und vorwärts, ist das `_ConfirmPage(hasError: true)`-Banner weiter sichtbar, obwohl der
  ack-Checkbox zurückgesetzt wurde. UX-Glitch.

---

## Summary

**Anzahl Befunde:** 22
**P0:** 0
**P1:** 3 (BH-A-01, BH-A-02, BH-A-07)
**P2:** 11 (BH-A-03, BH-A-05, BH-A-06, BH-A-08, BH-A-09, BH-A-10, BH-A-11, BH-A-13, BH-A-17, BH-A-19, BH-A-21)
**P3:** 8 (BH-A-04, BH-A-12, BH-A-14, BH-A-15, BH-A-16, BH-A-18, BH-A-20, BH-A-22)

### P0-Liste
Keine P0-Befunde.

### Top-3-Aufmerksamkeit (höchster Impact)
1. **BH-A-01** — Inbox-Cache überlebt signOut → DSGVO Art. 17 / 25 Verletzung auf shared Devices.
   `deleteForUser` existiert, getestet, doch nirgends aufgerufen. Trivial fixbar in
   `AuthController.signOut`.
2. **BH-A-07** — `ProfileVisibility.fromWire` defaultet bei unbekanntem/null Wert auf
   `friendsOnly` statt `private` → konterkariert die Privacy-Floor-Annahme, die das Settings-
   Section-Widget aus genau diesem Default macht. Hidden Privacy-Downgrade möglich, wenn
   Server-Antwort die Spalte verliert.
3. **BH-A-02 + BH-A-05 + BH-A-21** — Inbox-Refresh ist additiv (kein Delete-Sync). Kombiniert
   mit dem Umstand, dass `friend_request_reject` / `friend_remove` das Inbox-Item gar nicht
   abräumen, bleiben "Annehmen"-Buttons stehen für nicht-mehr-existierende Friendships;
   Server-Reaktion auf Tap ist hart fehlerhaft.
