# Report script and remote access

`ema_report.py` turns the EA's files into a dashboard, and this is the plan for
reaching it from your own machine while the EA runs on a VPS.

Python 3.8+. Standard library only — nothing to install for the script itself.
It only ever reads the EA's files, so nothing here can place or close a trade.

---

## Part 0 — going live, in order

Ten steps, first to last. Steps 0–5 are required; 6–8 are what make it
survive a reboot; 9 is optional.

**The dashboard does not find MT5 by itself.** It reads files, and it finds them
only because you hand it the path. Three things have to be true before any data
appears, and one of them is off by default:

| | Required | Default |
|---|---|---|
| `InpUseJsonLog` | **`true`** | `false` ← the usual reason a fresh dashboard is empty |
| The path you pass | the *data folder*, not the install folder | — |
| The EA | attached, AutoTrading on, at least one run | — |
| Python on the VPS | installed, on `PATH` | not present on a stock Windows VPS |

### 0. Get the files onto the VPS

The zip holds six files that end up in **three different places**. Extracting it
somewhere and leaving it there does nothing — MT5 only looks in its own folders.

Copy `ema-strategy-v1.30.zip` to the VPS Desktop. Dragging it into the RDP
window is simplest; if you download it in the VPS browser instead, right-click
the zip → **Properties** → tick **Unblock** first, or Windows quarantines every
file inside it.

Right-click → **Extract All** → `C:\Users\<you>\Desktop\ema-strategy\`.

Then distribute:

| File | Goes to | How to get there |
|---|---|---|
| `SniperEntry_..._v1.30.mq5` | `MQL5\Experts\` | MT5 → File → **Open Data Folder** → `MQL5\Experts` |
| `ema_report.py` | `C:\ea-dashboard\` | make the folder; keep it off the Desktop so a profile reset cannot take it |
| the four `.md` files | leave on the Desktop | they are your reference while you work |

**Install Python if it is not there.** A Windows VPS almost never has it. Get
3.8+ from python.org and **tick "Add python.exe to PATH"** on the first screen —
missing that is why `python` returns "not recognized" afterwards. Check with:

```bat
python --version
```

Nothing else to install. The dashboard is standard library only.

> Keep the zip. When a newer version replaces these files, having the previous
> one on disk is the fastest way back.

### 1. Compile the EA

Copy `SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5` into
`MQL5\Experts\` on the VPS, open it in **MetaEditor**, press **F7**. It must say
`0 errors, 0 warnings`.

This has never been done — MetaEditor does not run on macOS, so nothing before
this point has been through a compiler. Do it before anything else.

### 2. Backtest it once

Strategy Tester, your symbol and timeframe, a few months back. See **Part 1b**
for the inputs. This is where you find out the ladder behaves as you expect,
without money involved.

### 3. Attach it to a live chart

Drag it onto the chart, then in **Inputs**:

| Input | Set to | Why |
|---|---|---|
| `InpUseJsonLog` | `true` | **the dashboard reads this file** |
| `InpUseCsvLog` | `true` | keep it — it is your spreadsheet copy |
| `InpServerGmtOffset` | your broker's offset (GMT+3 → `3.0`) | wrong value puts every trade in the wrong session bucket |
| `InpMagic` | unique per chart | two EAs sharing a magic number will manage each other's trades |
| `InpTgToken` / `InpTgChatId` | your bot | Telegram alerts, including "EA online" after a crash |
| `InpLogSkips` | `true` | records refused crosses, not just taken ones |

Then check the **AutoTrading** button is green. A red button is completely
silent — the EA loads, logs and never sends an order.

### 4. Find the real path

**MT5 → File → Open Data Folder → MQL5 → Files.** Copy that path from the
address bar. It is a hashed folder under `AppData\Roaming\MetaQuotes\Terminal\`,
**not** where you installed MT5 — pointing at the install folder is the second
most common reason for an empty dashboard.

You should see files named:

```
SniperEA_Log_<SYMBOL>_<TF>.jsonl     <- events
SniperEA_Log_<SYMBOL>_<TF>.csv       <- same data, spreadsheet form
SniperEA_Log_<SYMBOL>_<TF>_state.txt <- the live snapshot
```

The prefix follows `InpCsvPrefix`, so it changes if you change that input.

### 5. Start the dashboard

```bat
python ema_report.py "C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hash>\MQL5\Files\*.jsonl" --serve 8800 --poll 5
```

Open `http://localhost:8800` on the VPS. The state file is written the moment
the EA starts, so the **Live** tab has data straight away — balance, equity,
today's tally, the open position if there is one. The analytics tabs stay empty
until trades close, which is correct, not a fault.

