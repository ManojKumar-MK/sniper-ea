#!/usr/bin/env python3
"""
bhavcopy.py - historical NSE F&O daily data, per strike.

WHAT THIS CORRECTS
    I previously recorded that historical option data "cannot be back-filled"
    because Angel One serves only the current chain. That is true of Angel, and
    false of NSE: the F&O bhavcopy is published daily, free, and archived for
    years. Per contract per day it gives OHLC, settlement price, the underlying
    price, OPEN INTEREST, change in OI, traded volume and the lot size.

WHAT IT CLOSES, AND WHAT IT DOES NOT
    Closes: the backtest can now apply the SAME liquidity filter live uses
            (min_oi_lots), using the OI that genuinely existed that day, and
            can price a strike from a real settlement price instead of a
            modelled one.
    Does not close: BID/ASK. Bhavcopy is end-of-day, so intraday spread still
            has to be recorded forward with chain_recorder.py. Spread is the
            single largest cost in this system, so the recorder is still
            needed - it is just no longer the only route to everything.

BONUS: a date with no bhavcopy is an NSE holiday. That is the trading calendar
    the live loop was missing, derived rather than hard-coded.

USAGE
    python3 bhavcopy.py --days 180              # download + cache
    python3 bhavcopy.py --days 180 --report     # ... and summarise what arrived
"""
import argparse, io, os, sys, time, zipfile
from datetime import date, timedelta

import pandas as pd
import requests

URL = ("https://nsearchives.nseindia.com/content/fo/"
       "BhavCopy_NSE_FO_0_0_0_{d:%Y%m%d}_F_0000.csv.zip")
HDRS = {"User-Agent": "Mozilla/5.0", "Accept": "*/*"}
DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ict_data", "bhav")

# The columns we keep. STO = stock options; STF = stock futures, ignored.
KEEP = ["TradDt", "TckrSymb", "XpryDt", "StrkPric", "OptnTp", "ClsPric", "SttlmPric",
        "UndrlygPric", "OpnIntrst", "TtlTradgVol", "NewBrdLotQty"]


def path_for(d):
    os.makedirs(DIR, exist_ok=True)
    return os.path.join(DIR, f"fo_{d:%Y%m%d}.parquet")


def holiday_path():
    os.makedirs(DIR, exist_ok=True)
    return os.path.join(DIR, "no_bhavcopy.txt")


def _known_missing():
    p = holiday_path()
    return set(open(p).read().split()) if os.path.exists(p) else set()


def _mark_missing(d):
    with open(holiday_path(), "a") as f:
        f.write(f"{d:%Y-%m-%d}\n")


def fetch_day(d, session=None, retries=2):
    """One session's F&O bhavcopy, cached as parquet. None on a holiday."""
    if d.weekday() >= 5:
        return None
    p = path_for(d)
    if os.path.exists(p):
        return pd.read_parquet(p)
    if f"{d:%Y-%m-%d}" in _known_missing():
        return None
    s = session or requests.Session()
    for attempt in range(retries + 1):
        try:
            r = s.get(URL.format(d=d), headers=HDRS, timeout=45)
            if r.status_code == 404:
                _mark_missing(d)          # holiday - remember, do not re-ask
                return None
            r.raise_for_status()
            z = zipfile.ZipFile(io.BytesIO(r.content))
            df = pd.read_csv(z.open(z.namelist()[0]))
            df = df[df.FinInstrmTp == "STO"][KEEP].copy()
            df["StrkPric"] = pd.to_numeric(df.StrkPric, errors="coerce")
            for c in ("ClsPric", "SttlmPric", "UndrlygPric", "OpnIntrst",
                      "TtlTradgVol", "NewBrdLotQty"):
                df[c] = pd.to_numeric(df[c], errors="coerce")
            df.to_parquet(p, index=False)
            return df
        except Exception as e:
            if attempt == retries:
                print(f"  {d}: {e}", file=sys.stderr)
                return None
            time.sleep(2 * (attempt + 1))
    return None


def load_range(start, end, quiet=False):
    """All sessions in [start, end]. Returns one DataFrame."""
    s = requests.Session()
    out, d, got, miss = [], start, 0, 0
    while d <= end:
        df = fetch_day(d, s)
        if df is not None and len(df):
            out.append(df); got += 1
        elif d.weekday() < 5:
            miss += 1
        d += timedelta(days=1)
        if not quiet and (got + miss) % 20 == 0 and (got + miss):
            print(f"  {got} sessions, {miss} holidays/missing", flush=True)
    if not quiet:
        print(f"  done: {got} sessions, {miss} weekday gaps (NSE holidays)")
    return pd.concat(out, ignore_index=True) if out else pd.DataFrame(columns=KEEP)


def liquidity_index(df):
    """(symbol, date, strike, side) -> (oi_lots, volume).

    This is what lets the BACKTEST apply the filter live already applies. Up to
    now it traded strikes that may have had no open interest at all, and was
    optimistic by exactly that set of trades.
    """
    idx = {}
    for r in df.itertuples():
        lot = r.NewBrdLotQty or 0
        idx[(r.TckrSymb, str(r.TradDt)[:10], float(r.StrkPric), r.OptnTp)] = (
            (r.OpnIntrst / lot) if lot else 0.0, r.TtlTradgVol or 0.0)
    return idx


def main():
    ap = argparse.ArgumentParser(description="Download and cache NSE F&O bhavcopy")
    ap.add_argument("--days", type=int, default=180)
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    end = date.today()
    start = end - timedelta(days=a.days)
    print(f"bhavcopy {start} .. {end}")
    df = load_range(start, end)
    if df.empty:
        sys.exit("nothing downloaded")
    print(f"\n{len(df):,} option rows, {df.TckrSymb.nunique()} underlyings, "
          f"{df.TradDt.nunique()} sessions")
    if a.report:
        print(f"\ncolumns: {list(df.columns)}")
        print(f"\nOI per strike (lots), all symbols:")
        lots = (df.OpnIntrst / df.NewBrdLotQty.replace(0, pd.NA)).dropna()
        for q in (10, 25, 50, 75, 90):
            print(f"   p{q:<3d} {lots.quantile(q / 100):10,.0f}")
        thr = 50
        print(f"\n   share of strikes with >= {thr} lots OI: {100 * (lots >= thr).mean():.1f}%")
        print(f"   -> that is the share the backtest's min_oi_lots filter would KEEP")
        print(f"\nmost liquid underlyings by median OI lots:")
        d2 = df.assign(lots=df.OpnIntrst / df.NewBrdLotQty.replace(0, pd.NA))
        print(d2.groupby("TckrSymb").lots.median().sort_values(ascending=False)
              .head(12).round(0).to_string())


if __name__ == "__main__":
    main()
