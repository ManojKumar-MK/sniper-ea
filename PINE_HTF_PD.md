# HTF PD Arrays — confluence filter for the Pine entry model

Adds four ICT premium/discount checks on H1 / H4 to the EMA9/21 cross in
`ict+ema.pine`. Each is a tickbox, so you can turn one on at a time and see what
it costs you.

Group: **Sniper — HTF PD Arrays 🧊**. Off by default; the script behaves exactly
as before until you enable it.

---

## The four arrays

| Filter | A BUY needs | A SELL needs |
|---|---|---|
| **Liquidity swept** | a prior HTF swing **low** taken by a wick, bar closed back **above** | prior swing **high** taken, closed back **below** |
| **Order block activated** | price back inside the last **down** candle before an HTF displacement **up** | last **up** candle before displacement **down** |
| **FVG tapped** | price re-entered a bullish 3-candle gap | bearish gap |
| **Imbalance filled** | that gap **fully** closed | same, bearish |

**A sweep is a wick, not a close.** If the bar closes beyond the level that is a
break of structure — the opposite read — so it does not count.

> **FVG tapped and Imbalance filled are the same structure at two stages.**
> Filled implies tapped. Ticking both under *All enabled must agree* is almost
> the same as ticking Filled alone. Pick one.

---

## Settings that change the meaning

| Input | Default | |
|---|---|---|
| **Combine** | All enabled must agree | *Any one is enough* is much looser — start there |
| **H1 / H4** | both | with both ticked a condition passes if **either** shows it |
| **Stays valid for … HTF bars** | 6 | 6 on H4 is about a day |
| **Swing length** | 5 | bars either side of an HTF pivot; larger = only major swings |
| **Displacement lookback** | 10 | HTF close beyond this range = displacement; the last opposite candle becomes the OB |

**Recency is the setting that decides whether this means anything.** Too low and
the EMA cross has to happen on the same HTF bar as the sweep. Too high and
"confluence" means something that happened last week.

---

## Two things built in deliberately

**It reads the last *closed* H1/H4 bar.** Every value leaves the detector with
`[1]` applied, so a forming H4 candle cannot flip a signal that already printed.
Without this the filter looks flawless in replay and fails live.

**An empty filter opens the gate, it does not close it.** With the master switch
on but nothing ticked — or no timeframe ticked — signals pass through. A filter
that silently blocks every trade is worse than one that does nothing.

---

## A bug worth knowing about, because it was in the first draft

On the bar a bullish FVG forms, that bar's own low **is** the upper edge of the
gap. A plain overlap test therefore scores every new FVG as instantly tapped, so
the filter passes on nearly every bar and looks like it is working. The detector
now requires `bar_index > <creation bar>`.

If you write your own variant, that is the trap.

---

## The ICT column in the trade log

The log gained a column recording **what ICT context was present when the trade
was taken**. It is written once, at entry, and never changes — so a row always
shows what you actually knew at the time.

```
ICT column                 meaning
LDN·SW·OB·DISC             London, liquidity swept + OB live, buying discount
NY·OB·PREM                 NY session, OB only, price in premium
-·EQ                       no killzone, no array, mid-range
```

| Piece | Book | |
|---|---|---|
| `LDN` `NY` `LC` `ASIA` `-` | Ch 9 | which killzone the entry fell in |
| `SW` `OB` `FVG` `FIL` | Ch 3/5/7 | HTF PD arrays live **for that trade's direction** |
| `SB` | Ch 15 | inside a Silver Bullet hour (3–4 AM, 10–11 AM, 2–3 PM NY) |
| `SMT` | Ch 18 | divergence against a correlated market, in the trade's direction |
| `DO+` `DO-` | Ch 17 | above or below the **daily open** — the Power of 3 cycle position |
| `DISC` `PREM` `EQ` | Ch 5 | where price sat in the dealing range |

A bullish day manipulates **below** the open and distributes above, so a buy
tagged `DO-` is early in the cycle and one tagged `DO+` is already in
distribution. That distinction is the whole of Chapter 17 in one character.

**SMT needs the right second symbol.** Default is `TVC:DXY` with *Negative*
correlation, which is correct for gold. For silver use `OANDA:XAGUSD` and
*Positive*. Wrong symbol, meaningless tag — it is off by default for that
reason.

### What was left out, deliberately

| Model | Why not |
|---|---|
| Market Maker (Ch 19) | needs you to recognise a whole cycle — a judgement call, not a test |
| Unicorn (Ch 18) | needs breaker detection; real work, and it only fires rarely |
| Weekly profiles (Ch 20) | the log's Time column already gives you the day of week |
| Judas Swing (Ch 16) | overlaps `SW` almost entirely — a second name for the same event |

A tag that is only right when you already agree with it tells you nothing. Every
piece above is a clock, a price level, or a comparison.

