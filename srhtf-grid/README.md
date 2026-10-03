# srhtf-grid — SR_HTF_StopEntry_EA

36 sets, M5.

```
.\RUN_SRHTF.bat        ONE CLICK: compile -> prove on one set -> run 36 sets over 2026
.\RUN_SRHTF_FAST.bat   the same 36 sets on Model=1 - ~1 hour instead of ~11, as a screen
.\RUN_SRHTF_4Y.bat     the same 36 sets over 2023-2026 (144 runs), once one looks good
```

**Budget the time before starting.** Real ticks cost ~19 min per set per year:

| | passes | time |
|---|---|---|
| `RUN_SRHTF_FAST.bat` | 36 | ~1 hour |
| `RUN_SRHTF.bat` | 36 | ~11 hours |
| `RUN_SRHTF_4Y.bat` | 144 | ~45 hours |

The fast pass writes to `results_2026_M5_m1` and is a **shortlist only** — 1-minute
OHLC fills stop orders at prices the tape may never have printed, and this EA is
entirely stop-entry, so its numbers are optimistic. Take the survivors to real ticks.

`RUN_SRHTF.bat` compiles the EA, runs **`SR_ctrl` alone** and stops if that produces no
report, then runs the other 35. The grid EA burned a whole 100-pass run producing
nothing, so nothing here commits to 36 passes before one has worked.

**If step 2 prints `NO REPORT` after a pass that clearly ran** (the log tail shows
`Test passed in 0:19:xx` and `automatic testing finished`), the run was fine and only
the report went missing — an absolute `Report=` in the `.ini` is silently not written.
Fixed by asking for a bare name and moving the file afterwards. Pull and rerun.

**If step 2 prints `(0 files)` and `ZERO RUNS`,** you are on a build from before the
single-`.set` fix. `RUNSETS.bat` read the extension off `%~x1`, which is empty by then
because the argument loop has already shifted every argument away — so a `.set` file
fell through to the folder branch and globbed `SR_ctrl.set\*.set`, which matches
nothing. It now reads the extension off the variable instead. Pull and rerun.

---

## `InpResetState=true` in every set, and why that is not optional

`GVName()` builds its keys from `InpMagic`:

```cpp
string GVName(string s) { return "SRHTF_" + IntegerToString(InpMagic) + "_" + s; }
```

`InpMagic` is identical in all 36 sets, so they share one global-variable namespace. A
set that trips `acc_halt` leaves `SRHTF_52741_acc_halt` behind, and the **next** set
reads it at `OnInit`:

```cpp
g_accHalted = GlobalVariableCheck(GVName("acc_halt"));
```

and starts already halted — taking no trades at all, for the whole run.

Two things set `acc_halt`, and the second is the nasty one:

| | |
|---|---|
| the max-loss guard | a **bad** set poisons the ones after it |
| `InpTargetLock` reaching `InpTargetPct` | a **good** set poisons the ones after it |

So without the reset, the better a set performs the more damage it does to the rest of
the grid — and the result would look like a strategy that stops working halfway through
the alphabet. `InpResetState=true` calls `GlobalVariablesDeleteAll(GVName(""))` at
`OnInit`, which clears it.

`InpNewsFilter` is set `false` too. The EA already ignores it under `MQL_TESTER`, so this
only makes the sets say what they mean.

## The chart timeframe does not matter

`_Period` appears **nowhere** in the source — every read uses an explicit input
(`InpEntryTF`, `InpTF1..3`, `InpRangeTF`). M5 is used to match `InpEntryTF`, so the
drawings and the analysis line up, but the behaviour is the same on any chart.

## The blocks

| block | sets |
|---|---|
| control | `SR_ctrl` — the author's own defaults |
| HTF agreement | `agree1` `agree2` — how much of the A+ gate is earning its place |
| reward:risk | `rr2` `rr4` `rr5` `fixedrr` |
| location / structure | `nopd` `swing1` `swing3` `range15` `range60` |
| the sweep | `sweep6` `sweep20` `pool10` `pool40` |
| the stop order | `buf5` `buf50` `expiry3` `expiry12` `sl15` `sl60` |
| entry timeframe | `entry_m1` `entry_m15` |
| HTF set | `htf_m15h1h4` |
| sessions | `london_only` `ny_only` `wide_sess` |
| management | `nobe` `be2` `trades4` `sl_wide` |
| risk | `risk025` `risk1` |
| funded | `fn_nolock` `fn_tight` |

`SR_fn_nolock` and `SR_fn_tight` turn `InpTargetLock` **off** on purpose. With it on, a
run stops the moment it reaches +8% — which is correct for a challenge and useless for
measuring a year, because every good year truncates at the same number.

## Reading it

1. **`SR_ctrl` first.** If the author's defaults have no edge across four years, nothing
   downstream supplies one.
2. **`agree1` / `agree2` against `ctrl`.** `InpMinAgree=3` is the A+ premise. If 1 or 2
   does as well, the premise is not doing the work.
3. **Equity drawdown against `InpMaxGuardPct`**, not balance drawdown.
4. **Then 2024.** Every grid EA reviewed lost there, and so did both of our own
   strategies — it is the year that has separated real from fitted so far.
5. **Rank by the worst year**, never the best.

---

## 2026 fast screen (Model=1, Jan-Sep) - what it found

All 36 ran. `results_2026_M5_m1/`. **35 of the 36 sets are uninformative**, and the
reason is worth more than the numbers.

### The grid could not test what it was built to test

15 sets returned numbers *identical* to `SR_ctrl` - same net (-368.89), same 5 trades,
same drawdown. The reports embed the inputs actually used, and all 35 applied
correctly, so this is not a harness fault: those inputs genuinely changed nothing.

| set | input changed | trades |
|---|---|---|
| `SR_ctrl` | - | 5 |
| `SR_agree1` | `InpMinAgree` 3 -> 1 | 5, identical |
| `SR_agree2` | `InpMinAgree` 3 -> 2 | 5, identical |
| `SR_nopd` | `InpUsePDFilter` off | 5, identical |
| `SR_entry_m1` | `InpEntryTF` M5 -> M1 | 5, identical |
| `SR_entry_m15` | `InpEntryTF` M5 -> M15 | 5, identical |
| `SR_sweep6` / `SR_sweep20` | `InpSweepWindow` 12 -> 6 / 20 | 5, identical |
| `SR_trades4` | `InpMaxTradesDay` 2 -> 4 | 5, identical |