`*_state.txt` is picked up automatically from the same folder. `--state` is only
for the case where the state file lives somewhere else.

Leave the bind address alone. It defaults to `127.0.0.1`; `--host 0.0.0.0`
publishes your balance to the internet and gets found by scanners within hours.

### 5b. Bringing your existing history across

Old trades are not lost, but they are not picked up by magic either. Two things
decide what you see.

**The dashboard reads the EA's own files — never MT5's account history.** Trades
from before the EA was logging, or from any other EA or manual order, do not
appear and cannot be recovered from the terminal. Nothing to fix; just know the
boundary.

**Which file your old trades are in** depends on what was switched on then:

| Old setting | What you have | What to do |
|---|---|---|
| `InpUseCsvLog = true` (the default) | a `.csv` covering the whole period | pass it alongside the `.jsonl` |
| `InpUseJsonLog = true` | a `.jsonl` too | already matched by `*.jsonl` |
| both off | nothing | that history cannot be reconstructed |

Old CSVs load correctly. Verified on a 54-column file written before the
excursion columns existed: 40 trades, win rate, R, profit factor and every
breakdown all built normally. The only thing missing is MFE/MAE, and the
dashboard states the sample it used — *Trades measured 15* — rather than
averaging over trades that never carried the figure.

To load both at once:

```bat
python ema_report.py "C:\...\MQL5\Files\*.jsonl" "C:\...\MQL5\Files\*.csv" --serve 8800 --poll 5
```

Each file is parsed by its own extension and the events are merged, so a trade
present in both is not counted twice — it is grouped by trade id.

> **Move the old `.csv` aside before you start v1.30.** The header is written
> only when the file is new, so the EA will append 56-field rows under the old
> 54-name header. `r_realized` and `profit` still land correctly — they sit
> before the new columns — but `balance`, `equity` and `note` shift by two, and
> an equity curve drawn from a balance column reading `2.7` is worse than no
> curve. Rename it to `..._pre130.csv`, keep it, and pass it to the dashboard as
> a second argument.

### 6. Confirm it is really reading MT5

| Check | Expected |
|---|---|
| Startup output | `read 1 state file(s): SniperEA_Log_...` |
| Live tab badge | green **live** |
| Balance on screen | matches MT5's Trade tab |
| Wait 5 minutes | the freshness time keeps moving |

If the badge says **EA down?** while the market is open, the heartbeat has
stopped — the EA is not running, whatever the chart looks like.

### 7. Make the dashboard survive a reboot

Task Scheduler, *Run whether user is logged on or not*, trigger *At startup*.
Full settings in **[CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md)**, Part D.

### 8. Make MT5 survive a reboot

Different problem, different fix. MT5 is a GUI app and needs Windows to log
itself in — Task Scheduler's "logged on or not" is wrong for it. Enable
auto-logon and put MT5 in Startup: **[RESTART_RECOVERY.md](RESTART_RECOVERY.md)**.

Skipping this is how a VPS comes back from an overnight reboot with a healthy
dashboard, a green tunnel and no EA running.

### 9. Reach it from your phone (optional)

An SSH tunnel is enough to look at it yourself (Part 2, Option A). For phone
access with a sign-in in front, follow
**[CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md)** end to end — Part C, the Access
policy, is the part that actually protects you.

---

## Part 1 — the script

### Three modes

```bash
# text report in the terminal
python ema_report.py logs/*.jsonl

# one self-contained HTML file you can open, email or publish
python ema_report.py logs/*.jsonl --html report.html

# live dashboard, rebuilt on every request
python ema_report.py logs/*.jsonl --serve 8800
```

