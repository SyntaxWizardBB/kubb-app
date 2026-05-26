# Domain-Knowledge-Notes

Dieser Ordner sammelt langlebige Kubb-Domain-Notizen — Faktenlage plus Empfehlung zu Fragen, die Spec und Regelwerk offen lassen oder nur teilweise abdecken.

Eine Domain-Notiz entsteht aus dem internen Kubb-Knowledge-Workflow (Knowledge-Builder → Expert-Voten → Synthesis → Persistierung). Format pro Note: Frage, Empfehlung, Begründung, Edge Cases, Folge-Aktionen, Quellen.

Diese Notes sind **nicht** ADRs (keine Architektur-Entscheidung) und **nicht** Spec (keine normative Anforderung). Sie sind Domain-Wissen mit Quellen-Bezug, das in Planung, Code-Reviews und Setup-Wizard-Texten als Referenz dient.

## Vorhandene Notes

- [`spiel-um-platz-3.md`](./spiel-um-platz-3.md) — Default-Verhalten für das Spiel um Platz 3 im KO-Bracket (CH-Liga-Praxis + Hybrid via `tournaments.league_eligible`).
- [`qualifier-count.md`](./qualifier-count.md) — Qualifier-Anzahl im Hybrid `round_robin_then_ko` (Option B Beliebige Top-N mit BYE-Auffüllung plus UX-Mitigation).
