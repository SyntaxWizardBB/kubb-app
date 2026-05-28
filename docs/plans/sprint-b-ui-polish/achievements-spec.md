# Achievements-System Spec

> Sprint B · Wave 6 · W6-T1 (Architect-Spike)
> Quelle: `docs/design/AUDIT.md` §4.6 (Badge-Vorschlaege, 12–15 Stueck).
> Strategie: Foundation jetzt bauen — Designer-Visuals (SVG-Glyphs + Mobile-Kit-JSX)
> werden nachgereicht. Bis dahin laufen wir auf Lucide-Fallback-Icons.

## 1. Badge-Inventar (15 Stueck)

Jedes Badge ist ein stabiler, deklarativer Eintrag. Trigger-Bedingungen werden als
pure Funktionen ueber die existierende Stats-Aggregation formuliert
(`StatsAggregate`, `FinisseurStatsAggregate`, ggf. Match-History und
Friends-Count). Trigger sind **monoton**: einmal entsperrt, bleibt entsperrt
(kein Re-Lock bei Datenkorrekturen).

Felder pro Badge:

- **ID** — snake_case, stabil (DB-Key, NIE renamen).
- **Display-Name** — Deutsch (de-CH), via ARB lokalisierbar.
- **Beschreibung** — 1 Satz, im UI als Karten-Subline.
- **Trigger-Bedingung** — pure Funktion der Aggregate-Inputs.
- **Glyph-Beschreibung** — Hinweis fuer den Designer, was im SVG drinsteckt.
- **Rarity-Tier** — `common` / `rare` / `epic`. Reines UX-Konstrukt
  (steuert Akzentfarbe + Sortier-Gewichtung in der Liste).

| ID | Display-Name | Beschreibung | Trigger | Glyph | Rarity |
|---|---|---|---|---|---|
| `first_match` | Erstes Match | Erstes Solo-Match abgeschlossen. | `matchHistory.completedSoloMatches >= 1` | Holz-Kubb mit Funken | common |
| `hits_100` | 100 Treffer | Hundertster Sniper-Treffer eingelocht. | `sniperAggregate.totalHits >= 100` | Holz-Kubb mit "100"-Inlay | common |
| `hits_1000` | 1000 Treffer | Sniper-Veteran: vierstellig getroffen. | `sniperAggregate.totalHits >= 1000` | Goldener Kubb mit "1K"-Gravur | rare |
| `first_strafkubb` | Erster Strafkubb | Im Finisseur erstmals einen Strafkubb gezogen. | `finisseurAggregate.penaltyCount >= 1` | Stehender Kubb mit roter Schleife | common |
| `streak_10` | 10er Streak | Zehn Sniper-Treffer hintereinander. | `sniperAggregate.longestHitStreak >= 10` | Stab mit drei goldenen Ringen | common |
| `streak_25` | 25er Streak | Fuenfundzwanzig Treffer am Stueck — Hand-Kalibrierung. | `sniperAggregate.longestHitStreak >= 25` | Stab mit Blitz-Akzent | epic |
| `heli_master` | Heli-Master | Fuenfzig Helikopter-Wuerfe getrackt. | `sniperAggregate.heliCount + finisseurAggregate.heliCount >= 50` | Wind-Rosette ueber Stab | rare |
| `konstanz_king` | Konstanz-King | Zehn Sessions in Folge mit ueber 70 % Trefferquote. | letzte 10 `StatsSessionRow.hitRatePercent` alle `>= 70` | Krone aus dem Logo, Sockel aus Holzscheiben | epic |
| `saisonteilnehmer` | Saisonteilnehmer | An mindestens einer Saison teilgenommen. | `seasonsJoined >= 1` | Banner mit Jahreszahl | common |
| `top_100_elo` | Top 100 ELO | Im Liga-Ranking unter den Top 100 platziert. | `eloRank != null && eloRank <= 100` (TODO: Backend) | Pfeil-nach-oben auf goldenem Schild | epic |
| `finisseur_clean` | Sauberer Finisseur | Finisseur ohne einen einzigen Strafkubb gewonnen. | `finisseurAggregate.sessionRows.any((s) => s.success && session.penaltyHits == 0)` | Stehender Kubb mit klarem Funken-Kranz | rare |
| `match_marathon` | Match-Marathon | Zehn Matches an einem einzigen Tag. | `groupBy(matchHistory, day).any((day) => count >= 10)` | Stoppuhr mit Lorbeer | rare |
| `daily_streak_7` | Wochen-Streak | Sieben Tage hintereinander mindestens eine Session. | sortierte distinct `session.completedAt.day` enthaelt 7er Folge | Kalender-Blatt mit 7 Haken | common |
| `tournament_winner` | Turniersieger | Ein Turnier gewonnen. | `tournamentHistory.any((t) => t.placement == 1)` (TODO: Bracket-Hook) | Pokal aus Logo-Stil | epic |
| `friends_3` | Drei Freunde | Mindestens drei angenommene Freundschaften. | `socialRepo.acceptedFriendsCount >= 3` | Drei verbundene Punkte (Trigon) | common |

