# SniperOTE_Fib_v1.00 — session impulse into the OTE retrace

The MQL5 port of **"Fib OTE Trade Setup [TP/SL]"**. A genuinely different model from the
rest of this repo: a **trend-aligned pullback**, not a cross and not a sweep.

Derived from `SniperTurtle_KZ v1.00`, so the ladder, runner, prop guards, daily caps,
weekend and news filters, CSV/JSON logging, skip audit, MFE/MAE, state persistence,
Telegram, dashboard and signals-only mode all come across unchanged. **One thing differs:
what fires a trade.**

Magic **995000**, logs `SniperOTE_Log_*` — runs beside SniperEA (990021), SniperSweep
(993000) and SniperTurtle (994000) without touching any of them.

---

## The model

**1 — IMPULSE.** Inside a session, track the high and the low made since it opened.
**Whichever extreme came last gives the direction**: a high after a low is a bullish
impulse. That is what makes it a leg rather than a range.

**2 — QUALIFY.** The leg must span at least `InpOteMinAtr` ATR, and at least
`InpOteImpulseLen` bars must have passed since the open. Optionally price must also be on
the right side of a trend EMA.

**3 — OTE.** Price retraces into the **0.618–0.79** zone of that leg. A touch is enough.

**4 — STOP.** Beyond the impulse swing (the Pine default), or an ATR multiple, or a fixed
distance.

**5 — TARGET.** One fixed R multiple. No ladder.

One trade per session by default.

### Two things about the Pine that are easy to read past

Both are reproduced faithfully rather than "improved", because changing either would make
this a different model that nobody has tested.

**The impulse keeps updating all session**, not just during the first `InpOteImpulseLen`
bars. A new extreme late in the session redefines the leg and moves the zone.

**Direction is whichever extreme came last.** A session that puts in its low and then
rallies is bullish, and the model waits for a dip back. It is a pullback model — it never
fades the leg.

---

## Inputs

| Input | Default | |
|---|---|---|
| `InpOteOn` | true | master switch |
| `InpOteImpulseLen` | 12 | bars after the open before an entry can be taken |
| `InpOteZ1` / `InpOteZ2` | 0.618 / 0.79 | the retrace zone, as fibs of the leg |
| `InpOteMinAtr` | 1.0 | minimum leg size. Without it a flat session gives a zone a few points wide |
| `InpOteUseTrend` | true | longs only above the trend EMA |
| `InpOteTrendEma` | 50 | |
| `InpOteStopMode` | 0 | 0 = beyond the swing · 1 = ATR · 2 = fixed |
| `InpOteStopAtr` / `InpOteStopFixed` | 1.5 / 5.0 | for modes 1 and 2 |
| `InpOteStopBuf` | 0.0 | extra ATR beyond the swing. 0 puts the stop exactly on the extreme |
| `InpOteRR` | 2.0 | target as a multiple of the real risk |
| `InpOteOnePerSess` | true | off allows re-entry after a stop-out — a different model |

**Sessions** reuse the killzone plumbing, so the same DST-correct New York clock drives
them — but the defaults differ, matching the Pine: London **0200-0600**, NY **0930-1200**,
Asia **off**, lead **0** (the impulse is measured from the open, so there is no lead-in).

---

## The one configuration trap

**`InpUseScaleOut` must be `false`.**

The Pine model has a single take-profit at an R multiple. Leave the 5-level ladder on and
`InpOteRR` is silently ignored — TP1–TP5 take over instead. Every set in `ote-grid/` has
the ladder off and `InpTpRMultiple` carrying the R target, and the startup banner warns if
you load a config that gets this wrong.

Because the stop is structural, **1R varies per trade**, so `OpenTrade` lays the target
out from the real distance. `InpSlAtrMult`, the halved-evening factor and
`InpTpFromHalvedRisk` are all bypassed — with a structural stop there is nothing to scale.

---

## Backtesting

`ote-grid/RUN_OTE.bat` — 25 sets × M15/M5 × 4 years = **200 runs**.

`OTE_ctrl` is the Pine script's own defaults. **Read it first.** If the model has nothing
there, no amount of zone tuning will supply it — the blocks that follow vary the zone, the
impulse size, the leg length, the stop, the target, the trend filter and the sessions, and
all of them are downstream of whether the idea works at all.

---

## Status

**Not compiled.** This is new source — expect to fix something on the first F7.

It has also never been backtested, so every claim above is about what the code does, not
about whether it makes money. The Pine header calls this "the one setup that survived
out-of-sample + RR-robustness testing in our research" — that is the script author's
claim about their own testing, not a result from this repo.
