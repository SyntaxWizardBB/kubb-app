# Tournament foundation — Offene Entscheidungen

> Status: Entwurf, wartet auf Abnahme
> Datum: 2026-05-25

Folgende Punkte müssen vor Implementierungsstart geklärt werden. Jeder Punkt ist blockierend in dem Sinn, dass das Antwort das Architektur-Bild und/oder den Code-Pfad verändert.

## OD-01: Realtime-Strategie

**Frage**: Nutzen wir Supabase Realtime ab M1 oder bleiben wir vorerst bei Polling?

**Warum blockierend**: Die Code-Schicht für Match-Status-Updates wird einmal geschrieben. Ein späterer Wechsel von Polling auf Realtime ist nicht trivial — Realtime-Subscriptions brauchen einen Channel-Lifecycle, der von Riverpod-Provider-Lifecycle abweicht.

**Optionen**:
- A) **Polling im MVP, Realtime ab M4**. Match-Detail und Standings refetchen jedes 5-Sekunden-Intervall. Konsequenz: 8-Spieler-Turnier mit 5 offenen Match-Detail-Tabs erzeugt 40 Lese-Requests/Min. Bei 50 Turnieren parallel: 2000 req/min. Bleibt unter Supabase Free Limit, fühlt sich für Spieler langsam an (3–5 s Verzögerung beim Match-Status-Wechsel).
- B) **Realtime ab M1**. Eine Subscription pro geöffnetem Turnier auf `tournament_matches`+`tournament_set_scores`. Konsequenz: 200 Realtime-Verbindungen Limit auf Free Tier kann bei 8 Spielern x mehrere offene Apps schnell überschritten werden. Tiefe Abhängigkeit von `RealtimeChannel`-Lifecycle.
- C) **Hybrid**: Polling für die Liste-Views, Realtime nur für Match-Detail-Screen (eine Subscription pro offenes Match-Detail). Konsequenz: deutlich bessere UX am Pitch, deutlich weniger Verbindungen als B.

**Empfehlung**: C — Hybrid. Match-Detail ist der einzige Screen, wo Sub-Sekunden-Updates relevant sind (für den Konflikt-Flow, "andere Seite hat gerade submittet"). Standings und Live-Rangliste sind auch mit 5-Sek-Polling gut genug, weil die Daten nicht sekundenkritisch sind.

Risiko: 200-Verbindungs-Limit auf Free Tier wird bei mehreren parallelen Turnieren mit vielen Zuschauern schnell warm. Daher: das öffentliche Live-View bleibt auf Polling, nur eingeloggte Spieler im Match-Detail bekommen Realtime.

## OD-02: Cross-Platform-Sequenzierung

**Frage**: In welcher Reihenfolge bringen wir die App auf iOS, Android, Windows, Web und Linux?

**Warum blockierend**: Die Dev-Maschine hat Linux- und Web-Builds heute kaputt (Linux: pkg-config-Probleme; Web: dart:ffi via drift, WASM-Spike pending per ADR-0005 alt). Wenn der MVP auf Web laufen soll, kostet das einen Spike, bevor M1 startet. Wenn er auf Linux laufen soll, kostet das das Aufräumen der pkg-config-Kette.

**Optionen**:
- A) **Android first (geht jetzt), iOS sobald macOS-Setup steht, Web nach M4, Linux/Windows später**. Konsequenz: schnellster Weg zum MVP. Owner kann am eigenen Phone demoen. Web (= Veranstalter-Tablet im Browser, Zuschauer ohne App-Install) entfällt im MVP — Veranstalter müsste auch ein Phone/Tablet mit Android nehmen.
- B) **Android + Web parallel ab M1**. Konsequenz: 3–5 Tage Web-Spike vor M1 (drift-on-Web-Frage wieder offen, oder per ADR-0005 die `SupabaseTournamentRemote` ohne lokale Drift auf Web fahren). Veranstalter-Dashboard funktioniert ab MVP im Browser.
- C) **Alle 5 Plattformen ab M1**. Konsequenz: iOS-Build allein erfordert Apple Developer Account, macOS-Build-Maschine, Code-Signing-Pipeline. Mindestens 1 Woche Setup ohne Feature-Fortschritt. Linux + Windows brauchen je einen separaten Tag für Build-Konfiguration und Test. Nicht realistisch im MVP-Zeitrahmen.

