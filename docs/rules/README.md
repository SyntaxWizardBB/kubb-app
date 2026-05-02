# Rule sets

The active rule set in v1 is the **Schweizer Kubbverband v1.11 (April 2026)**.

- Official source: https://kubbtour.ch/dynpg/upload/imgfile39.pdf
- A local copy of the PDF lives at `kubb_ch_regelwerk.pdf` (gitignored — © Schweizer Kubbverband, do not redistribute through this repository).

## Engineering summary — Schweizer Kubbverband v1.11

This is a paraphrased, engineering-oriented summary used to derive the rule engine. For any actual play or dispute resolution, refer to the official PDF.

### Equipment

- 10 kubbs (15 cm tall, 7×7 cm cross section)
- 6 batons / Wurfstöcke (30 cm long, 4.4 cm diameter)
- 1 king / König (~30 cm tall, ~9×9 cm cross section)
- Field: 5 m baseline × 8 m sideline; midline ~5.5 m
- Boundary: ~3 mm non-elastic cord, clearly visible

### Teams and field

- Standard team size: ≥3 players (Swiss championship). Variants: 1–6 players.
- Field on short-mown lawn. Variants: sand, snow, gravel, etc.

### Game flow

1. Toss for opening (King throw).
2. Attackers (Team A) throw batons from their baseline at Team B's base kubbs.
3. Fallen kubbs are picked up by Team B and tossed into Team A's half (becoming **field kubbs**).
4. Team B (now attackers) must hit field kubbs first, then base kubbs.
5. Cycle continues. The first team to clear all opposing kubbs and the king wins the set.

**Hard rules:**
- King may only be thrown at after all opposing kubbs are down.
- Toppling the king before that → immediate loss.
- "Holz auf Holz": only wood contact counts as a hit.

### Throwing rules

- Underarm only.
- Vertical rotation allowed; horizontal spin (helicopter) is not.
- Deviation > 30° from vertical → invalid throw.
- Special exception for 8 m baton tosses: if both teams disagree on validity (deviation in 20°–40° band), one re-throw may be requested; the worse of the two counts.
- Both feet must stay behind the throwing line and inside the side boundary during and after release.
- If the opponent failed to clear all field kubbs in the previous round, the throwing line advances to the foremost remaining field kubb (advance line).

### Distributing batons

- 6 batons must be distributed across at least 3 different players each round.
- For 2-baton or 4-baton openings: at least 2 / 3 different players respectively.
- No fixed throwing order required.

### Throwing kubbs in (after a round)

- All kubbs from one's own baseline → opponent's half.
- Underarm throw, both feet inside extended sideline.
- A thrown-in kubb is **valid** if it can be stood up over a short edge, fully inside the opponent's half, without touching the boundary cord.
- Two-pass throw-in: first pass throws all kubbs; second pass re-throws those that couldn't be placed.
- Rotation: at least 3 different players must take turns throwing in (per round).
- "Gstellt isch gstellt" — once a placed kubb is released, it cannot be re-positioned.
- A kubb that lands stacked off-ground in a stand-able pose is a "Chriesi" / award kubb — placed freely on opponent's half.
- A kubb that fails the second pass becomes a **Strafkubb**: opponent places it freely, ≥1 baton-length from king and corners.
- A kubb placed on the baseline becomes a base kubb — no longer required to be hit before the others.

### Opening variants

| Code | Round 1 batons | Round 2 | Round 3+ | Notes |
|---|---|---|---|---|
| 6-6-6 | 6 | 6 | 6 | full-strength opening |
| 4-6-6 | 4 | 6 | 6 | for 2-player teams / individuals |
| 3-6-6 ("Basel 3") | 3 | 6 | 6 | classic short opening |
| 2-4-6 | 2 | 4 | 6 | gentle ramp for individuals |

### King

- King throw is from the baseline, regular underarm.
- Toppled too early (with baton or kubb) → immediate set loss.
- Helicopter throws not permitted on the king either.

### Tie-break

- Triggered after a time cap (e.g. 20 min). Re-do the king toss; winner removes the first kubb.
- Each subsequent round, the rear-most kubb of the defender is removed before they throw.
- KO matches: tie-break finishes the current set; if the match is tied on sets, a deciding set follows where the original opening-toss winner picks between opening or tie-break-advantage.

### League points (informational, NOT in v1 scope)

- Three leagues: A (registered), B (auto from main tournaments), C (auto from side tournaments). Plus an individual ranking.
- Tournament must have ≥8 teams to count.
- Base points: 100 for the winner of a "base tournament" sized 10/20/40 (A/B, C, individual).
- Range factor: 3 (size for which winner gets 2× base points).
- Rank factors: 1 / 0.8 / 0.65 / 0.5 (ranks 1–4); rank ≥5 uses a different formula.
- 2-player teams weighted at 2/3 of headcount.
- Masters tournament: top 8 (A, B), top 16 (C). A/C double points, B single.

These computations are intentionally **not** in Phase 1 — domain knowledge documented for later.