Only arrays matching the trade's own side are listed — a bullish sweep is not
confluence for a short.

**It records, it never blocks.** Turn on every array, leave the PD master switch
off, and the log fills with context while every EMA cross still trades. That is
the way to gather evidence before you start filtering on it.

Sort your eye down the ICT column against Result. If `·SW` rows win and bare
`-·EQ` rows lose, you have found the filter worth enabling — and worth porting
to MQL5.

> **The Sniper module now defaults to ON** (`enableSniper`). It used to ship
> `false`, which meant the dashboard, the trade log, the levels panel and the
> hit-rate panel all stayed invisible until you found that one switch.

## The dashboard — ICT simple

**`Sniper — Visuals & UI ▸ Dashboard style`**, default **`ICT simple`**. The old
readout is still there as `Full (indicators)`.

A trade needs four things answered: where you got in, where you are out if
you are **wrong**, where you are out if you are **right**, and **why** you are in
it. RSI, MACD, ADX and the bias score answer none of those, so they moved to the
Full style.

**In a trade:**

```
ICT MODEL            LONG
Entry             4300.00
Stop              4291.50  H1      beyond the pool that invalidates the idea
Target       4318.00 3.0R H4       the draw on liquidity
Reason       LDN·SW·OB·DISC
ATR stop          4288.00          grey — reference, not the plan
ATR TP5           4360.00          grey
Status                HOLD
Day P/L     +12.0 p (2W/1L)
Trigger      EMA 9/21 ✕ + PD       grey — said once, at the bottom
```

**The ICT plan is the headline.** `Stop` and `Target` are the *method's* levels.
The ATR ladder is demoted to two grey reference rows — still shown, because the
ladder is what the script actually latches as a result: `TP3`, `SL 💣` and the
Day P/L all come from it, not from the ICT target.

**The `Trigger` row is deliberate.** The entry engine is an EMA 9/21 cross with
optional PD-array and Quality-Filter gates; every *level* above it is ICT.
Printing "ICT" over an EMA trigger without saying so would make the panel a lie,
and you would eventually mis-read your own backtest because of it. One grey row
costs nothing and keeps it honest.

Two further sections fold in below it, so one panel replaces four
(**`ICT simple ▸ include Levels section`** and **`… include Hit-rate section`**,
both default ON):

```
LEVELS
  Above         4318.00  H4       nearest pool — price clears this first
  EQ 50%          4300.00
  Below         4281.00  H1
  OTE buy   4293.18 – 4320.04  ●
  OTE sell  4357.96 – 4384.82
DRAW REACHED           N · hit
  under 2R          43 · 51%
  2 – 3R            49 · 14%
  3 – 5R            40 ·  2%
  5R +              46 ·  0%
```

The by-distance rows answer the one question that matters for your R setting:
**is the minimum you demand actually reachable here?** Read N first.

The two standalone panels therefore default **OFF** now:

| Panel | Default | Why |
|---|---|---|
| ICT Levels (separate) | off | its content is the LEVELS section |
| Draw hit rate (separate) | off | keeps the **per-pool** breakdown, which the dashboard omits |

**Tracking is unaffected.** `hrOn` gates the counting; the new `hrShowPanel`
gates only the panel. Turn the panel off and the numbers keep accumulating —
they just display in the dashboard instead.

### Hover any Reason or Target cell

The compact tags are for scanning; the **tooltip** is for reading. Hovering
`Reason` — on the dashboard or on any row of the log — expands it in full:

```
WHY THIS TRADE WAS TAKEN
LDN·SW·OB·DO-·DISC

── SESSION ──
LDN  London killzone, 02:00-05:00 New York (11:30-14:30 IST in US summer).
     London raids the Asian range, so reversals cluster here.

── HTF PD ARRAYS (H1 / H4) ──
SW  Liquidity SWEPT. A prior higher-timeframe swing was taken by a WICK and
    the bar closed back inside it. That is the stop-hunt before a reversal -
    a close beyond the level would have been a break, which reads the other way.
OB  Order block ACTIVATED. Price traded back into the last opposite candle
    before an HTF displacement. Tapped, not closed through.

── MODELS ──
DO-  Below the daily open (Power of 3, Ch 17). On a bullish day this is the
     MANIPULATION half - early in the cycle, which is where you want to be.

── PRICE LOCATION ──
DISC  Discount. Below the 50% of the dealing range - the buy half.
```

Hovering `Target` explains the draw the same way: the price, the distance in R,
whether it was reached, **which pool** it came from, and — if the tag carries a
`!` — that no pool cleared your minimum R and this was merely the best available.

The tooltip is parsed back **out of the stored tag**, not rebuilt from live
variables, so a row from three weeks ago explains itself with the context that
was true *when it was taken*.