**Empfehlung**: A — Android first. Owner will alle 5 Plattformen langfristig, aber der schnellste demobare Slice ist Android-only. Web wird zwingend mit M3 oder M4 (spätestens für Live-Dashboard und Zuschauer-Sicht), iOS dann separat sobald die Distribution-Pipeline existiert. Linux + Windows sind Last in der Reihenfolge — sind primär für Owner-eigenen Komfort als Entwickler relevant, nicht für Endnutzer.

Konkret: für M1 reicht Android. Vor M2 ein 2-Tage-Spike, ob Web mit `SupabaseTournamentRemote` ohne lokale Drift funktioniert. Vor M4 (Live-Dashboard) muss Web stehen.

## OD-03: Privacy-Stats-Split

**Frage**: Wie wird die Trennung "Training-Stats nur für Freunde, Turnier-Stats öffentlich" technisch umgesetzt?

**Warum blockierend**: Die bestehende `StatsScreen` zeigt heute drei Tabs (Sniper, Finisseur, Match). Match-Tab zeigt heute Solo-Match-Ergebnisse — die zählen funktional zum **Training**-Sichtbarkeits-Bucket (siehe FR-SOCIAL-4). Wenn wir jetzt Turnier-Matches in den gleichen Provider-Pfad einspeisen, vermischen sich die Privacy-Buckets im Code. Das Refactoring später wird teuer.

**Optionen**:
- A) **Separater Tab "Turnier" in der bestehenden StatsScreen**. Konsequenz: vier Tabs, klar getrennt. Provider-Pfade trennen sich auf Datenebene: `trainingStatsProvider` (Sniper, Finisseur, Solo-Match → friends-only-RLS) vs. `tournamentStatsProvider` (Turnier-Matches → public-RLS). Minimal-invasive Lösung.
- B) **Eigener StatsScreen-Bereich für Turnier**. Komplette Trennung, eigene Route `/stats/tournament`. Heutige `/stats`-Route bleibt Training-only. Konsequenz: klarerer Bruch, aber zwei verstreute Eingänge. Owner muss entscheiden ob ein zweiter Tab im Bottom-Nav reinpasst oder ob es eine Unter-Navigation im Profil wird.
- C) **Im bestehenden Profil-Screen verschieben**: Turnier-Stats kommen ins öffentliche Spielerprofil (per FR-PROFILE-2/-3), nicht in die "Meine Statistik"-Sicht. StatsScreen bleibt komplett Training. Konsequenz: sauberste konzeptuelle Trennung (privat = Stats, öffentlich = Profil). Erfordert FR-PROFILE-Implementierung schon im MVP-Slice.

**Empfehlung**: C — Trennung nach Sichtbarkeit. Solo-Match (heute öffentlich!) wird FR-SOCIAL-4-konform auf friends-only umgestellt — das ist heute schon eine Spec-Verletzung im Code. Turnier-Match-Stats erscheinen im öffentlichen Profil, nicht in der privaten Stats-Sicht. Eine kleine Migration für M1, aber sie bringt das Datenmodell und die UI in einen Zustand, der den Spec-Anforderungen entspricht.

Zu prüfen mit Owner: ist die heutige öffentliche Sichtbarkeit der Solo-Match-Stats Absicht (Phase-2-Decision in ADR-0012) oder ein Übersehen?

## OD-04: Auto-Approve oder manuelle Bestätigung von Anmeldungen