**`InpMinAgree` is not a relaxable threshold, because of `dn == 0`:**

```cpp
if(up >= need && dn == 0) return 1;
if(dn >= need && up == 0) return -1;
```

Lowering `need` to 1 still requires that **no** timeframe disagrees. The no-opposition
clause dominates the count, so 1, 2 and 3 select almost the same bars. The "3 TFs must
agree = A+ only" premise cannot be measured against 1 or 2 until that is separated.

### One trade a month, and one binding constraint

`SR_ctrl` took **5 trades in nine months** - none at all before 4 May. The gate is
`InpTargetLiquidity`:

```cpp
tp = (buy) ? rHi - InpTPBufPts*_Point : rLo + InpTPBufPts*_Point;
double rr = MathAbs(tp - entry) / risk;
if(wrongSide || rr < InpMinRR) { ...skipped... }
```

The H4 30-bar range extreme has to sit **3R or further** beyond entry. It almost never
does, so nearly every valid sweep is discarded - which is also why loosening the
*upstream* filters changes nothing: they were never what was rejecting the setups.

`SR_fixedrr` (`InpTargetLiquidity=false`, so TP is a flat 3R) is the only set that got
past it: **30 trades instead of 5, 6x the sample.**

### The one candidate, and why it is not yet a result

| | `SR_fixedrr` |
|---|---|
| net | +514.48 |
| trades | 30 |
| win rate | 63.3% |
| profit factor | 1.37 |
| expected payoff | $17.15 / trade |
| equity DD | 745.64 (**2.92%**, inside `InpMaxGuardPct` 6.0) |
| avg win / avg loss | 99.82 / -124.25 |

Three reasons to hold off:

1. **It is not significant.** Average win is *below* average loss (payoff ratio 0.80),
   so breakeven needs 55.4% wins. It scored 63.3%, but the standard error of a win rate
   on 30 trades is ~8.8 points. The edge is inside one standard error of nothing.
2. **`Model=1` flatters it specifically.** 1-minute OHLC fills stop orders anywhere in
   the bar's range, and every entry here is a stop order. This is the set most exposed
   to that bias, being the one that actually trades.
3. **Longs and shorts disagree** - shorts 73.7% won (19 trades), longs 45.5% (11). On a
   year that trended, a short-only edge on gold is more likely a regime artifact than a
   model.

### Next grid, not next live set

The useful move is a second grid with `InpTargetLiquidity=false` as the **baseline**,
re-testing the knobs that were unmeasurable while 5 trades was the sample: `InpMinRR`,
break-even, sessions, and `InpMinAgree` once `dn == 0` is separated from the count.
Then real ticks, then 2023-2025.

---

## v1.10 and the v2 grid - chasing $100/day

```
.\RUN_SRHTF_V2.bat        44 sets, fast model, ~75 min
```

### The arithmetic first, because it decides how to read the results

$100/day x 20 days = **$2,000/month = 8% of a 25k account, every month.** The best set
in the 2026 screen made $514 in nine months at 0.5% risk - about $57/month. Closing that
gap by size alone needs roughly 35x, and equity drawdown scales with it: 2.92% x 35 is
past 100%. The account is gone long before the month ends.

So size is not the route. **Frequency is the only lever with any headroom**, and the
2026 screen showed exactly what was suppressing it. That is what v1.10 changes and what
this grid measures. The `_r15` and `_r2` sets are in the grid to *find the wall*, not
because they are expected to pass - they should breach `InpMaxGuardPct`, and seeing
where they breach it is the useful part.

### What v1.10 adds

Every new input defaults to the v1.00 behaviour, so an old `.set` reproduces its old
result exactly.

| input | default | what it is for |
|---|---|---|
| `InpTPFallback` | `false` | HTF target nearer than `InpMinRR`? Take the setup at a fixed `InpMinRR` target instead of discarding it. **This was the 5-trades-in-nine-months cause.** |
| `InpMaxOppose` | `0` | TFs allowed to disagree, separated from `InpMinAgree`. `0` is the old hard-coded `dn == 0`. |
| `InpAsia` / `InpAsiaStart` / `InpAsiaEnd` | `false` / `0` / `3` | A third killzone; wraps midnight correctly. |
| `InpDailyTargetUSD` | `0` | Bank the day at this **realised** profit: pull pendings, take no new entries, leave open positions to their own TP. |

Two ordering points in the guards, both deliberate:

- The daily **loss** guard runs before the daily-target check. A banked day can still be
  holding a position, and returning early on the banked flag would leave nothing
  watching it drag equity through the daily limit.
- `ManageBreakEven` now runs **before** `RunGuards`, for the same reason - a banked day
  returns false for the rest of the session, which would otherwise abandon the open
  position unmanaged until it closed.

### The grid

44 sets, no two identical (checked - 15 of the last 36 were). Three layers:

| block | sets | asks |
|---|---|---|
| anchors | `V2_nofb`, `V2_base`, `V2_fixedrr` | did `InpTPFallback` take? |
| one knob | `V2_rr15`…`V2_be15` (23 sets) | which knob adds trades that pay |
| frequency stacks | `V2_freq1`…`V2_freq4` | stacked, each adding one idea |
| size | `_r1`, `_r15`, `_r2` on freq2/3/4 | where does size breach 6% |
| daily target | `_t50`, `_t100`, `_t200` | what the rule costs |
| funded | `V2_freq3_fn`, `V2_freq3_r2_fn` | no target lock, tighter guards |

`V2_ag1` and `V2_ag2` are expected to stay **inert** - that is the `dn == 0` finding
reproducing on the new baseline, and it is the control for `V2_opp1_ag1` / `V2_opp1_ag2`,
which are the first real test of the A+ premise.

### Reading it

Rank on **expectancy per trade**, never net. Every set here trades more than the last
grid did, so net rises on volume alone and would rank the loosest set first. A daily
target cannot create an edge either - it can only end a good day early - so each `_t*`
set is only meaningful against the same stack without it.

---

## v2 grid results (2026 Jan-Sep, Model=1) - the daily number, measured

44 ran. `results_2026_M5_v2_m1/`. **29 of 44 profitable**, against 4 of 36 before.

### The fix worked

