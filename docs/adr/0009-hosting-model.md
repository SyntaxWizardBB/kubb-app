# ADR-0009: Hosting model — self-hosted Supabase on Hetzner

- **Status**: Accepted
- **Date**: 2026-05-04
- **Refines**: ADR-0001 (which picked Supabase generically without locking cloud vs self-hosted)

## Context

ADR-0001 chose Supabase as the cloud backend (Frankfurt, EU) without committing to managed Supabase Cloud vs self-hosted. As Phase 1 implementation approaches, the owner needs a concrete hosting decision that is cost-predictable at the projected scale and keeps data ownership in-hand.

Three candidate paths were discussed:

1. **Supabase Cloud** (managed) — fastest setup, free tier up to 50k MAU, $25/mo Pro.
2. **Self-hosted on owner's home server** (16GB / 4 cores) — zero recurring cost, but tournament-day availability depends on home internet, power, and the owner being on-call. Tournaments are exactly when failures hurt most.
3. **Self-hosted on rented VPS** (Hetzner) — predictable low cost, business-grade uplink, full data control.

The owner expressed a clear preference for keeping data on infrastructure they control, while avoiding the operational risk of running production from home.

## Decision

**Hetzner Cloud VPS in Falkenstein/Nuremberg, running Supabase self-hosted in Docker.**

### Components

| Layer | Choice | Notes |
|---|---|---|
| Compute | Hetzner Cloud VPS | Start CX22 (€4.51/mo, 4GB / 2 vCPU / 40GB), grow to CX32 (€7.05/mo, 8GB / 4 vCPU) when first real load appears |
| Backend stack | Supabase self-hosted via official `docker-compose` | Postgres + GoTrue + Realtime + PostgREST + Storage + Studio + Kong |
| Backups | Hetzner automated snapshots (20% surcharge) + nightly `pg_dump` to off-site object storage | Belt and suspenders for tournament data |
| Web app hosting | Cloudflare Pages | Free tier, unlimited bandwidth, hosts the Flutter web build |
| CDN / DDoS shield | Cloudflare in front of Hetzner | Free tier, also caches read-heavy public endpoints (tournament listing, spectator views) |
| Push notifications | Firebase Cloud Messaging (FCM) | Free, unlimited, replaces email for in-app invites |
| Mobile distribution | Google Play Store (€25 one-time), Apple App Store ($99/yr, deferred) | Standard channels |
| Monitoring | Self-hosted Uptime Kuma on the same VPS, Hetzner status alerts | Free, sufficient for solo ops |
| Domain | TBD `kubb-app.<tld>` (~CHF 10–15/yr) | Owner picks before launch |

### Why these picks

- **Hetzner over Hostinger / DO / AWS**: best price/perf for VPS in EU, full root access, EU-jurisdiction (data lives where Swiss/EU users expect it).
- **Supabase self-hosted over plain Postgres + custom server**: gets Auth, Realtime, RLS, and PostgREST out of the box. The same client SDK works against self-hosted and cloud, so a future migration in either direction is low-friction.
- **Cloudflare in front**: free DDoS protection, free TLS, free static hosting for the web build, aggressive caching for public read endpoints. Cuts effective load on Hetzner by 50–80% for spectator-heavy traffic.
- **FCM for push**: kills the email-deliverability problem for tournament invites and notifications. ADR-0010 covers the auth-side consequence.

## Scaling path

Concrete upgrade triggers, so we do not over-build now and do not panic later.

| Concurrent users | Hetzner tier | Approx. monthly cost (incl. backups + domain) |
|---|---|---|
| 0–500 | CX22 (4GB) | ~€7 |
| 500–2.5k | CX32 (8GB) | ~€12 |
| 2.5k–5k | CX42 (16GB) | ~€18 |
| 5k–10k | CCX23 (16GB dedicated) | ~€38 |
| 10k+ | Split: dedicated DB server + app server, optional Hetzner Managed Postgres | ~€80–150 |

Scale triggers are operational thresholds (CPU sustained > 70%, p95 latency degradation, Realtime subscription count near `max_connections`), not user-count thresholds. ADR-0004 covers the broader scaling watch-list.

## Alternatives considered

- **Supabase Cloud (managed)** — rejected primarily because owner wants data residency under direct control and the predictable VPS cost is lower at the projected user count. Cloud stays as a fallback if self-hosting ops becomes too much (one `pg_dump` + restore migrates to Cloud in a day).
- **Home self-hosting** — rejected for production due to tournament-day availability risk. Useful as a staging/dev mirror, optional.
- **Plain Postgres + custom Dart/Go backend** — rejected for v1: too much to build before first user. Could be revisited if Supabase self-hosted ops becomes painful, but the SDK ecosystem benefit is significant.
- **AWS / GCP / Azure** — rejected: expensive at this scale, ops complexity not justified.

## Consequences

- Predictable infra cost: ~€7/mo at launch, €15–40/mo at multi-thousand-user scale, €100+/mo only at serious traction.
- Owner takes on the ops burden: OS updates, Postgres upgrades, Supabase version upgrades, certificate renewal (mostly automated via Caddy or Cloudflare), backup verification.
- Data lives in EU on Hetzner infrastructure. Switzerland-compliant for typical Verein use.
- Cloudflare and FCM introduce two third-party dependencies (both free, both very stable). FCM means Google has metadata about delivery (which user, when, not content); acceptable for non-sensitive notifications.
- Web build distribution becomes free; mobile distribution costs are platform-store fees only.
- Migration to managed Supabase Cloud later is straightforward (same SDK, same schema, same auth model). Migration to a different stack entirely (e.g., self-built backend) is harder but not blocked.

## Implementation order

1. Hetzner project + CX22 VPS, Ubuntu LTS, hardened SSH config.
2. Docker + docker-compose, Supabase self-hosted from the official template.
3. Caddy reverse proxy with Let's Encrypt.
4. Cloudflare account, DNS pointed at VPS, proxy mode enabled.
5. Initial schema migration (auth + first tables per ADR-0003 and ADR-0010).
6. Backups: enable Hetzner snapshots, set up nightly `pg_dump` to a separate Hetzner Storage Box.
7. Uptime Kuma for monitoring.
8. Cloudflare Pages project for the Flutter web build, hooked up to GitHub.
9. FCM project for push notifications (Android first; iOS later).

Each step is a candidate for one `/task` workflow run.
