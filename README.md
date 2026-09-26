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

## Backtesting — one click

```
RUN_ALL.bat          double-click on Windows
python run_all.py    the same thing, from a terminal
```

Runs all three grids across M15 / M5 / M3, merges each, and copies the summaries
into `backtest-results/<timestamp>/` ready to commit.

| Grid | EA | Sets |
|---|---|---|
| [kz-grid/](kz-grid/) | SniperEntry_Strict v1.30 | 10 — killzone entry window |
| [sweep-grid/](sweep-grid/) | SniperSweep_PDHPDL v1.00 | 14 — PDH/PDL raid model |
| [turtle-grid/](turtle-grid/) | SniperTurtle_KZ v1.00 | 21 — killzone ranges, daily targets |

135 backtests in all. Narrow it with `--grids turtle` or `--periods M5`; see what
would run first with `--list`; pass anything else straight through after `--`:

```
python run_all.py --grids turtle --periods M15 -- --from 2026.01.01 --to 2026.09.18
```

Each grid's own `.bat` still works if you only want that one.

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
