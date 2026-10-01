# Using jev-trader's idea on XAUUSD

[jarrodwatts/jev-trader](https://github.com/jarrodwatts/jev-trader) asks a hosted model
one typed question per Monad block and posts an order on the answer. This is what of it
can be used for gold, what cannot, and the order to build it in.

## What does not port, and why

| jev-trader | XAUUSD at a retail broker |
|---|---|
| Posts **post-only limit orders** one tick inside the touch and earns the spread | There is no book you can rest in. The broker quotes a bid and an ask; you cross it. **Spread capture is structurally unavailable** - this is the repo's whole mechanism. |
| Inputs are L2: `bookImbalance`, `depth` at 10/25/50 bps, top-5 levels, `cvdMon`, individual taker prints | A CFD feed gives none of it. MT5 `MarketBookAdd` is absent or meaningless for gold. **The model's entire input vector has to be replaced.** |
| 300 ms blocks, 30-second horizon | Measured round-trip cost here is ~$2.13 a trade. Nothing decided on a 30-second gold horizon clears that. |
| `SPEC.md`: *"the model is not trying to be profitable"*, non-goals include *"no backtests"* | Out-of-sample survival is the only thing that has mattered in this project. |

So it is not a strategy to copy. It is an **architecture** for letting a model judge a
setup, plus a dashboard. Both are usable.

## The blocker you need to know first

**`WebRequest()` does not work in the MT5 Strategy Tester.** It returns -1 there, by
design. An EA that calls a cloud model therefore **cannot be backtested in MT5 at all** -
not slowly, not with a flag, not at all.

That single fact decides the architecture. The model cannot live inside the EA during
validation, so the split is:

```
  validation   bars + features -> CSV -> replay offline -> model -> measured edge
  live         EA -> features -> model (WebRequest or a local bridge) -> order
```

The EA must be able to run **with the model and without it**, and the two must agree on
the same feature row. Anything else is untestable.

## Where the model belongs: on setups, not on bars

The v4 diagnostic is the reason this is affordable and sane:

```
20,800 evaluations -> 180 setups found -> 13 orders placed
```

Asking a model every M5 bar is ~75,000 calls a year and judges mostly nothing - 79.5% of
bars are rejected for "no HTF bias" before any interesting question exists. Asking it
only when the EA has already found a setup is **a few hundred calls a year**. At
jev-trader's own figure (~$0.20/hour for 3.3 decisions/second, so ~$1.7e-5 each) a full
year replay costs **under a cent**.

So the model is a **filter on setups the EA already found**, answering one question:

> This setup is about to risk `riskUsd`. Over the next `InpOrderExpiryBars` bars, is it
> more likely to reach `tp` than `sl`?

Take the trade when `p(win)` beats the breakeven rate the R-multiple implies. For
`V4_s1_part50`, scaling out puts breakeven at 66.5%, so the gate is `p > 0.665` plus a
margin. That is a real decision rule, not a vibe.

## Step 1 (done): collect the data

`InpSetupCSV=true` writes `SRHTF_setups.csv`, one row per setup placed:

```
time,hour,dow,bias,b1,b2,b3,riskPts,atrPts,spreadPts,liqRR,rangePos,
ret5,ret20,ret100,lots,riskUsd,filled,profitUsd,R
```

Every field is something a CFD feed can actually supply - no book, no depth, no taker
flow. `filled=0` rows are kept deliberately: a stop order that was never taken out is a
real outcome, and dropping those rows would bias the set toward setups that happened to
trigger. `R` is `profitUsd / riskUsd`, so rows are comparable across risk settings, and
a scaled-out trade is summed over its whole position rather than counted at its first
exit.

`RUNSETS.bat` collects it the same way it collects `diag_*.csv`.

## Step 2: the replay harness (not built)

Reuse jev-trader's `Model` interface verbatim - it is the one piece that transfers
cleanly:

```ts
interface Model { decide(state: TradeState): Promise<Decision> }
```

Replace `TradeState` with the CSV row, keep `MockModel` as the baseline, point `JevModel`
at the same `experimental_evaluate` call with a gold-shaped question. Then measure on
held-out years:

- **Baseline to beat:** take every setup. That is the v4 result already in hand.
- **A filter is only worth having if it raises expectancy per trade AND leaves enough
  trades to matter.** A model that keeps 20 of 180 setups has not been validated, it has
  been fitted.
- Split by year, not at random. 2023-2024 to choose a threshold, 2025-2026 to test it.
  Random splits leak, because adjacent setups share the same market.

## Step 3: live, if and only if step 2 passed

Two ways in, both fine at M5 speed - a bar close gives seconds, not the 300 ms
jev-trader fights for:

1. **`WebRequest` straight from the EA.** Add the endpoint to the terminal's allow-list.
   Simplest, and the EA stays one file.
2. **File bridge**, if the model runs locally: EA writes the feature row, a Bun process
   writes a decision file, EA reads it. Slower to set up, but nothing leaves the VPS and
   it is the same code path the replay harness uses - which makes live and backtest agree
   by construction.

Either way the EA must **take the trade when the model is unreachable or late**, or fail
closed deliberately and say which it is doing. jev-trader's own `late` handling is the
right pattern: a missed decision is recorded as missed, never silently treated as a
signal.

## What is actually worth copying today

`src/server.ts` is 45 lines: snapshot endpoint, `/history` ring buffer, SSE pushing one
typed event per decision. Mapped onto this EA, one event per bar carrying bias, killzone
state, the `g_status` rejection reason, open position and day P&L - and `g_status` and the
rejection tally already produce exactly that. That is a live dashboard for an afternoon's
work, and it is useful whether or not any model is ever involved.

## Honest summary

- The trading idea: **does not port.** Market making is not available to you.
- The architecture - typed question, probabilities, one decision per event, honest
  accounting of cost: **ports, and is worth having.**
- The cost: **negligible**, because the model only judges setups, not bars.
- The risk: an unvalidatable component inside a system whose last three grids measured
  the wrong thing. Step 1 exists now. **Nothing goes live before step 2 reports a number.**
