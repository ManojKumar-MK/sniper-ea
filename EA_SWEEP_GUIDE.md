# SniperSweep_PDHPDL_v1.00 — the PDH/PDL sweep EA

The MQL5 port of `ict_sweep_model.pine` (see [PINE_SWEEP_MODEL.md](PINE_SWEEP_MODEL.md)
for the model itself and why each rule is there).

It is **derived from `SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5`, deliberately.**
Everything around the trade is that EA's code, unchanged. One thing differs: what fires a trade.

| | SniperEntry_Strict | SniperSweep_PDHPDL |
|---|---|---|
| Trigger | EMA 9 crosses EMA 21 | raid → MSS → FVG |
| Stop | `ATR × InpSlAtrMult` | beyond the raid extreme (structural) |
| 1R | the same every trade | varies per trade — the ladder is laid out from the actual distance |
| Magic | 992000 | **993000** |
| CSV | `SniperEA_Log_*` | `SniperSweep_Log_*` |
| Telegram prefix | `SniperEA` | `SniperSweep` |

Different magic and different log prefix, so **both can run on the same symbol at the
same time** without touching each other's positions or overwriting each other's files.

---

## The signal, in four steps

**1 — RAID.** Price wicks through the previous day's (or week's) high or low and
**closes back inside it**. A close *beyond* is a breakout — the opposite read — and
arms nothing. This is the whole distinction the model rests on.

**2 — MSS.** Within `InpSwConfirmBars` a candle **closes through the most recent
opposing swing**. That is a market structure shift. One strong candle is not — which
is why `InpSwMssStrict=false` is the cruder setting, not the looser one: it fires
inside a continuing trend with no turn at all.

The MSS can never be the raid bar itself. The raid candle closed back *inside* the
level; if a nearby swing let it also count as the shift, the EA would enter on the
raid with nothing having confirmed it.

**3 — ENTRY.** At the MSS close, or on a retrace into the fair value gap the
displacement left behind (`InpSwEntryMode`). An unfilled retrace is abandoned after
`InpSwLimitBars`.

**4 — STOP.** Beyond the raid extreme plus `InpSwStopBufAtr × ATR`. Not
ATR × multiplier — the stop is *where the idea is wrong*, which is a place on the
chart, not a volatility number.

---

## Inputs that are new

Everything else is SniperEA's and is documented in [EA_GUIDE.md](EA_GUIDE.md).

### Raid
| Input | Default | |
|---|---|---|
| `InpSwLongs` / `InpSwShorts` | true / true | buys from a low raid, sells from a high raid |
| `InpSwUseDay` | **true** | previous DAY high/low (PDH/PDL) |
| `InpSwUseWeek` | false | previous WEEK (PWH/PWL). Heavier pools, reversals run further — but a few times a month, not daily |
| `InpSwConfirmBars` | 6 | how long a raid stays armed waiting for its MSS. Too short misses slow reversals; too long enters on something unrelated to the raid |

### Structure shift
| Input | Default | |
|---|---|---|
| `InpSwMssPivot` | 2 | bars either side of a swing. A swing needs this many bars *after* it to confirm, so the level being broken was always visible in real time — no hindsight |
| `InpSwMssStrict` | **true** | close through the last opposing swing. false = close beyond the raid candle (cruder) |

### Entry
| Input | Default | |
|---|---|---|
| `InpSwEntryMode` | 0 | 0 = FVG of the MSS leg · 1 = market at the MSS close · 2 = 50% of the raid leg |
| `InpSwFvgSide` | 1 | 0 = near edge (fills most, worst price) · 1 = **CE, the 50%** (ICT standard) · 2 = far edge (best price, most often missed) |
| `InpSwFvgLook` | 5 | bars back from the MSS bar to find the imbalance |
| `InpSwSkipNoFvg` | true | no gap, no trade. false = take it at market and **tag it**, so you can check afterwards whether those were worth having |
| `InpSwLimitBars` | 8 | an unfilled retrace entry is abandoned after this many bars |

### Stop
| Input | Default | |
|---|---|---|
| `InpSwStopBufAtr` | 0.25 | buffer beyond the raid extreme, in ATR. 0 puts the stop exactly on the wick, where a one-tick overshoot takes you out |
| `InpSwStopFromFvg` | false | true = stop just beyond the FVG. Much tighter, so the same target is a far larger R — **and a normal retrace through the gap takes you out of a trade that was still right** |

### The EMAs are still there
`InpEmaFast/Mid/Trend` no longer trigger anything, but they are still read: the bias
score, the quality filter's EMA50 side, the `[LOGIC]` line, the order-comment reason
code and the dashboard all use them. Keeping them costs one indicator handle and keeps
every one of those outputs identical to the EMA EA — which is what makes the two
comparable.

---

## What carried over from SniperEA

All of it, and unchanged: the 5-level target ladder and stop stepping · the runner ·
session stop widths · the killzone entry window (`InpUseKzWindow`, `InpKzLeadMin`) ·
prop/funded guards · the daily loss cap and daily profit target · weekend flattening ·
the news filter · CSV and JSON logging · the skip audit · MFE/MAE · state persistence
across restarts · Telegram · the on-chart dashboard · the order-comment reason code ·
signals-only mode.

Two small adaptations:

- `OpenTrade()` takes `double structStop=0.0`. When a structural stop is passed, **that**
  price is the stop and 1R is the real distance to it — `InpSlAtrMult`, the halved-risk
  factor and `InpTpFromHalvedRisk` are all bypassed, because with a structural stop there
  is nothing to halve.
- `CrossDirection()` now returns the pending sweep direction, so the **skip audit still
  works** — it tells you which setups were rejected and by which filter, exactly as before.

The order comment reads `SWP <code>` and carries the raid level: `DH` `DL` `WH` `WL`.
The CSV note carries `SETUP=`.

---

## Before you run it

1. **Compile it (F7).** None of the `InpSw*` inputs exist in any older `.ex5`, and MT5
   **silently ignores keys it does not recognise** — you would get a grid of identical
   runs and never know why.
2. Backtest it. `sweep-grid/` is a one-click grid — see [sweep-grid/README.md](sweep-grid/README.md).
3. Demo it. Real spread and slippage change these results, and a structural stop is
   more slippage-sensitive than a fixed one.

`SniperSweep_PDHPDL_v1.00.mq5` has **not been compiled yet** — it is new source. Expect
to fix something on the first F7.
