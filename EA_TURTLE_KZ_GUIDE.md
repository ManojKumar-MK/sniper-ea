# SniperTurtle_KZ_v1.00 — the killzone-range EA

The MQL5 side of [`sma+sniper+turtle.pine`](sma+sniper+turtle.pine).

---

## Read this first: the signal is SniperEA's, and that is the finding

The only layer in `sma+sniper+turtle.pine` that produces a **trade** — an entry, a
stop and five targets — is the Sniper layer. It is the same EMA 9/21 cross behind the
same quality filter as `SniperEntry_Strict v1.30`, with the same defaults:

| Pine | MQL5 |
|---|---|
| `ta.crossover(ema9, ema21)` (L975) | `CrossDirection()` |
| `adx >= adxMin` (25) | `InpQfTrend` / `InpAdxMin` (25) |
| `abs(ema21-ema50) >= structMult*atr` (0.5) | `InpQfStruct` / `InpStructMult` (0.5) |
| `volume > volAvg` | `InpQfVolume` |
| cooldown bars (5) | `InpQfCooldown` / `InpCooldownBars` (5) |
| ema50 side · VWAP side · bias % | `InpQfEma50` / `InpQfVwap` / `InpQfBias` |
| ladder 1R–5R (L1026–30) | `InpTP1_R` … `InpTP5_R` |

Every other layer in that script — SMC, HTF, OTE, SFP, **Turtle Soup** — draws boxes
and fires alerts. None of them opens a position. Turtle Soup in particular is
default-OFF in the Pine and is a drawing engine: porting it as a *trade* would mean
inventing entry and stop rules it does not have.

So this EA does not re-derive the signal. It inherits it, and adds the one part of
the script that had no MQL5 equivalent.

---

## How it runs by default

The killzone entry window is **ON**, with a **60-minute lead**:

| | NY clock | |
|---|---|---|
| Asia | 18:00 – 24:00 | opens an hour before the 19:00 session |
| London | 01:00 – 05:00 | opens an hour before 02:00 |
| New York | 06:00 – 10:00 | opens an hour before 07:00 |

**840 minutes a day, 58% of the clock**, with no overlap between the three. The EA is
awake for the run-up into each session and rests in between — the raid that sets a
killzone up often happens in the hour before it, which is why the lead is 60 and not 0.

**A trade opened inside a killzone carries on to its target after that killzone
closes.** The window governs *entries*; an open position is managed on every tick
regardless of the clock — ladder, stop stepping, runner all keep working. In `OnTick`
the management runs before the window check, so this is structural rather than a
setting that could drift.

`InpKzCloseAtEnd` would flatten at the session end instead. It is **off**, and should
stay off unless you specifically want that: closing a winner because the clock struck
is a different decision from not opening one.

To trade all day instead, set `InpUseKzWindow=false`. `turtle-grid/TU_nokzwindow` is
that run, so you can see what the window is worth before deciding.

---

## What is new: killzone ranges

The killzone **window** (already in SniperEA) governs *when* you may enter. This
module is *where* — and where is the half you trade against. Asia's high and low are
the liquidity London raids; London's are what New York runs.

```
KILLZONE  high / low
  Asia    4361.20 / 4342.10  high taken  | 5d 4375.00 / 4330.40
  London  4370.50 / 4355.00  open        | 5d 4381.20 / 4344.10
  NY      no session yet
  sweeps  2026.09.24 14:05 Asia H @ 4375.00 | 2026.09.23 09:40 London L @ 4344.10
```

Each session's high and low are tracked live and **held after the session closes**
rather than blanked — which is exactly when you start trading against them. Completed
sessions go into a short history (`InpKzrDays`, default 5 = a trading week) and the
**weekly** level is the extreme across it.

That distinction is the whole point. A session high that is merely today's gets taken
several times a week and means little. The one that has stood all week is where the
stops have had time to pile up, and taking **that** is the event worth knowing about
without scrolling back through the chart.

### The re-arm rule, and why it is not a detail

A level re-arms when a new session replaces it, so a sweep is reported once per level
rather than once per bar. Without it there is a false positive waiting: when the
oldest day drops out of the history the weekly level can move **down** to a price the
market is already above, and the EA would announce a sweep that never happened. The
port keeps the Pine's guard — a level is armed only if price is on the correct side of
it at the moment it starts being watched.

---

## Inputs

| Input | Default | |
|---|---|---|
| `InpUseKzWindow` | **true** | entries only inside a killzone |
| `InpKzLeadMin` | **60** | minutes before each killzone that entries open |
| `InpKzCloseAtEnd` | false | leave off — lets a trade run past the session end |
| `InpKzrOn` | true | track the three session ranges |
| `InpKzrDays` | 5 | completed sessions to remember (1–10). 5 is a trading week |
| `InpKzrAlertSweep` | true | Telegram + log when a weekly level is taken |
| `InpKzrFilter` | **false** | OFF = recording only. It blocks nothing until you turn this on |
| `InpKzrFilterMode` | 0 | 0 = require a recent sweep in the trade's favour · 1 = block entries heading into an untaken level |
| `InpKzrSweepBars` | 12 | mode 0: how recently the sweep must have happened |
| `InpKzrNearAtr` | 1.0 | mode 1: how close counts as "in front of", in ATR |

**Mode 0** takes a long only after a weekly *low* was taken — buying where the sell
stops just went, which is the reason for tracking these at all.

