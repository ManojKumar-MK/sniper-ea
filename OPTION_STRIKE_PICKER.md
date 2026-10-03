# The strike picker

## What the old one did

```python
for lab in ["ITM1", "ATM"]:        # fixed preference order
    ...spread check, OI check...
    delta = CONFIG["delta_est"][lab]   # 0.62 or 0.50, always
    return first one that passes
```

Two strikes considered, a constant delta, and the **first** one that passed - not the
best one. That is a liquidity filter, not a choice.

## The sizing bug it caused

Position size comes from

```
lots = risk_per_trade // (stop_distance * delta * lotsize)
```

so a wrong delta goes straight into the position. Spot 100, 30 days, 25% IV:

| strike | real delta | assumed | Rs2,000 budget actually risks |
|---|---|---|---|
| 95 (ITM1) | **0.796** | 0.62 | **Rs2,568** - 28% over |
| 100 (ATM) | 0.544 | 0.50 | Rs2,180 - 9% over |
| 105 | 0.284 | - | - |

The legacy picker prefers ITM1, and a one-strike-ITM option is usually well above 0.62,
so **the error runs in the dangerous direction on most trades**. Every daily-loss-limit
calculation downstream inherits it.

## What it does now

`CONFIG["picker"] = "ev"` scores **every strike within `strike_window` of ATM** on
expected rupees after that strike's own costs:

```
move   = |target - entry|            on the underlying
gross  = delta x move x qty          what the move is worth
spread = (ask - bid) x qty           paid once, round trip
theta  = theta_per_day x hold x qty  decay while held
net    = gross - spread - theta      <- the strike with the highest net wins
```

Delta, theta and IV are **solved from the live mid price**, not assumed. IV comes from a
bisection against the Black-Scholes price - slower than Newton, but it cannot diverge, and
a bad IV silently mis-sizes every position.

### Why this can beat a preference list

A nearer strike has more delta but a worse spread. A further one is cheap but barely
moves. **Which wins depends on how far the target is** - and that changes every trade. A
fixed `["ITM1", "ATM"]` order cannot express that; an expected-value comparison can.

### The filters, and what each is actually for

| setting | default | rejects |
|---|---|---|
| `min_delta` / `max_delta` | 0.35 / 0.85 | options that barely follow the underlying, and deep ITM where you pay intrinsic for no leverage |
| `max_theta_frac` | 0.25 | a day of decay eating more than a quarter of the target - a losing trade dressed as a winner |
| `min_edge_ratio` | 1.5 | gross expected move worth less than 1.5x the round-trip cost |
| `max_iv` | 0 (off) | buying rich volatility intraday |
| `max_spread_pct`, `min_oi_lots`, `min_volume` | 1.5 / 50 / 0 | illiquidity |

When nothing clears the bar the rejection names the best candidate and why:
`no strike clears the cost bar (best 2900CE: gross Rs1,240 vs cost Rs980)`. That is a
useful message - it says the *signal* was fine and the *instrument* was not.

`CONFIG["picker"] = "legacy"` restores the old behaviour exactly, so the two can be
compared on the same signals.

## What a strike picker cannot do

**It cannot create edge.** The 120-day backtest returned **-0.072R per trade before any
costs at all**. A better instrument improves the execution of a signal; it does not make
a negative-expectancy signal positive.

Worth being plain about: of the two problems, the signal is the larger one, and the grid
running now is the test of whether any parameter corner of the current model is positive
out of sample. The picker matters either way - it was mis-sizing positions by ~28% - but
fixing it is not the same as fixing the strategy.

---

# The Rs5,000-10,000/day target, checked

At `risk_per_trade = Rs2,000`, **Rs5,000/day is 2.5R per day and Rs10,000/day is 5.0R.**

The 120-day run traded **0.46 times a day**. That single number decides the answer:

| expectancy | x 0.46 trades/day | per day |
|---|---|---|
| +0.10R | 0.046 R | **Rs92** |
| +0.20R | 0.092 R | **Rs183** |
| +0.30R | 0.137 R | **Rs275** |
| +0.50R | 0.229 R | **Rs458** |

+0.50R per trade would be an exceptional intraday system, and it still returns Rs458 a
day. **Frequency, not edge quality, is what stands between here and Rs5,000.**

### The two ways to close it, and what each costs

