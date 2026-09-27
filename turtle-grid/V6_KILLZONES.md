# v6 — every killzone combination

14 sets × M15/M5 × 4 years = **112 runs**. `RUN_V6.bat`, or `python run_all.py --grids v6`.

## The seven combinations

All-off is omitted — it would trade nothing.

| Set | Asia | London | NY |
|---|---|---|---|
| `_asia` | ✔ | | |
| `_london` | | ✔ | |
| `_ny` | | | ✔ |
| `_asia_london` | ✔ | ✔ | |
| `_asia_ny` | ✔ | | ✔ |
| `_london_ny` | | ✔ | ✔ |
| `_all` | ✔ | ✔ | ✔ |

Windows are unchanged — Asia `1900-2400`, London `0200-0500`, NY `0700-1000` on the New
York clock, each opening 60 minutes early.

## Two bases, on purpose

Each combination exists twice.

**`KZ_*` — no prop guards.** The clean read on which killzone carries the edge. This
matters: with the guards on, a bad year halts the EA partway through, and the comparison
then measures *when the halt fired* rather than how the killzone performed. In 2024 the
guarded 0.5% config took 23 trades against 91 unguarded, so more than two thirds of that
year was the guard, not the strategy.

**`KZFN_*` — the FundedNext 25k guards.** Which combination actually passes.

`KZ_all` and `KZFN_all` are the controls — byte-identical to `V5_notrail` and
`V5_fn_r050` apart from the log prefix, verified.

**Read `KZ_*` to learn, `KZFN_*` to decide.** If they disagree, the guards are shaping the
result and the answer is about risk settings rather than about sessions.

## What to look for

**Is one session carrying the other two?** If `_london` alone beats `_all`, then Asia and
NY are costing money and the current config is paying for them.

**Do the pairs behave additively?** If `_asia_london` is roughly `_asia` + `_london`, the
sessions are independent and you can pick freely. If it is much worse, they are
interfering — most likely through the cooldown or through one session leaving a position
open into the next.

**Does any of it hold in 2023 and 2024?** A killzone that only works in 2025 and 2026 was
selected on 2025 and 2026. Those two years chose everything upstream of this grid; give
the two older ones more weight than their row count suggests.

## The trap in this particular grid

Seven combinations × two bases × four years × two timeframes is **112 chances for
something to look good**. The best of 112 will always look convincing.

A finding is only worth acting on here if the **same** combination wins in most of the
four years, in both bases. One combination winning one year is noise with a name.

## Expected trade counts

Fewer sessions means fewer trades, and this strategy has already shown that the results
thin out fast — on M15 the control takes 23–91 trades a year. A single-session set may
land under 30 trades in a year, which is not a bad result, it is no result. Check the
count before reading the net.