**Frage**: Im MVP — bestätigt der Veranstalter jede Anmeldung manuell, oder werden alle Anmeldungen bis zur Obergrenze automatisch approved?

**Warum blockierend**: Spec [FR-REG-6](../../specs/tournament-mode-spec.md#36-anmeldung-fr-reg) sagt klar "Der Veranstalter kann Anmeldungen bestätigen, ablehnen, in die Warteliste verschieben oder zurückziehen". Im MVP heisst das einen weiteren Screen + Workflow. Wenn wir Auto-Approve im MVP machen, bleiben die manuellen Aktionen für M2 — aber dann fehlt die Möglichkeit, dubiose Anmeldungen abzulehnen.

**Optionen**:
- A) **Auto-Approve bis Obergrenze im MVP**. Veranstalter spart Klickerei, demo-Flow ist 3 Schritte schneller. Anmelden = sofort akzeptiert.
- B) **Manuell ab MVP**. Veranstalter sieht Liste, klickt Approve/Reject pro Eintrag. Doppelt so viel UI-Arbeit für M1.
- C) **Config-Flag pro Turnier**. Veranstalter wählt im Wizard "Auto-Approve" oder "Manuell". Eine Zeile mehr in der Konfiguration, etwas mehr Logik in der RPC.

**Empfehlung**: A — Auto-Approve im MVP. Für ein 8-Spieler-Test-Turnier ist Manuelles Approven keine UX-Verbesserung. C ist die richtige Lösung längerfristig, kann aber bis M2 warten ohne dass M1 etwas dabei verliert.

## OD-05: Score-Eingabe-UI — pro Satz EKC vs. einfaches Match-Total

**Frage**: Lassen wir im MVP wirklich die Spieler pro Satz Basekubbs eingeben (volle EKC-Spec), oder reicht ein einfaches "Sieger + Satz-Score 2:1"?

**Warum blockierend**: Die Score-Spec ist auf Satz-genauer Eingabe gebaut (DSCORE-2, -10, -11). Solo-Match-Code heute fährt mit Match-Total. Wenn wir pro Satz erfassen, müssen wir die Eingabe-UI komplett neu bauen (Stepper pro Team pro Satz, König-Schalter, Live-Vorschau). Das ist die teuerste Komponente im MVP-Slice.

Wenn wir bei Match-Total bleiben, fehlt:
- EKC-genaue Punkte-Berechnung (Basekubbs pro Satz × 1 + Satz-Sieg × 3).
- Tiebreaker "Kubb-Differenz" (FR-RANK-4 — braucht die Basekubbs pro Satz).
- Mitlauf-Modus (FR-SCORE-8, ist eh SOLL).

**Optionen**:
- A) **Pro Satz EKC im MVP**. Drei bis fünf Tage UI-Arbeit. Eingabe in 30 Sekunden (NFR-UX-1) ist machbar, wenn Stepper schnell sind und Defaults stimmen. Voller Spec-Konformer.
- B) **Match-Total im MVP, EKC ab M2**. Eingabe ist trivial (zwei Steppers für Satz-Score 2:1, fertig). Spart 3–5 Tage. Tiebreaker "Kubb-Diff" entfällt, fällt zurück auf "Anzahl Siege" + "Direkter Vergleich". Punkte-Berechnung simpler.
- C) **Konfigurierbar pro Turnier**. Veranstalter wählt im Wizard "EKC" oder "Klassisch" (passend zu FR-CFG-6). Doppelter Implementierungsaufwand.