Options: `--min-trades N` (hide thin buckets, default 3) · `--symbol XAUUSD` ·
`--csv` (force CSV parsing) · `--anon` (R and percentages only, no cash) ·
`--state FILE` · `--daily-cap-pct` / `--total-cap-pct` (the guard bars) ·
`--poll SEC` (how often the Live tab refreshes itself, default 5) ·
`--from` / `--to YYYY-MM-DD` · `--alert-telegram TOKEN:CHAT_ID` ·
`--stale-mins N` · `--host` / `--token` for serve mode.

Point it at the EA's log folder, typically:

```
C:/Users/<you>/AppData/Roaming/MetaQuotes/Terminal/<hash>/MQL5/Files/*.jsonl
```

Globs work, so several symbols or months can be read at once. The CSV is read
too if you'd rather not switch `InpUseJsonLog` on.

### What it reads

Three things, all written by the EA already:

| Source | Written when | Feeds |
|---|---|---|
| `*.jsonl` / `*.csv` | every event | the whole history |
| `*_state.txt` | after every event, at startup, and every `InpHeartbeatMin` min | the **Live** tab |
| `DAY_SUMMARY` rows | end of each day | the calendar |

The state file is picked up automatically from the same folder as the logs;
`--state` points somewhere else. It needs `InpPersistState` on, which is the
default.

### What it reports

Five tabs.

**Live** — what is happening right now, straight from `_state.txt`: the open
position with its entry, current stop (flagged when it has moved, and when it
has moved past entry so the trade is risk-free), the TP ladder with the rungs
already reached — including the runner rungs above TP5 — today's tally, the guard
badges (day locked, account locked, warnings) and a daily-loss-room bar.

A freshness badge reads **live**, **no pulse** or **EA down?**. Because the EA
writes its state file on a timer rather than on ticks, that badge tracks the EA's
own pulse: an old timestamp means it is not running, not merely that nothing has
traded. “EA down?” while the market is open means the terminal is not running —
see **[RESTART_RECOVERY.md](RESTART_RECOVERY.md)**.

**Performance** — headline cards, the equity curve with drawdown beneath it
(hover for per-trade detail), the target-ladder funnel showing how far trades
actually get, breakdowns by mode, direction and exit type, plus streaks and
give-backs.

**Timing** — a daily result calendar, then IST session, IST hour and day of week.

**Signals & filters** — three things.

*Refused signals* needs `InpLogSkips` on in the EA (v1.30+). It is the
denominator every other number here has been missing: how many EMA crosses the
EA actually saw, how many it took, and which gate declined the rest — weekend
cutoff, news blackout, loss guard, entry window, quality filter, spread cap,
already-positioned, zero lot size. Without it every filter is judged only on the
trades that got through. These rows have no outcome, so read the counts as the
cost of a setting, not as lost profit.

The evening-session controls each get their own row — `evening session off`,
`outside the evening window`, and one row **per hour** (`evening hour 18:00
off`). They are deliberately kept apart from `outside the entry window`, which
is the server-clock filter: when both are on, the whole point is knowing which
one refused the trade. Untick an hour, let it run a month, and this panel tells
you what that hour was actually worth.

*How far trades ran* needs v1.30's `mfe_r` / `mae_r`. **MFE** is the furthest a
trade went in your favour, **MAE** the furthest against, both in R and sampled
every tick from entry. MFE says whether the ladder was ever reachable; MAE says
how much of the stop you actually needed. The section calls out the obvious
readings itself — a book where no trade ever passed −0.5R is telling you the
stop has slack in it, and losers that averaged +0.9R before turning are profit
that was on the table.

*Filters: passed vs failed* — the original table, plus ADX, spread and RSI
buckets.

**Trades** — every completed trade, with a CSV download.

When `InpRunUntilFlip` is on, Performance also carries **Runner: was it worth
running past TP5?** Every trade that reached TP5 would have banked its TP5
target under the old rule; the section sums what they actually made against
that counterfactual, so the feature is measured rather than assumed. It also
reports give-back (best rung minus exit — what the trail hands back), how
runners ended, and how much longer they are held.

### Times, and which clock they are on

**Every time on the dashboard is IST.** The EA runs on the broker's clock —
usually GMT+2 or GMT+3, never IST — and converts before writing, so nothing here
needs converting again.

