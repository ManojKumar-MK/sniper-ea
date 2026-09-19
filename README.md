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

## Status

**The `.mq5` has not been compiled.** It needs MetaEditor (`F7`) and a Strategy
Tester run before it goes anywhere near a live account.

Log files, state files and generated reports are gitignored — they contain
account balances and every trade.