**Mode 1** refuses an entry with an untaken pool sitting just ahead of it. The pool is
the magnet; being early into it is a poor place to be.

The sessions and the clock are shared with the killzone window module
(`InpKzAsiaSess`, `InpKzLondonSess`, `InpKzNYSess`, read on the New York clock with US
DST handled per bar), so the two can never drift apart.

---

## What carried over from SniperEA

Everything, unchanged: the 5-level ladder and stop stepping · the runner · session
stop widths · the killzone entry window · prop/funded guards · daily loss cap and
profit target · weekend flattening · news filter · CSV and JSON logging · skip audit ·
MFE/MAE · state persistence · Telegram · dashboard · order-comment reason code ·
signals-only mode.

Magic **994000**, logs `SniperTurtle_Log_*`, Telegram prefix `SniperTurtle` — so it
runs beside SniperEA (990021) and SniperSweep (993000) without touching either.

---

## Two things to know before running it

**The history starts empty on every load.** Until a killzone has closed there is no
weekly level, so `InpKzrFilter` in mode 0 refuses *every* entry. The startup banner
says so explicitly rather than leaving you to diagnose a silent EA. Give it a day, or
backtest from a start date early enough to warm up.

**Recording is the useful default.** With the filter off, every entry still carries
`KZR=` in the CSV note — what was last swept, how long ago, which side. That is the
evidence for whether the filter is worth switching on. Decide it from your own data
rather than from the idea being appealing.

Nothing here has been compiled. Compile with F7 before the grid — MT5 silently ignores
inputs an older `.ex5` lacks, so you would get nine identical runs and no error.

See [turtle-grid/README.md](turtle-grid/README.md) for the 9-set backtest grid, whose
whole purpose is to answer whether the filter earns its place.

---

## The trade preset

[`SniperTurtle_Trade.example.set`](SniperTurtle_Trade.example.set) — **derived from
`SniperEA_990555.set`**, not rebuilt from the template. All 139 shared keys are carried
verbatim, so the trading behaviour is the one you already run; only what would make
this EA collide with SniperEA is overridden:

| Key | 990555 | here | why |
|---|---|---|---|
| `InpMagic` | 990555 | **994000** | otherwise it manages SniperEA's open trades |
| `InpCsvPrefix` | `SniperEA_990555` | `SniperTurtle_Log` | otherwise both EAs interleave rows in one file |
| `InpTgPrefix` | `SniperEntry EA 1.30v =>` | `SniperTurtle` | otherwise you cannot tell which EA sent a message |

Plus the new module at its defaults: ranges **recording**, filter off. It prints and
alerts and blocks nothing, while every entry still carries `KZR=` in the CSV — which is
how you get the evidence before deciding whether to switch the filter on.

### Lot size: it is a flat 0.05, not 0.5%

`InpUseSessionLots=true` is carried from the base, and it **wins over
`InpRiskPercent`**. So this preset trades a flat 0.05 lot and the `0.5` sitting in
`InpRiskPercent` does nothing at all.

That is what 990555 actually does, so it is carried on purpose. But it is also exactly
the trap that made an earlier backtest look risk-sized when it was flat-lot, so it is
stated in the `.set` header too. To size by risk, set **both** `InpUseSessionLots` and
`InpUseFixedLot` to false — only then does the percentage apply.

---

## The FundedNext 25k preset

[`SniperTurtle_FundedNext_25k.example.set`](SniperTurtle_FundedNext_25k.example.set) —
for a **Stellar 1-Step $25K**, with the plan's figures taken in **cash**, as the page
states them, so there is no percentage to mis-key.

| Plan rule | | EA stops first at |
|---|---|---|
| Profit target | $2,500 | `InpDailyProfitTarget` $250/day → 10 such days |
| Daily loss limit | $750 | **$600** (`InpMaxDailyLossMoney`) |
| Maximum loss | $1,500 | **$1,200** (80% of `InpMaxTotalLossMoney`) |
| Drawdown type | **Static** | `InpDrawdownMode=0` |
| Min trading days | 2 | — see the warning below |
| News trading | Allowed | `InpUseNewsFilter=false` |
| Max risk | 3% at any time | 0.35%/trade = **$87.50**, one position |

Plus a **soft cash cap at $250** that flattens and ends the day — which is about 2.9
losing trades, so it lands in the same place as `InpMaxLossesPerDay=3` rather than
fighting it.

**Why $600 and not $750.** The daily cap has no stop-at-% of its own, unlike the total
loss guard — it halts at exactly the figure given. Set it to $750 and the EA stops at
the precise moment you have breached. The headroom has to be in the number.

**Why static and not "both".** `InpDrawdownMode=2` adds a trailing-from-peak stop this
firm does not measure. It would halt you mid-challenge on a rule that does not exist.
Do not set it to 2 to be safe; here it is the less safe choice.

**Min 2 trading days is the risk nobody plans for.** Killzone-only entries can go quiet
for days. Confirm in the backtest that this configuration trades often enough to clear
that rule — passing on profit and failing on activity is a real way to lose a
challenge. `turtle-grid/TU_fn25k` runs exactly this configuration so you can count the
trading days rather than hope.

### Before it goes on a live chart

- Fill `InpTgToken` / `InpTgChatId` on the machine; they are blank in the repo.
- Check `InpServerGmtOffset` against your broker — the killzone ranges are cut on the
  NY clock derived from it, so a wrong offset puts Asia/London/NY boundaries in the
  wrong place and every level with them.
- The EA is **not compiled**. Nothing above has been run.
