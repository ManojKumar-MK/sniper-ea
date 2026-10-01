# SniperEA — EMA 9/21 strategy and dashboard

A MetaTrader 5 Expert Advisor and a standard-library Python dashboard that reads
what it logs.

| | |
|---|---|
| `SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5` | the EA |
| `ema_report.py` | the dashboard — read-only, stdlib only, single file |

## The EA

EMA 9/21 cross, one position at a time, flipped on the opposite signal. Stop is
ATR(14) × multiplier, halved in the IST evening session. Targets are a 1R–5R
ladder; by default nothing is booked until TP5 and the stop steps up one level at
a time. `InpBookAtTP5 = false` lets it run past TP5 instead, trailing one rung
behind until the signal flips.

Also: an IST session split with per-hour entry toggles, weekend and news guards,
prop-account loss limits, Telegram alerts, restart recovery from a state file,
MFE/MAE per trade, and a `SKIP` row for every signal it refused.

## The dashboard

```bash
python ema_report.py "<MQL5/Files>/*.jsonl" --serve 8800 --poll 5
```

Five tabs, an inline SVG equity curve, light and dark themes, and a print layout.
It never writes to the EA's files and cannot place or close a trade. Bind it to
`127.0.0.1` — never `0.0.0.0`.

Requires Python 3.8+. Nothing to install.

## Documentation

| File | What it answers |
|---|---|
| [DEPLOY_STEPS.md](DEPLOY_STEPS.md) | setting it up on a VPS, step by step |
| `*.example.set` | MT5 input presets — trading and signals-only |
| [EA_GUIDE.md](EA_GUIDE.md) | every input, and why it is there |
| [TELEGRAM_MESSAGES.md](TELEGRAM_MESSAGES.md) | every alert it can send, with samples |
| [REPORT_AND_DEPLOY.md](REPORT_AND_DEPLOY.md) | the dashboard, and backtest analysis |
| [CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md) | reaching it from a phone, behind a sign-in |
| [RESTART_RECOVERY.md](RESTART_RECOVERY.md) | what survives a crash, and what does not |
| [EA_SWEEP_GUIDE.md](EA_SWEEP_GUIDE.md) | the PDH/PDL sweep EA |
| [EA_TURTLE_KZ_GUIDE.md](EA_TURTLE_KZ_GUIDE.md) | the killzone-range EA |
| [backtest-results/](backtest-results/) | what was tested, and when |

## Third-party repos assessed

| repo | verdict |
|---|---|
| [TRADE_SPLIT_MANAGER.md](TRADE_SPLIT_MANAGER.md) | execution manager with a 5-level TP ladder. No signals. Cannot be backtested (`Socket*` is dead in the tester), but its volume-flooring and "filled then closed" logic are worth copying into SR_HTF. |
| [JEV_XAUUSD.md](JEV_XAUUSD.md) | market maker on an on-chain book. Mechanism does not port; typed-decision architecture does. |

## Can an AI model judge the setups?

