# EMA Strategy — setup steps for the VPS

Paste this to Claude in the browser and follow it one step at a time.
Ask Claude if any step fails.

## What this is

- A MetaTrader 5 Expert Advisor: `SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5`
  (EMA 9/21 cross, scale-out TP ladder, runner mode).
- A Python dashboard: `ema_report.py` — reads the EA's log files and serves a
  web dashboard. Read-only. It can never place or close a trade.
- Everything runs on a Windows VPS that also runs MT5.

## Important before you start

- The dashboard reads FILES the EA writes. It does NOT connect to MT5 and does
  NOT read MT5's account history.
- `InpUseJsonLog` is `false` by default. That is the file the dashboard needs.
  If you forget this step the dashboard will be empty with no error.
- The EA has never been compiled. Step 3 is not optional.

---

## Step 1 — Copy the zip to the VPS

1. Connect to the VPS with Remote Desktop.
2. Drag `ema-strategy-v1.30.zip` into the RDP window, onto the Desktop.
3. If you downloaded it in the VPS browser instead: right-click the zip →
   Properties → tick **Unblock** → OK.
4. Right-click → **Extract All** → extract to the Desktop.

## Step 2 — Install Python

1. Download Python 3.8 or newer from python.org.
2. On the first install screen, tick **Add python.exe to PATH**. This matters.
3. Open Command Prompt and run:
   ```
   python --version
   ```
4. It must print a version number. If it says "not recognized", reinstall and
   tick the PATH box.

Nothing else to install.

## Step 3 — Put the files in the right folders

1. Open MT5 → **File → Open Data Folder**. A window opens. Keep it open.
2. Go into `MQL5\Experts\`.
3. Copy `SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5` into it.
4. Make a new folder `C:\ea-dashboard\`.
5. Copy `ema_report.py` into `C:\ea-dashboard\`.
6. Leave the `.md` files on the Desktop.

## Step 4 — Compile the EA

1. In MT5 press **F4** to open MetaEditor.
2. In the Navigator on the left, open `Experts` → double-click the
   `SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5` file.
3. Press **F7**.
4. The bottom panel must say `0 errors, 0 warnings`.
5. If there are errors, copy them and ask Claude.

## Step 5 — Save your old log file

Only if you ran an earlier version of this EA.

1. In the data folder window, go into `MQL5\Files\`.
2. Find `SniperEA_Log_<SYMBOL>_<TF>.csv`.
3. Rename it to `SniperEA_Log_<SYMBOL>_<TF>_pre130.csv`.
4. Do not delete it. Your old trade history is in it.

Reason: the new version writes 2 extra columns. If it appends to the old file,
the balance and equity columns get shifted and the equity chart goes wrong.

## Step 6 — Run a backtest first

1. In MT5 press **Ctrl+R** to open the Strategy Tester.
2. Choose the EA, your symbol, your timeframe, a few months of dates.
3. In the Inputs tab set:
   - `InpUseJsonLog` = `true`
   - `InpLogSkips` = `true`
   - `InpTesterFreshLog` = `true`
   - `InpServerGmtOffset` = your broker's GMT offset (GMT+3 → `3.0`)
4. Click Start and let it finish.
5. Do not skip this. It is how you check the EA behaves before real money.

## Step 7 — Attach the EA to a live chart

1. Open a chart for your symbol and timeframe.
2. Drag the EA from the Navigator onto the chart.
3. In the **Inputs** tab set:

   | Input | Value |
   |---|---|
   | `InpUseJsonLog` | `true` |
   | `InpUseCsvLog` | `true` |
   | `InpLogSkips` | `true` |
   | `InpServerGmtOffset` | your broker's GMT offset |
   | `InpMagic` | a unique number for this chart |
   | `InpTgToken` | your Telegram bot token (optional) |
   | `InpTgChatId` | your Telegram chat id (optional) |

4. Click OK.
5. Check the **AutoTrading** button in the toolbar is **green**, not red.
   A red button means the EA runs but never places an order, silently.
6. Check there is a smiley face in the top-right corner of the chart.

## Step 7b — The signals-only instance (optional)

A second EA that posts Telegram signals and places no orders.

1. Open a **second chart** of the same symbol and timeframe. One EA per chart.
2. Drag the EA on, then **Load** `SniperEA_Signal.set` in the Inputs tab.
3. Check three values survived the load:

   | Input | Must be |
   |---|---|
   | `InpSignalsOnly` | `true` |
   | `InpMagic` | **different** from your trading chart |
   | `InpCsvPrefix` | **different** from your trading chart |

Those last two are not cosmetic. Three close paths in the EA gate only on
`POSITION_MAGIC == InpMagic`, so a shared magic number lets the "signals only"
instance close your real position. A shared prefix makes both instances write the
same log and the same state file.

### The two preset files

| File | For |
|---|---|
| `SniperEA_Trade.set` | the account — places orders |
| `SniperEA_Signal.set` | the feed — posts to Telegram, places nothing |

They differ in 11 inputs; the other 120 are identical.

**Only the `.example.set` versions are in the repo.** The real files hold a live
bot token and are gitignored — a private repo is not a secret store, and a token
committed once stays in the history. On a new machine:

```bat
copy SniperEA_Trade.example.set  SniperEA_Trade.set
copy SniperEA_Signal.example.set SniperEA_Signal.set
```

then fill in `InpTgToken` and `InpTgChatId` in the copies.

Verify the pipe before trusting it: `InpTgNotifyStart` is on, so attaching the EA
should post an "EA online" card straight away. If nothing arrives, the Experts
tab says which of the two failures it was — the WebRequest whitelist, or the
token/chat id.

## Step 8 — Find the log folder path

1. In the data folder window, go into `MQL5\Files\`.
2. Copy the full path from the address bar. It looks like:
   ```
   C:\Users\YOU\AppData\Roaming\MetaQuotes\Terminal\LONGHASH\MQL5\Files
   ```
3. You should see files starting with `SniperEA_Log_`.

This is NOT the folder where MT5 is installed. Using the install folder is the
most common mistake.

## Step 9 — Start the dashboard

1. Open Command Prompt.
2. Run this, with your path from Step 8:
   ```
   cd C:\ea-dashboard
   python ema_report.py "C:\Users\YOU\AppData\Roaming\MetaQuotes\Terminal\LONGHASH\MQL5\Files\*.jsonl" --serve 8800 --poll 5
   ```
3. If you have an old log from Step 5, include it too:
   ```
   python ema_report.py "C:\...\MQL5\Files\*.jsonl" "C:\...\MQL5\Files\*.csv" --serve 8800 --poll 5
   ```
4. Open `http://localhost:8800` in the VPS browser.

