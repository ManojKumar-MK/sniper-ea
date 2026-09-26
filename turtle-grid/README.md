# turtle-grid — does the killzone-range filter earn its place?

33 sets × 2 timeframes (M5, M3) = **66 backtests**, then one merged table.

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
> silently ignores keys it does not recognise — you would get 33 identical runs and
> spend an evening wondering why the model has no parameters.

## The 33 sets

Every set changes **one thing** against `TU_ref_kz60`.

That control is the EA as it ships: killzone entry window **on** with a 60-minute
lead, ranges recording, filter off, no daily target. It should reproduce SniperEA's
numbers *restricted to the killzones* — not SniperEA outright, because it is awake 58%
of the day rather than all of it. It is also the **no-target** run, so there is no
separate `TU_tgt_none`.

### The killzone window

| Set | What it changes |
|---|---|
| `TU_ref_kz60` | **the control.** Window on, lead 60, filter off, no daily target |
| `TU_nokzwindow` | window off — trades all day. What is the window itself worth? |
| `TU_lead30` | open 30 min before each killzone instead of 60 |
| `TU_lead120` | open 120 min before |
| `TU_closeatend` | flatten when the killzone ends instead of running to target |

### The range filter

| Set | What it changes |
|---|---|
| `TU_mode0_sweep12` | only enter within 12 bars of a weekly sweep in the trade's favour |
| `TU_mode0_sweep6` | the same, tightened to 6 bars |
| `TU_mode0_sweep24` | the same, loosened to 24 bars |
| `TU_mode1_near1` | block entries with an untaken weekly level within 1 ATR ahead |
| `TU_mode1_near2` | the same, widened to 2 ATR |
| `TU_days3` | weekly level built from 3 sessions instead of 5 |
| `TU_days10` | built from 10 |

### The signal quality filter

**`InpEnableQFilter` is `false` in the control**, which is the EA's default and the
Pine's — "original behaviour", every EMA 9/21 cross taken. So the seven `InpQf*` flags
below it do nothing until the master switch is on, and none of these conditions has
ever been tested here. That is what this block is for.

| Set | What it changes |
|---|---|
| `TU_qf_default` | master **on** with the ticks the EA ships (trend, struct, EMA50, VWAP, cooldown) |
| `TU_qf_all` | every condition, including bias and volume which ship off |
| `TU_qf_trend` | ADX ≥ 25 **only** |
| `TU_qf_struct` | \|EMA21−EMA50\| ≥ 0.5 ATR **only** |
| `TU_qf_ema50` | price on the right side of EMA50 **only** |
| `TU_qf_vwap` | price on the right side of VWAP **only** |
| `TU_qf_cooldown` | 5 bars between signals **only** |
| `TU_qf_bias` | the bias score ≥ 70 **only** |
| `TU_qf_volume` | volume > average **only** |
| `TU_qf_adx20` | default ticks, ADX threshold 20 |
| `TU_qf_adx30` | default ticks, ADX threshold 30 |
| `TU_qf_cool10` | default ticks, cooldown 10 bars |

The one-condition-at-a-time runs are the point of this block. `TU_qf_default` turns on
five conditions at once, and if it helps you still cannot say which one did the work —
or whether one of them is quietly costing you while the other four carry it. Read the
singles against `TU_ref_kz60` first, then check whether `TU_qf_default` beats the best
single by enough to justify four extra conditions.

A filter can only ever **remove** trades, so compare expectancy per trade and drawdown,
not net. Cutting trade count in half and keeping 60% of the profit is a good filter;
the net alone makes it look like a loss.

### Stopping for the day

`InpDailyProfitTarget` is **cash in the account currency**, measured on **closed trades
only**, so a floating winner cannot trip it and then evaporate. It stops *new entries*;
an open trade keeps running unless `InpDayTargetClose` is on.

| Set | What it changes |
|---|---|
| `TU_tgt50` | stop taking entries at +$50 realised for the day |
| `TU_tgt100` | +$100 |
| `TU_tgt200` | +$200 |
| `TU_tgt500` | +$500 |
| `TU_tgt100_close` | +$100 **and** flatten the open trade at that moment |
| `TU_cap80` | soft daily loss cap at $80 |
| `TU_cap250` | soft daily loss cap at $250 |
| `TU_tgt100_cap80` | both ends: +$100 stops, −$80 stops |
| `TU_fn25k` | the whole FundedNext 25k configuration as a single run |

