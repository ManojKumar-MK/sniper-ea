# sq-grid - SniperEntry v1.40: HTF gate, ICT confluence, chop filter

```
.\RUN_SQ.bat        23 sets x M3 and M5, 2026, fast model. 46 passes, ~70 min.
```

## Why this is not just more filters

The EMA9/21 cross has no edge on its own. ~1,500 backtests put the median profit factor
at **0.990**, and adding indicator filters made it **monotonically worse** - no filters
+581, all five +200. Three things here are different in kind:

| gate | what it asks | why it might not fail the same way |
|---|---|---|
| **HTF structure** | do H1 swing highs/lows agree with the cross? | It is structure, not another average. The same `TFBias` powers `SR_HTF_StopEntry_EA`, which reached its target in **6 of 8 real-tick years** - the only component in this repo with an out-of-sample record. |
| **ICT confluence** | is there a *reason* this level matters - a sweep, an unfilled FVG, or a 62-79% OTE retrace? | It asks for displaced liquidity, not for more confirmation of the same trend. |
| **Chop filter** | how many times has the EMA pair crossed in the last 30 bars? | This is the actual definition of chop. ADX, EMA separation and VWAP all measure something else. |

Everything defaults **off**, so an existing `.set` reproduces its old result exactly.

## The chop definition, since that was the complaint

```cpp
for(int i=0;i<need-1;i++)
{
   bool a=(e9[i] > e21[i]);
   bool b=(e9[i+1]> e21[i+1]);
   if(a!=b) crosses++;
}
```

`InpChopMaxCrosses` refuses the signal when the pair has crossed more than N times in
`InpChopLookback` bars. A market that crosses six times in thirty bars is chop by
construction, and this is the first thing in the EA that measures it. Two optional floors
come with it: the signal bar's body against ATR (`InpMinBodyAtr`) and the recent range
against ATR (`InpMinRangeAtr`), both of which collapse in a flat tape.

## What each gate does mechanically

- **Sweep** - within `InpConfLookback` bars, a bar pushed through the prior
  `InpSweepPoolBars` extreme and **closed back inside it**. Taking the low and reclaiming
  it is the bullish case.
- **FVG** - a 3-bar imbalance where bar *k*'s low sits above bar *k+2*'s high by at least
  `InpFvgMinPts`, and price has not dropped back through the bottom of that gap.
- **OTE** - price inside the 62-79% retracement of the most recent leg. **The leg must
  point the right way**: for a long, the high has to be more recent than the low, or this
  would call a falling market an entry.
- **HTF gate** - `InpHtfMinAgree` counts agreeing timeframes; `InpHtfNoOppose` is a
  *separate* input for "and none may disagree". Those two were conflated in SR_HTF and it
  made `InpMinAgree` unmeasurable - 1, 2 and 3 picked the same bars and three grids could
  not see it.

## The sets

| block | sets |
|---|---|
| anchor | `SQ_base` - all gates off |
| HTF | `SQ_htf_h1`, `_h1_noopp`, `_h1h4_1`, `_h1h4_2`, `_h1h4d1_2`, `_m15h1_2` |
| confluence | `SQ_conf_any`, `_sweep`, `_fvg`, `_ote`, `_2of3`, `_3of3` |
| chop | `SQ_chop_x2`, `_x3`, `_x5`, `_body`, `_range`, `_all` |
| all three | `SQ_model_a` … `SQ_model_d` |

23 sets, none duplicated. Each leg is isolated before anything is stacked, so a win in
`SQ_model_a` can be attributed rather than guessed at.

## Reading it

**The `SIGNAL TALLY` line, printed at the end of every pass, comes first:**

```
SIGNAL TALLY  crosses=N taken=N | htf=N conf=N chop=N quality=N sameway=N spread=N
```

A gate showing **0 rejections did nothing** - that set is `SQ_base` with extra inputs, and
it is evidence about nothing. This line exists because a run that takes no trades looks
identical whether the gate rejected everything or was never reached, and that ambiguity
cost three SR_HTF grids.

Then: **expectancy per trade, not net.** Every gate can only remove trades, so net falls
as trades fall even when the edge improves. And compare **M3 against M5** for the same
set - per-trade cost here is ~$2.13, which M3 pays far more often, so a gate that works
only on M5 is probably buying back spread rather than finding edge.