`Reason` is the ICT context captured **at entry**, so it never rewrites itself
later. Read it as: London killzone, HTF liquidity **sw**ept, **o**rder **b**lock
active, price in **disc**ount.

**Flat**, the card does not go blank — it shows what you are actually deciding
while you wait:

```
ICT                  FLAT
Zone       DISC  LDN  DO-
Draw ▲      4318.00 3.0R H4         green = clears the minimum R
Draw ▼      4281.00 1.2R H1         grey  = does not
HTF PD          L ✔   S ✖
Status                WAIT
Day P/L     +12.0 p (2W/1L)
```

### The trade log, same treatment

Every column has its own checkbox in **`Sniper — Trade Log 🧾`**, and **every one
of them is live**. Only `Result` is permanent — a log row with no outcome is not
a log row.

```
Time   Dir    Entry     SL      Exit   Reason           Result
09:45  LONG   4300.00  4288.00  4336.00  LDN·SW·OB·DISC  TP3
11:20  SHORT  4322.00  4334.00  4334.00  NY·FVG·PREM     SL 💣 (TP1)
```

`ICT` is relabelled **Reason** to match the dashboard, and **ICT target** now
defaults **off** — the draw already shows on the dashboard and in the levels
panel, and it was the column making the log too wide to read. Tick it if you
want it back.

---

## The ICT Levels panel

Separate table, default **Middle Left**, listing the levels the *method* points
at rather than the ATR ladder. **`ICT Levels panel ▸ Panel style`**, default
**`Simple`**:

```
ICT LEVELS
  Zone            DISC  LDN  DO-
  Draw ▲     4318.00  3.0R H4
  Draw ▼     4281.00  1.2R H1
  Above        4318.00  H4        the nearest pool, the one price clears first
  EQ 50%           4300.00
  Below        4281.00  H1
  OTE buy   4293.18 – 4320.04  ●
  OTE sell  4357.96 – 4384.82
PLAN — LONG                        only while a trade is open
  Entry            4300.00
  ICT stop     4291.50  H1
  ICT target  4318.00 3.0R H4
```

The Full panel broke each side out into separate H1 / H4 / range-edge rows and
added the OTE sweet spots — 22 rows. You only ever act on the **nearest** level,
so Simple collapses each side to that one and names which pool it came from.
Switch to `Full` when you want the whole ladder.


```
ICT LEVELS
  Zone            DISC  LDN  DO-
DRAW  (if entered now)
  Long ▲         4318.00  3.0R H4    green once it clears the minimum R
  Short ▼        4297.00  0.5R H1!   grey - no pool pays on the short side
LIQUIDITY ABOVE
  H1 high             4356.00  ◄     the draw - first pool price must clear
  H4 high                4402.00
  Range high             4418.00
  EQ (50%)               4339.00
LIQUIDITY BELOW
  H1 low               4322.00  ◄
  H4 low                  4280.00
  Range low               4260.00
OTE ENTRY
  Buy band        4293.18 – 4320.04  ● marks price inside the band
    sweet                 4306.61    the 0.705
  Sell band       4357.96 – 4384.82
    sweet                 4371.39
PLAN — LONG
  Entry                   4340.00
  ICT stop            4322.00  H1
  ICT target     4356.00  1.5R H1
  ATR stop                4318.00    shown for comparison
  ATR TP5                 4395.00
```

The **DRAW** rows are new: they run every bar, not only while a trade is open,
and show what the picker *would* choose for a long and for a short if a signal
fired on this bar. Green means that side clears the minimum R; grey means it
does not. With **Block signals whose draw is under the minimum** turned on, a
grey row is a side that cannot currently trade.

`◄` marks the **nearest** pool on each side — the one price has to clear first.
`●` appears when price is actually inside an OTE band.

### The ICT stop is not the ATR stop

An ATR stop is `entry − 2 × ATR`: volatility arithmetic. The **ICT stop sits
beyond the pool that would prove the idea wrong**, so it moves with the chart
instead of with volatility. Both are shown, deliberately — on the example above
they land 4 points apart, and when they diverge badly that is worth knowing
*before* you take the trade.

The panel reads levels only. It places nothing and blocks nothing.

---

## The ICT target column — where the concept says price is drawing to

`TP1`–`TP5` are ATR arithmetic: `entry ± risk × n`. They know nothing about the
chart. ICT does not work that way — price is delivered to the **opposite
liquidity**, wherever that happens to sit. Chapter 24 says it plainly: sweep one
side of the range, target the other side.

### Why the first version reported such poor R

The original picker took the **nearest** pool on the far side of the entry. That
is a defensible reading — the first pool price must clear — but as a *target* it
is wrong, and it is the reason the logged R looked so thin. The nearest pool is
almost always a minor H1 swing a few tenths of an R away. Price does not draw to
a minor swing; it draws through it.

