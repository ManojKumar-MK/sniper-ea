# Backtesting ict_options.py the way we backtested gold

The script already reported **entry / stop / target / R per setup** and a rejection tally.
What it did not do was measure *one account*, over *separate periods*, after *costs* - and
those three are what every wrong conclusion in the gold work came from.

## One click

```
./run_ict.sh              macOS / Linux.  ./run_ict.sh 250  for 250 days
.\RUN_ICT.bat             Windows VPS.    .\RUN_ICT.bat 250
```

`run_ict.sh` builds a `.venv_ict` so `smartapi-python` and its pins stay out of the system
python. Both scripts stop at the first thing that is wrong and say what to do.

## Credentials: use `.env`, not the shell, and never a chat

```
cp .env.example .env     # then fill it in
```

`.env` is gitignored and `load_env()` reads it with no dependency. **Real environment
variables are not overwritten**, so a VPS using `setx` or systemd is unaffected.

Credentials on a command line end up in shell history and in `ps`. Pasted into a chat they
are in a transcript forever. The file is the only place they belong.

### Running the backtest from a laptop first

This works, with one thing to check: **the machine's public IP must be whitelisted on the
SmartAPI app**, per the SEBI static-IP rule the script's header cites. The login is what
fails otherwise, so it fails immediately and clearly rather than halfway through.

If your home IP is dynamic, either add it before each session or do the data pull on the
VPS and copy the CSVs down. The fully offline route needs no credentials at all:

```
python3 ict_options.py backtest --csv-dir ./csv     # SYMBOL.csv: datetime,open,high,low,close,volume
```

Checks python can import its own stdlib, installs the packages, runs the demo, then the
backtest and the grid. It stops at the first thing that is wrong and says what to do. With
no Angel One credentials it stops cleanly after the demo - that is a pass, not a failure.

**It checks for the broken Python specifically.** Earlier in this project the tester VPS
had `ModuleNotFoundError: No module named 'encodings'` with both `PYTHONHOME` and
`PYTHONPATH` empty - a damaged install, not a stale variable. The MT5 runners are pure
batch to avoid it; this one cannot be, so step 0 detects exactly that failure and gives
the fix.

Or by hand:

```
python3 ict_options.py backtest --days 120          # per-setup + portfolio report
python3 ict_options.py grid --days 120 --oos 0.3    # parameter sweep, 30% held out
python3 ict_options.py backtest --csv-dir ./csv     # offline, no API
python3 ict_options.py grid --synthetic             # proves the machinery runs, nothing more
```

## 1. Per-setup detail (this already existed)

Every setup, taken or not, with `entry`, `stop`, `target`, `tgt` (what the target was),
`kind` (FVG or OB), `score` out of 9, `status`, `exit`, and `R`. Plus the breakdowns by
score, entry type, session window, exit reason and stock - and, importantly, **why
rejected setups were rejected**. That tally is the same instrument that caught three dead
inputs in the MQL5 grids.

## 2. The portfolio layer (new, and it changes the numbers)

`run_backtest` evaluates each symbol **independently**. It has no idea that two other
positions were already open, that the day's fourth trade is not allowed, or that the loss
cap had already stopped trading. `live_loop` enforces all three in `handle()`.

**Without the same rules in the backtest, you are measuring a different system from the
one that trades**, and always a more profitable one. `portfolio_sim()` replays the setups
in time order through the real caps:

```
max_open              a third concurrent position is refused
max_trades_per_day    the day's fifth setup is refused
daily_loss_limit      everything after the cap is refused
```

The report says how many setups the caps removed. If that number is large, the
per-setup statistics above are describing a system you cannot run.

## 3. Money, and where it comes from

From the sizing rule in `Executor.pick()`:

```
risk_1lot = underlying_risk * delta * lotsize
lots      = risk_per_trade // risk_1lot
```

So a filled trade risks ~`risk_per_trade` by construction, and **gross P&L = R x
risk_per_trade**. Costs come off as `CONFIG["cost_R"]`, a fraction of that.

**`cost_R` ships at 0.12 and you must calibrate it.** 0.12 of Rs2,000 is Rs240 a round
trip, meant to cover brokerage, STT, exchange charges, GST and the bid/ask you actually
cross. Take it from your own contract notes. It is the single most load-bearing
assumption in the whole backtest: at ~0.3R average expectancy, a cost error of 0.1R moves
the result by a third.

What is **not** modelled: delta drift as the underlying moves, theta over the holding
period, and IV changes. All three work against a buyer. Treat the money figure as an
upper bound.

## 4. Periods, not averages

The report breaks P&L down by year and by month and names the **worst** one.

This is the lesson that cost the most in the gold work. `V4_s1_part50` had the best
numbers in a 41-set grid and blew the account in 2 of 4 real-tick years. A total hides the
stretch that would have made you stop trading.

## 5. The grid, with a held-out tail

```
python3 ict_options.py grid --days 120 --oos 0.3
```

Sweeps `min_score`, `disp_atr`, `min_rr`, `entry_at` and `stop_buf_atr` - 162
combinations as shipped - and scores each **twice**: on the first 70% of sessions and on
the last 30%, which no choice is allowed to see.

