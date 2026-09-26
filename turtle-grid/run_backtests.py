#!/usr/bin/env python3
"""
run_backtests.py - run every .set in a folder through the MT5 Strategy Tester,
then put the results side by side.

MetaTrader can be driven from the command line with an .ini config file. This
script writes one .ini per .set, launches the terminal, waits for it to finish,
collects the HTML report, and at the end parses every report into one table.

Windows only - it needs terminal64.exe. Run it on the machine MT5 is installed on.

    python run_backtests.py --sets sets\\ --symbol XAUUSD --period M15 ^
        --from 2026.06.01 --to 2026.09.18

Add --compare-only to re-parse reports you already have without running anything.

Standard library only.
"""

import argparse
import configparser
import datetime as _dt
import csv
import glob
import html as html_mod
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime

# --------------------------------------------------------------------------
# finding MetaTrader
# --------------------------------------------------------------------------

TERMINAL_GUESSES = [
    r"C:\Program Files\MetaTrader 5\terminal64.exe",
    r"C:\Program Files\MetaTrader 5 EXNESS\terminal64.exe",
    r"C:\Program Files (x86)\MetaTrader 5\terminal64.exe",
]

MODELS = {           # tester "Model" values
    "real": 4,       # every tick based on real ticks - the one to use
    "tick": 0,       # every tick
    "ohlc": 1,       # 1 minute OHLC
    "open": 2,       # open prices only
    "math": 3,       # math calculations
}


class Tee:
    """
    Everything printed also goes to run.log in the results folder. A week-long
    batch scrolls its console away, and the one line that explains a failure is
    always the one you lost.
    """
    def __init__(self, path):
        self.term = sys.stdout
        self.fh = open(path, "a", encoding="utf-8", errors="replace")
        self.fh.write(f"\n{'='*70}\n{_dt.datetime.now():%Y-%m-%d %H:%M:%S}  "
                      f"{' '.join(sys.argv)}\n{'='*70}\n")

    def write(self, s):
        self.term.write(s)
        self.fh.write(s)
        self.fh.flush()

    def flush(self):
        self.term.flush()
        self.fh.flush()


def check_writable(path, label):
    """A VPS terminal under Program Files often cannot write where you assume."""
    try:
        os.makedirs(path, exist_ok=True)
        probe = os.path.join(path, ".write_probe")
        with open(probe, "w") as fh:
            fh.write("x")
        os.remove(probe)
        return True, ""
    except OSError as exc:
        return False, f"{label} is NOT writable: {path}\n    {exc}"


def sweep_for_reports(data_dir, terminal_exe):
    """
    Every .htm anywhere MT5 might have put one. Printed when a run produces no
    report, so 'it wrote nothing' and 'it wrote somewhere else' are told apart
    without you hunting by hand.
    """
    roots = [data_dir, os.path.dirname(terminal_exe), os.getcwd()]
    found = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            depth = dirpath[len(root):].count(os.sep)
            if depth > 3:
                dirnames[:] = []
                continue
            for fn in filenames:
                if fn.lower().endswith((".htm", ".html")):
                    full = os.path.join(dirpath, fn)
                    try:
                        found.append((os.path.getmtime(full), full))
                    except OSError:
                        pass
    found.sort(reverse=True)
    return found[:15]


def tail_mt5_logs(data_dir, since, lines=25):
    """
    MT5 keeps its own journal, and it states plainly why a tester run did not
    start - missing history, a symbol it does not know, an expert it cannot
    load, a login it needs. Nothing this script can infer beats reading it.

        <data>\\logs\\YYYYMMDD.log          the terminal
        <data>\\Tester\\logs\\YYYYMMDD.log  the tester
    """
    out = []
    for sub, label in ((("logs",), "terminal"), (("Tester", "logs"), "tester")):
        d = os.path.join(data_dir, *sub)
        if not os.path.isdir(d):
            out.append((label, d, ["(no such folder)"]))
            continue
        logs = [os.path.join(d, f) for f in os.listdir(d) if f.lower().endswith(".log")]
        if not logs:
            out.append((label, d, ["(no .log files)"]))
            continue
        newest = max(logs, key=os.path.getmtime)
        try:
            raw = open(newest, "rb").read()
            txt = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") \
                  else raw.decode("utf-8", errors="replace")
            rows = [r.rstrip() for r in txt.splitlines() if r.strip()]
            out.append((label, newest, rows[-lines:]))
        except OSError as exc:
            out.append((label, newest, [f"(could not read: {exc})"]))
    return out