The book is explicit about the consequence. **Chapter 28, Rule 3: demand a
minimum 1:3 reward-to-risk** — and, in its own words, *"this is why the ICT
method targets clean draws on liquidity: it produces the room for a real 1:3 or
better."* A picker that reports 0.4R is not measuring the ICT draw. It is
measuring the first obstacle.

### The picker now — settings group `Sniper — ICT Target (the draw) 🎯`

| Setting | What it does |
|---|---|
| **Target selection** | `Nearest pool` = the old behaviour, kept so you can compare. `First pool ≥ min R` *(default)* = skip the pools that do not pay, take the nearest one that clears the minimum. `Opposite range edge (ERL)` = always the far side of the dealing range, whatever it costs. |
| **Minimum reward (R)** | Default `3.0`, straight from Rule 3. |
| **When no pool clears the minimum** | `Furthest pool, flagged !` *(default)* names the best draw available and marks it. `No target (—)` leaves it blank. |
| **Block signals whose draw is under the minimum** | Default **OFF**. The only switch here that changes which trades happen — Rule 3 applied as a filter rather than a note. |
| **Include previous day / week high-low** | Default ON. The book names the day's and the week's high and low as the heaviest stop clusters, above any intraday swing. |
| **R measured against** | `ATR stop` *(default)* keeps the number comparable with the TP ladder. `ICT stop` measures against a stop beyond the liquidity on the wrong side — usually tighter, so the same target reads as a larger R. |

Worked example, long from 4300 with a 6.00 ATR risk and pools at H1 4302.5,
H4 4318, PDH 4325, range high 4331, PWH 4360:

| Mode | Target | R |
|---|---|---|
| Nearest pool *(old)* | 4302.50 H1 | **0.42R** |
| First pool ≥ 3R *(new default)* | 4318.00 H4 | **3.0R** |
| First pool ≥ 5R | 4331.00 ERL | 5.17R |
| Opposite range edge | 4331.00 ERL | 5.17R |

Same chart, same entry. The old number was not a small reward — it was the wrong
level.

### Reading the column

```
ICT tgt               Result
4318.00  3.0R ✔ H4    TP3       draw reached
4331.00  5.2R   ERL   SL 💣     draw was past TP5 — the ladder could not get there
4305.00  0.8R   ERL!  TP1       ! = nothing cleared 3R; this was the best there was
—                     TP1       no pool on the far side at all
```

| Field | |
|---|---|
| price | the level price was drawing to |
| `3.0R` | how far that is in R, measured against the stop you chose above |
| `✔` | price reached it before the trade ended |
| `H1` `H4` | an H1 or H4 swing level |
| `ERL` | the dealing-range edge — external range liquidity |
| `PDH` `PDL` `PWH` `PWL` | previous day / previous week high and low |
| `!` | no pool met the minimum; this is the best available, not a valid draw |

### ERL and IRL — the rhythm the tag is naming

Chapter 6: **External Range Liquidity** rests at the edges of the dealing range;
**Internal Range Liquidity** is the FVGs inside it. Price cycles `ERL → IRL →
ERL`. That is why an `ERL` tag reads differently from an `H1` tag — `ERL` means
the target is the far edge of the range, which is the full leg; `H1` means an
intermediate pool on the way.

**Still not implemented:** the IRL half. The picker has no FVG targets, so an
entry that swept an edge and should be drawing to an internal gap gets pointed
at the opposite edge instead. See the gaps list below.

### The number to actually read

**Compare the R against your ladder.** An ICT target at `1.5R` while TP5 sits at
`5R` means the ladder reaches past the draw — you are holding for a level the
concept never pointed at.

**And watch the `✔` rate, not the R.** Raising the minimum R does not make a
target more likely to be hit; it only moves it further away. A 3R draw reached
40% of the time beats a 5R draw reached 10% of the time, and the only way to
tell them apart is to count the ticks in the log.

## Exporting the log

Pine **cannot write files** — no script can. Two routes exist and
**`Sniper — Export 📤`** covers both.

### 1. Pine Logs → copy-paste  *(the one you want)*

`Write each trade to the Pine Logs pane`, default OFF. One CSV line per
completed trade:

```
time,dir,entry,stop,exit,result,code,pips,reason,ind,ict_target
2026-09-19 14:23,LONG,4300.00,4288.00,4336.00,"TP3",3,36.0,"LDN·SW·OB·DISC","E✔W✔M✔V+  R58 A31 B71","4318.00  3.0R H4"
2026-09-19 15:10,SHORT,4322.00,4334.00,4334.00,"SL 💣 (TP1)",-1,-12.0,"NY·FVG·PREM","E✔W✖M✖V-  R49 A14 B43","—"
```

