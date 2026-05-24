# match — bounded context

**Layering**: server-shaped (per ADR-0013, amending ADR-0002).

Solo-Match (per ADR-0012) uses Supabase RPCs as the domain authority. The Flutter side is a thin client over the `match_*` RPCs declared in `supabase/migrations/20260507*_match_*.sql`.

```
match/
├── application/    Riverpod controllers over the repository
├── data/           Wire-shaped models + MatchRepository (RPC wrapper)
└── presentation/   List, lobby, result form
```

Data models in `data/match_models.dart` mirror the RPC payloads (`MatchSummary`, `MatchDetail`, `MatchResultProposal`, …). Round reconciliation, vote tallying, and audit-trail emission live server-side in `_match_try_reconcile`. The `packages/kubb_domain/match/` slot stays reserved for the tournament live-scoring slice (M3+).
