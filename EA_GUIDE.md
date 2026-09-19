# EMA Based Strategy EA — reference

MQL5 expert advisor. EMA9/EMA21 cross entries, ATR stop, a five-level target
ladder, IST-aware sessions, prop-account guards, Telegram reporting and a
machine-readable event log.

File: `SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5`
Version 1.30 · Manojkumar K · mailtomktech@gmail.com

The filename carries the version, so old builds stay on disk next to new ones
and MT5 lists them separately. Bump both the filename and `#property version`
together — MetaTrader shows the property, the folder shows the filename, and
they should never disagree.

**1.30** — runner mode (`InpRunUntilFlip`), heartbeat (`InpHeartbeatMin`),
skip audit (`InpLogSkips`), MFE/MAE on every exit.

---

## 1. What it does

**Entry.** On each closed bar: buy when EMA9 crosses above EMA21, sell when it
crosses below. One position at a time; an opposite signal flips it. Entries are
gated by the server-time session window, the spread cap, the optional quality
filter, the news blackout, the weekend cutoff and (in prop mode) the loss guards.

**Stop.** ATR(14) × `InpSlAtrMult`, halved in the evening session if
`InpUseHalfSlOutside` is on.

**Targets.** TP1–TP5 at 1R–5R. By default nothing is booked at TP1–TP4: full
size runs to TP5 and the stop steps up one level at a time —
TP1 → breakeven, TP2 → TP1, TP3 → TP2, TP4 → TP3, TP5 → close.

Turn `InpUseFullTarget` off to get the older behaviour: 20 % booked at each of
TP1–TP4 with the stop trailing behind each level.

**Runner.** With `InpRunUntilFlip` on, TP5 stops being an exit. The position
runs on and the stop keeps stepping one rung behind, exactly as it does below
TP5 — 6R → SL to TP5, 7R → SL to 6R, and so on at `InpRunnerStepR` spacing. The
trade then ends only on the trailed stop, the opposite EMA cross, or one of the
usual guards. Off by default; nothing changes unless you turn it on.

## 2. The two IST sessions

Stop width differs, and the evening can be switched off, narrowed or thinned out
by the hour. Management is otherwise identical.

| | Day | Evening |
|---|---|---|
| IST window | 00:00–16:00 | 16:00–00:00 |
| Stop | ATR × mult | that × `InpOutsideSlFactor` (0.5) |
| Lot | `InpDayLot` | `InpEveningLot` |
| Partials | none | none |
| Risk % | `InpDayRiskPct` | `InpEveningRiskPct` |
| Can be switched off | no | **yes** — `InpTradeEvening` |

The session is decided once, at entry, and stays with the trade.

`InpTpFromHalvedRisk` decides whether the evening targets shrink with the stop
(`true`, keeping the same 1R–5R shape at half the distance) or stay at the full
ATR distances (`false`, making evening trades 2R–10R off a tighter stop).

> **Equal lots ≠ equal risk.** The evening stop is half as wide, so the same lot
> risks half the money. Set `InpEveningLot` to roughly double `InpDayLot` if you
> want the two sessions risking the same amount.

### Switching the evening off, or thinning it out

Three controls, and they compose — an evening entry needs all three to agree.

| Input | Default | What it does |
|---|---|---|
| `InpTradeEvening` | `true` | `false` = no new entries 16:00–00:00 IST at all |
| `InpEveEntryStartIST` / `InpEveEntryEndIST` | `16` / `0` | narrows the evening entry window (`16`/`20` = 4–8 PM only) |
| `InpEveH16` … `InpEveH23` | all `true` | untick one hour to skip it and keep the rest |

So 4–8 PM with 6–7 PM skipped is `InpEveEntryEndIST = 20` plus
`InpEveH18 = false`.

**These decide whether to enter, never how wide the stop goes.** The evening
still uses `InpOutsideSlFactor`, unchanged.

