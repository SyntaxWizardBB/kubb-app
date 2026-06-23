# Spec — Realtime-Sync: Bugfixes & Frische-/Prioritäts-Erweiterung

**Status:** Verbindliche Implementierungs-Spezifikation & Quality-Gate.
**Geltung:** Die Realtime-/Messaging-Schicht (`feat/realtime-sync`, P0–P6 bereits live).
**Amendiert:** ADR-0029. Das **Design-Zielbild** (Push-für-kritisch, Delta-Catch-up,
Freshness-Budget, Kritikalitäts-Stufe) ist in **ADR-0041** festgelegt; **diese Spec ist
die v1-Korrektheits-Umsetzung + Bugfixes** auf dem Weg dorthin.
**Ziel (unverändert):** Akku hält den ganzen Tag **UND** kritische Daten
(Punktestand/Score) sind nie veraltet. Bei Konflikt hat **für kritische Daten die
Frische Vorrang**, sonst der Akku.

> **MUSS** = harte Anforderung. Datei:Zeile sind Anker aus dem Ist-Stand.

---

## 0. Vorab verifizieren (vor Umsetzung, MUSS)

1. **Lifecycle-Teardown** wirklich in `lib/app/app.dart` verdrahtet? (Audit-Agenten
   widersprüchlich: `realtime_lifecycle_controller.dart` existiert, aber ein Agent fand
   keinen Teardown-Aufruf.) Verifizieren, dass `paused/detached` Sockets wirklich
   abbaut.