def find_terminal(given):
    if given:
        if os.path.isfile(given):
            return given
        sys.exit(f"terminal not found at {given}")
    for p in TERMINAL_GUESSES:
        if os.path.isfile(p):
            return p
    sys.exit("Could not find terminal64.exe - pass --terminal "
             r'"C:\Program Files\MetaTrader 5\terminal64.exe"')


def running_terminal_paths():
    """
    Full paths of every running terminal64.exe.

    The PATH is what matters, not the image name. The setup deliberately has
    TWO terminals: your live one, which stays open, and the portable tester,
    which must be closed. Matching on the name alone flags the live one and
    makes the check useless - which is how it came to be bypassed with
    --allow-running everywhere, taking the real check down with it.
    """
    ps = ("Get-CimInstance Win32_Process -Filter \"Name='terminal64.exe'\" "
          "| ForEach-Object { $_.ExecutablePath }")
    for cmd in (["powershell", "-NoProfile", "-Command", ps],
                ["wmic", "process", "where", "name='terminal64.exe'",
                 "get", "ExecutablePath"]):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
        except Exception:
            continue
        paths = [l.strip() for l in out.splitlines()
                 if l.strip().lower().endswith("terminal64.exe")]
        if paths:
            return paths
    return []


def tester_already_running(terminal_exe):
    """
    Is a terminal running FROM THE TESTER PATH? That one hands the /config: off
    to the open instance and exits in seconds, leaving no report - which looks
    exactly like a missing EA or a bad expert name, and is neither.

    Returns (blocked, note).
    """
    #  These are always Windows paths, and this script may be reasoned about on
    #  another OS, where os.path.normcase is a no-op and would silently stop
    #  matching on case. Normalise explicitly instead of relying on it.
    def norm(p):
        return p.strip().strip('"').replace("/", "\\").lower()
    want = norm(terminal_exe)
    paths = running_terminal_paths()
    if not paths:
        #  Could not read process paths (not Windows, or both tools missing).
        #  Fall back to the image-name check, and SAY it is a guess.
        try:
            out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq terminal64.exe"],
                                 capture_output=True, text=True, timeout=30).stdout
            if "terminal64.exe" in out:
                return True, ("could not read process paths, so this may be your LIVE "
                              "terminal rather than the tester - pass --allow-running "
                              "if you know the tester itself is closed")
        except Exception:
            pass
        return False, ""
    for p in paths:
        if norm(p) == want:
            return True, "that is the tester terminal itself"
    return False, ""


def find_data_dir(given):
    """
    The tester reads its .set from <data>\\MQL5\\Profiles\\Tester.
    The data folder is usually under %APPDATA%\\MetaQuotes\\Terminal\\<hash>.
    """
    if given:
        if os.path.isdir(given):
            return given
        sys.exit(f"data folder not found at {given}")

    root = os.path.join(os.environ.get("APPDATA", ""), "MetaQuotes", "Terminal")
    if not os.path.isdir(root):
        sys.exit("Could not find the MetaQuotes data folder - pass --data-dir. "
                 "In MT5: File > Open Data Folder, and use that path.")

    candidates = [os.path.join(root, d) for d in os.listdir(root)
                  if os.path.isdir(os.path.join(root, d, "MQL5", "Profiles", "Tester"))]
    if not candidates:
        sys.exit("No terminal data folder with MQL5\\Profiles\\Tester - pass --data-dir.")
    if len(candidates) > 1:
        # the most recently used one is almost always the right one
        candidates.sort(key=os.path.getmtime, reverse=True)
        print(f"  ! {len(candidates)} data folders found, using the most recent:")
        print(f"    {candidates[0]}")
    return candidates[0]


# --------------------------------------------------------------------------
# running one backtest
# --------------------------------------------------------------------------

def normalise_expert(expert):
    """
    MT5 resolves Expert= relative to MQL5\\Experts and prepends that folder
    itself, so "Experts\\Foo.ex5" becomes "Experts\\Experts\\Foo.ex5" and the
    tester exits with:
        Tester  Experts\\Experts\\Foo.ex5 not found
        shutdown with -1000012355 (tester EX5 not found)
    Accept either form and send the one MT5 wants.
    """
    e = expert.replace("/", "\\").lstrip("\\")
    low = e.lower()
    for prefix in ("mql5\\experts\\", "experts\\"):
        if low.startswith(prefix):
            e = e[len(prefix):]
            low = e.lower()
    if not low.endswith(".ex5"):
        e += ".ex5"
    return e


