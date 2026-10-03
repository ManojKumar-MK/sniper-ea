# Why the Pine log shows ~200 pips a day and the EA shows nothing

Same signal - EMA 9 crossing EMA 21, five TP levels at 1R to 5R. The TradingView log
reads about 200 pips a day. The MT5 version of the same thing was backtested roughly
1,500 times and came out at a **median profit factor of 0.990**.

Both cannot be right. The difference is not the market; it is how a trade is scored.

## 1. There is no TradingView backtest

All three Pine files declare `indicator(...)`, not `strategy(...)`, and contain **zero**
`strategy.*` calls:

```
ict+ema.pine            indicator('ICT Suite [SMC + Sniper + HTF + TS + OTE + SFP ...]'
sma+sniper+turtle.pine  indicator('ICT Suite [SMC + Sniper + HTF + TS + OTE + SFP ...]'
ict_sweep_model.pine    indicator('ICT Sweep Model - PDH/PDL [entry · stop · 1:N · log]'
```

So the Strategy Tester never ran. The "trade log" is a table the script draws from its
own bookkeeping - no broker model, no spread, no commission, no slippage.

## 2. The real inflation: targets that were touched but never taken

This is the one that matters.

```pinescript
logIncludeFlips = input.bool(true, 'Log trades that flipped early', ...)
```

Default **on**. When an opposite cross replaces a live trade before it reached SL or TP5,
the trade is logged with the best level it ever touched:

```pinescript
_mult = str.contains(_res,'SL') ? -1.0 : ... 'TP3' ? 3.0 : 'TP2' ? 2.0 : 'TP1' ? 1.0 : 0.0
```

**A trade that touched TP3 and then flipped at +0.4R is recorded as +3R.**

Nothing exits at TP3. In the MT5 EA `InpUseFullTarget=true` - no partial is ever booked,
full size runs to TP5 or comes back. So the Pine credits a 3R exit that, by the
strategy's own rules, does not happen.

And it is systematic rather than occasional: only `TP5 🚀` and `SL 💣` are genuine
closes. **Every `TP1`-`TP4` row in that log is a flipped trade credited at a price it
never traded out at** - and EMA 9/21 crosses flip constantly on a 5-minute chart.

## 3. What the script does get right

Worth saying, because it is better than most:

- `f_tradePips` scores a stopped trade as **-1R regardless of how far it ran** - the
  comment says so explicitly. The optimistic `SL 💣 (TP3)` label does **not** inflate the
  P&L.
- The ambiguous-bar rule (`TPs checked before SL`) only affects the label, not the pips.
- The HTF reads mostly use the non-repainting `[1] + lookahead_on` idiom.

One exception worth a look: line 559 requests `high[0], low[0], time[0]` with
`lookahead = barmerge.lookahead_on`. The `[1]` idiom is safe; `[0]` with lookahead on is
the classic repaint, and it feeds the FVG detection.

## 4. The arithmetic, for completeness

`pipSize = 0.1`, so 200 pips = **$20.00 of gold movement per day**, net, after losses.
Gold's daily range is $40-60. That is 35-50% of the entire day's range captured every
day - which is the same number the EA grids kept failing to produce, and the reason they
disagreed was never the execution.

## 5. How to settle it in ten minutes

Change one line in the Pine and re-read the log:

```pinescript
logIncludeFlips = input.bool(false, ...)   // only count trades that closed on SL or TP5
```

That removes every credited-but-untaken target. If 200 pips/day survives, the EA has an
execution problem worth hunting. If it collapses, the EA was right all along and the
premise behind the $100/day target needs rebuilding on the honest number.

**Do that before any more EA work.** Every target in this project - $100/day, Rs5,000/day
- traces back to this log.

## 6. What it means for "execute the high quality pick"

The EA already *is* the honest version: it exits at real prices, pays the spread, and
reports what is left. That is why it shows PF 0.990 where the log shows 200 pips.

Making the EA pick better trades is worth doing. But it cannot close a gap that exists
because the two are counting different things - and until the Pine is rescored, there is
no way to know how large the real gap is.
