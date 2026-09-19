# If the VPS restarts

What survives an unplanned reboot, what does not, and the one piece of Windows
configuration that decides whether the EA comes back on its own.

A planned shutdown is the easy case and is at the end.

---

## The short version

**Your stop is safe.** It is sent to the broker with the order
(`trade.Buy(lots, _Symbol, 0.0, sl, tp, cmt)`), so it sits on the broker's
server and works whether or not MT5 is running. A crash cannot widen your worst
case on an open trade.

**Your targets are not.** In scale-out and full-target mode the EA passes no
broker TP — it manages TP1–TP5 itself, tick by tick. While the terminal is down
nothing books, nothing trails, and nothing flattens.

**Recovery is automatic and safe** provided Windows logs itself back in. That
last point is where most setups quietly fail.

---

## What is exposed while it is down

| | Status |
|---|---|
| Stop loss | **Broker-side.** Works with MT5 off |
| TP1–TP5 | **Not protected.** Price can run through TP5 and back with nothing booked |
| Stop stepping to breakeven | Does not happen — a winner can round-trip to the initial stop |
| The runner's trail above TP5 | Does not happen |
| Weekend / news / daily-cap flattening | Does not happen |
| Flip exit on an opposite cross | Does not happen |

So the downside is capped and the upside is unmanaged. That is the right way
round, but it means a long outage during a fast move costs you profit, not
capital.

---

## What recovers by itself

**The open position is re-adopted.** `AdoptOpenPosition()` runs at startup:

- **State matches the live position** (`posId` equal, entry and risk present) →
  full recovery. Entry, 1R, the whole TP ladder, which rungs already fired and
  the runner level all come back. Logged as
  `[STATE] resumed | … | full state recovered`.
- **State missing or mismatched** → the position is adopted with 1R rebuilt from
  the live stop distance. Logged as `ADOPTED`, tagged `…-ADOPTED`, and the log
  says plainly that the ladder may differ from the original.

**A duplicate entry cannot happen.** Entries are gated on
`g_lastSignal` — `triggerBuy = buyCond && g_lastSignal <= 0` — and that value is
both written to the state file and set from the live position during adoption.
So a restart that re-reads the same closed bar will not open a second position
on top of the one already running.

**The daily guard state is preserved.** A restart on the *same* trading day
restores `dTrades`, the loss count, `dayLocked`, `warnDaily` and `dayStartBal`.
A crash cannot hand back a fresh daily loss allowance — which matters on a
funded account, where repeatedly restarting would otherwise be a way to trade
straight through the cap.

**At most `InpHeartbeatMin` minutes of state is lost.** The state file is
rewritten after every event *and* on the heartbeat timer, so even a hard power
cut with no clean shutdown leaves a recent file behind.

---

## The part you must configure

**MT5 is a GUI application. It cannot start without an interactive Windows
session.** This is the single most common reason a VPS comes back from a reboot
with no EA running and no error anywhere.

1. **Enable automatic logon.** Run `netplwiz`, untick *Users must enter a user
   name and password*, enter the password when prompted. Without this, Windows
   boots to a lock screen and MT5 never launches.
2. **Put MT5 in Startup.** `Win+R` → `shell:startup` → drop a shortcut to
   `terminal64.exe` in there.
3. **Confirm AutoTrading comes back enabled.** MT5 remembers the toggle, but
   verify it once — a red AlgoTrading button is completely silent. The EA loads,
   logs, draws its panel and never sends an order.
4. **Disconnect from RDP, never log off.** Logging off ends the session and
   closes MT5. Clicking the X on the RDP window leaves it running.

> **Task Scheduler's "run whether user is logged on or not" is right for the
> Python dashboard and wrong for MT5.** The dashboard is headless and runs
> happily in session 0. MT5 in session 0 has no desktop and will not work
> properly. Different tools, different treatment.

---

## How you find out it happened

**The EA already tells you.** With `InpTgNotifyStart` on it sends a Telegram
"EA online" message every time it starts. An "EA online" you did not ask for
*is* your crash alert — no extra monitoring needed.