The Live card's **Entered** row shows both, because a conversion you cannot check
is a conversion you have to trust:

```
Entered   2026.09.19 06:45 IST
          04:15 broker (GMT+3.0) · held 5.2h
```

The broker line collapses to `HH:MM` when both clocks are on the same calendar
day and expands to the full date when the conversion crosses midnight — which on
a GMT+3 broker happens for every entry between 21:30 and midnight IST.

The date is there for a reason. The EA previously recorded `HH:MM` only, which
says nothing about *which day* — fine for an intraday trade, useless for a runner
that `InpRunUntilFlip` can hold for days. `held` answers the question that
actually follows.

> Requires EA v1.30+. A state file from an older build has the time but no date,
> and the card says so rather than guessing a day.

The Live card's subtitle also names the offset the EA resolved:

```
Open BUY · live · 3s ago · times IST, converted from broker GMT+3.0
```

**This is the one clock fault worth watching for.** A wrong offset shifts every
timestamp by a constant and breaks nothing else — trades, R multiples and session
buckets all stay self-consistent, so it is invisible unless the number is shown.
`InpServerGmtOffset = 0` on a GMT+3 broker puts every trade three hours late and
into the wrong IST session. The offset is never auto-detected in the Strategy
Tester, which is where this usually happens. The card flags a `0` in amber.

> If a time looks wrong, check this line first, then check what the dashboard is
> actually pointed at — a path still aimed at test data explains more mismatches
> than the conversion ever will.

### Fixing a wrong GMT offset after the fact

The EA converts server time to IST before writing, so a wrong
`InpServerGmtOffset` bakes the error into every row — and nothing looks broken,
because the trades, the R multiples and the buckets all stay self-consistent.

`t_srv`, the broker's own stamp, is never adjusted. So the dashboard can redo the
conversion from it:

```bat
python ema_report.py "...\MQL5\Files\*.jsonl" --gmt-offset 3 --serve 8800
```

It recomputes every IST timestamp **and re-derives the DAY/EVENING label**, since
that is a function of the IST hour — shifting the times without relabelling would
just move the wrong answer somewhere subtler. It reports what it touched:

```
reconverted 6 timestamp(s) at GMT+3.0, 4 session label(s) changed
```

Worked example, from a log the EA wrote with its offset stuck at 0:

| Broker | As logged | With `--gmt-offset 3` |
|---|---|---|
| 11:20 | 16:50 **EVENING** | 13:50 **DAY** |
| 13:00 | 18:30 **EVENING** | 15:30 **DAY** |
| 21:39 | 03:09 DAY | **00:09** DAY |

No recompile, no re-run, and it fixes history rather than just new rows. Use
`--day-session S,E` if your `InpDaySessionStartIST` / `EndIST` are not `0,16`.

Leave the flag off and the EA's own conversion is used unchanged, which is the
right thing when the offset was correct.

### Running a signals-only instance alongside the trading one

Give the two instances different `InpCsvPrefix` values, or they write the same
`.csv`, the same `.jsonl` and the same `_state.txt` and overwrite each other.

```
InpCsvPrefix = "SniperEA_Log"             -> SniperEA_Log_XAUUSD_M15.jsonl
InpCsvPrefix = "SniperEA_Signal_1.30v"    -> SniperEA_Signal_1.30v_XAUUSD_M15.jsonl
```

A dot in the prefix is fine — the extension is always appended last, and the
loader dispatches on the ending, not on `splitext`.

**Point each dashboard at one prefix, not at `*.jsonl`.** Both instances see the
same EMA crosses, so a wildcard merges two copies of every trade:

| Pattern | Result |
|---|---|
| `Files\*.jsonl` | **10 trades** — the same 5 counted twice |
| `Files\SniperEA_Signal_1.30v_*.jsonl` | 5 trades, the signal feed |
| `Files\SniperEA_Log_*.jsonl` | 5 trades, the account |

```bat
python ema_report.py "...\Files\SniperEA_Log_*.jsonl"          --serve 8800
python ema_report.py "...\Files\SniperEA_Signal_1.30v_*.jsonl" --serve 8801
```

