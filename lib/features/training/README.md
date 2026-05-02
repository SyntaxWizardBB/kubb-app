# training — bounded context

**Layering**: pragmatic (per ADR-0002).

Solo-user practice modes. Local-only by default. The architectural goal here is **1-tap UX**, not domain purity — Riverpod talks directly to drift, no event log, no ports.

```
training/
├── application/    Riverpod providers (TrainingSessionController, etc.)
├── data/           Drift tables: TrainingSession, TrainingThrow
└── presentation/   Eight-meter ticker, finisseur, four-meter screens
```

Modes:
- **8m-Ticker** — configurable target throw count, hit/miss tap counter
- **Finisseur** — preset like 7/3 (7 thrown-in kubbs + 3 base kubbs to clear)
- **4m-Linie** — kubbs on the 4 m line, hit-rate tracking

Per ADR-0001 this is the **first feature to ship** — it derisks the offline slice before any cloud sync exists.
