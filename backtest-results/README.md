# backtest-results

One folder per run, stamped `YYYY-MM-DD_HHMM`, written by
[`run_all.py`](../run_all.py).

This folder is **committed on purpose**. A `.set` file means very little without
the run that justified it, and six months from now the question is always "what
did we actually test, and when" — which is unanswerable if the results only ever
lived on one machine.

## What is in each run

```
2026-09-26_2110/
  README.md              what ran, and how to read it
  turtle/
    all_results.csv      every set, every timeframe, one table
    results_tu_M5/
      comparison.csv     that timeframe alone
      run.log            what the tester actually did
```

## What is deliberately not in it

MT5's raw `report_*.htm`. A full grid is tens of megabytes of HTML that does not
diff and holds nothing the CSVs do not. `run_all.py --with-reports` keeps them if
you need one for a specific question — but think before committing them.

## Reading them

- **Rank by the worst timeframe, not the best.** A set that prints beautifully on
  M5 and loses on M3 has found an M5 artifact, not an edge.
- **Read the control first.** `REF_nokz`, `SW_base_day`, `TU_ref_kz60` — a variant
  only means something against the run it was varied from.
- **Under ~30 trades a set has said nothing yet**, whatever its win rate.
- **Breakeven win rate for a 1:N model is `1/(1+N)`.** At 1:3 that is 25%, so 40%
  is a wide margin, not a mediocre one. Judge against that, not against 50%.
- A daily profit target **cannot raise gross profit** — it only removes trades
  after the target was hit. Compare max daily loss and drawdown, not net.