| set | trades | net | $/trade | eqDD% |
|---|---|---|---|---|
| `V2_nofb` (= old `SR_ctrl`) | 5 | -368.9 | -73.78 | 1.79 |
| `V2_base` (`InpTPFallback=true`) | 30 | +514.5 | +17.15 | 2.92 |
| `V2_rr20` (fallback + `InpMinRR=2.0`) | **30** | **+1384.7** | **+46.16** | **1.44** |

`InpTPFallback` took: 5 trades to 30, and the sign flipped. Dropping `InpMinRR` to 2.0
then nearly tripled net on the *same* trade count - a closer target converts the same
setups at a better rate than a 3R target does.

### The ceiling, which is the real answer

| set | risk% | trades | net | $/month | eqDD% |
|---|---|---|---|---|---|
| `V2_freq2` | 0.5 | 38 | 1646.9 | 183 | 2.12 |
| `V2_freq2_r1` | 1.0 | 24 | 2000.7 | 222 | 3.21 |
| `V2_freq2_r15` | 1.5 | 18 | 2153.0 | 239 | 4.82 |
| `V2_freq2_r2` | 2.0 | 15 | 2054.8 | 228 | **6.43 - breach** |

**Net plateaus at about $2,100 no matter how much size is added, and trade count falls
as risk rises** - 38, 24, 18, 15.

> **CORRECTION (v4).** I attributed this plateau to `InpDailyGuardPct` halting days. That
> was wrong. $2,100 is `InpTargetLock` firing: `InpTargetPct=8.0` on a $25,000 balance is
> $2,000, and at that point the EA closes everything and stops **for the rest of the
> run**. The v4 reports make it visible - `V4_s1`'s deals stop in July, `V4_ag2_opp1`'s in
> August, while `V4_s1_part50` (net $1,737, never reaching the lock) trades all nine
> months. The sets were not being throttled; they had finished the challenge and halted
> by design. Read the ceiling below as "these sets pass a +8% target", not as a limit on
> what the strategy can earn.

So the daily figure this model supports is about **$240/month, or ~$11 a trading day** -
roughly a ninth of $100/day. $100/day would need 8.3x this, and the table above shows
size cannot deliver it: 2.0% risk already breaches the rule while earning *less* than
1.5%.

### `InpDailyTargetUSD=100` is free, and slightly positive

| | trades | net | PF | eqDD% | Sharpe |
|---|---|---|---|---|---|
| `V2_freq2` | 38 | 1646.9 | 1.87 | 2.12 | 19.2 |
| `V2_freq2_t100` | 37 | **1769.1** | **1.99** | 2.11 | **20.8** |

Banking the day at $100 cost one trade and *gained* $122. A daily target cannot create
an edge, so read this as "costs nothing measurable" rather than as an edge - but it does
mean the rule you wanted is not a handicap.

### What broke

`V2_freq3` and `V2_freq4` - the stacks that drop the PD filter, loosen the swing
strength and widen the sweep window - **all breach 6%** and all lose money
(-1505, -1519). Pushed further with size, `V2_freq3_r2` reaches **12.04%** drawdown.
Loosening the entry quality filters adds trades that lose. That is the same monotonic
result the EMA grids gave: more trades from weaker filters is always worse.

`V2_nobe` is the other clear one: break-even off drops the win rate from 63.3% to
**23.3%**. The break-even move is carrying this strategy, not the targets.

### Still inert, and it is now a question about the code

11 sets again returned identical numbers to `V2_base`. The reports confirm the inputs
applied, so these genuinely change nothing:

`V2_ag1` `V2_ag2` `V2_opp1` `V2_opp1_ag1` `V2_opp1_ag2` `V2_entry_m1` `V2_trades4`
`V2_trades6` `V2_fixedrr`

Two are explained. `V2_opp1` is vacuous by construction - `InpMinAgree=3` means `up>=3`,
which already implies `dn==0`, so `InpMaxOppose` has nothing to relax. `V2_fixedrr`
matching `V2_base` means the HTF target is *never* `InpMinRR` or further away, so the
fallback fires every time and the two settings are the same thing on this data.

**`V2_opp1_ag1` and `V2_entry_m1` are not explained.** `InpMinAgree=1` with
`InpMaxOppose=1` is a far looser bias gate, and `InpEntryTF=M1` changes every input to
the sweep search - neither can legitimately leave the trade list byte-identical. Before
this grid is extended, the EA should tally *why* setups are rejected (it already builds
the reason into `g_status`) and print the tally at `OnDeinit`. Without that, the next
grid risks measuring the same thing 44 more times.

### The candidate

`SRHTF_v110_CANDIDATE_t100.set` - `V2_freq2_t100` with `InpNewsFilter=true` and
`InpResetState=false` for live use. **Not validated:** one year, and on `Model=1`, which
fills stop orders anywhere inside the bar while every entry here is a stop order. Real
ticks and 2023-2025 first.

---

## v1.20 and the v3 grid - quality, and the diagnostic that should have come first

```
.\RUN_SRHTF_V3.bat        35 sets, fast model, ~60 min
```

Baseline is `V2_freq2_t100`, the best-balanced set of the v2 grid.

### `InpDiagCSV` - read these before any of the numbers

Every v3 set writes `diag_<set>.csv` alongside its report: a count of **why** setups
were rejected, by reason, with percentages. It exists because v2 left a question it
could not answer - `V2_opp1_ag1` and `V2_entry_m1` returned byte-identical trades with
their inputs verifiably applied, and a looser bias gate and a different entry timeframe
cannot both be no-ops.

`V3_q_ag1` and `V3_q_m1` repeat those two with the tally on. The reasons are counted at
all 14 rejection points in `TryPlaceSetup`, plus the orders actually placed, so:

- if `no HTF bias` dominates and does not move between `V3_base` and `V3_q_ag1`, the
  bias computation is not responding to its inputs - a code fault
- if the counts *do* move but the trade list does not, the gate is downstream, and the
  tally names it

**If those two sets say an input is a no-op, the rest of this grid is built on sand.**
The EA writes to a fixed `MQL5\Files\SRHTF_diag.csv` because it cannot know which
`.set` it was handed; `RUNSETS.bat` renames it per pass.

### Three quality changes, each from a measurement

