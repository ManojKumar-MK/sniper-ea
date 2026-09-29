# MT5-SMC trading bot — vendored third-party source

| | |
|---|---|
| Upstream | https://github.com/KVignesh122/MT5-SMC-trading-bot |
| Author | K. Vignesh |
| Licence | **Apache 2.0** — redistribution permitted with the notice and attribution |
| Strategy | Order Block / FVG / BOS, selectable, XAUUSD |
| Tested by | [`smc-grid/`](../../smc-grid/) |

Unmodified.

## Why it is worth testing

It is the only third-party EA reviewed whose loss guard reads **equity** and compares it
against both a profit and a loss threshold:

```cpp
double equity = AccountInfoDouble(ACCOUNT_EQUITY);
if(equity >= profitThreshold || equity <= lossThreshold) { ... }
```

Gold Reaper measured balance. GOLD_ORB called its guard "equity" and read balance. This
one gets it right, which matters more for a funded account than any strategy detail.

Four selectable modes — OB, FVG, BOS, AUTO — so `smc-grid` runs each separately. AUTO
is the default and hides which one is doing the work.

## Two things to know

**`lossThreshold` is computed ONCE at init**, from the balance at that moment:

```cpp
currentBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
lossThreshold   = currentBalance * (1.0 - BagLossPercent/100.0);
```

It is a fixed price level, not a trailing one. Once the account grows, −4% is measured
from the original baseline rather than the current peak — so the guard loosens as you
profit. For a static-drawdown prop rule that is arguably correct; for a trailing one it
is not. Restarting the EA re-baselines it.

**The README claim is marketing.** "60%+ to 300%+ RETURNS Yearly on XAUUSD" appears
alongside a broker referral link and a consulting section, with no backtest anywhere in
the repo. That is the same shape as Gold Reaper and FvgGold: a number in the README and
nothing behind it. `smc-grid/` is the check.
