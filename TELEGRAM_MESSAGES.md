# Telegram messages

Every message the EA can send, with a sample of each. The columns below are
rendered with the EA's own padding, so what arrives on your phone lines up the
same way.

Bold is `<b>`, the boxed blocks are `<pre>`. Set `InpTgHtmlStyle = false` to send
plain text instead — the content is identical, only the markup is dropped.

> **Emoji are built with `Emo(0x1F916)`, not string escapes.** MQL5's `\x`
> parser does not reliably yield a UTF-16 code unit, and an emoji outside the
> BMP needs a surrogate *pair*, which no single escape can express — the escape
> form leaked into the message as literal `xDD16`. `Emo()` takes a code point and
> assembles the pair with `ShortToString()`. Pasting the character into the
> source is worse again: MetaEditor can save the file as ANSI and destroy it.

> **IST times in these messages are 12-hour** — `02:29 PM`, not `14:29`. The
> end-of-day table uses the compact `02:29a` / `02:05p` to keep its column
> widths. This applies to Telegram only; the Experts tab, the chart panel and
> every logged timestamp stay 24-hour, because they are parsed, not read.

---

Every message is prefixed with **SniperEA** (`InpTgPrefix`) on its own first line.

## 1 · Startup — `InpTgNotifyStart`

🤖 **EA online**
XAUUSD  M15

```
Lots d/e  0.05 / 0.05
Mode      live trading
IST now   09:42 AM
```
**Reading the close card**
```
R      what the trade actually made, in multiples of the risk
Best   furthest it ran IN FAVOUR before it ended   (MFE)
Worst  furthest it ran AGAINST you before it ended (MAE)
```
Both are measured after entry, so they only appear on the closing message - never on the signal itself.
`Best far above R = the target closed too early. Worst near 0 = the stop was wider than it needed to be.`

> The legend is sent once per session, so the close cards stay compact.

## 2 · Entry — `InpTgNotifyEntry`

🟢 **BUY  XAUUSD  M15**
Entry taken  -  `FULLTGT`  DAY session

```
Entry   2412.40
SL      2401.40
TP1     2417.90
TP2     2423.40
TP3     2428.90
TP4     2434.40
TP5     2439.90
Lots    0.05
```
**Why**
```
EMA  2412.9 / 2410.1 / 2402.7
ADX  31.4    RSI 58.2 (M5 61.0)
MACD 0.83 / 0.51
ATR  5.50    VWAP 2409.80
Vol  489 vs 697
Bias 71% bull / 29% bear
Sprd 18 pts
```
`09:42 srv / 12:12 PM IST`

> Signals-only says `Signal only` instead of `Entry taken`, and omits **Lots**.

## 3 · Each target reached — `InpTgNotifyTP`

✅ **TP1 reached  +1.0R**
XAUUSD  M15  BUY

```
TP1    2417.90
Booked nothing - running to TP5
Stop   SL -> Breakeven 2412.40
```

Scale-out mode instead books a slice:

✅ **TP2 booked  +2.0R**
XAUUSD  M15  BUY

```
TP2    2423.40
Booked 0.01 lots
Stop   SL -> TP1 2417.90
```

## 4 · TP5 — depends on `InpBookAtTP5`

`true` (default) — booked and closed:

🏁 **TP5 HIT - FULL TARGET  +5.0R**
XAUUSD  M15  BUY

```
TP5    2439.90
Closed full position
```

`false` — runs on:

🚀 **TP5 reached - RUNNING ON  +5.0R**
XAUUSD  M15  BUY

```
TP5    2439.90
Booked nothing - running until the flip
Stop   SL -> TP4 2434.40
```

Then one per rung above TP5:

🚀 **Runner +6.0R**
XAUUSD  M15  BUY

```
Price  2445.40
Stop   TP5 2439.90
```

## 5 · Close — `InpTgNotifyClose`

Live trading:

💰 **CLOSED  EXIT_TRAIL_SL**
XAUUSD  M15  BUY

```
Entry   2412.40
Exit    2439.90
Pips    +275.0
R       +5.00R
Net     +512.30
Best    +6.12R
Worst   -0.31R
```

Icon is 💰 profit · ❌ loss · ➖ breakeven. Signals-only sends the same card without **Net**: It also carries a one-line reminder, because a signal channel has readers who joined mid-week and never saw the startup legend:

❌ **SL HIT**
XAUUSD  M15  BUY