**An open trade is never touched.** Switching an hour off stops new entries in
it; a position carried into that hour runs to its own SL/TP. Stopping entries
and flattening a live trade are different decisions, and only the first is what
these inputs do.

Every refusal is written as its own `SKIP` row with the reason
(`evening session switched off`, `IST hour 18:00-19:00 switched off`, …), so
the dashboard's refused-signals panel shows exactly what each toggle cost you.

> **Check this before trusting any of it.** All of the above is gated by the
> *server-clock* window on top. With the default `InpSessionStartHour 0` /
> `EndHour 11` on a GMT+3 broker that is 02:30–13:30 IST, which never reaches
> the evening — so these inputs, `InpEveningLot` and `InpOutsideSlFactor` are
> all inert. The EA now detects this and prints
> `evening | WARNING: the server entry window … never reaches an evening IST
> hour` at startup. Widen the server window, or ignore the evening entirely.

### Per-session risk %

`InpUseSessionRisk` swaps the single `InpRiskPercent` for `InpDayRiskPct` and
`InpEveningRiskPct`. It only affects the risk-% branch — session lots still beat
fixed lot, and fixed lot still beats risk %.

The evening stop is already halved, so the **same** risk % there buys roughly
double the lot. `InpEveningRiskPct` defaults to `0.25` against `0.5` for the day
for that reason.

## 3. Clocks — three of them, deliberately

| What | Clock | Input |
|---|---|---|
| Day / evening split | **IST** | `InpDaySessionStartIST` / `EndIST` |
| Logged timestamps | **both** | `t_srv` + `t_ist` on every row; state carries `entryIstFull` and `entrySrvFull` |
| Entry window | **broker/server** | `InpSessionStartHour` / `EndHour` |
| Weekend cutoff | **broker/server** | auto-detected from the symbol's sessions |
| Prop day reset | either | `InpDayResetHour` + `InpDayResetUseIST` |

IST is derived from the broker's GMT offset, auto-detected live and taken from
`InpServerGmtOffset` in the Strategy Tester. **Set that to your broker's offset
before backtesting** or the sessions land in the wrong place. Startup prints the
offset it resolved — check it once.

> A common mistake: a server-time entry window of 00:00–11:00 on a GMT+3 broker
> is roughly 02:30–13:29 IST, which sits entirely inside the day session — the
> evening half-stop can then never trigger. The startup banner labels the entry
> window as SERVER time directly under the IST session lines for this reason.

### The GMT offset — set it, don't detect it

`InpAutoGmtOffset` now defaults to **`false`**, and `InpServerGmtOffset` is the
value actually used.

Auto-detect derived the offset from `TimeCurrent() - TimeGMT()`. `TimeCurrent()`
is the time of the *last quote*, not the server's clock, so it stops advancing
whenever ticks stop — a quiet hour, an illiquid symbol, the minutes before the
Friday close — while `TimeGMT()` keeps running. The gap was absorbed into the
offset and then snapped to a half hour:

| Feed idle | Offset it produced (true GMT+3) |
|---|---|
| 20 min | GMT+2.5 |
| 90 min | GMT+1.5 |
| 5 h | GMT−2.0 |
| 48 h | GMT+3.0 — fell outside the 14-hour guard and used the input |

Everything under ~14 hours passed the sanity check and was believed, which is
why it never showed up over a weekend.

**Set `InpServerGmtOffset` to your broker's real offset.** The cost is DST: most
forex brokers run GMT+2 in winter and GMT+3 in summer, so it needs changing twice
a year. The startup banner prints the value in force — check it once each season.

> This matters beyond timestamps. The IST hour drives `InDaySessionIST()`, which
> now **gates entries** through `InpTradeEvening` and the per-hour toggles. A
> wrong offset does not just mislabel a trade, it skips the wrong hours.

**A wrong offset is recoverable in the log.** The dashboard can redo the
conversion from the broker's own `t_srv` stamp with `--gmt-offset`, across
history, without recompiling or re-running a backtest. See REPORT_AND_DEPLOY.md.