**Empfehlung**: B im MVP, A spätestens M2. Spec [FR-CFG-6](../../specs/tournament-mode-spec.md#35-turnier-konfiguration-durch-veranstalter-fr-cfg) sieht das klassische System sowieso als Option vor — wir starten mit dem klassischen und ergänzen EKC später. Begründung: der MVP-Wert ist im e2e-Flow, nicht in der EKC-Treue.

Wenn Owner explizit EKC will (weil das die Schweizer Turnier-Realität ist), dann A. Dann sind +3–5 Tage einzuplanen.

## OD-06: Turnier vs. Match — gemeinsamer Datenpfad oder zwei?

**Frage**: Verwenden wir die bestehende `match_propose_result`-RPC + `public.matches`-Tabelle für Turnier-Matches mit, oder kommt ein paralleler Pfad daneben?

**Warum blockierend**: Bestimmt den Code-Aufwand, die Komplexität der RLS-Policies und die Frage, wie Solo-Match und Turnier-Match miteinander interagieren (oder nicht).

**Optionen**:
- A) **Gemeinsamer Pfad**: `public.matches` bekommt nullable `tournament_id`. Solo-Match hat NULL, Turnier-Match hat den FK. `match_propose_result` wird erweitert um optional Satz-Daten. Eine Schreib-RPC für beide Welten. Konsequenz: kompakter Code, eine Datenstruktur. Die `match_propose_result`-Logik wird komplexer (zwei Eingabe-Schemas).
- B) **Zwei Pfade nebeneinander**: neue `tournament_matches`-Tabelle FK auf `public.matches`, neue `tournament_propose_set_score`-RPC. Solo-Match-Code unverändert. Konsequenz: keine Refactoring-Risiken, sauber getrennt, mehr SQL aber kein Eingriff in laufendem Code.
- C) **Tournament eigene `tournament_matches`-Tabelle ohne FK auf `public.matches`**. Komplett unabhängige Welt. Konsequenz: zwei Matches-Welten ohne Bezug, später kein einfacher Migration-Pfad zur Vereinheitlichung.

**Empfehlung**: B — Zwei Pfade nebeneinander, mit FK von `tournament_matches.match_id` auf `public.matches.id`. Bewahrt den Solo-Match-Code, lässt die Audit-Trail-Mechanik wiederverwenden, vermeidet Big-Bang-Refactor von `match_propose_result`. Die `public.matches`-Tabelle wird zur gemeinsamen Match-Identität, alles Turnier-Spezifische hängt daneben.

Die Architektur-Datei modelliert B. Wenn Owner A bevorzugt, ändert sich §3.3 und §10 von `architecture.md`.

## OD-07: Reichweite des MVP — Einzel oder auch Teams?

**Frage**: Hat der erste demobare Slice Einzelturniere oder auch Teamturniere?

**Warum blockierend**: Teamturniere brauchen `teams`+`team_members`-Tabellen, Pool-Verwaltungs-UI, Roster-Auswahl-Screen, Captain-Rechte-Modell. Das ist nicht "ein Feature mehr", das ist 4–6 zusätzliche Tage.

**Optionen**:
- A) **MVP nur Einzel (FR-CFG-1 mit teamSize=1)**. Team-Feature ist eigener Milestone M3. Konsequenz: 4–6 Tage gespart. Demo ist 8 Einzelspieler.
- B) **MVP mit Team-Support**. Komplette Team-Spec FR-TEAM-1..-20 im ersten Slice. Konsequenz: M1 wird zu M1+M3 zusammen, 15–20 Tage Arbeit.
- C) **MVP mit simpler Team-Variante**: feste Team-Zusammenstellung, keine Pool-Verwaltung, keine Captain-Rechte (eine Person registriert das Team mit fest hinterlegten Spielern). Konsequenz: schlanker als B, aber konzeptuell ein Compromise — entweder volles Pool-Modell oder gar keins.

**Empfehlung**: A — Einzel im MVP. Owner hat den Roadmap-Punkt "Solo-Match härtet die Match-Engine — Tournament ist im Kern N Matches mit Bracket drüber" formuliert. Das gilt auch für Einzel-Tournament. Teams sind eigenes Feature und sollten als M3 stehen.

## OD-08: Score-Spec — sind Penalty-Kubbs und Helicopter-Würfe wirklich raus?

