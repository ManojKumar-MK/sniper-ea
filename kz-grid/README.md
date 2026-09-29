# Killzone grid

10 sets × M5 / M3 = **20 backtests**, one click.

```
RUN_KZ.bat
```

Reuses `run_backtests.py` from `ema-final-grid.zip` — it already drives the
Tester, collects the HTML reports and merges them. One flag was added to it,
`--portable`; see below.

---

## The tester terminal

The runs drive a **separate portable MT5** so your live terminal keeps running
untouched.

1. Install a second MT5 to `C:\MT5-Tester` (not the default path)
2. Shortcut with `/portable` appended — this exact command line:

   ```
   C:\MT5-Tester\terminal64.exe /portable
   ```

   `/portable` is what makes the terminal keep its data folder **beside
   `terminal64.exe`** instead of under `%APPDATA%\MetaQuotes\Terminal\<hash>`.
   The `.bat` passes `--portable` to every tester run as well, so both halves
   agree on where `MQL5\Profiles\Tester` actually is. Without it the runner
   stages each `.set` into `C:\MT5-Tester\...` while the terminal reads from
   `%APPDATA%` — every run produces no report and the failure looks like a
   missing EA.
3. Launch it, log in, and copy the compiled `.ex5` into
   `C:\MT5-Tester\MQL5\Experts\`
4. Open an XAUUSD M3 chart there and scroll back past 1 Jan so it downloads the
   history
5. **Close that terminal.** MT5 will not start a tester pass while the same
   portable instance is open. Leave your live one running.

---

## Compile first

The `InpKz*` inputs **do not exist** in an `.ex5` built before this change, and
MT5 ignores unknown keys **silently**. Every run would come back identical to
the control and look like the killzone window does nothing.

F7 in MetaEditor → copy the `.ex5` to `C:\MT5-Tester\MQL5\Experts\`. The `.bat`
checks the file is there and stops if it is not.

---

## The grid

One engine across every run — SL ATR × 2.5, ladder 1/2/4/6/8, quality filter
off, session filter off, 0.05 lots, no prop guards. **Only the killzone inputs
vary**, verified by diffing each set against the control.

| Set | The question it asks |
|---|---|
| `REF_nokz` | **the control** — killzone window off |
| `KZ_all_lead30` | the ask: 30 min before → killzone close, all three |
| `KZ_all_lead00` | does the lead-in matter, or is the killzone enough? |
| `KZ_all_lead15` | half the lead |
| `KZ_all_lead60` | double it — if 60 > 30 > 0, the run-in carries something |
| `KZ_asia_lead30` | Asia alone |
| `KZ_london_lead30` | London alone |
| `KZ_ny_lead30` | New York alone |
| `KZ_ldnny_lead30` | the two liquid sessions, no Asia |
| `KZ_all_lead30_close` | same, but flat at the killzone end — isolates the **exit** |

Guards are off on purpose. A daily loss cap truncates bad days and a profit
target truncates good ones, and either would make the killzone comparison
measure the guard instead.

---

## Reading it

`all_results.csv` holds every run. **Start with `REF_nokz`** — a killzone
number only means something next to it.

Three questions, in order:

1. **Does the window help at all?** `KZ_all_lead30` vs `REF_nokz`. If PF is
   flat, the window is cutting trades without improving them.
2. **Does the lead-in matter?** `lead00` → `15` → `30` → `60`. A clean
   gradient is a finding; noise across them means 30 was arbitrary.
3. **Which killzone carries it?** Asia / London / NY alone. If one is doing
   all the work, trading the other two is paying spread for nothing.

Then check the **trade count**. A window that allows 12.5 of 24 hours should
cut trades by roughly half; far fewer than that and you are reading a
small-sample result, not an edge.

Rank by the **worst** timeframe, not the best — that is how the earlier sweep's
headline run turned out to lose money on M5.

---

## `SniperEA_FundedNext_25k.set`

Not part of the grid. Live-ready, and deliberately conservative.

**The guard numbers in it are mine, not FundedNext's.** I cannot verify your
programme's rules, so they are set tighter than any limit I am aware of:

| | |
|---|---|
| daily loss | 3% = **$750** |
| inner day cap | **$400** — independent of prop mode |
| overall loss | 6% = **$1500**, halting at 80% = **$1200** |
| losing trades | 3/day |
| daily target | 1.5% = **$375** |

**Open your FundedNext dashboard, read your real limits, and set the EA's
below them — not equal to them.** The EA halts at `InpTotalLossStopPct` of
whatever figure you give it; that gap is what stops a breach being one bad tick
away.

Sizing is risk-% — 0.4% of the 25,000 baseline = **$100 per trade**, so it
scales with the account. Session lots are off.

Engine is preset A from the earlier sweep (SL 2.5, ladder to 8R, VWAP filter)
with the killzone window on. Telegram is off with a blank token — fill it in
locally.

> Backtest it on your own data before it sees the evaluation. Every figure in
> `SET_PRESETS.md` is in-sample, and the killzone window has not been tested at
> all yet — that is what the grid above is for.
