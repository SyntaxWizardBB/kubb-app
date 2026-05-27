# M4 Demo-Script — Realtime-Dashboard, Spectator-View, Offline-Outbox

> Dauer: 25–35 Min
> Setup: Tablet (Veranstalter, Owner-Account) plus zwei Phones (Spieler A, Spieler B), ein Zuschauer-Phone (Inkognito-Browser, nicht eingeloggt)
> Stand: 2026-05-27

## Pre-Demo-Checklist

Spätestens 30 Min vor Demo-Start:

- **Web-Build-Status**: `flutter build web --release` erfolgreich, Spectator-URL unter `https://kubb.app/public/tournament/:id` erreichbar (R-M4-G1, R-M4.2-1). Bei WASM-Spike-Failure: HTML-Renderer-Build als Fallback bereitstellen.
- **Realtime-Connect-Test**: Tablet plus beide Spieler-Phones öffnen ein Test-Turnier, `RealtimeStateBanner` zeigt "Live" auf allen drei Geräten (R-M4.1-1). Kein "Polling aktiv"-Banner.
- **Flugmodus-Toggle**: Auf dem Score-Eingabe-Phone den Flugmodus einmal an und wieder aus toggeln, prüfen ob `connectivity_plus` den Wechsel meldet (R-M4.2-3-Folge, R-M4.3-Toggle-Trägheit). Bei trägem Toggle: WLAN-Disconnect via Android-Settings als Backup.
- **Pro-Tier-Upgrade-Option**: Supabase-Projekt auf Pro-Tier upgegradet (~$25 / Monat) oder Upgrade-Knopf griffbereit, falls Free-Tier-Connection-Limits während der Demo greifen (Demobarkeits-Risiko-Bewertung Punkt 1).
- **Seed**: Round-Robin-Turnier "Demo M4" mit acht Teams läuft, vier Pitches sind in Status `in_progress`, ein Match steht auf `disputed` für den Konflikt-Schritt.

## Demo-Flow

### Schritt 1: Veranstalter öffnet Live-Dashboard auf Tablet (3 Min)

**Aktion**: Owner öffnet auf dem Tablet das Turnier "Demo M4" und tippt auf "Live-Dashboard".

**Erwartung**: `tournament_live_dashboard_screen` rendert ein Grid mit einer Karte pro Pitch. Farbcodes sichtbar: drei Pitches grün (laufend, frisch aktualisiert), ein Pitch gelb (Stillstand > 2 min), ein Pitch rot (`disputed`). `RealtimeStateBanner` zeigt "Live". FR-LIVE-1 erfüllt.

### Schritt 2: Zwei Spieler-Geräte registrieren parallel Sätze (4 Min)

**Aktion**: Spieler A trägt auf Phone A einen Set-Score für Pitch 1 ein, Spieler B für Pitch 2. Beide drücken "Absenden" innerhalb von zwei Sekunden.

**Erwartung**: Beide Submissions gehen sauber durch die `tournament_submit_set_score`-RPC. Auf den Phones erscheint "wartet auf Bestätigung Gegner" bzw. der Konsens-Schritt aus M1. Keine Outbox-Pending-Anzeige (online-Pfad).

### Schritt 3: Realtime-Update auf Dashboard ohne Refresh (2 Min)

**Aktion**: Owner schaut auf das Tablet, ohne pull-to-refresh zu drücken.

**Erwartung**: Die Dashboard-Karten für Pitch 1 und Pitch 2 zeigen die neuen Set-Stände innerhalb von <2 s (LTE-Bedingung aus architecture.md §11 Punkt 2). Status-Farbe bleibt grün. FR-LIVE-2 erfüllt, kein Polling-Tick im Provider-Log (verifizierbar über DevTools, optional).

### Schritt 4: Public-Link via QR auf Zuschauer-Phone (3 Min)

**Aktion**: Owner öffnet auf dem Tablet den Share-Sheet des Turniers, lässt den QR-Code für `https://kubb.app/public/tournament/:id` anzeigen. Zuschauer-Phone scannt den QR im Inkognito-Browser.