## 4. Inputs by group

### Signal
`InpEmaFast` 9, `InpEmaMid` 21, `InpEmaTrend` 50, `InpAtrPeriod` 14,
`InpTradeOnClose` true.

### Risk and stop
`InpSlAtrMult` 2.0 · `InpRiskPercent` 0.5 · `InpUseFixedLot` / `InpFixedLot`
`InpUseSessionLots` true, `InpDayLot` 0.05, `InpEveningLot` 0.05

Sizing precedence: session lots → fixed lot → risk %.

### Targets
`InpUseScaleOut` true · `InpTP1_R`…`InpTP5_R` 1–5 · `InpPartialPct` 20
`InpTrailBehindTP` true · `InpUseFullTarget` true

### TP5 — `InpBookAtTP5` **true**
`InpRunnerStepR` 1.0 · `InpFlipExitAnyTime` true

**`true` books at TP5 and closes the trade** — the default, and what the EA
already did. **`false` lets it run**: TP5 stops closing, the stop keeps stepping
one rung behind (6R → SL to TP5, 7R → SL to 6R, …), and the trade ends on the
opposite EMA cross, the trailed stop or a guard. `InpRunnerStepR` and
`InpFlipExitAnyTime` only do anything when it is `false`.

> Replaces `InpRunUntilFlip`, inverted. `InpRunUntilFlip = false` and
> `InpBookAtTP5 = true` are the same setting, so the default behaviour is
> unchanged — but a saved `.set` file from an earlier build will not carry over
> and reverts to booking at TP5.

`InpFlipExitAnyTime` matters more than it looks. A flip is normally only
detected inside the entry window, because `SessionAllowed()` gates
`EvaluateSignal()`. A runner held past that window would otherwise ride on with
nothing but the trailed stop under it until the window reopened — on the default
00:00–11:00 server window, potentially thirteen hours. With it on, an opposite
cross **closes** the runner at any hour; it never opens a new position outside
the window, so entries stay governed by the session filter as before.

> The runner has no upper bound and no time limit. It is held over the weekend
> only as far as `InpHoldOverWeekend` allows, and the news and prop guards still
> flatten it, but otherwise a trend can carry it for days. Size accordingly.

### Sessions
`InpDaySessionStartIST` 0 · `InpDaySessionEndIST` 16
`InpTradeEvening` true · `InpEveEntryStartIST` 16 · `InpEveEntryEndIST` 0
`InpEveH16`…`InpEveH23` all true
`InpUseSessionRisk` false · `InpDayRiskPct` 0.5 · `InpEveningRiskPct` 0.25
`InpUseHalfSlOutside` true · `InpOutsideSlFactor` 0.5 · `InpTpFromHalvedRisk` true
`InpUseSessionFilter` true · `InpSessionStartHour` 0 · `InpSessionEndHour` 11

### Weekend
`InpHoldOverWeekend` false · `InpFridayCloseBufferMin` 15
`InpFridayCloseHour` −1 (auto-detect) · `InpBlockFridayEntries` true

### News
`InpUseNewsFilter` **false** · `InpNewsMinsBefore` / `After` 15
`InpNewsImportance` 2 · `InpNewsCurrencies` "" · `InpNewsCloseOpen` false
`InpNewsManualTimes` "" · `InpNewsTgAlerts` true · `InpNewsAlertMins` 15

Alerts work independently of the filter: leave the filter off and you still get
a formatted heads-up on Telegram.

### Funded account — `InpPropMode` **false**
With it off, no guard runs and none of their lines print. With it on:

`InpBaselineBalance` · `InpDayResetHour` / `Minute` / `UseIST`
`InpMaxDailyLossPct` 4.0 · `InpMaxDailyLossMoney` · `InpDailyWarnPct` 75
`InpMaxLossesPerDay` 3 · `InpCloseOnDailyCap` true
`InpDrawdownMode` 2 · `InpMaxTotalLossPct` 10 · `InpTotalLossStopPct` 90 ·
`InpTotalWarnPct` 70