> Hinweis: Sniper-Total-Hits ist heute nicht direkt im `StatsAggregate` als
> `totalHits`-Feld exponiert — `StatsRepository.computeAggregate` rechnet
> `hitsTotal` lokal aus. W6-T3 erweitert das Aggregate um `totalHits` (kostet
> ein extra Feld, keine zweite Query).

## 2. Datenmodell

```
class Badge {                         // statisches Inventar, im Code definiert
  final String id;                    // snake_case, stabil
  final String displayName;           // via l10n-Key resolvable
  final String description;
  final String glyphAssetKey;         // 'badge-hits_100' → asset path
  final BadgeRarity rarity;
  final BadgeTrigger trigger;         // pure function — siehe unten
}

enum BadgeRarity { common, rare, epic }

class BadgeUnlock {                   // Drift-Table-Row
  final String userId;
  final String badgeId;
  final DateTime unlockedAt;
  final String? sourceSessionId;      // optional, fuer "ausgeloest in Session X"
}

typedef BadgeTrigger = bool Function(BadgeTriggerInput input);

class BadgeTriggerInput {             // alles read-only, kommt aus Providern
  final StatsAggregate sniper;
  final FinisseurStatsAggregate finisseur;
  final List<MatchHistoryEntry> matches;
  final List<TournamentResult> tournaments;
  final int seasonsJoined;
  final int acceptedFriendsCount;
  final int? eloRank;                 // null = Backend liefert noch nicht
}
```

- **Inventar im Code, Unlock-State in der DB.** Das Inventar ist eine
  konstante `List<Badge>` in `lib/features/achievements/data/badge_catalog.dart`.
  Nur Unlocks (User-spezifisch, mit Timestamp) landen in einer Drift-Tabelle
  `badge_unlocks`.
- **Idempotenz.** Der Evaluator schreibt einen Unlock nur, wenn noch keiner
  fuer `(userId, badgeId)` existiert. Damit kein Doppel-Toast bei Restart.
- **Server-Sync (out-of-scope Wave 6).** Backend-Push der Unlocks ist ein
  Wave-7-Thema; das DB-Schema bleibt absichtlich lokal-first.

## 3. Screen-Layout (Mobile-Kit-konform)

- **AppBar:** `KubbAppBar(eyebrow: 'Profil', title: 'Erfolge')`,
  Back-Pfeil links, kein Right-Slot.
- **Body:** `ListView` mit zwei Sections:
  - "Erspielt" — entsperrte Badges, neueste zuerst.
  - "Noch offen" — gesperrte Badges, sortiert nach Rarity (`common` zuerst,
    damit naheliegende Ziele oben stehen).
- **Card pro Badge:** Inset-Card im Brand-Look (siehe `ProfileScreen.jsx`
  Card-Stil). Layout:
  - Glyph-Vignette 48 dp (Holz-Optik, Gold-Akzent fuer `rare`/`epic`).
  - Title (Bricolage, fett, 15 sp).
  - Description (12 sp, muted).
  - Right-Slot: `"Erspielt am 14.04.2026"` oder `"Sperrt frei bei 100 Treffern"`
    (computed Hint je Trigger).
- **Empty-State:** `KubbEmptyState` mit Title `"Noch keine Erfolge"`,
  Body `"Spiel ein paar Sessions, dann fuellt sich die Vitrine."`,
  CTA `"Sniper starten"` → routet auf den Sniper-Start.
- **Routing:** Push von `AppSettingsModal.onOpenAchievements`,
  Route-Name `/profile/achievements`.

## 4. Designer-Pflichten (Owner-Eskalation)

Diese Punkte sind **Designer-Output**, nicht im Worker-Scope:

