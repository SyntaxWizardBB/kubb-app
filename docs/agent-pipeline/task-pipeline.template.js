// Reusable 4-role task pipeline for the Workflow tool.
// See docs/AGENT_PIPELINE_PLAYBOOK.md for the methodology.
//
// USAGE:
//  1. Fill the TASK block (title / brief / designOnly) for the concrete block.
//  2. Point SPEC_REFS at the relevant files + spec.
//  3. Pass THIS script as the Workflow tool's `script` argument.
//
// CAVEAT: the Workflow tool's `args` arrived as `undefined` in practice — so
// the task is inlined here as the TASK constant, NOT read from `args`. Edit
// the TASK block per block instead of passing args.
//
// CONVENTIONS baked in: sequential phases (rate-limit-friendly), hard
// guardrails (no overreach / no `git add -A` / no `supabase db reset` /
// no stale-body), German UI strings + English code comments, analyze+tests
// as gates. Adjust GUARDRAIL's DB lines out if the block is pure-Dart.

export const meta = {
  name: 'task-pipeline',
  description: 'Generic task: QA-Gate(DoD) -> Implement -> Review -> Improve',
  phases: [
    { title: 'DoD' },
    { title: 'Implement' },
    { title: 'Review' },
    { title: 'Improve' },
  ],
}

const REPO = '/home/lukas/Workbench/FlutterKubbClub/KubbProj'

// ---- EDIT PER BLOCK -------------------------------------------------------
const TASK = {
  title: 'Block X — <kurzer Titel>',
  // designOnly: true  -> reines Dokument/Design, kein Code/keine Tests.
  // designOnly: false -> Code-Task: analyze sauber + Tests gruen sind Pflicht.
  designOnly: false,
  brief: `<<Praeziser Brief: 5-8 nummerierte, konkrete Punkte. Verweise auf die
Spec-Datei + nenne die exakten Items und Schluessel-Dateien. Setze eine klare
SCOPE-GRENZE (was NICHT angefasst wird). Bei Server-Anteil: additive Migration,
Stale-Body-Diff, BEGIN/ROLLBACK-Proben.>>`,
}
// ---------------------------------------------------------------------------

const GUARDRAIL = `!!! NICHT-UEBERGRIFF + DB-SICHERHEIT (zwingend) !!!
- Verschiebe/loesche/verlagere NIEMALS Dateien ausserhalb deines Scopes. KEINE untracked Dateien anfassen.
- docs/plans/realtime-messaging/, docs/adr/0029*, messaging-framework-implementation-plan.md NICHT beruehren. Kein neues Timer.periodic-Polling (ADR-0029).
- 'git add' nur Scope-Dateien; NIE 'git add -A'. Keine Commits/Pushes.
- DB: NIE 'supabase db reset'/loeschende Befehle; additive Migration via 'supabase migration up'; Proben read-only/BEGIN-ROLLBACK. Bei CREATE OR REPLACE geschichteter Funktionen ZWINGEND auf der AKTUELLEN Definition basieren (Stale-Body per Diff ausschliessen).`

const SPEC_REFS = `Repo-Root: ${REPO} (absolute Pfade).
ZUERST lesen: <<die relevante Spec-Datei + Schluessel-Code-Dateien hier auflisten>>, KubbProj/CLAUDE.md, docs/AGENT_PIPELINE_PLAYBOOK.md.
${GUARDRAIL}
Konventionen: UI-Strings Deutsch, Code-Kommentare Englisch. Branch feat/p6-tournament-setup, nicht committen/pushen.`

const DOD_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['criteria'],
  properties: { criteria: { type: 'array', items: {
    type: 'object', additionalProperties: false, required: ['id', 'criterion', 'verify'],
    properties: { id: { type: 'string' }, criterion: { type: 'string' }, verify: { type: 'string' } },
  } } },
}

const REVIEW_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['findings', 'gateResults', 'overall'],
  properties: {
    findings: { type: 'array', items: {
      type: 'object', additionalProperties: false, required: ['severity', 'location', 'problem', 'fix'],
      properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, location: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } },
    } },
    gateResults: { type: 'array', items: {
      type: 'object', additionalProperties: false, required: ['id', 'verdict', 'note'],
      properties: { id: { type: 'string' }, verdict: { type: 'string', enum: ['pass', 'fail'] }, note: { type: 'string' } },
    } },
    overall: { type: 'string', enum: ['pass', 'fail'] },
  },
}

