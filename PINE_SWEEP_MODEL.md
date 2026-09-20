# ICT Sweep Model — PDH / PDL raid

`ict_sweep_model.pine` — a **standalone** script. It shares nothing with
`ict+ema.pine`; Pine namespaces are per-script, so both can sit on one chart.

Written to be ported to MQL5, which is why every decision is mechanical and
taken on a closed bar.

---

## The model

| | |
|---|---|
| **1 · RAID** | Price trades **through** yesterday's high (or low) and **closes back inside**. |
| **2 · MSS** | Within N bars, price **closes through the last opposing swing** — the lower-timeframe structure shift. |
| **3 · ENTRY** | Limit in the **FVG** left by the displacement leg that broke structure. |
| **4 · STOP** | Beyond the raid extreme, plus an ATR buffer. |
| **5 · TARGET** | Fixed 1:N, or the opposite previous-day level. |

**A close beyond the level is a breakout, not a raid**, and arms nothing. That
single distinction is the model: fading a stop-hunt and buying a breakout are
opposite trades, and the same candle can look like either until you ask where
it closed.

### MSS, and why the first draft was wrong

The first version confirmed on *a close beyond the raid candle*. That is a proxy
for displacement, not a structure shift — **it fires inside a continuing trend
with no turn at all**, which is the opposite of what the setup is claiming.

Confirmation is now, by default, **a close through the most recent opposing
swing** (`ta.pivothigh` / `ta.pivotlow`, length adjustable, default 2). A swing
needs `mssPivot` bars printed *after* it before it confirms, so the level being
broken was always visible in real time — no lookahead, and an EA can do the same.

While a raid waits, a **nearer** swing may form; the MSS level follows it in.
Breaking the closest structure is what short-term MSS means.

The two older tests are kept as options so you can **measure** what the stricter
one is worth rather than take it on trust.

### FVG entry

The leg that breaks structure normally leaves a 3-candle imbalance, and price is
expected back into it before delivering. That gap is the entry.

- **Near edge** — fills most often, worst price of the three
- **CE (50%)** — the ICT standard, consequent encroachment *(midpoint)*
- **Far edge** — best price, most often missed

`If the leg left no FVG` defaults to **Skip the trade**. Displacement without an
imbalance is weaker displacement, and skipping keeps the model honest about what
it is. Switch it to `Enter at market` and those trades are logged as
`MSS·nogap`, so you can check afterwards whether they were worth having.

`Stop placement` can move to **beyond the FVG** — much tighter, so the same
target is a far larger R, at the cost of being stopped by an ordinary retrace
through the gap. Tighter stops buy R with hit rate; the panel shows the trade.

### Three guards on the FVG entry

These are the cases that would otherwise produce numbers that look good and
aren't:

1. **A gap price has already passed** would fill the instant it is placed — a
   market order wearing a limit order's name. If the candidate price isn't on
   the retrace side of the close, the setup is treated as gapless.
2. **Far-edge entry with a beyond-the-FVG stop** leaves a risk of one ATR
   buffer and an R figure that is arithmetic rather than a trade. That
   combination falls back to the raid extreme for its stop.
3. **Any stop not genuinely on the losing side of the entry**, or within two
   ticks of it, drops the trade rather than logging a 40R win that was never
   available.

Optional: previous **week** high/low as well (heavier pools, a few setups a
month rather than daily).

---

## About "sure-shot"

There isn't one, and a model that appeared to win every time would mean a bug
rather than an edge. What a **fixed** 1:N does give you is an exact breakeven:

```
at 1:N you need better than  1/(1+N)  wins

1:2 → 33.3%      1:3 → 25%      1:5 → 16.7%
```

The stats panel prints your measured win rate directly beside that number, and
says which side of it you are on:

```
SWEEP MODEL            1:3
Trades                  47
Won / lost / BE     14/31/2
Win rate             29.8%      ← green when above the line below
Breakeven needs      25.0%
Expectancy          +0.19 R
Total               +8.9 R
Verdict     clears breakeven
```

**`Verdict` says "too few trades to judge" under 30 trades**, because a win rate
from 9 trades is noise and reading it as a result is how people talk themselves
into an EA that loses money.

Raising N does not raise expectancy on its own — it lowers the hit rate at the
same time. The panel is what tells you which way that trade-off actually went
on your market.

---

## Two settings that decide whether the backtest is honest

**`If one bar touches both`** — when a single candle spans your stop *and* your
target, the chart cannot say which came first. Default is **stop first**.
Switching it to target-first will make every number above look better and none
of that improvement is real. It is there so you can measure how much of your
result depends on the assumption.

**`Flat after …`** — a cutoff session, not "the last bar of the day". A live
script cannot know a bar is the day's last until the next bar opens, and
neither can an EA, so building on that would be untradeable.

---

## Testing order

1. **Both sides, 1:3, market entry, no killzone filter.** Get 50+ trades.
2. Read `Verdict`. Below breakeven → change the model, not the target.
3. Try `N` at 2 and 5. Expectancy usually peaks in the middle; the panel shows
   where.
4. Compare the three entries — **FVG**, **market at MSS**, **50% of the raid
   leg**. Compare trade *count* as well as expectancy: a better average fill on
   half as many trades is not obviously a better model.
5. Then the FVG side: near edge → CE → far edge, watching how many setups stop
   filling at all.
6. Only then add the killzone filter, and check it did not just cut the sample
   to something too small to read.

---

## Porting to MQL5

The script is deliberately EA-shaped:

- **No repainting.** PDH/PDL use the `[1]` + `lookahead_on` idiom, so on today's
  forming daily bar you read yesterday's completed high.
- **Bar-close decisions.** Arming and confirmation run under
  `barstate.isconfirmed`.
- **One open path.** Every entry route raises a request; a single block opens
  the trade. Port that one block and the two versions take the same trade.
- **Frozen levels.** Stop and target are set at entry and never recalculated.
- **`Fire alerts on entry and exit`** emits a parseable line:

```json
{"model":"ict_sweep","event":"entry","side":"sell","level":"PDH",
 "entry":4321.50,"stop":4329.80,"target":4296.60}
```

The one thing that will differ live: the limit entry assumes a touch fills. Real
fills need the spread, so expect slightly worse than the panel says.

---

> **Not compiled.** Checked structurally — delimiters, declaration order, no
> future references, no global writes inside functions (Pine forbids these, and
> the first draft of this script had two of them). Paste it into TradingView and
> read the console once.