**Frage**: Helicopter-Würfe und Strafkubbs (penalty kubbs) sind im Kubb-Regelwerk relevant, werden aber in der Score-Spec (FR-SCORE) nicht erfasst. Der Orchestrator hat das bestätigt: per-throw events sind tournament-mode raus. Stimmt der Owner zu?

**Warum blockierend**: Wenn doch nötig, ändert das die Daten-Granularität dramatisch (Match-Event-Log statt Score-Konsens).

**Optionen**:
- A) **Wie spec'd: nur Endergebnis pro Satz**. Helicopter, Strafkubbs sind Spiel-Realität ohne Datenrepräsentation. Konsequenz: konsistent mit der per-Match-Result-Entscheidung aus ADR-0013 und feature-note `live-scoring-granularity.md`.
- B) **Doch per-Wurf**. Match-Event-Log mit Lamport-Clock wird real, die alte ADR-0002-Vision tritt in Kraft. Konsequenz: massiv mehr Arbeit, Realtime-Sync wird kritisch, Konflikt-Auflösung pro Event nötig.

**Empfehlung**: A bestätigen. Per-Wurf-Granularität ist Trainings-Modus, nicht Turnier. Wenn Owner irgendwann doch eine Live-Streaming-Sicht "watch a match throw by throw" will, kann das nachgerüstet werden — aber als optionaler Add-on, nicht als Default.

## OD-09: Rollen und Rechte — wie weit im MVP?

**Frage**: Brauchen wir im MVP schon die Rolle "Veranstalter" vom "Spieler" technisch zu unterscheiden, oder kann jeder authentifizierte Nutzer Turniere anlegen?

**Warum blockierend**: Spec sieht fünf Rollen vor (Player, Organizer, League-Admin, Club-Admin, Platform-Admin). Heute hat der Code keine Rollen-Spalte.

**Optionen**:
- A) **Keine Rollen im MVP**: jeder authentifizierte Nutzer kann Turniere anlegen. Im Spiel-Modus ist er Spieler. Konsequenz: trivial. Risiko: jeder könnte Spam-Turniere anlegen.
- B) **Veranstalter-Flag pro Nutzer**: neue Spalte `user_profiles.can_organize`. Plattform-Admin setzt sie. Default false. Konsequenz: ein bisschen mehr Aufwand, CLI-Befehl für Plattform-Admin reicht (FR-ADM-12).
- C) **Vollständiges Rollen-Modell**: `user_roles`-Tabelle mit (user_id, role, scope_id). Konsequenz: deutlich komplexer, RLS-Checks werden teurer.

**Empfehlung**: A im MVP. Im Pilot-Stadium (Tier 0 per ADR-0004) ist Spam-Anlage kein realistisches Risiko. Owner kann manuell unsinnige Turniere löschen. B kommt mit M2, C mit M5 (wenn Vereine ins Bild kommen).

## OD-10: BIP-39-Keypair-User dürfen Turniere veranstalten?

**Frage**: Aktuell sagt [ADR-0010](../../adr/0010-identity-and-auth.md): "Tournament organizers are forced to OAuth (audit-trail value of a known identity)". Heisst das im MVP auch?

**Warum blockierend**: Wenn Owner selbst anonymous-keypair-account ist, kann er das eigene MVP nicht demoen. Wenn die Regel bleibt, muss er für die Demo OAuth nutzen.

**Optionen**:
- A) **Regel beibehalten**: keypair-User können nicht organisieren. Owner braucht OAuth-Account für die Demo.
- B) **Im MVP gelockert**: jeder kann organisieren. ADR-0010-Regel wird auf Production-Launch verschoben.
- C) **ADR-0010 amendieren**: keypair-User dürfen organisieren, Audit-Trail-Argument fällt.

**Empfehlung**: B im MVP, dann nach M1 mit Owner besprechen ob die Regel wirklich noch Wert hat. Es scheint primär eine Mass-Adoption-Sorge zu sein — fürs Pilot-Stadium unrelevant.
