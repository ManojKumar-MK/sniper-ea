#!/usr/bin/env python3
"""
ema_report.py - turn the EA's files into a dashboard.

Reads three things the EA writes and needs no changes to it:

  *.jsonl / *.csv     every event, for the history
  *_state.txt         rewritten after every event: the open trade, today's
                      tally and the prop-guard state - this is the "now" view
  DAY_SUMMARY rows    per-day roll-ups already computed by the EA

Usage
    python ema_report.py logs/*.jsonl                  # text report in the terminal
    python ema_report.py logs/*.jsonl --html out.html  # one self-contained HTML file
    python ema_report.py logs/*.jsonl --serve 8800     # live dashboard in a browser

The state file is picked up automatically from the same folder as the logs.
Point --state somewhere else if it lives apart.

Reading it from your own machine while the EA runs on a VPS:

    On the VPS:   python ema_report.py "C:/.../MQL5/Files/*.jsonl" --serve 8800
    On your PC:   ssh -N -L 8800:localhost:8800 user@your-vps
    Then open:    http://localhost:8800

The tunnel means nothing is exposed to the internet and you do not have to log
in to look. To reach it without a tunnel, use --host 0.0.0.0 --token SOMETHING
and open http://vps-ip:8800/?t=SOMETHING - but a tunnel is the safer habit.

--anon strips balances, equity and cash P/L, leaving R-multiples and
percentages, so the page can be published somewhere less private.

Read-only by design: it opens the EA's files and never writes to them, so
nothing here can place, change or close a trade.

Standard library only - no pandas, no installs.
"""

import argparse
import csv
import glob
import html as html_mod
import io
import json
import os
import re
import sys
import time
from collections import defaultdict, OrderedDict
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs, quote

# --------------------------------------------------------------------------
# loading
# --------------------------------------------------------------------------

EXIT_PREFIX = "EXIT"
ENTRY_EVENTS = ("ENTRY", "ADOPTED")

# The EA logs a trade's end twice for any close it tags itself (flip, news,
# weekend, guard): once from ClosePositionTagged with profit hardcoded to 0,
# then again from AuditAndLogExit with the real money. The second one is
# usually EXIT_OTHER, because the audit reads the deal reason rather than the
# tag. So: the specific tag says WHY, the audit row says HOW MUCH, and a trade
# needs both. See build_trades.
VAGUE_EXITS = {"EXIT_OTHER"}


def load_jsonl(path):
    """Yield one dict per line, skipping anything malformed."""
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                print(f"  ! {os.path.basename(path)}:{n} unparseable, skipped",
                      file=sys.stderr)


def load_csv(path):
    """The CSV carries the same events in flat columns."""
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as fh:
        for row in csv.DictReader(fh):
            yield csv_to_event(row)


def csv_to_event(row):
    """Reshape a CSV row into the nested form the rest of the script expects."""
    def f(key, default=0.0):
        try:
            return float(row.get(key) or 0)
        except ValueError:
            return default

    flags = {}
    for part in (row.get("qf_flags") or "").split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            flags[k.lower()] = int(v) if v in ("0", "1") else v

    # the CSV keeps this in its own column; the JSONL puts it inside "filters"
    qf_on = (row.get("qfilter_on") or "").strip()
    if qf_on in ("0", "1"):
        flags["enabled"] = (qf_on == "1")

    return {
        "event": row.get("event", ""),
        "t_ist": row.get("time_ist", ""),
        "t_srv": row.get("time_server", ""),
        "sym": row.get("symbol", ""),
        "trade": row.get("trade_id", ""),
        "dir": row.get("direction", ""),
        "mode": row.get("exit_mode", ""),
        "session": row.get("ist_session", ""),
        "logic": {
            "adx": f("adx"), "rsi": f("rsi"), "rsi_m5": f("rsi_m5"),
            "atr": f("atr"), "macd": f("macd_main"), "macd_sig": f("macd_signal"),
            "vwap": f("vwap"), "close": f("close"),
            "vol": f("volume"), "vol_avg": f("vol_avg"),
            "bull_pct": f("bull_pct"), "bear_pct": f("bear_pct"),
            "spread": f("spread_pts"),
            "ema_gap_atr": f("ema21_50_gap_atr"),
        },
        "filters": flags,
        "result": {"r_real": f("r_realized"), "profit": f("profit"),
                   "mfe_r": (float(row["mfe_r"]) if (row.get("mfe_r") or "").strip() else None),
                   "mae_r": (float(row["mae_r"]) if (row.get("mae_r") or "").strip() else None)},
        "acct": {"balance": f("balance"), "equity": f("equity")},
    }


def collect(paths, as_csv, quiet=False):
    events, seen = [], []
    for pattern in paths:
        for path in sorted(glob.glob(pattern)) or [pattern]:
            if not os.path.exists(path):
                if not quiet:
                    print(f"  ! {path} not found, skipped", file=sys.stderr)
                continue
            if path.lower().endswith("_state.txt"):
                continue                       # not an event log
            loader = load_csv if (as_csv or path.lower().endswith(".csv")) else load_jsonl
            n0 = len(events)
            events.extend(loader(path))
            seen.append(path)
            if not quiet:
                print(f"  read {len(events) - n0:>6} events from {os.path.basename(path)}")
    return events, seen


# --------------------------------------------------------------------------
# the state file - what is happening right now
# --------------------------------------------------------------------------

IST_HOURS = 5.5          # India is GMT+5:30, and has no DST


def retime(events, offset, day_start=0, day_end=16):
    """
    Recompute every IST stamp from the broker's own clock.

    The EA converts before it writes, using whatever GMT offset it resolved. If
    that offset was wrong, every t_ist in the log is wrong by a constant - and
    baked in, because the EA only ever writes the converted value once.

    Doing the conversion here instead means a wrong offset is fixable after the
    fact, across history, without recompiling anything or re-running a backtest.
    t_srv is the broker's own timestamp and is never adjusted, so it stays the
    source of truth.

    The DAY/EVENING label is re-derived too. It is a function of the IST hour, so
    leaving the EA's label in place after shifting the times would put trades in
    the wrong session bucket - a subtler wrong answer than a wrong clock.
    """
    if offset is None:
        return 0, 0
    shift = timedelta(hours=IST_HOURS - offset)
    moved = relabelled = 0
    for ev in events:
        t = parse_ts(ev.get("t_srv") or "")
        if not t:
            continue                       # no broker stamp: leave the EA's value alone
        ist = t + shift
        if ev.get("t_ist") != ist.strftime("%Y.%m.%d %H:%M:%S"):
            moved += 1
        ev["t_ist"] = ist.strftime("%Y.%m.%d %H:%M:%S")
        if ev.get("session"):
            h = ist.hour
            day = True if day_start == day_end else (
                day_start <= h < day_end if day_start < day_end
                else (h >= day_start or h < day_end))
            lab = "DAY" if day else "EVENING"
            if ev["session"] != lab:
                relabelled += 1
            ev["session"] = lab
    return moved, relabelled


def retime_state(st, offset):
    """The Live card's entry stamp, converted the same way."""
    if offset is None:
        return
    t = parse_ts((st.get("entrySrvFull") or "").strip())
    if not t:
        return
    st["entryIstFull"] = (t + timedelta(hours=IST_HOURS - offset)).strftime("%Y.%m.%d %H:%M")
    st["entryIst"] = st["entryIstFull"][-5:]
    st["gmtOffset"] = f"{offset:.1f}"


def find_states(log_paths, explicit):
    """Locate *_state.txt beside the logs, unless told exactly where to look."""
    if explicit:
        out = []
        for pattern in explicit:
            out.extend(sorted(glob.glob(pattern)) or
                       ([pattern] if os.path.exists(pattern) else []))
        return out
    # Derive the state pattern from the LOG pattern, because the EA builds both
    # from the same InpCsvPrefix: "<prefix>_<symbol>_<tf>" plus .jsonl / .csv /
    # _state.txt. Two instances on one symbol (a trading one and a signals-only
    # one) share a folder, so globbing every *_state.txt there would put both
    # cards on the Live tab even when the logs were scoped to one of them.
    found, seen = [], set()
    for pattern in log_paths:
        d = os.path.dirname(pattern) or "."
        base = os.path.basename(pattern)
        stem = base.rsplit(".", 1)[0] if "." in base else base
        for cand in (os.path.join(d, stem + "_state.txt"),
                     os.path.join(d, "*_state.txt")):
            hits = sorted(glob.glob(cand))
            if hits:
                for h in hits:
                    if h not in seen:
                        seen.add(h)
                        found.append(h)
                break              # the derived pattern wins; the wide one is a fallback
    return found


def load_state(path):
    """
    Parse one _state.txt. Keys are flat 'k=v' lines; 'D|' rows are finished
    days and 'T|' rows are the trades closed today. Written after every event,
    so its mtime is a good proxy for "the EA was alive at".
    """
    st = {"_path": path, "_name": os.path.basename(path), "_days": [], "_today": []}
    try:
        st["_mtime"] = os.path.getmtime(path)
    except OSError:
        st["_mtime"] = 0.0

    def fl(s, d=0.0):
        try:
            return float(s)
        except (TypeError, ValueError):
            return d

    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith("D|"):
                p = line.split("|")
                if len(p) >= 10:
                    st["_days"].append({
                        "day": int(fl(p[1])), "trades": int(fl(p[2])),
                        "wins": int(fl(p[3])), "losses": int(fl(p[4])),
                        "gp": fl(p[5]), "gl": fl(p[6]), "net": fl(p[7]),
                        "r": fl(p[8]), "pips": fl(p[9]),
                    })
            elif line.startswith("T|"):
                p = line.split("|")
                if len(p) >= 11:
                    st["_today"].append({
                        "t_ist": p[1], "x_ist": p[2], "dir": int(fl(p[3])),
                        "entry": fl(p[4]), "sl": fl(p[5]), "exit": fl(p[6]),
                        "pips": fl(p[7]), "r": fl(p[8]), "net": fl(p[9]),
                        "result": p[10],
                    })
            elif "=" in line:
                k, v = line.split("=", 1)
                st[k] = v
    return st


def sget(st, key, default=0.0):
    try:
        return float(st.get(key, default))
    except (TypeError, ValueError):
        return default


def sint(st, key, default=0):
    return int(sget(st, key, default))


def state_symbol(st):
    """'EMA_XAUUSD_M15_state.txt' -> 'XAUUSD M15'."""
    base = st["_name"]
    if base.lower().endswith("_state.txt"):
        base = base[:-len("_state.txt")]
    bits = base.split("_")
    return " ".join(bits[1:3]) if len(bits) >= 3 else base


def state_has_position(st):
    return sint(st, "posId") != 0 and sint(st, "dir") != 0


def ladder(st):
    """[(n, price, hit), ...] for TP1..TP5."""
    prices = (st.get("tpPrice") or "").split(",")
    hits = (st.get("tpHit") or "").split(",")
    out = []
    for i in range(5):
        try:
            px = float(prices[i])
        except (IndexError, ValueError):
            px = 0.0
        try:
            hit = hits[i].strip() == "1"
        except IndexError:
            hit = False
        out.append((i + 1, px, hit))
    return out


# --------------------------------------------------------------------------
# pairing entries with their exits
# --------------------------------------------------------------------------

def build_trades(events):
    """
    One record per completed trade. Events are grouped by trade id first, so a
    trade is assembled from everything it produced rather than from whichever
    exit row happened to arrive first:

      entry   ENTRY / ADOPTED  - the reasoning
      journey SL_MOVE, TPn_REACHED, TPn_PARTIAL, TPn_EXIT - how it was managed
      exit    EXIT_*           - the outcome

    A tagged close (flip, news, weekend, guard) writes EXIT_<tag> with profit
    0 and then an audit row with the real money, so the money is taken from
    the last exit row that carries a non-zero figure and the label from the
    most specific tag. Taking the first row, as an earlier version did, booked
    every one of those trades as a flat 0.00.
    """
    by_id = OrderedDict()
    for ev in events:
        tid = str(ev.get("trade", "") or "")
        if not tid or tid == "0":
            continue
        by_id.setdefault(tid, []).append(ev)

    trades, open_syms, orphan_exits = [], [], 0

    for tid, evs in by_id.items():
        entry = next((e for e in evs if e.get("event", "") in ENTRY_EVENTS), None)
        exits = [e for e in evs if e.get("event", "").startswith(EXIT_PREFIX)]

        if entry is None:
            orphan_exits += len(exits)
            continue
        if not exits:
            open_syms.append(entry.get("sym", ""))
            continue

        net = r = 0.0
        mfe = mae = None
        for ex in exits:                       # last non-zero wins
            res = ex.get("result", {}) or {}
            p, rr = float(res.get("profit") or 0), float(res.get("r_real") or 0)
            if p:
                net = p
            if rr:
                r = rr
            if res.get("mfe_r") is not None:
                mfe = float(res.get("mfe_r") or 0)
            if res.get("mae_r") is not None:
                mae = float(res.get("mae_r") or 0)

        tags = [e["event"] for e in exits]
        label = next((t for t in tags if t not in VAGUE_EXITS), tags[-1])

        reached, sl_moves = 0, 0
        peak_r, tp5_r = 0.0, None
        for e in evs:
            name = e.get("event", "")
            if name.startswith("SL_MOVE"):
                sl_moves += 1
                continue
            if not (name.startswith("TP") and "_" in name):
                continue
            try:
                n = int(name[2:name.index("_")])
            except ValueError:
                continue
            reached = max(reached, n)
            # r_target on a rung row is that rung's R, so the ladder tells us
            # how far the trade ran without us having to assume InpTP*_R
            rt = float((e.get("result", {}) or {}).get("r_target") or 0)
            peak_r = max(peak_r, rt)
            if n == 5 and rt:
                tp5_r = rt          # what closing at TP5 would have paid

        trades.append({
            "id": tid,
            "t_ist": entry.get("t_ist", ""),
            "x_ist": exits[-1].get("t_ist", ""),
            "sym": entry.get("sym", ""),
            "dir": entry.get("dir", ""),
            "mode": entry.get("mode", ""),
            "session": entry.get("session", ""),
            "exit": label,
            "adopted": entry.get("event") == "ADOPTED",
            "r": r,
            "net": net,
            "tp_reached": reached,
            "sl_moves": sl_moves,
            "peak_r": peak_r,
            "tp5_r": tp5_r,
            "mfe": mfe,
            "mae": mae,
            "mins": duration_mins(entry.get("t_ist", ""), exits[-1].get("t_ist", "")),
            "logic": entry.get("logic", {}) or {},
            "filters": entry.get("filters", {}) or {},
            "acct": exits[-1].get("acct", {}) or {},
        })

    return trades, open_syms, orphan_exits


