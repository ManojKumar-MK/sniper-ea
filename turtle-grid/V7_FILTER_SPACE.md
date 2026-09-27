# v7 — the complete filter space on the 50/100 signal

**128 combinations × M5 × 4 years = 512 runs.** `RUN_V7.bat`.

---

## Why this exists

The seven quality conditions were characterised on the **9/21** signal back in v1:

| single filter | worst-year net (on 9/21) |
|---|---|
| VWAP | **+2220** |
| cooldown | −439 |
| EMA50 | −1572 |
| bias | −2030 |
| volume | −2665 |
| ADX ≥ 25 | −2896 |
| EMA separation | −4078 |

Every config since has carried that conclusion forward — VWAP on, the rest off. But the
signal changed. 50/100 fires on a different kind of setup, produces a payoff near 22
instead of 2, and **only 2 of the 128 combinations have ever been run on it**. The
filter rankings above were never re-measured.

That is the gap this closes. Every on/off combination of:

`T` ADX ≥ 25 · `S` EMA21–50 separation · `E` EMA50 side · `V` VWAP side ·
`B` bias score · `L` volume · `C` cooldown

`F_000_none` is the filter switched off entirely; `F_127_TSEVBLC` is all seven at once.

## Guards are off on purpose

With the funded guards on, a bad year halts the EA partway through — in 2024 that meant
17 trades instead of 54. A filter comparison run that way measures *when the halt fired*,
not what the filter did. Winners get re-run with guards afterwards.

## The rule, set before the run

**A combination counts only if it is profitable in all four years.**

Stated now, because 128 combinations × 4 years is a great many chances to look good, and
the temptation afterwards is always to relax the bar until something passes it.

### And even that is not enough

If each year were a coin flip, **roughly 8 of the 128 would clear all four by chance
alone**. So a clean sweep is the beginning of the argument, not the end of it. Anything
that passes gets two further tests:

1. **The plateau check.** Do its neighbours work — the same combination plus or minus one
   filter? A real filter effect is a region, not a point. `V` working while `VC` and `VE`
   both fail means `V` was lucky, not right.
2. **Trade count.** Heavy combinations will produce single-digit trade counts on a signal
   that already only fires ~150 times a year. Under ~30 trades in a year there is no
   result to read, whatever the net says.

## What would count as a real finding

- A **single** filter profitable in all four years, whose pairs also hold up.
- Or a family — say every combination containing `V` and not `S` — behaving consistently.
  A family is evidence; a lone winner among 128 is arithmetic.

## What this cannot do

It searches one dimension exhaustively and leaves the thresholds fixed: ADX at 25, struct
at 0.5, bias at 70, cooldown at 5 bars. Those were also inherited from the 9/21 era and
never retested on this signal. If a filter looks borderline here, its threshold is the
obvious next thing to move — but that is a second grid, after this one says which filters
are worth tuning at all.
