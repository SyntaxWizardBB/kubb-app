# ADR-0041: Push-getriebene kritische Frische, Delta-Catch-up & Freshness-Budget

- **Status**: Accepted (Owner-Entscheid 2026-06-22)
- **Date**: 2026-06-22
- **Amends**: ADR-0029 (Unified Messaging & Battery-Lifecycle) — **erweitert** dessen
  uniformes Regime um eine Kritikalitäts-Stufe, Push-getriebene Hintergrund-Frische für
  den kritischen Tier, Delta-/Cursor-Catch-up statt forward-only-CDC, und ein
  Freshness-Budget. **Supersedet 0029 nicht**: das v1-Regime (Polling gelöscht, genau
  eine Socket im Vordergrund, Hintergrund dunkel) bleibt die Basis.
- **Depends on**: ADR-0029, ADR-0021 (RealtimeChannel-Port/Refcount/Backoff), ADR-0026
  (anon-Broadcast `private:false`), ADR-0004 (Tier-Limits). Setzt den vorhandenen
  **Lamport-Counter** auf `tournament_matches` als Cursor-Basis voraus.
- **Bezug**: `docs/specs/realtime-sync-fixes-spec.md` (v1-Korrektheits-Fixes; dieses ADR
  ist das v2-Zielbild), `docs/plans/realtime-messaging/`.

> **Reines DESIGN-/Entscheid-Dokument.** Legt Regel und Zielbild fest, kein Code, keine
> Sprint-Roadmap. Umsetzung auf `feat/realtime-sync` nach den v1-Fixes.

## Kontext

ADR-0029 erreicht den Tag-Akku über ein **binäres Regime**: Vordergrund = gehaltene
WebSocket (frisch, aber Radio-Kosten inkl. ~30-s-Heartbeat), Hintergrund = 0 Sockets +
0 Timer (Akku gespart, **Frische = 0**). Der Push-Seam ist bewusst nur **gestubbt**;
solange er nicht lebt, gibt es im Hintergrund **keine** Updates — der User sieht
Änderungen erst beim App-Öffnen.

Das Tiefenaudit (2026-06-22, siehe Fixes-Spec) fand zusätzlich: CDC ist **forward-only
ohne Catch-up** (verpasste Events werden nie nachgespielt → Screens veralten nach
Hintergrund/Reconnect), die **Live-Rangliste hängt gar nicht am CDC**, und es gibt
**keine Priorisierung** relevanter Daten.

**Owner-Verschärfung:** Für **kritische** Daten — Punktestand/Score und Match-Status des
Turniers, an dem der User teilnimmt oder das er live ansieht — hat **Frische Vorrang vor
Akku, auch im Hintergrund**, ohne den Tag-Akku zu sprengen. Das ist mit dem binären
Regime nicht erreichbar; es braucht den richtigen Transport pro Zustand.

## Entscheidung

Vier Erweiterungen zu ADR-0029. Sie gelten **nur für den kritischen Tier**; der
Normal-Tier bleibt beim 0029-Standard.

### 1. Kritikalitäts-Stufe (zwei Tiers, deklarativ)

Jeder Concern/Channel-Key trägt eine Stufe (am `kubb_domain`-Key-Builder hinterlegt, nie
ad hoc):

| Stufe | Concerns | Garantien |
|---|---|---|
| **kritisch** | aktiver Match-Score, **Live-Rangliste**, Match-Status/Clock eines Turniers mit User-Bezug | Push-Wake im Hintergrund (§2), Delta-Catch-up (§3), engeres Freshness-Budget (§4), **nie stilles** Degradieren (Banner) |
| **normal** | Anmeldung, Check-in-Listen, Freunde, my-Teams/-Turniere, Stammdaten | 0029-Standard (CDC + 30-s-Fallback, **kein** Push, kein Banner) |

### 2. Push-getriebene Hintergrund-Frische (kritischer Tier)

Statt einer gehaltenen Socket im Hintergrund (deren Heartbeat das Radio wach hält) fährt
die App auf dem **OS-Push-Kanal** mit (FCM/APNs) — **eine** vom OS für **alle** Apps
unterhaltene, gebatchte Verbindung, marginale App-Kosten ≈ 0.