def collect_skips(events):
    """
    The EMA crosses the EA refused. Each carries the same logic and filters an
    ENTRY does, plus the reason - so these can be compared directly against the
    trades that got through. Present only when InpLogSkips is on.
    """
    out = []
    for ev in events:
        if ev.get("event") != "SKIP":
            continue
        out.append({
            "t_ist": ev.get("t_ist", ""),
            "sym": ev.get("sym", ""),
            "dir": ev.get("skip_dir", "") or ev.get("dir", ""),
            "session": ev.get("session", ""),
            "reason": (ev.get("note", "") or "unknown").strip(),
            "logic": ev.get("logic", {}) or {},
            "filters": ev.get("filters", {}) or {},
        })
    return out


def skip_family(reason):
    """Collapse the parameterised reasons so 'spread 41 > max 35' groups."""
    r = reason.lower()

    # the evening gate is checked FIRST. Its reasons contain "entry window",
    # which the generic rule below would swallow - and then a trade refused by
    # an evening hour toggle would be indistinguishable from one refused by the
    # server-clock window, which is the one thing you want to tell apart.
    if "evening session switched off" in r:
        return "evening session off"
    if "evening entry window" in r:
        return "outside the evening window"
    m = re.match(r"ist hour (\d{2}):00", r)
    if m:
        return f"evening hour {m.group(1)}:00 off"

    for key, label in (("spread", "spread cap"), ("quality", "quality filter"),
                       ("already positioned", "already positioned that way"),
                       ("lot size", "lot size 0"), ("news", "news blackout"),
                       ("weekend", "weekend cutoff"), ("guard", "loss guard locked"),
                       ("entry window", "outside the entry window")):
        if key in r:
            return label
    return reason


def summaries(events):
    """The EA's own DAY_SUMMARY rows, newest last."""
    out = []
    for ev in events:
        if ev.get("event") == "DAY_SUMMARY" and ev.get("date"):
            out.append(ev)
    return out


TIME_FORMATS = ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d %H:%M", "%Y-%m-%d %H:%M:%S")


def parse_ts(ts):
    for fmt in TIME_FORMATS:
        try:
            return datetime.strptime(ts, fmt)
        except (ValueError, TypeError):
            continue
    return None


def hour_of(ts):
    """'2026.09.18 21:39:00' -> 21. Returns None if unparseable."""
    d = parse_ts(ts)
    return d.hour if d else None


def date_of(ts):
    d = parse_ts(ts)
    return d.date() if d else None


def duration_mins(t_in, t_out):
    """Minutes held, or None if either timestamp is unreadable."""
    a, b = parse_ts(t_in), parse_ts(t_out)
    if not a or not b or b < a:
        return None
    return (b - a).total_seconds() / 60.0


def fmt_mins(m):
    if m is None:
        return "-"
    if m < 90:
        return f"{m:.0f}m"
    if m < 2880:
        return f"{m / 60:.1f}h"
    return f"{m / 1440:.1f}d"


DOW = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def dow_of(ts):
    d = parse_ts(ts)
    return f"{d.weekday()} {DOW[d.weekday()]}" if d else None


# --------------------------------------------------------------------------
# statistics
# --------------------------------------------------------------------------

def parse_day(txt):
    """'2026-08-01' or '2026.08.01' -> date. None if unusable."""
    if not txt:
        return None
    for fmt in ("%Y-%m-%d", "%Y.%m.%d", "%d-%m-%Y", "%d/%m/%Y"):
        try:
            return datetime.strptime(txt.strip(), fmt).date()
        except ValueError:
            continue
    return None


def in_range(ts, lo, hi):
    if lo is None and hi is None:
        return True
    d = date_of(ts)
    if d is None:
        return False
    return (lo is None or d >= lo) and (hi is None or d <= hi)


def apply_filters(trades, skips, symbol, lo, hi):
    if symbol:
        trades = [t for t in trades if t["sym"] == symbol]
        skips = [s for s in skips if s["sym"] == symbol]
    if lo or hi:
        trades = [t for t in trades if in_range(t["t_ist"], lo, hi)]
        skips = [s for s in skips if in_range(s["t_ist"], lo, hi)]
    return trades, skips


def preset_range(name, today=None):
    """'7d' | '30d' | '90d' | 'mtd' | 'all' -> (from, to)"""
    today = today or datetime.now().date()
    if name == "mtd":
        return today.replace(day=1), None
    for days, key in ((7, "7d"), (30, "30d"), (90, "90d")):
        if name == key:
            return today - timedelta(days=days - 1), None
    return None, None


def stats(rows):
    n = len(rows)
    if n == 0:
        return None
    wins = [t for t in rows if t["net"] > 0]
    losses = [t for t in rows if t["net"] < 0]
    gp = sum(t["net"] for t in wins)
    gl = -sum(t["net"] for t in losses)
    return {
        "n": n,
        "wins": len(wins),
        "losses": len(losses),
        "win_pct": len(wins) / n * 100,
        "net": sum(t["net"] for t in rows),
        "r": sum(t["r"] for t in rows),
        "avg_r": sum(t["r"] for t in rows) / n,
        "avg_win": (gp / len(wins)) if wins else 0.0,
        "avg_loss": (-gl / len(losses)) if losses else 0.0,
        "pf": (gp / gl) if gl > 0 else float("inf"),
        "expectancy": sum(t["net"] for t in rows) / n,
    }


def bucket(trades, keyfn):
    out = defaultdict(list)
    for t in trades:
        k = keyfn(t)
        if k is not None:
            out[k].append(t)
    return out


def num_bucket(t, field, edges, label):
    v = t["logic"].get(field)
    if v is None:
        return None
    for lo, hi in zip(edges, edges[1:]):
        if lo <= v < hi:
            return f"{label} {lo:g}-{hi:g}"
    return f"{label} {edges[-1]:g}+" if v >= edges[-1] else None


def equity_curve(trades):
    """Cumulative net and the drawdown beneath the running peak."""
    cum, dd, run, peak = [], [], 0.0, 0.0
    for t in trades:
        run += t["net"]
        peak = max(peak, run)
        cum.append(run)
        dd.append(run - peak)
    return cum, dd


def streaks(trades):
    """Longest and current runs of wins and losses, plus the worst drawdown."""
    best_w = best_l = cur_w = cur_l = 0
    for t in trades:
        if t["net"] > 0:
            cur_w, cur_l = cur_w + 1, 0
        elif t["net"] < 0:
            cur_l, cur_w = cur_l + 1, 0
        else:
            cur_w = cur_l = 0
        best_w, best_l = max(best_w, cur_w), max(best_l, cur_l)
    _, dd = equity_curve(trades)
    return {"max_wins": best_w, "max_losses": best_l,
            "cur_wins": cur_w, "cur_losses": cur_l,
            "max_dd": min(dd) if dd else 0.0}


def after_losses(trades, n):
    """Trades taken straight after n consecutive losers - is a cool-off worth it?"""
    out, run = [], 0
    for t in trades:
        if run >= n:
            out.append(t)
        if t["net"] < 0:
            run += 1
        elif t["net"] > 0:
            run = 0
    return out


def ladder_funnel(trades, cap=14):
    """
    How far up the TP ladder trades actually get. With InpRunUntilFlip on the
    EA logs rungs above TP5 (TP6_REACHED, TP7_REACHED, ...), so the funnel
    grows to whatever the log actually contains rather than stopping at 5.
    """
    total = len(trades)
    top = min(max([t["tp_reached"] for t in trades] + [5]), cap)
    rows = []
    for n in range(1, top + 1):
        hit = [t for t in trades if t["tp_reached"] >= n]
        rows.append({"n": n, "count": len(hit), "runner": n > 5,
                     "pct": (len(hit) / total * 100) if total else 0.0,
                     "net": sum(t["net"] for t in hit)})
    return rows


def runner_stats(trades):
    """
    The question InpRunUntilFlip raises: was running past TP5 better than
    closing there?

    Every trade that reached TP5 would have banked tp5_r under the old rule.
    What it actually made is r. The difference, summed, is what the runner
    earned or cost - a straight A/B on the feature, from the log alone.

    give_back is peak_r - r: how much of the best rung the trail handed back.
    """
    ran = [t for t in trades if t["tp5_r"] is not None]
    if not ran:
        return None

    actual = sum(t["r"] for t in ran)
    counter = sum(t["tp5_r"] for t in ran)
    beat = [t for t in ran if t["r"] > t["tp5_r"] + 1e-9]
    worse = [t for t in ran if t["r"] < t["tp5_r"] - 1e-9]

    gb = [t["peak_r"] - t["r"] for t in ran if t["peak_r"] > 0]
    held = [t["mins"] for t in ran if t["mins"] is not None]
    others = [t for t in trades if t["tp5_r"] is None and t["mins"] is not None]

    by_exit = defaultdict(list)
    for t in ran:
        by_exit[t["exit"]].append(t)

    return {
        "n": len(ran),
        "actual_r": actual,
        "counter_r": counter,
        "delta_r": actual - counter,
        "delta_per": (actual - counter) / len(ran),
        "beat": len(beat),
        "worse": len(worse),
        "net": sum(t["net"] for t in ran),
        "give_back": (sum(gb) / len(gb)) if gb else 0.0,
        "give_back_total": sum(gb),
        "peak_avg": sum(t["peak_r"] for t in ran) / len(ran),
        "held_avg": (sum(held) / len(held)) if held else None,
        "held_max": max(held) if held else None,
        "other_held_avg": (sum(t["mins"] for t in others) / len(others)) if others else None,
        "by_exit": by_exit,
    }


def gaveback(trades):
    """
    Trades that reached TP1 - so the stop stepped to breakeven - and still
    finished flat or negative. This is what the breakeven rule costs.
    """
    return [t for t in trades if t["tp_reached"] >= 1 and t["net"] <= 0]


def flag_items(filters):
    """
    The signal filters only. 'enabled' is the quality filter's own on/off
    switch, not a filter verdict, and in Python a JSON true is an int - so it
    has to be excluded by name as well as by type or it shows up as a filter
    called 'enabled' with a verdict of 'worth enabling'.
    """
    for k, v in filters.items():
        if k == "enabled" or isinstance(v, bool):
            continue
        if isinstance(v, int):
            yield k, v


def filter_names(trades):
    return sorted({k for t in trades for k, _ in flag_items(t["filters"])})


def filter_split(trades, name):
    passed = [t for t in trades if dict(flag_items(t["filters"])).get(name) == 1]
    failed = [t for t in trades if dict(flag_items(t["filters"])).get(name) == 0]
    return stats(passed), stats(failed)


def verdict_of(sp, sf):
    if not sp or not sf:
        return "", "dim"
    if sf["net"] < 0 < sp["net"]:
        return "worth enabling", "good"
    if sf["avg_r"] > sp["avg_r"]:
        return "costs you money", "bad"
    return "no clear edge", "dim"


# --------------------------------------------------------------------------
# text report
# --------------------------------------------------------------------------

def table(title, groups, min_trades):
    """groups: {label: [trade, ...]} -> printed table sorted by net."""
    print(f"\n{title}")
    print("-" * 78)
    print(f"{'':<22}{'Trades':>7}{'Win%':>7}{'Net':>11}{'Avg R':>8}{'Net R':>8}{'PF':>7}")

    rows = []
    for label, items in groups.items():
        st = stats(items)
        if st and st["n"] >= min_trades:
            rows.append((label, st))
    if not rows:
        print("  (nothing with enough trades)")
        return

    for label, st in sorted(rows, key=lambda x: -x[1]["net"]):
        pf = "inf" if st["pf"] == float("inf") else f"{st['pf']:.2f}"
        print(f"{str(label)[:21]:<22}{st['n']:>7}{st['win_pct']:>6.0f}%"
              f"{st['net']:>11.2f}{st['avg_r']:>8.2f}{st['r']:>8.1f}{pf:>7}")


def filter_report(trades, min_trades):
    """
    For each signal filter, compare the trades it would have passed with
    those it would have blocked. This is the number that tells you whether
    turning a filter on is worth it.
    """
    print("\nFilters: PASS vs FAIL at entry")
    print("-" * 78)
    print(f"{'Filter':<14}{'':<6}{'Trades':>7}{'Win%':>7}{'Net':>11}{'Avg R':>8}{'Verdict':>18}")

    names = filter_names(trades)
    if not names:
        print("  (no filter flags in this log)")
        return

    shown = 0
    for name in names:
        sp, sf = filter_split(trades, name)
        if not sp or not sf or sp["n"] < min_trades or sf["n"] < min_trades:
            continue
        shown += 1
        verdict, _ = verdict_of(sp, sf)
        for tag, st in (("PASS", sp), ("FAIL", sf)):
            note = verdict if tag == "FAIL" else ""
            print(f"{name:<14}{tag:<6}{st['n']:>7}{st['win_pct']:>6.0f}%"
                  f"{st['net']:>11.2f}{st['avg_r']:>8.2f}{note:>18}")
        print()
    if not shown:
        print("  (no filter has enough trades on both sides yet)")


def funnel_report(trades):
    print("\nTarget ladder - how far trades get")
    print("-" * 78)
    print(f"{'':<22}{'Trades':>7}{'% of all':>10}{'Net':>12}")
    for row in ladder_funnel(trades):
        tag = "reached TP" + str(row["n"]) + (" (runner)" if row["runner"] else "")
        print(f"{tag:<22}{row['count']:>7}{row['pct']:>9.0f}%{row['net']:>12.2f}")
    gb = gaveback(trades)
    if gb:
        st = stats(gb)
        print(f"\n  {len(gb)} trades reached TP1 and still finished flat or down"
              f" ({st['net']:+.2f}).")
        print("  That is the price of stepping the stop to breakeven.")


def summary(trades):
    st = stats(trades)
    if not st:
        print("\nNo completed trades found.")
        return
    sk = streaks(trades)
    pf = "inf" if st["pf"] == float("inf") else f"{st['pf']:.2f}"
    print("\nOverall")
    print("-" * 78)
    print(f"  Trades        {st['n']}  ({st['wins']}W / {st['losses']}L)")
    print(f"  Win rate      {st['win_pct']:.1f}%")
    print(f"  Net           {st['net']:+.2f}")
    print(f"  Net R         {st['r']:+.1f}R")
    print(f"  Avg R/trade   {st['avg_r']:+.2f}R")
    print(f"  Avg win       {st['avg_win']:+.2f}   avg loss {st['avg_loss']:+.2f}")
    print(f"  Expectancy    {st['expectancy']:+.2f} per trade")
    print(f"  Profit factor {pf}")
    print(f"  Worst drawdown{sk['max_dd']:+.2f}")
    print(f"  Longest run   {sk['max_wins']}W / {sk['max_losses']}L"
          f"   (now {sk['cur_wins']}W / {sk['cur_losses']}L)")