Never use `--host 0.0.0.0`. That publishes your account balance to the internet.

## Step 10 — Check it is working

| Check | Expected |
|---|---|
| Command Prompt output | `read 1 state file(s)` |
| Live tab badge | green, says **live** |
| Balance shown | matches MT5's Trade tab |
| Wait 5 minutes | the time keeps updating |

The Live tab works immediately. The other tabs stay empty until trades close.
That is correct, not a fault.

## Step 11 — Make the dashboard restart automatically

1. Open **Task Scheduler** → **Create Task** (not Basic Task).
2. General tab: tick **Run whether user is logged on or not** and
   **Run with highest privileges**.
3. Triggers tab: New → **At startup**.
4. Actions tab: New → Start a program:
   - Program: `C:\Path\To\python.exe`
   - Arguments: `ema_report.py "C:\...\MQL5\Files\*.jsonl" --serve 8800 --poll 5`
   - Start in: `C:\ea-dashboard`   (do not leave this blank)
5. Settings tab: tick **If the task fails, restart every 1 minute**, and untick
   **Stop the task if it runs longer than**.

## Step 12 — Make MT5 restart automatically

MT5 needs a logged-in Windows session. Task Scheduler will not work for it.

1. Press `Win+R`, type `netplwiz`, Enter.
2. Untick **Users must enter a user name and password**. Enter the password.
3. Press `Win+R`, type `shell:startup`, Enter.
4. Put a shortcut to `terminal64.exe` in that folder.
5. When leaving RDP, click the **X** to disconnect. Never click **Log off** —
   logging off closes MT5.

## Step 13 — Test a reboot

1. Reboot the VPS.
2. Wait, reconnect, and check:
   - MT5 opened by itself
   - The chart has the EA on it
   - AutoTrading is green
   - `http://localhost:8800` still loads

If MT5 did not open, Step 12 did not work. Fix it now, not later.

## Step 14 — Phone access (optional, do later)

Follow `CLOUDFLARE_SETUP.md`. Summary:
1. Install cloudflared on the VPS.
2. Create a Cloudflare Tunnel pointing to `localhost:8800`.
3. Put a Cloudflare Access policy in front, restricted to your email.

Do not skip the Access policy. Without it anyone with the link sees your balance.

---

## Common problems

| Problem | Cause |
|---|---|
| Dashboard is empty | `InpUseJsonLog` is `false`. Set it to `true`. |
| `No events loaded and no state file found` | Wrong folder path. Redo Step 8. |
| `python is not recognized` | PATH box not ticked during install. Reinstall. |
| EA does nothing, no errors | AutoTrading button is red. |
| Badge says **EA down?** | The EA is not running. Check the chart. |
| Balance column looks wrong | You appended to an old CSV. Redo Step 5. |
| Trades in all wrong sessions | `InpServerGmtOffset` is wrong. |

## Files in the zip

| File | What it is |
|---|---|
| `SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5` | the EA |
| `ema_report.py` | the dashboard |
| `EA_GUIDE.md` | every EA input explained |
| `REPORT_AND_DEPLOY.md` | dashboard details, backtest use |
| `CLOUDFLARE_SETUP.md` | phone access |
| `RESTART_RECOVERY.md` | what happens on a crash |
| `DEPLOY_STEPS.md` | this file |