The state file follows automatically: `find_states()` derives its pattern from
the log pattern, so a prefix-scoped glob gets that instance's Live card and not
the other one's. A bare `*.jsonl` still picks up every state file, which is the
right answer when you really did ask for both. `--state FILE` overrides either
way.

> Putting a version in the prefix means a new file when you move to v1.31.
> Glob `SniperEA_Signal_*` rather than `SniperEA_Signal_1.30v_*` if you want the
> history to carry across versions.

### The open trade, on one axis

The Live card used to be five prices and a row of blocks. It now leads with a
single R axis carrying the whole trade:

```
          entry          stop
            |             |
 [ risk ]===[###############################]----|----|----|
   -1R      0R      TP1  +1R  TP2      TP3      TP4      TP5
            worst -0.40R      best +3.40R
```

| Element | Means |
|---|---|
| red tint left of entry | the part of the move that is still a loss |
| blue band | where the trade has **been** — `mae` to `mfe` |
| ● red / ● blue | the worst and best points it reached |
| green/red stop line | what is already safe; green once it is at or above entry |
| TP ticks | solid when reached, dashed when not |

Then two progress bars:

- **Locked in** — `+1.00R guaranteed`, or `1.00R still at risk` in red when the
  stop is still below entry
- **Best so far** — how far up the ladder it actually got, out of TP5 (or out of
  the top runner rung when `InpBookAtTP5 = false`)

> **It is not a price marker.** The state file carries no live price — only
> `entry`, `risk`, the stops, the ladder and `mfe`/`mae`. So the bar shows where
> the trade *has been* and what the stop has *made safe*, which is the more
> useful pair anyway: one says what the trade offered, the other says what you
> have already banked. The caption on the card says so, so nobody reads the blue
> band as "price is here".

Verified across a normal trade, a trade still at risk (stop below entry, bar
red at 0%), a runner three rungs above TP5 (top rescales to 8R), and a SELL,
where every R is sign-flipped.

### Where the Live card's entry time comes from

Three sources, in order of trust:

| | Source | Exact? |
|---|---|---|
| 1 | `entryTimeSrv` in the state file — the raw broker instant | yes |
| 2 | the log's `ENTRY` row for that trade id, via `t_srv` | yes |
| 3 | `entryBar` in the state file | **yes when adopted** — `AdoptOpenPosition()` sets it to `POSITION_TIME`; otherwise it is the bar open |
| 4 | `entryIst` — a string converted once, long ago | no, and unrepairable |

Only an `ENTRY` row is used for (2). An `ADOPTED` row's `t_srv` is when the EA
re-attached, not when the trade opened.

The card names which one it used — `from the broker's position time`,
`from the log`, `bar open, to the minute` — so an approximate value is never
passed off as an exact one.

The EA converts before it writes, so a wrong GMT offset bakes the error into
the state file's formatted strings. One weekend restart resolved GMT-5.5 —
`TimeCurrent()` freezes at the Friday close while `TimeGMT()` keeps running —
and wrote `entryIst=05:45` for a trade opened at 21:15 IST.

The dashboard recovers from that **without any change to the EA**: the state
file names the trade (`tradeId`), and the log keeps that trade's `t_srv`, which
is never adjusted. Matching the two gives the true instant:

```
Entered   2026.09.18 21:15 IST
          18:45 broker (GMT+3.0) · from the log · held 17.6h
```

`from the log` marks a value recovered this way rather than read from the state
file.

**When the log cannot cover it** — a position adopted from before the log
existed, or a log cleared by `InpTesterFreshLog` — there is genuinely nothing
to compute from, and the card says so rather than presenting a number it cannot
stand behind:

```
05:45 IST — unverified: this EA build stored only the formatted time,
so a wrong GMT offset at the time is baked in.
```

EA v1.30+ writes `entryTimeSrv`, which removes the dependency on the log
entirely and lets a restart repair a bad stamp. Useful, but not required — with
`InpAutoGmtOffset = false` every new entry is stamped correctly in the first
place.

### Filtering

