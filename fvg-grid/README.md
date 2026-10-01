# fvg-grid - FvgGold-EA

---

## Killzone grid - 28 sets, six months

```
.\RUN_FVG_KZ.bat        28 sets, 2026.04.01-2026.09.30, M15, ~35 min
```

Reports land in `results_2026H2_M15_kz_m1/`. `RUNSETS.bat` gained `FROMDATE` /
`TODATE` / `PERIODTAG` for this: a six-month window cannot be expressed as a calendar
year, and without them each year argument still runs 01.01 to 12.31 as before.

### Three properties of this EA that the sets are built around

**1. `DailyLossLimit` is in DOLLARS, not percent.** The vendor default is `5.0` - five
dollars. On a 25k account that halts the EA after almost any losing trade. Every set
here uses `300`.

**2. `KZ_OverlapEnd` is inert in the default mode.** From `IsKillzoneActive`:

```cpp
bool londonOpen = (hour >= KZ_LondonStart && hour < KZ_LondonEnd);
bool overlap    = (hour >= KZ_OverlapStart && hour < KZ_OverlapEnd);
bool nySession  = (hour >= KZ_OverlapStart && hour < KZ_NYEnd);
return(londonOpen || overlap || nySession);
```

`nySession` starts at `KZ_OverlapStart`, so it already contains `overlap` whenever
`KZ_NYEnd > KZ_OverlapEnd`. The live window is `[LondonStart,LondonEnd)` union
`[OverlapStart,NYEnd)`, and **there is no separate NY start input** - `KZ_OverlapStart`
is it. `KZ_OverlapEnd` only bites when `KZ_PreferOverlap=true`, which short-circuits the
function, so every `FKZ_ovl_*` set sets that flag. Varying `KZ_OverlapEnd` without it
would have produced a block of identical sets - the same trap that cost three SR_HTF
grids.

**3. The hours are not knowable from the code.** `IsKillzoneActive` reads `TimeGMT()`,
which the Strategy Tester derives from the **host machine's** timezone offset, and the EA
has no GMT-offset input to correct with. So the windows are **swept**, not asserted,
including whole +2 and +3 shifts (`FKZ_both_sh2`, `FKZ_both_sh3`). If a shifted set wins,
the VPS clock is the finding, not a session edge.

### The sets

| block | sets | window |
|---|---|---|
| anchors | `FKZ_nokz`, `FKZ_ctrl` | no filter / vendor default |
| London only | `FKZ_lon_6_9` … `FKZ_lon_6_12` (6) | NY disabled by `OverlapStart == NYEnd` |
| NY only | `FKZ_ny_12_16` … `FKZ_ny_16_20` (6) | London disabled by `LondonStart == LondonEnd == 0` |
| overlap only | `FKZ_ovl_12_15` … `FKZ_ovl_12_18` (6) | `KZ_PreferOverlap=true` |
| Asia | `FKZ_asia_0_4`, `FKZ_asia_0_6` | borrows the London pair; it **cannot wrap midnight** - `hour>=23 && hour<3` is never true |
| clock shift | `FKZ_both_sh2`, `FKZ_both_sh3` | both sessions moved +2 / +3 |
| quality | `FKZ_ovl_score70`, `FKZ_ovl_score35`, `FKZ_ovl_noob`, `FKZ_ctrl_eod` | is the session doing the work, or the score filter? |

28 sets, verified none identical.

### Reading it

`FKZ_nokz` first. **If no windowed set beats trading every hour, the killzone idea is
worth nothing on this EA** and the rest of the table is noise.

Then trade count. Six months of M15 is a small sample before you cut it to three hours a
day; under ~30 trades a set has said nothing whatever its net. Six months is **half a
sample** - any winner here is a candidate for real ticks and 2023-2025, never a result.