Open the **Pine Logs** tab beside the Pine Editor, select all, paste into a
spreadsheet. This is the **only** route that carries the string columns —
`reason`, `ind`, `ict_target` — so it is the one for actual analysis.

- `code` is the result as a number: `-1` stopped, `0` flat, `1-5` = TP1–TP5.
  Sort or pivot on it.
- String fields are **quoted**, so a `;` delimiter works for locales where
  comma is the decimal separator.
- Emitted at the exact moment the trade enters the log arrays, so the export
  and the on-screen log are always the same set of trades.

**Limits:** TradingView caps how many log messages it retains, and the pane
clears on every recompile. For a long backtest, narrow the chart's date range
and export in chunks.

### 2. Export chart data → a real file

`Also expose numeric columns for Export chart data`, default OFF. Adds seven
hidden plots (`exp_entry`, `exp_stop`, `exp_exit`, `exp_code`, `exp_pips`,
`exp_adx`, `exp_rsi`) that TradingView's own **Export chart data…** writes into
a CSV.

No copying, but two real costs: **one row per BAR**, blank except on trade
rows, so you filter on `exp_entry` being non-empty; and **numbers only** — Pine
cannot plot a string, so `reason` and `ind` cannot come through this route.

Use route 1 for analysis, route 2 when you want a file without copy-paste.

---

## MTF EMA confluence — 3m + 5m

**`Sniper — MTF EMA confluence ⏱️`**, default **OFF** (it changes which trades
fire). The cure for the `flat ↷` rows on a 3-minute chart.

A 3m cross fires constantly and most of those trades are replaced by the next
signal before they resolve. A 5m cross needs real displacement, not one
impulsive 3m candle.

| Setting | |
|---|---|
| **Require the higher timeframe to agree** | master switch |
| **Confirming timeframe** | `5` — one step up from the chart |
| **How they must agree** | `Both aligned` or `Pair within window` *(default)* |
| **Pairing window** | `10` chart bars — 30 minutes on 3m |

**`Both aligned`** — the 3m cross fires only if the 5m is *already* on that
side. Simple, but if the 5m crosses *after* your 3m did, the trade is missed
entirely. On random data this halves signals, by construction: the 5m sits on
the wrong side half the time.

**`Pair within window`** *(default)* — waits for **both**, and enters on
whichever completes the pair. This is the case you described: the 3m crossed
four minutes ago, the 5m just confirmed, **enter now at the 5m cross**. It
works in either order.

```
3m crosses b0, 5m confirms b4   → enter at b4   (the 5m cross)
5m crosses b0, 3m follows  b3   → enter at b3   (the 3m cross)
both cross on b7                → enter at b7, once
3m b0, 5m b11, window 10        → no trade, the pair went stale
3m alone, 5m never              → no trade
```

## The Grade column — A+ / A / B / C

The `Reason` tag lists what was *present*. **`Grade`** says whether that
combination is the one the book actually calls high-probability — so you can
sort the log by quality and ask the only question that matters: **does the EMA
engine do better on A+ than on C?**

Scored at entry, weighted by the book's emphasis rather than a flat count:

| pts | component | why that weight |
|---|---|---|
| **3** | Liquidity **swept** | Ch 6 — the reversal signature, heaviest single element |
| **2** | Correct **half** of the range | Ch 5 — buy in discount, sell in premium |
| **2** | In a **killzone** (LDN / NY) | Ch 9 — LC and ASIA score nothing here |
| **2** | **OB or FVG** active | Ch 7/8 — a real PD array to enter from |
| **2** | Draw clears your **min R** | Ch 28 Rule 3 — somewhere worth going |
| 1 | Power of 3 correct side | Ch 17 — `DO-` buy, `DO+` sell |
| 1 | Silver Bullet window | Ch 15 |
| 1 | SMT divergence | Ch 18 |
| | | **14 total** |

```
A+   10+  AND swept AND correct half
A    8+
B    5+
C    under 5
```

**A+ demands the sweep and the location on top of the score.** A high total
assembled from weak parts is not an A+ setup in ICT terms, and grading it as one
would make the column worthless. Verified: across all 256 possible component
combinations, **A+ is never awarded without both** — and only 12% of
combinations reach it at all, so it stays selective.

### Using it against the EMA strategy

New **`Grade filter`** in the Trade Log: `All` / `A+ only` / `A and above` /
`B and above`.

Set it to **`A+ only`**, read the win rate and Day P/L. Then set it back to
**`All`** and compare. If the two are the same, the ICT context is adding
nothing on top of the EMA trigger — which is worth knowing either way, and is
exactly the test you cannot run without this column.

The grade also appears on the dashboard's live card and as a `grade` column in
the CSV export.

### The GRADE scoreboard on the dashboard

`ICT simple ▸ include Grade section` (ON by default) adds a four-row block to
the dashboard counting every trade already in the log:

```
GRADE            N · win
A+                 4 · 75%
A                 11 · 55%
B                 18 · 44%
C                  9 · 44%
```

`N` is the number of logged trades at that grade; `win` is how many reached a TP
without stopping out first. **Read N first** — a 100% win rate on two trades is
noise, and the column will happily print it.

What the block is for: **A+ should beat C.** If the four rows come out flat, the
ICT context is decorating the EMA trigger rather than improving it, and no
amount of tuning the arrays changes that. This is the same test as the `Grade
filter` on the log, done without having to toggle anything.

It replaces `DRAW REACHED` as the default section — the hit-rate block is still
there under `ICT simple ▸ include Hit-rate section`, now **OFF** by default, and
the standalone panel with the per-pool breakdown is unchanged.

### The column switches actually switch now (2026-09-20)

**Bug, and it was mine.** The log had a `Trade Log style` input whose default —
`ICT simple` — silently forced its own column set and ignored every checkbox
below it. Unticking `Column: Entry` did nothing, and there was no indication
why. The checkboxes were not broken; they were being overridden.

`Trade Log style` has been **removed**. Every column switch is now honoured,
unconditionally, and two that had no switch at all gained one:

| Switch | Default |
|---|---|
| `Column: Time` · `Column: Dir` · `Column: Grade` | on |
| `Column: Entry` · `Column: SL` · `Column: Result value (Exit price)` | on |
| `Column: Reason (ICT context)` · `Column: Indicator state` | on |
| `Column: ICT target (draw on liquidity)` | **off** |
| *Result* | permanent — no switch |

`Dir` and `Grade` were previously hard-wired on. `ICT target` now defaults off,
which is what `ICT simple` was doing anyway, so the shipped layout is unchanged
— it is simply no longer a lie about which settings apply.

One edge case handled: with every optional column off, `Result` becomes column
0, so the `DAY ▸` footer label would overwrite the figure it labels. The label
is skipped in that case.

---

## The Ind column — indicator state at entry

New log column, and the companion to `Reason`. `Reason` says what ICT saw; `Ind`
says what the indicators saw.

```
Ind
E✔W✔M✔V+  R58 A31 B71/29   everything agreed, trending
E✔W✖M✖V-  R49 A14 B43/57   only the trigger agreed, ADX 14 = chop
```

Every mark is scored **against the trade's own direction** — `✔` agreed, `✖`
argued against. "MACD bullish" means nothing on a short; "MACD disagreed" means
a lot. Hover for the full breakdown.

| | |
|---|---|
| `E` | EMA 9 vs 21 — the trigger itself |
| `W` | VWAP side |
| `M` | MACD line vs signal |
| `V` | volume vs its 20-bar average, `+` or `-` |
| `R` | RSI(14), raw — a long at R75 is chasing |
| `A` | **ADX(14), raw — under 20 is a range** |
| `B` | bias score, **own side / opposite side** — `B71/29` is one-way agreement, `B57/43` is the two sides fighting |

### Reading the flat setups

`flat ↷` means the trade was replaced by the next signal before it hit SL or
TP5 — the signature of chop. Filter the log to those rows and read the **`A`**
value. If the flats cluster under ADX 20 while the winners sit above 25, you
have your answer, and these are the switches for it, in order of strength:

1. **Quality Filter ▸ `ADX ≥ 25`** — `enableQFilter` is OFF by default, so this
   is doing nothing right now. It is the single strongest anti-chop filter.
2. **MTF pairing**, above.
3. **Quality Filter ▸ EMA structure** — demands real EMA21/EMA50 separation.
4. **Cooldown** — stops the rapid flip-flop directly.

### The hover now reads the combination

The tooltip used to be a legend — one paragraph per mark, the same text every
time. A legend can never tell you the thing that matters, because **three
components agreeing on a dead, thin bar is not the same setup as three agreeing
in a real trend**, and explaining E, W and M one at a time cannot say so.

It now parses the stored string and opens with a verdict on the whole
combination:

| Verdict | When |
|---|---|
| **CLEAN TREND ENTRY** | all three agreed · ADX ≥ 25 · volume above average · bias split ≥ 40 |
| **CHOP — the flat-setup signature** | ADX < 20 · volume below average · bias split < 20 |
| **INDICATORS DISAGREED** | one or none of E/W/M agreed |
| **TREND ENTRY, PARTIAL AGREEMENT** | ADX ≥ 25 and at least two agreed |
| **RANGE ENTRY** | components agreed but ADX < 20 |
| **MIXED** | none of the above |

Order matters: `E✔W✔M✔V-  R66 A18 B57/43` reads **CHOP**, not "clean," even
though all three marks agree — because the ADX and volume say there was nothing
behind them. That case is exactly why the per-mark legend was not enough.