A chip row above every tab filters by **symbol** and by **period** (all, this
month, 7 / 30 / 90 days). It is server-side, so the whole page — cards, charts,
filter verdicts, skips — reflects the selection, and the URL carries it:
`?symbol=XAUUSD&range=30d`. Bookmark a view, or send someone a link to exactly
what you were looking at. On the command line the same thing is
`--symbol XAUUSD --from 2026-08-01 --to 2026-08-31`.

### Watching for a dead EA

```bash
python ema_report.py "<path>/*.jsonl" --serve 8800 \
       --alert-telegram 123456:AA-your-bot-token:-1001234567890 \
       --stale-mins 20
```

A background thread watches the state file's age. Because the EA writes on a
timer rather than on ticks, an old file means the EA is not running rather than
the market being quiet — so this is a real down-alert, not a noise generator. It
fires **once** on the way down, saying whether a position was open at the time,
and **once** on the way back up. Never repeatedly.

Use the same bot token the EA uses; the chat id is the same one in
`InpTgChatId`. The dashboard still never writes to the EA's files — this is an
outbound notification, nothing more.

### Reading it, printing it, sharing it

**Themes.** Dark by default — it is read for hours against charts. The **Light**
button in the header switches, and the choice is remembered per browser. Light
is a hand-picked set, not an inversion: both the blue series colour and the
diverging red were validated against the light surface for contrast and
colourblind separation, the same way the dark steps were.

**Print gives you a report.** `Ctrl/Cmd+P`, or press **p**. The print stylesheet
expands *every* tab into one continuous document, switches to black-on-white,
drops the tabs, buttons, live dot and hover hints, and sets page breaks so a
table or a chart is never split across a page. A 60-trade log comes out around
ten pages. "Save as PDF" in the print dialog is your monthly report — no extra
tooling, and `--anon` strips the cash figures first if it is going to anyone
else.

**Keyboard.** `1`–`5` jump to a tab, `p` prints.

**Motion.** Panels rise in, the equity curve draws itself, funnel bars grow,
and a Live row flashes when its value actually changes on a poll — so a
five-second repaint tells you *what* moved instead of just repainting. All of it
sits behind `prefers-reduced-motion`, and the print stylesheet disables
animation and transitions outright.

### How it refreshes

In `--serve` mode the page does **not** reload. It asks for a small JSON
fragment every `--poll` seconds (default 5) and swaps the Live tab in place, so
nothing scrolls or collapses while you are reading. That request is a few KB
against ~60 KB for the whole page, and it skips the event log entirely - the
completed-trade count is cached against the log files' size and mtime, so a
poll is nearly free until the EA actually writes something.

When a trade does close, the page does not yank itself out from under you: a
*"N new trades - reload for the full history"* button appears instead. If the
server goes away the indicator reads "reconnecting" and the poll backs off
rather than hammering it.

A static `--html` file has no server to ask, so it keeps the old 60-second
meta refresh.

The table that matters most is **filters: passed vs failed at entry**. The EA
records each filter's verdict on every entry even while the quality filter is
switched off, so this compares the trades a filter would have allowed against
the ones it would have blocked:

```
Filter        Pass n  Pass net  Pass avg R   Fail n  Fail net  Fail avg R   Verdict
trend             26   1683.78        1.96       24    827.57        0.96   worth enabling
struct            25    846.81        1.08       25   1664.54        1.88   costs you money
```

"Worth enabling" means the blocked trades lost money. "Costs you money" is the
finding people miss — the filter was rejecting your better trades.

### How to read it honestly

Only completed trades count; an `ENTRY` is paired with its `EXIT_*` by
`trade_id`. Open trades and exits whose entry predates the log are reported
separately in the header, not silently dropped.

One subtlety worth knowing. For any close the EA tags itself — flip, news,
weekend, guard — it writes the exit **twice**: once from `ClosePositionTagged`
with `profit` hardcoded to 0, then again from `AuditAndLogExit` with the real
money, usually labelled `EXIT_OTHER` because the audit reads the deal reason
rather than the tag. The script assembles a trade from every row it produced,
taking the money from the row that has it and the label from the more specific
tag. Anything that pairs on the first exit row it sees books all of those
trades as a flat 0.00 and throws the real figure away.

Sample size decides everything. At 60 trades the hourly buckets hold 5–9 trades
each and the ranking is mostly noise. `--min-trades` hides the thin ones; want
30+ in a bucket before changing a setting on the strength of it. Two months of
logs before retuning is a reasonable rule.

