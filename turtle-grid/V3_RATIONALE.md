# v3 — attacking trade count, and testing the signal itself

23 sets × M15 / M5 / M3 = **69 runs**. `RUN_V3.bat`, or `python run_all.py --grids v3`.

---

## What v1 and v2 established

**Profit factor does not move.** Across 100 runs with ≥100 trades: median **0.990**,
mean 0.990, and 59 of them between 0.95 and 1.05. Sixty-one configurations across two
grids and two timeframes, and the result sits on breakeven throughout.

**The timeframes disagree.** Correlation of M5 net against M3 net across the v2 sets is
**−0.42**. What helps one hurts the other, which is what noise looks like.

**Exits were not the problem.** `V2_exit_partials` books TP1–TP4, wins **58%** of its
trades, and still loses. `V2_exit_noboth` wins 62% and loses more. You cannot win six in
ten and lose money if the exits are the fault.

## The one thing that is not noise

Trade count.

| | median net |
|---|---|
| runs under 300 trades | **+25** |
| runs over 600 trades | **−703** |

Matched by set, M3 takes on average **200 more trades** than M5 and nets **425 less** —
about **$2.13 per extra trade**. At 0.5% risk on $25,000 that is roughly 1.7% of the risk
budget lost per trade to spread and slippage. With a raw edge near zero, that is
precisely enough to hold profit factor at 1.0.

**So v3 attacks trade count, and tests the one input nobody has touched.**

---

## A — EMA periods (10 sets)

`InpEmaFast=9`, `InpEmaMid=21`, `InpEmaTrend=50` were **never varied once** across the 61
sets of v1 and v2. Everything downstream of the signal was swept; the signal was held
fixed. That is the gap.

`V3_ema_5_13` · `8_21` · `10_30` · `12_26` · `15_40` · `20_50` · `21_55` · `34_89` ·
`50_100`, against `V3_ctrl` at 9/21.

Slower pairs cross less often, so this block and the trade-count finding test the same
idea from two directions. If the slow pairs improve and nothing else does, the answer was
always "trade less".

## B — Spread cap (4 sets)

`V3_spread15` · `20` · `25` · `30`, against the default 50. A direct attack on the
measured cost: refuse the entries whose spread is eating the edge.

## C — Fewer trades by other means (4 sets)

`V3_cool20` · `V3_cool40` force 20 or 40 bars between signals. `V3_atr21` · `V3_atr30`
slow the ATR, which widens the stop and moves the whole ladder with it.

## D — The combinations the evidence supports (4 sets)

`V3_slow_tight` (20/50 EMA + 20-point spread cap), `V3_slow_caps`, `V3_slow_tight_caps`,
and `V3_caps_only`.

The daily-cap pair is the only result that **repeated across both grids**:

| | M5 | M3 | max DD |
|---|---|---|---|
| `TU_tgt100_cap80` | +1470 PF 1.11 | +1526 PF 1.10 | 10.9% |
| `V2_tgt100_cap80` | +548 PF 1.05 | +970 PF 1.07 | 6.9% |

Positive on both timeframes in both grids, drawdown cut from ~20% to under 7%. Worth
carrying forward — while being clear about what it is. **Daily caps limit losses; they do
not create an edge.** It is risk management on a flat strategy.

## E — Sanity (1 set)

`V3_kz_off` re-checks the killzone window on the v3 spine.

---

## M15 is back, against the earlier decision

You asked to drop M15 and run M5/M3 only. The data since then argues the other way: if
trade count is what bleeds the account, the higher timeframe is the most direct test
available, and leaving it out would mean not asking the question the numbers raised.

M15 should take roughly a third of M5's trades. If the per-trade cost theory is right it
should be the best of the three — and if M15 is *also* stuck at PF 1.0, then the cost
theory is wrong too, and that is worth knowing in one run rather than three grids.

Drop it with `--periods M5,M3` if you disagree.

---

## Reading it

- **EMA block first.** It is the only block testing the strategy rather than its packaging.
- Rank by the **worst** timeframe. Under ~30 trades a set has said nothing.
- Watch **trades** as closely as net. If the winners are simply the sets that traded
  least, the finding is about cost, not about the parameter that produced it.

## What would make me stop

If the slow-EMA and M15 runs are still at PF ~1.0, then trade count was not the cause
either, and 84 more sets will not find one. At that point the EMA 9/21 cross on XAUUSD
has been tested across 84 configurations and three timeframes without producing an edge,
and the honest conclusion is that it does not have one — not that the next grid will
find it.
