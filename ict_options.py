#!/usr/bin/env python3
"""
ict_options.py - intraday stock-option picker driven by ICT confluence on the UNDERLYING.

Signals are built on the stock's own 5-minute chart (the option is only the execution vehicle):
  HTF context (daily + 1H)  ->  liquidity sweep  ->  MSS with displacement  ->  FVG / OB retrace entry
then the system picks a liquid ATM / 1-ITM CE or PE, sizes it from the underlying stop, and manages
the exit on the underlying's stop / target levels.

Broker: Angel One SmartAPI (free data + execution).

MODES
  python ict_options.py demo                          # synthetic data, no API - checks the engine runs
  python ict_options.py backtest --days 60            # 5m history from SmartAPI, results in R on the underlying
  python ict_options.py backtest --csv-dir ./csv      # offline: files named SYMBOL.csv (datetime,open,high,low,close,volume)
  python ict_options.py paper                         # live data, simulated option fills at real bid/ask
  python ict_options.py live --i-understand-the-risk  # real orders (also needs CONFIG["live_trading"] = True)

SETUP
  pip install smartapi-python pyotp pandas numpy requests logzero websocket-client
  env: ANGEL_API_KEY, ANGEL_CLIENT, ANGEL_PIN, ANGEL_TOTP_SECRET   (optional: TG_TOKEN, TG_CHAT for Telegram)
  Run paper/live from the machine whose static IP is whitelisted on your SmartAPI app (SEBI rule since Apr 2026).
  Start it each trading day before 09:15 (cron); it logs in fresh, trades, squares off and exits.
"""
import argparse, csv, json, math, os, sys, time
from dataclasses import dataclass, field
from datetime import datetime, date, time as dtime, timedelta

import numpy as np
import pandas as pd

# ============================================================================ CONFIG
CONFIG = {
    "universe": ["RELIANCE", "HDFCBANK", "ICICIBANK", "SBIN", "AXISBANK", "KOTAKBANK", "INFY", "TCS",
                 "HCLTECH", "LT", "BHARTIARTL", "ITC", "BAJFINANCE", "MARUTI", "M&M", "SUNPHARMA",
                 "TATASTEEL", "JSWSTEEL", "HINDALCO", "ADANIENT", "TITAN", "BEL", "HAL", "DLF", "INDUSINDBK"],
    "tf_min": 5,
    # sessions (IST)
    "market_open": "09:15", "or_end": "09:30",             # opening range = 09:15-09:30
    "windows": [("09:30", "10:45"), ("13:30", "14:45")],   # setups only form inside these
    "last_entry": "14:50", "square_off": "15:15",
    # structure
    "swing_k": 2,                 # fractal pivot strength (bars each side)
    "atr_len": 14,
    "sweep_reclaim_bars": 2,      # a pierced level must be reclaimed within N bars to count as a sweep
    "eq_tol_atr": 0.10,           # equal highs/lows tolerance
    "mss_window": 8,              # bars after the sweep allowed for the MSS
    "disp_atr": 1.0,              # min displacement candle body (x ATR) for a valid MSS
    "disp_strong_atr": 1.5,       # strong displacement bonus
    "fvg_min_atr": 0.10,          # ignore FVGs smaller than this
    "fvg_wait": 2,                # bars after MSS to wait for an FVG before falling back to OB
    "entry_at": "ce",             # "ce" = 50% of FVG/OB, "edge" = near edge
    "entry_valid_bars": 10,       # pending entry expires after N bars
    "stop_buf_atr": 0.10,
    "max_risk_atr": 2.5,          # skip if stop distance is wider than this
    "min_rr": 1.5, "default_rr": 2.0,
    # confluence
    "min_score": 6,               # out of 9 when no indicator components are on
    "min_score_frac": 0.0,        # if > 0, min_score becomes this FRACTION of the max.
                                  # Switching indicators on raises the max from 9 to 15,
                                  # so a fixed 6 is a different filter in each case and
                                  # the two cannot be compared. A fraction can.
    "reject_against_daily": True,
    "max_trades_per_stock": 1, "max_trades_per_day": 4, "max_open": 2,
    # options
    "expiry_roll_days": 3,        # within N days of expiry use next month
    "strike_pref": ["ITM1", "ATM"],          # legacy picker only
    "delta_est": {"ITM1": 0.62, "ATM": 0.50},  # legacy picker only
    # --- strike picker ---
    "picker": "ev",               # "ev" = score every strike on expected rupees.
                                  # "legacy" = the old first-match-by-label rule.
    "strike_window": 4,           # how many strikes each side of ATM to consider
    "min_delta": 0.35,            # below this the option barely follows the underlying
    "max_delta": 0.85,            # above this you are paying intrinsic for no leverage
    "max_iv": 0.0,                # skip if IV above this (0 = off). Buying rich IV intraday
    "max_theta_frac": 0.25,       # reject if a day of theta exceeds this share of the target
    "hold_hours": 3.0,            # typical intraday hold, used for the theta charge
    "min_edge_ratio": 1.5,        # expected gross must beat round-trip cost by this much
    "min_volume": 0,              # today's traded contracts; 0 = rely on OI only
    # --- extra score components (indicators) ---
    # Each adds 1 to the confluence score when true. They are SCORE components,
    # not gates, and that is deliberate: frequency is already the binding
    # constraint at 0.46 trades/day, and a gate can only make it worse. A score
    # lets min_score decide how selective to be, so the same indicators can be
    # run loose (wide net, rank hard) or tight.
    "sc_vol": False,              # volume surge on the displacement bar
    "sc_vol_mult": 1.5,           # ... >= this x the 20-bar average
    "sc_ema": False,              # price the right side of EMA(sc_ema_len)
    "sc_ema_len": 20,
    "sc_emastack": False,         # EMA fast above/below slow, in trade direction
    "sc_ema_fast": 9,
    "sc_ema_slow": 21,
    "sc_rsi": False,              # RSI has room left in the trade direction
    "sc_rsi_len": 14,
    "sc_rsi_hi": 70.0,            # longs need RSI below this, shorts above 100-this
    "sc_vwap": False,             # price the right side of session VWAP
    "sc_atr": False,              # volatility expanding vs its own average
    "sc_atr_mult": 1.1,
    # --- STAGE 1: pick the stocks first ---
    # "fixed"  = run every name in `universe`, as before.
    # "ranked" = score every name each morning on information available by
    #            09:30 and run the engine on the best `rank_top_n` only.
    # Ranking a SMALL universe reduces frequency, which is the wrong direction
    # for a daily target. It earns its keep by letting the universe GROW: screen
    # 150 names down to the 15 that are actually moving today, instead of
    # watching the same 25 whether or not anything is happening in them.
    # --- signal model ---
    # "ict" = sweep -> MSS -> FVG/OB. "orb" = opening-range breakout.
    # The ICT model returned 16 of 162 grid combinations positive out of
    # sample - worse than coin-flip - with the 20 best in-sample combinations
    # averaging -Rs6,144 out of sample. A second model shares the harness so
    # it can be judged on the same terms rather than on a fresh set of
    # assumptions.
    "model": "ict",
    "orb_max_per_day": 1,          # breakouts per stock per day
    "orb_one_way": True,           # do not take the opposite break of the same range
    # MEASURED, not guessed. Over 3,000 real symbol-sessions the 09:15-09:30
    # range is 5.2x the 5-MINUTE ATR at the median (p5 2.8, p95 11.5) - an
    # opening range spans three bars, so of course it dwarfs a single-bar ATR.
    # The first version of these bounds was 0.3-2.0 and kept 0.6% of sessions,
    # which is why ORB produced 131 setups in four months and looked dead.
    "orb_min_rng_atr": 2.5,        # ~p5: below this the range is noise
    "orb_max_rng_atr": 9.0,        # ~p90: above it the move has already happened
    "orb_close_beyond_atr": 0.1,   # "clean break" score point
    # A RANGE stop risks the whole range - ~5 ATR at the median - against
    # max_risk_atr of 2.5, so it is rejected as "stop too wide" almost always.
    # The ATR stop is the default for that reason; "range" is kept for testing
    # and needs max_risk_atr raised to be usable at all.
    "orb_stop": "atr",             # "atr" = orb_stop_atr x ATR, "range" = far side of OR
    "orb_stop_atr": 1.0,
    "universe_mode": "fixed",
    "rank_top_n": 10,
    "rank_w_atr": 1.0,       # prior ATR as % of price - movement to pay costs with
    "rank_w_orr": 1.0,       # opening-range size as % of price - today's energy
    "rank_w_orv": 1.0,       # opening-range volume vs its own 20-day average
    "rank_w_gap": 0.5,       # overnight gap, absolute
    "rank_w_rs": 1.0,        # move vs the universe median - relative strength
    "rank_min_atr_pct": 0.0, # hard floor: skip names quieter than this (0 = off)
    "min_oi_lots": 50,            # min open interest (in lots) on the chosen strike
    "max_spread_pct": 1.5,        # (ask-bid)/mid %
    "risk_per_trade": 2000.0,     # Rs risked per trade (underlying stop translated via delta)
    "max_lots": 3,
    "daily_loss_limit": 5000.0,
    "limit_buffer_ticks": 2,
    # runtime
    "poll_sec": 3,
    "live_trading": False,
    "data_dir": "./ict_data",
    # unattended operation
    "require_telegram": True,   # paper/live refuse to start without a working bot
    "heartbeat_min": 30,        # "still alive" ping; 0 = off
    "max_loop_errors": 20,      # consecutive failed cycles before giving up and flattening
    # backtest realism
    "cost_R": 0.12,             # round-trip cost as a fraction of risk_per_trade. CALIBRATE THIS
                                # from real contract notes: brokerage + STT + exchange + GST +
                                # the bid/ask you actually cross. 0.12 of Rs2,000 = Rs240/trade.
    "bt_apply_caps": True,      # enforce max_open / max_trades_per_day / daily_loss_limit in the
                                # backtest, as live_loop does. Off = count setups the live system
                                # would have refused, which flatters the result.
}
SCRIP_MASTER_URL = "https://margincalculator.angelbroking.com/OpenAPI_File/files/OpenAPIScripMaster.json"


