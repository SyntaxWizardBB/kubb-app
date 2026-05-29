# Sprint C — Bug-Hunt Mini-Sweep, Tail-Findings

Datum: 2026-05-29. Nach Abschluss von Sprint C Wave 1-4 (Compliance + DSGVO-Substanz + Infra-Tail + Achievements-Persistenz). Drei Hunter-Agents parallel auf Wave-2-bis-4-Substanz.

Vollständige Reports:
- `docs/bug-hunt-2026-q3/bh-a-report.md` — Auth, Account-Lifecycle, Visibility, Inbox-Cache, Multi-OAuth-ADR
- `docs/bug-hunt-2026-q3/bh-b-report.md` — Anon-Realtime, Groups-Drop, Public-Tournament-Pipeline
- `docs/bug-hunt-2026-q3/bh-c-report.md` — Achievements-Drift, Badge-Trigger-Wiring, Privacy-Texte

## Zahlen

| Hunter | Total | P0 | P1 | P2 | P3 |
|---|---|---|---|---|---|
| BH-A | 22 | 0 | 3 | 11 | 8 |
| BH-B | 21 | 0 | 3 | 11 | 7 |
| BH-C | 13 | 2 | 3 | 5 | 3 |
| **Summe** | **56** | **2** | **9** | **27** | **18** |

Entschieden: alle 56 als Sprint-C-Tail dokumentieren, nicht in einer Hotfix-Wave nachfahren. Ein eigener Pre-TestFlight-Sprint adressiert die P0 und Privacy-relevanten P1 vor dem Submission-Lauf.

## P0 (2)

| ID | Datei | Befund |
|---|---|---|
| BH-C-01 | `lib/features/training/application/active_finisseur_notifier.dart` | `complete()` / `giveUp()` rufen `evaluateAfterSession` nicht auf. Finisseur-Badges (`first_penalty_kubb`, `finisseur_ace`) sind Dead-Code. |
| BH-C-02 | `lib/features/training/application/active_session_notifier.dart` `_fireBadgeEvaluation` | `BadgeTriggerContext` wird ohne `consecutiveDaysActive` und weitere Aggregate gebaut. Aggregate-Badges (`konstanz_king` etc.) können nie ausgelöst werden. |

## P1 — Privacy / DSGVO (4)

| ID | Datei | Befund |
|---|---|---|
| BH-A-01 | `lib/features/auth/application/auth_controller.dart` `signOut` | `InboxMessagesDao.deleteForUser` ist definiert und getestet, wird aber nirgends im Production-Code aufgerufen. User-Wechsel auf dem gleichen Gerät zeigt Inbox-Rows von User A bei User B. DSGVO Art. 17/25. |
| BH-A-07 | `packages/kubb_domain/lib/src/profile/profile_visibility.dart:34-39` | `fromWire` defaultet bei unbekanntem oder `null` Wert auf `friendsOnly` statt `private`. Privacy-Floor-Direction ist falsch — leere Werte vom Wire suggerieren der UI "Nur Freunde", obwohl der echte Wert eventuell permissiver ist. |
| BH-A-02 / BH-A-05 / BH-A-21 | `lib/features/inbox/data/inbox_repository.dart` + Friendship-RPCs | Inbox-Refresh ist rein additiv (`upsertMany`, kein DELETE-Sync). `friend_request_reject` und `friend_remove` räumen die `verification_request`-Items serverseitig nicht ab — stale Aufforderungen für gelöschte Friendships, harter Server-Error beim Tap. |
| BH-C-03 / BH-C-05 | `docs/legal/privacy-policy-de.md` + `lib/features/auth/presentation/sign_in_screen.dart` | Privacy-Text fehlt Visibility-Sektion aus W2-T2. Sign-In hat keine Links zu `/legal/privacy` und `/legal/imprint`, obwohl der Router beide whitelisted hat. |

## P1 — Funktional (5)

| ID | Datei | Befund |
|---|---|---|
| BH-C-09 | `lib/features/match/application/match_providers.dart` | Match-Pfad-Trigger-Context ignoriert Tournament-Refs, Friend-Status, Elo-Delta. 5 von 15 Match-Badges sind unerreichbar. |
| BH-B-01 | `lib/features/tournament/data/public_tournament_realtime.dart` | `SupabasePublicTournamentRealtime` ruft `channel..subscribe()` ohne Status-Callback und ohne Reconnect-Backoff. Nach Offline-Phase bleibt das Topic stumm. Referenz-Implementation in `supabase_realtime_channel.dart` zeigt korrekt. |
| BH-B-08 | `lib/features/tournament/data/public_tournament_polling_provider.dart` | `publicTournamentPollingProvider` und `publicLiveModeProvider` sind dead code. Der ADR-vorgesehene "Polling default, Live-Mode-Toggle" ist nicht erreichbar; jede Page startet sofort einen Realtime-Channel. |
| BH-B-10 | `test/features/tournament/data/public_tournament_realtime_test.dart` | `SupabasePublicTournamentRealtime` ist nur über `_FakeRealtime` getestet — kein Refcount, kein `removeChannel`, kein Whitelist-Production-Path. |
| BH-B-11 | `supabase/tests/` | Kein pgTAP-Test für die neuen Trigger-Funktionen, `public_tournament_is_visible` oder `public_tournament_realtime_topic`. Privacy-Anker nur konzeptionell gepinnt. |

## P2 (27) und P3 (18)

In den vollständigen Hunter-Reports. Highlights:

- **BH-B-04**: `private: false` nur als Channel-Default angenommen statt explizit gesetzt.
- **BH-B-05**: `assertPayloadColumnsWhitelisted` ist release-eliminiert — Privacy-Anker greift nur in Debug-Builds.
- **BH-B-09**: `PublicMatchScreen` ist nicht realtime-wired.
- **BH-B-13**: `consensus_round`-Bumps emittieren kein `match_status`-Event.
- **BH-B-16**: Pull+Push Out-of-Order-Race ohne Generation-Stamp.
- **BH-B-21**: `_FakeRealtime` deckt die `payload['payload']`-Envelope-Form nicht ab.

## Nächste Aktion

Pre-TestFlight-Sprint (vor Owner-Eskalations-Block "Bundle-ID + Apple-Cert + Support-Mail" auflöst):

1. **HF-1 (BH-C-01)** — Finisseur-Notifier an `evaluateAfterSession` anschließen.
2. **HF-2 (BH-C-02 + BH-C-09)** — Trigger-Contexts vollständig befüllen.
3. **HF-3 (BH-A-01)** — `deleteForUser`-Call in `signOut` + Account-Switch-Pfad einbauen.
4. **HF-4 (BH-A-07)** — `ProfileVisibility.fromWire` Default auf `private` umstellen.
5. **HF-5 (BH-A-02 + BH-A-21)** — Inbox-Refresh um DELETE-Sync ergänzen, serverseitiges `verification_request`-Cleanup.
6. **HF-6 (BH-C-03 + BH-C-05)** — Privacy-Text um Visibility-Sektion ergänzen, Sign-In-Footer auf `/legal/*` verlinken.
7. **HF-7 (BH-B-01)** — Status-Callback und Reconnect-Backoff im Realtime-Channel.
8. **HF-8 (BH-B-10 + BH-B-11)** — pgTAP-Test für Whitelist-Trigger + Production-Path-Test für `SupabasePublicTournamentRealtime`.

P2/P3 in den Hunter-Reports — Bewertung pro Sprint-Block.
