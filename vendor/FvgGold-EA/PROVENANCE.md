# FvgGold EA — vendored third-party source

Not our code. Copied here so that
[`FvgGold_FN25K_2Step.set`](../../FvgGold_FN25K_2Step.set) is not pointing at an EA
that lives only on someone else's GitHub.

| | |
|---|---|
| Upstream | https://github.com/foeed/FvgGold-EA.git |
| Commit | `4fa57db` |
| Copied | 2026-09-29 |
| Licence | **MIT** — Copyright (c) 2026 foeed |
| Author | foeed |

MIT permits redistribution provided the copyright notice is kept, which is why
`LICENSE` is copied alongside the source. Do not edit `FvgGold.mq5` here — if it
needs changing, take it upstream or fork it properly. This copy exists so the preset
can be read against the exact version it was written for.

`FvgGold.set` is the author's own defaults, kept for comparison. Ours is
`FvgGold_FN25K_2Step.set` in the repo root.

## Not vendored: XAU-USD-Signal-Bot

The other repo cloned during this work, `Kiran-Kumbar/XAU-USD-Signal-Bot`, has **no
LICENSE file**, so it is all-rights-reserved by default and is not redistributable.
It stays outside this repo. Re-clone it if needed:

```
git clone https://github.com/Kiran-Kumbar/XAU-USD-Signal-Bot.git
```

## Status

**Never compiled and never backtested here.** There is no backtest in the upstream
repo either — no results, no equity curve, no data. The landing page shows an equity
chart and a demo video; that is the author's marketing, not something verifiable.

Two things found reading the source, both recorded in the preset's header:

- **No total-drawdown guard exists.** `DailyLossLimit` is the only protection in the
  EA. Nothing stops it at a cumulative loss.
- **Killzones ignore daylight saving.** Fixed GMT hours from `TimeGMT()`, so the
  windows sit an hour off their labels for about five months a year.