2. **Migrations-Timestamps** `202612xx` sind die **monotone Sequenz-Konvention** des
   Projekts (kein echtes Datum) — bestätigen, dass die Ordering konsistent strikt
   aufsteigend ist (der „2026-12-31 = skippt auf Prod"-Befund ist vermutlich Fehlalarm).
3. **Prod-Publication** real prüfen (`pg_publication_tables`): welche Tabellen sind in
   `supabase_realtime`? (Hosted-vs-local-Risiko, ADR-0029 §Risiko.)

---

## 1. Kritische Frische-Fixes (Priorität 1)

### 1.1 Live-Rangliste an Realtime hängen (MUSS)
- **Heute (Bug):** `tournamentStandingsProvider` ist ein reiner `FutureProvider`,
  synthetisiert die Tabelle client-seitig aus Matches und ist **nicht** ans Match-CDC
  gehängt ([tournament_match_providers.dart:143](../../lib/features/tournament/application/tournament_match_providers.dart)). Score kommt rein → Rangliste rührt
  sich nicht.
- **Soll:** Der Standings-Provider MUSS bei jedem `tournament_matches`-CDC-Event
  invalidiert werden (Kanal existiert: `tournamentMatchListRealtimeProvider`,
  `tournament_realtime_provider.dart:22`). Standings ist ein **first-class
  Realtime-Concern**.

### 1.2 Catch-up nach Reconnect/Resume (MUSS — Zielbild ADR-0041)
- **Heute (Bug 1 & 8, `realtime_channel_lifecycle.dart`):** CDC ist **forward-only** —
  Verpasstes wird nie nachgespielt; nach Reconnect/Resume gibt es **keinen garantierten
  Catch-up**. Screen bleibt veraltet bis zum nächsten Live-Event.
- **Soll — Delta-Catch-up (primär, ADR-0041 §3):** Jeder synchronisierte Concern
  persistiert den zuletzt gesehenen **monotonen Cursor** (Lamport-Counter — auf
  `tournament_matches` vorhanden). Geht ein Kanal nach `errored`/`closed` wieder in
  `joined` (= Reconnect) ODER beim App-`resume`, holt der Client **das Delta seit
  Cursor X** — exakt und billig, **nicht** aufs nächste Event warten.
- **Fallback (kein Cursor verfügbar):** **genau einmal** voll refetchen
  (`invalidateSelf`/`refreshFromRemote`).
- Das deckt **beide** Lücken ab: Hintergrund→Resume **und** das ≥60-s-Error-Fenster.
- **Hinweis:** Die v1-Umsetzung darf mit dem Voll-Refetch starten; der Delta-Cursor ist
  die Ziel-Form (ADR-0041) und sollte folgen, sobald die v1-Fixes stehen.

---

## 2. Kritikalitäts-Stufe (MUSS — formalisiert in ADR-0041)

ADR-0029 behandelt alle Concerns gleich. **ADR-0041** führt **zwei Stufen** ein, als
Eigenschaft am Concern/Channel-Key (nicht ad hoc am Call-Site). Die v1-Fixes setzen den
**kritischen** Tier minimal um (Catch-up + Banner + engerer Fallback); **Push für den
kritischen Tier** (ADR-0041 §2) ist eine spätere Phase:

| Stufe | Concerns | Verhalten |
|---|---|---|
| **kritisch** | aktiver Match-Score, **Live-Rangliste**, Match-Status/Clock eines Turniers, an dem der User teilnimmt oder das er live ansieht | garantierter Catch-up-Refetch (§1.2); **kürzere** Fallback-Kadenz (z. B. 10 s statt 30 s); **niemals stilles** Degradieren → Banner (§3.2) |
| **normal** | Anmeldung, Check-in-Listen, Freunde, my-Teams/-Turniere | Standard-CDC + 30-s-Fallback, kein Banner-Zwang |

- **MUSS:** Score/Rangliste sind **kritisch** — für sie hat Frische Vorrang vor Akku
  (engeres Fallback, garantierter Catch-up). Anmeldung ist **normal**.
- Die Stufe ist deklarativ pro `kubb_domain`-Channel-Key-Builder hinterlegt.

---

## 3. Fallback-Abdeckung & „Live degradiert"-Signal (MUSS)

### 3.1 Participants/Check-in Fallback-Gate (MUSS)
- **Heute (Bug 6):** Der Participants-CDC (`tournament_participants`, Check-in) hängt
  **nicht** im generalisierten `realtimePollingFallbackProvider`. Fällt der Kanal
  ≥60 s aus, ist Check-in-Frische = 0.
- **Soll:** Participants/Check-in in das generalisierte Fallback-Gate einhängen (wie
  Matches/Bracket).

### 3.2 „Live unterbrochen"-Banner (MUSS, nur kritische Screens)
- **Heute (Bug):** Fällt CDC aus (Fallback aktiv oder Kanal errored), sieht der User
  **nichts** — stille Veralterung auf Live-Screens.
- **Soll:** Kritische Screens (Live-Rangliste, Match-Detail, Veranstalter-Dashboard)
  zeigen ein dezentes **„Live unterbrochen / aktualisiere …"**-Banner, solange der
  Kanal nicht `joined` ist; es verschwindet beim Reconnect (+ Catch-up §1.2).

---

## 4. Robustheits-Bugfixes (MUSS)

| # | Bug | Ort | Fix |
|---|---|---|---|
| 4.1 | CDC-Callback feuert nach `dispose`/`close` → „StreamController is closed" | [supabase_realtime_channel.dart:63](../../lib/core/data/realtime/supabase_realtime_channel.dart) | `disposed`-Check vor `changeController.add()` |
| 4.2 | `close()` nicht in try/catch → uncaught async exception beim Teardown | [realtime_channel_lifecycle.dart:102](../../lib/core/data/realtime/realtime_channel_lifecycle.dart) | `close()` defensiv kapseln |
| 4.3 | Fallback-Gate-Race: errored↔joined-Flackern → doppelte Timer / Schreiben in geschlossenen Controller | [realtime_fallback_provider.dart:95](../../lib/features/tournament/application/realtime_fallback_provider.dart) | Single-flight-Timer; `controller.isClosed`-Guard vor `add` |
| 4.4 | Backoff-Index resettet nicht bei manuellem `closeRef` → überspringt 1s/2s-Stufen | [realtime_channel_lifecycle.dart:136](../../lib/core/data/realtime/realtime_channel_lifecycle.dart) | `backoffIndex` bei `joined`/manuellem Close zurücksetzen |
| 4.5 | Broadcast-Controller-Leak bei fehlgeschlagenem Subscribe (refCount bleibt >0, Zombie) | [public_tournament_realtime.dart:220](../../lib/features/tournament/data/public_tournament_realtime.dart) | refCount-Decrement / Cleanup auch im Fehlerpfad |

---

## 5. Akzeptanzkriterien / Quality-Gates (nachprüfbar)

**5.1 Rangliste live:** Match finalisiert auf Gerät B → auf Gerät A aktualisiert sich
die Rangliste in **<1 s**, **ohne** manuellen Reload.

**5.2 Resume-Catch-up:** App auf Gerät A in den Hintergrund; Score ändert sich
serverseitig; App resumen → Rangliste/Match zeigt den neuen Stand **sofort beim
Resume**, nicht erst beim nächsten Event.

**5.3 Error-Fenster-Catch-up:** Kanal ~70 s künstlich `errored`, dann Reconnect → beim
ersten `joined` wird **einmal** refetcht (Daten frisch), ohne aufs nächste Event zu
warten.

**5.4 Kein Dispose-Crash:** schnelles Rein/Raus-Navigieren auf Turnier-Screens unter
Last → **keine** „StreamController closed"-Exceptions.

**5.5 Fallback-Gate stabil:** Kanal schnell errored↔joined flackern lassen → **genau
ein** Fallback-Timer, kein Doppel-Polling, kein Schreiben in geschlossenen Controller.

**5.6 Check-in-Fallback:** Participants-Kanal ~70 s killen → Check-in aktualisiert sich
weiter über den 30-s-Fallback (Frische ≠ 0).

**5.7 Degraded-Banner:** Kanal killen → kritischer Screen zeigt „Live unterbrochen";
nach Reconnect verschwindet es und die Daten sind frisch (Catch-up).

**5.8 Priorität:** Im Fallback-Modus aktualisiert sich der **Score** (kritisch) in der
kürzeren Kadenz; **Anmeldung** (normal) in 30 s.

---

## 6. Reihenfolge der Umsetzung (empfohlen)

1. §1.1 Rangliste ans Match-CDC (kleiner Fix, größter spürbarer Effekt).
2. §1.2 Catch-up-Refetch-Regel (Reconnect + Resume) — der zentrale Frische-Baustein.
3. §4 Robustheits-Bugs (verhindern Crashes/Leaks unter Last).
4. §3 Fallback-Abdeckung + Degraded-Banner.
5. §2 Kritikalitäts-Stufe (formalisieren, sobald 1–4 stehen).

---

## 7. Offene Punkte

- **Background-Frische (geplant, ADR-0041 §2):** Echte Out-of-app-Aktualität für den
  kritischen Tier kommt über **Push** (FCM/APNs data-message als Wake) + Delta-Fetch.
  Zielbild steht in ADR-0041; Umsetzung nach den v1-Fixes. Bis dahin gilt bewusst
  ADR-0029 (Hintergrund-Frische = 0).
- **OFFEN-1 (Kausale Konsistenz):** Im Fallback/Delta können gemischte Stände entstehen
  (alter Score, neuer Status). Lamport-Epoche als Konsistenz-Constraint prüfen
  (Detail-Design in ADR-0041-Umsetzung).