[JEV_XAUUSD.md](JEV_XAUUSD.md) - what of [jarrodwatts/jev-trader](https://github.com/jarrodwatts/jev-trader)
ports to XAUUSD and what does not. Short version: its market-making mechanism does not
port at all (there is no book to rest in), but its typed-decision architecture does.
`WebRequest()` is dead in the Strategy Tester, so a cloud model cannot be backtested
inside MT5 - validation has to be an offline replay over `SRHTF_setups.csv`, which
`InpSetupCSV=true` now produces.

## No Python? Use MetaTrader directly

```
.\RUNSETS.bat <setsfolder> <Expert.ex5> <TF> <year> [year...]

.\RUNSETS.bat grid-grid\sets_grid SniperGrid_v1.00.ex5 M5 2023 2024 2025 2026
.\RUNSETS.bat orb-grid\sets_orb   GOLD_ORB_single.ex5  H1 2026
.\RUN_GRID_NOPY.bat                         one-click wrapper for the grid EA
```

The first argument may be a **single `.set` file** instead of a folder — one run,
a couple of minutes, to prove the harness before committing to 36 or 144 passes:

```
.\RUNSETS.bat srhtf-grid\sets_srhtf\SR_ctrl.set SR_HTF_StopEntry_EA.ex5 M5 2026
```

Reports still land in `<grid>\results_<year>_<TF>\`, so the folder form afterwards
skips the set that already ran. `RUN_SRHTF.bat` chains exactly that: compile, one set,
then the rest.

Pure batch. It writes the tester `.ini` itself and drives `terminal64.exe /config:`
directly, so **nothing here needs python**. Use it when python.exe fails with
`ModuleNotFoundError: No module named 'encodings'` — a broken `PYTHONHOME` or a damaged
install, which clearing the variable per-window does not always fix.

It skips runs whose report already exists, so it is resumable. It also stops to warn if
a `terminal64.exe` is running, since a second launch of the tester terminal hands the
`/config:` to the open instance and every pass finishes in seconds with no report.

### `.set` files must give enums as integers

MT5 stores an enum input as a number. A line reading `InpTF1=PERIOD_H1` **does not
parse** - the input silently becomes `0`, and for `ENUM_TIMEFRAMES` that is
`PERIOD_CURRENT`, the chart timeframe. Nothing warns you, and the tester report's
Inputs section echoes the `.set` as written, so it looks correct there.

```
InpTF1=16385            correct
; InpTF1=PERIOD_H1      keep the name on its own comment line
```

`M1=1  M5=5  M15=15  M30=30  H1=16385  H4=16388  D1=16408  W1=32769  MN1=49153`

This silently invalidated three SR_HTF grids - see
[srhtf-grid/README.md](srhtf-grid/README.md). Any EA here that takes a timeframe input
is affected, so all 136 affected `.set` files were rewritten.

Two sets folders under one grid folder would collide, because the results directory is
named from the grid. `OUTTAG` separates them:

```
set OUTTAG=_v2
.\RUNSETS.bat srhtf-grid\sets_srhtf_v2 SR_HTF_StopEntry_EA.ex5 M5 2026 nostop
```

### It is taking hours

`Model=4` (every tick from real ticks) costs about **19 minutes per XAUUSD year on
M5** — 36 sets is ~11 hours. Set `MODEL=1` (1-minute OHLC) for a screening pass at
roughly 10–15x that speed:

```
set MODEL=1
.\RUNSETS.bat srhtf-grid\sets_srhtf SR_HTF_StopEntry_EA.ex5 M5 2026 nostop

.\RUN_SRHTF_FAST.bat        one-click, same 36 sets, Model=1
```

Reports land in `results_<year>_<TF>_m1`, a different folder from the real-tick
`results_<year>_<TF>`, so a fast screen can never end up in the same comparison table
as an authoritative run.

**A fast pass is a shortlist, not a result.** 1-minute OHLC grants stop-order fills at
prices the tape may never have printed, which flatters any stop-entry strategy — and
every EA here is one. Screen wide on `MODEL=1`, then re-run only the survivors on
`MODEL=4`. A set that looks good on 1 and bad on 4 was never good.

The tester is given `Report=<setname>` as a **bare name**, not the path the report
should end up at, and the runner moves it afterwards. An absolute `Report=` is accepted
silently and then never written: a full 19-minute pass logged `automatic testing
finished` and produced no file anywhere. A bare name resolves against the terminal's
own data folder, which under `/portable` is the terminal directory itself.

If it prints `ZERO RUNS`, no `.set` matched and **nothing was tested** — it exits 1
rather than printing a tidy summary. The two causes seen so far: the sets were never
committed (a `.gitignore` rule — check `git ls-files`), or the path was wrong.

**What it gives up:** the merged comparison table, which was the Python part. MT5 still
writes a full `.htm` report per run into `results_<year>_<TF>/` — commit those and they
can be parsed for the table.

## Single click: compile, check, run

```
GO.bat            in cmd.exe, or just double-click it
.\GO.bat          in PowerShell  <-- the .\ is required
```

**PowerShell will not run a script from the current directory without `.\`.** Every
`.bat` here carries that note in its header, because `COMPILE.bat all` fails with
*"not recognized as the name of a cmdlet"* and it reads like a missing file.

Three steps, each pausing so you can stop rather than find out 80 runs later:

1. **`COMPILE.bat`** — builds the EAs headlessly with MetaEditor's command line,
   straight into `C:\MT5-Tester\MQL5\Experts\`. No opening MetaEditor, no F7.
   Prints the compiler's errors if a build fails.
2. **`CHECK_SETUP.bat`** — the seven pre-flight checks below.
3. **`RUN_ORB_GMP.bat`** — 156 backtests.

```
.\COMPILE.bat                          the two under test
.\COMPILE.bat all                      every .mq5 found in the repo
.\COMPILE.bat SniperGrid_v1.00.mq5     just that one
```

Each file is routed by **what its entry point says it is**, not by where it sits:

| entry point | goes to |
|---|---|
| `OnTick` | `MQL5\Experts` |
| `OnCalculate` | `MQL5\Indicators` |
| `OnStart` | `MQL5\Scripts` |

A script compiled into `Experts` builds fine and then never appears under Scripts in the
Navigator, which looks like a failed build. Any `vendor/*/Include` tree is copied to
`MQL5\Include` as well, so quoted includes resolve.

The `all` list is **discovered**, not hand-maintained — it went stale twice, and the
symptom was a grid failing with *"not in MQL5\Experts"*, which reads like a missing
file rather than a launcher that had not been told about a new EA. Only
`vendor/GOLD_ORB/GOLD_ORB.mq5` is skipped, because it needs its `Include/` folder.

**MetaEditor comes from the same folder as the tester terminal** — `metaeditor64.exe`
ships beside `terminal64.exe` in every MT5 install, so it uses the same MT5 the
backtests run on and there is no second version to keep in step. If yours is elsewhere:

```
.\COMPILE.bat all "D:\MT5-Tester"      as an argument
set MT5DIR=D:\MT5-Tester                or as an environment variable
```

It lists any `metaeditor64.exe` it can find if the expected one is missing.

### What compiles to what

| source | → `.ex5` | used by |
|---|---|---|
| `vendor/GOLD_ORB/GOLD_ORB_single.mq5` | `GOLD_ORB_single.ex5` | `orb-grid` |
| `vendor/GridMasterPro/GridMaster Pro.mq5` | `GridMaster Pro.ex5` | `gmp-grid` |
| `vendor/FvgGold-EA/FvgGold.mq5` | `FvgGold.ex5` | `fvg-grid` |
| `vendor/MT5-SMC/EA_Script.mq5` | `EA_Script.ex5` | `smc-grid` — **does not compile yet** |
| `SniperTurtle_KZ_v1.00.mq5` | `SniperTurtle_KZ_v1.00.ex5` | `turtle`, `v2`–`v9` |
| `SniperOTE_Fib_v1.00.mq5` | `SniperOTE_Fib_v1.00.ex5` | `ote-grid` |
| `SniperSweep_PDHPDL_v1.00.mq5` | `SniperSweep_PDHPDL_v1.00.ex5` | — |
| `SniperEntry_Strict...v1.30.mq5` | `...v1.30.ex5` | `kz-grid` |

**`vendor/GOLD_ORB/GOLD_ORB.mq5` is not in that list on purpose.** It is the original
and needs its nine `.mqh` files from an `Include/` folder beside it;
`GOLD_ORB_single.mq5` has them inlined and builds alone. Both carry the braces fix.

## Before any grid — check the setup

```
CHECK_SETUP.bat                      checks C:\MT5-Tester
CHECK_SETUP.bat "D:\Your\Path"       or wherever yours is
```

Runs nothing, changes nothing, places no trade. Seven checks, in the order they bite:

| | |
|---|---|
| 1 | `python` on PATH |
| 2 | `terminal64.exe` exists at the tester folder |
| 3 | it is **portable** — `MQL5\Profiles\Tester` sits beside the exe, not under `%APPDATA%` |
| 4 | the tester terminal is **closed** — a second launch hands off to the open instance and every pass finishes in seconds with no report |
| 5 | which `.ex5` files are compiled and in place |
| 6 | no space or bracket in the repo path — MT5 cannot read a `/config:` path containing one |
| 7 | prints the exact windows, timeframes and run count the launcher will use |

Everything it checks is something that has actually gone wrong here at least once.

## Third-party EAs under test — one click

```
RUN_ORB_GMP.bat        GOLD_ORB + GridMaster Pro, 156 runs
```

| grid | EA | sets | TF | runs |
|---|---|---|---|---|
| [orb-grid/](orb-grid/) | GOLD_ORB (opening range breakout) | 19 | H1 | 76 |
| [gmp-grid/](gmp-grid/) | GridMaster Pro (ATR grid) | 20 | M15 | 80 |

Each runs on the timeframe its author built it for, which is why it is two passes
rather than one loop. Compile `vendor/GOLD_ORB/GOLD_ORB_single.mq5` (single file, no
`Include/` needed) and `vendor/GridMasterPro/GridMaster Pro.mq5` first.

**Read equity drawdown, not balance drawdown.** Across the eleven grid EAs reviewed from
`geraked/metatrader5` that ratio was never below 3.4×, and the gap is where a funded
account dies. The FundedNext limit is 6% equity.

Also built but not in this launcher: [fvg-grid/](fvg-grid/) (FvgGold, 20 sets) and
[smc-grid/](smc-grid/) (MT5-SMC, 21 sets — does not compile yet).

## Backtesting — one click

```
RUN_ALL.bat          double-click on Windows
python run_all.py    the same thing, from a terminal
```

Runs all three grids across M5 and M3, merges each, and copies the summaries
into `backtest-results/<timestamp>/` ready to commit.

| Grid | EA | Sets |
|---|---|---|
| [kz-grid/](kz-grid/) | SniperEntry_Strict v1.30 | 10 — killzone entry window |
| [turtle-grid/](turtle-grid/) | SniperTurtle_KZ v1.00 | 33 — killzone ranges, daily targets, quality filter |

86 backtests in all. Narrow it with `--grids turtle` or `--periods M5`; see what
would run first with `--list`; pass anything else straight through after `--`:

```
python run_all.py --grids turtle --periods M5 -- --from 2026.01.01 --to 2026.09.18
```

Each grid's own `.bat` still works if you only want that one.

Runs use a **$25,000 deposit** by default, matching the FundedNext 25k account.
Risk-% sizing is a fraction of the balance, so this sets position size on every
set — `--deposit 50000` to change it.

**Close the tester terminal before running.** A second launch of the same
terminal hands off to the open instance and exits, so every pass "finishes" in
seconds with no report. The runner refuses to start in that state and names the
path; your live terminal is unaffected, as the check compares paths rather than
image names.

**Compile first (F7).** MT5 ignores inputs an older `.ex5` does not have *without
an error*, so a stale build gives you a grid of identical runs and nothing to
explain them. `run_all.py` checks each `.ex5` is in place and asks before running
without one.

[`backtest-results/`](backtest-results/) is committed on purpose — a `.set` means
little without the run that justified it. Only the small, diffable part is kept
(`all_results.csv`, `comparison.csv`, `run.log`); MT5's raw `report_*.htm` is
gitignored, being tens of MB per grid that hold nothing the CSVs do not.

## Status

**The `.mq5` has not been compiled.** It needs MetaEditor (`F7`) and a Strategy
Tester run before it goes anywhere near a live account.

Log files, state files and generated reports are gitignored — they contain
account balances and every trade.