def load_env(path=".env"):
    """Read KEY=VALUE from a .env beside the script, without a dependency.

    Credentials belong in a gitignored file, never on a command line (they end
    up in shell history and in `ps`) and never pasted into a chat. Real
    environment variables already set are NOT overwritten, so a VPS using
    setx/systemd keeps working untouched.
    """
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), path)
    if not os.path.exists(p):
        return
    loaded = []
    for raw in open(p, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip().strip('"').strip("'")
        if k and not os.getenv(k):
            os.environ[k] = v
            loaded.append(k)
    if loaded:
        log(f".env loaded: {', '.join(loaded)}")


def T(s):
    h, m = map(int, s.split(":"))
    return dtime(h, m)


def log(msg):
    line = f"{datetime.now():%Y-%m-%d %H:%M:%S} | {msg}"
    print(line, flush=True)
    os.makedirs(CONFIG["data_dir"], exist_ok=True)
    with open(os.path.join(CONFIG["data_dir"], f"log_{date.today():%Y%m%d}.txt"), "a") as f:
        f.write(line + "\n")


def telegram(msg, retries=3):
    """Best-effort push. Returns True if Telegram accepted it.

    On a VPS this is the only window into the system, so it retries, splits
    messages over Telegram's 4096-character limit, and reports its own
    failures to the log rather than swallowing them.
    """
    tok, chat = os.getenv("TG_TOKEN"), os.getenv("TG_CHAT")
    if not tok or not chat:
        return False
    import requests
    ok = True
    # 4096 is the hard limit; 3900 leaves room for the part counter.
    parts = [msg[i:i + 3900] for i in range(0, len(msg), 3900)] or [""]
    for idx, part in enumerate(parts):
        body = part if len(parts) == 1 else f"({idx + 1}/{len(parts)})\n{part}"
        for attempt in range(retries):
            try:
                r = requests.post(f"https://api.telegram.org/bot{tok}/sendMessage",
                                  json={"chat_id": chat, "text": body,
                                        "disable_web_page_preview": True}, timeout=10)
                if r.status_code == 200:
                    break
                # 429 carries retry_after; anything else is worth one more try
                wait = 2 ** attempt
                try:
                    wait = max(wait, int(r.json().get("parameters", {}).get("retry_after", 0)))
                except Exception:
                    pass
                log(f"telegram HTTP {r.status_code}, retry in {wait}s: {r.text[:200]}")
                time.sleep(wait)
            except Exception as e:
                log(f"telegram send failed ({attempt + 1}/{retries}): {e}")
                time.sleep(2 ** attempt)
        else:
            ok = False
            log("telegram GAVE UP on a message - it is not reaching you")
    return ok


def telegram_preflight(mode):
    """Refuse to run unattended with a broken alert path.

    A typo in TG_CHAT used to mean total silence, which is indistinguishable
    from a quiet market - the worst possible failure on a machine nobody is
    watching.
    """
    if not CONFIG["require_telegram"]:
        return
    tok, chat = os.getenv("TG_TOKEN"), os.getenv("TG_CHAT")
    if not tok or not chat:
        sys.exit("TG_TOKEN / TG_CHAT not set. Set them, or CONFIG['require_telegram'] = False "
                 "to run blind on purpose.")
    if not telegram(f"[{mode}] alert path OK - {datetime.now():%Y-%m-%d %H:%M} - "
                    f"starting on {os.uname().nodename if hasattr(os, 'uname') else 'host'}"):
        sys.exit("Telegram is configured but the test message failed. Fix it before trading "
                 "unattended, or set CONFIG['require_telegram'] = False.")


class SingleInstance:
    """A second copy of this process would place a second set of orders.

    cron restarts, a manual run on top of a scheduled one, or a tmux session
    nobody remembered are all ordinary ways that happens.
    """
    def __init__(self, name="ict_options"):
        os.makedirs(CONFIG["data_dir"], exist_ok=True)
        self.path = os.path.join(CONFIG["data_dir"], f"{name}.pid")

    def acquire(self):
        if os.path.exists(self.path):
            try:
                old = int(open(self.path).read().strip())
            except Exception:
                old = None
            if old and old != os.getpid():
                alive = True
                try:
                    os.kill(old, 0)          # signal 0 only tests existence
                except OSError:
                    alive = False
                except Exception:
                    alive = False
                if alive:
                    sys.exit(f"Already running as PID {old} ({self.path}). Refusing to start a second copy.")
            log(f"clearing stale pid file {self.path}")
        with open(self.path, "w") as f:
            f.write(str(os.getpid()))

    def release(self):
        try:
            if os.path.exists(self.path) and int(open(self.path).read().strip()) == os.getpid():
                os.remove(self.path)
        except Exception:
            pass


def append_csv(name, row):
    os.makedirs(CONFIG["data_dir"], exist_ok=True)
    path = os.path.join(CONFIG["data_dir"], name)
    new = not os.path.exists(path)
    with open(path, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(row.keys()))
        if new:
            w.writeheader()
        w.writerow(row)


# ============================================================================ HTF CONTEXT
def structure_bias(h, l, c, k=2):
    """+1 / -1 / 0 = direction of the last break of a confirmed fractal swing."""
    bias, sh, sl = 0, None, None
    for i in range(len(c)):
        j = i - k
        if j >= k:
            if h[j] == max(h[j - k:j + k + 1]):
                sh = h[j]
            if l[j] == min(l[j - k:j + k + 1]):
                sl = l[j]
        if sh is not None and c[i] > sh:
            bias, sh = 1, None
        elif sl is not None and c[i] < sl:
            bias, sl = -1, None
    return bias


def unmitigated_fvgs(h, l, lookback=30):
    """Daily FVGs not yet traded through. Returns [(dir, bottom, top)]."""
    out, n = [], len(h)
    for i in range(max(2, n - lookback), n):
        if l[i] > h[i - 2]:
            bot, top = h[i - 2], l[i]
            if not any(l[j] <= bot for j in range(i + 1, n)):
                out.append((1, bot, top))
        elif h[i] < l[i - 2]:
            bot, top = h[i], l[i - 2]
            if not any(h[j] >= top for j in range(i + 1, n)):
                out.append((-1, bot, top))
    return out


def build_context(daily, day):
    d = daily[daily.index.date < day].tail(60)
    if len(d) < 22:
        return None
    h, l, c = d["high"].values, d["low"].values, d["close"].values
    return {
        "pdh": h[-1], "pdl": l[-1], "pdc": c[-1],
        "pwh": h[-5:].max(), "pwl": l[-5:].min(),
        "pd_eq": (h[-1] + l[-1]) / 2,
        "daily_bias": structure_bias(h, l, c, 2),
        "daily_fvgs": unmitigated_fvgs(h, l, 30),
    }


def wilder_atr(df, n):
    pc = df["close"].shift(1)
    tr = pd.concat([df["high"] - df["low"], (df["high"] - pc).abs(), (df["low"] - pc).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / n, adjust=False).mean()


def resample_1h(df5):
    r = df5.resample("60min", origin="start_day", offset="15min").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last"}).dropna()
    return r


def resample_daily(df5):
    return df5.resample("1D").agg({"open": "first", "high": "max", "low": "min", "close": "last",
                                   "volume": "sum"}).dropna()


# ============================================================================ ENGINE
@dataclass
class Level:
    name: str
    price: float
    side: int            # +1 = buy-side liquidity (above highs), -1 = sell-side (below lows)
    htf: bool
    state: str = "live"  # live / pierced / swept / broken
    pierce_i: int = -1
    ext: float = 0.0


@dataclass
class Sweep:
    dir: int             # expected move: +1 after sell-side sweep, -1 after buy-side sweep
    i: int
    ext: float
    names: list
    htf: bool
    ref: float           # structure level whose break = MSS
    mss_i: int = -1
    disp: float = 0.0
    done: bool = False


@dataclass
class Setup:
    sym: str
    dir: int
    i: int
    t: datetime
    kind: str
    entry: float
    stop: float
    target: float
    tgt_name: str
    score: int
    notes: str
    status: str = "pending"   # pending/rejected/filled/closed/expired/missed/invalid
    reason: str = ""
    fill_t: datetime = None
    exit_t: datetime = None
    exit_px: float = 0.0
    exit_reason: str = ""

    @property
    def risk(self):
        return abs(self.entry - self.stop)

    @property
    def r(self):
        return (self.exit_px - self.entry) * self.dir / self.risk if self.risk else 0.0


class DayEngine:
    """One stock, one session. Feed completed 5m bars with on_bar(); in tick mode, prices via on_price()."""

    def __init__(self, sym, day, ctx, hist5, cfg=CONFIG, tick_mode=False):
        self.sym, self.day, self.ctx, self.cfg, self.tick_mode = sym, day, ctx, cfg, tick_mode
        self.hist5 = hist5[hist5.index.date < day].tail(400) if hist5 is not None else None
        a = wilder_atr(self.hist5, cfg["atr_len"]) if self.hist5 is not None and len(self.hist5) > 20 else None
        self.atr = float(a.iloc[-1]) if a is not None else None
        self.prev_c = float(self.hist5["close"].iloc[-1]) if self.hist5 is not None and len(self.hist5) else None
        self.bars, self.levels, self.sweeps, self.setups = [], [], [], []
        # Rolling series for the indicator score components. Seeded from prior
        # history so an EMA is not cold at 09:15 - a 20-period EMA built from
        # three bars of the current session is noise wearing an indicator's name.
        self.vwap_pv = 0.0
        self.vwap_v = 0.0
        self._ema = {}
        self._rsi_state = None
        self._atr_hist = []
        if self.hist5 is not None and len(self.hist5):
            closes = self.hist5["close"].astype(float).tolist()
            for ln in (cfg["sc_ema_len"], cfg["sc_ema_fast"], cfg["sc_ema_slow"]):
                k = 2.0 / (ln + 1.0)
                e = closes[0]
                for c0 in closes[1:]:
                    e = c0 * k + e * (1 - k)
                self._ema[ln] = e
            self._rsi_state = self._seed_rsi(closes, cfg["sc_rsi_len"])
        self.vols = []
        self.sw_hi, self.sw_lo = [], []   # confirmed swings (idx, price)
        self.or_done = False
        self.or_hi = self.or_lo = None
        self.orb_fired = 0
        self.orb_dir = 0
        self.trades_taken = 0
        self.allow_new = True             # runner can switch off (daily caps)
        self._h1_cache = (None, 0)
        if ctx:
            for nm, p, s in (("PDH", ctx["pdh"], 1), ("PDL", ctx["pdl"], -1),
                             ("PWH", ctx["pwh"], 1), ("PWL", ctx["pwl"], -1)):
                if not any(abs(L.price - p) < 1e-9 and L.side == s for L in self.levels):
                    self.levels.append(Level(nm, p, s, True))

    # ---------------- indicator helpers
    @staticmethod
    def _seed_rsi(closes, n):
        """Wilder RSI state (avg gain, avg loss) from history, or None."""
        if len(closes) < n + 1:
            return None
        g = l = 0.0
        for i in range(1, n + 1):
            d = closes[i] - closes[i - 1]
            g += max(d, 0.0); l += max(-d, 0.0)
        ag, al = g / n, l / n
        for i in range(n + 1, len(closes)):
            d = closes[i] - closes[i - 1]
            ag = (ag * (n - 1) + max(d, 0.0)) / n
            al = (al * (n - 1) + max(-d, 0.0)) / n
        return [ag, al, closes[-1]]

    def _update_indicators(self, b):
        c, h, l = b["close"], b["high"], b["low"]
        v = float(b.get("volume") or 0.0)
        cfg = self.cfg
        for ln in (cfg["sc_ema_len"], cfg["sc_ema_fast"], cfg["sc_ema_slow"]):
            k = 2.0 / (ln + 1.0)
            self._ema[ln] = c if ln not in self._ema else c * k + self._ema[ln] * (1 - k)
        if self._rsi_state is not None:
            ag, al, pc = self._rsi_state
            d = c - pc
            nn = cfg["sc_rsi_len"]
            self._rsi_state = [(ag * (nn - 1) + max(d, 0.0)) / nn,
                               (al * (nn - 1) + max(-d, 0.0)) / nn, c]
        # Session VWAP uses the typical price, and only today's bars - a VWAP
        # carried over from yesterday is not a VWAP.
        if v > 0:
            self.vwap_pv += ((h + l + c) / 3.0) * v
            self.vwap_v += v
        self.vols.append(v)

    def _rsi(self):
        if not self._rsi_state:
            return None
        ag, al, _ = self._rsi_state
        if al <= 0:
            return 100.0
        rs = ag / al
        return 100.0 - 100.0 / (1.0 + rs)

    def _vwap(self):
        return (self.vwap_pv / self.vwap_v) if self.vwap_v > 0 else None

    def _vol_surge(self, lookback=20):
        """Last bar's volume against the average of the ones before it."""
        v = [x for x in self.vols if x > 0]
        if len(v) < 5:
            return None
        cur = v[-1]
        base = v[-(lookback + 1):-1]
        if not base:
            return None
        avg = sum(base) / len(base)
        return (cur / avg) if avg > 0 else None

    def _indicator_score(self, d, entry):
        """Returns (points, notes). Each component is worth 1 and is OFF by default."""
        cfg, pts, notes = self.cfg, 0, []
        if cfg["sc_vol"]:
            vs = self._vol_surge()
            if vs is not None and vs >= cfg["sc_vol_mult"]:
                pts += 1; notes.append(f"vol {vs:.1f}x")
        if cfg["sc_ema"]:
            e = self._ema.get(cfg["sc_ema_len"])
            if e and ((d == 1 and entry > e) or (d == -1 and entry < e)):
                pts += 1; notes.append(f"EMA{cfg['sc_ema_len']}")
        if cfg["sc_emastack"]:
            ef, es = self._ema.get(cfg["sc_ema_fast"]), self._ema.get(cfg["sc_ema_slow"])
            if ef and es and ((d == 1 and ef > es) or (d == -1 and ef < es)):
                pts += 1; notes.append(f"EMA{cfg['sc_ema_fast']}/{cfg['sc_ema_slow']}")
        if cfg["sc_rsi"]:
            r = self._rsi()
            # Room LEFT in the direction, not "RSI agrees" - buying into an
            # already-overbought print is the thing worth avoiding.
            if r is not None and ((d == 1 and r < cfg["sc_rsi_hi"]) or
                                  (d == -1 and r > 100 - cfg["sc_rsi_hi"])):
                pts += 1; notes.append(f"RSI {r:.0f}")
        if cfg["sc_vwap"]:
            w = self._vwap()
            if w and ((d == 1 and entry > w) or (d == -1 and entry < w)):
                pts += 1; notes.append("VWAP")
        if cfg["sc_atr"]:
            if self.atr and len(self._atr_hist) >= 10:
                avg = sum(self._atr_hist[-20:]) / len(self._atr_hist[-20:])
                if avg > 0 and self.atr / avg >= cfg["sc_atr_mult"]:
                    pts += 1; notes.append("ATR exp")
        return pts, notes

    @staticmethod
    def score_max(cfg=CONFIG):
        """Per-MODEL maximum, plus whichever indicator components are on.

        These scales differ: ICT can reach 9 from its own confluence, ORB only
        5. A single hardcoded 9 made min_score=6 unreachable for ORB, so every
        breakout was rejected on score and the model looked like it produced
        nothing. Any new model must add its base here or it will fail the same
        silent way.
        """
        base = {"ict": 9, "orb": 5}.get(cfg["model"], 9)
        return base + sum(1 for k in ("sc_vol", "sc_ema", "sc_emastack", "sc_rsi",
                                      "sc_vwap", "sc_atr") if cfg[k])

    # ---------------- helpers
    def _tc(self, b):  # bar close time
        return b["t"] + timedelta(minutes=self.cfg["tf_min"])

    def _in_window(self, t):
        return any(T(a) <= t.time() <= T(b) for a, b in self.cfg["windows"])

    def _h1_bias(self):
        n = len(self.bars)
        if self._h1_cache[0] is not None and self._h1_cache[1] == n // 12:
            return self._h1_cache[0]
        today = pd.DataFrame(self.bars).set_index("t")[["open", "high", "low", "close"]]
        base = pd.concat([self.hist5[["open", "high", "low", "close"]], today]) if self.hist5 is not None else today
        h1 = resample_1h(base).iloc[:-1]  # drop the in-progress hour
        b = structure_bias(h1["high"].values, h1["low"].values, h1["close"].values, 2) if len(h1) > 6 else 0
        self._h1_cache = (b, n // 12)
        return b

    # ---------------- main
    def on_bar(self, b):
        """b = dict(t, open, high, low, close). Returns list of events."""
        cfg, ev = self.cfg, []
        self.bars.append(b)
        i = len(self.bars) - 1
        o, h, l, c = b["open"], b["high"], b["low"], b["close"]
        self._update_indicators(b)
        # ATR update
        tr = h - l if self.prev_c is None else max(h - l, abs(h - self.prev_c), abs(l - self.prev_c))
        self.atr = tr if self.atr is None else self.atr + (tr - self.atr) / cfg["atr_len"]
        self._atr_hist.append(self.atr)   # for the sc_atr expansion test
        self.prev_c = c
        atr = self.atr

        if i == 0:  # gap beyond HTF levels -> not a sweep candidate
            for L in self.levels:
                if (L.side == 1 and o > L.price) or (L.side == -1 and o < L.price):
                    L.state = "broken"

        # 1) manage existing setups with this bar's range
        if not self.tick_mode:
            ev += self._check_prices(h, l, self._tc(b), o)
        for s in self.setups:
            if s.status == "pending" and i - s.i > cfg["entry_valid_bars"]:
                s.status, s.reason = "expired", "no retrace"
                ev.append({"type": "expired", "setup": s})
        if self._tc(b).time() >= T(cfg["square_off"]):
            ev += self.square_off(c, self._tc(b))

        # 2) liquidity sweeps
        for L in self.levels:
            if L.state in ("swept", "broken"):
                continue
            beyond = h > L.price if L.side == 1 else l < L.price
            back = c < L.price if L.side == 1 else c > L.price
            if L.state == "live" and beyond:
                L.ext = h if L.side == 1 else l
                if back:
                    L.state = "swept"
                else:
                    L.state, L.pierce_i = "pierced", i
            elif L.state == "pierced":
                L.ext = max(L.ext, h) if L.side == 1 else min(L.ext, l)
                if back:
                    L.state = "swept"
                elif i - L.pierce_i >= cfg["sweep_reclaim_bars"]:
                    L.state = "broken"
            if L.state == "swept":
                self._register_sweep(-L.side, i, L)

        # 3) MSS -> FVG/OB -> setup
        for sw in self.sweeps:
            if sw.done:
                continue
            if sw.mss_i < 0:
                if i - sw.i > cfg["mss_window"]:
                    sw.done = True
                    continue
                if sw.dir == 1 and l < sw.ext:
                    sw.ext = l
                if sw.dir == -1 and h > sw.ext:
                    sw.ext = h
                broke = c > sw.ref if sw.dir == 1 else c < sw.ref
                if broke and i > sw.i:
                    seg = self.bars[sw.i:i + 1]
                    bodies = [(x["close"] - x["open"]) * sw.dir for x in seg]
                    sw.disp = max(bodies) / atr if atr else 0
                    if sw.disp >= cfg["disp_atr"]:
                        sw.mss_i = i
                    else:
                        sw.done = True  # weak break, no displacement
                        continue
            if sw.mss_i >= 0:
                st = self._make_setup(sw, i) if cfg["model"] == "ict" else None
                if st:
                    sw.done = True
                    self.setups.append(st)
                    ev.append({"type": "signal", "setup": st})

        # 4) confirm swing at i-k (added after sweep checks so it can only be swept later)
        k = cfg["swing_k"]
        j = i - k
        if j >= k:
            win = self.bars[j - k:j + k + 1]
            bj = self.bars[j]
            tol = cfg["eq_tol_atr"] * atr
            if bj["high"] == max(x["high"] for x in win):
                eq = any(abs(p - bj["high"]) <= tol for _, p in self.sw_hi)
                self.sw_hi.append((j, bj["high"]))
                self.levels.append(Level("EQH" if eq else "SWH", bj["high"], 1, False))
            if bj["low"] == min(x["low"] for x in win):
                eq = any(abs(p - bj["low"]) <= tol for _, p in self.sw_lo)
                self.sw_lo.append((j, bj["low"]))
                self.levels.append(Level("EQL" if eq else "SWL", bj["low"], -1, False))

        # 5) opening range levels
        if not self.or_done and self._tc(b).time() >= T(cfg["or_end"]):
            self.or_done = True
            self.or_hi = max(x["high"] for x in self.bars)
            self.or_lo = min(x["low"] for x in self.bars)
            self.levels.append(Level("ORH", self.or_hi, 1, False))
            self.levels.append(Level("ORL", self.or_lo, -1, False))

        # 6) ORB model, if selected. Runs on the same bars, produces the same
        #    Setup objects and passes through the same gates, so the two models
        #    are comparable rather than merely both present.
        if cfg["model"] == "orb":
            st = self._make_orb_setup(i)
            if st is not None:
                self.setups.append(st)
                ev.append({"type": "signal", "setup": st})
        return ev

    def _make_orb_setup(self, i):
        """Opening-range breakout: a 5m bar CLOSES beyond the opening range.

        Close, not touch, deliberately - an intrabar poke through the high is
        the thing ORB traders are most often stopped by, and requiring a close
        is the cheapest filter against it.
        """
        cfg, atr = self.cfg, self.atr
        if not self.or_done or self.or_hi is None or atr is None or atr <= 0:
            return None
        if self.orb_fired >= cfg["orb_max_per_day"]:
            return None
        b = self.bars[i]
        c, t = b["close"], self._tc(b)
        rng = self.or_hi - self.or_lo
        if rng <= 0:
            return None
        # A range that is already huge has nothing left to break into, and one
        # that is microscopic breaks on noise.
        if not (cfg["orb_min_rng_atr"] * atr <= rng <= cfg["orb_max_rng_atr"] * atr):
            return None

        prev_c = self.bars[i - 1]["close"] if i > 0 else None
        if prev_c is None:
            return None
        # The FIRST close beyond the range is the breakout. Without this the
        # engine emits a fresh setup on every bar price merely remains outside
        # - 26,775 of them in a 120-session test, nearly all rejected, which
        # buries the real signal in the rejection tally.
        if c > self.or_hi and prev_c <= self.or_hi:
            d, lvl = 1, self.or_hi
        elif c < self.or_lo and prev_c >= self.or_lo:
            d, lvl = -1, self.or_lo
        else:
            return None
        if cfg["orb_one_way"] and self.orb_dir not in (0, d):
            return None            # do not flip-flop on the same range

        entry = c
        stop = (self.or_lo - cfg["stop_buf_atr"] * atr) if d == 1 else \
               (self.or_hi + cfg["stop_buf_atr"] * atr)
        if cfg["orb_stop"] == "atr":
            stop = entry - d * cfg["orb_stop_atr"] * atr
        risk = abs(entry - stop)
        if risk <= 0:
            return None

        # Target: nearest opposing level that clears min_rr, else a fixed R.
        target, tname = entry + d * cfg["default_rr"] * risk, f"{cfg['default_rr']}R"
        for p, nm in sorted([(L.price, L.name) for L in self.levels
                             if L.side == d and L.state in ("live", "pierced")
                             and (L.price - entry) * d > 0],
                            key=lambda x: (x[0] - entry) * d):
            if (p - entry) * d / risk >= cfg["min_rr"]:
                target, tname = p, nm
                break

        score, notes = 2, [f"ORB {'up' if d == 1 else 'down'} {rng / atr:.1f}ATR"]
        if abs(c - lvl) >= cfg["orb_close_beyond_atr"] * atr:
            score += 1; notes.append("clean break")
        db = self.ctx["daily_bias"] if self.ctx else 0
        if db == d:
            score += 1; notes.append("daily bias")
        if self._h1_bias() == d:
            score += 1; notes.append("1H bias")
        ipts, inotes = self._indicator_score(d, entry)
        score += ipts; notes += inotes

        need = (math.ceil(cfg["min_score_frac"] * self.score_max(cfg))
                if cfg["min_score_frac"] > 0 else cfg["min_score"])
        st = Setup(self.sym, d, i, t, "ORB", round(entry, 2), round(stop, 2),
                   round(target, 2), tname, score, ", ".join(notes))
        st = self._gate(st, t, d, risk, score, need)
        if st.status != "rejected":
            self.orb_fired += 1
            self.orb_dir = d
        return st

    def _register_sweep(self, d, i, L):
        for sw in self.sweeps:  # merge with an active same-direction sweep
            if not sw.done and sw.dir == d and sw.mss_i < 0 and i - sw.i <= self.cfg["mss_window"]:
                sw.ext = min(sw.ext, L.ext) if d == 1 else max(sw.ext, L.ext)
                sw.names.append(L.name)
                sw.htf = sw.htf or L.htf
                return
        if d == 1:   # bullish: MSS = close above the last swing high before the sweep
            prior = [p for j, p in self.sw_hi if j < i]
            ref = prior[-1] if prior else (max(x["high"] for x in self.bars[max(0, i - 6):i]) if i else None)
        else:
            prior = [p for j, p in self.sw_lo if j < i]
            ref = prior[-1] if prior else (min(x["low"] for x in self.bars[max(0, i - 6):i]) if i else None)
        if ref is None:
            return
        self.sweeps.append(Sweep(d, i, L.ext, [L.name], L.htf, ref))

    def _make_setup(self, sw, i):
        cfg, atr, d = self.cfg, self.atr, sw.dir
        bars = self.bars
        zone, kind = None, None
        for j in range(i, max(sw.i + 2, 2) - 1, -1):   # latest qualifying FVG in the displacement leg
            if d == 1 and bars[j]["low"] > bars[j - 2]["high"]:
                bot, top = bars[j - 2]["high"], bars[j]["low"]
            elif d == -1 and bars[j]["high"] < bars[j - 2]["low"]:
                bot, top = bars[j]["high"], bars[j - 2]["low"]
            else:
                continue
            if top - bot >= cfg["fvg_min_atr"] * atr:
                zone, kind = (bot, top), "FVG"
                break
        if zone is None:
            if i - sw.mss_i < cfg["fvg_wait"]:
                return None   # wait for an FVG a little longer
            for j in range(sw.mss_i, sw.i - 1, -1):   # OB = last opposite candle before the move
                x = bars[j]
                if (d == 1 and x["close"] < x["open"]) or (d == -1 and x["close"] > x["open"]):
                    zone, kind = (x["low"], x["high"]), "OB"
                    break
            if zone is None:
                sw.done = True
                return None
        bot, top = zone
        if cfg["entry_at"] == "ce":
            entry = (bot + top) / 2
        else:
            entry = top if d == 1 else bot
        stop = sw.ext - d * cfg["stop_buf_atr"] * atr
        risk = (entry - stop) * d
        t = self._tc(bars[i])
        last_c = bars[i]["close"]
        if risk <= 0 or (last_c - entry) * d <= 0:
            sw.done = True
            return None
        # target = nearest opposing liquidity giving >= min_rr
        cands = sorted([(L.price, L.name) for L in self.levels
                        if L.side == d and L.state in ("live", "pierced") and (L.price - entry) * d > 0],
                       key=lambda x: (x[0] - entry) * d)
        target, tname = entry + d * cfg["default_rr"] * risk, f"{cfg['default_rr']}R"
        for p, nm in cands:
            if (p - entry) * d / risk >= cfg["min_rr"]:
                target, tname = p, nm
                break
        # confluence score
        ctx, notes, score = self.ctx, [], 2
        notes.append(f"sweep {'+'.join(sw.names)} -> MSS")
        if kind == "FVG":
            score += 1; notes.append("FVG")
        else:
            notes.append("OB")
        if sw.disp >= cfg["disp_strong_atr"]:
            score += 1; notes.append(f"disp {sw.disp:.1f}ATR")
        if sw.htf:
            score += 1; notes.append("HTF liquidity")
        db = ctx["daily_bias"] if ctx else 0
        if db == d:
            score += 1; notes.append("daily bias")
        h1 = self._h1_bias()
        if h1 == d:
            score += 1; notes.append("1H bias")
        if ctx and ((d == 1 and entry < ctx["pd_eq"]) or (d == -1 and entry > ctx["pd_eq"])):
            score += 1; notes.append("discount" if d == 1 else "premium")
        if ctx and any(fd == d and fb - atr <= sw.ext <= ft + atr for fd, fb, ft in ctx["daily_fvgs"]):
            score += 1; notes.append("daily FVG")
        ipts, inotes = self._indicator_score(d, entry)
        score += ipts; notes += inotes
        st = Setup(self.sym, d, i, t, kind, round(entry, 2), round(stop, 2), round(target, 2), tname,
                   score, ", ".join(notes))
        # Resolve the score threshold once, here, so every downstream gate and
        # every grid row means the same thing regardless of how many indicator
        # components are switched on.
        need = (math.ceil(cfg["min_score_frac"] * self.score_max(cfg))
                if cfg["min_score_frac"] > 0 else cfg["min_score"])
        return self._gate(st, t, d, risk, score, need)

    def _gate(self, st, t, d, risk, score, need):
        """The gates every model shares. Extracted so a second signal model
        reuses these exact rules rather than a drifting copy of them - the
        rejection tally is only comparable across models if the gates are."""
        cfg, atr = self.cfg, self.atr
        db = self.ctx["daily_bias"] if self.ctx else 0
        if not self.allow_new:
            st.status, st.reason = "rejected", "daily cap"
        elif atr and risk > cfg["max_risk_atr"] * atr:
            st.status, st.reason = "rejected", f"stop too wide ({risk / atr:.1f} ATR)"
        elif not self._in_window(t):
            st.status, st.reason = "rejected", "outside window"
        elif t.time() > T(cfg["last_entry"]):
            st.status, st.reason = "rejected", "too late"
        elif cfg["reject_against_daily"] and db == -d:
            st.status, st.reason = "rejected", "against daily bias"
        elif score < need:
            st.status, st.reason = "rejected", f"score {score}<{need}"
        elif self.trades_taken >= cfg["max_trades_per_stock"]:
            st.status, st.reason = "rejected", "stock trade cap"
        elif any(s.status in ("pending", "filled") for s in self.setups):
            st.status, st.reason = "rejected", "already active"
        return st

    # ---------------- price checks (bars or ticks)
    def _check_prices(self, hi, lo, t, open_=None):
        ev = []
        for s in self.setups:
            d = s.dir
            if s.status == "pending":
                touched = lo <= s.entry if d == 1 else hi >= s.entry
                if t.time() > T(self.cfg["last_entry"]):
                    s.status, s.reason = "expired", "past last entry"
                    ev.append({"type": "expired", "setup": s})
                elif touched:
                    s.status, s.fill_t = "filled", t
                    self.trades_taken += 1
                    ev.append({"type": "fill", "setup": s})
                elif (hi >= s.target if d == 1 else lo <= s.target):
                    s.status, s.reason = "missed", "target hit before retrace"
                    ev.append({"type": "missed", "setup": s})
            if s.status == "filled":
                stop_hit = lo <= s.stop if d == 1 else hi >= s.stop
                tgt_hit = hi >= s.target if d == 1 else lo <= s.target
                if stop_hit:   # conservative: stop wins when both are inside one bar
                    ev += self._close(s, s.stop if hi != lo else hi, t, "stop")
                elif tgt_hit:
                    ev += self._close(s, s.target if hi != lo else hi, t, "target")
        return ev

    def on_price(self, ltp, t):
        return self._check_prices(ltp, ltp, t)

    def square_off(self, px, t):
        ev = []
        for s in self.setups:
            if s.status == "filled":
                ev += self._close(s, px, t, "square-off")
            elif s.status == "pending":
                s.status, s.reason = "expired", "session end"
        return ev

    def _close(self, s, px, t, why):
        s.status, s.exit_px, s.exit_t, s.exit_reason = "closed", px, t, why
        return [{"type": "exit", "setup": s}]


# ============================================================================ BACKTEST
def rank_features(hist5, daily, today_df, cfg=CONFIG):
    """Everything needed to rank a stock for today, using ONLY what is knowable
    by 09:30 - prior daily bars and the opening range. No lookahead: the close
    of the session being ranked is never touched.
    """
    if today_df is None or len(today_df) == 0 or daily is None or len(daily) < 25:
        return None
    or_end = T(cfg["or_end"])
    orb = today_df[today_df.index.time <= or_end]
    if len(orb) == 0:
        return None
    px = float(orb["close"].iloc[-1])
    if px <= 0:
        return None

    a = wilder_atr(daily, 14)
    atr_d = float(a.iloc[-1]) if a is not None and len(a.dropna()) else 0.0
    prev_c = float(daily["close"].iloc[-1])
    or_hi, or_lo = float(orb["high"].max()), float(orb["low"].min())
    or_vol = float(orb["volume"].sum()) if "volume" in orb else 0.0

    # The same opening window on the previous 20 sessions, so "busy open" is
    # measured against this stock's own normal rather than across stocks.
    base, seen = [], 0
    if hist5 is not None and len(hist5):
        for d, grp in hist5.groupby(hist5.index.date, sort=True):
            w = grp[grp.index.time <= or_end]
            if len(w) and "volume" in w:
                base.append(float(w["volume"].sum())); seen += 1
    base = base[-20:]
    or_vol_ratio = (or_vol / (sum(base) / len(base))) if base and sum(base) > 0 else 1.0

    return {
        "px": px,
        "atr_pct": 100.0 * atr_d / px if px else 0.0,
        "or_pct": 100.0 * (or_hi - or_lo) / px,
        "or_vol_ratio": or_vol_ratio,
        "gap_pct": 100.0 * abs(px - prev_c) / prev_c if prev_c else 0.0,
        "ret_or": 100.0 * (px - prev_c) / prev_c if prev_c else 0.0,
    }


def rank_day(feats, cfg=CONFIG):
    """feats: {sym: rank_features(...)}. Returns symbols best-first.

    Each component is converted to a PERCENTILE within the day before
    weighting. Raw values are not comparable across stocks - a 2% ATR means
    something different on a Rs300 stock than on a Rs3,000 one - and summing
    raw numbers would let whichever has the largest units dominate the score.
    """
    rows = {s: f for s, f in feats.items() if f}
    if not rows:
        return []
    if cfg["rank_min_atr_pct"] > 0:
        rows = {s: f for s, f in rows.items() if f["atr_pct"] >= cfg["rank_min_atr_pct"]}
        if not rows:
            return []
    syms = list(rows)
    med = sorted(rows[s]["ret_or"] for s in syms)[len(syms) // 2]
    for s in syms:
        rows[s]["rs"] = abs(rows[s]["ret_or"] - med)      # move vs the pack, either way

    def pct(key):
        vals = sorted(rows[s][key] for s in syms)
        out = {}
        for s in syms:
            v = rows[s][key]
            out[s] = (sum(1 for x in vals if x < v) / max(1, len(vals) - 1)) if len(vals) > 1 else 0.5
        return out

    comps = {"atr_pct": cfg["rank_w_atr"], "or_pct": cfg["rank_w_orr"],
             "or_vol_ratio": cfg["rank_w_orv"], "gap_pct": cfg["rank_w_gap"],
             "rs": cfg["rank_w_rs"]}
    score = {s: 0.0 for s in syms}
    for key, w in comps.items():
        if w == 0:
            continue
        pr = pct(key)
        for s in syms:
            score[s] += w * pr[s]
    return sorted(syms, key=lambda s: -score[s])


def prepare(data5, daily_map=None, days=None):
    """Slice and contextualise once, so a grid can reuse it.

    df[df.index.date < day] costs ~3 ms on a 15k-bar frame because it rebuilds
    the whole date array each time. Two of those per session per symbol per
    COMBINATION is 97,200 slices for a 162-combination grid - about five
    minutes of pure slicing before any strategy code runs, which is why the
    first grid attempt produced no output at all.

    build_context() reads none of the swept parameters, so its results are
    cached here too. Anything that DOES depend on a swept parameter must stay
    inside run_backtest.
    """
    prepped = {}
    for sym, df in data5.items():
        df = df.sort_index()
        daily = daily_map[sym] if daily_map and sym in daily_map else resample_daily(df)
        dates = df.index.date                      # built ONCE per symbol
        sessions = sorted(set(dates))
        if days:
            sessions = sessions[-days:]
        per_day = []
        for day in sessions:
            ctx = build_context(daily, day)
            if ctx is None:
                continue
            hist, today = df[dates < day], df[dates == day]
            # Ranking features are parameter-independent, so they are cached
            # here with everything else prepare() precomputes.
            feats = rank_features(hist, daily[daily.index.date < day], today)
            per_day.append((day, ctx, hist, today, feats))
        prepped[sym] = per_day
    return prepped


def run_backtest(data5, daily_map=None, days=None, prepped=None):
    """data5: {sym: 5m DataFrame (index datetime IST)}. Returns DataFrame of all setups.

    Pass `prepped` from prepare() to skip the re-slicing - that is what makes a
    grid finish this century.
    """
    rows = []
    prepped = prepped if prepped is not None else prepare(data5, daily_map, days)

    # STAGE 1 - pick the stocks, before any signal work. Done per day across
    # ALL symbols, which is why it cannot live inside the per-symbol loop.
    allowed = None
    if CONFIG["universe_mode"] == "ranked":
        by_day = {}
        for sym, per_day in prepped.items():
            for day, ctx, hist, today, feats in per_day:
                by_day.setdefault(day, {})[sym] = feats
        allowed = {}
        for d, f in by_day.items():
            order = rank_day(f)
            # rank_features returns None until a symbol has ~25 daily bars and
            # an opening range, so early sessions can rank nothing. Falling
            # through to an empty set would silently trade NOTHING on those
            # days and look like a quiet market. Fall back to the full list
            # instead - no ranking information is not a reason to stand aside.
            allowed[d] = set(order[:CONFIG["rank_top_n"]]) if order else set(f.keys())

    for sym, per_day in prepped.items():
        for day, ctx, hist, today, feats in per_day:
            if allowed is not None and sym not in allowed.get(day, ()):
                continue
            eng = DayEngine(sym, day, ctx, hist)
            if today.empty:
                continue
            for t, r in today.iterrows():
                eng.on_bar({"t": t, "open": r["open"], "high": r["high"], "low": r["low"],
                            "close": r["close"], "volume": r.get("volume", 0.0)})
            last = today.iloc[-1]
            eng.square_off(last["close"], today.index[-1] + timedelta(minutes=CONFIG["tf_min"]))
            for s in eng.setups:
                rows.append({"sym": s.sym, "date": day, "time": s.t.strftime("%H:%M"), "dir": "CE" if s.dir == 1 else "PE",
                             "kind": s.kind, "score": s.score, "entry": s.entry, "stop": s.stop, "target": s.target,
                             "tgt": s.tgt_name, "status": s.status, "reason": s.reason, "exit": s.exit_reason,
                             "R": round(s.r, 2) if s.status == "closed" else None, "notes": s.notes,
                             # timestamps, so the portfolio layer can order and overlap trades
                             "t_sig": s.t, "t_fill": s.fill_t, "t_exit": s.exit_t})
    return pd.DataFrame(rows)


# ====================================================== PORTFOLIO LAYER
def portfolio_sim(df, cfg=None):
    """Turn a pile of per-symbol setups into what ONE account would have done.

    run_backtest evaluates every symbol independently, so it reports setups the
    live system would never have taken: it has no idea that two other positions
    were already open, that the day's fourth trade is not allowed, or that the
    loss cap had already stopped trading. live_loop enforces all three in
    handle(); without the same rules here the backtest measures a different
    system from the one that trades.

    Money is modelled from the sizing rule in Executor.pick():
        risk_1lot = underlying_risk * delta * lotsize
        lots      = risk_per_trade // risk_1lot
    so by construction the rupee risk of a filled trade is ~risk_per_trade, and
    gross P&L is R * risk_per_trade. Costs are taken as a fraction of that -
    see CONFIG["cost_R"], which must be calibrated from real contract notes
    rather than trusted as shipped.
    """
    cfg = cfg or CONFIG
    tr = df[df["status"] == "closed"].copy()
    if tr.empty:
        return tr.assign(taken=False, pnl=0.0, cum=0.0)
    tr["t_fill"] = pd.to_datetime(tr["t_fill"])
    tr["t_exit"] = pd.to_datetime(tr["t_exit"])
    tr = tr.sort_values("t_fill").reset_index(drop=True)

    risk_rs = cfg["risk_per_trade"]
    cost_rs = cfg["cost_R"] * risk_rs
    taken, pnl = [], []
    open_until, day, n_day, day_pnl = [], None, 0, 0.0

    for _, r in tr.iterrows():
        if day != r["date"]:
            day, n_day, day_pnl, open_until = r["date"], 0, 0.0, []
        open_until = [x for x in open_until if x > r["t_fill"]]
        ok = True
        if cfg["bt_apply_caps"]:
            if len(open_until) >= cfg["max_open"]:            ok = False
            elif n_day >= cfg["max_trades_per_day"]:          ok = False
            elif -day_pnl >= cfg["daily_loss_limit"]:         ok = False
        if not ok:
            taken.append(False); pnl.append(0.0); continue
        p = r["R"] * risk_rs - cost_rs
        taken.append(True); pnl.append(p)
        n_day += 1; day_pnl += p
        open_until.append(r["t_exit"])

    tr["taken"] = taken
    tr["pnl"] = pnl
    tr["cum"] = tr["pnl"].cumsum()
    return tr


def report_portfolio(df, cfg=None):
    cfg = cfg or CONFIG
    tr = portfolio_sim(df, cfg)
    t = tr[tr["taken"]] if "taken" in tr else tr
    if t.empty:
        print("\nPORTFOLIO: no trades survived the caps.")
        return
    risk_rs = cfg["risk_per_trade"]
    eq = t["pnl"].cumsum()
    dd = (eq.cummax() - eq).max()
    gross_win = t.loc[t.pnl > 0, "pnl"].sum()
    gross_loss = -t.loc[t.pnl < 0, "pnl"].sum()
    pf = gross_win / gross_loss if gross_loss else float("inf")
    print(f"\n{'=' * 70}\nPORTFOLIO (one account, live caps {'ON' if cfg['bt_apply_caps'] else 'OFF'}, "
          f"cost {cfg['cost_R']}R = Rs{cfg['cost_R'] * risk_rs:,.0f}/trade)")
    print(f"  setups closed {len(tr)} | taken {len(t)} | refused by caps {len(tr) - len(t)}")
    print(f"  net Rs{t.pnl.sum():,.0f} | win% {(t.pnl > 0).mean() * 100:.1f} | PF {pf:.2f} | "
          f"avg Rs{t.pnl.mean():,.0f}/trade | maxDD Rs{dd:,.0f}")

    # Per period, because an average hides the year that would have stopped you.
    t = t.copy()
    t["month"] = pd.to_datetime(t["date"]).dt.to_period("M").astype(str)
    t["year"] = pd.to_datetime(t["date"]).dt.year
    for key in ("year", "month"):
        g = t.groupby(key).agg(n=("pnl", "size"), net=("pnl", "sum"),
                               win=("pnl", lambda x: round((x > 0).mean() * 100, 1)))
        g["net"] = g["net"].round(0)
        if len(g) > 1:
            print(f"\nBy {key}:\n{g.to_string()}")
            worst = g["net"].idxmin()
            print(f"  WORST {key}: {worst} at Rs{g.loc[worst, 'net']:,.0f} over {g.loc[worst, 'n']} trades")
            print(f"  -> judge on this, not on the total. A system is only as good as the"
                  f" stretch that would have made you stop.")


def report(df):
    if df.empty:
        print("No setups found.")
        return
    tr = df[df["status"] == "closed"].copy()
    print(f"\nSetups seen: {len(df)} | traded: {len(tr)} | rejected: {(df.status == 'rejected').sum()} | "
          f"expired/missed: {df.status.isin(['expired', 'missed']).sum()}")
    if df["reason"].astype(bool).any():
        print("Top rejection reasons:\n" + df[df.status == "rejected"]["reason"]
              .str.replace(r"[\s(]*\d.*", "", regex=True).value_counts().head(6).to_string())
    if tr.empty:
        return

    def stats(g):
        r = g["R"]
        return pd.Series({"n": len(r), "win%": round((r > 0).mean() * 100, 1), "avgR": round(r.mean(), 2),
                          "totalR": round(r.sum(), 1)})
    eq = tr.sort_values(["date", "time"])["R"].cumsum()
    print(f"\nOVERALL  n={len(tr)}  win%={(tr.R > 0).mean() * 100:.1f}  expectancy={tr.R.mean():.2f}R  "
          f"total={tr.R.sum():.1f}R  maxDD={(eq.cummax() - eq).max():.1f}R")
    print("\nBy score:\n" + tr.groupby("score").apply(stats, include_groups=False).to_string())
    print("\nBy entry type:\n" + tr.groupby("kind").apply(stats, include_groups=False).to_string())
    tr["window"] = np.where(tr["time"] < "12:00", "morning", "afternoon")
    print("\nBy window:\n" + tr.groupby("window").apply(stats, include_groups=False).to_string())
    print("\nBy exit:\n" + tr.groupby("exit").apply(stats, include_groups=False).to_string())
    print("\nBy stock (top 10 by n):\n" + tr.groupby("sym").apply(stats, include_groups=False)
          .sort_values("n", ascending=False).head(10).to_string())


def synthetic_data(syms=("DEMO1", "DEMO2", "DEMO3"), days=90, seed=7):
    rng = np.random.default_rng(seed)
    out = {}
    for s in syms:
        px, rows = 1000.0 + rng.uniform(-200, 200), []
        d = date.today() - timedelta(days=int(days * 1.45))
        n = 0
        while n < days:
            d += timedelta(days=1)
            if d.weekday() >= 5:
                continue
            n += 1
            px *= 1 + rng.normal(0, 0.008)
            drift = rng.normal(0, 0.0004)
            t = datetime.combine(d, T("09:15"))
            for _ in range(75):
                vol = px * 0.0022
                if rng.random() < 0.04:   # occasional stop-hunt spike and reversal
                    drift = -drift * 1.5
                o = px
                c = o + drift * px + rng.normal(0, vol)
                h = max(o, c) + abs(rng.normal(0, vol * 0.6))
                l = min(o, c) - abs(rng.normal(0, vol * 0.6))
                rows.append((t, o, h, l, c, int(rng.integers(1e4, 1e5))))
                px, t = c, t + timedelta(minutes=5)
        out[s] = pd.DataFrame(rows, columns=["t", "open", "high", "low", "close", "volume"]).set_index("t")
    return out


def cache_path(sym, interval):
    d = os.path.join(CONFIG["data_dir"], "cache")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, f"{sym}_{interval}.csv")


def fetch_cached(api, sym, token, interval, start, end, max_age_h=20):
    """Fetch once, reuse all day.

    Every backtest and every grid was re-pulling the same candles from
    SmartAPI - 213 symbols at a 0.4s throttle is minutes of waiting before any
    work starts, and it burns rate limit for data that cannot change. The cache
    is keyed by symbol and interval and refreshed when it is older than
    max_age_h, so an intraday rerun is instant and tomorrow's is current.
    """
    p = cache_path(sym, interval)
    if os.path.exists(p):
        age_h = (time.time() - os.path.getmtime(p)) / 3600.0
        if age_h < max_age_h:
            try:
                df = pd.read_csv(p, index_col=0, parse_dates=True)
                if len(df):
                    return df
            except Exception:
                pass
    df = api.candles(token, interval, start, end)
    if len(df):
        df.to_csv(p)
    return df


def load_csv_dir(path, syms=None):
    out = {}
    for fn in os.listdir(path):
        if not fn.lower().endswith(".csv"):
            continue
        sym = fn[:-4]
        if syms and sym not in syms:
            continue
        df = pd.read_csv(os.path.join(path, fn))
        df.columns = [x.lower() for x in df.columns]
        tcol = "datetime" if "datetime" in df.columns else df.columns[0]
        df["t"] = pd.to_datetime(df[tcol]).dt.tz_localize(None)
        out[sym] = df.set_index("t")[["open", "high", "low", "close", "volume"]].astype(float)
    return out


# ============================================================================ ANGEL ONE
class Angel:
    def __init__(self):
        from SmartApi import SmartConnect
        import pyotp
        need = ["ANGEL_API_KEY", "ANGEL_CLIENT", "ANGEL_PIN", "ANGEL_TOTP_SECRET"]
        miss = [k for k in need if not os.getenv(k)]
        if miss:
            sys.exit(f"Missing env vars: {', '.join(miss)}")
        self.api = SmartConnect(api_key=os.getenv("ANGEL_API_KEY"))
        r = self.api.generateSession(os.getenv("ANGEL_CLIENT"), os.getenv("ANGEL_PIN"),
                                     pyotp.TOTP(os.getenv("ANGEL_TOTP_SECRET")).now())
        if not r or not r.get("status"):
            sys.exit(f"Login failed: {r}")
        self._last = {}
        log("SmartAPI login ok")
        self.master = self._load_master()

    def _throttle(self, key, gap):
        dt = time.time() - self._last.get(key, 0)
        if dt < gap:
            time.sleep(gap - dt)
        self._last[key] = time.time()

    def _load_master(self):
        import requests
        os.makedirs(CONFIG["data_dir"], exist_ok=True)
        path = os.path.join(CONFIG["data_dir"], f"scrip_{date.today():%Y%m%d}.json")

        def _download():
            # Write to a temp file and RENAME. The master is ~34 MB and takes
            # seconds; a second process starting meanwhile would otherwise read
            # a half-written file and die on a JSON decode error. rename() is
            # atomic on the same filesystem, so a reader sees either the old
            # file or the complete new one, never a partial.
            log("downloading instrument master...")
            tmp = f"{path}.{os.getpid()}.tmp"
            with open(tmp, "wb") as f:
                f.write(requests.get(SCRIP_MASTER_URL, timeout=120).content)
            os.replace(tmp, path)

        if not os.path.exists(path):
            _download()
        try:
            m = pd.DataFrame(json.load(open(path)))
        except Exception as e:
            # A truncated file from an older build, or a download interrupted
            # before this fix existed. Re-fetch once rather than fail the run.
            log(f"instrument master unreadable ({e}) - re-downloading")
            _download()
            m = pd.DataFrame(json.load(open(path)))
        m["strike"] = pd.to_numeric(m["strike"], errors="coerce") / 100.0
        m["lotsize"] = pd.to_numeric(m["lotsize"], errors="coerce")
        m["tick_size"] = pd.to_numeric(m["tick_size"], errors="coerce") / 100.0
        m["exp"] = pd.to_datetime(m["expiry"], format="%d%b%Y", errors="coerce").dt.date
        return m

    def fno_underlyings(self):
        """Every stock with listed options AND an NSE cash line to take candles
        from. 213 names against the hand-written 25 - and frequency, not
        selectivity, is what the daily target is short of."""
        m = self.master
        names = set(m[(m.exch_seg == "NFO") & (m.instrumenttype == "OPTSTK")].name.dropna())
        eq = set(m[(m.exch_seg == "NSE") & (m.symbol.str.endswith("-EQ"))]
                 .symbol.str.replace("-EQ", "", regex=False))
        return sorted(names & eq)

    def eq_token(self, sym):
        r = self.master[(self.master.exch_seg == "NSE") & (self.master.symbol == f"{sym}-EQ")]
        return None if r.empty else str(r.iloc[0]["token"])

    def candles(self, token, interval, start, end, exch="NSE"):
        out, step = [], timedelta(days=30 if interval != "ONE_DAY" else 1500)
        cur = start
        while cur < end:
            nxt = min(cur + step, end)
            for attempt in range(3):
                self._throttle("candle", 0.4)
                try:
                    r = self.api.getCandleData({"exchange": exch, "symboltoken": token, "interval": interval,
                                                "fromdate": cur.strftime("%Y-%m-%d %H:%M"),
                                                "todate": nxt.strftime("%Y-%m-%d %H:%M")})
                    out += (r or {}).get("data") or []
                    break
                except Exception as e:
                    log(f"candle retry {token}: {e}")
                    time.sleep(1 + attempt)
            cur = nxt
        if not out:
            return pd.DataFrame(columns=["open", "high", "low", "close", "volume"])
        df = pd.DataFrame(out, columns=["t", "open", "high", "low", "close", "volume"])
        df["t"] = pd.to_datetime(df["t"]).dt.tz_localize(None)
        return df.drop_duplicates("t").set_index("t").astype(float).sort_index()

    def quotes(self, exch, tokens, mode="FULL"):
        res = {}
        tokens = list(tokens)
        for k in range(0, len(tokens), 50):
            self._throttle("quote", 0.25)
            try:
                r = self.api.getMarketData(mode, {exch: tokens[k:k + 50]})
                for q in ((r or {}).get("data") or {}).get("fetched") or []:
                    res[str(q["symbolToken"])] = q
            except Exception as e:
                log(f"quote error: {e}")
        return res

    def option_chain(self, sym, today):
        m = self.master
        ch = m[(m.exch_seg == "NFO") & (m.instrumenttype == "OPTSTK") & (m.name == sym)]
        exps = sorted(e for e in ch.exp.dropna().unique() if e >= today)
        if not exps:
            return None, None
        exp = exps[0]
        if (exp - today).days <= CONFIG["expiry_roll_days"] and len(exps) > 1:
            exp = exps[1]
        return ch[ch.exp == exp], exp

    def place(self, row, side, qty, price):
        p = {"variety": "NORMAL", "tradingsymbol": row["symbol"], "symboltoken": str(row["token"]),
             "transactiontype": side, "exchange": "NFO", "ordertype": "LIMIT", "producttype": "INTRADAY",
             "duration": "DAY", "price": f"{price:.2f}", "quantity": str(int(qty))}
        self._throttle("order", 0.2)
        return self.api.placeOrder(p)

    def order_status(self, oid):
        self._throttle("book", 0.5)
        book = (self.api.orderBook() or {}).get("data") or []
        for o in book:
            if str(o.get("orderid")) == str(oid):
                return o
        return None


# ====================================================== OPTION MATHS
# Enough Black-Scholes to size and compare strikes.
#
# The delta the old picker used was a CONSTANT - 0.62 for ITM1, 0.50 for ATM -
# which ignores both how far the strike is from spot and how long is left to
# expiry. Sizing is lots = risk_budget // (stop_distance * delta * lotsize), so
# the error feeds straight into position size:
#
#   assumed delta BELOW the real one  -> too many contracts -> loses MORE than
#                                        the budget when stopped
#   assumed delta ABOVE the real one  -> too few            -> under-risked
#
# The dangerous direction is the common one here, because the legacy picker
# prefers ITM1 and a one-strike-ITM option is usually well above 0.62. Worked
# example, spot 100, 30 days, 25% IV: the 95 strike has a real delta of 0.796,
# so a Rs2,000 budget actually risks Rs2,568 - 28% over - every trade.
SQ2PI = math.sqrt(2.0 * math.pi)


def _ncdf(x):
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


def _npdf(x):
    return math.exp(-0.5 * x * x) / SQ2PI


def bs_price(spot, strike, t_years, iv, is_call, r=0.065):
    """European option price. NSE stock options are European, so no early-exercise term."""
    if t_years <= 0 or iv <= 0 or spot <= 0 or strike <= 0:
        return max(0.0, (spot - strike) if is_call else (strike - spot))
    d1 = (math.log(spot / strike) + (r + 0.5 * iv * iv) * t_years) / (iv * math.sqrt(t_years))
    d2 = d1 - iv * math.sqrt(t_years)
    disc = math.exp(-r * t_years)
    if is_call:
        return spot * _ncdf(d1) - strike * disc * _ncdf(d2)
    return strike * disc * _ncdf(-d2) - spot * _ncdf(-d1)


def bs_delta(spot, strike, t_years, iv, is_call, r=0.065):
    if t_years <= 0 or iv <= 0:
        itm = (spot > strike) if is_call else (spot < strike)
        return (1.0 if is_call else -1.0) if itm else 0.0
    d1 = (math.log(spot / strike) + (r + 0.5 * iv * iv) * t_years) / (iv * math.sqrt(t_years))
    return _ncdf(d1) if is_call else _ncdf(d1) - 1.0


def bs_theta_per_day(spot, strike, t_years, iv, is_call, r=0.065):
    """Theta in rupees per unit per CALENDAR day. Negative for a buyer."""
    if t_years <= 0 or iv <= 0:
        return 0.0
    sq = math.sqrt(t_years)
    d1 = (math.log(spot / strike) + (r + 0.5 * iv * iv) * t_years) / (iv * sq)
    d2 = d1 - iv * sq
    disc = math.exp(-r * t_years)
    term1 = -(spot * _npdf(d1) * iv) / (2 * sq)
    if is_call:
        return (term1 - r * strike * disc * _ncdf(d2)) / 365.0
    return (term1 + r * strike * disc * _ncdf(-d2)) / 365.0


def implied_vol(price, spot, strike, t_years, is_call, r=0.065):
    """Bisection. Slower than Newton but it cannot diverge, and a bad IV here
    silently mis-sizes every position - worth the extra few microseconds."""
    if price <= 0 or t_years <= 0:
        return 0.0
    intrinsic = max(0.0, (spot - strike) if is_call else (strike - spot))
    if price < intrinsic:                 # stale or crossed quote
        return 0.0
    lo, hi = 0.01, 5.0
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        if bs_price(spot, strike, t_years, mid, is_call, r) > price:
            hi = mid
        else:
            lo = mid
        if hi - lo < 1e-5:
            break
    iv = 0.5 * (lo + hi)
    return 0.0 if iv >= 4.99 or iv <= 0.011 else iv


def round_tick(px, tick):
    tick = tick if tick and tick > 0 else 0.05
    return round(round(px / tick) * tick, 2)


# ============================================================================ OPTION LEG
@dataclass
class OptPos:
    setup: Setup
    row: dict
    qty: int
    entry_px: float
    exit_px: float = 0.0
    pnl: float = 0.0
    oid_in: str = ""
    oid_out: str = ""


class Executor:
    def __init__(self, angel, live):
        self.a, self.live = angel, live
        self.open, self.closed = {}, []

    @staticmethod
    def _bid_ask(q):
        dep = q.get("depth") or {}
        bid = (dep.get("buy") or [{}])[0].get("price") or 0
        ask = (dep.get("sell") or [{}])[0].get("price") or 0
        return float(bid), float(ask)

    def pick(self, s, spot, today):
        return self._pick_ev(s, spot, today) if CONFIG["picker"] == "ev" \
            else self._pick_legacy(s, spot, today)

    def _candidates(self, s, spot, today):
        """Every strike within the window, with a real delta and theta.

        The old picker looked at exactly two strikes (ATM and one in-the-money)
        and took the first that passed a spread and OI check. That is a
        liquidity filter, not a choice: it never asked which strike made the
        most money for the risk, and it priced both with a constant delta.
        """
        ch, exp = self.a.option_chain(s.sym, today)
        if ch is None or ch.empty:
            return [], None, "no chain"
        side = "CE" if s.dir == 1 else "PE"
        is_call = s.dir == 1
        ch = ch[ch.symbol.str.endswith(side)]
        strikes = sorted(ch.strike.unique())
        if not strikes:
            return [], None, "no strikes"

        atm = min(strikes, key=lambda k: abs(k - spot))
        ai = strikes.index(atm)
        w = CONFIG["strike_window"]
        sel = strikes[max(0, ai - w): ai + w + 1]
        rows = {k: ch[ch.strike == k].iloc[0].to_dict() for k in sel}
        qs = self.a.quotes("NFO", [str(r["token"]) for r in rows.values()])

        # Calendar days, floored at part of a day: an option expiring today
        # still has hours of life and a zero here would make theta infinite.
        t_years = max((exp - today).days, 0.25) / 365.0
        out, why = [], []
        for k, r in rows.items():
            q = qs.get(str(r["token"]))
            if not q:
                why.append(f"{k:.0f}: no quote"); continue
            bid, ask = self._bid_ask(q)
            if bid <= 0 or ask <= 0:
                why.append(f"{k:.0f}: no bid/ask"); continue
            mid = (bid + ask) / 2.0
            spr_pct = (ask - bid) / mid * 100.0
            lot = int(r["lotsize"])
            oi_lots = float(q.get("opnInterest") or 0) / lot
            vol = float(q.get("tradeVolume") or q.get("volume") or 0)

            if spr_pct > CONFIG["max_spread_pct"]:
                why.append(f"{k:.0f}: spread {spr_pct:.1f}%"); continue
            if oi_lots < CONFIG["min_oi_lots"]:
                why.append(f"{k:.0f}: OI {oi_lots:.0f} lots"); continue
            if CONFIG["min_volume"] and vol < CONFIG["min_volume"]:
                why.append(f"{k:.0f}: vol {vol:.0f}"); continue

            iv = implied_vol(mid, spot, k, t_years, is_call)
            if iv <= 0:
                why.append(f"{k:.0f}: IV unsolvable"); continue
            if CONFIG["max_iv"] and iv > CONFIG["max_iv"]:
                why.append(f"{k:.0f}: IV {iv * 100:.0f}%"); continue

            delta = abs(bs_delta(spot, k, t_years, iv, is_call))
            if not (CONFIG["min_delta"] <= delta <= CONFIG["max_delta"]):
                why.append(f"{k:.0f}: delta {delta:.2f}"); continue
            theta = abs(bs_theta_per_day(spot, k, t_years, iv, is_call))

            out.append({"row": r, "strike": k, "bid": bid, "ask": ask, "mid": mid,
                        "spread": spr_pct, "lot": lot, "oi_lots": oi_lots, "vol": vol,
                        "iv": iv, "delta": delta, "theta": theta, "exp": exp,
                        "label": f"{k:.0f}{side}"})
        return out, exp, "; ".join(why[:6]) or "no candidate"

    def _pick_ev(self, s, spot, today):
        """Choose the strike with the best expected rupees AFTER its own costs.

        For each candidate:
            move     = |target - entry| on the underlying
            gross    = delta * move * qty                  what the move is worth
            spread   = (ask - bid) * qty                   paid once, round trip
            theta    = theta_per_day * hold * qty          time decay while held
            net      = gross - spread - theta
        and the position is sized so the UNDERLYING stop costs ~risk_per_trade,
        using the real delta rather than a constant.

        This is why it can beat the old rule: a nearer strike has more delta but
        a worse spread, a further one is cheaper but barely moves, and which
        wins depends on how far the target is. A fixed preference list cannot
        express that; an expected-value comparison can.
        """
        cands, exp, why = self._candidates(s, spot, today)
        if not cands:
            return None, why
        move = abs(s.target - s.entry)
        best, scored = None, []
        for c in cands:
            risk_1lot = s.risk * c["delta"] * c["lot"]
            if risk_1lot <= 0:
                continue
            lots = int(CONFIG["risk_per_trade"] // risk_1lot)
            if lots < 1:
                if risk_1lot > 1.5 * CONFIG["risk_per_trade"]:
                    continue
                lots = 1
            lots = min(lots, CONFIG["max_lots"])
            qty = lots * c["lot"]

            gross = c["delta"] * move * qty
            spread_rs = (c["ask"] - c["bid"]) * qty
            theta_rs = c["theta"] * (CONFIG["hold_hours"] / 24.0) * qty
            net = gross - spread_rs - theta_rs
            cost = spread_rs + theta_rs

            c2 = dict(c, lots=lots, qty=qty, risk_rs=lots * risk_1lot,
                      gross=gross, cost=cost, net=net)
            scored.append(c2)
            # A day of theta that eats a quarter of the target is a losing
            # trade dressed as a winner, however good the signal was.
            if c["theta"] * qty > CONFIG["max_theta_frac"] * gross:
                continue
            if cost > 0 and gross / cost < CONFIG["min_edge_ratio"]:
                continue
            if best is None or net > best["net"]:
                best = c2
        if best is None:
            if scored:
                b = max(scored, key=lambda x: x["net"])
                return None, (f"no strike clears the cost bar (best {b['label']}: "
                              f"gross Rs{b['gross']:.0f} vs cost Rs{b['cost']:.0f})")
            return None, why
        return best, ""

    def _pick_legacy(self, s, spot, today):
        ch, exp = self.a.option_chain(s.sym, today)
        if ch is None or ch.empty:
            return None, "no chain"
        side = "CE" if s.dir == 1 else "PE"
        ch = ch[ch.symbol.str.endswith(side)]
        strikes = sorted(ch.strike.unique())
        if not strikes:
            return None, "no strikes"
        atm = min(strikes, key=lambda k: abs(k - spot))
        ai = strikes.index(atm)
        cand = {"ATM": atm}
        itm_i = ai - 1 if s.dir == 1 else ai + 1
        if 0 <= itm_i < len(strikes):
            cand["ITM1"] = strikes[itm_i]
        rows = {lab: ch[ch.strike == k].iloc[0].to_dict() for lab, k in cand.items()}
        qs = self.a.quotes("NFO", [str(r["token"]) for r in rows.values()])
        why = []
        for lab in CONFIG["strike_pref"]:
            if lab not in rows:
                continue
            r = rows[lab]
            q = qs.get(str(r["token"]))
            if not q:
                why.append(f"{lab}: no quote"); continue
            bid, ask = self._bid_ask(q)
            if bid <= 0 or ask <= 0:
                why.append(f"{lab}: no bid/ask"); continue
            spr = (ask - bid) / ((ask + bid) / 2) * 100
            oi_lots = float(q.get("opnInterest") or 0) / r["lotsize"]
            if spr > CONFIG["max_spread_pct"]:
                why.append(f"{lab}: spread {spr:.1f}%"); continue
            if oi_lots < CONFIG["min_oi_lots"]:
                why.append(f"{lab}: OI {oi_lots:.0f} lots"); continue
            delta = CONFIG["delta_est"][lab]
            risk_1lot = s.risk * delta * r["lotsize"]
            lots = int(CONFIG["risk_per_trade"] // risk_1lot)
            if lots < 1:
                if risk_1lot > 1.5 * CONFIG["risk_per_trade"]:
                    why.append(f"{lab}: 1 lot risks Rs{risk_1lot:.0f}"); continue
                lots = 1
            lots = min(lots, CONFIG["max_lots"])
            return {"row": r, "label": lab, "bid": bid, "ask": ask, "spread": spr,
                    "qty": lots * int(r["lotsize"]), "lots": lots, "exp": exp,
                    "risk_rs": lots * risk_1lot, "delta": delta}, ""
        return None, "; ".join(why) or "no candidate"

    def enter(self, s, spot, today):
        pk, why = self.pick(s, spot, today)
        if not pk:
            return None, why
        r = pk["row"]
        px = pk["ask"]
        oid = ""
        if self.live:
            px = round_tick(pk["ask"] + CONFIG["limit_buffer_ticks"] * r["tick_size"], r["tick_size"])
            oid = self.a.place(r, "BUY", pk["qty"], px)
            if not oid:
                return None, "order rejected"
            filled = self._wait_fill(oid, 10)
            if not filled:
                try:
                    self.a.api.cancelOrder(oid, "NORMAL")
                except Exception:
                    pass
                return None, "entry not filled (cancelled)"
            px = filled
        pos = OptPos(s, r, pk["qty"], px, oid_in=str(oid))
        self.open[id(s)] = pos
        return pos, pk

    def exit(self, s):
        pos = self.open.pop(id(s), None)
        if not pos:
            return None
        r = pos.row
        q = self.a.quotes("NFO", [str(r["token"])]).get(str(r["token"]))
        bid, ask = self._bid_ask(q) if q else (0, 0)
        px = bid if bid > 0 else float((q or {}).get("ltp") or pos.entry_px)
        if self.live:
            for attempt in range(4):   # re-price down until filled
                lim = round_tick(max(px - (CONFIG["limit_buffer_ticks"] + 2 * attempt) * r["tick_size"],
                                     r["tick_size"]), r["tick_size"])
                oid = self.a.place(r, "SELL", pos.qty, lim)
                f = self._wait_fill(oid, 6) if oid else None
                if f:
                    px, pos.oid_out = f, str(oid)
                    break
                if oid:
                    try:
                        self.a.api.cancelOrder(oid, "NORMAL")
                    except Exception:
                        pass
            else:
                log(f"!!! EXIT NOT CONFIRMED for {r['symbol']} - CHECK POSITION MANUALLY")
                telegram(f"!!! Exit not confirmed: {r['symbol']} qty {pos.qty}. Check manually.")
        pos.exit_px = px
        pos.pnl = (px - pos.entry_px) * pos.qty
        self.closed.append(pos)
        return pos

    def _wait_fill(self, oid, secs):
        end = time.time() + secs
        while time.time() < end:
            o = self.a.order_status(oid)
            if o:
                st = str(o.get("status", "")).lower()
                if st == "complete":
                    return float(o.get("averageprice") or o.get("price"))
                if st in ("rejected", "cancelled"):
                    log(f"order {oid} {st}: {o.get('text')}")
                    return None
            time.sleep(1)
        return None

    def day_pnl(self):
        return sum(p.pnl for p in self.closed)


# ============================================================================ LIVE / PAPER LOOP
def live_loop(live=False):
    cfg = CONFIG
    now = datetime.now()
    today = now.date()
    if today.weekday() >= 5:
        sys.exit("Weekend - exiting.")
    mode0 = "LIVE" if live else "PAPER"
    telegram_preflight(mode0)
    lock = SingleInstance()
    lock.acquire()
    a = Angel()
    ex = Executor(a, live)
    mode = "LIVE" if live else "PAPER"
    tokens = {s: a.eq_token(s) for s in cfg["universe"]}
    tokens = {s: t for s, t in tokens.items() if t}
    log(f"{mode} start, {len(tokens)} symbols")

    # warm-up: daily + recent 5m history
    engines, hist, daily_hist = {}, {}, {}
    for s, tok in tokens.items():
        d = a.candles(tok, "ONE_DAY", datetime.combine(today - timedelta(days=120), T("09:15")),
                      datetime.combine(today, T("09:00")))
        h5 = a.candles(tok, "FIVE_MINUTE", datetime.combine(today - timedelta(days=12), T("09:15")),
                       datetime.combine(today, T("09:00")))
        ctx = build_context(d, today)
        if ctx is None or h5.empty:
            log(f"{s}: not enough history, skipped")
            continue
        hist[s] = h5
        daily_hist[s] = d
        engines[s] = DayEngine(s, today, ctx, h5, tick_mode=True)
    log(f"warm-up done: {len(engines)} engines")

    # wait for open, then liquidity screen on ATM options
    while datetime.now().time() < T("09:20"):
        time.sleep(5)
    spots = a.quotes("NSE", [tokens[s] for s in engines], mode="LTP")
    keep = []
    for s in list(engines):
        q = spots.get(tokens[s])
        if not q:
            continue
        ok = True
        for d in (1, -1):
            probe = Setup(s, d, 0, datetime.now(), "probe", q["ltp"], q["ltp"] * (1 - 0.004 * d), 0, "", 0, "")
            pk, why = ex.pick(probe, q["ltp"], today)
            if not pk:
                ok = False
                log(f"{s}: dropped ({'CE' if d == 1 else 'PE'} {why})")
                break
        if ok:
            keep.append(s)
    engines = {s: engines[s] for s in keep}

    # STAGE 1 - rank what survived the liquidity screen and keep the best.
    # Order matters: liquidity first (an untradeable option is not a candidate
    # at any rank), then ranking among what is actually tradeable.
    if cfg["universe_mode"] == "ranked" and engines:
        while datetime.now().time() < T(cfg["or_end"]):
            time.sleep(10)                      # the opening range must be complete
        feats = {}
        for s in list(engines):
            try:
                td = a.candles(tokens[s], "FIVE_MINUTE",
                               datetime.combine(today, T(cfg["market_open"])), datetime.now())
                feats[s] = rank_features(hist.get(s), daily_hist.get(s), td)
            except Exception as e:
                log(f"{s}: ranking failed ({e})")
                feats[s] = None
        order = rank_day(feats)
        if order:
            keep2 = order[:cfg["rank_top_n"]]
            dropped = [s for s in engines if s not in keep2]
            engines = {s: engines[s] for s in keep2}
            log(f"ranked: keeping {keep2}; dropped {len(dropped)}")
        else:
            log("ranking produced nothing - keeping the full liquid list")
    msg = (f"[{mode}] START {today:%Y-%m-%d}\n"
           f"watchlist ({len(engines)}): {', '.join(engines)}\n"
           f"risk/trade Rs{cfg['risk_per_trade']:,.0f} | max {cfg['max_trades_per_day']} trades, "
           f"{cfg['max_open']} open | daily loss cap Rs{cfg['daily_loss_limit']:,.0f}\n"
           f"square-off {cfg['square_off']} | live_trading={cfg['live_trading']}")
    log(msg.replace("\n", " | ")); telegram(msg)

    fed = {s: 0 for s in engines}
    last_candle_pull = None
    trades_today = 0

    def handle(ev_list):
        nonlocal trades_today
        for e in ev_list:
            s = e["setup"]
            tag = f"{s.sym} {'CE' if s.dir == 1 else 'PE'}"
            if e["type"] == "signal":
                row = {"time": s.t, "sym": s.sym, "dir": tag[-2:], "kind": s.kind, "score": s.score,
                       "entry": s.entry, "stop": s.stop, "target": s.target, "tgt": s.tgt_name,
                       "status": s.status, "reason": s.reason, "notes": s.notes}
                append_csv(f"signals_{today:%Y%m%d}.csv", row)
                if s.status == "pending":
                    m = (f"[{mode}] SETUP {tag} score {s.score}/{DayEngine.score_max()} ({s.kind})\nentry {s.entry} | SL {s.stop} | "
                         f"TGT {s.target} ({s.tgt_name})\n{s.notes}")
                    log(m.replace("\n", " | ")); telegram(m)
                else:
                    log(f"signal {tag} rejected: {s.reason} [{s.notes}]")
            elif e["type"] == "fill":
                open_n = len(ex.open)
                if trades_today >= cfg["max_trades_per_day"] or open_n >= cfg["max_open"] \
                        or -ex.day_pnl() >= cfg["daily_loss_limit"]:
                    s.status, s.reason = "rejected", "risk caps at fill"
                    log(f"{tag} fill skipped: risk caps")
                    continue
                pos, info = ex.enter(s, s.entry, today)
                if not pos:
                    s.status, s.reason = "rejected", f"option: {info}"
                    log(f"{tag} not entered: {info}"); telegram(f"[{mode}] {tag} skipped - {info}")
                    continue
                trades_today += 1
                m = (f"[{mode}] ENTRY {pos.row['symbol']} x{pos.qty} ({info['lots']} lot, {info['label']}) @ "
                     f"{pos.entry_px:.2f} | spread {info['spread']:.1f}% | risk ~Rs{info['risk_rs']:.0f}\n"
                     f"underlying SL {s.stop} / TGT {s.target}")
                log(m.replace("\n", " | ")); telegram(m)
            elif e["type"] == "exit":
                pos = ex.exit(s)
                if pos:
                    m = (f"[{mode}] EXIT {pos.row['symbol']} @ {pos.exit_px:.2f} ({s.exit_reason}) | "
                         f"P&L Rs{pos.pnl:,.0f} | {s.r:+.2f}R underlying | day Rs{ex.day_pnl():,.0f}")
                    log(m); telegram(m)
                    append_csv(f"trades_{today:%Y%m%d}.csv", {
                        "sym": s.sym, "option": pos.row["symbol"], "qty": pos.qty, "signal_t": s.t,
                        "fill_t": s.fill_t, "exit_t": s.exit_t, "entry_opt": pos.entry_px, "exit_opt": pos.exit_px,
                        "pnl": round(pos.pnl, 2), "R_under": round(s.r, 2), "exit": s.exit_reason,
                        "score": s.score, "notes": s.notes, "mode": mode})
            if trades_today >= cfg["max_trades_per_day"] or -ex.day_pnl() >= cfg["daily_loss_limit"]:
                for en in engines.values():
                    en.allow_new = False

    def flatten(reason):
        """Close everything at the last price we can get. Used at square-off
        AND on the way out of a crash - an open INTRADAY option left to the
        broker's own auto-square-off is the worst outcome available."""
        try:
            q = a.quotes("NSE", [tokens[s] for s in engines], mode="LTP")
        except Exception as e:
            log(f"flatten: quotes failed ({e}) - closing at last known price")
            q = {}
        for s, en in engines.items():
            px = float(q.get(tokens[s], {}).get("ltp") or 0)
            try:
                handle(en.square_off(px, datetime.now()))
            except Exception as e:
                log(f"flatten {s} failed: {e}")
        log(f"flatten done ({reason})")

    errors = 0
    last_beat = datetime.now()
    try:
        while True:
            nowt = datetime.now()
            try:
                # pull completed 5m candles shortly after each boundary
                boundary = nowt.replace(second=0, microsecond=0, minute=(nowt.minute // 5) * 5)
                if nowt >= boundary + timedelta(seconds=4) and boundary != last_candle_pull:
                    last_candle_pull = boundary
                    for s, en in engines.items():
                        df = a.candles(tokens[s], "FIVE_MINUTE", datetime.combine(today, T("09:15")), nowt)
                        df = df[df.index + timedelta(minutes=5) <= nowt]
                        for t, r in df.iloc[fed[s]:].iterrows():
                            handle(en.on_bar({"t": t, "open": r["open"], "high": r["high"],
                                              "low": r["low"], "close": r["close"],
                                              "volume": r.get("volume", 0.0)}))
                        fed[s] = len(df)
                # tick checks for pending entries / open positions
                active = [s for s, en in engines.items()
                          if any(x.status in ("pending", "filled") for x in en.setups)]
                if active:
                    q = a.quotes("NSE", [tokens[s] for s in active], mode="LTP")
                    for s in active:
                        if tokens[s] in q:
                            handle(engines[s].on_price(float(q[tokens[s]]["ltp"]), datetime.now()))
                errors = 0
            except Exception as e:
                # One bad cycle is a network blip, not a reason to abandon open
                # positions. Many bad cycles in a row means the session is gone.
                errors += 1
                import traceback
                log(f"cycle error {errors}/{cfg['max_loop_errors']}: {e}\n{traceback.format_exc()}")
                if errors in (1, 5):
                    telegram(f"[{mode}] cycle error {errors}: {type(e).__name__}: {e}")
                if errors >= cfg["max_loop_errors"]:
                    telegram(f"[{mode}] {errors} consecutive errors - flattening and stopping.")
                    flatten("too many errors")
                    break
                time.sleep(min(30, 2 ** min(errors, 5)))
                continue

            if cfg["heartbeat_min"] and (nowt - last_beat).total_seconds() >= cfg["heartbeat_min"] * 60:
                last_beat = nowt
                telegram(f"[{mode}] {nowt:%H:%M} alive | open {len(ex.open)} | done {len(ex.closed)} | "
                         f"day Rs{ex.day_pnl():,.0f}")

            if nowt.time() >= T(cfg["square_off"]):
                flatten("square-off")
                break
            time.sleep(cfg["poll_sec"])

        m = f"[{mode}] day done: {len(ex.closed)} trades, P&L Rs{ex.day_pnl():,.0f}"
        log(m); telegram(m)

    except BaseException as e:
        # Covers KeyboardInterrupt and SystemExit too: whatever is killing the
        # process, the positions must not be left open and silent.
        import traceback
        tb = traceback.format_exc()
        log(f"FATAL: {e}\n{tb}")
        telegram(f"[{mode}] FATAL {type(e).__name__}: {e}\nFlattening now. Check the account.")
        try:
            flatten("fatal error")
        finally:
            telegram(f"[{mode}] after flatten: open {len(ex.open)}, done {len(ex.closed)}, "
                     f"day Rs{ex.day_pnl():,.0f}")
        raise
    finally:
        lock.release()


# ====================================================== PARAMETER GRID
# Session windows as named presets, because the grid stores scalars and a
# window is a list of tuples. The tally is why this axis exists at all: of
# 15.6 setups found per day, the two 75-minute windows discard 9.0 - more than
# every other filter combined - and 0.46 survive to trade. Frequency, not the
# ICT logic, is what caps the daily number, so it has to be swept rather than
# assumed.
WINDOW_PRESETS = {
    "two75":  [("09:30", "10:45"), ("13:30", "14:45")],   # current default
    "morn":   [("09:30", "11:30")],
    "wide":   [("09:30", "11:30"), ("13:00", "14:45")],
    "allday": [("09:30", "14:45")],
}

GRID = {
    "min_score":  [5, 6, 7],
    "disp_atr":   [0.8, 1.0, 1.3],
    "min_rr":     [1.2, 1.5, 2.0],
    "entry_at":   ["ce", "edge"],
    "stop_buf_atr": [0.05, 0.10, 0.20],
}

# --grid-set freq : aimed at the daily-target question rather than at tuning.
# A Rs5,000 day at Rs2,000 risk is 2.5R, and 0.46 trades a day cannot produce
# that at any believable expectancy. This sweep asks whether frequency can be
# raised WITHOUT destroying the edge - the two move against each other, and
# where they cross is the only thing that decides whether the target is
# reachable at all.
# --grid-set ind : every on/off combination of the six indicator components,
# at three selectivity levels. 64 x 3 = 192 runs.
#
# They are scored as a FRACTION of the maximum, because switching components on
# raises the max from 9 to 15 - comparing a fixed min_score across those is
# comparing two different filters and calling it one result.
#
# Expect most of these to do nothing. The gold work put ~1,500 backtests into
# the same question and found adding indicator filters monotonically WORSE
# (none +581 -> all five +200). The reason to run it anyway is that here they
# are ranking components rather than gates, and the binding constraint is
# frequency, not selectivity - a different question from the one that failed.
GRID_IND = {
    "sc_vol":       [False, True],
    "sc_ema":       [False, True],
    "sc_emastack":  [False, True],
    "sc_rsi":       [False, True],
    "sc_vwap":      [False, True],
    "sc_atr":       [False, True],
    "min_score_frac": [0.55, 0.65, 0.75],
}

# --grid-set orb : selection on the ORB model.
#
# Worth running only because frequency is no longer the constraint. ORB finds
# 10.2 trades a day against ICT's 0.46, so a filter that discards 70% still
# leaves 3/day - selection can finally be afforded. The same sweep on ICT was
# pointless: cutting 0.46/day leaves nothing to trade.
GRID_ORB = {
    "min_score_frac":       [0.5, 0.65, 0.8],
    "reject_against_daily": [True, False],   # 1,757 of 5,549 setups died on this alone
    "orb_stop":             ["atr", "range"],
    "sc_vol":               [False, True],
    "sc_emastack":          [False, True],
    "sc_vwap":              [False, True],
    "windows":              ["two75", "wide"],
}

GRID_FREQ = {
    "windows":    ["two75", "morn", "wide", "allday"],
    "min_score":  [5, 6, 7],
    "max_trades_per_day": [4, 8],
    "max_open":   [2, 4],
    "min_rr":     [1.2, 1.5],
}

# Axes whose grid value is a KEY into a preset table rather than the value
# itself. Kept separate so run_grid can translate without special-casing.
GRID_PRESETS = {"windows": WINDOW_PRESETS}


def run_grid(data5, daily_map, days, oos_frac=0.3, out=None, grid=None):
    """Sweep GRID, scoring every combination on a HELD-OUT tail.

    The gold work in this repo spent three grids learning this: the best
    in-sample combination of a large sweep is usually the luckiest one, not the
    best one. So each combination is scored twice - on the first (1-oos_frac)
    of the sessions and on the last oos_frac, which no choice is allowed to
    see - and only the out-of-sample column is worth reading.
    """
    import itertools
    grid = grid or GRID
    keys = list(grid)
    combos = list(itertools.product(*(grid[k] for k in keys)))
    print(f"grid: {len(combos)} combinations x {len(data5)} symbols", flush=True)

    # Split by SESSION DATE, never at random: adjacent setups share a market,
    # so a random split leaks the answer across the boundary.
    all_days = sorted({d for df in data5.values() for d in set(df.index.date)})
    if days:
        all_days = all_days[-days:]
    cut = all_days[int(len(all_days) * (1 - oos_frac))]
    print(f"sessions {all_days[0]} .. {all_days[-1]} | out-of-sample from {cut}")
    # Trades per day is the number the daily target depends on, so carry the
    # session counts and report it per combination.
    nsess = {"is": sum(1 for d in all_days if d < cut),
             "oos": sum(1 for d in all_days if d >= cut)}

    print("preparing data once for all combinations...", flush=True)
    prepped = prepare(data5, daily_map, days)
    nday = sum(len(v) for v in prepped.values())
    print(f"  {nday} symbol-sessions ready", flush=True)

    saved = {k: CONFIG[k] for k in keys}
    rows = []
    t0 = time.time()
    try:
        for i, combo in enumerate(combos, 1):
            for k, v in zip(keys, combo):
                CONFIG[k] = GRID_PRESETS[k][v] if k in GRID_PRESETS else v
            df = run_backtest(data5, daily_map, days, prepped=prepped)
            rec = dict(zip(keys, combo))
            for tag, sel in (("is", df["date"] < cut), ("oos", df["date"] >= cut)):
                sub = portfolio_sim(df[sel], CONFIG)
                t = sub[sub["taken"]] if "taken" in sub and len(sub) else sub
                if len(t):
                    eq = t["pnl"].cumsum()
                    rec[f"{tag}_n"] = len(t)
                    rec[f"{tag}_net"] = round(t["pnl"].sum())
                    rec[f"{tag}_win"] = round((t["pnl"] > 0).mean() * 100, 1)
                    rec[f"{tag}_dd"] = round((eq.cummax() - eq).max())
                    rec[f"{tag}_per_day"] = round(len(t) / max(1, nsess[tag]), 2)
                else:
                    rec[f"{tag}_n"] = 0; rec[f"{tag}_net"] = 0
                    rec[f"{tag}_win"] = 0.0; rec[f"{tag}_dd"] = 0
                    rec[f"{tag}_per_day"] = 0.0
            rows.append(rec)
            el = time.time() - t0
            eta = el / i * (len(combos) - i)
            print(f"  [{i}/{len(combos)}] {combo} -> IS {rec['is_net']:+,} ({rec['is_n']})  "
                  f"OOS {rec['oos_net']:+,} ({rec['oos_n']}, {rec['oos_per_day']}/day)  "
                  f"[eta {eta / 60:.0f}m]", flush=True)
    finally:
        CONFIG.update(saved)

    g = pd.DataFrame(rows)
    out = out or os.path.join(CONFIG["data_dir"], f"grid_{date.today():%Y%m%d}.csv")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    g.to_csv(out, index=False)

    print(f"\n{'=' * 70}\nTOP 10 BY OUT-OF-SAMPLE NET (the only column worth ranking on)")
    print(g.sort_values("oos_net", ascending=False).head(10).to_string(index=False))
    print(f"\nTOP 10 BY IN-SAMPLE, and what they then did out of sample:")
    print(g.sort_values("is_net", ascending=False).head(10).to_string(index=False))
    pos = (g["oos_net"] > 0).sum()
    print(f"\n  {pos} of {len(g)} combinations positive out of sample.")
    print(f"  If that is near half, the grid is finding noise - a real edge shows up in a")
    print(f"  CLUSTER of neighbouring parameter values, not in one or two scattered winners.")
    print(f"\ngrid written to {out}")
    return g


# ============================================================================ CLI
def main():
    load_env()
    ap = argparse.ArgumentParser(description="ICT confluence intraday stock-options system (Angel One)")
    ap.add_argument("mode", choices=["demo", "backtest", "grid", "paper", "live"])
    ap.add_argument("--days", type=int, default=60)
    ap.add_argument("--symbols", help="comma list, overrides universe")
    ap.add_argument("--universe", choices=["default", "fno"], default="default",
                    help="'fno' = every stock with listed options (213), discovered from "
                         "the scrip master. The frequency lever: 8.5x the hand-written list.")
    ap.add_argument("--no-cache", action="store_true", help="always re-pull from the API")
    ap.add_argument("--csv-dir")
    ap.add_argument("--out", default=None, help="write setups CSV here")
    ap.add_argument("--oos", type=float, default=0.3, help="grid: fraction of sessions held out")
    ap.add_argument("--grid-set", choices=["default", "freq", "ind", "orb"], default="default",
                    dest="grid_set",
                    help="'freq' sweeps windows and trade caps; 'ind' sweeps the six "
                         "indicator score components (64 on/off x 3 thresholds)")
    ap.add_argument("--synthetic", action="store_true",
                    help="use generated data - proves the machinery runs, says nothing about the edge")
    ap.add_argument("--i-understand-the-risk", action="store_true")
    a = ap.parse_args()
    if a.symbols:
        CONFIG["universe"] = [x.strip().upper() for x in a.symbols.split(",")]

    if a.mode in ("demo", "backtest", "grid"):
        daily_map = None
        if a.mode == "demo" or a.synthetic:
            data = synthetic_data(days=200)
        elif a.csv_dir:
            data = load_csv_dir(a.csv_dir, set(CONFIG["universe"]) if a.symbols else None)
        else:
            api = Angel()
            if a.universe == "fno" and not a.symbols:
                CONFIG["universe"] = api.fno_underlyings()
                log(f"universe: {len(CONFIG['universe'])} F&O underlyings")
            data, daily_map = {}, {}
            end = datetime.now()
            get = (lambda s, t, iv, st: api.candles(t, iv, st, end)) if a.no_cache else \
                  (lambda s, t, iv, st: fetch_cached(api, s, t, iv, st, end))
            total = len(CONFIG["universe"])
            for i, s in enumerate(CONFIG["universe"], 1):
                tok = api.eq_token(s)
                if not tok:
                    log(f"{s}: token not found"); continue
                if i % 25 == 0 or i == total:
                    log(f"fetching {i}/{total} ...")
                data[s] = get(s, tok, "FIVE_MINUTE", end - timedelta(days=int(a.days * 1.5) + 10))
                daily_map[s] = get(s, tok, "ONE_DAY", end - timedelta(days=int(a.days * 1.5) + 120))
                if data[s] is None or len(data[s]) == 0:
                    data.pop(s, None); daily_map.pop(s, None)
        if a.mode == "grid":
            g = {"default": GRID, "freq": GRID_FREQ, "ind": GRID_IND, "orb": GRID_ORB}[a.grid_set]
            if a.grid_set == "orb":
                CONFIG["model"] = "orb"
                CONFIG["max_risk_atr"] = 12.0   # a range stop needs the room; the ATR
                                                # stop is unaffected by a higher cap
            run_grid(data, daily_map, a.days if a.csv_dir or a.mode == "grid" else None,
                     oos_frac=a.oos, out=a.out, grid=g)
            return
        res = run_backtest(data, daily_map, a.days if a.mode == "backtest" else None)
        report(res)
        report_portfolio(res)
        out = a.out or os.path.join(CONFIG["data_dir"], f"backtest_{a.mode}_{date.today():%Y%m%d}.csv")
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        res.to_csv(out, index=False)
        print(f"\nsetups written to {out}")
    elif a.mode == "paper":
        live_loop(live=False)
    else:
        if not (a.i_understand_the_risk and CONFIG["live_trading"]):
            sys.exit("Live trading needs --i-understand-the-risk AND CONFIG['live_trading'] = True.")
        live_loop(live=True)


if __name__ == "__main__":
    main()