- Mechanik = der **bereits gelegte Seam** aus ADR-0029 fertig gebaut („one write, two
  wakes"): kritisches Event → `push_outbox` → FCM/APNs **data-message** → OS weckt die
  App kurz → **Delta-Fetch** (§3) → schläft wieder.
- **Disziplin (verbindlich):** Push **nur** für den kritischen, **niederfrequenten** Tier
  (dein Match ist dran, Resultat final) — **nie** für Anmeldungen/Listen. iOS drosselt
  Background-Data-Push hart; nur striktes Tiering hält den Pfad zuverlässig.
- **Akku:** kein eigener Hintergrund-Heartbeat → Hintergrund-Drain bleibt ≈ 0, aber
  kritische Updates kommen an. Das löst die 0029-Tension (Akku **vs.** Frische) auf.

### 3. Delta-/Cursor-Catch-up (ersetzt forward-only + Voll-Refetch)

Jede synchronisierte Tabelle trägt einen **monotonen Cursor** (Lamport-Counter — auf
`tournament_matches` vorhanden, wo nötig erweitern). Der Client persistiert pro Concern
den **zuletzt gesehenen Cursor**.

- Bei **Reconnect / Resume / Push-Wake**: ein „**changes since cursor X**"-Read holt
  **nur das Delta** — exakt, vollständig, billig.
- Ersetzt die „einmal voll refetchen"-Regel der Fixes-Spec; Voll-Refetch bleibt nur
  **Fallback**, wenn kein Cursor verfügbar ist.

### 4. Freshness-Budget (verallgemeinerte adaptive Kadenz)

Jeder Concern deklariert ein **Staleness-Budget** (max. tolerierte Veralterung). Das
System wählt den **billigsten** Mechanismus, der es einhält:
**Push (kritisch, Hintergrund) > offene Socket/CDC (Vordergrund) > adaptiver Poll
(Fallback)**. Ersetzt die Pauschal-30-s-Kadenz: laufendes Match eng, fertiges Match nie,
Anmeldung locker. Generalisiert die Kritikalitäts-Stufe zu einem prinzipiellen Regler.

### 5. Presence (optional, nicht verbindlich)

Supabase-Realtime-Presence als **Kür**: „beide Teams am Pitch anwesend → Match startbar",
Live-Zuschauerzahl, „Gegner trägt gerade ein". Nicht im kritischen Pfad; spätere Phase.

## Alternatives considered

- **Gehaltene Socket auch im Hintergrund** (für Frische): verworfen — Heartbeat hält das
  Radio wach, Tag-Akku bricht (Ziel B von 0029 verfehlt).
- **Forward-only CDC + Voll-Refetch** (Fixes-Spec v1): bleibt als **Fallback**, aber
  Delta-via-Cursor ist exakt **und** billiger.
- **Push für alle Events** (auch normal): verworfen — iOS-Drosselung + Akku; nur der
  kritische, niederfrequente Tier pusht.
- **Eigener Background-Service/Socket statt OS-Push**: verworfen — vervielfacht
  Wake-ups, sprengt Tier-Limits (ADR-0004), genau der Posten, den 0029 eliminiert.

## Consequences

### Positiv
- **Beide Ziele zugleich**: Tag-Akku **und** kritische Frische, auch im Hintergrund.
- Hintergrund-Drain bleibt ≈ 0 (kein eigener Heartbeat), kritische Updates trotzdem da.
- Delta-Catch-up: exakt + billig, kein „stale after resume".
- Freshness-Budget macht Kadenz **prinzipiell** statt ad hoc.

### Negativ
- **Push-Infra** (FCM/APNs, Token-Verwaltung, `push_outbox`-Fan-out) = echte Arbeit; die
  iOS-Drosselung erzwingt strikte Tier-Disziplin.
- **Delta** braucht verlässliche monotone Cursor **überall** (Lamport erweitern) +
  Konsistenz-/Lücken-Tests.
- Mehr bewegliche Teile → mehr Stellen für Kausal-Konsistenzfehler (gemischte Epochen).

### Neutral
- Das 0029-Regime (Polling gelöscht, 1 Socket Vordergrund, Hintergrund dunkel) bleibt
  **unverändert** die Basis; dieses ADR erweitert nur den kritischen Tier.
- Presence bleibt optional und ist kein Merge-Gate.

## Status-Notiz

Owner-Entscheid 2026-06-22, Design only. Umsetzung auf `feat/realtime-sync` **nach** den
v1-Fixes (`realtime-sync-fixes-spec.md`). Empfohlene Reihenfolge:
**(1)** v1-Fixes (Rangliste ans CDC, Catch-up, Robustheit) → **(2)** Delta-Cursor →
**(3)** Push-für-kritisch (Seam aus Stub holen) → **(4)** Freshness-Budget →
**(5)** Presence (optional).
