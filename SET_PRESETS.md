# Presets from `all_results.csv`

81 runs · M3 / M5 / M15 · 2026-01-01 → 2026-09-18.

---

## The headline run is the one to avoid

`W_sl3p0_L8_t25` tops the file on M15 — **PF 1.55**, net 5770. Its other two
timeframes:

| | M3 | M5 | **M15** |
|---|---|---|---|
| `W_sl3p0_L8_t25` | 1.06 | **0.93** | **1.55** |

It loses money on M5. A setting that only works at one timeframe is usually
telling you about that window rather than about the market, and picking the
largest number in an 81-run grid is how you select for exactly that.

**Rank by each run's WORST timeframe instead** and something different comes
out — the top four are all VWAP-filtered:

| Run | M3 | M5 | M15 | worst |
|---|---|---|---|---|
| `W_sl2p5_L5_ema50_vwap` | 1.23 | 1.25 | 1.29 | **1.23** |
| `W_sl2p5_L8_vwap` | 1.24 | 1.20 | 1.46 | **1.20** |
| `W_sl2p5_L5_vwap` | 1.27 | 1.32 | 1.20 | 1.20 |
| `W_sl3p0_L5_vwap` | 1.22 | 1.13 | 1.37 | 1.13 |

**VWAP is the finding in this sweep.** Every run carrying it is profitable on
all three timeframes; nothing else manages that.

Cooldown looks excellent on M3 and M15 (PF 1.52 / 1.25) and **falls to 0.93–0.98
on M5** — real, but timeframe-dependent. `_t25` and `_all3` are single-timeframe
peaks.

---

## The three presets

| File | From | M3 | M5 | M15 | Trades |
|---|---|---|---|---|---|
| `SniperEA_A_vwap_robust.set` | `W_sl2p5_L8_vwap` | 1.24 | 1.20 | 1.46 | 189–325 |
| `SniperEA_B_vwap_ema50.set` | `W_sl2p5_L5_ema50_vwap` | 1.23 | 1.25 | 1.29 | 125–287 |
| `SniperEA_C_m15_cooldown.set` | `W_sl3p0_L8_cool` | 1.13 | **0.96** | 1.52 | 163 |

**A** — start here. Best worst-case with a usable trade count.
**B** — flattest across timeframes; lower ceiling, fewer trades. Flat usually
means the result belongs to the model rather than the window.
**C** — **M15 only**, and the file says so in its header. It loses on M5.

Each is a **verbatim copy of the run's own `.set`**, differing only in a header
comment and `InpCsvPrefix`. All 133 keys match the source file, so a re-run
reproduces the backtest exactly. `InpTgToken` / `InpTgChatId` are blank.

---

## Corrected once the source `.set` files arrived

The first version of these presets was rebuilt from
`SniperEA_Trade.example.set` and **would not have reproduced the numbers
above**. Against the real run files it carried five differences, two of them
decisive:

| Key | I had | Actual sweep | Effect |
|---|---|---|---|
| `InpSessionStartHour` | `0` | **`3`** | **real — changes which trades exist** |
| `InpDailyProfitTarget` | `50.0` | `0.0` | **real — caps the day at +50** |
| `InpPipSize` | `0.0` | `0.10` | pip *reporting* only |
| `InpUseFixedLot` | `true` | `false` | **none** — see below |
| `InpCommentLogic` | present | absent | cosmetic |

**Rebuilding from the template was the wrong method** — the presets are now
copies of the run files themselves, which makes drift impossible rather than
merely unlikely.

### Correction: the sizing claim above was wrong

I first read `InpUseFixedLot=false` as "the sweep sized by `InpRiskPercent`".
It did not. `CalcLots()` has a precedence order:

```
1) InpUseSessionLots  ->  InpDayLot / InpEveningLot
2) InpUseFixedLot     ->  InpFixedLot
3) neither            ->  risk % of balance
```

Both files set `InpUseSessionLots=true` with `InpDayLot=InpEveningLot=0.05`, so
**sizing never reaches the `InpUseFixedLot` line at all** — that difference was
inert, and both would have traded the same flat 0.05 lot. `InpRiskPercent=0.5`
sits in the file doing nothing.

**Which means every figure in this document is for a flat 0.05 lot.** They do
not scale with account size and the drawdown percentages are relative to
whatever balance the tester ran on. Raise the lot and net, drawdown and the cash
value of every R rise in exact proportion.

### The two mappings, now confirmed rather than inferred

- **`L8` = TP ladder `1 / 2 / 4 / 6 / 8`** — exactly as inferred. `L5` is the
  default `1/2/3/4/5`; `L4` is `1 / 1.5 / 2.5 / 3 / 4`.
- **`_t25` = `InpDailyProfitTarget=25.0`**, a daily profit stop — which is why
  the `filters` column reads `none`. Not a Quality Filter at all.

Also worth knowing: every `REF_*` run uses `InpSessionStartHour=0` and
`InpDailyProfitTarget=50`, while every `W_*` run uses `3` and `0`. **The two
families are not directly comparable** — REF vs W differs by more than the
parameter in the name.

---

## Two things the table does not say

**Drawdown is high.** 20–35% at `InpRiskPercent=0.5`. That is the observed
figure, not a limit — doubling risk doubles it. A 30% drawdown on M15 means
roughly a third of the account gone before the equity curve recovers, and the
sweep cannot tell you whether you would still be running the EA at that point.

**Every number is in-sample.** The parameters were chosen on 2026-01-01 →
09-18 and the PFs are measured on that same window, so they are optimistic by
an unknown amount. Before committing real money:

1. Re-run **A** on a window the sweep never saw — 2025, or paper-forward from
   today.
2. Expect the PF to come down. **How far** is the number that matters, not
   whether it does.
3. Only then consider **C**, and only on M15.
