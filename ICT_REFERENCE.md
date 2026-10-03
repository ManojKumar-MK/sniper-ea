# ICT concepts, and what this repo actually measured about each

A reference for building the next set, not a tutorial. Every row is tied to code in this
repo and, where we have it, to a measured result. **Where there is no evidence the row
says so** - that is the point of the file.

## The canonical ICT sequence

```
  1. liquidity sweep      price runs a prior high/low, takes the stops, closes back inside
  2. market structure shift   price then breaks the last opposing short-term swing
  3. entry on the retrace     into the FVG / order block left by the displacement
  4. stop beyond the sweep    target at the next pool of liquidity
```

`SR_HTF_StopEntry_EA` implements exactly this, with one difference worth understanding:
instead of entering on the retrace it places a **stop order beyond the structure high**,
so the order only fills if price actually breaks structure. **The entry mechanism is
itself the confirmation.** That is the single design choice most likely to explain why it
is the only component here with an out-of-sample record.

## Concept by concept

| concept | where it is | what we measured |
|---|---|---|
| **HTF bias (structure)** | `TfStructBias` in SR_HTF + SniperEntry v1.40 | The 2-swing HH/HL vs LH/LL test. 79.5% of all SR_HTF evaluations are rejected as "no HTF bias" - it is by far the most selective gate in the whole system. |
| **Premium / discount** | `InpUsePDFilter`, equilibrium of the H4 range | Second most selective: 18.6% of rejections. `V4_nopd` turned it off and lost money at 7.40% drawdown, so it is doing real work. |
| **Liquidity sweep** | `FindBullSetup` / `HasSweep` | Only 0.89% of rejections are "no sweep setup". Sweeps are **common**; the bias and location gates are what make a setup rare. |
| **FVG (imbalance)** | `HasFVG` in SniperEntry v1.40 | **Untested.** Never run. |
| **OTE (62-79% retrace)** | `HasOTE` in SniperEntry v1.40, `SniperOTE_Fib_v1.00.mq5` | **Untested.** The `.ex5` was never even built. |
| **Order block** | `UseOBFilter` in vendor FvgGold | **Untested** on our sets. |
| **Killzones** | `InpKzWindow` + sessions in all EAs | London was positive in **1 year out of 4** on all three timeframes - the most robust negative finding in the project. A 60-minute lead beat a 0-minute lead decisively (+1,119 vs -409 mean). |
| **MSS / break of structure** | implicit in the stop-entry fill | Not isolated as its own input, so never measured separately. |
| **Target at liquidity** | `InpTargetLiquidity` | Demanding the HTF pool be >= `InpMinRR` away **rejected almost every setup**: 5 trades in nine months. `InpTPFallback` fixed it. A liquidity target is a *preference*, never a requirement. |

## Rules this project learned the hard way

**1. More filtering is monotonically worse.** No filters +581 -> all five +200 across the
EMA grids. A filter can only remove trades, so it must be judged on **expectancy per
trade**, never on net. If two sets have the same per-trade expectancy, the filter did
nothing but shrink the sample.

**2. The entry mechanism matters more than the signal.** A stop order beyond structure
only fills on a real break. A market order on an indicator cross fills always. Same
"signal", completely different selection.

**3. Rank on the worst year, never the average.** `V4_s1_part50` looked best in the v4
grid and blew the account in 2 of 4 real-tick years.

**4. A target that ends the run is not a ceiling.** Four sets clustering near +$2,100 was
`InpTargetLock` at +8% completing and halting, not the drawdown guard throttling. Read
the deal list's last month before concluding anything about a plateau.

**5. Static drawdown is not peak-to-trough drawdown.** FundedNext's max is $1,500 **below
the initial balance**. MT5's "Equity Drawdown Maximal %" measures from a high-water mark
and over-reports badly: `V4_s1` showed 8.60% and passed. I ranked four grids on the wrong
number before catching this.

**6. Trade less.** `V4_s1` passed 6 of 8 years on 12-40 trades a year. The scale-out
version traded 40-91 and died twice. Per-trade cost here is ~$2.13, and M5 at 290
trades/year carried 23% drawdown against M15's 4% at 76 trades/year.

## Implementation notes, all of them bugs we hit

