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