`InpDrawdownMode`: 0 static from baseline, 1 trailing from peak equity,
2 both — whichever is hit first. Use 2 when unsure which your firm applies.

The overall guard stops at 90 % of the limit by default, leaving headroom before
a real breach. A daily lock clears at the next reset.

> An overall lock does **not** clear on a restart. `acctLocked` is written to the
> state file and is not day-scoped, so `LoadState()` restores it every time the
> EA starts. Clearing it means deleting `<prefix>_<symbol>_<tf>_state.txt` — and
> that also discards the day tally and the finished-day history, so only do it
> deliberately.

> With `InpPropMode` off there is **no daily loss cap at all**, even though the
> percentage still shows a value. Turn it on if you want that protection on a
> personal account.

### Signal audit
`InpLogSkips` true

Every EMA cross that was **not** taken is written as a `SKIP` row carrying the
same `logic` and `filters` blocks an `ENTRY` does, plus the reason it was
refused: `weekend cutoff`, `news blackout`, `loss guard locked`, `outside the
entry window`, `quality filter`, `already positioned that way`,
`spread N > max M`, `lot size calculated as 0`.

One row per closed bar, and only when a cross actually happened — an idle EA
writes nothing. Without this the log holds only the trades that got through, so
every filter is judged on survivors; this is what lets the report say how many
signals a setting cost you.

### Heartbeat
`InpHeartbeatMin` 5 (0 = off)

The state file is rewritten every N minutes on a **timer**, not on ticks, plus
once at startup. That matters: ticks stop when the market is quiet or the price
feed dies, so a tick-driven heartbeat cannot tell a quiet Tuesday from a crashed
terminal. On a timer, an old timestamp means one thing — the EA is not running —
which is what makes the dashboard's freshness badge worth trusting.

### Shutdown behaviour

The day is wrapped up — `DAY_SUMMARY` emitted, the row pushed into the
weekly/monthly history, the tally cleared and the state file written — only when
the EA is genuinely going away: `REASON_CLOSE`, `REASON_REMOVE`,
`REASON_CHARTCLOSE`.

A recompile, a parameter change, a timeframe switch or a template reload
deliberately does **none** of that. The EA is back within seconds in those cases,
and rolling the day there would publish a partial summary and hand back a fresh
daily loss allowance to anyone who touched the inputs.

### Strategy Tester
`InpTesterFreshLog` true

Each run of a backtest writes into the same agent sandbox, so without this run
two appends to run one and the report reads a blend of both. With it on, the
`.csv`, `.jsonl` and state file are deleted at the start of every Tester run —
one backtest, one clean set of files. It never touches anything outside the
Tester.

Two other things happen automatically in the Tester: the heartbeat timer is not
started (nothing is watching, and it would rewrite the state file thousands of
times over a simulated year), and the last day is always rolled at the end of
the run so the final `DAY_SUMMARY` is never lost.

The startup banner prints a `TESTER` line naming whether the JSON log, the skip
audit and the fresh-file behaviour are on, and warns if `InpServerGmtOffset` is
still 0.

### Excursion (MFE / MAE)

Every `EXIT_*` row now carries `mfe_r` and `mae_r` — the furthest the trade ran
**in favour** and **against**, in R, sampled on every tick from entry. They are
also two new CSV columns and two new lines on the Telegram close card.

MFE says whether the targets were ever reachable; MAE says how much of the stop
was actually needed. A book of trades with MAE never worse than −0.4R is telling
you the stop is wider than it needs to be.

**They hold up in the Strategy Tester.** As well as sampling the price on every
tick, each bar that closes after the entry bar has its high and low folded in.
That matters because on *Open prices only* and *1 minute OHLC* the Tester calls
`OnTick` only a handful of times per bar, and tick sampling alone would badly
understate both figures — but the bars are real OHLC on every modelling mode, so
the magnitudes come out the same. The entry bar itself is skipped, since its
range includes movement from before the trade existed.