| input | default | why |
|---|---|---|
| `InpTPRMult` | `0` (= `InpMinRR`) | `InpMinRR` was both the **gate** and the **target**. 2R beat 3R on an identical trade list, so "only take 3R-clear setups, exit at 2R" is worth being able to express - and was not. |
| `InpPartialPct`, `InpTrailATRMult` | `0` | `V2_nobe` dropped the win rate from 63.3% to 23.3%. The break-even move is where this strategy's edge actually is, so scale out at `BE_R` and trail the rest rather than working around it. Trailing needs `InpBreakEven=true` - with BE off the stop never passes entry and the trail branch is unreachable. |
| `InpDirection` | `BOTH` | Shorts have beaten longs on every set measured (73.7% vs 45.5%, then 69.6% vs 50.0%). Possibly a trending-year artifact. Now testable instead of assumed. |
| `InpMinATRPts` | `0` | Skip dead tape. Cheap to test, and the per-trade cost measured earlier (~$2.13) is paid regardless of whether the market moves. |

The partial and the BE move fire in the same branch - the SL still being beyond entry is
the branch condition, and moving it to BE is what closes the branch - so each happens
exactly once per position with no per-ticket bookkeeping. `PartialOut` refuses a split
that would leave either side below the broker's minimum volume.

### Expect the direction sets to disappoint

`V3_short` will probably top the table. It is also the set most likely to be fitting one
year of a gold uptrend, and it halves the sample while doing it. Judge it on 2023-2025 or
not at all.

---

## STOP - the first three grids measured the wrong strategy

```
.\PROBE_SRHTF.bat        3 passes, ~6 min. Run this before any more grids.
```

**An MT5 `.set` file stores an enum input as an INTEGER.** Every `.set` in this repo
wrote them by name:

```
InpTF1=PERIOD_H1        <- does not parse. Input becomes 0 = PERIOD_CURRENT.
```

So `InpTF1`, `InpTF2`, `InpTF3`, `InpRangeTF` and `InpEntryTF` were **all** resolving to
the chart timeframe. The EA has never run the H1/H4/D1 model it was tested as, and the
tester report cannot show this because its Inputs section echoes the `.set` as written,
not as resolved - which is why "the inputs applied correctly" was checked twice and came
back clean twice.

### It explains every anomaly, including the ones I had called unexplained

| observation | cause |
|---|---|
| `InpMinAgree` 1 / 2 / 3 identical | all three TFs were the same timeframe, so `TFBias` returned the same value three times. `up` could only ever be 0 or 3 - `InpMinAgree` had nothing to choose between, and `InpMaxOppose` nothing to relax. |
| `InpEntryTF` M1 vs M5 vs M15 identical | all resolved to the chart TF. |
| **5 trades in nine months** | `InpRangeTF` H4 became M5, so the "HTF dealing range" was 30 M5 bars - about two hours. The liquidity target sat minutes away, `rr` was almost always below `InpMinRR`, and the gate discarded nearly every sweep. The frequency problem the whole v2 grid was built to solve was a side effect of this. |
| `InpDirection` long-only == short-only == both | `SRHTF_SHORT_ONLY` did not parse either; the input became 0 = `SRHTF_BOTH`. |
| `InpMinATRPts` 100 / 200 / 300 identical | not explained by this, and still open. The probe's diagnostic will say. |

### What changed

- **All 136 affected `.set` files rewritten with integer enums**, across every grid - the
  other EAs' sets had the same defect. The name is kept on a preceding `;` comment line,
  since MT5 does not accept a trailing comment on a value line.
- **v1.30 refuses to start** if any timeframe input resolves to `PERIOD_CURRENT`, and
  prints the resolved values at `OnInit`. A silent wrong-timeframe run cannot happen
  again - the test fails instead.
- **The diagnostic CSV now carries the resolved inputs** above the rejection tally, so
  one file settles what the binary actually used, independently of the report.
- **`RUNSETS.bat` finds the diagnostic by search**, not by path. The tester sandboxes
  file writes per agent, so the EA's CSV lands in
  `Tester\Agent-<addr>-<port>\MQL5\Files`, not `MQL5\Files` - which is why the v3 run
  produced 35 reports and zero CSVs.

### What the earlier results are now worth

| | status |
|---|---|
| v1 grid (36 sets) | void - wrong timeframes |
| v2 grid (44 sets) | void - wrong timeframes |
| v3 grid (35 sets) | void - wrong timeframes |
| "drawdown guard caps the month near $2,100" | **unaffected** - that is about `InpDailyGuardPct` and position sizing, neither of them enum inputs, and it held across four risk levels |
| "break-even is carrying the strategy" (63% -> 23%) | probably holds, worth re-confirming |
| `SRHTF_v110_CANDIDATE_t100.set` | **do not trade it** - it was fitted to a model that was not running |

The sizing ceiling is the one finding that survives, and it is the one that answers the
$100/day question, so the conclusion there does not change.

---

## Probe: the enum fix is confirmed, and the real strategy is worse

`results_2026_M5_probe_m1/`. The diagnostic CSVs settle it - the resolved inputs are now
what the sets ask for:

```
InpTF1,PERIOD_H1,16385      InpRangeTF,PERIOD_H4,16388
InpTF3,PERIOD_D1,16408      InpDirection,SRHTF_SHORT_ONLY,2
```

and `V3_short` shows **0 long trades** with `blocked by InpDirection` counted 2,280
times. Every input now does what it says.

### The strategy, measured for the first time

| set | trades | net | $/trade | eqDD% | PF | long / short |
|---|---|---|---|---|---|---|
| `V3_base` | **6** | **-235.8** | -39.29 | 3.98 | 0.36 | 2 / 4 |
| `V3_q_m1` (M1 entry) | 23 | +398.6 | +17.33 | **6.35 breach** | 1.39 | 6 / 17 |
| `V3_short` | 4 | -235.8 | -58.96 | 1.87 | 0.02 | 0 / 4 |
| *old `V3_base`, wrong TFs* | *37* | *+1769.1* | *+47.81* | *2.11* | *1.99* | *14 / 23* |

**The +1769 was the bug, not the strategy.** Run as written - H1/H4/D1 bias, H4 dealing
range - it takes 6 trades in nine months and loses money. Every positive number in the
v1, v2 and v3 tables came from a configuration where all five timeframe inputs had
collapsed onto M5.

