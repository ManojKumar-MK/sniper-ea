#!/usr/bin/env python3
"""
One click, every grid.

Runs the registered grids across M15/M5/M3, merges each
grid's runs, then copies the SUMMARIES into backtest-results/<stamp>/ so they
can be committed and compared later.

    python run_all.py                  every grid, every timeframe
    python run_all.py --years 2023,2024,2025,2026    one window per year
    python run_all.py --grids turtle   just that one
    python run_all.py --periods M5     just that timeframe
    python run_all.py --collect-only   re-collect results already on disk
    python run_all.py --list           show what would run, and exit

Everything after `--` is passed straight through to run_backtests.py, so
    python run_all.py -- --from 2026.01.01 --to 2026.09.18
works without this script having to know about every flag.

WHAT GETS COLLECTED, and what does not:
  copied  all_results.csv, comparison.csv, run.log     - small, diffable, the
                                                         part you actually read
  left    report_*.htm, logs/, *.ini                   - MT5's raw output. A
                                                         full grid is tens of
                                                         MB of HTML that no one
                                                         reads twice, and it
                                                         does not diff.
Pass --with-reports if you want the HTML too.
"""
import argparse, datetime, glob, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))

#  A grid is a folder with its own sets, its own EA, and its own run_backtests.py.
GRIDS = {
    "kz":     dict(folder="kz-grid",     sets="sets_kz",
                   expert="SniperEntry_Strict_SessionFilter_Telegram_v1.30.ex5",
                   out="results_kz"),
    "turtle": dict(folder="turtle-grid", sets="sets_turtle",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_tu"),
    #  v2 lives beside v1 rather than replacing it: v1's numbers stay on disk
    #  and stay comparable, and the two differ in the spine (v1 had the server
    #  session filter on), so merging them into one table would mislead.
    "v2":     dict(folder="turtle-grid", sets="sets_v2",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_v2"),
    "v3":     dict(folder="turtle-grid", sets="sets_v3",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_v3"),
    "v4":     dict(folder="turtle-grid", sets="sets_v4",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_v4"),
    "v5":     dict(folder="turtle-grid", sets="sets_v5",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_v5"),
    "v6":     dict(folder="turtle-grid", sets="sets_v6",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_v6"),
    "v7":     dict(folder="turtle-grid", sets="sets_v7",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_v7"),
    "v8":     dict(folder="turtle-grid", sets="sets_v8",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_v8"),
    "v9":     dict(folder="turtle-grid", sets="sets_v9",
                   expert="SniperTurtle_KZ_v1.00.ex5",
                   out="results_v9"),
    "gmp":    dict(folder="gmp-grid", sets="sets_gmp",
                   expert="GridMaster Pro.ex5", out="results_gmp"),
    "smc":    dict(folder="smc-grid", sets="sets_smc",
                   expert="EA_Script.ex5", out="results_smc"),
    "orb":    dict(folder="orb-grid", sets="sets_orb",
                   expert="GOLD_ORB.ex5", out="results_orb"),
    "fvg":    dict(folder="fvg-grid", sets="sets_fvg",
                   expert="FvgGold.ex5", out="results_fvg"),
    "ote":    dict(folder="ote-grid", sets="sets_ote",
                   expert="SniperOTE_Fib_v1.00.ex5",
                   out="results_ote"),
}
#  M15 first, because it is where the evidence landed: it is the only frame
#  whose drawdown stays inside the funded 6% limit, and the only one the
#  chosen config passes on. M5 and M3 are the robustness check - a result on
#  one frame and not the others is a property of the frame, not the strategy.
PERIODS = ["M15", "M5", "M3"]
SUMMARIES = ("all_results.csv", "comparison.csv", "run.log")


def count_sets(g):
    return len(glob.glob(os.path.join(HERE, g["folder"], g["sets"], "*.set")))


def run_grid(key, g, periods, spans, passthrough, mt5dir, deposit):
    """
    spans: list of (label, date_from, date_to). One entry = one window.

    The dates are passed EXPLICITLY on every call. They used to be left off
    entirely, which silently fell through to run_backtests.py's own defaults -
    a single 3.5-month window - while the .bat files looped over whole years.
    The deposit came through because its default had been changed to match, so
    the run looked configured when only half of it was.
    """
    folder = os.path.join(HERE, g["folder"])
    runner = os.path.join(folder, "run_backtests.py")
    if not os.path.isfile(runner):
        print(f"  ! {g['folder']}/run_backtests.py is missing - skipped")
        return False
    ok = True
    for label, d_from, d_to in spans:
        for p in periods:
            out = f"{g['out']}_{label}_{p}" if label else f"{g['out']}_{p}"
            cmd = [sys.executable, "run_backtests.py",
                   "--sets", g["sets"], "--out", out, "--period", p,
                   "--expert", g["expert"], "--skip-done", "--portable",
                   "--deposit", str(deposit),
                   "--from", d_from, "--to", d_to]
            if mt5dir:
                cmd += ["--terminal", os.path.join(mt5dir, "terminal64.exe"),
                        "--data-dir", mt5dir]
            cmd += passthrough
            print(f"\n===== {key} grid, {label or 'default'} {p}  ({d_from} - {d_to}) =====")
            print("  " + " ".join(cmd))
            rc = subprocess.call(cmd, cwd=folder)
            if rc != 0:
                print(f"  ! {key}/{label}/{p} exited {rc}")
                ok = False
    print(f"\n----- merging {key} -----")
    subprocess.call([sys.executable, "run_backtests.py", "--merge-all"], cwd=folder)
    return ok


def collect(keys, stamp, with_reports):
    dest_root = os.path.join(HERE, "backtest-results", stamp)
    copied = 0
    for key in keys:
        g = GRIDS[key]
        src_folder = os.path.join(HERE, g["folder"])
        dest = os.path.join(dest_root, key)

        top = os.path.join(src_folder, "all_results.csv")
        if os.path.isfile(top):
            os.makedirs(dest, exist_ok=True)
            shutil.copy2(top, os.path.join(dest, "all_results.csv")); copied += 1

        for rd in sorted(glob.glob(os.path.join(src_folder, "results*"))):
            if not os.path.isdir(rd):
                continue
            sub = os.path.join(dest, os.path.basename(rd))
            for name in SUMMARIES:
                f = os.path.join(rd, name)
                if os.path.isfile(f):
                    os.makedirs(sub, exist_ok=True)
                    shutil.copy2(f, os.path.join(sub, name)); copied += 1
            if with_reports:
                for rep in glob.glob(os.path.join(rd, "report_*.htm*")):
                    os.makedirs(sub, exist_ok=True)
                    shutil.copy2(rep, os.path.join(sub, os.path.basename(rep))); copied += 1

    if not copied:
        print("\nNothing collected - no results*/ folders with summaries yet.")
        print("That usually means the runs did not produce reports. Check the")
        print("run.log in each grid folder, and that the .ex5 is compiled.")
        return None

    os.makedirs(dest_root, exist_ok=True)
    with open(os.path.join(dest_root, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(f"# Backtest run {stamp}\n\n")
        fh.write("Collected by `run_all.py`.\n\n")
        fh.write("| Grid | Sets | Summary |\n|---|---|---|\n")
        for key in keys:
            n = count_sets(GRIDS[key])
            fh.write(f"| {key} | {n} | [all_results.csv]({key}/all_results.csv) |\n")
        fh.write("\n`all_results.csv` is every run of that grid across every "
                 "timeframe.\n`comparison.csv` inside each `results_*` folder is "
                 "that one timeframe.\n\n")
        fh.write("Rank by the **worst** timeframe, not the best: a set that "
                 "prints well on M5 and loses on M3 has found an M5 artifact, "
                 "not an edge.\n")
        if not with_reports:
            fh.write("\nMT5's raw `report_*.htm` files were not collected "
                     "(`--with-reports` keeps them). They are large, they do not "
                     "diff, and everything in them that matters is in the CSVs.\n")
    print(f"\nCollected {copied} file(s) into backtest-results/{stamp}/")
    return dest_root


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--grids", default="all",
                    help="comma list: kz,sweep,turtle  (default: all)")
    ap.add_argument("--periods", default=",".join(PERIODS),
                    help="comma list of timeframes (default: M15,M5,M3)")
    ap.add_argument("--mt5dir", default=r"C:\MT5-Tester",
                    help=r"portable MT5 folder (default: C:\MT5-Tester)")
    ap.add_argument("--years", default="",
                    help="comma list of whole calendar years to run, e.g. "
                         "2023,2024,2025,2026 - each becomes its own window and its "
                         "own results folder. Omit to use --from/--to instead.")
    ap.add_argument("--from", dest="date_from", default="2026.01.01",
                    help="start date when --years is not used (default 2026.01.01)")
    ap.add_argument("--to", dest="date_to", default="2026.09.18",
                    help="end date when --years is not used (default 2026.09.18)")
    ap.add_argument("--deposit", type=int, default=25000,
                    help="tester starting balance (default 25000, the FundedNext 25k "
                         "account). Risk-%% sizing is a fraction of the balance, so this "
                         "changes position size on every set - not just the funded one.")
    ap.add_argument("--with-reports", action="store_true",
                    help="also copy MT5's raw report_*.htm into backtest-results")
    ap.add_argument("--collect-only", action="store_true",
                    help="skip the runs, just gather what is already on disk")
    ap.add_argument("--list", action="store_true", help="show what would run, then exit")
    args, rest = ap.parse_known_args()
    passthrough = [a for a in rest if a != "--"]

    keys = list(GRIDS) if args.grids == "all" else [k.strip() for k in args.grids.split(",") if k.strip()]
    bad = [k for k in keys if k not in GRIDS]
    if bad:
        sys.exit(f"unknown grid(s): {', '.join(bad)}   known: {', '.join(GRIDS)}")
    periods = [p.strip().upper() for p in args.periods.split(",") if p.strip()]

    if args.years:
        spans = [(y.strip(), f"{y.strip()}.01.01", f"{y.strip()}.12.31")
                 for y in args.years.split(",") if y.strip()]
    else:
        spans = [("", args.date_from, args.date_to)]

    total = sum(count_sets(GRIDS[k]) for k in keys) * len(periods) * len(spans)
    print("=" * 62)
    print(f"  grids    : {', '.join(keys)}")
    print(f"  periods  : {', '.join(periods)}")
    print(f"  windows  : " + " | ".join(f"{d} - {t}" for _, d, t in spans))
    print(f"  backtests: {total}")
    print(f"  deposit  : {args.deposit:,} USD")
    for k in keys:
        g = GRIDS[k]
        exe = os.path.join(args.mt5dir, "MQL5", "Experts", g["expert"])
        mark = "ok " if os.path.isfile(exe) else "?? "
        print(f"    {mark}{k:7} {count_sets(g):3} sets   {g['expert']}")
    print("=" * 62)
    if args.list:
        return

    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    if not args.collect_only:
        missing = [GRIDS[k]["expert"] for k in keys
                   if not os.path.isfile(os.path.join(args.mt5dir, "MQL5", "Experts", GRIDS[k]["expert"]))]
        if missing:
            print("\nThese are not in " + os.path.join(args.mt5dir, "MQL5", "Experts") + ":")
            for m in missing:
                print("   " + m)
            print("\nCompile with F7 and copy them there first. MT5 ignores inputs an")
            print("older .ex5 does not have WITHOUT AN ERROR, so a stale build gives")
            print("you a grid of identical runs and nothing to explain them.")
            if input("\nRun anyway? [y/N] ").strip().lower() not in ("y", "yes"):
                return
        for k in keys:
            run_grid(k, GRIDS[k], periods, spans, passthrough, args.mt5dir, args.deposit)

    dest = collect(keys, stamp, args.with_reports)
    if dest:
        print("\nNext:")
        print(f"  git add backtest-results/{stamp} && git commit -m 'backtest {stamp}'")


if __name__ == "__main__":
    main()
