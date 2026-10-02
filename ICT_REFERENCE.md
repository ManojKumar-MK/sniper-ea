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