### Where the trades go, from `diag_V3_base.csv`

| reason | count | % |
|---|---|---|
| **no HTF bias** | 16,561 | **79.54** |
| **wrong side of equilibrium** | 3,871 | **18.59** |
| no sweep setup | 185 | 0.89 |
| already exposed | 151 | 0.73 |
| sweep already used | 23 | 0.11 |
| SL size out of range | 17 | 0.08 |
| ORDER PLACED | 13 | 0.06 |
| below `InpMinRR` gate | 0 | 0.00 |

Two gates are 98% of everything. Requiring H1, H4 **and** D1 to agree stands the EA
aside four evaluations in five; of what survives, the premium/discount filter removes
most of the rest. The `InpMinRR` gate - the thing the whole v2 grid was built around -
now rejects **nothing**, because `InpTPFallback` takes every setup it would have
discarded.

So the question is no longer "which knob pays". It is whether a three-timeframe
unanimous-agreement model fires often enough to trade at all.

## v4 grid - the first one that tests the real thing

```
.\RUN_SRHTF_V4.bat        41 sets, ~70 min
```

Built on the corrected `V3_base`, with `InpMaxOppose=0` so the baseline is honest
(`InpMinAgree=3` means `up>=3`, which already implies `dn==0`, so `MaxOppose` has nothing
to relax there). Most of the grid aims at the two gates that matter:

| block | sets | attacks |
|---|---|---|
| bias | `V4_ag1/ag2`, `_opp1/_opp2`, `V4_tf_fast/faster/mid`, `V4_swing*`, `V4_look*` | the 79.5% |
| location | `V4_nopd`, `V4_range15/60/100`, `V4_rangetf_h1/d1` | the 18.6% |
| entry TF | `V4_entry_m1/m15`, `V4_m1_pool40/60`, `V4_m1_sweep30`, `V4_m1_expiry20` | M1 was the only probe set that made money |
| targets | `V4_nofb`, `V4_tpr15/30`, `V4_rr3` | now that the gate is visible |
| direction | `V4_short`, `V4_long` | works for the first time |
| stacks + guards | `V4_s1`…`V4_s4`, `_tight`, `_r025`, `_r1`, `_notgt`, `_part50` | `V3_q_m1` breached 6%, so the tighter guard is tested |

**Judge trade count before anything else.** `V4_base` is 6 trades; a set under ~30 has
said nothing whatever its net. And `V3_q_m1` is the warning for this grid: the one
profitable probe set also breached the 6% rule, so a high net here is not a pass.

---

## v4 results - one set passes, and the ceiling was never the drawdown guard

41 ran, all with correct timeframes (`diag_*.csv` confirms `InpTF1 = PERIOD_H1 / 16385`
in every set that used it). 13 of 41 profitable. Applying all three bars at once -
**30+ trades, profitable, equity drawdown inside 6%** - leaves exactly one:

| | `V4_s1_part50` | `V4_s1` (same, no scale-out) |
|---|---|---|
| trades | **70** | 39 |
| net | +1737.25 | +2126.10 |
| equity DD | **2.47%** | **9.15% breach** |
| balance DD | 1.76% | 6.08% |
| win rate | **80.0%** | 61.5% |
| profit factor | 1.96 | 2.19 |
| Sharpe | **37.70** | 5.46 |
| LR correlation | **0.93** | -0.56 |
| months traded | all 9 | stops in July |

Both are `InpMinAgree=2` with an M1 entry. The only difference is
`InpPartialPct=50` + `InpTrailATRMult=1.5`, and it **cut equity drawdown from 9.15% to
2.47%** - a 3.7x reduction - while nearly doubling the trade count. Net fell 18%. On a
6%-limit account that is not a trade-off, it is the difference between usable and dead.

The mechanism is visible in the averages: scaling out drops the average win from $162.76
to $63.33, so the payoff ratio falls to 0.50 and breakeven needs a 66.5% win rate. It
scored **80.0%** over 70 trades. The standard error there is 4.8 points, so the edge sits
**2.8 standard errors** above breakeven - the first candidate in this project that is
not inside one.

### The $2,100 cluster was `InpTargetLock`, not the daily guard

Four sets land within $30 of $2,100 (`V4_s1` 2126, `V4_s1_r025` 2121, `V4_ag2_opp1` 2100,
`V4_s1_r1` 2032). `InpTargetPct=8.0` of $25,000 is $2,000: the EA hits the challenge
target, closes everything and stops for the remainder of the run. Their deal lists end in
July and August to prove it. I had told the record this was the drawdown guard capping
monthly profit - see the correction above. It is not a cap, it is completion.

`V4_s1_r1` is the clearest case: **2 trades, net +2031.80, PF 9.00.** Two trades at 1%
risk reached +8% and the EA locked. That is not a result, it is a lucky fortnight.

### What the diagnostic bought

`V4_nopd` turns the premium/discount filter off and `wrong side of equilibrium` drops to
0.0% as it must - the tally is wired correctly. The trade is bad though: 52 trades,
-148.6, and **7.40% drawdown**. `V4_ag1_opp2`, the loosest bias setting in the grid, cuts
`no HTF bias` from 79.5% to 3.1% and loses $1,502 at 8.85% drawdown. **Opening the gates
produces trades, not edge** - the same monotonic result every grid in this repo has
given.

`V4_look50`, `V4_look300`, `V4_nofb`, `V4_rr3`, `V4_tpr15` and `V4_tpr30` all returned
`V4_base` exactly (6 trades, -235.8). With only 13 orders placed, none of those branches
is reached enough to matter - and now the tally says so rather than leaving it a mystery.

## Next: real ticks, four years

```
.\RUN_SRHTF_FINAL.bat     4 sets x 2023-2026 on real ticks. ~5 hours.
```

`Model=1` cannot settle `V4_s1_part50`, because scaling out and trailing is precisely the
behaviour that benefits most from fills granted anywhere inside a bar. `V4_s1` is in the
shortlist as its control: if the scale-out is real, it should still be the one with the
lower drawdown on real ticks.

**Rank on the worst of the four years, not the average.** Positive in three years and
-8% in the fourth is not tradeable on a 6% account.

---

## REAL TICKS, 4 years - and my pass/fail criterion was wrong

16 passes, `results_<year>_M5_final/`. The result inverts the v4 ranking, because of a
mistake in how I was judging every grid before this one.