def live_report(states):
    for st in states:
        print(f"\nLive - {state_symbol(st)}")
        print("-" * 78)
        age = time.time() - st["_mtime"]
        pulse = ("live" if age < 900 else ("no pulse" if age < 7200 else "EA down?"))
        print(f"  Last heartbeat {fmt_age(age)} ago  ({pulse})")
        if state_has_position(st):
            d = "BUY" if sint(st, "dir") == 1 else "SELL"
            print(f"  OPEN {d} {sget(st, 'origVol'):.2f} lots @ {sget(st, 'entry'):.5f}"
                  f" | SL {sget(st, 'curSL'):.5f} (from {sget(st, 'initSL'):.5f})"
                  f" | {st.get('entryTag', '?')} | entered "
                  f"{st.get('entryIstFull') or st.get('entryIst', '?')} IST"
                  + (f" ({st.get('entrySrvFull')} broker)"
                     if st.get('entrySrvFull') else ""))
            rungs = " ".join(f"TP{n}{'*' if hit else ''}" for n, _, hit in ladder(st))
            run = sint(st, "runLevel")
            if run > 0:
                rungs += f" +{run} above TP5"
            print(f"  Ladder {rungs}   (* = reached)")
            if run > 0:
                print("  RUNNING past TP5 - ends on the opposite signal or the trailed stop")
        else:
            print("  Flat - no position open")
        print(f"  Today  {sint(st, 'dTrades')} trades"
              f" ({sint(st, 'dWins')}W / {sint(st, 'dLoss')}L)"
              f" | net {sget(st, 'dGrossP') - sget(st, 'dGrossL'):+.2f}"
              f" | {sget(st, 'dR'):+.2f}R")
        locks = []
        if sint(st, "dayLocked"):
            locks.append("DAY LOCKED")
        if sint(st, "acctLocked"):
            locks.append("ACCOUNT LOCKED")
        if sint(st, "warnDaily"):
            locks.append("daily warning")
        if sint(st, "warnTotal"):
            locks.append("overall warning")
        print(f"  Guards {', '.join(locks) if locks else 'clear'}")


def fmt_age(sec):
    sec = max(0, int(sec))
    if sec < 90:
        return f"{sec}s"
    if sec < 5400:
        return f"{sec // 60}m"
    if sec < 172800:
        return f"{sec // 3600}h"
    return f"{sec // 86400}d"


# --------------------------------------------------------------------------
# HTML dashboard
# --------------------------------------------------------------------------

# Chart colour, decided by job rather than taste:
#   single series (equity, funnel bars)  -> one blue
#   polarity (calendar, bar signs)       -> blue <-> red diverging, gray middle
# Blue/red is used on fills because green/red is not colourblind-safe as a
# fill pair (deutan dE 4.1). Green and red stay on TEXT, where the leading
# +/- sign already carries the sign and colour is only reinforcement.
CSS = """
/* Dark is the default - this is read for hours against charts. Light is a
   hand-picked set for daylight, projectors and print, not an inversion:
   both the blue series and the diverging red were validated against their
   own surface for contrast and colourblind separation. */
:root{
  --bg:#0f1319;--card:#171d27;--line:#2a3342;--txt:#dfe5ee;--dim:#8b97a8;
  --hover:#1d2431;--well:#121722;--shadow:0 1px 2px rgba(0,0,0,.4);
  --good:#3fd18b;--bad:#f2704f;--warn:#e7c356;--accent:#5aa9ff;
  --pos:#3987e5;--neg:#d03b3b;--mid:#383835;
  --ok:#0ca30c;--caution:#fab219;--crit:#d03b3b;
  --posrgb:57,135,229;--negrgb:208,59,59;
}
:root[data-theme="light"]{
  --bg:#f4f5f3;--card:#ffffff;--line:#e2e3dd;--txt:#16181d;--dim:#5e6672;
  --hover:#f6f7f9;--well:#f0f1ee;--shadow:0 1px 3px rgba(11,11,11,.09);
  --good:#0a7d3c;--bad:#bf3317;--warn:#8a6410;--accent:#1c5cab;
  --pos:#2a78d6;--neg:#d03b3b;--mid:#e0e0db;
  --ok:#0a7d3c;--caution:#8a6410;--crit:#bf3317;
  --posrgb:42,120,214;--negrgb:208,59,59;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--txt);
     font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
     -webkit-font-smoothing:antialiased}
header{padding:16px 20px;border-bottom:1px solid var(--line);background:var(--bg);
       position:sticky;top:0;z-index:20}
.htop{display:flex;flex-wrap:wrap;gap:12px;align-items:baseline}
h1{font-size:17px;margin:0;font-weight:600}
.sub{color:var(--dim);font-size:12px}
.wrap{padding:16px 20px;max-width:1180px;margin:0 auto}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-bottom:18px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px;
      box-shadow:var(--shadow)}
.card .k{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.05em}
.card .v{font-size:21px;font-weight:600;margin-top:3px;font-variant-numeric:tabular-nums}
.card .s{color:var(--dim);font-size:11px;margin-top:2px}
h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--dim);
   margin:26px 0 8px;font-weight:600}
table{width:100%;border-collapse:collapse;background:var(--card);
      border:1px solid var(--line);border-radius:10px;overflow:hidden;box-shadow:var(--shadow)}
th,td{padding:8px 11px;text-align:right;font-variant-numeric:tabular-nums;
      border-bottom:1px solid var(--line);white-space:nowrap}
th:first-child,td:first-child{text-align:left}
th{color:var(--dim);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.04em}
tr:last-child td{border-bottom:none}
tbody tr{transition:background .12s ease}
tbody tr:hover{background:var(--hover)}
.good{color:var(--good)}.bad{color:var(--bad)}.warn{color:var(--warn)}.dim{color:var(--dim)}
.note{color:var(--dim);font-size:12px;margin:14px 0 30px;line-height:1.7}
.scroll{overflow-x:auto}
svg{background:var(--card);border:1px solid var(--line);border-radius:10px;display:block;width:100%;
    box-shadow:var(--shadow)}
.tabs{display:flex;gap:4px;flex-wrap:wrap;margin-top:12px}
.tabs button{background:none;border:1px solid transparent;color:var(--dim);
  font:inherit;font-size:13px;padding:6px 13px;border-radius:8px;cursor:pointer;
  transition:background .14s ease,color .14s ease,border-color .14s ease}
.tabs button:hover{color:var(--txt);background:var(--hover)}
.tabs button:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.tabs button[aria-selected=true]{background:var(--card);border-color:var(--line);color:var(--txt)}
.tabs button kbd{font:inherit;font-size:10px;opacity:.5;margin-left:6px}
.panel[hidden]{display:none}
.badge{display:inline-block;padding:2px 9px;border-radius:999px;font-size:11px;
  font-weight:600;letter-spacing:.03em;border:1px solid}
.b-ok{color:var(--ok);border-color:var(--ok)}
.b-warn{color:var(--caution);border-color:var(--caution)}
.b-crit{color:var(--crit);border-color:var(--crit)}
.b-dim{color:var(--dim);border-color:var(--line)}
.live{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:12px}
.pos{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px;
     box-shadow:var(--shadow)}
.pos h3{margin:0 0 3px;font-size:15px;font-weight:600}
.kv{display:flex;justify-content:space-between;gap:14px;padding:4px 0;
    border-bottom:1px solid var(--line);font-size:13px}
.kv:last-child{border-bottom:none}
.kv span:first-child{color:var(--dim)}
.kv span:last-child{font-variant-numeric:tabular-nums}
.rungs{display:flex;gap:5px;margin:9px 0 3px}
.rung{flex:1;text-align:center;padding:5px 2px;border-radius:6px;font-size:11px;
  border:1px solid var(--line);color:var(--dim);background:var(--well)}
.rung.hit{border-color:var(--pos);color:var(--txt);
  background:color-mix(in srgb,var(--pos) 16%,var(--card))}
.bar{height:7px;border-radius:4px;background:var(--well);overflow:hidden;margin-top:6px}
.bar i{display:block;height:100%;border-radius:4px;transition:width .5s cubic-bezier(.2,.8,.2,1)}
.cal{display:flex;flex-wrap:wrap;gap:16px}
.cal figure{margin:0}
.cal figcaption{color:var(--dim);font-size:11px;margin-bottom:5px;
  text-transform:uppercase;letter-spacing:.05em}
.grid{display:grid;grid-template-columns:repeat(7,20px);gap:2px}
.grid i{width:20px;height:20px;border-radius:3px;background:var(--well);display:block;
  transition:transform .12s ease}
.grid i:hover{transform:scale(1.18)}
.dow{display:grid;grid-template-columns:repeat(7,20px);gap:2px;margin-bottom:3px}
.dow b{font-size:9px;color:var(--dim);text-align:center;font-weight:500}
.legend{display:flex;align-items:center;gap:7px;color:var(--dim);font-size:11px;margin-top:9px}
.legend i{width:16px;height:10px;border-radius:2px;display:inline-block}
.dl{background:none;border:1px solid var(--line);color:var(--dim);font:inherit;
    font-size:12px;padding:5px 12px;border-radius:8px;cursor:pointer;
    transition:color .14s ease,border-color .14s ease}
.dl:hover{color:var(--txt);border-color:var(--dim)}
.dl:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.filters{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:0 0 16px}
.flab{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.05em;
      margin-right:2px}
.flab:not(:first-child){margin-left:10px}
.chip{display:inline-block;padding:4px 11px;border-radius:999px;font-size:12px;
  border:1px solid var(--line);color:var(--dim);text-decoration:none;background:var(--card);
  transition:color .14s ease,border-color .14s ease}
.chip:hover{color:var(--txt);border-color:var(--dim)}
.chip.on{color:var(--txt);border-color:var(--accent);
  background:color-mix(in srgb,var(--accent) 14%,var(--card))}
#livedot{color:var(--good)}
#livedot::before{content:"";display:inline-block;width:6px;height:6px;border-radius:50%;
  background:var(--good);margin-right:5px;vertical-align:middle}
#theme{margin-left:auto}

/* --- motion: only where it explains something, never as decoration --- */
@media (prefers-reduced-motion:no-preference){
  #livedot::before{animation:bp 2s ease-in-out infinite}
  .panel:not([hidden]){animation:rise .26s cubic-bezier(.2,.8,.2,1) both}
  .cards .card{animation:rise .3s cubic-bezier(.2,.8,.2,1) both}
  .fbar{transform-box:fill-box;transform-origin:left center;
        animation:grow .55s cubic-bezier(.2,.8,.2,1) both}
  .eqline{animation:draw 1.1s ease-out both}
  .ddband{animation:fade .8s .35s ease-out both}
  .grid i{animation:fade .4s both}
  .kv.changed{animation:flash 1.1s ease-out}
}
@keyframes bp{0%,100%{opacity:1}50%{opacity:.25}}
@keyframes rise{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}
@keyframes grow{from{transform:scaleX(0)}to{transform:scaleX(1)}}
@keyframes draw{from{stroke-dashoffset:var(--len,3000)}to{stroke-dashoffset:0}}
@keyframes fade{from{opacity:0}to{opacity:1}}
@keyframes flash{0%{background:color-mix(in srgb,var(--accent) 26%,transparent)}
                 100%{background:transparent}}

@media(max-width:600px){
  .wrap{padding:12px}th,td{padding:7px 8px}
  header{position:static}
  .cards{grid-template-columns:repeat(auto-fit,minmax(128px,1fr))}
  .card .v{font-size:18px}
}

/* --- print: one clean report, every tab expanded, light on white --- */
@media print{
  :root{
    --bg:#fff;--card:#fff;--line:#c9cac4;--txt:#000;--dim:#4a4a46;
    --hover:#fff;--well:#f2f2ef;--shadow:none;
    --good:#0a5c2d;--bad:#96280f;--warn:#6b4c0c;--accent:#14488a;
    --pos:#2a78d6;--neg:#d03b3b;--mid:#e0e0db;
    --ok:#0a5c2d;--caution:#6b4c0c;--crit:#96280f;
    --posrgb:42,120,214;--negrgb:208,59,59;
  }
  @page{margin:14mm}
  body{font-size:11px}
  header{position:static;border-bottom:2px solid var(--line)}
  .tabs,.dl,#theme,#newtr,.livewrap,.screenonly{display:none!important}
  .filters .chip:not(.on){display:none}
  .chip.on{border-color:var(--line)}
  .panel[hidden]{display:block!important}           /* every tab in the report */
  .panel{break-before:page;padding-top:4px}
  .panel:first-of-type{break-before:auto}
  h2{break-after:avoid;margin-top:14px}
  table,svg,.pos,figure{break-inside:avoid}
  tbody tr{break-inside:avoid}
  svg,table,.card,.pos{box-shadow:none}
  .note{font-size:10px}
  *{animation:none!important;transition:none!important}
}
"""


def esc(v):
    return html_mod.escape(str(v))


def cls(v):
    return "good" if v > 0 else ("bad" if v < 0 else "dim")


def pf_str(st):
    return "inf" if st["pf"] == float("inf") else f"{st['pf']:.2f}"


class Ctx:
    """What the page is allowed to show, and how thin a bucket may be."""

    def __init__(self, min_trades=3, anon=False, daily_cap=4.0, total_cap=10.0):
        self.min_trades = min_trades
        self.anon = anon
        self.daily_cap = daily_cap
        self.total_cap = total_cap

    def money(self, v, signed=True):
        if self.anon:
            return "--"
        return f"{v:+,.2f}" if signed else f"{v:,.2f}"


def h_cards(st, sk, ctx):
    items = [
        ("Trades", f"{st['n']}", "", f"{st['wins']}W / {st['losses']}L"),
        ("Win rate", f"{st['win_pct']:.0f}%", "", ""),
        ("Net R", f"{st['r']:+.1f}R", cls(st["r"]), ""),
        ("Avg R", f"{st['avg_r']:+.2f}R", cls(st["avg_r"]), "per trade"),
        ("Profit factor", pf_str(st), "", ""),
    ]
    if not ctx.anon:
        # money cards are dropped rather than blanked under --anon: a card
        # reading "--" is just clutter where an R figure already says it
        items[2:2] = [("Net", ctx.money(st["net"]), cls(st["net"]), "")]
        items += [
            ("Expectancy", ctx.money(st["expectancy"]), cls(st["expectancy"]), "per trade"),
            ("Worst drawdown", ctx.money(sk["max_dd"]), cls(sk["max_dd"]), "peak to trough"),
        ]
    out = ['<div class="cards">']
    for k, v, c, s in items:
        sub = f'<div class="s">{esc(s)}</div>' if s else ""
        out.append(f'<div class="card"><div class="k">{esc(k)}</div>'
                   f'<div class="v {c}">{esc(v)}</div>{sub}</div>')
    out.append("</div>")
    return "".join(out)


