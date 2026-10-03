# sq-grid - SniperEntry v1.40: HTF gate, ICT confluence, chop filter

```
.\RUN_SQ_1Y.bat     23 sets x M3 and M5, a FULL YEAR. 46 passes, ~90 min.   <-- use this
.\RUN_SQ.bat        the same sets over calendar 2026, which is ~9 months of data
```

`RUN_SQ_1Y.bat` runs **2025.10.01 to 2026.09.30** - a genuine twelve months ending at the
last data the broker has. Calendar 2026 is only about nine months today, which would
under-report every trade count by a quarter. The last complete calendar year is 2025, and
the command for it is in the runner's header.

Both are resumable: a pass whose report already exists is skipped, so an interruption
costs nothing.

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

---

## Book sets - `sets_sq_book`, 17 sets from *Practical ICT Strategies 7th Ed*

```
.\RUN_SQ_BOOK.bat     17 sets x M3 and M5, a full year. 34 passes, ~70 min.
```

v1.41 adds six inputs, all default off, each making an existing test **stricter in the way
the book specifies**. The point is not more filters - it is that our versions were looser
than the source.

| input | book | what ours did instead |
|---|---|---|
| `InpFvgUseCE` | ch5 p58: consequent encroachment is the FVG's **50% midpoint**, "the single most reactive point inside a gap"; price "often turns from the CE rather than needing to fill the whole gap" | accepted any price that had not retraced through the gap |
| `InpOteUseSweet` | ch12 p131: band 0.62-0.79 "with **0.705** as the sweet spot at its centre" | accepted the whole band equally |
| `InpOteNeedShift` | ch12 p132 step 4: "look for a lower-timeframe **MSS or CISD** up to confirm" | returned true on price merely being in the zone |
| `InpSweepAsianRange` | ch9 p105: the Asian range high/low "become tomorrow's liquidity... price often sweeps one side of that range... then reverses" | used an N-bar extreme, which only guesses where liquidity sits |

`InpOteNeedShift` is a **proxy** and is commented as one: a full MSS needs its own swing
tracking, so it requires the last closed bar to take out the prior bar's extreme in the
trade direction. The point is that "in the zone" alone is not the book's rule.

### Session windows the book gives us for free

The killzone strings are **New York time** - `KzNameNow()` converts with `ServerToNY()` -
so Appendix C's EST tables drop in with no offset arithmetic. That was read out of the
code, not assumed.

| set | window (NY) | source |
|---|---|---|
| `BK_sb_london` | 03:00-04:00 | Silver Bullet, ch15 |
| `BK_sb_nyam` | 10:00-11:00 | Silver Bullet |
| `BK_sb_nypm` | 14:00-15:00 | Silver Bullet |
| `BK_lonclose` | 10:00-12:00 | London Close killzone, App. C - **never implemented here** |
| `BK_asia_book` | 19:00-22:00 | the book's Asian **killzone** is 7-10 PM; our old sets used 1900-2400, which is the Asian **range** |

Silver Bullet sets run `InpKzLeadMin=0` deliberately: the book's rule is "no window, no
trade", so a lead would defeat the model.

### Reading it

`BK_base` is `SQ_model_a` and every book set differs from it by **one idea**, so anything
that does not beat it *per trade* is a book rule that does not survive contact with gold.

Watch trade count on the Silver Bullet sets - one hour a day is tiny, and under ~30 trades
in a year says nothing whatever the net. And `BK_ce` matters beyond itself: if the CE
version helps, our FVG test was simply too loose and **every earlier FVG number is
suspect**.

---

## If a pass is taking minutes instead of seconds

Every logging switch in the inherited base set was **on**, and all of them are per-event
I/O:

| input | cost in a grid |
|---|---|
| `InpEchoLogToTerminal` | prints a JSON object to the Experts tab **per event** - by far the worst in the tester |
| `InpLogSkips` | writes a line for **every EMA cross that was not taken** - on M3 with no filters that is thousands |
| `InpUseCsvLog` / `InpUseJsonLog` | appends to a `.csv` **and** a `.jsonl` per event |
| `InpShowPanel` | `Comment()` redraw on every tick |
| `InpPersistState` / `InpHeartbeatMin` | state file rewrites |

All 40 sets in `sets_sq` and `sets_sq_book` now have these **off**. None of it was being
read: the analysis parses the `.htm` reports and the tally file.

**Stopping a run is safe.** Any pass whose report already exists is skipped, so only the
pass that was in flight is redone. Nothing is corrupted and nothing is repeated.

## `tally_<set>.csv`

With terminal echo off, the `SIGNAL TALLY` line still prints to the journal - but the
journal is not collected per pass, so the EA also writes `SniperEA_tally.csv` and
`RUNSETS.bat` renames it to `tally_<set>.csv` beside the report. It carries the counts and
**which gates were actually on**:

```
crosses, taken, rej_htf, rej_conf, rej_chop, rej_quality, rej_sameway, rej_spread
gate_htf_on, gate_conf_on, gate_chop_on, fvg_use_ce, ote_sweet, ote_shift, sweep_asia
```

The second block exists so a set can never again be *assumed* to have had a gate enabled -
the file states it. That is the same lesson as the SR_HTF enum bug: the report echoes the
`.set` as written, so only the EA can say what it actually used.
