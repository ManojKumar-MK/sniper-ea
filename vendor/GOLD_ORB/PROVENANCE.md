# GOLD_ORB — vendored, with one bug fixed

Not our code. Vendored because [`orb-grid/`](../../orb-grid/) tests it and the preset
would otherwise reference an EA living only on someone else's GitHub.

| | |
|---|---|
| Upstream | https://github.com/yulz008/GOLD_ORB |
| Author | Ulysses O. Andulte |
| Licence | **none stated** — see below |
| Strategy | Opening Range Breakout, XAUUSD, H1 |

## Licence: there isn't one

The upstream repo has **no LICENSE file**, so it is all-rights-reserved by default.
This copy is here for private testing only. **Do not redistribute it** and do not treat
its presence here as permission to. If that matters to you, delete this folder and clone
upstream instead — `orb-grid/` works either way once the `.ex5` is in the tester.

## The fix

One change from upstream, at the equity-drawdown guard. Upstream:

```cpp
if(100*((BALANCE - capital)/capital) < -1*MaxEquityDrawdownPercent)
   printf(...);
   execute_trade = false;      // <-- no braces
```

Both statements are indented under the `if`, but there are no braces, so only the
`printf` was conditional. **`execute_trade = false` ran on every tick whenever
`MaxEquityDrawdownPercent != 0`** — meaning enabling the drawdown guard stopped the EA
trading entirely.

That is almost certainly why the shipped `Input/default_input.set` has
`MaxEquityDrawdownPercent=0.0`. Disabling the guard was the only way to get any trades
out of it. So upstream offers no protection, or no trades, and nothing in between.

Fixed by adding the braces. Verified by diffing against upstream with line endings
normalised: that block is the only change, and CRLF terminators are preserved.

## Two things NOT fixed, because they are judgement calls not bugs

**It is called an equity guard and reads `ACCOUNT_BALANCE`.** Floating losses do not
count, so it measures something different from what a prop firm measures. Left as the
author wrote it — changing it would be a behaviour change, not a repair.

**`MoneyManagement()` puts the risk percentage FIRST.** Any `MaxRiskPerTradePercent > 0`
makes `FixedVolume` irrelevant:

```cpp
if(pPercent > 0 && pStopPoints > 0) { ...risk-based...; return; }
else { return pFixedVol; }
```

The same precedence trap as `InpUseSessionLots` in our own EA and `FixedLot` in FvgGold.
The grid sets it to `0.0` in the control so `FixedVolume` applies, and to a real value
only in the sets that intend risk-based sizing.

## Single-file build

`GOLD_ORB_single.mq5` is the one to compile. Upstream pulls nine `.mqh` files from an
`Include/` folder beside the source; this has them inlined, so it builds on its own with
nothing else to copy into `MQL5/Experts/`.

- **Inlined** (the author's, ~2,960 lines): Trade, TradeVirtual, TrailingStops,
  TrailingStopsVirtual, price_action, Indicators, MoneyManagement, RiskManagement,
  errordescription. Each appears once even though four files included
  `errordescription.mqh`, and each file's own includes are emitted before its body so
  dependencies precede use.
- **`#property` stripped** from the inlined files — every one carried its own
  copyright/link/version block and repeating them makes MQL5 complain. Only the main
  file's three remain.
- **Not inlined:** `Include/Math/Stat/Normal.mqh` is MetaQuotes' own standard library
  file that had been bundled into the repo. It now uses MT5's copy via
  `#include <Math\Stat\Normal.mqh>`. Inlining it would have added 6,400 lines of
  MetaQuotes code when the only symbol used from it is `MathSum()`.

Verified: braces and parens balance (222/222, 992/992) with line comments, block
comments and string literals all stripped correctly; no duplicate function, class or
enum definitions; `OnInit` and `OnTick` both present.

The original `GOLD_ORB.mq5` and `Include/` are kept alongside for reference. Compile
whichever you prefer — they are the same EA, and both carry the braces fix.

## Status

**Never compiled here and never backtested.** Upstream ships a `.ex5` and a
`Test Cases.pptx`, but no MT5 report — no equity curve, no drawdown figure, nothing
comparable to the other EAs. Generating that is what `orb-grid/` is for.
