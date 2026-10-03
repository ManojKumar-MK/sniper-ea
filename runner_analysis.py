#!/usr/bin/env python3
"""
runner_analysis.py - can a TP3+ trade be told apart AT ENTRY?

THE QUESTION
    Trades that run to TP3, TP4 and TP5 are real. The question is not whether
    they exist, it is whether anything OBSERVABLE AT THE MOMENT OF ENTRY
    separates them from the ones that stall at TP1 or stop out. If something
    does, the EA can filter for it. If nothing does, the big winners are a tail
    you must take every trade to catch - which is a completely different system
    with completely different sizing.

    This answers that from the EA's own CSV. No new backtest machinery: every
    field needed is already logged.

HOW TO PRODUCE THE INPUT
    Run one backtest with logging ON (the grid sets have it off for speed):
        InpUseCsvLog=true, InpLogSkips=false, InpEchoLogToTerminal=false
    then point this at MQL5/Files/<prefix>_<symbol>_<tf>.csv

USAGE
    python3 runner_analysis.py SniperEA_Log_XAUUSD_M5.csv
    python3 runner_analysis.py log.csv --runner-r 3.0
"""
import argparse, math, sys
import pandas as pd

# Features recorded at entry. Anything derived from the exit is excluded on
# purpose - using it would be lookahead and would "prove" a filter that cannot
# be run in real time.
FEATURES = ["ema21_50_gap_atr", "atr", "adx", "rsi", "rsi_m5", "macd_hist",
            "bull_pct", "bear_pct", "spread_pts", "volume", "vol_avg",
            "sl_distance", "sl_factor"]


def auc(pos, neg):
    """Probability a random runner scores above a random non-runner.

    0.50 = the feature knows nothing. Reported instead of a p-value because it
    says HOW separable, not merely whether a difference is detectable - with a
    few hundred trades almost anything reaches significance.
    """
    if not len(pos) or not len(neg):
        return float("nan")
    allv = sorted([(v, 1) for v in pos] + [(v, 0) for v in neg])
    ranks, i = {}, 0
    while i < len(allv):
        j = i
        while j + 1 < len(allv) and allv[j + 1][0] == allv[i][0]:
            j += 1
        r = (i + j) / 2.0 + 1
        for k in range(i, j + 1):
            ranks[k] = r
        i = j + 1
    rp = sum(ranks[k] for k in range(len(allv)) if allv[k][1] == 1)
    n1, n0 = len(pos), len(neg)
    return (rp - n1 * (n1 + 1) / 2.0) / (n1 * n0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--runner-r", type=float, default=3.0,
                    help="a trade counts as a RUNNER if it reached this many R in favour")
    a = ap.parse_args()

    df = pd.read_csv(a.csv)
    if "mfe_r" not in df.columns:
        sys.exit("no mfe_r column - this is not a SniperEA event log")

    ent = df[df.event == "ENTRY"].copy()
    # mfe_r is carried on the exit rows, so take the best seen per trade_id.
    mfe = df.groupby("trade_id").mfe_r.max()
    real = df.groupby("trade_id").r_realized.last()
    ent = ent.set_index("trade_id")
    ent["mfe_r"] = mfe
    ent["r_realized"] = real
    ent = ent.dropna(subset=["mfe_r"])
    if ent.empty:
        sys.exit("no completed trades in this log")

    ent["runner"] = ent.mfe_r >= a.runner_r
    n, nr = len(ent), int(ent.runner.sum())
    print(f"{n} trades | {nr} reached {a.runner_r}R ({100 * nr / n:.1f}%) | "
          f"mean realised {ent.r_realized.mean():+.3f}R")
    print(f"\nHow far trades actually ran (mfe_r):")
    for q in (10, 25, 50, 75, 90, 95):
        print(f"   p{q:<3d} {ent.mfe_r.quantile(q / 100):6.2f}R")

    print(f"\nIf you could take ONLY the runners: mean realised "
          f"{ent[ent.runner].r_realized.mean():+.3f}R over {nr} trades")
    print(f"If you took only the rest:          mean realised "
          f"{ent[~ent.runner].r_realized.mean():+.3f}R over {n - nr} trades")
    print("   ^ that gap is the PRIZE. What follows is whether it is reachable.")

    print(f"\nSeparability at entry (AUC; 0.50 = the feature knows nothing):")
    rows = []
    for f in FEATURES:
        if f not in ent.columns:
            continue
        s = pd.to_numeric(ent[f], errors="coerce")
        p, q = s[ent.runner].dropna(), s[~ent.runner].dropna()
        if len(p) < 5 or len(q) < 5:
            continue
        rows.append((f, auc(list(p), list(q)), p.median(), q.median()))
    rows.sort(key=lambda r: -abs(r[1] - 0.5))
    print(f"   {'feature':20s} {'AUC':>6s}  {'runners':>10s} {'others':>10s}")
    for f, u, mp, mq in rows:
        flag = "  <-- separates" if abs(u - 0.5) >= 0.10 else ""
        print(f"   {f:20s} {u:6.3f}  {mp:10.3f} {mq:10.3f}{flag}")

    best = max((abs(u - 0.5) for _, u, _, _ in rows), default=0)
    print()
    if best < 0.06:
        print("VERDICT: nothing at entry separates the runners. AUC is ~0.5 across the")
        print("board, so a filter cannot find them in advance - the big winners are a")
        print("TAIL you have to take every trade to catch. That argues for smaller size")
        print("and more trades, not for pickier entries.")
    elif best < 0.10:
        print("VERDICT: weak separation. Worth one grid, not a redesign - and check it")
        print("holds out of sample before believing it.")
    else:
        print("VERDICT: something separates them. Build a filter on the flagged features")
        print("and test it OUT OF SAMPLE - this is exactly where curve-fitting starts.")


if __name__ == "__main__":
    main()