def h_table(title, groups, ctx, first_col="", note="", sort_key=None):
    rows = [(lab, stats(items)) for lab, items in groups.items()]
    rows = [(lab, st) for lab, st in rows if st and st["n"] >= ctx.min_trades]
    if not rows:
        return ""
    rows.sort(key=sort_key or (lambda x: -x[1]["net"]))

    out = [f"<h2>{esc(title)}</h2>"]
    if note:
        out.append(f'<div class="note" style="margin:0 0 8px">{esc(note)}</div>')
    out.append('<div class="scroll"><table><thead><tr>')
    heads = [first_col or title, "Trades", "Win%"]
    if not ctx.anon:
        heads.append("Net")
    heads += ["Avg R", "Net R", "PF"]
    for h in heads:
        out.append(f"<th>{esc(h)}</th>")
    out.append("</tr></thead><tbody>")
    for lab, st in rows:
        money = "" if ctx.anon else \
            f'<td class="{cls(st["net"])}">{esc(ctx.money(st["net"]))}</td>'
        out.append(
            f"<tr><td>{esc(pretty(lab))}</td><td>{st['n']}</td>"
            f"<td>{st['win_pct']:.0f}%</td>{money}"
            f'<td class="{cls(st["avg_r"])}">{st["avg_r"]:+.2f}</td>'
            f'<td class="{cls(st["r"])}">{st["r"]:+.1f}</td><td>{pf_str(st)}</td></tr>')
    out.append("</tbody></table></div>")
    return "".join(out)


def pretty(label):
    """Day-of-week keys are sorted as '0 Monday'; show only the name."""
    s = str(label)
    return s[2:] if len(s) > 2 and s[0].isdigit() and s[1] == " " else s


def h_filters(trades, ctx):
    body = []
    for name in filter_names(trades):
        sp, sf = filter_split(trades, name)
        if not sp or not sf or sp["n"] < ctx.min_trades or sf["n"] < ctx.min_trades:
            continue
        verdict, vc = verdict_of(sp, sf)
        money_p = "" if ctx.anon else \
            f'<td class="{cls(sp["net"])}">{esc(ctx.money(sp["net"]))}</td>'
        money_f = "" if ctx.anon else \
            f'<td class="{cls(sf["net"])}">{esc(ctx.money(sf["net"]))}</td>'
        body.append(
            f"<tr><td>{esc(name)}</td>"
            f"<td>{sp['n']}</td>{money_p}"
            f'<td class="{cls(sp["avg_r"])}">{sp["avg_r"]:+.2f}</td>'
            f"<td>{sf['n']}</td>{money_f}"
            f'<td class="{cls(sf["avg_r"])}">{sf["avg_r"]:+.2f}</td>'
            f'<td class="{vc}">{esc(verdict)}</td></tr>')
    if not body:
        return ('<h2>Filters: passed vs failed at entry</h2><div class="note">'
                "No filter has enough trades on both sides yet.</div>")
    net_p = "" if ctx.anon else "<th>Pass net</th>"
    net_f = "" if ctx.anon else "<th>Fail net</th>"
    return ("<h2>Filters: passed vs failed at entry</h2>"
            '<div class="note" style="margin:0 0 8px">Verdicts are computed even when the '
            "quality filter is switched off, so this is what enabling it would have done. "
            "&ldquo;Costs you money&rdquo; is the one people miss - the filter was "
            "rejecting your better trades.</div>"
            '<div class="scroll"><table><thead><tr>'
            f"<th>Filter</th><th>Pass n</th>{net_p}<th>Pass avg R</th>"
            f"<th>Fail n</th>{net_f}<th>Fail avg R</th><th>Verdict</th>"
            "</tr></thead><tbody>" + "".join(body) + "</tbody></table></div>")


# ---------------------------------------------------------------- charts

def h_equity(trades, ctx, w=1120, h=300):
    """
    Cumulative net with the drawdown beneath it. One series, so no legend -
    the heading names it. Crosshair and tooltip on hover.
    """
    if len(trades) < 2:
        return ""
    cum, dd = equity_curve(trades)
    lo, hi = min(min(cum), 0.0), max(max(cum), 0.0)
    if hi == lo:
        hi = lo + 1.0
    padl, padr, padt, padb = 54, 16, 18, 46
    plot_h = h - padt - padb
    dd_h = 42
    gap = 24                               # room for the drawdown caption
    line_h = plot_h - dd_h - gap
    sx = (w - padl - padr) / (len(cum) - 1)

    def y(v):
        return padt + (hi - v) / (hi - lo) * line_h

    pts = " ".join(f"{padl + i * sx:.1f},{y(v):.1f}" for i, v in enumerate(cum))
    zero = y(0.0)
    worst = min(dd) if dd else 0.0
    dd_top = padt + line_h + gap

    def ddy(v):
        return dd_top + (0 if worst == 0 else (v / worst) * dd_h)

    dd_pts = " ".join(f"{padl + i * sx:.1f},{ddy(v):.1f}" for i, v in enumerate(dd))
    dd_area = (f"{padl:.1f},{dd_top:.1f} " + dd_pts +
               f" {padl + (len(dd) - 1) * sx:.1f},{dd_top:.1f}")

    grid = []
    for frac in (0.0, 0.25, 0.5, 0.75, 1.0):
        v = hi - frac * (hi - lo)
        gy = y(v)
        grid.append(f'<line x1="{padl}" y1="{gy:.1f}" x2="{w - padr}" y2="{gy:.1f}" '
                    'stroke="var(--line)" stroke-width="1"/>')
        if not ctx.anon:
            grid.append(f'<text x="{padl - 8}" y="{gy + 4:.1f}" fill="var(--dim)" '
                        f'font-size="10" text-anchor="end">{v:+,.0f}</text>')

    payload = json.dumps([
        {"i": i + 1, "v": round(cum[i], 2), "d": round(dd[i], 2),
         "t": trades[i]["t_ist"][:16], "r": round(trades[i]["r"], 2),
         "x": trades[i]["exit"]}
        for i in range(len(cum))
    ])

    return (
        "<h2>Equity curve and drawdown</h2>"
        f'<svg id="eq" viewBox="0 0 {w} {h}" height="{h}" '
        'role="img" aria-label="Cumulative net profit by trade, with drawdown below">'
        + "".join(grid) +
        f'<line x1="{padl}" y1="{zero:.1f}" x2="{w - padr}" y2="{zero:.1f}" '
        'stroke="var(--dim)" stroke-width="1" stroke-dasharray="3 3"/>'
        f'<polygon class="ddband" points="{dd_area}" fill="var(--neg)" opacity="0.28"/>'
        f'<polyline class="ddband" fill="none" stroke="var(--neg)" stroke-width="1.5" '
        f'points="{dd_pts}" opacity="0.85"/>'
        f'<polyline class="eqline" fill="none" stroke="var(--pos)" stroke-width="2" '
        f'stroke-linejoin="round" stroke-linecap="round" points="{pts}"/>'
        f'<text x="{padl}" y="{dd_top - 7:.1f}" fill="var(--dim)" font-size="10">'
        f'drawdown{"" if ctx.anon else f" (worst {worst:+,.0f})"}</text>'
        f'<text x="{w - padr}" y="{h - 26}" fill="var(--dim)" font-size="10" '
        f'text-anchor="end">{len(cum)} trades</text>'
        f'<line id="eqx" x1="0" y1="{padt}" x2="0" y2="{dd_top + dd_h:.1f}" '
        'stroke="var(--accent)" stroke-width="1" opacity="0"/>'
        f'<circle id="eqd" r="4" fill="var(--pos)" stroke="var(--card)" '
        'stroke-width="2" opacity="0"/>'
        f'<rect id="eqhit" x="{padl}" y="{padt}" width="{w - padl - padr}" '
        f'height="{plot_h}" fill="transparent" style="cursor:crosshair"/>'
        f'<text id="eqt" class="screenonly" x="0" y="{h - 8}" fill="var(--txt)" font-size="11">'
        'Hover the curve for trade detail</text>'
        "</svg>"
        f'<script>window.EQ={{d:{payload},padl:{padl},sx:{sx},w:{w},'
        f'anon:{"true" if ctx.anon else "false"}}};</script>')


EQ_JS = """
(function(){
 var s=document.getElementById('eq'); if(!s||!window.EQ) return;
 var E=window.EQ, hit=document.getElementById('eqhit'), xl=document.getElementById('eqx'),
     dot=document.getElementById('eqd'), lab=document.getElementById('eqt');
 function pt(ev){
   var r=s.getBoundingClientRect(), cx=(ev.touches?ev.touches[0].clientX:ev.clientX);
   return (cx-r.left)/r.width*E.w;
 }
 function move(ev){
   var x=pt(ev), i=Math.round((x-E.padl)/E.sx);
   if(i<0)i=0; if(i>=E.d.length)i=E.d.length-1;
   var d=E.d[i], px=E.padl+i*E.sx;
   xl.setAttribute('x1',px); xl.setAttribute('x2',px); xl.setAttribute('opacity','1');
   var poly=s.querySelector('polyline.eqline'),
       pts=poly.getAttribute('points').split(' ')[i].split(',');
   dot.setAttribute('cx',pts[0]); dot.setAttribute('cy',pts[1]); dot.setAttribute('opacity','1');
   lab.setAttribute('x', Math.min(Math.max(px-90,8), E.w-260));
   lab.textContent='#'+d.i+'  '+d.t+'   '+d.x+'   '+(d.r>=0?'+':'')+d.r+'R'+
     (E.anon?'':'   equity '+(d.v>=0?'+':'')+d.v.toLocaleString()+
      (d.d<0?'   dd '+d.d.toLocaleString():''));
 }
 function out(){ xl.setAttribute('opacity','0'); dot.setAttribute('opacity','0');
   lab.setAttribute('x','0'); lab.textContent='Hover the curve for trade detail'; }
 hit.addEventListener('mousemove',move); hit.addEventListener('mouseleave',out);
 hit.addEventListener('touchmove',function(e){move(e);e.preventDefault();},{passive:false});
})();
"""


def h_funnel(trades, ctx, w=1120, bar_h=30):
    """
    How far up the ladder trades get. Length carries the magnitude, so every
    bar is the same blue - colour would be encoding what position already says.
    """
    rows = ladder_funnel(trades)
    total = len(trades)
    if not total:
        return ""
    padl, padr, padt = 78, 140, 24
    h = padt + len(rows) * (bar_h + 6) + 14
    span = w - padl - padr
    body = []
    for i, row in enumerate(rows):
        yy = padt + i * (bar_h + 6)
        bw = span * (row["pct"] / 100.0)
        # rungs above TP5 only exist with InpRunUntilFlip on; same hue, lighter,
        # so the runner reads as a continuation rather than a separate series
        runner_op = ' opacity="0.62"' if row["runner"] else ""
        runner_tip = " (runner)" if row["runner"] else ""
        body.append(
            f'<text x="{padl - 10}" y="{yy + bar_h / 2 + 4:.0f}" fill="var(--dim)" '
            f'font-size="11" text-anchor="end">TP{row["n"]}</text>'
            f'<rect x="{padl}" y="{yy}" width="{span}" height="{bar_h}" rx="4" '
            'fill="var(--well)"/>'
            f'<rect x="{padl}" y="{yy}" width="{max(bw, 2):.1f}" height="{bar_h}" '
            f'rx="4" class="fbar" fill="var(--pos)"{runner_op}><title>{row["count"]} of {total} trades '
            f'reached TP{row["n"]}{runner_tip} ({row["pct"]:.0f}%)</title></rect>'
            f'<text x="{padl + span + 10}" y="{yy + bar_h / 2 + 4:.0f}" '
            f'fill="var(--txt)" font-size="12">{row["count"]} &#183; '
            f'{row["pct"]:.0f}%</text>')
    return (
        "<h2>Target ladder - how far trades actually get</h2>"
        f'<svg viewBox="0 0 {w} {h}" height="{h}" role="img" '
        f'aria-label="Share of trades reaching each target level">'
        f'<text x="{padl}" y="14" fill="var(--dim)" font-size="10">'
        f'share of all {total} completed trades'
        f'{" - rungs above TP5 are runner rungs" if any(r["runner"] for r in rows) else ""}</text>'
        + "".join(body) + "</svg>")


def h_calendar(trades, ctx):
    """
    A month grid per month, cell colour = that day's net. Polarity, so the
    diverging pair: blue for up, red for down, neutral gray for a flat or
    untraded day. Every cell carries its numbers in a tooltip, and the same
    figures are in the day table below, so colour is never the only channel.
    """
    days = defaultdict(list)
    for t in trades:
        d = date_of(t["t_ist"])
        if d:
            days[d].append(t)
    if not days:
        return ""
    nets = {d: sum(x["net"] for x in items) for d, items in days.items()}
    peak = max((abs(v) for v in nets.values()), default=0.0) or 1.0

    months = OrderedDict()
    for d in sorted(days):
        months.setdefault((d.year, d.month), []).append(d)

    def shade(net):
        if net == 0:
            return "var(--mid)"
        a = 0.25 + 0.75 * min(abs(net) / peak, 1.0)
        base = "57,135,229" if net > 0 else "208,59,59"
        return f"rgba({base},{a:.2f})"

    figs = []
    for (yr, mo), dlist in months.items():
        first = datetime(yr, mo, 1).date()
        lead = first.weekday()
        cells = ['<i style="background:transparent"></i>'] * lead
        nxt = datetime(yr + (mo == 12), (mo % 12) + 1, 1).date()
        cur = first
        while cur < nxt:
            if cur in nets:
                net, n = nets[cur], len(days[cur])
                money = "" if ctx.anon else f" &#183; {net:+,.2f}"
                tip = (f"{cur:%a %d %b %Y} &#183; {n} trade{'s' if n != 1 else ''}"
                       f"{money} &#183; {sum(x['r'] for x in days[cur]):+.1f}R")
                cells.append(f'<i style="background:{shade(net)}" title="{tip}"></i>')
            else:
                cells.append('<i title="' + f"{cur:%a %d %b %Y}" + ' &#183; no trades"></i>')
            cur += timedelta(days=1)
        figs.append(
            f'<figure><figcaption>{first:%b %Y}</figcaption>'
            '<div class="dow"><b>M</b><b>T</b><b>W</b><b>T</b><b>F</b><b>S</b><b>S</b></div>'
            f'<div class="grid">{"".join(cells)}</div></figure>')

    return ("<h2>Daily result calendar</h2>"
            f'<div class="cal">{"".join(figs)}</div>'
            '<div class="legend"><span>loss</span>'
            '<i style="background:rgba(208,59,59,0.95)"></i>'
            '<i style="background:rgba(208,59,59,0.45)"></i>'
            '<i style="background:var(--mid)"></i>'
            '<i style="background:rgba(57,135,229,0.45)"></i>'
            '<i style="background:rgba(57,135,229,0.95)"></i>'
            '<span>profit</span><span class="screenonly" style="margin-left:8px">'
            'hover a day for its figures</span></div>')


