# mt5-trade-split-manager - assessment

[codedpro/mt5-trade-split-manager](https://github.com/codedpro/mt5-trade-split-manager).
1,659 lines of MQL5 plus a FastAPI server, a TCP bridge and an MCP server.

**This is the most relevant third-party repo looked at so far, and it is not a strategy.**
It generates no signals. It is an execution manager: you POST an entry, an SL and a TP
ladder, and it splits the order across up to 10 positions, then moves the stop as the
ladder is hit.

## Why it matters here

The single strongest result in the v4 grid was a scale-out:

| | `V4_s1` | `V4_s1_part50` |
|---|---|---|
| equity DD | 9.15% **breach** | **2.47%** |
| trades | 39 | 70 |
| win rate | 61.5% | 80.0% |

`InpPartialPct=50` + `InpTrailATRMult=1.5` cut drawdown 3.7x. This repo is the same idea
taken further: a 5-level ladder defaulting to **60/10/10/10/10** - 60% banked at TP1 -
with the stop moved to TP1's price once TP2 fills. On an account where drawdown is the
binding constraint, that direction is the one the data already points at.

## The blocker, and it is the same one as jev-trader

The EA talks to Python over MQL5's native `Socket*` functions (`SocketCreate`,
`SocketConnect`, `SocketRead`, `SocketSend` - lines 141-210). **Socket functions do not
work in the MT5 Strategy Tester.** There is no `MQL_TESTER` guard either, so under the
tester it fails to connect and does nothing.

So the split logic **cannot be backtested through this EA**, which means the one question
worth answering - does 60/10/10/10/10 beat our 50/50, and does either beat no split -
cannot be answered by adopting it.

## How to actually use it

**Port the idea, not the bridge.** `SR_HTF_StopEntry_EA` already has a one-level
scale-out that *is* backtestable. Generalise it:

```
InpSplitLevels   1..5     number of TP levels (1 = today's behaviour)
InpSplitDist     "60,10,10,10,10"   volume share per level
InpSplitTPR      "1,2,3,4,5"        each level's target in R
InpSplitSLTo     level after which SL moves to the previous level's price
```

Then grid `60/10/10/10/10` against `50/50`, against `33/33/34`, against no split, over
2023-2026. That is a day's work and it answers the question. Taking the bridge instead
gives a system that cannot be measured.

Worth lifting verbatim while doing it - these are the parts they clearly got wrong once
and fixed:

- **Volume flooring** (lines 634-676): floor each slice to `SYMBOL_VOLUME_STEP`, reject
  the whole order if any nonzero slice floors below `SYMBOL_VOLUME_MIN`, and give the
  flooring leftover to the largest slice. Their error even computes the minimum viable
  `lot_size` for you.
- **The TP2 trigger** (lines 886-890): "filled and then closed" is `!OrderSelect(t) &&
  !PositionSelectByTicket(t)`. Checking positions alone misfires, because a pending stop
  that has not filled is not a position either - so TP2 reads as "closed" one tick after
  placement. They hit that and left the comment.
- **Group cleanup only when nothing is alive on any level**, pending or open. Their
  earlier version leaked groups forever once `tp2_reached` was set.
- Everything is selected **by ticket**, never by symbol. That is the same bug class we
  fixed across the four Sniper EAs, and this repo does not have it.

## Problems to fix if you do run it

| | |
|---|---|
| `MaxDailyLossPercent = 5.0` | **Exactly FundedNext's daily limit.** Zero headroom: the EA stops at the same number that fails the account. `SR_HTF` uses 2.5% for this reason. |
| `MaxPositions = 50` | 50 positions + pendings on a 25k account. `config.json` says 10, the EA input says 50, and the EA input is what runs. |
| README: *"Enable Allow DLL imports"* | Wrong. There is no `#import` anywhere. Native `Socket*` needs the **host and port added to the terminal's allowed-address list**, not DLL imports. Following the README leaves the terminal misconfigured and the failure looks like a server problem. |
| No `MQL_TESTER` guard | Attach it in the tester and it silently does nothing. |
| 5-level split needs `lot_size >= 0.10` | At 0.01 min lot, 10% of anything under 0.10 floors below minimum and the order is **rejected outright**. Our 0.5%-risk sets trade 0.18-0.21 lots so they fit; a 0.25%-risk set at ~0.09 lots would not. |
| Daily baseline is day-start **balance** vs live **equity** | Reasonable and conservative, but it ignores floating P&L carried into the day. `SR_HTF` uses `max(balance, equity)` at the day boundary. |

## Verdict

- As a strategy: **nothing to take.** It has none.
- As an execution layer to run SR_HTF's signals live: **plausible, but untestable**, and
  it would put an unmeasurable component in the one place where the measurement is the
  whole point.
- As engineering to copy into SR_HTF: **genuinely useful.** The volume flooring and the
  "filled then closed" test are both things we would otherwise get wrong on the first
  attempt.
- The MCP server is incidental to the trading question; it exposes the same REST surface
  to Claude, and the same no-backtest problem applies to anything it drives.