---

## Part 1b — using it on a backtest

The same script reads a Strategy Tester log, so a backtest and live trading get
the same analysis rather than two different stories.

**In the Tester**, set these before the run:

| Input | Value | Why |
|---|---|---|
| `InpUseJsonLog` | **true** | the report's preferred source; off by default |
| `InpLogSkips` | true | records the signals the run refused |
| `InpTesterFreshLog` | true | one run, one clean file — otherwise runs append |
| `InpServerGmtOffset` | your broker's | or the IST sessions land in the wrong place |

Modelling mode: *Every tick based on real ticks* is best, but **MFE/MAE are
accurate on any mode** — each closed bar's high and low are folded in alongside
the tick sampling, and bars are real OHLC regardless. Only the ordering of the
best and worst points needs real ticks.

**After the run**, the files are in the agent's sandbox, typically:

```
<terminal>/Tester/Agent-127.0.0.1-3000/MQL5/Files/EMA_XAUUSD_M15.jsonl
```

Then:

```bash
python ema_report.py "<that path>" --html backtest_report.html
```

One self-contained HTML file — no server, no internet, nothing to install. It
opens anywhere, prints to a PDF with `Ctrl/Cmd+P`, and carries every section the
live dashboard has except the Live tab, which has nothing to show for a finished
run. A 1,900-trade year comes out around 600 KB.

Compare two runs by writing each to its own file and putting them side by side —
the figure to look at first is **Refused signals**, because a parameter change
usually moves the taken/refused split long before it moves the P&L.

---

## Part 2 — reaching it from your machine

### Option A — SSH tunnel (free, private, nothing exposed)

Best when you only need it at your desk.

On the VPS:

```bash
python ema_report.py "<path>/MQL5/Files/*.jsonl" --serve 8800
```

On your machine:

```bash
ssh -N -L 8800:localhost:8800 user@your-vps
```

Open `http://localhost:8800`. The page rebuilds on every request and refreshes
itself every 60 seconds.

The server binds to `127.0.0.1` by default, so the tunnel is the only way in —
no firewall port, no public URL.

### Option B — Cloudflare Tunnel + Access (recommended for phone access)

> Full step-by-step, including the Windows service gotcha and the Access session
> setting the polling page needs: **[CLOUDFLARE_SETUP.md](CLOUDFLARE_SETUP.md)**.
> The summary below is the shape of it.

Google sign-in in front of the dashboard, enforced before a request reaches your
VPS, with no open ports and no code. This is the plan I'd follow.

**Quick test, no domain:**

