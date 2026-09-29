# GridMaster Pro — vendored third-party source

| | |
|---|---|
| Upstream | https://github.com/sajidmahamud835/grid-master-pro-mt5-ea |
| Licence | **MIT** — redistribution permitted with the notice, which is why `LICENSE` is here |
| Strategy | bi-directional ATR grid, explicitly |
| Tested by | [`gmp-grid/`](../../gmp-grid/) |

Unmodified. No backtest exists upstream — no results, no equity curve, no data at all.

## What the grid is actually testing

`MaxDrawdownPct` is the whole question. It is the only thing standing between a grid and
a 6% funded limit, and unlike Gold Reaper's guard it is genuinely **equity-based**:

```cpp
double maxLoss = accountEquityStart * MaxDrawdownPct / 100.0;
return (accountEquityStart - equity) >= maxLoss;
```

So it measures what the firm measures. Five of the twenty sets move it (2/3/4/5%) and one
turns `CloseOnDrawdown` off to see whether a paused grid recovers or just sits underwater.

**Read equity drawdown, not balance drawdown.** Across the eleven geraked grid EAs the
ratio between them was never below 3.4×, and that gap is exactly where a funded account
dies. If GridMaster's circuit breaker genuinely holds equity drawdown under 4%, it would
be the first grid in this whole review that could survive a prop rule — worth knowing
either way.
