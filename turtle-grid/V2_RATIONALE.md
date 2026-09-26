# v2 grid — what the v1 results actually said, and what v2 does about it

56 runs (28 sets × M5/M3). `RUN_V2.bat`, or `python run_all.py --grids v2`.

v1's numbers are in `all_results.csv` and stay there. v2 does **not** replace them —
the spine differs, so the two must not be merged into one table.

---

## What v1 showed

**1. The control lost money.** `TU_ref_kz60`: −1977 on M5, +32 on M3. The EA as shipped
is not profitable over Jan–Sep 2026. Everything positive in v1 came from switching on
the quality filter, which ships `false`.

**2. One filter condition carried everything.** Single-condition runs, worst timeframe:

| | worst net | trades |
|---|---|---|
| VWAP | **+2220** | 437 |
| cooldown | −439 | 589 |
| EMA50 | −1572 | 513 |
| bias | −2030 | 613 |
| volume | −2665 | 343 |
| ADX ≥ 25 | −2896 | 283 |
| EMA separation | −4078 | 342 |

VWAP was the only profitable single. **EMA separation and ADX were the two worst** — and
both are on in the EA's default tick set, which is why `TU_qf_default` needs 5 conditions
to reach a profit that VWAP alone beats on net.

**3. The window block was unreadable.** `InpUseSessionFilter=true` with hours 0–11
*server* time was in every set, ANDed with the killzone window:

| | killzone | AND session |
|---|---|---|
| lead 60 | 840 min | 540 |
| lead 120 | 1020 | **660** |
| no window | — | **660** |

At lead 120 the killzones fully contain the session window, so `TU_lead120` came out
byte-identical to `TU_nokzwindow`, and `TU_nokzwindow` never tested "all day" at all.

**4. The range filter has no sample.** Mode 0 produced 2, 8, 16, 13 and 5 trades. Not
"bad" — no data. Requiring a weekly sweep *and* an EMA cross *and* a killzone almost
never coincides.

**5. The exit logic was never tested.** All 33 sets shared an identical ladder. This is
the important one — see below.

---

## The arithmetic that points at the exits

Win rate sits at **~24%** in nearly every v1 run. With `InpUseFullTarget=true` the whole
position runs to TP5 at **5R**, so breakeven is `1/(1+5)` = **16.7%**.

A 24% win rate against a 16.7% breakeven should be comfortably profitable. Instead
profit factor is ~0.95 and the payoff ratio comes out 2.85–5.45 rather than 5.

The likely reason is in the same block: `InpTrailBehindTP=true` steps the stop
BE → TP1 → TP2 → TP3. A trade that reaches TP1 and retraces is closed at breakeven or
TP1 — a small win — while every loser pays the full stop. The ladder promises 5R and the
trail keeps collecting 0–1R.

**If that is right, the entry is not the problem and no amount of filtering fixes it.**
That is the single biggest thing v2 tests.

---

## The 28 sets

Spine for all of them: session filter **off**, killzone window on at lead 60, quality
filter on with **VWAP only**, unique `InpCsvPrefix`, risk 0.5%.

### A — Exits and the ladder (10 sets, the untested axis)

| Set | |
|---|---|
| `V2_exit_partials` | book TP1–TP4 instead of running full size to TP5 |
| `V2_exit_notrail` | stop stays where it started — stop cutting winners at BE |
| `V2_exit_noboth` | both of the above |
| `V2_exit_tp3` | ladder 0.75–3.75R, nearer targets |
| `V2_exit_tp2` | ladder 0.5–2.5R, nearer still |
| `V2_exit_single3R` | one TP at 3R, no ladder |
| `V2_exit_single2R` | one TP at 2R |
| `V2_exit_runner` | do not book TP5, let it run |
| `V2_exit_nohalf` | no halved stop in the evening session |

`V2_exit_notrail` is the direct test of the theory above. If the trail is the problem,
that set should improve on the control while taking the *same trades*.

### B — Stop size (3)

`V2_sl15`, `V2_sl25`, `V2_sl30` — ATR multiple 1.5 / 2.5 / 3.0 against the default 2.0.
Also never varied in v1, and it moves 1R, so it moves the whole ladder with it.

### C — VWAP-centred filter combinations (7)

v1 only tested 1 condition or 5. The useful region is in between.

`V2_qf_vwap_cool`, `V2_qf_vwap_ema50`, `V2_qf_vwap_trend`, `V2_qf_vwap_adx30`,
`V2_qf_vwap_cool_ema50`, `V2_qf_default`, and **`V2_qf_default_novwap`** — the default
five minus VWAP, which says whether VWAP is carrying that combination or merely riding
in it.

### D — The killzone window, now uncontaminated (4)

`V2_kz_off`, `V2_kz_lead0`, `V2_kz_lead30`, `V2_kz_lead120`. With the session filter off
these finally mean what they say, and `V2_kz_off` is a real all-day run.

### E — Daily caps (3)

v1's one genuine drawdown improvement: `TU_tgt100_cap80` cut max DD from 18.9% to 10.9%
while turning a loss into a profit. `V2_tgt100_cap80`, `V2_cap80` and `V2_tgt100` re-test
it on the new spine.

Treat that result with suspicion until it repeats. In v1 **both** components lost on
their own and only the combination won, which is the shape of a coincidence as often as
a discovery.

### F — Funded (1)

`V2_fn25k`. In v1 it lost on both timeframes (−1231 / −1215, PF 0.83 / 0.92) and would
have failed the challenge.

---

## Reading it

- **`V2_ctrl` first.** If it is not clearly better than `TU_ref_kz60`, the spine change
  did not help and the rest needs reading with that in mind.
- **Then the exit block.** If nothing there fixes profit factor, the problem is the entry
  after all, and the EMA cross needs replacing rather than filtering.
- Rank by the **worst** timeframe. Under ~30 trades a set has said nothing.
- A filter only removes trades: compare **expectancy per trade** and drawdown, not net.

## What this grid cannot tell you

Every set is fitted to the same nine months of XAUUSD. Picking the best of 28 on one
period is how overfitting happens. Whatever wins here needs an out-of-sample run on
dates this grid never saw before it goes near a funded account.