### The correction first

**I ranked every set on MT5's "Equity Drawdown Maximal %" and called anything over 6% a
breach. That is the wrong test for this account.** FundedNext's 25k 2-Step maximum is
**static**: $1,500 below the *initial* balance, i.e. equity must never reach 23,500.
MT5's figure is **peak-to-trough** - it counts a fall from a high-water mark, which on a
static rule costs nothing.

`V4_s1` in 2024 makes it concrete: 8.60% equity drawdown, and it **passed**, ending
+$2,000.16 with deals stopping in March. Equity fell 8.6% from a peak above 25,000 and
never approached the floor. Under my old criterion I marked it a breach and ranked it
below the set that actually blew the account.

The guards make the real test readable straight off the net, because the EA closes
everything at both ends:

```
InpTargetPct   8.0  -> locks at equity 27,000  ->  net ~ +2,000  = target reached
InpMaxGuardPct 6.0  -> halts at equity 23,500  ->  net ~ -1,500  = floor hit, account dead
```

### The table, read correctly

| set | 2023 | 2024 | 2025 | 2026 | verdict |
|---|---|---|---|---|---|
| `V4_s1` | **+1998** | **+2000** | **+1998** | **+2002** | target in **all four years** |
| `V4_s1_r025` | **+1999** | **+1999** | **+2000** | **+2001** | target in **all four years** |
| `V4_ag2_opp1` | +1999 | **-1502** | **-1501** | +2011 | floor hit **twice** |
| `V4_s1_part50` | +623 | **-1504** | **-1502** | +1440 | floor hit **twice** |

`V4_s1_part50` - the set I championed - is the worst of the four. Its deals run to May
2024 and July 2025 and then stop, which is the max-loss guard firing. Two blown accounts
in four years.

### What the scale-out actually did