const codeGates = TASK.designOnly
  ? 'Design-only: Kriterien betreffen Vollstaendigkeit/Konsistenz/Korrektheit des Dokuments.'
  : "Code-Task: MUSS enthalten — 'flutter analyze' sauber (keine neuen Issues), 'flutter test --no-pub' gruen inkl. neuer Tests, Spec-Konformitaet, keine hartkodierten Tokens, Scope/Guardrail eingehalten."

phase('DoD')
const dod = await agent(
  `Du bist der QUALITY-GATE-Agent fuer "${TASK.title}".
${SPEC_REFS}
Aufgabe-Brief:
${TASK.brief}
Schreibe eine Definition of Done: praezise, UEBERPRUEFBARE Akzeptanzkriterien. ${codeGates}
Gib NUR die Kriterienliste zurueck.`,
  { phase: 'DoD', label: 'qa-gate', schema: DOD_SCHEMA },
)
const dodText = dod.criteria.map((c) => `- [${c.id}] ${c.criterion} (Pruefung: ${c.verify})`).join('\n')

phase('Implement')
const impl = await agent(
  `Du bist der IMPLEMENT-Agent fuer "${TASK.title}".
${SPEC_REFS}
Aufgabe-Brief:
${TASK.brief}
Definition of Done (MUSS erfuellt werden):
${dodText}
Setze die Aufgabe VOLLSTAENDIG um. ${TASK.designOnly ? 'Reines Dokument — kein Code aendern.' : "'flutter analyze' sauber, Tests schreiben + 'flutter test --no-pub' gruen (echte Ergebnisse berichten)."} Strikt im Scope, GUARDRAIL strikt einhalten.
Gib eine knappe Zusammenfassung zurueck: geaenderte/neue Dateien, wie jedes DoD-Kriterium adressiert ist, Analyse-/Test-Ergebnis.`,
  { phase: 'Implement', label: 'implement' },
)

phase('Review')
const review = await agent(
  `Du bist der REVIEWER fuer "${TASK.title}". Sei streng und adversarial.
${SPEC_REFS}
Definition of Done:
${dodText}
Zusammenfassung des Implement-Agents:
${impl}
Pruefe gegen Spec + DoD. ${TASK.designOnly ? 'Pruefe inhaltliche Vollstaendigkeit/Konsistenz.' : "Fuehre SELBST 'cd " + REPO + " && flutter analyze' und 'flutter test --no-pub' aus und berichte die ECHTEN Ergebnisse."} Pruefe Scope + GUARDRAIL (git status: nur Scope-Dateien; realtime untracked unberuehrt; bei CREATE OR REPLACE Body-Diff = kein Stale-Body).
Liste konkrete Maengel (Datei:Zeile, Problem, Fix) + pro DoD-Kriterium pass/fail + Gesamturteil.`,
  { phase: 'Review', label: 'review', schema: REVIEW_SCHEMA },
)

phase('Improve')
const improve = await agent(
  `Du bist der IMPROVE-Agent fuer "${TASK.title}".
${SPEC_REFS}
Definition of Done:
${dodText}
Reviewer-Befunde (JSON):
${JSON.stringify(review)}
Behebe ALLE Befunde (mind. alle blocker/major) und erfuelle JEDES DoD-Kriterium. ${TASK.designOnly ? '' : "Danach 'cd " + REPO + " && flutter analyze' sauber UND 'flutter test --no-pub' gruen (ausfuehren, Ergebnisse berichten)."} GUARDRAIL strikt.
Gib Abschluss-Zusammenfassung + finalen DoD-Status (pass/fail je Kriterium) + geaenderte Dateien + offene Punkte zurueck.`,
  { phase: 'Improve', label: 'improve' },
)

return {
  task: TASK.title,
  dod: dod.criteria,
  reviewOverall: review.overall,
  reviewFindings: review.findings,
  improveSummary: improve,
}