**Erwartung**: `public_tournament_screen` lädt ohne Login, zeigt Spielplan, Live-Rangliste und Bracket. Default ist Polling alle 10 s (Spectator-Default per R-M4.2-3). Owner tippt auf dem Zuschauer-Phone "Live-Modus aktivieren" → Banner wechselt auf "Live", Realtime-Subscribe greift. FR-PUB-1, FR-PUB-2, FR-PUB-3, FR-PUB-11 erfüllt.

### Schritt 5: Offline-Modus, Score-Eingabe, Pending-Indicator (5 Min)

**Aktion**: Spieler A schaltet Phone A auf Flugmodus. Trägt zwei weitere Set-Scores für Pitch 1 ein.

**Erwartung**: `connectivity_plus` meldet `offline`, die Outbox nimmt beide Submissions auf (Lamport-Counter monoton inkrementiert). UI zeigt "ausstehend, wird übertragen sobald online" pro Eintrag (architecture.md §4.3, Sequence-Schritt). Tablet-Dashboard bleibt unverändert — die Submissions sind noch nicht synchronisiert. DSCORE-94..-104 erfüllt.

### Schritt 6: Online, Sync, Indicator weg (3 Min)

**Aktion**: Spieler A deaktiviert Flugmodus.

**Erwartung**: `connectivity_plus` meldet `online`, Outbox-Flush startet binnen 2 s. Beide Submissions gehen durch, Server idempotency-Index lässt sie nur einmal landen. Pending-Indicators verschwinden auf Phone A. Tablet-Dashboard und Zuschauer-Phone aktualisieren sich live auf den neuen Stand (Realtime). FR-LIVE-10 erfüllt.

### Schritt 7: Konflikt simulieren — Stale-Round, Banner, Erneut-eingeben (5 Min)

**Aktion**: Vor der Demo wird Phone B online auf Pitch 1 ein Score-Update absetzen, während Phone A noch im Flugmodus ist. Phone A wird dann mit einer veralteten `consensus_round` aus dem Flugmodus zurückkehren. Alternativ: Owner triggert das Szenario manuell über die Test-Action "Stale-Round simulieren" im Debug-Menü.

**Erwartung**: Outbox-Flush auf Phone A scheitert mit `stale_round`-Fehler vom Server (Idempotency-Index erkennt Round-Mismatch). UI zeigt Konflikt-Banner "Stand hat sich geändert, bitte erneut eingeben" mit Button "Eingabe öffnen" (R-M4.3-3-Mitigation). Spieler A öffnet den Score-Sheet erneut, sieht den aktuellen Server-Stand, gibt seinen Score neu ein, sendet ab. Banner verschwindet. Owner-Abnahme M4 abgeschlossen.

## Demobarkeits-Risiken

- **R-M4-G1 Web-WASM-Spike**: Falls der Web-Build im WASM-Modus crasht, vor der Demo auf HTML-Renderer (`--web-renderer html`) zurückfallen. Spectator-Schritt 4 darf nicht an einem Build-Bug scheitern.
- **R-M4.2-3 Flugmodus-Toggle**: Android-Toggle ist auf manchen Geräten träge. Backup: WLAN manuell in den System-Settings aus- und einschalten. Vor Demo am genutzten Phone testen.
- **R-M4.1-1 Realtime-WS**: Free-Tier-Connection-Limits oder Supabase-Outage können den Live-Pfad killen. Pre-Demo-Connect-Test plus Pro-Tier-Upgrade-Option (Demobarkeits-Risiko-Bewertung Punkt 1).

## Backup-Plan falls Realtime-WS down

Falls der `RealtimeStateBanner` während der Demo dauerhaft "Polling aktiv" zeigt:

- Owner erklärt: Polling-Provider aus M1–M3 bleibt im Code als Fallback (architecture.md §3.1, §9). Dashboard und Public-View aktualisieren sich dann mit 5–10 s Verzögerung statt <2 s — die Funktionalität ist vollständig, nur die Latenz wechselt.
- Schritt 3 ("ohne Refresh") wird angepasst: "Update erscheint nach maximal 5 s, weil Polling-Tick statt WebSocket". Demo-Wert bleibt erhalten.
- Schritt 6 (Outbox-Flush) ist Realtime-unabhängig — funktioniert auch im Polling-Modus, weil die RPCs HTTP sind.
- Nach der Demo: Channel-Diagnose via Supabase-Dashboard, ggf. Pro-Tier-Upgrade.