What bar folding cannot recover is *sequence* — whether the trade hit its worst
point before or after its best one. If that matters to you, run *Every tick
based on real ticks*.

> **The CSV gained two columns** (`mfe_r`, `mae_r`, before `balance`). The header
> is only written when the file is new, so an existing `.csv` will keep its old
> 54-column header while new rows carry 56 fields. Start a fresh file — rename
> the old one, or change `InpCsvPrefix` — or read the `.jsonl` instead, which is
> self-describing and unaffected.

### Restart recovery
`InpPersistState` true. State is written after every event, at startup, and on
the heartbeat timer, to `<prefix>_<symbol>_<tf>_state.txt`.

### Telegram
`InpUseTelegram`, `InpTgToken`, `InpTgChatId`, `InpTgPrefix`, per-event toggles,
`InpTgHtmlStyle`, `InpTgDayTable`, `InpTgNotifyPeriod`, `InpPipSize`.

Setup once: Tools → Options → Expert Advisors → allow WebRequest for
`https://api.telegram.org`. WebRequest never runs in the Strategy Tester.

### Logging and dashboard
`InpUseCsvLog` true · `InpUseJsonLog` false · `InpEchoLogToTerminal` true
`InpCsvPrefix` · `InpShowPanel` true plus position, font and colour inputs.

## 5. Terminal output

Every line is `[SNIPER][TAG] field | field | field`. Tags: `CONFIG SESS ENTRY
LOGIC FILTER TP SL EXIT FLIP GUARD HALT NEWS STATE PERIOD DAILY EVENT SKIP ERROR TG`.

An entry prints four lines:

```
[SNIPER][ENTRY ] BUY  0.05 lots (day lot) @ 4352.55 | SL 4348.00 (x1.00) | mode FULLTGT | DAY session | IST 00:09
[SNIPER][LOGIC ] EMA 9/21/50 4388.96 / 4389.22 / 4383.60 | prev 9/21 4389.73 / 4389.55 | gap 2.467 ATR | ATR 2.27 | ADX 24.00
[SNIPER][LOGIC ] RSI 42.79 (M5 56.74) | MACD 0.83 / sig 2.11 / hist -1.27 | VWAP 4368.81 | close 4385.91 | vol 489 vs avg 697 | bias bull 28.6% bear 42.9% | spread 37
[SNIPER][FILTER] quality filter OFF | cross EMA9<EMA21 | trend FAIL | struct PASS | vol PASS | cool PASS | ema50 FAIL | vwap FAIL | bias PASS
```

Filter verdicts print even when the filter is off, so the log tells you what
enabling it *would* have blocked. The report script turns that into a verdict.

A banner prints at startup, at each new trading day, and whenever the IST
session flips — settings in force, day-to-date result, loss room, gates, and
whether a position is being carried across.

## 6. Event log

Two files in `MQL5/Files`, same events, different shapes.

**CSV** (`InpUseCsvLog`) — 56 fixed columns, one row per event, for Excel.
Files written by a version before 1.30 have 54 — see the column note above.

**JSONL** (`InpUseJsonLog`) — one JSON object per line, shaped by event type:

```json
{"seq":19,"t_srv":"...","t_ist":"...","event":"ENTRY","sym":"XAUUSD","tf":"M3",
 "trade":10579769801,"dir":"SELL","mode":"FULLTGT","session":"DAY",
 "logic":{"ema9":...,"adx":24.00,"rsi":42.79,"macd":0.83,"vwap":4368.81,
          "vol":489,"vol_avg":697,"bull_pct":28.6,"spread":37},
 "filters":{"enabled":false,"cross":"EMA9<EMA21","trend":0,"struct":1},
 "acct":{"balance":101760.74,"equity":101911.04},"note":"..."}
```