1. Download `cloudflared` on the VPS (Windows `.exe` from Cloudflare's releases).
2. Keep the dashboard on localhost as in Option A.
3. `cloudflared tunnel --url http://localhost:8800`

It prints a `https://<random>.trycloudflare.com` URL that works anywhere. Good
for testing — but the URL changes on restart and **anyone with the link gets in**.

**Permanent, with sign-in:**

4. Point a domain at Cloudflare (a Hostinger domain works — change its
   nameservers to Cloudflare's; the free plan is enough).
5. `cloudflared tunnel login`
6. `cloudflared tunnel create ea`
7. Route `ea.yourdomain.com` to `http://localhost:8800` in the tunnel config.
8. `cloudflared tunnel run ea` — install it as a service so it survives reboots.
9. Cloudflare **Zero Trust → Access → Applications** → add `ea.yourdomain.com` →
   policy: allow only your email, via Google or one-time PIN.

Now the page asks you to sign in before it renders, sessions last as long as you
configure, and the VPS never accepts an inbound connection.

### Option C — static snapshot to Hostinger

No live server, no tunnel. Least that can go wrong; data is as old as the last
upload.

1. Scheduled task on the VPS every 15 minutes:
   `python ema_report.py "<path>/*.jsonl" --html report.html`
2. Upload by SFTP (WinSCP scripting, driven by Task Scheduler).
3. In hPanel: put it in a subfolder, enable **Password Protect Directories**,
   and turn on the free SSL certificate.

### Option D — Firebase Hosting

`firebase deploy` of a single HTML file. Free, fast, trivial.

The catch: Firebase Hosting is **public by default** — static files take no
password. Firebase Auth runs in the browser and can hide a page, but it cannot
protect a file the server will hand to anyone who asks. Protecting it properly
means Firebase Auth plus a Cloud Function, or a Function that verifies an ID
token before returning the HTML.

Since the dashboard is read-only, nobody can trade or change settings through
it. The remaining risk is disclosure: balance, equity, cash P/L and lot sizes.
So Firebase is fine **if the page carries no money figures** — R-multiples, win
rates, profit factor, pips and the session and filter breakdowns reveal nothing
about account size and are the parts you actually tune on.

### Why not Firebase Auth in front of the VPS dashboard

A reasonable idea that doesn't hold up as stated. Firebase Auth is client-side:
it can hide the page, but the VPS has no idea a login happened, so typing the
VPS URL directly still returns everything. A login screen in front of an open
door. An HTTPS Firebase page also can't fetch an HTTP VPS URL — browsers block
mixed content — so the VPS needs HTTPS anyway.

It can be made real: Firebase hands the browser a signed ID token, the browser
sends it as `Authorization: Bearer <token>`, and the Python server verifies the
signature against Google's public keys and checks `aud`, `iss`, `exp` and the
email allowlist. That needs `pip install google-auth`, a JS shim on the Firebase
side, and the tunnel for HTTPS regardless — roughly 80 lines to reimplement what
Cloudflare Access does for free.

Worth it only if you already have a Firebase app this belongs inside.

### Choosing

| | Live data | Sign-in | Effort | Cost |
|---|---|---|---|---|
| A · SSH tunnel | yes | SSH key | lowest | free |
| B · Cloudflare + Access | yes | Google / email PIN | medium | free |
| C · Hostinger static | 15-min old | directory password | low | hosting |
| D · Firebase | 15-min old | none on static files | low | free |

**A** at your desk. **B** if you want it on your phone with full figures.
**C or D** if a snapshot is enough — and for **D**, strip the money figures first.

---

## Part 3 — security notes worth keeping

- The dashboard shows balance, equity and daily loss room. Treat the URL as
  account data, not a convenience link.
- An unguessable URL is not access control. Unlinked URLs leak through browser
  telemetry, extensions, shared screenshots and certificate transparency logs.
- Never open the MT5 VPS's RDP or the dashboard port directly to the internet.
  Tunnels dial out; open ports get scanned within hours.
- Your Telegram bot token sits in plaintext in `.set` files. If one is ever
  shared, revoke it with `/revoke` in BotFather and issue a new one.
- Read-only removes execution risk entirely — nobody can place a trade through
  this page. That makes disclosure the only thing left to manage, which is why
  stripping cash figures is usually enough.

---

## Part 4 — possible next additions

**To the script** (`--anon`, the live tab, day-of-week, consecutive-loss and
the CSV export are done)

- Built-in SFTP upload so the Hostinger route is one scheduled command.
- Firebase ID-token verification in serve mode, for the Part 2 Option D route.
- MAE/MFE per trade, which needs the EA to log the excursion.
- A control channel — pause entries, flatten, force a day-lock — from the
  browser. This one is not a script change: the EA has no inbound channel at
  all (no `GlobalVariable`, it reads only its own state file and only at
  startup, and Telegram is `sendMessage`-only with no `getUpdates` poll), so it
  would need a command-file poller in `OnTick`. That also ends the read-only
  property this whole security section rests on, so it needs real auth first.

**To the EA** (in the order I'd do them)

1. **Stop-level and freeze-level validation.** The halved evening stop can land
   closer to price than the broker allows and the order is rejected 10016; the
   entry is silently lost. Check before sending, then widen, skip or log clearly.
2. **Hard lot ceiling plus a margin pre-check**, so a mistyped lot can't breach
   a position-size rule and an unaffordable entry is refused with a reason.
3. **Consecutive-loss cool-off** — pause N minutes after 2–3 straight losses,
   softer than stopping the day.
4. **Slippage and retry handling** — deviation is fixed at 20 points and a
   requote currently just fails the entry.
5. **Trading-days counter**, for firms with a minimum-days requirement.
