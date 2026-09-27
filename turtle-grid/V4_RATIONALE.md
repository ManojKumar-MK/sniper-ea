# v4 — is 50/100 real, or the best of 69 draws?

23 sets, run on **two periods**: 2026 (where it was found) and **2025 (never seen)**.
`RUN_V4.bat`.

---

## What v3 found

`V3_ema_50_100` is the first result in this project that is clearly not noise:

| | net | trades | PF | DD | win | payoff |
|---|---|---|---|---|---|---|
| M15 | +1094 | 45 | **1.43** | 5.7% | 35.6% | 24.31 |
| M5 | +4182 | 190 | **1.39** | 6.9% | 30.5% | 22.01 |
| M3 | +5495 | 315 | **1.29** | 7.8% | 31.8% | 17.44 |

Positive on all three timeframes, PF 1.29–1.43, drawdown under 8% everywhere.

**The trade character changed, not just the number.** That is what makes it interesting:

| | win% | payoff | PF | DD |
|---|---|---|---|---|
| `V3_ema_50_100` M5 | 30.5 | **22.01** | 1.39 | 6.9% |
| `V3_ctrl` 9/21 M5 | 23.9 | 2.16 | 1.04 | 14.9% |
| `V2_ctrl` M5 | 22.5 | 0.78 | 1.01 | 18.6% |
| `TU_ref_kz60` M5 | 23.9 | −2.64 | 0.95 | 23.0% |

A payoff of 22 against 2.16 is a different population of trades, not a tuned one. A
50/100 cross only happens on a real change of trend, and the moves that follow run far
enough to pay for the losers. That is a mechanism, which is more than anything else in
this project has had.

## Why I do not trust it yet

**The EMA block is not monotonic.** Ordered by speed, worst-timeframe net:

```
 5/13   +362      10/30  -3299     21/55   -949
 8/21   -759      12/26  -3475     34/89   -246
 9/21   +118      15/40  -2047     50/100 +1094
                  20/50  -1989
```

The extremes win and the middle loses. If "slower means fewer trades means better" were
the mechanism, this would improve monotonically with speed. It does not — 12/26 is the
worst set in the grid and trades less than 5/13, which is positive.

**So the per-trade-cost theory from v3 is refuted**, and 50/100 is not yet explained by
it. Which leaves two possibilities, and v4 exists to separate them.

---

## The two tests

### A — The plateau test (13 sets)

If 50/100 is a real parameter, its neighbours work too: the surface is a hill and 50/100
sits near the top. If it is a fluke, it is a lone spike with losses either side.

`V4_ema_30_60` · `35_70` · `40_80` · `45_90` · **`50_100`** · `55_110` · `60_120` ·
`70_140` · `80_160` · `100_200`

Plus three that hold the fast EMA at 50 and change only the slow one — `50_75`, `50_150`,
`50_200` — to separate "the 1:2 ratio" from "50 specifically".

**This is the decisive one.** A hill means a parameter. A spike means a coincidence, and
I would not trade it whatever the 2026 numbers say.

### B — Out-of-sample: 2025 (every set, all three timeframes)

The same 23 sets on **2025.01.01 – 2025.12.31**, dates none of this was selected on.

50/100 was picked as the best of 69 runs. Picking the best of 69 always produces a good
number; the question is whether it survives contact with data that had no vote in
choosing it. **Read the 2025 rows first.** A result that exists only on the period it was
found on is not a strategy, it is a memory of that period.

### C — Does the rest still apply (9 sets)

`V4_caps`, `V4_spread15`, `V4_atr30`, `V4_kz_off`, `V4_nofilter` (does VWAP still earn
its place on a slow signal?), `V4_sl15`, `V4_sl30`, `V4_notrail`, `V4_partials`, and
`V4_fn25k` — the funded configuration, which lost on every previous grid.

---

## How to read it

1. **2025 first.** If 50/100 is negative there, stop — the rest does not matter.
2. **Then the plateau.** Hill or spike.
3. Only then the 2026 numbers, and only to size the thing.

A result that passes both is worth demo-trading. A result that passes one is worth
another look. A result that passes neither has been answered.

## The honest warning

Forty-five trades on M15 is a thin sample, and 2025 may hold a very different gold
regime from 2026 — a slow trend-following signal can look superb in a trending year and
awful in a range, which is not the same as being right or wrong. If 2025 disagrees with
2026, the answer is not to pick the better year: it is that the edge is regime-dependent,
and you would need to know which regime you are in before it could be traded.