All of them share the sizing spine — Telegram off, session and fixed lots off,
`InpRiskPercent=0.5` — **except `TU_fn25k`**, which carries its own 0.35% and its prop
guards, because the point of that one is to run the live configuration rather than a
variable in isolation.

Two of these answer questions the defaults only assume:

- **`TU_nokzwindow`** is the honest test of the whole premise. If trading all day beats
  trading the killzones on your data, the window is costing you money and no amount of
  it being the ICT convention changes that.
- **`TU_closeatend`** tests carrying a trade past its killzone. The default lets it run
  because the window is about *when to enter*; this run is what says whether that is
  true here or merely tidy.

### Reading the daily-target runs, specifically

A daily target **cannot increase** gross profit — it only ever removes trades that
would have happened after the target was hit. So the question is never "did it earn
more", it is:

- Did it cut the **worst days**? Compare max daily loss and the drawdown, not the net.
- Did it cost much? A target that halves net for a small drawdown improvement is a bad
  trade on a personal account and possibly a good one on a funded account, where
  breaching ends everything.
- On a $25k challenge the target is not about profit at all. It is about not being in
  the market after you have already done the day's work.

## "no EA logs found"

The run **succeeded** — that line only ever prints after the report was written and
filed. It is a note about a second, optional thing: the EA's own CSV/JSONL trade log,
which `ema_report.py` reads for per-trade detail, the skip audit and MFE/MAE.

It appears when the set's `InpCsvPrefix` is not unique. The EA names its file
`<InpCsvPrefix>_<symbol>_<tf>.csv`, and the collector matches on the set name, so a
shared prefix means the logs cannot be told apart — and worse, every set writes to the
same file and overwrites the one before.

Every set here now carries `InpCsvPrefix=<its own name>`. If you see this message
again, check that first.

**The grid comparison is unaffected either way.** Net, profit factor and drawdown come
from MT5's own report, not from the EA's log.

## "finished in 0.0 min but NO REPORT was written"

Every run ends in seconds, no report, and MT5's log shows the terminal connecting
normally rather than a tester pass.

**The tester terminal is already open.** A second launch of the *same* terminal hands
the `/config:` off to the running instance and exits — so the pass never happens. The
usual cause is an interrupted run leaving MT5 open in the background.

Close the tester window and rerun. If it is not visible:

```
taskkill /IM terminal64.exe /F     (closes ALL terminals, your live one too)
```

The runner now refuses to start in this state and names the path. Your **live**
terminal does not trigger it — the check compares executable paths, not image names,
so the two terminals are told apart.

If you genuinely need to override it, `--allow-running` still exists — but it was
being passed on every run by default, which is what let this failure through in the
first place.

## Deposit: 25,000

The runs use a **$25,000** starting balance, matching the FundedNext 25k account these
sets are aimed at. `--deposit 50000` changes it.

This is not cosmetic. Risk-% sizing is a fraction of the **balance**, so the deposit
sets position size on every set, not just `TU_fn25k`. At the old $5,000 default the
funded run was meaningless:

| | at $5,000 | intended at $25,000 |
|---|---|---|
| risk 0.35%/trade | $17.50 | $87.50 |
| daily cap $600 | 12% of the account | 2.4% |
| total stop $1,200 | 24% | 4.8% |

The cash guards do not scale with the deposit, so at $5,000 they sat at a large
multiple of the per-trade risk and would effectively never have fired — the run would
have looked like a configuration with no guards at all, and said nothing about whether
the real ones are survivable.

For the other sets the deposit mostly scales the absolute numbers, and the comparison
between them holds either way. Percentages — drawdown %, return % — do shift, so do not
compare a run at one deposit against a run at another.

## Reading the output

`all_results.csv` holds every run.

- **`TU_ref_nofilter` first.** A filter only means something against the trade it
  removed. The number that matters is not whether a filtered run is profitable — it is
  whether it beats the control after giving up trades to get there.
- **Rank by the WORST timeframe, not the best.** A set that prints beautifully on M5
  and loses on M3 has found an M5 artifact.
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