Entry rows carry the reasoning; TP, SL and exit rows carry `result` instead.
`trade` groups every row of one trade; `flip_from` links a flip to the trade it
replaced.

With the runner on, `TP5_EXIT` is replaced by `TP5_REACHED` and the rungs above
it are logged as `TP6_REACHED`, `TP7_REACHED` and so on, each with its `SL_MOVE`.
The report script grows its ladder funnel to match.

Events: `SKIP ENTRY ADOPTED FLIP TP1_REACHED…TP5_EXIT TPn_PARTIAL SL_MOVE
EXIT_SL EXIT_BE EXIT_TRAIL_SL EXIT_TP EXIT_FLIP EXIT_WEEKEND EXIT_NEWS
EXIT_DAILYCAP EXIT_GUARD NEWS_PAUSE HALT_* DAY_SUMMARY WEEK_SUMMARY MONTH_SUMMARY`.

For reports: group by `trade`, take the `ENTRY` row for the reason and the last
`EXIT_*` row for the outcome.

## 7. Telegram

Entry with levels and reasoning · each TP with the stop move · exit with pips,
R and net · news ahead / paused / clear · guard warnings and stops ·
daily summary with a per-trade table · weekly and monthly roll-ups with a
per-day table.

Times are IST. Messages over 3800 characters split automatically.

## 8. Restart behaviour

On start the EA loads its state file and looks for a live position.

- **State matches** → full recovery: entry, 1R, TP ladder, which TPs already
  fired, the day tally and the day's trade rows.
- **No state, position open** → adopted with an approximate 1R rebuilt from the
  live stop distance. Logged as `ADOPTED`, tagged `…-ADOPTED`, and the log says
  plainly that the ladder may differ from the original.

Same trading day → the tally and loss count survive, so a restart cannot hand
back a fresh daily allowance. New day → trade state survives, tally resets.

`LoadState()` decides this by reading the saved `day=` stamp before it applies
anything else. On a new day it drops the day-scoped keys — `dayStartBal`,
`dayLocked`, `warnDaily`, `dTrades/dWins/dLoss`, `dGrossP/dGrossL`, `dSwap`,
`dComm`, `dR`, `dBest`, `dWorst` — and keeps `baseline`, `peakEquity`,
`acctLocked` and the finished-day history. That is what makes an unplanned
reboot survivable; see **[RESTART_RECOVERY.md](RESTART_RECOVERY.md)**.

> Two instances on the same symbol and timeframe share a state filename. Put the
> magic number in `InpCsvPrefix` to keep them apart.

## 9. Two-instance setup

Run one copy with `InpSignalsOnly = true` for a pure Telegram feed (no orders,
tracks the trade virtually from price), and another with it false to trade.
Give them different magic numbers and different `InpCsvPrefix` values.

## 10. Before going live

- [ ] `InpServerGmtOffset` matches the broker, for tester runs
- [ ] Startup `[CONFIG]` lines read as expected — clock, sessions, guards
- [ ] Entry window (server) actually reaches the IST sessions you intend
- [ ] `InpPipSize` matches how you count a pip on this symbol
- [ ] WebRequest allowed for `api.telegram.org` if using Telegram
- [ ] `InpPropMode` on, with `InpBaselineBalance` set, for a funded account
- [ ] Broker preserves close comments (check the Trade tab after one exit)
- [ ] Demo for a week before real money

## 11. Known limitations

- Calendar functions are unavailable in the Strategy Tester; the news filter
  falls back to `InpNewsManualTimes` there.
- Stop-level and freeze-level are not yet validated before sending an order. A
  halved evening stop can be rejected as 10016 "Invalid stops" on a tight
  symbol — the entry is lost with only an `[ERROR]` line. This is the next
  thing worth building.
- No hard lot ceiling or margin pre-check yet.
- Guards measure account equity, so another EA's floating loss on the same
  account counts toward them.
- Deviation is fixed at 20 points; requotes fail the entry rather than retry.