| at +0.30R expectancy | |
|---|---|
| raise frequency | **8.3 trades/day** at Rs2,000 risk (today: 0.46) |
| raise size | **Rs36,364 risk/trade** at today's frequency |

Scaling size alone is not viable on a retail account: with `max_trades_per_day = 4`, a
four-loss day costs

```
Rs 2,000/trade  ->  Rs  8,000
Rs10,000/trade  ->  Rs 40,000
Rs36,000/trade  ->  Rs144,000
```

So the route, if there is one, is **frequency**.

### The frequency ceiling is self-inflicted

From the rejection tally:

```
15.6 setups/day found before any filter
 9.0/day discarded by the two 75-minute windows   <- more than everything else combined
 0.46/day actually traded
```

**The session windows are the binding constraint, not the ICT logic.** That is testable
rather than arguable:

```
python3 ict_options.py grid --grid-set freq --days 120 --oos 0.3
```

96 combinations sweeping `windows` (two75 / morn / wide / allday), `min_score`,
`max_trades_per_day`, `max_open` and `min_rr`, and the per-combination line now reports
**trades per day** alongside the out-of-sample net - because a combination that is
profitable at 0.5 trades/day is irrelevant to this target no matter how good it looks.

### The order this has to happen in

1. **Expectancy must turn positive.** It is currently **-0.072R before costs**, and
   30 of the first 162 default-grid combinations were negative *in sample*. No frequency
   or sizing arrangement rescues a negative edge - it makes it lose faster.
2. **Then frequency.** The `freq` grid says whether a wider window keeps the edge.
3. **Then size**, within what a four-loss day can survive.

Reaching Rs5,000/day needs roughly **8 quality trades a day** at a genuine +0.3R. For
reference, that is ~2,000 trades a year, which is a different kind of system from the one
here - and it is the honest shape of the target, not a reason to abandon it.

---

# Stage 1: pick the stock, then the option, then the trade

The pipeline is now explicit, and each stage is testable on its own.

```
 1. STOCK    rank_day()      which names are worth watching today
 2. SIGNAL   DayEngine       sweep -> MSS -> FVG/OB, scored 0..max
 3. OPTION   _pick_ev()      which strike pays best after its own costs
 4. TRADE    entry / stop / target, caps, square-off
```

## Stage 1 - the ranking

`CONFIG["universe_mode"] = "ranked"` scores every name each morning and keeps the best
`rank_top_n`. It uses **only what is knowable by 09:30** - prior daily bars and the
opening range. The close of the session being ranked is never touched.

| component | weight | what it is for |
|---|---|---|
| `atr_pct` | 1.0 | prior ATR as % of price - you need movement to pay costs with |
| `or_pct` | 1.0 | opening-range size as % of price - today's energy |
| `or_vol_ratio` | 1.0 | opening-range volume vs **this stock's own** 20-day average |
| `gap_pct` | 0.5 | overnight gap |
| `rs` | 1.0 | move versus the universe median - relative strength, either direction |

Each is converted to a **percentile within the day** before weighting. Raw values are not
comparable across stocks - 2% ATR means something different on a Rs300 stock than a
Rs3,000 one - and summing raw numbers would let whichever has the largest units dominate.

**Ranking a small universe reduces frequency, which is the wrong direction for a daily
target.** It earns its keep only by letting the universe *grow*: screen 150 names down to
the 15 actually moving today, rather than watching the same 25 whether or not anything is
happening. Ranking 25 down to 10 makes the Rs5,000 problem worse, not better.

If ranking cannot be computed - a symbol needs ~25 daily bars and a complete opening
range - it **falls back to the full list** rather than returning nothing. An empty
`allowed` set would silently trade nothing all day and look like a quiet market.

### Order of operations in live

Liquidity screen **first**, ranking second. An option you cannot trade is not a candidate
at any rank.

## The backtest/live divergence this exposed

Live drops a symbol at 09:20 if its ATM option fails the spread or OI check. **The
backtest has no equivalent** - it has no historical option chain to check against - so it
trades names that live would have refused.

This cannot be fixed, only known: **the backtest is optimistic by exactly the set of
setups that occurred in options you could not have traded.** It is one more reason the
paper week is not optional, and one more reason `cost_R` should be calibrated from real
contract notes rather than trusted.
