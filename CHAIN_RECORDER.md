# github.com/topics/option-chain - assessed, and what the gap actually is

## The verdict

**Nothing there is worth cloning for this system.** Of the 20 repositories on that topic
page, 19 are live option-chain **viewers** - fetch the current chain, show OI/IV/greeks,
refresh. We already fetch chains, and we compute greeks from solved IV rather than
displaying a vendor's.

| repo | stars | what it is | useful here? |
|---|---|---|---|
| `goldspanlabs/optopsy` | 1.5k | the only real backtesting library | **no - see below** |
| `VarunS2002/Python-NSE-Option-Chain-Analyzer` | 665 | live NSE chain + indicators | no, viewer |
| `TechfaneTechnologies/QtsApp` | 103 | chain with IV/OI/greeks | no, we compute these |
| `markov404/AngelOneOptionChainSmartApi` | 17 | our exact broker, chain fetch | no, already have it |
| `devag7/Indian-Option-MCP` | 12 | MCP server, "34+ strategies" | no, live tooling |
| the rest | <80 | viewers, notifiers, OI extractors | no |

### Why optopsy does not fit, specifically

It is a serious library, and it is the wrong shape twice over:

1. **It is end-of-day.** It groups by DTE and exits on `exit_dte`. Our system enters on a
   5-minute bar and squares off at 15:15. It cannot express an intraday trade.
2. **It requires historical option chain prices** - `quote_date, strike, bid, ask` per
   row. That is precisely the data we do not have.

## The real gap, which no repo on that page fills

Our backtest models option P&L as `delta x underlying_move x qty`, with spread and theta
charged from `cost_R`. It never sees a real option price. Three consequences, all
one-directional:

- `max_spread_pct` and `min_oi_lots` filter in live and **cannot** be checked in the
  backtest, so it trades strikes that were illiquid at the time.
- Delta drift, theta over the hold and IV changes are unmodelled, and all three work
  against a buyer.
- The live 09:20 liquidity screen drops symbols the backtest keeps.

**The backtest is optimistic, and by an unknown amount.** That is not fixable with better
code. It is fixable only with data.

## So: record it

`chain_recorder.py` snapshots the option chain during the session and stores it. Run it
alongside paper trading and in a few months there is a real dataset - with the bid/ask
and OI that actually existed at 10:35 on a Tuesday - to re-run every backtest against.

```
python3 chain_recorder.py --interval 300          # every 5 min, the configured universe
python3 chain_recorder.py --interval 300 --top 25 # the 25 best-ranked names only
```

Output: one gzipped CSV per day in `ict_data/chains/`, one row per strike per snapshot:

```
ts, symbol, expiry, strike, side, bid, ask, ltp, oi, volume, spot
```

At 25 symbols and 9 strikes a side that is ~450 tokens per snapshot, 9 quote calls, and
roughly 675 calls across a session - comfortably inside the rate limit and about 3 MB a
day compressed.

**Start it now even though nothing uses it yet.** The data cannot be back-filled: Angel
One serves the *current* chain only, so every day it is not running is a day that can
never be backtested honestly. It is the cheapest possible insurance against the one gap
in this system that money cannot close later.

---

# How to use it

## Run it once, by hand, to see it work

```
./record.sh                       macOS / Linux
.\RECORD.bat                      Windows VPS
```

Defaults: every 5 minutes, 9 strikes each side of ATM, stops at 15:30. It exits on its
own - there is nothing to stop.

**Only on a weekday.** It refuses at the weekend by design, which is what the
"Weekend - nothing to record" message is. Note that Angel One keeps serving Friday's
closing quotes on a Saturday, so without that guard you would silently record a day of
stale prices as if they were live.

## Then schedule it, because the value is in never missing a session

### Windows VPS - Task Scheduler

```powershell
schtasks /create /tn "OptionChainRecorder" /tr "C:\path\to\RECORD.bat" ^
  /sc weekly /d MON,TUE,WED,THU,FRI /st 09:14 /rl HIGHEST /f
```

09:14 so it is logged in before the 09:15 open. No stop task: `--until` ends it.

### macOS / Linux - cron

```cron
14 9 * * 1-5  cd /path/to/ema-strategy && ./record.sh >> ict_data/cron.log 2>&1
```