The split is **by session date, never at random**. Adjacent setups share a market, so a
random split leaks the answer across the boundary.

Two things to read, in this order:

- **Only the `oos_` columns rank anything.** The table of best in-sample results is
  printed directly beneath, deliberately, so you can watch them fail.
- **Count how many combinations are positive out of sample.** If it is near half, the grid
  is finding noise. A real edge shows up as a **cluster** of neighbouring parameter values
  with similar results - not one or two scattered winners. `V3_ema_50_100` was a scattered
  winner, and it went 0 for 23.

## Speed

`prepare()` slices the data and builds the daily context **once**, then every combination
reuses it. Without that, `df[df.index.date < day]` rebuilds a 15,000-element date array on
every call - two per session per symbol per combination, which is 97,200 slices for a
162-combination grid and about five minutes of pure slicing before any strategy code runs.
The first grid attempt produced no output at all for that reason.

With it: **162 combinations over 180 symbol-sessions in ~2.5 minutes**, with a live ETA
printed per combination. On 25 symbols x 120 sessions expect roughly half an hour - run it
with `nohup` and watch the log rather than piping it through `tail`, which buffers
everything until the end.

Anything cached in `prepare()` must be independent of the swept parameters.
`build_context()` reads none of them, which is why it is safe there; if a future `GRID`
key reaches into it, that cache becomes wrong and silently so.

## Honest limits

| | |
|---|---|
| **Option P&L is approximated** | from delta and the sizing rule, not from real option prices. The backtest never sees a premium. |
| **No bid/ask history** | `max_spread_pct` and `min_oi_lots` filter in live, and cannot be checked in the backtest. A strike that was illiquid at 10 AM looks tradeable here. |
| **Entry fills are assumed** | at the setup's limit price when touched. Live crosses the ask plus a buffer. |
| **Costs are a single number** | see above. |
| **Survivorship** | the universe is today's list of liquid names. |

Which is why the order is: **backtest to reject ideas, grid to narrow, then paper for a
full week** before any of it means anything. Paper is where the real bid/ask shows up, and
for an options system that difference is the whole question.

---

# Indicator score components, and the three grids

## Volume was never reaching the engine

`on_bar()` was fed `{t, open, high, low, close}` and the volume column was dropped on the
way in, in **both** the backtest and the live loop. Any volume rule would have been
silently reading zero. Fixed first, because a filter that cannot see its input is worse
than no filter - it looks like a tested idea.

## Six components, and why they are SCORE not GATES

| setting | fires when |
|---|---|
| `sc_vol` | the displacement bar's volume >= `sc_vol_mult` x the 20-bar average |
| `sc_ema` | price on the trade's side of EMA(`sc_ema_len`) |
| `sc_emastack` | EMA fast vs slow aligned with the trade |
| `sc_rsi` | RSI still has **room left** in the direction - not "RSI agrees" |
| `sc_vwap` | price on the trade's side of session VWAP |
| `sc_atr` | ATR expanding against its own average |

All default **off**. Each adds 1 to the confluence score.

**They are score components, not gates, deliberately.** Frequency is the binding
constraint at 0.46 trades/day, and a gate can only reduce it. A score lets `min_score`
decide the selectivity, so the same indicators can run loose (wide net, rank hard) or
tight.

EMAs and RSI are **seeded from prior history**, not from the session open. A 20-period EMA
built from three bars of today is noise wearing an indicator's name. VWAP is the opposite:
session-only, because a VWAP carried over from yesterday is not a VWAP.

## `min_score_frac`, and why a fixed threshold would have been a bug

Switching components on raises the maximum score from **9 to 15**. Comparing `min_score=6`
across those is comparing two different filters and calling it one result. `min_score_frac`
expresses the threshold as a fraction of whatever the maximum is, so rows stay comparable.

## The three grids

```
python3 ict_options.py grid --days 120 --oos 0.3                    # 162, tuning
python3 ict_options.py grid --grid-set freq --days 120 --oos 0.3    #  96, frequency
python3 ict_options.py grid --grid-set ind  --days 120 --oos 0.3    # 192, indicators
```

| set | sweeps | asks |
|---|---|---|
| `default` | score, displacement, RR, entry style, stop buffer | is any corner of the current model positive? |
| `freq` | **windows**, min_score, trade caps, RR | can frequency rise without destroying the edge? |
| `ind` | all 64 on/off combinations of the six components x 3 thresholds | do indicators add anything? |

Every row reports **trades per day** as well as net, in and out of sample.

## What to expect from `ind`, said in advance

Most of it will do nothing. The gold work put ~1,500 backtests into this exact question
and found added indicator filters **monotonically worse** - none +581 down to all five
+200. Saying so now is the point: if the `ind` grid comes back with two scattered winners
out of 192, that is the null result reproducing, not a discovery.

The reason to run it anyway is that the question is not identical. There they were gates
on a zero-edge trigger; here they are ranking components, and the binding constraint is
frequency rather than selectivity.
