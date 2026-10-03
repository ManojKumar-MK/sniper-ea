#!/usr/bin/env python3
"""
chain_recorder.py - snapshot the NSE stock-option chain through the session.

WHY THIS EXISTS
    ict_options.py models option P&L as delta x underlying_move, with spread and
    theta charged as a flat cost_R. It never sees a real option price, so the
    backtest cannot check the two filters that matter most in live - spread and
    open interest - and is optimistic by an unknown amount.

    That gap is not fixable in code. Angel One serves the CURRENT chain only;
    there is no historical option chain to buy back. Every session this is not
    running is a session that can never be backtested honestly.

    So: record now, backtest properly later.

USAGE
    python3 chain_recorder.py --interval 300             # every 5 min
    python3 chain_recorder.py --interval 300 --top 25    # best-ranked 25 only
    python3 chain_recorder.py --symbols RELIANCE,SBIN    # explicit list

OUTPUT
    ict_data/chains/chain_YYYYMMDD.csv.gz
    ts, symbol, expiry, strike, side, bid, ask, ltp, oi, volume, spot
"""
import argparse, csv, gzip, os, sys, time
from datetime import datetime, date, timedelta

import importlib.util

_spec = importlib.util.spec_from_file_location(
    "ict_options", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ict_options.py"))
ic = importlib.util.module_from_spec(_spec)
sys.modules["ict_options"] = ic
_spec.loader.exec_module(ic)

COLS = ["ts", "symbol", "expiry", "strike", "side", "bid", "ask", "ltp", "oi", "volume", "spot"]


def out_path(day):
    d = os.path.join(ic.CONFIG["data_dir"], "chains")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, f"chain_{day:%Y%m%d}.csv.gz")


def snapshot(api, syms, tokens, window, today, writer):
    """One pass over every symbol. Returns rows written."""
    spots = api.quotes("NSE", [tokens[s] for s in syms], mode="LTP")
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    n = 0
    for s in syms:
        q = spots.get(tokens[s])
        if not q:
            continue
        spot = float(q.get("ltp") or 0)
        if spot <= 0:
            continue
        ch, exp = api.option_chain(s, today)
        if ch is None or ch.empty:
            continue
        strikes = sorted(ch.strike.unique())
        if not strikes:
            continue
        atm = min(strikes, key=lambda k: abs(k - spot))
        ai = strikes.index(atm)
        sel = strikes[max(0, ai - window): ai + window + 1]
        rows = ch[ch.strike.isin(sel)]
        toks = [str(r.token) for r in rows.itertuples()]
        if not toks:
            continue
        qs = api.quotes("NFO", toks)
        for r in rows.itertuples():
            oq = qs.get(str(r.token))
            if not oq:
                continue
            bid, ask = 0.0, 0.0
            try:
                d = oq.get("depth") or {}
                b, a = (d.get("buy") or [{}]), (d.get("sell") or [{}])
                bid, ask = float(b[0].get("price") or 0), float(a[0].get("price") or 0)
            except Exception:
                pass
            writer.writerow({
                "ts": ts, "symbol": s, "expiry": exp, "strike": r.strike,
                "side": "CE" if str(r.symbol).endswith("CE") else "PE",
                "bid": bid, "ask": ask, "ltp": oq.get("ltp") or 0,
                "oi": oq.get("opnInterest") or 0,
                "volume": oq.get("tradeVolume") or oq.get("volume") or 0,
                "spot": spot})
            n += 1
    return n


def main():
    ap = argparse.ArgumentParser(description="Record the option chain through the session")
    ap.add_argument("--interval", type=int, default=300, help="seconds between snapshots")
    ap.add_argument("--window", type=int, default=9, help="strikes each side of ATM")
    ap.add_argument("--top", type=int, default=0, help="keep only the N best-ranked symbols")
    ap.add_argument("--symbols", help="comma list, overrides the universe")
    ap.add_argument("--until", default="15:30", help="stop at this time (IST)")
    a = ap.parse_args()

    ic.load_env()
    today = date.today()
    if today.weekday() >= 5:
        sys.exit("Weekend - nothing to record.")

    api = ic.Angel()
    syms = [x.strip().upper() for x in a.symbols.split(",")] if a.symbols else ic.CONFIG["universe"]
    tokens = {s: api.eq_token(s) for s in syms}
    tokens = {s: t for s, t in tokens.items() if t}
    syms = list(tokens)
    ic.log(f"recorder: {len(syms)} symbols, every {a.interval}s, {a.window} strikes each side")

    path = out_path(today)
    new = not os.path.exists(path)
    # Append, so a restart mid-session continues the same file instead of
    # overwriting the morning's data.
    f = gzip.open(path, "at", newline="", encoding="utf-8")
    w = csv.DictWriter(f, fieldnames=COLS)
    if new:
        w.writeheader()

    total = 0
    try:
        while datetime.now().strftime("%H:%M") < a.until:
            t0 = time.time()
            try:
                n = snapshot(api, syms, tokens, a.window, today, w)
                f.flush()
                total += n
                ic.log(f"snapshot: {n} rows (total {total:,})")
            except Exception as e:
                # A failed snapshot is one missing timestamp, not a reason to
                # lose the rest of the day.
                ic.log(f"snapshot failed: {e}")
            time.sleep(max(5, a.interval - (time.time() - t0)))
    except KeyboardInterrupt:
        ic.log("interrupted")
    finally:
        f.close()
        ic.log(f"recorder done: {total:,} rows -> {path}")
        ic.telegram(f"[REC] chain recorder finished: {total:,} rows for {today}")


if __name__ == "__main__":
    main()