- **15 SVG-Glyphen** unter `docs/design/assets/badges/badge-{id}.svg`,
  Master 192×192, Auto-Export auf 48 / 96 / 192 px.
- **AchievementsScreen.jsx** im Mobile-Kit (`docs/design/ui_kits/app/`),
  analog zu `ProfileScreen.jsx` + Card-Stil-Refs.
- **Rarity-Token-Mapping** (Common = Holz-Natur, Rare = Gold-Akzent,
  Epic = Gold + Korona / Glow). In Designer-Output dokumentieren.
- **Hover/Pressed-States: keine.** Read-only Liste, kein Tap-Target ausser
  optionalem Detail-Modal (out-of-scope).

Solange Designer-Output fehlt: Flutter-Skeleton (W6-T2) nutzt Lucide-Fallbacks
aus `lib/core/ui/icons.dart` (`Trophy`, `Crown`, `Wind` etc.). Visual-Treue
holt ein Wave-6.1-Polish-Worker nach Designer-Lieferung nach.

## 5. Wave-6-Task-Schnitt

- **W6-T2 (Flutter-Skeleton, UI-Worker).**
  - `lib/features/achievements/presentation/achievements_screen.dart`.
  - Statisches Inventar mit Placeholder-Fallback-Icons.
  - Section-Layout "Erspielt" / "Noch offen" mit Dummy-Daten (alle locked).
  - Empty-State + Routing von `AppSettingsModal.onOpenAchievements`.
  - **Kein** Trigger-Evaluator, **kein** DB-Write — nur UI-Shell.
- **W6-T3 (Domain, Logic-Worker).**
  - `lib/features/achievements/data/badge_catalog.dart` (15 Eintraege).
  - `lib/features/achievements/data/badge_unlock_dao.dart` + Drift-Migration
    fuer Table `badge_unlocks`.
  - `BadgeTriggerInput` + Trigger-Functions, plus `BadgeEvaluator`-Service.
  - `unlockedBadgesProvider` (StreamProvider, liest DAO).
  - `evaluateAchievementsProvider` (FutureProvider, ruft Evaluator
    nach Session-Completion via `ref.listen` auf Session-Events).
  - `totalHits` als neues Feld in `StatsAggregate` ergaenzen
    (siehe Hinweis in §1).
- **W6-T-Designer (extern, Owner-Eskalation).**
  - SVG-Set + JSX-Mockup nachreichen.
  - Triggert dann Wave-6.1-Polish-Task fuer Visual-Treue.

T2 und T3 koennen **parallel** laufen — T2 nutzt Mock-Provider, T3 wirft
einen echten Provider rein, T2 swappt am Schluss die Datenquelle.

## 6. Risiken

- **Sniper-`totalHits` fehlt im Aggregate.** `StatsAggregate` rechnet
  `hitsTotal` heute lokal in `computeAggregate`, exponiert es aber nicht.
  T3 muss das Feld ergaenzen. Low-Risk.
- **ELO/Top-100-Badge (`top_100_elo`).** Es gibt heute kein Liga-Modul mit
  ELO-Score; `lib/features/season/` deckt nur Saisonteilnahme ab. Trigger
  ist als `TODO` markiert — Badge bleibt im Inventar, Trigger gibt bis
  Backend-Hook konstant `false` zurueck. Nutzer sieht "Locked".
- **Tournament-Winner-Badge.** Bracket-Completion-Hook noch nicht klar;
  siehe `ADR-0007` (Disagreement-State-Machine). Trigger als `TODO`,
  gleiche Strategie wie ELO-Badge.
- **Konstanz-King-Definition.** "10 Sessions in Folge mit >70 % Hit-Rate"
  ist scharf — Definition ueber `sessionRows`-Reihenfolge (sortiert nach
  `completedAt`). Bei sehr wenigen Sessions (<10) trivial `false`.
- **Streak-25-Trigger** ist seltener als `streak_10` (Rarity `epic`),
  aber technisch identisch (longestHitStreak-Check). Keine Extra-Logik
  noetig.
- **`friends_3`-Badge** braucht `socialRepository.acceptedFriendsCount` —
  Modul `lib/features/social/` existiert, Methode muss ggf. ergaenzt
  werden (T3-Sub-Task).
- **`match_marathon`** braucht Grouping nach Tag ueber alle Modi
  (Solo-Match + Tournament-Match). Definition: Tag = UTC-Date, nicht
  lokal — sonst Edgecase bei Timezones.