- **A `.set` file stores an enum as an INTEGER.** `InpTF1=PERIOD_H1` does not parse; the
  input silently becomes `0` = `PERIOD_CURRENT`. This collapsed H1/H4/D1 onto the chart
  timeframe and **voided three grids**. `M1=1 M3=3 M5=5 M15=15 M30=30 H1=16385 H4=16388
  D1=16408`.
- **The tester report echoes the `.set` as written, not as resolved.** It cannot show a
  value that failed to parse, so "the inputs applied correctly" is not something the
  report can tell you. Have the EA print its resolved inputs.
- **`TimeGMT()` in the tester is derived from the host machine's timezone.** Any EA
  without a GMT-offset input has session hours that depend on the VPS clock. Sweep the
  windows; do not assert them.
- **`WebRequest()` and `Socket*` do not work in the Strategy Tester.** Any cloud model or
  bridge is unbacktestable by construction - see [JEV_XAUUSD.md](JEV_XAUUSD.md).
- **Count rejection reasons and print them.** A run that takes no trades looks identical
  whether a gate rejected everything or was never reached. `InpDiagCSV` in SR_HTF and the
  `SIGNAL TALLY` line in SniperEntry exist because that ambiguity cost three grids.
- **Never select a position by symbol on a hedging account.** `PositionSelect(_Symbol)`
  picked another EA's trade and made all four Sniper EAs report `FLAT` with four of their
  own positions open. Loop `PositionsTotal()` and match the magic.
- **Give every set its own `InpCsvPrefix`.** 33 sets once shared one and the logs
  overwrote each other.

## What is worth testing next, in order

1. **Break-even at 1R is the prime suspect for the two dead years.** 2019 and 2022 held a
   ~50% win rate while the average win collapsed to $17 and $13 against $120 losses -
   wins cut to nothing at entry. `RUN_SRHTF_BE.bat` tests five loosenings on those two
   years only.
2. **FVG and OTE have never been run once.** `RUN_SQ_1Y.bat` is their first data, and
   `SQ_conf_fvg` / `SQ_conf_ote` isolate them so a result is attributable.
3. **MSS as its own input.** The only element of the canonical sequence with no switch of
   its own.