# ---------------------------------------------------------------- live tab

def clock_note(st):
    """
    State which GMT offset the EA used to produce every IST time on this page.

    A wrong offset shifts every timestamp by a constant and nothing else looks
    broken - the trades, the R multiples and the session buckets all stay
    self-consistent, so the only way to catch it is to show the number. In the
    Strategy Tester the offset is never auto-detected, so a forgotten
    InpServerGmtOffset is exactly how this goes wrong.
    """
    raw = st.get("gmtOffset")
    if raw in (None, ""):
        return ""
    try:
        off = float(raw)
    except (TypeError, ValueError):
        return ""
    warn = ' class="warn"' if off == 0 else ' class="dim"'
    tail = " - IST times will be wrong unless the broker really is GMT+0" if off == 0 else ""
    return (f'<span{warn}> &#183; times IST, converted from broker GMT{off:+.1f}'
            f'{tail}</span>')


MQL5_EPOCH = datetime(1970, 1, 1)


def entry_instant(st):
    """
    The RAW entry time on the broker clock, as the EA recorded it.

    Preferred over the formatted strings because those were converted once,
    with whatever GMT offset was in force at the time. One weekend restart
    resolved GMT-5.5 (TimeCurrent() frozen at the Friday close while TimeGMT()
    kept running) and froze "05:45" into the state file for a trade opened at
    21:15 IST. A raw instant can be re-converted; a formatted string cannot.

    Needs EA v1.30+ with entryTimeSrv. None for anything older.
    """
    try:
        v = int(float(st.get("entryTimeSrv") or 0))
    except (TypeError, ValueError):
        return None
    return (MQL5_EPOCH + timedelta(seconds=v)) if v > 0 else None


def state_offset(st, override=None):
    if override is not None:
        return override
    try:
        return float(st.get("gmtOffset"))
    except (TypeError, ValueError):
        return None


def entered_cell(st, held=True):
    """
    The Live card's entry time, on both clocks.

    The EA runs on the BROKER's clock, which is almost never IST, so the entry
    time is converted before it is written. Showing the broker's own time beside
    the IST one means that conversion can be checked rather than taken on trust.

    The date matters too: the EA only recorded HH:MM, which says nothing about
    which day - and with InpRunUntilFlip a runner can be held for days.
    """
    raw = entry_instant(st)
    off = state_offset(st)

    if raw is not None and off is not None:
        # convert here, from the broker's own instant, so the value shown is
        # right even if the EA formatted it under a wrong offset earlier
        ist = raw + timedelta(hours=IST_HOURS - off)
        full = ist.strftime("%Y.%m.%d %H:%M")
        srv = raw.strftime("%Y.%m.%d %H:%M")
    else:
        full = (st.get("entryIstFull") or "").strip()
        srv = (st.get("entrySrvFull") or "").strip()

    short = (st.get("entryIst") or "").strip()
    if not full:
        if not short:
            return "?"
        # No raw instant and no date: this came from a build that only ever
        # stored the formatted time. It was converted once, and if the offset
        # was wrong then, it is wrong now and cannot be repaired from here.
        return (esc(short) + ' IST<span class="warn"> \u2013 unverified: this EA '
                'build stored only the formatted time, so a wrong GMT offset at '
                'the time is baked in. Recompile to fix.</span>')

    sub = []
    if srv:
        off_txt = f" (GMT{off:+.1f})" if off is not None else ""
        # same calendar day on both clocks -> the time alone is unambiguous
        shown = srv[-5:] if srv[:10] == full[:10] else srv
        sub.append(esc(shown) + " broker" + off_txt)

    t = parse_ts(full) if held else None
    if t:
        now_ist = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(hours=5, minutes=30)
        mins = (now_ist - t).total_seconds() / 60.0
        if mins >= 0:
            sub.append("held " + fmt_mins(mins))

    tail = ('<div class="dim">' + " &middot; ".join(sub) + "</div>") if sub else ""
    return esc(full) + " IST" + tail


def h_live(states, ctx):
    if not states:
        return ('<div class="note">No <code>_state.txt</code> found next to the logs, '
                "so there is nothing live to show. The EA writes one when "
                "<code>InpPersistState</code> is on; point <code>--state</code> at it "
                "if it lives somewhere else.</div>")

    blocks = []
    for st in states:
        age = time.time() - st["_mtime"]
        # with InpHeartbeatMin on, the state file is rewritten on a timer, so
        # its age is the EA's own pulse - not merely "time since a trade".
        fresh = ("b-ok" if age < 900 else ("b-warn" if age < 7200 else "b-crit"))
        stale_word = ("live" if age < 900
                      else ("no pulse" if age < 7200 else "EA down?"))

        rows = []
        if state_has_position(st):
            d = sint(st, "dir")
            side = "BUY" if d == 1 else "SELL"
            entry, cur_sl, init_sl = sget(st, "entry"), sget(st, "curSL"), sget(st, "initSL")
            risk = sget(st, "risk")
            moved = abs(cur_sl - init_sl) > 1e-9
            locked = (d == 1 and cur_sl >= entry) or (d == -1 and cur_sl <= entry)
            rows = [
                ("Side", f'<span class="{"good" if d == 1 else "bad"}">{side}</span>'),
                ("Lots", f"{sget(st, 'origVol'):.2f}"),
                ("Entry", f"{entry:.5f}"),
                ("Stop", f"{cur_sl:.5f}" +
                 ('<span class="dim"> moved</span>' if moved else "") +
                 ('<span class="good"> risk-free</span>' if locked else "")),
                ("Initial stop", f'<span class="dim">{init_sl:.5f}</span>'),
                ("1R", f"{risk:.5f}"),
                ("Mode", esc(st.get("entryTag", "?"))),
                ("Entered", entered_cell(st)),
            ]
            rungs = "".join(
                f'<div class="rung{" hit" if hit else ""}" title="TP{n} at {px:.5f}'
                f'{" - reached" if hit else ""}">TP{n}</div>'
                for n, px, hit in ladder(st))
            run = sint(st, "runLevel")
            if run > 0:
                # InpRunUntilFlip: TP5 did not close it, and it has cleared
                # this many rungs above TP5 with the stop stepping up behind
                rungs += (f'<div class="rung hit" title="running above TP5 - '
                          f'{run} rung{"s" if run != 1 else ""} cleared">'
                          f'+{run}&#9650;</div>')
            ladder_html = (f'<div class="rungs">{rungs}</div>'
                           '<div class="sub">filled rungs are targets already reached'
                           + (" &#183; running past TP5 until the signal flips" if run > 0 else "")
                           + "</div>")
            title = f"Open {side}"
            badge = ('<span class="badge b-ok">RUNNING</span>' if run > 0
                     else '<span class="badge b-ok">IN TRADE</span>')
        else:
            ladder_html = ""
            title = "Flat"
            badge = '<span class="badge b-dim">NO POSITION</span>'
            has_last = (st.get("entryIstFull") or st.get("entryIst") or "").strip()
            rows = [("Last entry",
                     entered_cell(st, held=False) if has_last else "&mdash;")]

        d_net = sget(st, "dGrossP") - sget(st, "dGrossL")
        d_tr, d_w, d_l = sint(st, "dTrades"), sint(st, "dWins"), sint(st, "dLoss")
        today = [
            ("Trades today", f"{d_tr} <span class='dim'>({d_w}W / {d_l}L)</span>"),
            ("Net today", f'<span class="{cls(d_net)}">{esc(ctx.money(d_net))}</span>'),
            ("R today", f'<span class="{cls(sget(st, "dR"))}">{sget(st, "dR"):+.2f}R</span>'),
            ("Best / worst", f"{esc(ctx.money(sget(st, 'dBest')))} / "
                             f"{esc(ctx.money(sget(st, 'dWorst')))}"),
        ]

        guards = []
        day_locked, acct_locked = sint(st, "dayLocked"), sint(st, "acctLocked")
        if acct_locked:
            guards.append('<span class="badge b-crit">ACCOUNT LOCKED</span>')
        if day_locked:
            guards.append('<span class="badge b-crit">DAY LOCKED</span>')
        if sint(st, "warnTotal"):
            guards.append('<span class="badge b-warn">OVERALL WARNING</span>')
        if sint(st, "warnDaily"):
            guards.append('<span class="badge b-warn">DAILY WARNING</span>')
        if not guards:
            guards.append('<span class="badge b-ok">GUARDS CLEAR</span>')

        base, peak = sget(st, "baseline"), sget(st, "peakEquity")
        day_start = sget(st, "dayStartBal")
        guard_rows = []
        if base > 0 and not ctx.anon:
            cap = base * ctx.daily_cap / 100.0
            used = max(0.0, -d_net)
            frac = min(used / cap, 1.0) if cap > 0 else 0.0
            col = "var(--crit)" if frac > .75 else ("var(--caution)" if frac > .5 else "var(--ok)")
            guard_rows.append(
                f'<div class="kv"><span>Daily loss used</span>'
                f'<span>{used:,.2f} of {cap:,.2f}</span></div>'
                f'<div class="bar"><i style="width:{frac * 100:.0f}%;background:{col}"></i></div>'
                f'<div class="sub" style="margin-top:4px">assumes a {ctx.daily_cap:g}% cap '
                f'(--daily-cap-pct); the EA keeps the real figure in its inputs</div>')
            if peak > 0:
                off = peak - max(day_start, 0.0)
                guard_rows.append(
                    f'<div class="kv"><span>Peak equity</span><span>{peak:,.2f}</span></div>'
                    f'<div class="kv"><span>Below peak</span>'
                    f'<span class="{cls(-off)}">{-off:+,.2f}</span></div>')
            guard_rows.append(
                f'<div class="kv"><span>Baseline</span><span>{base:,.2f}</span></div>')

        blocks.append(
            '<div class="pos">'
            f'<div class="htop" style="justify-content:space-between">'
            f'<h3>{esc(state_symbol(st))}</h3>{badge}</div>'
            f'<div class="sub">{esc(title)} &#183; '
            f'<span class="badge {fresh}">{stale_word} &#183; {fmt_age(age)} ago</span>'
            + clock_note(st) + '</div>'
            + ladder_html
            + "".join(f'<div class="kv"><span>{k}</span><span>{v}</span></div>'
                      for k, v in rows)
            + '<div style="height:10px"></div>'
            + "".join(f'<div class="kv"><span>{k}</span><span>{v}</span></div>'
                      for k, v in today)
            + f'<div style="margin-top:10px;display:flex;gap:6px;flex-wrap:wrap">'
            + "".join(guards) + "</div>"
            + "".join(guard_rows)
            + "</div>")

    today_rows = []
    for st in states:
        for t in st["_today"]:
            today_rows.append((state_symbol(st), t))
    table_html = ""
    if today_rows:
        body = []
        for sym, t in today_rows:
            side = "BUY" if t["dir"] == 1 else "SELL"
            rc = {"WIN": "good", "LOSS": "bad"}.get(t["result"], "dim")
            money = "" if ctx.anon else \
                f'<td class="{cls(t["net"])}">{esc(ctx.money(t["net"]))}</td>'
            body.append(
                f'<tr><td>{esc(t["t_ist"])}</td><td>{esc(sym)}</td>'
                f'<td>{side}</td><td>{t["entry"]:.5f}</td><td>{t["exit"]:.5f}</td>'
                f'<td>{t["pips"]:+.1f}</td>'
                f'<td class="{cls(t["r"])}">{t["r"]:+.2f}</td>{money}'
                f'<td class="{rc}">{esc(t["result"])}</td></tr>')
        net_h = "" if ctx.anon else "<th>Net</th>"
        table_html = (
            "<h2>Closed today</h2>"
            '<div class="scroll"><table><thead><tr><th>Entry IST</th><th>Symbol</th>'
            f"<th>Side</th><th>Entry</th><th>Exit</th><th>Pips</th><th>R</th>{net_h}"
            "<th>Result</th></tr></thead><tbody>"
            + "".join(body) + "</tbody></table></div>")

    return (f'<div class="live">{"".join(blocks)}</div>' + table_html +
            '<div class="note">Straight from the EA\'s <code>_state.txt</code>, which it '
            "rewrites after every event and again every <code>InpHeartbeatMin</code> minutes "
            "on a timer. Because that timer keeps beating when the market is quiet, an old "
            "timestamp means the EA itself is not running - not merely that nothing has "
            "traded. Over a weekend, with the terminal shut down, stale is expected.</div>")


# ---------------------------------------------------------------- trades tab

TRADE_COLS = ["entry_ist", "exit_ist", "symbol", "side", "mode", "session",
              "exit", "tp_reached", "sl_moves", "r", "net", "adx", "rsi",
              "spread", "ema_gap_atr"]


def trade_rows(trades, ctx):
    for t in trades:
        lg = t["logic"]
        yield {
            "entry_ist": t["t_ist"], "exit_ist": t["x_ist"], "symbol": t["sym"],
            "side": t["dir"], "mode": t["mode"], "session": t["session"],
            "exit": t["exit"], "tp_reached": t["tp_reached"],
            "sl_moves": t["sl_moves"], "r": round(t["r"], 2),
            "net": "" if ctx.anon else round(t["net"], 2),
            "adx": lg.get("adx", ""), "rsi": lg.get("rsi", ""),
            "spread": lg.get("spread", ""), "ema_gap_atr": lg.get("ema_gap_atr", ""),
        }


def trades_csv(trades, ctx):
    buf = io.StringIO()
    wr = csv.DictWriter(buf, fieldnames=TRADE_COLS, lineterminator="\n")
    wr.writeheader()
    for row in trade_rows(trades, ctx):
        wr.writerow(row)
    return buf.getvalue()


