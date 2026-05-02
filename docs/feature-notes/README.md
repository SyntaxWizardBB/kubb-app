# Feature notes

Holding place for feature requirements and ideas that came up before the relevant feature was scheduled. The `/feature` workflow's PO step reads this directory to find any pre-existing notes for the feature being planned.

## When to add a note here

- The owner mentions a requirement or behavior detail during a discussion that is not yet about the feature in question.
- A constraint or implication surfaces in an ADR review that affects a later feature.
- A clarification of an existing assumption that needs to land in the right feature backlog when its time comes.

## When NOT to add a note here

- Active task work — that lives in `docs/plans/<feature-slug>/`.
- Architectural decisions — those are ADRs in `docs/adr/`.
- Project-wide constraints — those go in CLAUDE.md.

## File naming

`<feature-slug>.md` — kebab-case, singular topic per file. One file per future feature, not one mega-doc.