def write_ini(path, args, set_name, report_path):
    """
    One .ini per run. ExpertParameters is a FILE NAME only - the terminal
    looks for it in MQL5\\Profiles\\Tester, which is why we copy the .set there.
    """
    ini = configparser.RawConfigParser()
    ini.optionxform = str                     # keep the key casing MT5 expects
    ini["Tester"] = {
        "Expert":            normalise_expert(args.expert),
        "ExpertParameters":  set_name,
        "Symbol":            args.symbol,
        "Period":            args.period,
        "Model":             str(MODELS[args.model]),
        "FromDate":          args.date_from,
        "ToDate":            args.date_to,
        "Deposit":           str(args.deposit),
        "Currency":          args.currency,
        "Leverage":          str(args.leverage),
        "Optimization":      "0",
        "ForwardMode":       "0",
        "ExecutionMode":     "0",
        "Visual":            "0",
        "Report":            report_path,   # bare name - see find_written_report()
        "ReplaceReport":     "1",
        "ShutdownTerminal":  "1",              # close when the run finishes
    }
    if args.login:
        ini["Tester"]["Login"] = args.login
    with open(path, "w", encoding="utf-8") as fh:
        ini.write(fh, space_around_delimiters=False)


def agent_files_dirs(data_dir):
    """
    Where a tester agent keeps the files an EA writes. There are two layouts
    and the one that matters is NOT under the terminal folder:

        %APPDATA%\\MetaQuotes\\Tester\\<hash>\\Agent-127.0.0.1-3000\\MQL5\\Files   <- usual
        <data>\\Tester\\Agent-127.0.0.1-3000\\MQL5\\Files                        <- portable

    Also the shared sandbox, which FILE_COMMON writes land in.
    """
    roots = []
    appdata = os.environ.get("APPDATA", "")
    if appdata:
        roots.append(os.path.join(appdata, "MetaQuotes", "Tester"))
        roots.append(os.path.join(appdata, "MetaQuotes", "Terminal", "Common", "Files"))
    roots.append(os.path.join(data_dir, "Tester"))
    roots.append(os.path.join(os.path.dirname(data_dir), "Common", "Files"))

    out = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        if root.lower().endswith(os.path.join("common", "files").lower()):
            out.append(root)
            continue
        # walk shallowly looking for Agent-*\MQL5\Files
        for dirpath, dirnames, _ in os.walk(root):
            if dirpath[len(root):].count(os.sep) > 5:
                dirnames[:] = []
                continue
            if os.path.basename(dirpath).lower() == "files" and "mql5" in dirpath.lower():
                out.append(dirpath)
    return out


def collect_agent_logs(data_dir, out_dir, set_name):
    """
    The EA writes its CSV / JSONL into the tester AGENT sandbox, and the agent
    number changes between runs, so the files are easy to lose. Copy whatever
    this run produced next to its report - that is what ema_report.py reads.
    """
    logs_dir = os.path.join(out_dir, "logs")
    found = []
    for files_dir in agent_files_dirs(data_dir):
        try:
            names = os.listdir(files_dir)
        except OSError:
            continue
        for fn in names:
            if not fn.lower().endswith((".csv", ".jsonl")):
                continue
            if set_name not in fn:        # each set has its own InpCsvPrefix
                continue
            os.makedirs(logs_dir, exist_ok=True)
            try:
                shutil.copyfile(os.path.join(files_dir, fn), os.path.join(logs_dir, fn))
                found.append(fn)
            except OSError:
                pass
    return found


def find_written_report(stem, data_dir, terminal_exe, out_dir, since):
    """
    Some MT5 builds ignore an absolute path in Report= and drop the file in
    their own folder instead. Look everywhere it could plausibly be and only
    accept a file written during THIS run.
    """
    places = [
        out_dir,
        data_dir,
        os.path.dirname(terminal_exe),
        os.path.join(data_dir, "MQL5", "Files"),
        os.path.join(data_dir, "Tester"),
        os.getcwd(),
    ]
    for d in places:
        if not os.path.isdir(d):
            continue
        for ext in (".htm", ".html"):
            cand = os.path.join(d, stem + ext)
            if os.path.isfile(cand) and os.path.getmtime(cand) >= since - 5:
                return cand
    return None


