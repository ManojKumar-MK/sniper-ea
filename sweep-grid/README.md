# sweep-grid — one-click backtest grid for SniperSweep_PDHPDL

14 sets × 3 timeframes (M3, M5, M15) = **42 backtests**, then one merged table.

```
RUN_SWEEP.bat          double-click this
run_backtests.py       the runner (same one as kz-grid)
sets_sweep/            the 14 .set files
SniperSweep_FundedNext_25k.set     the live-ready one, NOT part of the grid
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
3. Launch it, log in, **compile the EA with F7** and copy `SniperSweep_PDHPDL_v1.00.ex5`
   into `C:\MT5-Tester\MQL5\Experts\`
4. Open an XAUUSD M3 chart there and scroll back past 1 Jan so it downloads the history
5. Close that terminal. Leave your live one running.

Then double-click `RUN_SWEEP.bat`. Edit `MT5DIR` at the top of it if you installed
elsewhere.

> **Compile first.** None of the `InpSw*` inputs exist in an older `.ex5`, and MT5
> silently ignores keys it does not recognise — you would get 14 identical runs and
> spend an evening wondering why the model has no parameters.

## The 14 sets

Every set changes **one thing** against `SW_base_day`. That is the point — a grid where
two things move at once tells you nothing about either.

| Set | What it changes |
|---|---|
| `SW_base_day` | **the control.** PDH/PDL, strict MSS, FVG entry at CE, structural stop |
| `SW_day_week` | adds the previous week's levels |
| `SW_week_only` | weekly levels only — far fewer trades, heavier pools |
| `SW_mss_loose` | `InpSwMssStrict=false` — close beyond the raid candle instead of through the swing |
| `SW_pivot3` | wider swing definition (`InpSwMssPivot=3`) |
| `SW_market_entry` | enter at the MSS close, no retrace wait |
| `SW_fvg_optional` | take the trade even with no imbalance, and tag it |
| `SW_fvg_far` | fill at the far edge of the gap instead of CE |
| `SW_stop_from_fvg` | tight stop just beyond the FVG |
| `SW_confirm_tight` | raid expires after 3 bars |
| `SW_confirm_wide` | raid stays armed 12 bars |
| `SW_kz_lead30` | only trade the killzones, from 30 min before each |
| `SW_longs_only` | buys from low raids only |
| `SW_shorts_only` | sells from high raids only |

All 14 share the same spine: Telegram off, prop mode off, session/fixed lots off,
`InpRiskPercent=0.5` — so sizing is identical everywhere and the only difference in the
results is the model.

## Reading the output

`all_results.csv` holds every run.

- **Read `SW_base_day` first.** A variant only means something against the control.
- **Rank by the WORST timeframe, not the best.** A set that prints beautifully on M15
  and loses on M5 has found an M15 artifact, not an edge. This is the mistake that cost
  us the last grid.
- Under ~30 trades a set has not said anything yet, whatever its win rate.
- Breakeven win rate for a 1:N model is `1/(1+N)`. At 1:3 that is 25% — a 40% win rate
  is not "mediocre", it is a wide margin. Judge against that number, not against 50%.

## SniperSweep_FundedNext_25k.set

Not part of the grid — the live-ready configuration for a **FundedNext Stellar 1-Step $25K**.

### The firm's rules

| | |
|---|---|
| Profit target | 10% = **$2500** |
| Daily loss limit | 3% = **$750** |
| Maximum loss limit | 6% = **$1500** |
| Drawdown type | **Static** — measured from the $25,000 starting balance, not from peak equity |
| Minimum trading days | 2 |
| News trading | Allowed |
| Max risk | 3% at any time |

### How the set sits inside them

| | |
|---|---|
| Risk | 0.35% per trade (session and fixed lots both off, so the % actually applies) |
| Daily stop | **2.4% = $600**, not 3%. The EA's daily cap halts at exactly the figure given — unlike the total-loss guard it has no stop-at-% headroom, so the headroom has to be in the number itself |
| Soft cash cap | $250 — flattens and stops the day long before the $600 |
| Losing trades | stop after 3 in a day |
| Total stop | `InpDrawdownMode=0` (**static**, matching the firm) at 80% of 6% = **$1200**, leaving $300 |
| Open risk | one position at a time × 0.35% never approaches the 3% max-risk rule |
| News filter | **off** — the firm allows news trading |
| Levels | daily **and** weekly |
| Hours | killzones only, from 30 min before each |
| Weekend | flatten before the Friday close |
| Spread | skip entries above 40 points |

Telegram is left **off** in this file — fill `InpTgToken` and `InpTgChatId` yourself
rather than storing a token in the repo.

Two things to check before running it:

- **`InpServerGmtOffset`** against your broker. The killzone windows are computed from
  it, and if it is wrong the EA trades the wrong hours.
- **Minimum 2 trading days.** Killzones-only plus a setup that needs a raid *and* a
  structure shift can go quiet for days. Confirm in the backtest that this config
  actually trades often enough to clear that rule, or you can pass on profit and still
  fail the challenge.
