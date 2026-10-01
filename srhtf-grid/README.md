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
