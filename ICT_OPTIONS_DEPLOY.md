# ict_options.py on a VPS

Intraday stock-option system for Angel One SmartAPI. ICT confluence on the **underlying**
5-minute chart; the option is only the execution vehicle.

## What was hardened for unattended running

The strategy code was already careful - throttled API calls, candle retries, a cached
scrip master. The gaps were all operational, and every one of them is the kind that only
shows up at 10 AM on a Tuesday with money on the table.

| problem | what happened before | now |
|---|---|---|
| **The loop had no error handling** | one SmartAPI 500 or network blip raised out of `while True` and killed the process **with positions open** and no alert | each cycle is wrapped; a blip is logged and retried with backoff, `max_loop_errors` consecutive failures flattens and stops |
| **No square-off on crash** | positions were left to the broker's auto-square-off | `except BaseException` flattens, then re-raises. Catches `KeyboardInterrupt` and `SystemExit` too |
| **Telegram failed silently** | a typo in `TG_CHAT` meant total silence, which looks exactly like a quiet market | `telegram_preflight()` sends a test message at startup and **refuses to trade** if it fails |
| **No retry on alerts** | a dropped message was simply lost | 3 attempts with backoff, honours `retry_after` on 429, splits over the 4096-char limit |
| **Two copies could run** | cron restart or a forgotten tmux session = **double orders** | `SingleInstance` pid lock, with a liveness check so a stale file does not block a restart |
| **No sign of life** | a stalled loop was indistinguishable from a quiet day | heartbeat every `heartbeat_min` with open/closed/P&L |
| **No record of what it started with** | - | startup message states mode, risk per trade, caps, square-off time and `live_trading` |

## Setup

```bash
pip install smartapi-python pyotp pandas numpy requests logzero websocket-client

export ANGEL_API_KEY=...   ANGEL_CLIENT=...   ANGEL_PIN=...   ANGEL_TOTP_SECRET=...
export TG_TOKEN=...        TG_CHAT=...
```

The VPS needs the **static IP whitelisted** on the SmartAPI app (SEBI rule since Apr 2026),
and its clock on IST - every session time in `CONFIG` is local.

## Running

```bash
python3 ict_options.py demo                  # synthetic data, no API - proves the engine runs
python3 ict_options.py backtest --days 60    # real 5m history
python3 ict_options.py paper                 # live data, simulated fills   <-- start here
python3 ict_options.py live --i-understand-the-risk
```

`live` also needs `CONFIG["live_trading"] = True`. Two independent switches, deliberately.

**Run `paper` for a full week before `live`.** The backtest fills options at a modelled
price; paper fills at the real bid/ask, and that difference is the whole question for an
options system.

## cron

```cron
25 9 * * 1-5  cd /opt/ict && /usr/bin/python3 ict_options.py paper >> ict_data/cron.log 2>&1
```

09:25 gives the warm-up time to finish before the 09:30 window opens. The pid lock makes a
double-start safe, and the script exits on its own at `square_off`, so no stop job is
needed.

Holidays are **not** handled - only weekends. On an NSE holiday it will start, find no
candles and sit idle until square-off. Harmless, but it will send a heartbeat, so do not
read that as a trading day.

## Reading the Telegram feed

```
[PAPER] alert path OK - 2026-10-03 09:24 - starting on vps-01
[PAPER] START 2026-10-03
        watchlist (18): RELIANCE, HDFCBANK, ...
        risk/trade Rs2,000 | max 4 trades, 2 open | daily loss cap Rs5,000
[PAPER] SETUP RELIANCE CE score 7/9 (fvg)
        entry 2910.5 | SL 2898.0 | TGT 2935.5 (1H high)
[PAPER] ENTRY RELIANCE28OCT2900CE x500 (1 lot, ITM1) @ 42.15 | spread 0.8% | risk ~Rs1,950
[PAPER] 10:30 alive | open 1 | done 0 | day Rs0
[PAPER] EXIT RELIANCE28OCT2900CE @ 61.40 (target) | P&L Rs9,625 | +2.00R underlying
[PAPER] day done: 2 trades, P&L Rs11,200
```

A `FATAL` message means the process is coming down and has tried to flatten - **check the
account by hand**, because the flatten itself can fail if the API is what broke.

## Still worth doing

- **NSE holiday calendar**, so a holiday is not a silent idle day.
- **Position reconciliation at startup**: if a previous run died after entering, this one
  starts blind to that position. The pid lock prevents two *processes*, not two *states*.
- `live` has never been run. The order path (`place`, `order_status`) is exercised only in
  paper, where it is simulated.