def h_trades(trades, ctx, cap=400):
    if not trades:
        return ""
    shown = trades[-cap:]
    body = []
    for t in reversed(shown):
        money = "" if ctx.anon else \
            f'<td class="{cls(t["net"])}">{esc(ctx.money(t["net"]))}</td>'
        lg = t["logic"]
        body.append(
            f'<tr><td>{esc(t["t_ist"][:16])}</td><td>{esc(t["sym"])}</td>'
            f'<td>{esc(t["dir"])}</td><td>{esc(t["session"])}</td>'
            f'<td>{esc(t["mode"])}</td><td>{esc(t["exit"])}</td>'
            f'<td>{t["tp_reached"] or ""}</td>'
            f'<td class="{cls(t["r"])}">{t["r"]:+.2f}</td>{money}'
            f'<td class="dim">{lg.get("adx", "") or ""}</td>'
            f'<td class="dim">{lg.get("spread", "") or ""}</td></tr>')
    net_h = "" if ctx.anon else "<th>Net</th>"
    more = ("" if len(trades) <= cap else
            f'<div class="note" style="margin:8px 0 0">Showing the most recent {cap} '
            f"of {len(trades)}. The export has all of them.</div>")
    return (
        '<h2 style="display:flex;justify-content:space-between;align-items:center">'
        "<span>Every completed trade</span>"
        '<button class="dl" onclick="dlCsv()">Download CSV</button></h2>'
        '<div class="scroll"><table><thead><tr><th>Entry IST</th><th>Symbol</th>'
        f"<th>Side</th><th>Session</th><th>Mode</th><th>Exit</th><th>TP</th>"
        f"<th>R</th>{net_h}<th>ADX</th><th>Spread</th></tr></thead><tbody>"
        + "".join(body) + "</tbody></table></div>" + more)


DL_JS = """
function dlCsv(){
  var el=document.getElementById('csvdata'); if(!el) return;
  var b=new Blob([el.textContent],{type:'text/csv'}), u=URL.createObjectURL(b),
      a=document.createElement('a');
  a.href=u; a.download='ea_trades.csv'; a.click(); URL.revokeObjectURL(u);
}
"""

def poll_js(poll):
    """
    Refresh the Live tab in place. It asks for one small fragment rather than
    rebuilding the page, so the cost is roughly the state file, and nothing
    scrolls or collapses under you. The history tabs are only rebuilt when a
    trade actually closes - and then it offers a reload rather than taking one.
    """
    url, secs, base = poll
    return ("""
(function(){
 var URL=%s, MS=%d, fails=0, base=%d;
 var RM = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
 var dot=document.getElementById('livedot'), panel=document.getElementById('p-live');
 if(!panel) return;
 function stamp(t,ok){ if(dot) dot.textContent = ok ? ('live '+t) : ('reconnecting '+t); }
 function banner(n){
   if(document.getElementById('newtr')) return;
   var b=document.createElement('button');
   b.id='newtr'; b.className='dl'; b.style.cssText='margin:0 0 12px';
   b.textContent=n+' new trade'+(n===1?'':'s')+' - reload for the full history';
   b.onclick=function(){ location.reload(); };
   panel.insertBefore(b, panel.firstChild);
 }
 function tick(){
   fetch(URL,{cache:'no-store'}).then(function(r){
     if(!r.ok) throw 0; return r.json();
   }).then(function(d){
     fails=0;
     /* remember every row's value, so after the swap we can flash only the
        ones that actually moved - otherwise a 5s repaint tells you nothing */
     var was={};
     panel.querySelectorAll('.kv').forEach(function(r){
       var k=r.firstElementChild, v=r.lastElementChild;
       if(k&&v) was[k.textContent]=v.textContent;
     });
     var keep=document.getElementById('newtr');
     panel.innerHTML=d.html;
     if(keep) panel.insertBefore(keep, panel.firstChild);
     if(!RM) panel.querySelectorAll('.kv').forEach(function(r){
       var k=r.firstElementChild, v=r.lastElementChild;
       if(k&&v&&(k.textContent in was)&&was[k.textContent]!==v.textContent){
         r.classList.add('changed');
       }
     });
     if(d.trades!==base) banner(Math.abs(d.trades-base));
     stamp(d.ts,true);
   }).catch(function(){
     fails++; stamp('',false);
   }).then(function(){
     // back off while the server is down instead of hammering it
     setTimeout(tick, fails>3 ? Math.min(MS*fails,60000) : MS);
   });
 }
 setTimeout(tick, MS);
})();
""" % (json.dumps(url), int(secs * 1000), int(base)))


UI_JS = """
(function(){
 var RM = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

 /* theme: dark by default, remembered per viewer. Wrapped because storage
    throws in a private window and the page must still render. */
 var root=document.documentElement, btn=document.getElementById('theme');
 function paint(t){
   if(t==='light') root.setAttribute('data-theme','light');
   else root.removeAttribute('data-theme');
   if(btn){ btn.textContent = (t==='light'?'Dark':'Light');
            btn.setAttribute('aria-label','Switch to '+(t==='light'?'dark':'light')+' theme'); }
 }
 var saved=null; try{ saved=localStorage.getItem('eatheme'); }catch(e){}
 paint(saved||'dark');
 if(btn) btn.onclick=function(){
   var next = root.getAttribute('data-theme')==='light' ? 'dark' : 'light';
   paint(next); try{ localStorage.setItem('eatheme',next); }catch(e){}
 };

 /* number 1-5 jumps to a tab; p prints the report */
 document.addEventListener('keydown',function(e){
   if(e.metaKey||e.ctrlKey||e.altKey) return;
   var el=document.activeElement;
   if(el && /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)) return;
   var bs=document.querySelectorAll('.tabs button');
   if(e.key>='1'&&e.key<='9'){ var b=bs[+e.key-1]; if(b){ b.click(); b.focus(); } }
   if(e.key==='p'||e.key==='P'){ e.preventDefault(); window.print(); }
 });

 if(RM) return;   /* everything below is motion only */

 /* draw the equity line in - the exact path length, so it lands cleanly */
 var line=document.querySelector('.eqline');
 if(line && line.getTotalLength){
   try{ var L=line.getTotalLength();
        line.style.setProperty('--len',L);
        line.style.strokeDasharray=L; }catch(e){}
 }
 /* stagger the funnel bars and the headline cards */
 document.querySelectorAll('.fbar').forEach(function(el,i){
   el.style.animationDelay=(i*55)+'ms'; });
 document.querySelectorAll('.cards .card').forEach(function(el,i){
   el.style.animationDelay=(i*40)+'ms'; });
 document.querySelectorAll('.grid i').forEach(function(el,i){
   el.style.animationDelay=Math.min(i*6,700)+'ms'; });

 /* count the headline figures up once, on load only. Never on the Live tab,
    which repaints every few seconds - animating that would be unreadable. */
 document.querySelectorAll('#p-perf .cards .v').forEach(function(el){
   var m=el.textContent.match(/^([+-]?)([\\d,]+(?:\\.\\d+)?)(.*)$/);
   if(!m) return;
   var target=parseFloat(m[2].replace(/,/g,''));
   if(!isFinite(target)||target===0) return;
   var dec=(m[2].split('.')[1]||'').length, t0=null, D=650, sign=m[1], tail=m[3];
   function step(t){
     if(t0===null) t0=t;
     var p=Math.min((t-t0)/D,1), v=target*(1-Math.pow(1-p,3));
     el.textContent=sign+v.toLocaleString(undefined,
       {minimumFractionDigits:dec,maximumFractionDigits:dec})+tail;
     if(p<1) requestAnimationFrame(step);
   }
   requestAnimationFrame(step);
 });
})();
"""


TAB_JS = """
(function(){
 var bs=[].slice.call(document.querySelectorAll('.tabs button'));
 function show(id){
   bs.forEach(function(b){
     var on=b.dataset.t===id;
     b.setAttribute('aria-selected',on?'true':'false');
     document.getElementById('p-'+b.dataset.t).hidden=!on;
   });
   try{localStorage.setItem('eatab',id);}catch(e){}
 }
 bs.forEach(function(b){b.onclick=function(){show(b.dataset.t);};});
 var want=null; try{want=localStorage.getItem('eatab');}catch(e){}
 if(want&&document.getElementById('p-'+want)) show(want);
})();
"""


# ---------------------------------------------------------------- page

def build_html(trades, states, ctx, sources, still_open, orphans, poll=None,
               skips=None, filterbar=""):
    """
    poll = (url, seconds) when served: the Live tab is refreshed in place on
    that interval and the whole-page meta refresh is dropped, so nothing jumps
    under you while you are reading. A static --html file keeps the old
    60-second reload, since there is no server to ask.
    """
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    head = (
        "<!doctype html><html lang=en><head><meta charset=utf-8>"
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        + ("" if poll else '<meta http-equiv="refresh" content="60">')
        + "<title>EMA Strategy - dashboard</title>"
        f"<style>{CSS}</style></head><body>")

    if not trades:
        live_only = h_live(states, ctx)
        return (head + "<header><div class='htop'><h1>EMA Strategy &mdash; dashboard</h1>"
                f"<span class='sub'>no completed trades in the log yet &#183; "
                f"{esc(now)}</span></div></header>"
                f"<div class='wrap'>{live_only}</div>"
                + f"<script>{UI_JS}{poll_js(poll) if poll else ''}</script>"
                + "</body></html>")

    st = stats(trades)
    sk = streaks(trades)
    syms = sorted({t["sym"] for t in trades if t["sym"]})

    mt = ctx.min_trades
    perf = (
        filterbar
        + h_cards(st, sk, ctx)
        + h_equity(trades, ctx)
        + h_funnel(trades, ctx)
        + h_runner(trades, ctx)
        + h_table("By mode", bucket(trades, lambda t: t["mode"] or "?"), ctx, "Mode")
        + h_table("By direction", bucket(trades, lambda t: t["dir"] or "?"), ctx, "Side")
        + h_table("How trades ended", bucket(trades, lambda t: t["exit"]), ctx, "Exit")
        + h_streaks(trades, sk, ctx))

    timing = (
        filterbar
        + h_calendar(trades, ctx)
        + h_table("By IST session", bucket(trades, lambda t: t["session"] or "?"),
                  ctx, "Session")
        + h_table("By IST hour",
                  bucket(trades, lambda t: (lambda x: f"{x:02d}:00" if x is not None else None)
                         (hour_of(t["t_ist"]))), ctx, "Hour",
                  sort_key=lambda x: x[0])
        + h_table("By day of week", bucket(trades, lambda t: dow_of(t["t_ist"])),
                  ctx, "Day", sort_key=lambda x: x[0]))

    signals = (
        filterbar
        + h_skips(skips or [], trades, ctx)
        + h_excursion(trades, ctx)
        + h_filters(trades, ctx)
        + h_table("By ADX at entry",
                  bucket(trades, lambda t: num_bucket(t, "adx", [0, 15, 20, 25, 30, 40], "ADX")),
                  ctx, "ADX", sort_key=lambda x: x[0])
        + h_table("By spread at entry",
                  bucket(trades, lambda t: num_bucket(t, "spread", [0, 20, 35, 50, 70], "spread")),
                  ctx, "Spread", sort_key=lambda x: x[0])
        + h_table("By RSI at entry",
                  bucket(trades, lambda t: num_bucket(t, "rsi", [0, 30, 40, 50, 60, 70], "RSI")),
                  ctx, "RSI", sort_key=lambda x: x[0]))

    tabs = [("live", "Live"), ("perf", "Performance"), ("time", "Timing"),
            ("sig", "Signals &amp; filters"), ("trades", "Trades")]
    nav = "".join(
        f'<button data-t="{k}" role="tab" aria-selected="{"true" if i == 0 else "false"}">'
        f"{v}<kbd>{i + 1}</kbd></button>" for i, (k, v) in enumerate(tabs))
    nav += ('<button id="theme" class="dl" type="button" '
            'aria-label="Switch to light theme">Light</button>')
    panels = [
        ("live", h_live(states, ctx)),
        ("perf", perf),
        ("time", timing),
        ("sig", signals),
        ("trades", h_trades(trades, ctx)),
    ]
    body = "".join(
        f'<section class="panel" id="p-{k}" role="tabpanel"{"" if i == 0 else " hidden"}>'
        f"{v}</section>" for i, (k, v) in enumerate(panels))

    meta = " &#183; ".join(filter(None, [
        ", ".join(syms) or "unknown symbol",
        f"{len(trades)} completed trades",
        f"{still_open} open" if still_open else "",
        f"{orphans} unmatched exits" if orphans else "",
        f"generated {esc(now)}",
        "anonymised" if ctx.anon else "",
    ]))

    # the separator lives on the wrapper, not inside #livedot - the dot is a
    # ::before pseudo and would otherwise render ahead of it
    live_bit = ('<span class="livewrap"> &#183; <span id="livedot">live</span></span>'
                if poll else
                '<span class="screenonly"> &#183; refreshes every 60s</span>')
    return (
        head
        + "<header><div class='htop'><h1>EMA Strategy &mdash; dashboard</h1>"
        + f"<span class='sub'>{meta}{live_bit}</span></div>"
        + f'<nav class="tabs" role="tablist">{nav}</nav></header>'
        + f'<div class="wrap">{body}'
        + '<div class="note">A bucket with a negative net and enough trades is something to '
        f"stop doing; one with three trades means nothing. Buckets under {mt} trades are "
        "hidden (--min-trades). Sources: "
        + esc(", ".join(os.path.basename(s) for s in sources)) + "</div></div>"
        + f'<script type="text/plain" id="csvdata">{esc(trades_csv(trades, ctx))}</script>'
        + f"<script>{UI_JS}{TAB_JS}{DL_JS}{EQ_JS}{poll_js(poll) if poll else ''}</script>"
        + "</body></html>")


