# turtle-grid — does the killzone-range filter earn its place?

9 sets × 3 timeframes (M3, M5, M15) = **27 backtests**, then one merged table.

```
RUN_TURTLE.bat          double-click this
run_backtests.py       the runner (same one as kz-grid)
sets_turtle/            the 14 .set files
```

## Setup, once

The runner drives a **separate portable MT5** so your live terminal keeps running
untouched.

1. Install a second MT5 to `C:\MT5-Tester` (not the default path)
2. Shortcut with `/portable` appended — this exact command line:

   ```
   C:\MT5-Tester\terminal64.exe /portable
   ```

   `/portable` is what makes the terminal keep its data folder **beside
   `terminal64.exe`** instead of under `%APPDATA%\MetaQuotes\Terminal\<hash>`.
   The `.bat` passes `--portable` to every tester run as well, so both halves
   agree on where `MQL5\Profiles\Tester` actually is. Without it the runner
   stages each `.set` into `C:\MT5-Tester\...` while the terminal reads from
   `%APPDATA%` — every run produces no report and the failure looks like a
   missing EA.
3. Launch it, log in, **compile the EA with F7** and copy `SniperTurtle_KZ_v1.00.ex5`
   into `C:\MT5-Tester\MQL5\Experts\`
4. Open an XAUUSD M3 chart there and scroll back past 1 Jan so it downloads the history
5. Close that terminal. Leave your live one running.

Then double-click `RUN_TURTLE.bat`. Edit `MT5DIR` at the top of it if you installed
elsewhere.

> **Compile first.** None of the `InpKzr*` inputs exist in an older `.ex5`, and MT5
> silently ignores keys it does not recognise — you would get 9 identical runs and
> spend an evening wondering why the model has no parameters.

## The 9 sets

Every set changes **one thing** against `TU_ref_nofilter`. That control is the plain
Sniper EA with the ranges recording but blocking nothing — so it should reproduce
SniperEA's own numbers, and if it does not, something in the port is wrong. Check that
first; it is the cheapest bug you will ever catch.

| Set | What it changes |
|---|---|
| `TU_ref_nofilter` | **the control.** Ranges recorded, nothing blocked |
| `TU_mode0_sweep12` | only enter within 12 bars of a weekly sweep in the trade's favour |
| `TU_mode0_sweep6` | the same, tightened to 6 bars |
| `TU_mode0_sweep24` | the same, loosened to 24 bars |
| `TU_mode1_near1` | block entries with an untaken weekly level within 1 ATR ahead |
| `TU_mode1_near2` | the same, widened to 2 ATR |
| `TU_days3` | weekly level built from 3 sessions instead of 5 |
| `TU_days10` | built from 10 |
| `TU_mode0_kzwindow` | mode 0 **and** the killzone entry window, both on |

All nine share the same sizing spine: Telegram off, prop mode off, session and fixed
lots off, `InpRiskPercent=0.5`.

## Reading the output

`all_results.csv` holds every run.

- **`TU_ref_nofilter` first.** A filter only means something against the trade it
  removed. The number that matters is not whether a filtered run is profitable — it is
  whether it beats the control after giving up trades to get there.
- **Rank by the WORST timeframe, not the best.** A set that prints beautifully on M15
  and loses on M5 has found an M15 artifact.
- A filter that cuts trade count hard can look better on win rate while earning less.
  Compare net and expectancy per trade, not percentages alone.
- Under ~30 trades a set has not said anything yet.
- Breakeven win rate for a 1:N model is `1/(1+N)`. At 1:3 that is 25%.

## The warm-up trap

The range history starts **empty**. In mode 0 the EA refuses everything until a
killzone has closed, so the first day or two of any backtest takes no trades at all.
Start the test early enough that the warm-up is not a meaningful slice of the period,
or `TU_ref_nofilter` will look better than the filtered runs for a reason that has
nothing to do with the filter.