Below the verdict, each component is then described **with its own value**:
`A31` reads "a REAL TREND"; `A14` reads "a RANGE, and most flat setups show
exactly this"; `R75` reads "overbought — a long here is chasing"; `B57/43`
reads "a TIGHT split: the two sides were fighting."

Everything is parsed out of the stored string rather than rebuilt from live
variables, so a row from three weeks ago reads with its own numbers.

### The verdict is in the cell, not only the hover

The cell now leads with the verdict word and is coloured by it, so the column
can be scanned without hovering anything:

```
Ind
CLEAN     E✔W✔M✔V+  R58 A31 B71/29      green
TREND     E✔W✔M✖V+  R60 A28 B57/43      olive
MIXED     E✔W✔M✖V-  R55 A22 B55/45      grey
RANGE     E✔W✔M✔V+  R61 A17 B62/38      amber
DISAGREE  E✔W✖M✖V+  R52 A30 B57/43      orange
CHOP      E✔W✖M✖V-  R49 A14 B43/57      red
```

Scanning for red is now the fastest way to find the flat setups.

All three views — cell word, cell colour, tooltip paragraph — come from **one
classifier**, `f_indTier`. They cannot drift apart, which they would have if the
word and the paragraph were each written out separately.

### Ind on the dashboard

The live card now carries an `Ind` row under `Reason`, showing the same string
the log does, with the same combined read on hover. The dashboard table was
widened from 30 to 36 rows to fit it with every optional section on at once.

---

## The draw hit-rate panel

Settings group **`Sniper — Draw hit rate 📊`**, default position Bottom Left.

Raising the minimum R does not make a target more likely to be reached — it only
moves it further away. This panel is the check on that.

```
DRAW REACHED      N    hit
  H1 swing        36   14%
  H4 swing        43   16%
  Range edge      24   21%
  Prev day        30   20%
  Prev week       45   16%
BY DISTANCE
  under 2R        43   51%
  2 – 3R          49   14%
  3 – 5R          40    2%
  5R +            46    0%
  still open       1
```

Two questions, answered separately:

- **Which pool pays.** An H4 swing and a previous-week high are not the same
  kind of level, and the counts say which your market respects.
- **How far is realistic.** If `5R +` reads 8% over a hundred samples, the
  minimum R is set past what this market delivers and no filter fixes it.

**Read the N column first.** 100% on N=2 is noise.

### Two things it does deliberately

**It is measured independently of the trade.** When a signal fires, its draw
goes on a watch list and is followed for its own window (default 200 bars),
whether or not the trade survived. *"Did the level get reached"* and *"did my
stop hold"* are different questions — conflating them is how you conclude a good
draw was a bad one.

**A level is resolved before a new one registers**, so it can never be credited
with the high or low of the very bar it was set on. That one-bar optimism is a
real trap; the tracking in the script you pasted has it.

### The baseline to compare against

Simulated on a pure random walk — no edge, no trend — with a 50-bar window, the
distance rows came out `51% / 14% / 2% / 0%`. That is what "this market delivers
nothing" looks like. Your real numbers only mean something measured against that
shape. If `3 – 5R` on real gold is not clearly above a couple of percent, then
`minR = 3` is not a target, it is a wish — and the fix is a tighter stop (switch
**R measured against** to `ICT stop`), not a better filter.

---

### Known gaps in the target model

Ranked by how much they are likely costing:

1. **No IRL (FVG) targets** — see above.
2. **No HRLR / LRLR grading.** Chapter 6's practical rule is *target
   low-resistance liquidity, avoid trading toward high-resistance liquidity*. A
   pool defended by several swings in the way is hard to reach; the picker
   counts no obstacles, so a defended 3R pool and a clean 3R pool look identical.
3. **No equal highs / lows as pools.** The book calls these the richest pools.
   There is no clean source in the file today: the base layer's `equalHigh` is
   just the most recent 3-bar pivot, not an equal high, and the Turtle Soup
   layer's genuine EQH/EQL zones are locked behind `enableTS`.
4. **No liquidity void.** A wide one-sided stretch marks a low-resistance path —
   exactly the condition under which a distant target is realistic.

---

## The position-size panel

Settings group **`Sniper — Position size 🧮`**, default position Middle Right.
Written from scratch — the arithmetic is standard and owned by nobody:

```
lots = risk money / (stop distance × money per price unit per lot)
```

```
POSITION SIZE        ATR stop
Balance                 10000
Risk            1.00%  =  100
Entry                 4321.50
Stop                  4315.50
Stop distance            6.00
Per 1.0 lot / 1.0 move 100.00
LOT SIZE                 0.16
Risk at stop            96.00
1R is worth             96.00
ATR TP5  (5R)            +480
ICT target      +288  (3.0R)
Check                      ok
Quote ccy         USD × 1.00
```