**The dashboard can page you.** Run it with
`--alert-telegram TOKEN:CHAT_ID --stale-mins 20` and it pings you once when the
heartbeat stops — saying whether a position was open at the time — and once when
it comes back.

**The dashboard is the third signal.** The Live tab badge reads **live**,
**no pulse** or **EA down?** based on the heartbeat timer rather than on trading
activity, so it stays green through a quiet market and goes red only when the EA
really is not running. "EA down?" while the market is open means act now.

---

## After an unplanned restart, check

| # | Check | Where |
|---|---|---|
| 1 | The chart is open with the EA attached | the smiley face on the chart |
| 2 | **AutoTrading is on** | the toolbar button is green, not red |
| 3 | How it recovered the position | Experts tab: `[STATE] resumed … full state recovered`, or `ADOPTED` |
| 4 | If it says **ADOPTED** — the ladder is approximate | compare the live stop against what you expected |
| 5 | The day tally looks right, not reset | the startup banner's day-to-date line |
| 6 | Dashboard badge is green **live** | top-right of the symbol card |

Check 4 is the one that needs judgement. An adopted trade has its 1R rebuilt
from the live stop distance, so its TP ladder can differ from the original. If
the numbers look wrong, closing it manually and letting the EA start clean on
the next signal is a perfectly reasonable response.

---

## Test it once, deliberately

Reboot the VPS mid-week with a position open, on purpose, and walk the list
above. It takes ten minutes and it is the only way to know that auto-logon,
Startup, AutoTrading and Task Scheduler all actually work together. Finding out
that auto-logon was never enabled is much better on a Wednesday afternoon than
during a Monday open with a runner in profit.

Also worth doing once: confirm your VPS provider's "restart" keeps the disk.
Some restore a snapshot instead, which would take the state file, the logs and
the MT5 profile back to whenever the snapshot was taken. Write a throwaway file,
reboot, check it is still there.

---

## Planned shutdown, for completeness

You do not need to power the machine off — on a fixed monthly VPS plan it saves
nothing, since the fee is the same whether the machine runs or not. Only
hourly-billed cloud instances stop charging when stopped, and even there the
disk keeps billing.

If you do want to, **Saturday or Sunday is the safe window**. The market closed
on Friday, the EA already flattened while it was still running, and nothing
ticks over the weekend. Exit MT5 via *File → Exit*, shut down, and start again
Sunday evening IST — the forex week opens Sunday 17:00 New York, roughly
**Monday 02:30–03:30 IST**, so that leaves hours of margin.

**Never shut down mid-session on a Friday.** The weekend flatten only fires if
the EA is running when the cutoff arrives. Power off at 18:00 when the broker's
Friday close is 23:59 and the 23:44 flatten never happens — you carry an
unmanaged position into the Monday gap with only the broker-side stop under it.
If you need to stop earlier, set `InpFridayCloseHour` / `InpFridayCloseMinute`
to a fixed time before your shutdown instead of leaving them on `-1`.

If you deliberately run `InpHoldOverWeekend = true`, do not shut down at all —
the position is held and needs the EA running at the Sunday open.

---

## Why the state file can be trusted

`LoadState()` reads the saved `day=` stamp *before* it applies anything else,
then decides what is still yours:

| | Restored | Dropped |
|---|---|---|
| Restart on the **same** trading day | tally, loss count, today's trade rows, open-trade state | — |
| Restart on a **new** trading day | open-trade state, `baseline`, `peakEquity`, `acctLocked`, finished-day history | `dayStartBal`, `dayLocked`, `warnDaily`, `dTrades/dWins/dLoss`, `dGrossP/dGrossL`, `dSwap`, `dComm`, `dR`, `dBest`, `dWorst` |

One consequence worth knowing: `acctLocked` is **not** day-scoped, so an overall
drawdown lock survives every restart. Clearing it means deleting
`<prefix>_<symbol>_<tf>_state.txt`, which also discards the day tally and the
finished-day history.

A hard crash never runs `OnDeinit`, so that day's `DAY_SUMMARY` is not emitted
at shutdown — but the heartbeat left a recent state file, so the tally survives
and the day rolls normally at the next day boundary.