```
Entry   2412.40
Exit    2401.40
Pips    -110.0
R       -1.00R
Best    +0.42R
Worst   -1.00R
```
`Best/Worst = furthest in favour / against after entry, in R`

Other endings, same shape: `FLIP - signal ended` 🔁, `WEEKEND CLOSE` 📴, `TP5 REACHED - SIGNAL COMPLETE` 🏁.

## 6 · End of day — `InpTgNotifyEOD`

📊 **DAY SUMMARY  2026.09.19**
XAUUSD  M15   `times IST`

```
#  In    Out   S Entry   SL      Exit       Pips     R     Net
1  12:12p 02:05p B 2412.40 2401.40 2439.90  +275.0  +5.0 +512.30
2  03:30p 04:02p S 2441.10 2452.10 2452.10  -110.0  -1.0 -205.00
                                 TOTAL    +165.0  +4.0 +307.30
```
**Totals**
```
Trades        2  (W 1 / L 1)
Win rate      50%
Gross profit  +512.30
Gross loss    -205.00
NET           +307.30
Profit factor 2.50
Net R         +4.00R
Best/worst    +512.30 / -205.00
Balance       10000.00 -> 10307.30
```

`InpTgDayTable = false` drops the per-trade table and keeps Totals.

## 7 · Week and month — `InpTgNotifyPeriod`

🗓 **WEEK SUMMARY**
XAUUSD  M15   `dates IST`

```
Date        Trd    W/L     Pips     R       Net
2026.09.15    3    2/1   +310.0  +4.5   +420.10
2026.09.16    2    1/1    -45.0  -0.5    -60.00
TOTAL         5    3/2   +265.0  +4.0   +360.10
```

Followed by a Totals block: days traded, green days, trades, win rate, gross, NET, PF, net R, best/worst day.

## 8 · Guards — `InpTgNotifyHalt`, only when `InpPropMode = true`

🛑 **DAILY LOSS CAP**
XAUUSD

```
Day loss    412.00
Day cap     400.00
Trades      4
Equity      9588.00
```
No more trades today. Resets at the configured day reset time.

Also: ⚠️ `DAILY LOSS WARNING` · 🛑 `MAX LOSS GUARD - TRADING STOPPED` · ⚠️ `MAX LOSS WARNING` · 🛑 `MAX LOSSES PER DAY`.

## 9 · News — `InpNewsTgAlerts`

📰 **NEWS AHEAD**
XAUUSD

```
Event     Non-Farm Payrolls
Currency  USD
Impact    HIGH
Time      18:00 IST  (15:30 srv)
Starts    in 15 min
```
Heads-up only - the news filter is off, trading continues as normal.

With the filter on: ⏸ `NEW ENTRIES PAUSED` then ✅ `NEWS WINDOW CLEAR`.

## 10 · Weekend — `InpTgNotifyClose`

📴 **WEEKEND CLOSE**
XAUUSD

Position flattened before the Friday close.

---

## Which switch controls what

| Input | Default | Turns off |
|---|---|---|
| `InpUseTelegram` | false | **everything** — master switch |
| `InpTgNotifyStart` | true | EA online |
| `InpTgNotifyEntry` | true | the entry card |
| `InpTgNotifyTP` | true | TP1–TP4, TP5, runner rungs |
| `InpTgNotifyClose` | true | close cards, weekend close |
| `InpTgNotifyEOD` | true | day summary |
| `InpTgNotifyPeriod` | true | week and month summaries |
| `InpTgNotifyHalt` | true | guard alerts (also needs `InpPropMode`) |
| `InpNewsTgAlerts` | true | news heads-up, pause, resume |
| `InpTgDayTable` | true | the per-trade table inside the day summary |

## Two things worth knowing

**MFE/MAE appear once per trade**, on whichever message ends it — never on the
entry card (both are `0.00R` at that moment) and never on the TP messages (at TP1
the MFE is `+1.0R` by definition, so it just restates the headline).

**Messages over 3800 characters are split** on line breaks rather than truncated,
so a long day table arrives as several readable messages instead of failing.

## Setup

MT5 → **Tools → Options → Expert Advisors** → tick *Allow WebRequest for listed
URL* and add `https://api.telegram.org`. Without it `WebRequest` returns −1 and
nothing sends. WebRequest never runs in the Strategy Tester, so no message is
ever sent from a backtest.