It reads the **live trade's own entry and stop**, so the lot is for the trade on
the chart. `Entry / stop from` picks which stop: the **ATR** one the ladder
latches results on, or the **ICT** one beyond the pool — usually tighter, so the
same money buys a larger position. `Manual` sizes a trade the script hasn't
taken.

**Rounded down to the lot step, always.** Rounding up would quietly risk more
than you asked for — which is why the example shows 96.00 against a 100 request
rather than 100 exactly.

### The part these calculators get wrong

Money per price unit is in the **quote** currency, and only equals your account
currency when the pair is quoted in it. That's true for XAUUSD and every
XXX/USD pair on a USD account, and false for USDJPY, EURGBP and every cross.

So `Quote → account currency rate` is a visible input rather than a guess:

| Symbol (USD account) | Contract | Rate |
|---|---|---|
| XAUUSD | 100 | 1.0 |
| EURUSD · GBPUSD | 100000 | 1.0 |
| USDJPY | 100000 | ≈ 0.0065 *(1/155)* |
| EURGBP | 100000 | the GBP/USD rate |

Left at 1.0 on USDJPY the lot comes out **155× too small**. The `Check` row
turns orange and says `check quote rate` whenever the rate is 1.0 and the quote
currency isn't USD, because a silently wrong lot size is worse than none.

`Check` also reports **`stop too wide for this risk`** — the lot rounded below
your broker's minimum, meaning the trade cannot be taken at that risk. Reduce
the stop distance or accept more risk; do not round up to the minimum and
pretend the risk is unchanged.

### What it does not do

It sizes nothing and places nothing. There is no broker connection in Pine, and
an indicator that appeared to size a position would be lying about what it can
reach.

---

## Killzones and IST

**Sessions are anchored to New York, not to IST, and that is deliberate.**

Killzones are defined in New York time. Pine converts per bar, so US daylight
saving is handled automatically and the windows stay correct all year.
Hard-coding IST clock times would put every session an hour out for roughly four
months a year — a drift that looks exactly like the strategy degrading.

You still *read* everything in IST: the Trade Log timezone is already
`Asia/Kolkata`, so the Time column is IST while the session maths stays NY.

| Session | New York | IST (US summer) | IST (US winter) |
|---|---|---|---|
| Asian range | 19:00–24:00 | 04:30–09:30 | 05:30–10:30 |
| London KZ | 02:00–05:00 | 11:30–14:30 | 12:30–15:30 |
| New York KZ | 07:00–10:00 | 16:30–19:30 | 17:30–20:30 |
| London close | 10:00–12:00 | 19:30–21:30 | 20:30–22:30 |

The winter column applies from early November to mid-March. Both are shown in
each session's tooltip so you never have to work it out at the chart.

## Layers removed (2026-09-20)

Two whole layers were deleted — **413 lines, 11% of the file** — both of which
had shipped OFF and had never been switched on.

| Layer | Lines | Why it went |
|---|---|---|
| **OTE (Optimal Trade Entry)** `enableOTE` | 237 | Drew a golden-pocket box, a CE midline and a 7-level fib grid on the most recent swing leg. The dashboard's `OTE buy` / `OTE sell` rows already give the same bands as numbers, computed independently in the Sniper layer — **those rows are unaffected and stay.** |
| **Buyside / Sellside Liquidity** `enableBSSL` | 174 | Marked resting liquidity at swing highs and lows with pool boxes. Duplicated the `Above` / `Below` rows in the dashboard's Levels section, which read the same pools from H1/H4. |

Before deleting, all **139 identifiers** defined inside those two blocks were
grepped against the rest of the file. The only names that also appear earlier
are `i`, `j`, `p`, `nm`, `top`, `txt` and `band` — generic loop and temp
variables with their own separate scopes, not references. Nothing was orphaned.

Both layers were original implementations rather than inlined third-party
engines, so nothing about attribution changes.

**Still on the list, not yet cut:** the Turtle Soup + Structure layer
(`enableTS`, 673 lines, also OFF by default and never enabled), the standalone
ICT Levels panel, and the `Full (indicators)` dashboard style.

Backup of the pre-deletion file: `ict+ema.pine.bak24` in the session scratchpad.

---

## How to actually test it

1. **Any one is enough**, one array ticked, H1+H4, recency 6. Note trade count
   and win rate from the Sniper log.
2. Repeat per array. The one that moves win rate most is the real edge.
3. Only then try **All enabled must agree** with the best two.

Watch the trade count. Four filters on ALL across two timeframes can cut signals
by 90% — and 6 trades with a 70% win rate tells you nothing at all.

> Not compiled. Pine only compiles inside TradingView, so this has been checked
> structurally (balance, declaration order, the FVG creation-bar case) but not
> against the real compiler. Paste it in and check the console once.