Sources: ICT sequence and killzone conventions cross-checked against
[TradeZella's ICT backtesting guide](https://www.tradezella.com/blog/backtest-ict-strategy)
and a representative automated ICT implementation's input set on
[MQL5 Market](https://www.mql5.com/en/market/product/185364). Everything in the measured
columns is from this repo's own reports.

---

# From the book: *Practical ICT Strategies, 7th Edition*

283 pages, in the repo root. Text extracted with `pypdf`; chapter and page numbers below
are the book's own. This section records only what **changes a decision** - where our code
matches the source, and where it does not.

## The killzone tables confirm our hours (Appendix C, p282)

| killzone | NY (EST) | **GMT** | our `PASS_s1_tgt10` |
|---|---|---|---|
| Asian | 7:00 PM – 10:00 PM | **00:00 – 03:00** | `InpAsiaStart=0 InpAsiaEnd=3` ✓ |
| London Open | 2:00 AM – 5:00 AM | **07:00 – 10:00** | `InpLonStart=7 InpLonEnd=10` ✓ |
| New York Open | 7:00 AM – 10:00 AM | **12:00 – 15:00** | `InpNYStart=12 InpNYEnd=15` ✓ |
| London Close | 10:00 AM – 12:00 PM | 15:00 – 17:00 | **not implemented** |

All three of our windows are the canonical ones. That was worth confirming, because the
hours were inherited rather than sourced and `TimeGMT()` in the tester follows the host
clock. **London Close (15:00–17:00 GMT) has never been tested** - it is a one-line set.

The book's own caveat matters for us: the GMT column shifts by an hour for a few weeks
each spring and autumn because the US and UK change DST on different dates. The EST
column is the anchor. A fixed `InpServerGMTOffset` is therefore wrong for part of every
year.

## Silver Bullet - three one-hour windows we have never tested (ch 15, p148)

| window | NY (EST) | **GMT** |
|---|---|---|
| London | 3:00 – 4:00 AM | **08:00 – 09:00** |
| New York AM | 10:00 – 11:00 AM | **15:00 – 16:00** |
| New York PM | 2:00 – 3:00 PM | **19:00 – 20:00** |

The model: mark M15 buy-side and sell-side liquidity *before* the window; when it opens
drop to **1–3 minute** and wait for a liquidity take followed by an MSS/CISD toward that
draw; enter on the retrace into the **FVG** left by the displacement (its consequent
encroachment - the FVG midpoint - is the exact line); stop beyond the FVG or the swing
that formed it; target the opposite liquidity, ~20–30 pips.

**This is the best-fit next model in the book for what we have.** It needs no moving
average, it runs on M1–M3, and every component already exists in `SniperEntry v1.40`
(`HasSweep`, `HasFVG`) or `SR_HTF` (structure). The one missing piece is consequent
encroachment as the entry line rather than the FVG edge.

## ICT macros (p283) - 20-30 minute windows

Flagship is the **NY AM macro, 13:50–14:10 GMT** (9:50–10:10 EST), marked ★ as the most
reliable. Others: 06:33–07:00, 08:03–08:30, 12:50–13:10, 14:50–15:10, 15:50–16:10,
17:10–17:40, 19:15–19:45 GMT. Nothing in this repo has ever tested a window this narrow.

## Where our code diverges from the book

**1. `SR_HTF` is Turtle Soup with a trend filter bolted on - and the book says Turtle Soup
is a RANGE model.** Chapter 14 (p142): *"Turtle Soup is best in ranging conditions."* The
flow is sweep a range extreme without a clean body close beyond it, MSS back into the
range, enter the retest, stop beyond the sweep wick, target the **opposite side of the
range**. That is `FindBullSetup` + `InpTargetLiquidity` almost exactly.

But we gate it on `InpMinAgree=3` - unanimous H1/H4/D1 trend agreement - and in the v4
diagnostic **79.5% of all evaluations are rejected for "no HTF bias"**. We are demanding
trending conditions for a model the source says works best in ranges. That is a plausible
explanation for 12–40 trades a year, and `InpMinAgree=2` (which is what `V4_s1` and every
passing set uses) may be working *because* it relaxes exactly this.

**2. Our `HasOTE` is missing two things.** The book (ch 12, p131) puts the band at
0.62–0.79 with **0.705 as the sweet spot at its centre** - we have the band but no
preference for the middle. More importantly, step 4 requires *"a lower-timeframe MSS or
CISD up to confirm"* **inside** the band. Our `HasOTE` returns true on price merely being
in the zone, with no confirmation. That is a materially looser test than the book's.

The book also specifies targets as the **negative extensions −0.27, −0.62, −1** of the
leg, which is a different target model from both our fixed-R and HTF-liquidity options.

**3. Sweep definition matches.** The book wants the poke beyond the level *"without a
clean body close beyond it"*; our `HasSweep` requires `low < pool && close > pool`. Same
test.

## Tested since: the Asian range does not transfer

The Asian-range sweep (ch9 p105) was the best book-derived change in the SniperEntry
grid - best net *and* best per-trade on both M3 and M5. Ported to `SR_HTF` and run over
8 real-tick years it took that EA from **6/8 target hits to 0/8**.

Same idea, same instrument, opposite result. SniperEntry's trigger is an EMA cross with
no location filter, so a named liquidity pool adds information. SR_HTF already gates on
HTF structure and premium/discount, so the Asian extremes are one more constraint on an
already rare setup.

**Nothing in the book predicts which way that goes**, and neither did the reasoning that
made it worth trying. Treat every row in the tables above as a hypothesis attached to a
*specific* model, not as a property of the concept.

## What this changes, in order

1. **`InpMinAgree=2` over 3 is now theory-backed, not just empirical.** Every set that
   passed 6 of 8 years uses 2. The book explains why 3 is too strict for a sweep-reversal
   model.
2. **Add London Close (15:00–17:00 GMT)** as a killzone set. One line, never tested.
3. **Fix `HasOTE`** to require a structure shift inside the band, and add 0.705 weighting.
   As written it will pass far too often, which would make `SQ_conf_ote` look like noise
   for the wrong reason.
4. **Silver Bullet as its own model** - the one new strategy here worth building, and it
   lands exactly on the M3/M5 timeframes in question.
5. **`InpServerGMTOffset` is wrong for part of every year.** The book's DST warning says
   so explicitly. Worth a measurement before it is worth a fix.