`V4_s1_part50` on 2026 real ticks: 77 trades, +1440, 3.05% - close to its Model=1 numbers
(70 trades, +1737, 2.47%), so the fill model was *not* flattering it much. The scale-out
held up fine in-sample and simply has no edge in 2024 or 2025. Trading more (91, 40, 52,
77 trades a year against `V4_s1`'s 12, 16, 14, 40) converted a thin edge into enough
exposure to reach the floor.

`V4_s1` wins by trading **less**: it reaches +8% in a dozen trades and then stops for the
year by design. Its 2024 run was over in March.

### Still not a pass, and this is the real gap

`InpTargetPct=8.0` is **$2,000. FundedNext's 2-Step target is $2,500 (10%).** Both
surviving sets stop $500 short of actually completing the challenge. So the honest
statement is: *they reached +8% in four consecutive years without touching the static
floor*, which is not the same as passing.

```
.\RUN_SRHTF_PASS.bat     4 sets x 2023-2026, real ticks, ~5 hours
```

`sets_srhtf_pass` raises `InpTargetPct` to 10.0 on both survivors and asks the only
question left - can the last 2% be reached before equity hits 23,500? The `_dg2` pair
also tightens the daily guard to 2.0%, because more time trading is more chances to trip
the $750 daily rule.

**A set passes only if net is ~+2500 in all four years.** One year at ~-1500 is a blown
challenge, and in reality there is no retry without paying for it again.

### Why the daily limit is probably safe, with a caveat

`InpDailyGuardPct=2.5` of day-start equity is at most ~$675 at 27,000 equity, inside the
$750 rule, and the guard closes positions when it trips. That holds **by construction**
rather than by measurement - a gap through the level, or a weekend open, could still
overshoot it, and nothing in these reports proves it did not.

---

## 10% target, real ticks, four years - one set passes, and one parameter kills it

`results_<year>_M5_pass/`, 16 real-tick passes.

### PASS_s1_tgt10 reached the full FundedNext target in all four years

| year | net | trades | win% | PF | target reached |
|---|---|---|---|---|---|
| 2023 | **+2497.9** | 12 | 75.0 | 6.93 | April |
| 2024 | **+2501.8** | 16 | 43.8 | 3.12 | March |
| 2025 | **+2498.4** | 14 | 50.0 | 3.69 | March |
| 2026 | **+2510.9** | 40 | 57.5 | 2.28 | July |

+$2,500 on a 25k account, four years running, never touching the static floor at 23,500.
**2023-2025 are genuinely out of sample** - the set came out of a grid run on 2026 only.
It needs 12 to 40 trades and three to seven months.

That is the first thing in this project that has survived an honest out-of-sample test.

### And the set next to it blew two of the same four years

`PASS_s1_tgt10_dg2` is identical except `InpDailyGuardPct` 2.5 -> **2.0**:

| year | `PASS_s1_tgt10` | `PASS_s1_tgt10_dg2` |
|---|---|---|
| 2023 | +2497.9 (12 trades) | +2497.9 (12 trades) |
| 2024 | **+2501.8** (16) | **-1503.9** (36) - dead |
| 2025 | **+2498.4** (14) | **-1503.0** (41) - dead |
| 2026 | +2510.9 (40) | +2498.9 (40) |

**A tighter daily guard produced more than twice the trades and two blown accounts.** The
mechanism is structural: reaching the target **ends the year**, because `InpTargetLock`
closes everything and halts. Anything that delays the target - including a guard that
halts a day early - keeps the EA trading, and the extra exposure finds the floor. 16
trades became 36; 14 became 41.

So the behaviour is *win fast and stop, or keep trading and die*. A result that depends
on finishing early is not robust, and one surviving point beside a fatal neighbour is a
spike, not an edge.

### The 0.25% risk pair is safe and useless

`PASS_s1_r025_tgt10` never blew an account - and only reached target in 2026. 2023 ended
+$312 after 68 trades, 2025 +$50 after 82. It trades all year and gets nowhere: too small
to reach +10%, which on a challenge with no time limit is survivable but pointless.

### Next, and this is the decision point

```
.\RUN_SRHTF_ROBUST.bat     ~5 hours, real ticks
```

| step | what | asks |
|---|---|---|
| 1 | `OOS_s1_tgt10` over **2019-2022** (4 passes) | four *more* independent years. Eight in a row would mean the 4/4 was not luck. |
| 2 | six neighbours over 2023-2026 (24 passes) | daily guard 2.25 / 2.75 / 3.0, risk 0.4 / 0.6, max guard 5.0 |

**Step 2 is the one that decides it.** If 5 or 6 of the six neighbours also pass 4/4, the
configuration sits on a plateau and is worth a demo account. If only one or two survive,
it is a spike and must not be traded whatever the net says - the same plateau test that
killed `V3_ema_50_100` earlier in this project, which also looked excellent at one point
and had nothing around it.

> **ANSWERED, and I was wrong to call it a spike.** 5 of 6 neighbours pass 4/4. Daily
> guard 2.25, 2.75 and 3.0 all pass; risk 0.4 and 0.6 both pass. The `dg2` failure is a
> cliff *below* 2.25, not general fragility, and the only other failure (`RB_mg50`,
> max guard 5.0) is mechanical - a tighter floor is simply easier to hit, and it failed
> by ending 2026 short at -1255 rather than by dying. **Parameter robustness is good.**
> The problem turned out to be time, not parameters - see below.

---

## Eight years of real ticks: robust to its parameters, not to the calendar

### Step 2 - the plateau test passes

| neighbour | 2023 | 2024 | 2025 | 2026 | 4/4 |
|---|---|---|---|---|---|
| baseline (risk 0.5, daily 2.5, max 6.0) | +2498 | +2502 | +2498 | +2511 | **yes** |
| `RB_dg225` daily 2.25 | +2498 | +2502 | +2497 | +2505 | **yes** |
| `RB_dg275` daily 2.75 | +2498 | +2502 | +2498 | +2501 | **yes** |
| `RB_dg30` daily 3.0 | +2498 | +2502 | +2498 | +2510 | **yes** |
| `RB_r04` risk 0.4 | +2498 | +2498 | +2499 | +2499 | **yes** |
| `RB_r06` risk 0.6 | +2500 | +2497 | +2497 | +2501 | **yes** |
| `RB_mg50` max guard 5.0 | +2498 | +2502 | +2500 | **-1255** | no |

**5 of 6.** This is a plateau, and my "knife edge" call was wrong. The `dg2` death sits on
a cliff below 2.25, and `RB_mg50` fails for a mechanical reason - a floor at 5% instead of
6% is simply easier to reach, and it ended 2026 short rather than dead.

### Step 1 - and then the calendar

| year | net | trades | outcome |
|---|---|---|---|
| 2019 | **-1502.0** | 28 | **account dead** |
| 2020 | +2498.8 | 48 | passed |
| 2021 | +2497.3 | 7 | passed |
| 2022 | **-1502.9** | 25 | **account dead** |
| 2023 | +2497.9 | 12 | passed |
| 2024 | +2501.8 | 16 | passed |
| 2025 | +2498.4 | 14 | passed |
| 2026 | +2510.9 | 40 | passed |

**6 of 8 passed, 2 of 8 blew the account.** Bar counts are ~70,500 a year throughout, so
2019-2022 is real data and the failures are real.

**25% of years end in a blown challenge.** That is the number this project has been trying
to find, and no amount of parameter tuning moved it - the plateau above says the
parameters are not the problem.

### The two deaths have one fingerprint, and it is not luck

| | win% | avg win | avg loss | outcome |
|---|---|---|---|---|
| 2019 | 50.0 | **$17.30** | -$118.03 | dead |
| 2022 | 48.0 | **$13.02** | -$121.68 | dead |
| 2020 | 43.8 | $288.67 | -$127.60 | passed |
| 2021 | 57.1 | $723.40 | -$126.41 | passed |

**The win rate barely moves. What collapses is the size of the wins** - $17 and $13
against $120 losses. 2021 passed on 7 trades at an average win of $723; 2019 died over 28
trades whose wins averaged $17.

That is the break-even move firing at 1R and then stopping the trade out at entry plus
offset, booking a "win" worth nothing while the losses stay full size. In the six years
that passed, the winners ran.

```
.\RUN_SRHTF_BE.bat     5 sets x 2019 and 2022 only. 10 passes, ~3 hours.
```

`BE_base` (control), `BE_off`, `BE_r15`, `BE_r20`, `BE_r15_tr` (BE at 1.5R then trail at
2x ATR). **Run on the failures first, deliberately.** Only a variant that turns *both*
dead years into passes earns the two hours it then costs to re-check the six years that
already worked - a change that rescues 2019 and breaks 2024 is not progress.

`BE_base` must come back near -1500 in both years. If it does not, something changed in
the harness and nothing else in the table is comparable.

---

## "$100/day is only 400 pips at 0.05 lots" - checking that

It is not, and the gap is large enough to change the plan.

XAUUSD: 1 lot = 100 oz, so **1 point (0.01) = $1.00 per lot**.

| lots | $ per point | points needed for $100 | gold move needed, **net, every day** |
|---|---|---|---|
| 0.05 | $0.05 | 2,000 | **$20.00** |
| 0.10 | $0.10 | 1,000 | $10.00 |
| 0.20 | $0.20 | 500 | $5.00 |
| 0.50 | $0.50 | 200 | $2.00 |

Gold is ~$4,150 with a typical daily range of $40-60. At 0.05 lots, $100/day means
capturing **$20 of net favourable movement daily - roughly 40% of the entire day's range,
after losing days**. Not 400 pips in any convention: 400 points is $4.00 of move, which at
0.05 lots is $20, and 400 "pips" at the $0.10 convention is $200 of move.

Also worth knowing: the passing sets never traded 0.05 lots. At 0.5% risk on 25k they
sized **0.18-0.21**.

### What the measured config actually earns

`PASS_s1_tgt10`, real ticks, 8 years:

```
2019 -1502  2020 +2499  2021 +2497  2022 -1503
2023 +2498  2024 +2502  2025 +2498  2026 +2511     total +12,000
```

**+$1,500 a year, or $5.95 a trading day.** $100/day is **16.8x** that.

### But that number is wrong, and in our favour

**Every +2500 above is `InpTargetLock` halting the EA at +10% - not the year ending.**
2024 was over in March. 2025 in March. 2023 in April. So $1,500/year is not this
strategy's rate; it is the rate of a strategy that quits in the spring.

**We have never measured the full-year return.** That is the single biggest gap between
where we are and the question being asked.

```
.\RUN_SRHTF_RATE.bat     2 sets x 2019-2026, real ticks, InpTargetLock=false. ~5 h.
```

The static floor at 23,500 still applies - the max-loss guard is untouched, only the
profit halt is off - so a year can still end at -1500.

### What to do with the answer

Take the 8-year average annual return **R** as a percentage of 25,000. Then:

```
capital needed for $100/day  =  $25,200 / R
```

| if R turns out to be | capital needed |
|---|---|
| 10% | $252,000 |
| 20% | $126,000 |
| 30% | $84,000 |

**That is a capital number, not a strategy number**, and it is the honest shape of the
answer. Two things can still move it: removing the target lock (measured by this run), and
fixing the two blown years (`RUN_SRHTF_BE.bat` - if break-even at 1R is what killed 2019
and 2022, the average rises by roughly a third on its own).

What will *not* move it is more risk per trade. That was tested across four risk levels:
net plateaued and trade count fell, because bigger positions trip the guards sooner.

---

## The combination search - 1.24M of them, properly

```
.\RUN_SRHTF_OPT.bat     genetic, 2019-2026, forward 1/3 held out. 1-4 hours.
```

We have been testing 20-40 combinations at a time by hand. **The tester has had an
optimiser the whole time.** Ten parameters at sensible ranges is **1,244,160**
combinations; complete enumeration would take ~31,000 hours, so this runs genetic.

| parameter | range |
|---|---|
| `InpMinAgree` | 1 – 3 |
| `InpMaxOppose` | 0 – 1 |
| `InpSwingStrength` | 1 – 3 |
| `InpMinRR` | 1.5 – 4.0 step 0.5 |
| `InpTPRMult` | 0 – 4.0 step 0.5 |
| `InpBE_R` | 0.5 – 2.5 step 0.5 |
| `InpPartialPct` | 0 – 75 step 25 |
| `InpTrailATRMult` | 0 – 3 step 1 |
| `InpOrderExpiryBars` | 3 – 12 step 3 |
| `InpSweepWindow` | 6 – 24 step 6 |

Everything else is pinned at the `PASS_s1_tgt10` value.

### `OnTester()` - why the search can now be pointed at the right thing

New in v1.50. MT5's built-in optimisation criteria rank on profit, Sharpe or drawdown,
and **none of them know what a blown challenge is** - "max balance" would happily return a
set that dies in one year and recovers in another. The custom score is what the account
actually experiences:

```
floor hit        -1000      nothing recovers from this
no trades        -2000      worse than losing - it was never tested
target reached   +1000 and up, higher the sooner it arrives
neither          the return in %
```

Both the max-loss guard and the target lock set `g_accHalted`, so v1.50 records
`g_haltReason` separately - otherwise a passed challenge and a dead account are
indistinguishable at `OnTester`, which is the one thing this score exists to tell apart.

### The part that matters more than the run

**Searching 1.24M combinations will produce spectacular in-sample numbers from pure
chance.** That is arithmetic, not pessimism. Three things make the search honest, and all
three are required:

1. **`FORWARD=2`** - the last third is held out and never optimised on. Read the
   **Forward** column; the Back column is the fitted one.
2. **Take clusters, not spikes.** Neighbouring parameter values with similar scores mean a
   plateau. A single isolated winner is exactly what `V3_ema_50_100` looked like, and it
   scored 0 of 23 positive out of sample.
3. **Real ticks afterwards.** `MODEL=1` is the only way to afford the search, and it fills
   stop orders anywhere inside the bar. The top 4-6 get re-run on `MODEL=4`, year by year,
   and are judged on the **worst** year.

A combination that survives all three is worth a demo account. One that only tops the
in-sample table is worth nothing, and we have the receipts for that from earlier in this
project.

---

## The Asian-range sweep does NOT transfer to SR_HTF

32 real-tick passes, `results_<year>_M5_asia/`. The idea that won the SniperEntry book
grid loses here, and not marginally.

| set | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 | 2025 | 2026 | passes |
|---|---|---|---|---|---|---|---|---|---|
| `ASIA_off` (control) | -1502 | **+2498** | **+2497** | -1503 | **+2498** | **+2501** | **+2497** | **+2511** | **6/8** |
| `ASIA_on` | +266 | -1502 | +312 | -201 | -930 | -371 | -847 | -123 | **0/8** |
| `ASIA_on_0_3` | +404 | -1504 | -76 | -882 | -1504 | -459 | -829 | **+2500** | 1/8 |
| `ASIA_on_ag1` | -580 | -1505 | -818 | +917 | -1502 | -1503 | -1502 | -1021 | **0/8**, 4 dead |

**The control reproduces exactly** - `ASIA_off` returns +2498 / +2501 / +2497 / +2511 on
2023-2026, matching `PASS_s1_tgt10` to the rupee. So the harness is sound and the
comparison is valid.

With the Asian range as the pool, **the EA stops reaching target at all.** Not blowing up
mostly - just grinding out small losses and never arriving. Trade counts collapse in the
years that used to work: 2026 goes from 40 trades to **1**.

### Why it helped one EA and ruined the other

SniperEntry's trigger is an EMA cross with no location filter at all, so naming the
liquidity pool adds information it did not have. SR_HTF already gates on HTF structure
*and* premium/discount *and* requires the sweep to be reclaimed - the Asian high and low
are then one more constraint on a setup that was already rare, and the intersection is
nearly empty.

**A component's value is model-specific.** The Asian range was the best thing in the
SniperEntry grid and is the worst thing tried on SR_HTF. Nothing about "it is a real ICT
level" carried across, and nothing about the book's reasoning predicted which way it would
go - only the test did.

`InpSweepAsianRange` stays **false**. The 6/8 `PASS_s1_tgt10` configuration is still the
best thing in this repo.

### What is still open for gold

| run | asks | cost |
|---|---|---|
| `.\RUN_SRHTF_BE.bat` | does loosening break-even rescue 2019 and 2022? The two dead years share a fingerprint: ~50% win rate with average wins of $17 and $13 against $120 losses | ~3 h |
| `.\RUN_SRHTF_RATE.bat` | what does a FULL year earn? Every +2500 is the target lock halting in March - we have never measured an unconstrained year | ~5 h |
| `.\RUN_SRHTF_OPT.bat` | 1.24M combinations, genetic, forward third held out | 1-4 h |

`RUN_SRHTF_BE` is still the highest-value of the three: it targets a specific, identified
failure rather than searching.
