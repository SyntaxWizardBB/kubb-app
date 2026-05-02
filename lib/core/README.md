# core — cross-cutting infrastructure

```
core/
├── data/           Drift database setup, Supabase client, app-wide repositories
└── ui/             Shared widgets, theme tokens, error/loading states
```

Anything specific to a single bounded context lives in `lib/features/<context>/`, not here.
