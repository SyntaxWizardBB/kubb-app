# Agent-Pipeline-Playbook

> Wie umfangreiche Arbeit in diesem Repo mit dem **Workflow-Tool** (Multi-Agent)
> autonom, aber kontrolliert erledigt wird. Beschreibt die Pipeline, die
> Orchestrierungs-Entscheidungen, die harten Guardrails und den Verify-Loop.
> Vorlage: [`agent-pipeline/task-pipeline.template.js`](agent-pipeline/task-pipeline.template.js).
>
> **Opt-in:** Diese Pipeline wird nur gefahren, wenn der User Multi-Agent-
> Orchestrierung ausdrücklich will (z. B. „nutze Agents / Worker-Workflow /
> ultracode" oder eine Skill/Slash-Command). Sonst normal arbeiten.

## A) Die Pipeline pro Task — 4 Rollen, SEQUENZIELL

Ein Task = ein `Workflow`-Aufruf mit vier Phasen, die **nacheinander** laufen
(`await` Kette). Reihenfolge ist bewusst:

1. **QA-Gate (DoD)** — schreibt ZUERST die Definition of Done: präzise,
   überprüfbare Akzeptanzkriterien. Bei Code-Tasks zwingend dabei:
   `flutter analyze` sauber, `flutter test --no-pub` grün, Spec-Konformität,
   keine hartkodierten Tokens.
2. **Implement** — setzt gegen Spec + DoD um, schreibt/aktualisiert Tests.
3. **Review** — adversarisch, streng. Führt `analyze`/Tests **selbst** aus,
   vergibt pro DoD-Kriterium pass/fail + konkrete Befunde (Datei:Zeile,
   Problem, Fix), Gesamturteil.
4. **Improve** — behebt ALLE Befunde (mind. blocker/major), re-verifiziert,
   liefert finalen DoD-Status.

**Warum sequenziell:** Ein paralleler Fan-out (mehrere Agents gleichzeitig)
wurde vom Rate-Limiter gedrosselt (0 Tokens, alle gescheitert). Sequenzielle
`await`-Ketten verteilen die Calls und kommen durch. Nur für read-only
Hunt/Verify-Fan-outs lohnt Parallelität — und auch die bei Drosselung
serialisieren (siehe E).

## B) Orchestrierung — wie Tasks/Agents gewählt werden

- **Erst selbst scouten** (billig, im Master-Kontext): Dateien lokalisieren,
  Ist-Verhalten + Integrationspunkte verstehen. So wird der Agent-Brief präzise
  und der Implement-Agent rät nicht.
- **Scope schneiden & splitten:** große/schichtenübergreifende Arbeit in
  sequenzielle Sub-Blöcke teilen — typisch **Domain → Server → UI**
  (z. B. D1/D2a/D2b, E1–E4). Vorteile: jeder Block reviewbar, keine parallelen
  Datei-Konflikte, DB-Risiko isoliert.
- **Eine geschriebene Spec als Quelle der Wahrheit** (z. B. ein
  `*_ChangeSpec.md` / ADR). Der Brief zeigt darauf + nennt die **exakten Items**
  und **Schlüssel-Dateien**. Optional ein Konsolidierungs-Agent, der lose
  Kommentare/Anforderungen vorab in so eine Spec mappt (schont Master-Kontext).
- **Echte Design-Forks vorher mit dem User klären** (Beispiele: Trostturnier-
  Modell, Rangliste-Definition, Scoring-Erfassung) — nicht raten. `AskUserQuestion`
  mit Previews eignet sich für saubere Entweder-oder-Entscheide.
- **No-Ops erkennen:** existiert das Feature schon + ist getestet, dann
  **verifizieren und berichten** statt eine funktionierende Sache neu zu bauen.
- **Brief-Größe:** lieber 5–8 konkrete, nummerierte Punkte + Scope-Grenze als
  ein vages „mach das Feature".

## C) Harte Guardrails — in JEDEM Brief (Phasen DoD/Implement/Review/Improve)

Diese Regeln sind nicht verhandelbar und stehen im Brief jeder Phase:

- **Kein Übergriff:** NIE Dateien außerhalb des Scopes verschieben/löschen/
  verlagern. NIE untracked-Dateien anfassen (ein Agent hat einmal fremde,
  untracked WIP-Docs nach `/tmp` verschoben — daher diese Regel). „Im Weg
  liegende" untracked-Dateien werden **ignoriert**.
- **Git:** `git add` nur die Scope-Dateien, **nie `git add -A`**. Agents
  committen/pushen **nicht** — das macht der Orchestrator nach Verifikation.
- **DB-Sicherheit:** **nie `supabase db reset`** oder löschende/seedende
  Befehle (kostete den User mal echte Daten). Schema-Änderungen nur **additiv**
  in NEUER Migration, via `supabase migration up`. Funktionale Proben in
  `BEGIN … ROLLBACK` auf eigens angelegten Test-Daten, sonst read-only psql.
- **Stale-Body:** Bei `CREATE OR REPLACE` einer mehrfach neu-definierten
  Funktion ZWINGEND auf der **tatsächlich aktuellen** Definition basieren —
  per Diff bestätigen, dass NUR die beabsichtigte Stelle sich ändert. (Sonst
  dreht man stillschweigend spätere Logik zurück.)
- **Realtime-Tabu:** `docs/plans/realtime-messaging/`, `docs/adr/0029*`,
  `messaging-framework-implementation-plan.md` nicht anfassen (paralleler
  Branch `feat/realtime-sync`). Neue Sync-Arbeit folgt ADR-0029 — **kein neues
  `Timer.periodic`-Polling**.
- **Konventionen:** UI-Strings Deutsch, Code-Kommentare Englisch; Tokens nur
  über `KubbTokens`; `analyze` sauber + Tests grün als Gates.

## D) Verify-dann-Commit (Orchestrator-Seite, nach jedem Workflow)

1. **Ergebnis lesen** (reviewOverall, findings, improveSummary).
2. **Unabhängig verifizieren** — nicht blind dem Agent vertrauen:
   `git status` (nur Scope-Dateien?), `flutter analyze` (keine neuen Issues
   gegen die bekannte Baseline), Tests **selbst** laufen, Kern-Claims
   stichprobenartig prüfen, bei `CREATE OR REPLACE` den **Body-Diff** gegen die
   Vor-Definition.
3. **Committen** — nur verifizierte Scope-Dateien explizit stagen (nie
   untracked-Fremddateien / `build/`); **ein Commit pro Block**; Commit-Message
   Englisch, endet mit der `Co-Authored-By`-Zeile.
4. **Push nur auf ausdrückliche Anweisung.**
5. **Tracking:** Todo-Liste pflegen; entdeckte Latent-Bugs als Folge-Items
   notieren statt still zu schlucken.

> Der Review-Loop fängt echte Fehler: u. a. Stale-Body-Regressionen bei
> `CREATE OR REPLACE`, Test-Regressionen durch Layout-Änderungen, falsche
> Aggregations-/Routing-Logik. Deshalb ist „Review + Improve + eigene
> Verifikation" nicht optional.

## E) Bug-Hunt-Variante (read-only Fan-out)

Für „finde Bugs im Feature X": mehrere **Finder** (je ein Bereich, read-only)
→ **adversariale Verifier** (je Kandidat, Default „kein Bug" bei Unsicherheit,
gegen False-Positives) → **ein** sequenzieller Fix-Agent (konfliktfrei) →
**unabhängiger Re-Verify**. Bei Rate-Limiting die Finder/Verifier **seriell**
statt parallel (mit `try/catch` pro Agent, damit ein gedrosselter Agent den
Lauf nicht killt).

## F) Vorlage benutzen

[`agent-pipeline/task-pipeline.template.js`](agent-pipeline/task-pipeline.template.js)
ist die parametrisierte 4-Phasen-Pipeline. Verwendung:

1. Den `TASK`-Block (title/brief/designOnly) für den konkreten Block ausfüllen.
2. `SPEC_REFS` auf die relevanten Dateien/Spec zeigen lassen.
3. Inhalt als `script` an das `Workflow`-Tool geben (nicht als Datei-Referenz
   beim ersten Lauf).

> **Wichtiger Caveat:** Das `args`-Feld des Workflow-Tools kam in der Praxis als
> `undefined` im Script an. Deshalb wird der Task **inline** im Script als
> `TASK`-Konstante geführt (nicht über `args`). Pro Block den `TASK`-Block
> editieren statt `args` zu übergeben.
