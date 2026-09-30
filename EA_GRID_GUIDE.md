# SniperGrid v1.00 — flat-lot grid with an enforceable loss ceiling

580 lines, written for baskets rather than adapted from a single-position EA.
Magic **996000**. Backtested by [`grid-grid/`](grid-grid/) — 25 sets × M5 × 4 years.

---

## The model

**1 — TRIGGER.** A grid starts on an EMA 50/100 cross, or immediately on the bias, or
at a session open (`InpTrigger`).

**2 — LEGS.** Each further leg opens `InpStepAtr` ATR **against** the basket, **the same
lot every time**. No martingale.

**3 — EXIT.** The whole basket closes together — on a combined money target, a combined
stop, or a basket breakeven once it is ahead. No per-leg stops: a per-leg stop closes
winners individually and leaves the basket holding only its worst positions.

## Why flat lots

A martingale basket breaks even on a smaller retrace, which is exactly why those equity
curves look smooth for years and then lose everything in a week. Flat lots recover more
slowly and **cannot compound the loss** — drawdown grows linearly with leg count, so it
is predictable.

That predictability is what makes the funded mode possible.

---

## The funded mode is the point

Grids fail prop rules for one structural reason: they hold losers open, so **balance
barely moves while equity falls**, and the firm measures equity. Measured in this
project:

| | balance DD | equity DD |
|---|---|---|
| 11 geraked grid EAs | 4.3–16.3% | **18.9–64%** |
| Gold Reaper (M5) | 1.38% | **23%+** |

Not one was below a 3.4× ratio between the two.

`InpMode=FUNDED` does two things none of those did:

**It refuses baskets it cannot afford.** Before leg 1 exists, the worst case is
computable. With flat lots and even spacing, when the last leg fills leg *k* is down
`(n−k)` steps, so the basket's total adverse travel is `n(n−1)/2` steps:

| legs | steps of adverse travel |
|---|---|
| 3 | 3 |
| 5 | **10** |
| 8 | 28 |

If that exceeds `InpRiskBudget`, **no grid opens** and the panel says why. The exposure
is known in advance rather than discovered at leg 5.

**It checks floating equity every tick** against `InpEquityFloorPct` below the session's
starting equity, and flattens. Not balance — equity, which is what the rule measures.

**This does not make a grid a good idea on a 6% account.** It makes the limit
*enforceable* instead of hoped for. Whether the strategy is then still profitable is what
`grid-grid` answers.

---

## Key inputs

| | default | |
|---|---|---|
| `InpMode` | **FUNDED** | FREE removes both the budget test and the equity floor |
| `InpRiskBudget` | 600 | most the whole basket may ever lose. Set **below** the firm's daily limit |
| `InpEquityFloorPct` | 4.0 | flatten at this far below the day's starting equity |
| `InpLot` | 0.01 | every leg, always |
| `InpMaxLegs` | 5 | worst case scales as n(n−1)/2, so this is the main lever |
| `InpStepAtr` | 1.0 | spacing in ATR; `InpStepPoints` if 0 |
| `InpMinBarsBetween` | 1 | stops one fast candle filling the whole grid |
| `InpBasketTpMoney` | 50 | combined target |
| `InpBasketSlMoney` | 400 | combined stop |
| `InpBasketBreakeven` | true | once ahead by `InpBeTrigMoney`, close if it falls to `InpBeFloorMoney` |
| `InpGridDir` | TREND | COUNTER for mean reversion; **BOTH needs a hedging account** |

---

## What it does not do

**No DST handling.** `GTRIG_SESSION` reads `TimeGMT()` with fixed hours. Unlike
SniperTurtle there is no NY-clock conversion, so a session window drifts an hour against
the actual session for half the year. Deliberate — this EA does not claim killzone
accuracy.

**No news filter, no prop-mode baseline, no Telegram.** Kept small on purpose. The CSV
log carries basket P/L, leg count, equity and balance per event, which is what the
analysis needs.

**`GDIR_BOTH` is untested.** It opens a grid each way and doubles the open exposure;
both sides can lose in a trend. It needs a hedging account and the startup banner says
so.

---

## Reading the grid

1. **`G_fn_ctrl` and its EQUITY drawdown.** Under 6% or not? That is the whole question.
2. **`G_fn_ctrl` against `G_free_ctrl`** — what the guards cost. The FREE sets should
   earn more and breach; if they don't, the guards are free and that is worth knowing.
3. **Then 2024.** Every grid reviewed lost there, and so did both of our own strategies.
4. **A grid profitable in three years and breaching in the fourth has not passed.** One
   breach ends a funded account permanently, so the worst year is the only year that
   counts.

## Status

**Never compiled, never run.** Braces and parens balance and the worst-case formula was
verified three ways, but nothing here has been through a compiler.