def run_one(args, terminal, tester_dir, set_file, out_dir):
    name = os.path.splitext(os.path.basename(set_file))[0]
    stem = f"report_{name}"
    report = os.path.join(out_dir, stem)                  # MT5 appends .htm
    ini = os.path.join(out_dir, f"{name}.ini")

    if args.skip_done:
        for ext in (".htm", ".html"):
            if os.path.isfile(report + ext):
                print(f"  {name} already done, skipping")
                return report + ext

    # the terminal only reads .set files from its own Profiles\Tester folder
    staged = os.path.join(tester_dir, os.path.basename(set_file))
    shutil.copyfile(set_file, staged)

    # bare name, because an absolute path here is ignored on some builds
    write_ini(ini, args, os.path.basename(set_file), stem)

    print(f"  running {name} ...", end="", flush=True)
    t0 = time.time()
    try:
        cmd = [terminal, f"/config:{ini}"]
        if args.portable:
            # A portable terminal keeps its data folder BESIDE terminal64.exe.
            # Without this flag the same exe writes to %APPDATA%\MetaQuotes\
            # Terminal\<hash> instead, so the .ini we just staged into
            # --data-dir\MQL5\Profiles\Tester is in a folder the terminal
            # never reads, and no report is ever produced.
            cmd.append("/portable")
        subprocess.run(cmd, check=False, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        print(f" TIMED OUT after {args.timeout}s")
        return None
    dt = time.time() - t0

    found = find_written_report(stem, args._data_dir, terminal, out_dir, t0)
    if found:
        dest = report + os.path.splitext(found)[1]
        if os.path.abspath(found) != os.path.abspath(dest):
            shutil.move(found, dest)                      # MT5 put it elsewhere
        msg = f" done in {dt/60:.1f} min"
        if not args.no_logs:
            logs = collect_agent_logs(args._data_dir, out_dir, name)
            msg += f", {len(logs)} log file(s)" if logs else ", no EA logs found"
        print(msg)
        return dest

    print(f" finished in {dt/60:.1f} min but NO REPORT was written")
    # is the problem permissions rather than placement?
    for path, label in ((out_dir, "results folder"),
                        (args._data_dir, "MT5 data folder"),
                        (os.path.dirname(terminal), "MT5 install folder")):
        ok, why = check_writable(path, label)
        if not ok:
            print("     " + why.replace("\n", "\n     "))
    if dt < 30:
        print("     it exited almost immediately. Check MT5's log line above - if it")
        print("     says 'EX5 not found', the expert name is wrong; if there is no")
        print("     tester line at all, MT5 was already running.")
    else:
        print("     the test DID run, so the expert path is fine - MT5 just did not")
        print("     write the report. Run with --debug-report to see where it looked.")
    # MT5's own journal says why. Always show it on a failure - this is the
    # single most useful thing on the screen when a run produces nothing.
    print("     ---- MT5's own log, last lines ----")
    for label, path, rows in tail_mt5_logs(args._data_dir, t0):
        print(f"     [{label}] {path}")
        for r in rows:
            print("       " + r[:160])
    print("     -----------------------------------")

    if args.debug_report:
        print("     any .htm MT5 has written recently, newest first:")
        hits = sweep_for_reports(args._data_dir, terminal)
        if hits:
            for mt, full in hits:
                age = (time.time() - mt) / 60.0
                mark = "  <-- written during THIS run" if mt >= t0 - 5 else ""
                print(f"       {_dt.datetime.fromtimestamp(mt):%H:%M:%S} "
                      f"({age:5.1f} min ago)  {full}{mark}")
        else:
            print("       none found anywhere - MT5 is not writing a report at all.")
            print("       Check Tools > Options > Expert Advisors, and whether the")
            print("       terminal can write to its own folder (VPS, Program Files,")
            print("       antivirus). Try running this script as Administrator.")
        print("     searched for the exact name in:")
        for d in (out_dir, args._data_dir, os.path.dirname(terminal),
                  os.path.join(args._data_dir, "MQL5", "Files"), os.getcwd()):
            print(f"       {d}")
            if os.path.isdir(d):
                htm = [f for f in os.listdir(d) if f.lower().endswith((".htm", ".html"))]
                print(f"         -> {htm[:8] if htm else 'no .htm files'}")
    return None


# --------------------------------------------------------------------------
# reading the reports back
# --------------------------------------------------------------------------

def parse_report(path):
    raw = open(path, "rb").read()
    # MT5 writes UTF-16LE with a BOM, but a report that has been converted or
    # re-saved may be UTF-8. Guessing wrong yields mojibake that parses to zeros
    # rather than raising, so sniff it rather than relying on decode() to fail.
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        s = raw.decode("utf-16")
    elif b"\x00" in raw[:200]:                 # UTF-16 without a BOM
        s = raw.decode("utf-16", errors="replace")
    else:
        s = raw.decode("utf-8", errors="replace")

    txt = html_mod.unescape(re.sub(r"<[^>]+>", "|", s))
    rows = [[c.strip() for c in line.split("|") if c.strip()]
            for line in txt.split("\n")]
    rows = [r for r in rows if r]

    # "Label:" on one row, its value on the next
    res = {}
    for i, r in enumerate(rows):
        if len(r) == 1 and r[0].endswith(":") and i + 1 < len(rows) and len(rows[i + 1]) == 1:
            res[r[0][:-1]] = rows[i + 1][0]

    inputs = {}
    for r in rows:
        if len(r) == 1 and "=" in r[0] and r[0].startswith("Inp"):
            k, v = r[0].split("=", 1)
            inputs[k] = v

    def num(key):
        try:
            return float(str(res.get(key, "0")).replace(" ", "").split("(")[0])
        except ValueError:
            return 0.0

    period = ""
    for i, r in enumerate(rows):
        if r[0] == "Period:" and i + 1 < len(rows):
            period = rows[i + 1][0]
            break

    filters_on = [k.replace("InpQf", "") for k in
                  ("InpQfTrend", "InpQfStruct", "InpQfEma50", "InpQfVwap",
                   "InpQfBias", "InpQfVolume", "InpQfCooldown")
                  if inputs.get(k) == "true"]
    if inputs.get("InpEnableQFilter") != "true":
        filters_on = []

    return {
        "run": os.path.splitext(os.path.basename(path))[0].replace("report_", ""),
        "period": period,
        "filters": ",".join(filters_on) or "none",
        "trades": int(num("Total Trades")),
        "net": num("Total Net Profit"),
        "pf": num("Profit Factor"),
        "payoff": num("Expected Payoff"),
        "dd": res.get("Balance Drawdown Maximal", ""),
        "dd_pct": (lambda m: float(m.group(1)) if m else 0.0)(
            re.search(r"\(([\d.]+)%\)", res.get("Balance Drawdown Maximal", ""))),
        "win_pct": (lambda m: float(m.group(1)) if m else 0.0)(
            re.search(r"\(([\d.]+)%\)", res.get("Profit Trades (% of total)", ""))),
        "avg_win": num("Average profit trade"),
        "avg_loss": num("Average loss trade"),
        "sharpe": num("Sharpe Ratio"),
    }


def compare(reports, out_dir, baseline_hint="baseline"):
    rows = []
    for r in sorted(reports):
        try:
            rows.append(parse_report(r))
        except Exception as exc:
            print(f"  ! could not parse {os.path.basename(r)}: {exc}")
    if not rows:
        return

    # baseline first if we can spot it, then by net
    rows.sort(key=lambda x: (baseline_hint not in x["run"].lower(), -x["net"]))

    hdr = f"{'run':26s}{'filter':22s}{'trades':>7}{'net':>10}{'PF':>6}{'DD%':>7}{'win%':>6}{'avgW':>8}{'avgL':>8}"
    print("\n" + hdr)
    print("-" * len(hdr))
    base = next((r for r in rows if baseline_hint in r["run"].lower()), None)
    for r in rows:
        mark = ""
        if base and r is not base:
            mark = "  <-- better" if (r["pf"] > base["pf"] and r["net"] > base["net"]) else ""
        print(f"{r['run'][:26]:26s}{r['filters'][:22]:22s}{r['trades']:>7}"
              f"{r['net']:>10.2f}{r['pf']:>6.2f}{r['dd_pct']:>7.2f}"
              f"{r['win_pct']:>6.1f}{r['avg_win']:>8.2f}{r['avg_loss']:>8.2f}{mark}")

    csv_path = os.path.join(out_dir, "comparison.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"\nWrote {csv_path}")

    if base:
        print(f"\nBaseline: {base['trades']} trades, net {base['net']:+.2f}, PF {base['pf']:.2f}")
        print("A variant is only interesting if PF rises AND it did not get there")
        print("by removing most of the trades - check the trade count alongside it.")


# --------------------------------------------------------------------------

def merge_all(root="."):
    """Every results_* folder in one table, so the timeframes can be compared."""
    rows = []
    for d in sorted(glob.glob(os.path.join(root, "results*"))):
        if not os.path.isdir(d):
            continue
        for r in sorted(glob.glob(os.path.join(d, "report_*.htm*"))):
            try:
                row = parse_report(r)
                row["folder"] = os.path.basename(d)
                rows.append(row)
            except Exception:
                pass
    if not rows:
        print("No reports found in any results* folder")
        return
    rows.sort(key=lambda x: -x["net"])
    hdr = f"{'folder':22s}{'run':26s}{'trades':>7}{'net':>10}{'PF':>6}{'DD%':>7}"
    print("\n" + hdr)
    print("-" * len(hdr))
    for r in rows[:40]:
        print(f"{r['folder'][:22]:22s}{r['run'][:26]:26s}{r['trades']:>7}"
              f"{r['net']:>10.2f}{r['pf']:>6.2f}{r['dd_pct']:>7.2f}")
    if len(rows) > 40:
        print(f"... {len(rows)-40} more, all of them in all_results.csv")
    out = os.path.join(root, "all_results.csv")
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"\nWrote {out}  ({len(rows)} runs)")


def main():
    ap = argparse.ArgumentParser(description="Batch-run MT5 backtests over a folder of .set files.")
    ap.add_argument("--sets", default="sets", help="folder of .set files (default: sets)")
    ap.add_argument("--out", default="results", help="where reports and the comparison land")
    ap.add_argument("--expert", default="SniperEntry_Strict_SessionFilter_Telegram_v1.30.ex5",
                    help="compiled EA file name, relative to MQL5\\Experts. A leading "
                         "Experts\\ is stripped automatically - MT5 adds it itself, and "
                         "passing it twice makes the tester exit with 'EX5 not found'.")
    ap.add_argument("--symbol", default="XAUUSD")
    ap.add_argument("--period", default="M15", help="M1 M5 M15 M30 H1 ...")
    ap.add_argument("--from", dest="date_from", default="2026.06.01")
    ap.add_argument("--to", dest="date_to", default="2026.09.18")
    ap.add_argument("--model", default="real", choices=list(MODELS),
                    help="real = every tick based on real ticks (default)")
    ap.add_argument("--deposit", type=int, default=5000)
    ap.add_argument("--currency", default="USD")
    ap.add_argument("--leverage", type=int, default=100)
    ap.add_argument("--login", default="", help="account number, if the terminal has several")
    ap.add_argument("--terminal", default="", help="full path to terminal64.exe")
    ap.add_argument("--data-dir", default="", help="MT5 data folder (File > Open Data Folder)")
    ap.add_argument("--portable", action="store_true",
                    help="launch the terminal with /portable. REQUIRED when the tester "
                         "MT5 was installed outside the default path and you run it from "
                         "a /portable shortcut - its data folder is then beside "
                         "terminal64.exe, and --data-dir must point there too.")
    ap.add_argument("--timeout", type=int, default=0,
                    help="seconds per run. 0 = pick from the timeframe (M1/M3 8h, M5 6h, "
                         "M15+ 3h). A 2h default silently killed long M3 runs.")
    ap.add_argument("--compare-only", action="store_true",
                    help="skip running; just re-parse the reports already in --out")
    ap.add_argument("--debug-report", action="store_true",
                    help="when no report appears, list every folder searched and the "
                         ".htm files in each")
    ap.add_argument("--merge-all", action="store_true",
                    help="build one table from EVERY results* folder here, and write "
                         "all_results.csv. Run this at the end.")
    ap.add_argument("--allow-running", action="store_true",
                    help="start even if the TESTER terminal is already open. Normally "
                         "refused, because that launch hands off to the open instance "
                         "and produces no report. Your live terminal never triggers "
                         "the check - it compares executable paths, not image names.")
    ap.add_argument("--no-logs", action="store_true",
                    help="do not collect the EA's own CSV/JSONL logs from the tester agents")
    ap.add_argument("--skip-done", action="store_true",
                    help="skip any set whose report already exists in --out. This is what "
                         "makes a long batch resumable: rerun the same command after a crash "
                         "or a reboot and it carries on instead of starting over.")
    args = ap.parse_args()

    if args.timeout <= 0:                       # scale it to the timeframe
        args.timeout = {"M1": 28800, "M2": 28800, "M3": 28800,
                        "M4": 21600, "M5": 21600, "M6": 21600,
                        "M10": 10800, "M15": 10800, "M20": 10800, "M30": 10800}.get(
                            args.period.upper(), 10800)

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    sys.stdout = Tee(os.path.join(out_dir, "run.log"))

    if args.merge_all:
        merge_all()
        return

    if args.compare_only:
        reports = glob.glob(os.path.join(out_dir, "report_*.htm*"))
        if not reports:
            sys.exit(f"No reports in {out_dir}")
        print(f"Comparing {len(reports)} existing reports")
        compare(reports, out_dir)
        return

    sets = sorted(glob.glob(os.path.join(args.sets, "*.set")))
    if not sets:
        sys.exit(f"No .set files in {args.sets}")

    # MT5 parses the /config: argument itself and breaks it at the first space,
    # so a path containing a space or a bracket makes the terminal open, find
    # nothing, and exit in seconds - leaving .ini files and no reports.
    here = os.path.abspath(".")
    bad = [c for c in " ()" if c in here or c in os.path.abspath(args.out)]
    if bad:
        sys.exit("This folder's path contains " + " and ".join(repr(c) for c in bad) + ":\n"
                 f"    {here}\n"
                 "MetaTrader cannot read a /config: path with spaces or brackets - it would\n"
                 "open, find nothing and quit, writing .ini files but no reports.\n"
                 "Move the whole folder somewhere plain, for example C:\\ema, and rerun.")

    terminal = find_terminal(args.terminal)

    #  After find_terminal, because the check needs the resolved PATH - the
    #  point is to tell the tester terminal apart from your live one.
    blocked, note = tester_already_running(terminal)
    if blocked and not args.allow_running:
        sys.exit(f"The tester terminal is already running:\n"
                 f"    {terminal}\n"
                 f"    ({note})\n\n"
                 "Close it and rerun. A second launch of the SAME terminal hands the\n"
                 "/config: off to the open instance and exits in seconds, so every run\n"
                 "'finishes' with no report - which reads like a missing EA or a wrong\n"
                 "expert name, and is neither.\n\n"
                 "If a run was interrupted, MT5 can be left open in the background:\n"
                 "    taskkill /IM terminal64.exe /F      (closes ALL terminals, live too)\n"
                 "or close just the tester window.\n\n"
                 "Your LIVE terminal does not trigger this - the check compares paths.")
    data_dir = find_data_dir(args.data_dir)
    tester_dir = os.path.join(data_dir, "MQL5", "Profiles", "Tester")
    os.makedirs(tester_dir, exist_ok=True)

    args._data_dir = data_dir

    # pre-flight: say NOW if something cannot be written, not after a night of runs
    problems = []
    for path, label in ((out_dir, "results folder"),
                        (tester_dir, "MQL5\\Profiles\\Tester"),
                        (os.path.dirname(terminal), "MT5 install folder")):
        ok, why = check_writable(path, label)
        if not ok:
            problems.append(why)
    if problems:
        print("\n!! write permission problems:")
        for w in problems:
            print("   " + w.replace("\n", "\n   "))
        print("   MT5 may be unable to save its report. Try running this script as")
        print("   Administrator, or move the folder out of Program Files.\n")

    print(f"Terminal : {terminal}")
    print(f"Data dir : {data_dir}")
    print(f"Expert   : {normalise_expert(args.expert)}   (as given: {args.expert})")
    print(f"Run      : {args.symbol} {args.period} {args.date_from} - {args.date_to}, "
          f"model {args.model}, deposit {args.deposit}")
    print(f"Sets     : {len(sets)}\n")
    print("MT5 will open and close once per run. Do not use the terminal meanwhile.\n")

    started = datetime.now()
    reports = []
    for i, s in enumerate(sets, 1):
        print(f"[{i}/{len(sets)}]", end=" ")
        r = run_one(args, terminal, tester_dir, s, out_dir)
        if r:
            reports.append(r)

    print(f"\n{len(reports)} of {len(sets)} runs produced a report "
          f"in {(datetime.now()-started).total_seconds()/60:.0f} min")
    compare(reports, out_dir)


if __name__ == "__main__":
    main()