def h_runner(trades, ctx):
    rs = runner_stats(trades)
    if not rs:
        return ""

    d = rs["delta_r"]
    if d > 0.5:
        verdict, vc = "running past TP5 is paying", "good"
    elif d < -0.5:
        verdict, vc = "running past TP5 is costing you", "bad"
    else:
        verdict, vc = "running past TP5 is roughly a wash", "dim"

    cards = [
        ("Runners", f"{rs['n']}", "", "reached TP5"),
        ("Actual", f"{rs['actual_r']:+.1f}R", cls(rs["actual_r"]), "what they made"),
        ("Closed at TP5", f"{rs['counter_r']:+.1f}R", "", "what they'd have made"),
        ("Difference", f"{rs['delta_r']:+.1f}R", cls(d),
         f"{rs['delta_per']:+.2f}R per runner"),
        ("Beat TP5", f"{rs['beat']} of {rs['n']}", "",
         f"{rs['worse']} did worse"),
        ("Avg peak", f"{rs['peak_avg']:+.1f}R", "", "best rung reached"),
        ("Given back", f"{rs['give_back']:.1f}R", "bad" if rs["give_back"] > 1 else "dim",
         "peak to exit, per runner"),
    ]
    if rs["held_avg"] is not None:
        sub = ("vs " + fmt_mins(rs["other_held_avg"]) + " for the rest") \
            if rs["other_held_avg"] is not None else "average"
        cards.append(("Held", fmt_mins(rs["held_avg"]), "", sub))

    out = ['<h2>Runner: was it worth running past TP5?</h2>',
           f'<div class="note" style="margin:0 0 10px">Every one of these '
           f'{rs["n"]} trades reached TP5, so under the old rule each would have '
           f'banked its TP5 target and stopped. &ldquo;Difference&rdquo; is what '
           f'running instead actually earned. <span class="{vc}">{esc(verdict)}'
           f'</span>.</div>', '<div class="cards">']
    for k, v, c, s in cards:
        out.append(f'<div class="card"><div class="k">{esc(k)}</div>'
                   f'<div class="v {c}">{esc(v)}</div>'
                   f'<div class="s">{esc(s)}</div></div>')
    out.append("</div>")

    rows = []
    for label, items in sorted(rs["by_exit"].items(),
                               key=lambda x: -len(x[1])):
        st = stats(items)
        gb = [t["peak_r"] - t["r"] for t in items if t["peak_r"] > 0]
        money = "" if ctx.anon else \
            f'<td class="{cls(st["net"])}">{esc(ctx.money(st["net"]))}</td>'
        rows.append(
            f"<tr><td>{esc(label)}</td><td>{st['n']}</td>{money}"
            f'<td class="{cls(st["avg_r"])}">{st["avg_r"]:+.2f}</td>'
            f'<td>{(sum(gb) / len(gb)) if gb else 0:.1f}R</td></tr>')
    if rows:
        net_h = "" if ctx.anon else "<th>Net</th>"
        out.append(
            "<h2>How runners ended</h2>"
            '<div class="note" style="margin:0 0 8px">If most of them die on the '
            "trailed stop rather than the opposite cross, the trail is cutting the "
            "trade short of the signal it was meant to wait for - tighten "
            "InpRunnerStepR only if the give-back column says so.</div>"
            '<div class="scroll"><table><thead><tr><th>Exit</th><th>Trades</th>'
            f"{net_h}<th>Avg R</th><th>Given back</th></tr></thead><tbody>"
            + "".join(rows) + "</tbody></table></div>")
    return "".join(out)


def runner_report(trades):
    rs = runner_stats(trades)
    if not rs:
        return
    print("\nRunner - was it worth running past TP5?")
    print("-" * 78)
    print(f"  Runners        {rs['n']} trades reached TP5")
    print(f"  Actual         {rs['actual_r']:+.1f}R")
    print(f"  Closed at TP5  {rs['counter_r']:+.1f}R  (what the old rule would have paid)")
    print(f"  Difference     {rs['delta_r']:+.1f}R  ({rs['delta_per']:+.2f}R per runner)")
    print(f"  Beat TP5       {rs['beat']} of {rs['n']}, {rs['worse']} did worse")
    print(f"  Avg peak rung  {rs['peak_avg']:+.1f}R")
    print(f"  Given back     {rs['give_back']:.1f}R per runner, peak to exit")
    if rs["held_avg"] is not None:
        extra = (f"  (rest: {fmt_mins(rs['other_held_avg'])})"
                 if rs["other_held_avg"] is not None else "")
        print(f"  Held           {fmt_mins(rs['held_avg'])} avg, "
              f"{fmt_mins(rs['held_max'])} longest{extra}")
    d = rs["delta_r"]
    print("  Verdict        " + ("running past TP5 is paying" if d > 0.5 else
                                 "running past TP5 is costing you" if d < -0.5 else
                                 "roughly a wash so far"))


def h_skips(skips, trades, ctx):
    """
    What the EA refused, and why. The denominator most reports never have:
    signals offered vs signals taken.
    """
    if not skips:
        return ('<h2>Refused signals</h2><div class="note">No <code>SKIP</code> rows in '
                "this log. Turn on <code>InpLogSkips</code> in the EA and every EMA cross "
                "it declines is recorded with its reason — without it, every filter here "
                "is being judged only on the trades that got through.</div>")

    taken, refused = len(trades), len(skips)
    offered = taken + refused
    by = defaultdict(list)
    for sk in skips:
        by[skip_family(sk["reason"])].append(sk)

    rows = []
    for label, items in sorted(by.items(), key=lambda x: -len(x[1])):
        share = len(items) / offered * 100
        longs = sum(1 for x in items if str(x["dir"]).upper().startswith("B"))
        rows.append(
            f"<tr><td>{esc(label)}</td><td>{len(items)}</td>"
            f"<td>{share:.0f}%</td><td>{longs}</td><td>{len(items) - longs}</td></tr>")

    cards = [
        ("Signals offered", f"{offered}", "", "crosses the EA saw"),
        ("Taken", f"{taken}", "", f"{taken / offered * 100:.0f}% of them"),
        ("Refused", f"{refused}", "", f"{refused / offered * 100:.0f}% of them"),
    ]
    out = ["<h2>Refused signals</h2>",
           '<div class="note" style="margin:0 0 10px">Every EMA cross the EA declined, '
           "with the gate that declined it. These have no outcome — nothing was traded — "
           "so treat the counts as the cost of each setting, not as lost profit.</div>",
           '<div class="cards">']
    for k, v, c, sub in cards:
        out.append(f'<div class="card"><div class="k">{esc(k)}</div>'
                   f'<div class="v {c}">{esc(v)}</div><div class="s">{esc(sub)}</div></div>')
    out.append("</div>")
    out.append('<div class="scroll"><table><thead><tr><th>Refused by</th><th>Count</th>'
               "<th>Share of all signals</th><th>Long</th><th>Short</th>"
               "</tr></thead><tbody>" + "".join(rows) + "</tbody></table></div>")

    hours = bucket(skips, lambda x: (lambda h: f"{h:02d}:00" if h is not None else None)
                   (hour_of(x["t_ist"])))
    if hours:
        hrows = "".join(
            f"<tr><td>{esc(h)}</td><td>{len(v)}</td></tr>"
            for h, v in sorted(hours.items()) if len(v) >= ctx.min_trades)
        if hrows:
            out.append("<h2>Refusals by IST hour</h2>"
                       '<div class="scroll"><table><thead><tr><th>Hour</th>'
                       "<th>Refused</th></tr></thead><tbody>" + hrows + "</tbody></table></div>")
    return "".join(out)


def excursion_stats(trades):
    """MFE/MAE, only over trades that actually carry them."""
    have = [t for t in trades if t["mfe"] is not None and t["mae"] is not None]
    if not have:
        return None
    wins = [t for t in have if t["net"] > 0]
    losses = [t for t in have if t["net"] < 0]
    def avg(xs, key):
        return (sum(key(x) for x in xs) / len(xs)) if xs else 0.0
    worst_mae = min(t["mae"] for t in have)
    # a stop that is never seriously tested is a stop with slack in it
    slack = [t for t in have if t["mae"] > -0.5]
    return {
        "n": len(have),
        "mfe_all": avg(have, lambda t: t["mfe"]),
        "mfe_win": avg(wins, lambda t: t["mfe"]),
        "mfe_loss": avg(losses, lambda t: t["mfe"]),
        "mae_all": avg(have, lambda t: t["mae"]),
        "mae_win": avg(wins, lambda t: t["mae"]),
        "mae_loss": avg(losses, lambda t: t["mae"]),
        "worst_mae": worst_mae,
        "slack_pct": len(slack) / len(have) * 100,
        "give_back": avg(have, lambda t: t["mfe"] - t["r"]),
    }


def h_excursion(trades, ctx):
    ex = excursion_stats(trades)
    if not ex:
        return ('<h2>How far trades ran</h2><div class="note">No <code>mfe_r</code> / '
                "<code>mae_r</code> in this log. EA v1.30 records them on every exit; "
                "older rows have nothing to show.</div>")

    cards = [
        ("Trades measured", f"{ex['n']}", "", "with excursion data"),
        ("Avg best", f"+{ex['mfe_all']:.2f}R", "good", "furthest in favour"),
        ("Avg worst", f"{ex['mae_all']:.2f}R", "bad", "furthest against"),
        ("Given back", f"{ex['give_back']:.2f}R", "bad" if ex["give_back"] > 1 else "dim",
         "best to exit"),
        ("Deepest drawdown", f"{ex['worst_mae']:.2f}R", "bad", "worst single trade"),
        ("Stop barely tested", f"{ex['slack_pct']:.0f}%", "",
         "never went past -0.5R"),
    ]
    out = ["<h2>How far trades ran &mdash; MFE and MAE</h2>",
           '<div class="note" style="margin:0 0 10px">'
           "<strong>MFE</strong> is the furthest a trade ran in your favour, "
           "<strong>MAE</strong> the furthest it ran against you, both in R and both "
           "sampled every tick from entry. MFE says whether the ladder was ever "
           "reachable. MAE says how much of the stop you actually needed.</div>",
           '<div class="cards">']
    for k, v, c, sub in cards:
        out.append(f'<div class="card"><div class="k">{esc(k)}</div>'
                   f'<div class="v {c}">{esc(v)}</div><div class="s">{esc(sub)}</div></div>')
    out.append("</div>")

    out.append(
        '<div class="scroll"><table><thead><tr><th></th><th>Avg best (MFE)</th>'
        "<th>Avg worst (MAE)</th></tr></thead><tbody>"
        f'<tr><td>Winners</td><td class="good">+{ex["mfe_win"]:.2f}R</td>'
        f'<td class="bad">{ex["mae_win"]:.2f}R</td></tr>'
        f'<tr><td>Losers</td><td class="good">+{ex["mfe_loss"]:.2f}R</td>'
        f'<td class="bad">{ex["mae_loss"]:.2f}R</td></tr>'
        "</tbody></table></div>")

    notes = []
    if ex["worst_mae"] > -0.8:
        notes.append(f"No trade ever went past {ex['worst_mae']:.2f}R against you, so the "
                     "stop has slack in it — a tighter one would have risked less per trade "
                     "without stopping you out any more often.")
    if ex["mfe_loss"] > 0.8:
        notes.append(f"Losers still averaged +{ex['mfe_loss']:.2f}R in your favour before "
                     "turning. That is profit that was on the table and handed back.")
    if ex["give_back"] > 1.0:
        notes.append(f"Trades gave back {ex['give_back']:.2f}R on average between their best "
                     "point and the exit — the price of trailing rather than taking fixed targets.")
    if notes:
        out.append('<div class="note">' + " ".join(esc(x) for x in notes) + "</div>")
    return "".join(out)


def skip_report(skips, trades):
    if not skips:
        print("\nRefused signals\n" + "-" * 78)
        print("  (no SKIP rows - turn on InpLogSkips to record them)")
        return
    offered = len(skips) + len(trades)
    print("\nRefused signals")
    print("-" * 78)
    print(f"  {offered} crosses seen | {len(trades)} taken "
          f"({len(trades) / offered * 100:.0f}%) | {len(skips)} refused")
    print()
    by = defaultdict(list)
    for sk in skips:
        by[skip_family(sk["reason"])].append(sk)
    print(f"{'Refused by':<32}{'Count':>7}{'Share':>8}")
    for label, items in sorted(by.items(), key=lambda x: -len(x[1])):
        print(f"{label[:31]:<32}{len(items):>7}{len(items) / offered * 100:>7.0f}%")


def excursion_report(trades):
    ex = excursion_stats(trades)
    if not ex:
        return
    print("\nHow far trades ran (MFE / MAE)")
    print("-" * 78)
    print(f"  Measured        {ex['n']} trades")
    print(f"  Avg best        +{ex['mfe_all']:.2f}R   (winners +{ex['mfe_win']:.2f}R, "
          f"losers +{ex['mfe_loss']:.2f}R)")
    print(f"  Avg worst       {ex['mae_all']:.2f}R   (winners {ex['mae_win']:.2f}R, "
          f"losers {ex['mae_loss']:.2f}R)")
    print(f"  Deepest against {ex['worst_mae']:.2f}R")
    print(f"  Given back      {ex['give_back']:.2f}R from best to exit")
    print(f"  Stop untested   {ex['slack_pct']:.0f}% of trades never passed -0.5R")


def h_filterbar(symbols, cur_sym, cur_range, lo, hi):
    """Symbol and date-range chips. Server-side, so every tab reflects them."""
    def link(**kw):
        q = {}
        if kw.get("sym") or (cur_sym and "sym" not in kw):
            q["symbol"] = kw.get("sym", cur_sym)
        rng = kw.get("range", cur_range)
        if rng and rng != "all":
            q["range"] = rng
        return "?" + "&".join(f"{k}={quote(str(v))}" for k, v in q.items() if v) if q else "?"

    out = ['<div class="filters">']
    if len(symbols) > 1:
        out.append('<span class="flab">Symbol</span>')
        out.append(f'<a class="chip{"" if cur_sym else " on"}" href="{link(sym="")}">All</a>')
        for sym in symbols:
            on = " on" if cur_sym == sym else ""
            out.append(f'<a class="chip{on}" href="{link(sym=sym)}">{esc(sym)}</a>')
    out.append('<span class="flab">Period</span>')
    for key, label in (("all", "All"), ("mtd", "This month"), ("7d", "7 days"),
                       ("30d", "30 days"), ("90d", "90 days")):
        on = " on" if (cur_range or "all") == key else ""
        out.append(f'<a class="chip{on}" href="{link(range=key)}">{label}</a>')
    if lo or hi:
        span = f"{lo or '...'} to {hi or 'now'}"
        out.append(f'<span class="flab">{esc(span)}</span>')
    out.append("</div>")
    return "".join(out)


