# sma+sniper+turtle.pine — killzone ranges, and two layers removed

## Killzone highs and lows on the dashboard

The Killzones layer **shades** the sessions. Shading tells you *when*; it never
tells you *where* — and where is the part you trade against. The Asian range
high and low are the pools London raids; London's are what New York runs.

Three rows now carry those numbers:

```
KILLZONE      high / low
Asia     4361.20 / 4342.10  ⇑
London   4370.50 / 4355.00  ●
New York    no session yet
```

| Mark | Meaning |
|---|---|
| `●` | session is **open** — the range can still widen |
| `⇑` `⇓` `⇕` | that side has been **taken** since the session closed |
| *(none)* | closed, neither side touched yet |

Settings group **`Killzone ranges (dashboard) 📐`**:

```
kzrOn        true          show the three rows
kzrTz        America/New_York
kzrAsSess    1900-2400     Asian range
kzrLdnSess   0200-0500     London killzone
kzrNySess    0700-1000     New York session
kzrMid       false         also print the 50% of each range
```

All three read on **one clock** so they cannot drift apart, and New York handles
US daylight saving per bar. Widen `kzrNySess` to `0700-1600` if you want the
whole cash session rather than the killzone.

### Two decisions worth knowing

**The range is held after the session closes**, not blanked. It resets on the
bar the session next opens. Blanking at the close would clear the numbers at
exactly the moment you start trading against them.

**The sweep marks only arm after the close.** A wick through the high *during*
the session is just the session making its high — it is only a raid once the
range is fixed. Hovering any row gives the window in both clocks, the midpoint,
the range width, and which side was taken.

---

## A week of them, and what has been taken

One session's high is taken several times a week and means little. **The high
that has stood across every session of that killzone for a week** is where
stops have had time to pile up — and taking that is the event worth knowing
about without scrolling back through the chart.

```
KILLZONE      high / low
Asia     4361.20 / 4342.10  ⇑
London   4370.50 / 4355.00  ●
New York 4358.00 / 4349.80
  wk Asia    4390.10 / 4318.40  5d
  wk London  4402.00 / 4331.00  5d
  wk NY      4381.50 / 4327.90  4d
MAJOR SWEEPS          3 kept
  19 14:22   Asia H  ⇑
  18 09:05   London L  ⇓
  17 16:40   NY H  ⇑
```

`kzrDays` (default **5**, a trading week) sets how many completed sessions of
each killzone are remembered. The weekly level is the extreme across them; the
`5d` suffix is how many sessions are actually held, so a fresh chart says `1d`
rather than pretending to a week it does not have.

A sweep is logged **once per level**. When a new session prints a new extreme
the level is replaced and re-armed, so the same event is never logged twice.

### The edge case that made this harder than it looks

The weekly level does not only rise. **When the oldest session drops out of the
history, the level can fall** — and if price is already above it, arming that
blindly logs a sweep of a level the market left behind days ago. An event that
never happened.

So a level re-arms only when price is still on the near side of it:

```pine
array.set(kzrArmed, _i, _up ? high <= _lvl : low >= _lvl)
```

Verified against four cases: a genuine break fires once; repeated bars above it
do not re-fire; the oldest session dropping out fires nothing; a genuinely
higher new extreme re-arms and can fire again.

### What it does not tell you

Whether the sweep was **rejected**. A wick through that closes back inside is
the raid; a close beyond it is a break, and those read opposite ways. The log
records that the level was taken, not what happened next — that judgement stays
with you, and the row tooltip says so.

---

## Removed

| Layer | Lines | Why |
|---|---|---|
| **3-1-3 / 3-2-3 candle patterns** | 86 | shipped OFF (`enablePattern`), never enabled |
| **CISD** *(Change in State of Delivery)* | 254 | shipped OFF (`enableCISD`), never enabled |

**340 lines, 3872 → 3623.** Before deleting, every identifier defined inside
each block was grepped against the rest of the file. The only names that also
appear elsewhere are `result`, `p`, `top`, `bot` and `rightX` — generic locals
with their own scopes, not references. Nothing was orphaned.

Layers renumbered so the banners stay in sequence: HTF Candles is now THIRD,
Killzones FOURTH, Turtle Soup FIFTH, OTE SIXTH, Day/Week/Month H-L SEVENTH,
Buyside/Sellside EIGHTH.

---

## One implementation note

`f_kzRange` takes the previous in-session flag as a **parameter** rather than
reading `_in[1]` inside itself. The file's own killzone helpers
(`f_kzName`, `f_kzVline`) already do this, and the reason holds: a history
reference on a parameter only advances on the bars the function is actually
called, so it is only safe when every call site is unconditional. Passing it in
removes the question.

The state machine was simulated across open → widen → close → sweep high →
sweep low → reopen: the range resets only on the opening bar, holds after the
close, and the sweep flags clear on reopen.

---

> **Not compiled.** Structural checks only — delimiters balance, all helpers are
> defined before use, no orphaned identifiers. Paste it into TradingView and
> read the console once.