A Mac must stay awake - `record.sh` wraps the run in `caffeinate` for exactly that
reason. A sleeping laptop records nothing and the gap cannot be recovered.

## Check it worked

```
ls -la ict_data/chains/                      # one .csv.gz per session
zcat ict_data/chains/chain_20261006.csv.gz | head -3
zcat ict_data/chains/chain_20261006.csv.gz | wc -l
```

A full session at 5-minute intervals, 25 symbols, 9 strikes a side should be roughly
**70 snapshots x 25 x 38 ≈ 66,000 rows**, about 3 MB compressed. Far fewer means symbols
were dropping out - the log says which.

## Where to run it

| | pros | cons |
|---|---|---|
| **VPS** | always on, already whitelisted as the primary IP | python was broken there once - `RUN_ICT.bat` step 0 diagnoses it |
| **Mac** | works today, `.env` already set | must stay awake 09:15-15:30 IST every weekday |

The VPS is the right home. It is the machine that is already up at 09:14.

## What to do with the files

Nothing, for now. Let them accumulate. They are gitignored (`ict_data/chains/`) because
they are data, not code - but **back them up**, since they cannot be regenerated.

In a few months, the files answer three questions the current backtest has to assume:

1. Was the strike the picker chose **actually tradeable** at that minute - what were its
   real spread and OI?
2. What did the spread **actually cost**, trade by trade, instead of one flat `cost_R`?
3. How much do delta drift, theta and IV move the result over a 3-hour hold?

Until then it costs ~3 MB a day and one scheduled task.

---

# CORRECTION: the data CAN be partly back-filled

I recorded above that historical option data "cannot be back-filled". That is true of
Angel One, which serves only the current chain. It is **false of NSE**, and following
`devag7/Indian-Option-MCP` to its NSE endpoints is what surfaced it.

NSE publishes an **F&O bhavcopy** every session, free and archived for years:

```
https://nsearchives.nseindia.com/content/fo/BhavCopy_NSE_FO_0_0_0_YYYYMMDD_F_0000.csv.zip
```

Per contract per day: OHLC, settlement price, the underlying price, **open interest**,
change in OI, traded volume and lot size. Downloaded 124 sessions - **4,062,500 option
rows** - in a few minutes.

| closes | does not close |
|---|---|
| the liquidity filter: real OI per strike per day | **bid/ask** - bhavcopy is end-of-day |
| a real settlement price per strike | anything intraday |
| the NSE holiday calendar - a missing bhavcopy *is* a holiday | spread, the largest single cost |

So the recorder is still needed, for spread. It is no longer the only route to everything.

## What it changed, measured

`min_oi_lots = 50` is applied in live and was **never applied in the backtest**. Across
388,036 real rows only **33% of strikes clear 50 lots; the median strike holds four.**
Applying the real OI, on 120 sessions:

| model | | trades | per day | expectancy |
|---|---|---|---|---|
| ICT | without filter | 55 | 0.46 | **-0.072R** |
| ICT | **with real OI** | 34 | 0.28 | **+0.036R** |
| ORB | without filter | 1,224 | 10.20 | -0.029R |
| ORB | **with real OI** | 795 | 6.62 | -0.030R |

**ICT's expectancy flips sign.** Removing the 38% of trades that occurred in strikes with
no open interest turns -0.072R into +0.036R - the losses were concentrated in options
that could not have been traded. Part of the earlier "no edge" verdict was measuring
trades that never existed.

Two things that have not changed, and both matter more:

- **+0.036R is still below `cost_R = 0.12`.** Sign-flipped is not profitable.
- **34 trades is not a sample.** At 0.28 trades a day this is further from the Rs5,000
  target than before, not closer.

ORB is unaffected in expectancy (-0.029 to -0.030R) and keeps usable frequency at 6.62
trades a day.

## What this obliges

The 162-combination grid that produced "16 of 162 positive out of sample" ran **without**
the liquidity filter. That verdict was reached on a dataset containing trades live would
have refused, so it has to be re-run. It may not change - ORB's did not - but it is no
longer a result I would quote.

```
python3 bhavcopy.py --days 180            # download and cache, once
```