def h_streaks(trades, sk, ctx):
    rows = [
        ("Longest winning run", f"{sk['max_wins']} trades"),
        ("Longest losing run", f"{sk['max_losses']} trades"),
        ("Running now", f"{sk['cur_wins']}W / {sk['cur_losses']}L"),
    ]
    extra = []
    for n in (2, 3):
        after = after_losses(trades, n)
        sa = stats(after)
        if sa and sa["n"] >= ctx.min_trades:
            extra.append((f"Taken after {n} straight losses",
                          f"{sa['n']} trades &#183; "
                          f"<span class='{cls(sa['avg_r'])}'>{sa['avg_r']:+.2f}R</span> avg"))
    gb = gaveback(trades)
    if gb:
        sg = stats(gb)
        extra.append(("Reached TP1 then gave it back",
                      f"{len(gb)} trades &#183; "
                      f"<span class='{cls(sg['net'])}'>{esc(ctx.money(sg['net']))}</span>"))
    return ("<h2>Streaks and give-backs</h2><div class='pos'>"
            + "".join(f'<div class="kv"><span>{k}</span><span>{v}</span></div>'
                      for k, v in rows + extra)
            + "</div><div class='note'>A losing run tells you what a cool-off rule would "
              "have to sit through. &ldquo;Gave it back&rdquo; counts trades that reached "
              "TP1 - so the stop stepped to breakeven - and still finished flat or down; "
              "that is what the breakeven rule costs.</div>")


# --------------------------------------------------------------------------
# tiny web server
# --------------------------------------------------------------------------

def day_bounds(args):
    try:
        a, b = str(getattr(args, "day_session", "0,16")).split(",")
        return int(a), int(b)
    except (ValueError, AttributeError):
        return 0, 16


def read_states(args):
    """Just the state files - cheap enough to do on every poll."""
    states = []
    for p in find_states(args.logs, args.state):
        try:
            s = load_state(p)
            retime_state(s, getattr(args, "gmt_offset", None))
            if not args.symbol or args.symbol in s["_name"]:
                states.append(s)
        except OSError:
            continue
    return states


def log_signature(paths):
    """Size and mtime of every log file - changes only when the EA writes."""
    sig = []
    for pattern in paths:
        for p in sorted(glob.glob(pattern)) or [pattern]:
            if p.lower().endswith("_state.txt"):
                continue
            try:
                st = os.stat(p)
                sig.append((p, st.st_size, st.st_mtime))
            except OSError:
                pass
    return tuple(sig)


_COUNT_CACHE = {"sig": None, "n": 0}


def count_trades(args):
    """
    How many completed trades the log holds, cached against the files'
    size and mtime. The live poll runs every few seconds and the logs only
    change when something happens, so this is almost always a dict lookup.
    """
    sig = log_signature(args.logs)
    if sig != _COUNT_CACHE["sig"]:
        events, _ = collect(args.logs, args.csv, quiet=True)
        trades, _, _ = build_trades(events)
        if args.symbol:
            trades = [t for t in trades if t["sym"] == args.symbol]
        _COUNT_CACHE["sig"], _COUNT_CACHE["n"] = sig, len(trades)
    return _COUNT_CACHE["n"]


def gather(args, quiet=True, symbol=None, lo=None, hi=None):
    """Everything the page needs, rebuilt from disk."""
    events, sources = collect(args.logs, args.csv, quiet=quiet)
    ds, de = day_bounds(args)
    retime(events, getattr(args, 'gmt_offset', None), ds, de)
    trades, open_syms, orphans = build_trades(events)
    skips = collect_skips(events)
    all_syms = sorted({t["sym"] for t in trades if t["sym"]})

    sym = symbol if symbol is not None else args.symbol
    trades, skips = apply_filters(trades, skips, sym, lo, hi)
    if sym:
        open_syms = [x for x in open_syms if x == sym]
    return (trades, read_states(args), sources, len(open_syms), orphans,
            skips, all_syms)


def make_ctx(args):
    return Ctx(args.min_trades, args.anon, args.daily_cap_pct, args.total_cap_pct)


def telegram_send(token, chat, text):
    """One-shot Telegram push. Stdlib only; failures are never fatal."""
    import urllib.request, urllib.parse
    data = urllib.parse.urlencode({"chat_id": chat, "text": text}).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage", data=data)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status == 200
    except Exception as exc:
        print(f"  ! telegram: {exc}", file=sys.stderr)
        return False


def watchdog(args):
    """
    Watch the EA's pulse and say something when it stops.

    The EA rewrites its state file every InpHeartbeatMin minutes on a timer, so
    an old file means the EA is down rather than the market being quiet. Fires
    once on the way down and once on the way back up - never repeatedly, which
    is the difference between an alert and noise.
    """
    token, _, chat = args.alert_telegram.partition(":")
    if not token or not chat:
        sys.exit("--alert-telegram expects TOKEN:CHAT_ID")
    limit = args.stale_mins * 60
    down = set()

    def loop():
        while True:
            try:
                for st in read_states(args):
                    name = state_symbol(st)
                    age = time.time() - st["_mtime"]
                    if age > limit and name not in down:
                        down.add(name)
                        telegram_send(token, chat,
                            f"\u26a0\ufe0f EA heartbeat lost\n{name}\n"
                            f"No state write for {fmt_age(age)}.\n"
                            f"{'A position is OPEN and unmanaged.' if state_has_position(st) else 'Flat.'}")
                    elif age <= limit and name in down:
                        down.discard(name)
                        telegram_send(token, chat,
                            f"\u2705 EA heartbeat back\n{name}\nWriting again.")
            except Exception as exc:                  # never kill the thread
                print(f"  ! watchdog: {exc}", file=sys.stderr)
            time.sleep(max(30, min(limit / 2, 300)))

    import threading
    threading.Thread(target=loop, daemon=True).start()
    print(f"Watchdog on: alerting if no heartbeat for {args.stale_mins} min")


def serve(args):
    """Rebuild the report on every request, so a browser refresh shows live data."""
    ctx = make_ctx(args)

    class Handler(BaseHTTPRequestHandler):
        server_version = "ema_report"

        def _send(self, body, ctype="text/html; charset=utf-8", code=200):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            url = urlparse(self.path)
            if args.token:
                given = parse_qs(url.query).get("t", [""])[0]
                # compare in constant time so the token can't be guessed a
                # character at a time off response timing
                import hmac
                if not hmac.compare_digest(given, args.token):
                    self._send(b"forbidden - add ?t=YOURTOKEN", "text/plain", 403)
                    return
            if url.path not in ("/", "/index.html", "/trades.csv", "/live.json"):
                self._send(b"not found", "text/plain", 404)
                return
            try:
                # the live fragment only needs the state files, so skip the
                # whole event log on that route - it runs every few seconds
                if url.path == "/live.json":
                    states = read_states(args)
                    payload = {
                        "html": h_live(states, ctx),
                        "trades": count_trades(args),
                        "ts": datetime.now().strftime("%H:%M:%S"),
                    }
                    self._send(json.dumps(payload).encode("utf-8"),
                               "application/json; charset=utf-8")
                    return

                q = parse_qs(url.query)
                sym = (q.get("symbol", [args.symbol or ""])[0] or "") or None
                rng = q.get("range", [""])[0] or None
                lo, hi = preset_range(rng) if rng else (None, None)
                if q.get("from"):
                    lo = parse_day(q["from"][0])
                if q.get("to"):
                    hi = parse_day(q["to"][0])

                trades, states, sources, still_open, orphans, skips, all_syms = \
                    gather(args, symbol=sym, lo=lo, hi=hi)
                if url.path == "/trades.csv":
                    self._send(trades_csv(trades, ctx).encode("utf-8"),
                               "text/csv; charset=utf-8")
                    return
                live_url = "live.json" + (f"?t={quote(args.token)}" if args.token else "")
                bar = h_filterbar(all_syms, sym, rng, lo, hi)
                page = build_html(trades, states, ctx, sources, still_open, orphans,
                                  poll=(live_url, args.poll, len(trades))
                                       if args.poll > 0 else None,
                                  skips=skips, filterbar=bar)
            except Exception as exc:                       # never take the server down
                page = (f"<!doctype html><meta charset=utf-8><style>{CSS}</style>"
                        f"<body><div class=wrap><h1>Error building the report</h1>"
                        f"<pre>{esc(exc)}</pre></div>")
            self._send(page.encode("utf-8"))

        def log_message(self, *a):                          # keep the console quiet
            pass

    if args.alert_telegram:
        watchdog(args)

    srv = HTTPServer((args.host, args.serve), Handler)
    where = "localhost" if args.host in ("127.0.0.1", "localhost") else args.host
    tok = f"/?t={args.token}" if args.token else "/"
    print(f"Serving on http://{where}:{args.serve}{tok}")
    if args.host == "127.0.0.1":
        print("Bound to localhost only. From your own machine:")
        print(f"    ssh -N -L {args.serve}:localhost:{args.serve} user@this-vps")
        print(f"    then open http://localhost:{args.serve}")
    elif not args.token:
        print("WARNING: bound to a public address with no --token.", file=sys.stderr)
    print("Ctrl-C to stop.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Dashboard for the EA: live state, plus the log analysed by "
                    "session, hour, mode and filter state.")
    ap.add_argument("logs", nargs="+", help=".jsonl or .csv files (globs fine)")
    ap.add_argument("--csv", action="store_true", help="force CSV parsing")
    ap.add_argument("--gmt-offset", type=float, metavar="H", dest="gmt_offset",
                    help="broker's GMT offset (3 = GMT+3). Given, every IST time is "
                         "recomputed here from the broker stamp instead of trusting the "
                         "EA's conversion - use it when InpServerGmtOffset was wrong")
    ap.add_argument("--day-session", default="0,16", metavar="S,E",
                    help="IST day-session bounds used to relabel DAY/EVENING when "
                         "--gmt-offset is given (default 0,16)")
    ap.add_argument("--state", action="append", metavar="FILE",
                    help="_state.txt to read (default: any found beside the logs)")
    ap.add_argument("--min-trades", type=int, default=3,
                    help="hide buckets with fewer trades than this (default 3)")
    ap.add_argument("--symbol", help="only this symbol")
    ap.add_argument("--anon", action="store_true",
                    help="hide money: R, percentages and counts only")
    ap.add_argument("--daily-cap-pct", type=float, default=4.0,
                    help="daily loss cap %% used for the live guard bar (default 4)")
    ap.add_argument("--total-cap-pct", type=float, default=10.0,
                    help="overall loss cap %% used for the live guard bar (default 10)")
    ap.add_argument("--html", metavar="FILE",
                    help="write a self-contained HTML report to FILE instead of printing")
    ap.add_argument("--serve", type=int, metavar="PORT",
                    help="serve the report on this port, rebuilt on every request")
    ap.add_argument("--host", default="127.0.0.1",
                    help="bind address for --serve (default 127.0.0.1; 0.0.0.0 exposes it)")
    ap.add_argument("--from", dest="date_from", metavar="YYYY-MM-DD",
                    help="only trades entered on or after this date")
    ap.add_argument("--to", dest="date_to", metavar="YYYY-MM-DD",
                    help="only trades entered on or before this date")
    ap.add_argument("--alert-telegram", metavar="TOKEN:CHAT_ID",
                    help="ping Telegram when the EA's heartbeat goes stale (serve mode)")
    ap.add_argument("--stale-mins", type=int, default=20, metavar="N",
                    help="minutes without a heartbeat before alerting (default 20)")
    ap.add_argument("--poll", type=float, default=5.0, metavar="SEC",
                    help="how often the Live tab refreshes itself when serving, "
                         "in seconds (default 5; 0 falls back to a full page reload)")
    ap.add_argument("--token", default="",
                    help="require ?t=TOKEN when serving on a public address")
    args = ap.parse_args()

    if args.serve:
        serve(args)
        return

    print("Loading")
    events, sources = collect(args.logs, args.csv)
    ds, de = day_bounds(args)
    moved, relab = retime(events, args.gmt_offset, ds, de)
    if args.gmt_offset is not None:
        print(f"  reconverted {moved} timestamp(s) at GMT{args.gmt_offset:+.1f}"
              + (f", {relab} session label(s) changed" if relab else ""))

    trades, open_syms, orphans = build_trades(events)
    skips = collect_skips(events)
    lo, hi = parse_day(args.date_from), parse_day(args.date_to)
    trades, skips = apply_filters(trades, skips, args.symbol, lo, hi)
    if args.symbol:
        open_syms = [s for s in open_syms if s == args.symbol]
    still_open = len(open_syms)
    if lo or hi:
        print(f"  range {lo or 'start'} .. {hi or 'now'}")

    states = []
    for p in find_states(args.logs, args.state):
        try:
            states.append(load_state(p))
        except OSError:
            pass

    # an empty log with a live state file is the normal case on a fresh start,
    # so that is a dashboard with only a Live tab, not an error
    if not events and not states:
        sys.exit("No events loaded and no state file found.")

    if states:
        print(f"  read {len(states)} state file(s): "
              + ", ".join(os.path.basename(s['_path']) for s in states))

    print(f"\n  {len(trades)} completed trades"
          + (f", {still_open} still open" if still_open else "")
          + (f", {orphans} exits with no entry in the log" if orphans else ""))

    ctx = make_ctx(args)

    if args.html:
        page = build_html(trades, states, ctx, sources, still_open, orphans,
                          skips=skips)
        with open(args.html, "w", encoding="utf-8") as fh:
            fh.write(page)
        print(f"\nWrote {args.html} ({len(page) / 1024:.0f} KB) - open it in any browser.")
        return

    if states:
        live_report(states)

    if not trades:
        sys.exit("\nNothing to report on yet.")

    summary(trades)

    mt = args.min_trades
    table("By IST session", bucket(trades, lambda t: t["session"] or "?"), mt)
    table("By mode", bucket(trades, lambda t: t["mode"] or "?"), mt)
    table("By direction", bucket(trades, lambda t: t["dir"] or "?"), mt)
    table("By IST hour", bucket(trades, lambda t: (lambda h: f"{h:02d}:00" if h is not None else None)(hour_of(t["t_ist"]))), mt)
    table("By day of week", bucket(trades, lambda t: dow_of(t["t_ist"])), mt)
    table("How trades ended", bucket(trades, lambda t: t["exit"]), mt)
    table("By ADX at entry", bucket(trades, lambda t: num_bucket(t, "adx", [0, 15, 20, 25, 30, 40], "ADX")), mt)
    table("By spread at entry", bucket(trades, lambda t: num_bucket(t, "spread", [0, 20, 35, 50, 70], "spread")), mt)
    funnel_report(trades)
    runner_report(trades)
    excursion_report(trades)
    skip_report(skips, trades)
    filter_report(trades, mt)

    print("\nRead it this way: a bucket with a negative Net and enough trades is")
    print("something to stop doing. A filter whose FAIL rows lose money is one")
    print("worth enabling. Small buckets mean nothing - raise --min-trades.")


if __name__ == "__main__":
    main()
