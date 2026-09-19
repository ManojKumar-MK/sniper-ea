//+------------------------------------------------------------------+
//|                                          EmaStrategy_EA.mq5       |
//|   EMA Based Strategy module.                                      |
//|                                                                   |
//|   Copyright 2026, Manojkumar K                                    |
//|   mailtomktech@gmail.com                                          |
//|   Free to use as of now.                                          |
//|                                                                   |
//|   Signal:                                                         |
//|     buy  = EMA9 crosses ABOVE EMA21 ; sell = crosses BELOW        |
//|     one-position state machine (flip on opposite signal)          |
//|     SL = ATR(14)*mult ; targets = 1R..5R                          |
//|     optional Signal Quality Filter (ADX/EMA50/VWAP/vol/bias/CD)   |
//|                                                                   |
//|   v1.10 - 5-level target ladder                                   |
//|                                                                   |
//|   v1.20 (this build) adds:                                        |
//|     1) NO PARTIAL IS EVER BOOKED. Full size is carried to TP5 and |
//|        the stop moves up one level at a time:                     |
//|        TP1->breakeven, TP2->TP1, TP3->TP2, TP4->TP3, TP5->close.  |
//|        Same in both sessions.                                     |
//|     2) The IST clock sets the stop width, and the evening session |
//|        can be switched off or thinned out by the hour:            |
//|          12 AM - 4 PM IST -> usual stop, ATR * InpSlAtrMult       |
//|          4 PM - 12 AM IST -> that stop cut to HALF (x0.5)         |
//|     3) Order comments tagged with the exit level:                 |
//|        "TP1 exit", "TP2 exit", ... "SL exit", "BE exit".          |
//|     4) Every entry logs its full reason set (EMA/ADX/MACD/RSI/    |
//|        VWAP/ATR/volume/bias + quality-filter flags) on its own    |
//|        [LOGIC] and [FILTER] lines.                                |
//|     5) ONE fixed format for every event (entry, TP, SL move,      |
//|        exit, day summary): CSV for reports, JSON for parsing.     |
//|     6) Weekend guard - flat before the Friday close by default.   |
//|     7) FLIP logged explicitly, and an end-of-day consolidated     |
//|        gross / net result.                                        |
//|                                                                   |
//|   NOTE: validate in the Strategy Tester / on demo before running  |
//|   this live - real spread and slippage change the results.        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Manojkumar K - mailtomktech@gmail.com"
#property link      "mailto:mailtomktech@gmail.com"
#property description "EMA Based Strategy module - free to use as of now."
#property version   "1.30"
#property strict

#include <Trade/Trade.mqh>

//====================================================================
//  INPUTS
//====================================================================
input group "-- Signal (Sniper core) --"
input int      InpEmaFast        = 9;
input int      InpEmaMid         = 21;
input int      InpEmaTrend       = 50;
input int      InpAtrPeriod      = 14;
input bool     InpTradeOnClose   = true;    // act only on closed bars

input group "-- Risk & stop --"
input double   InpRiskPercent    = 0.5;     // risk per trade (% of balance)
input bool     InpUseFixedLot    = false;   // one fixed lot for every trade, both sessions
input double   InpFixedLot       = 0.10;
input bool     InpUseSessionLots = true;    // a separate fixed lot per IST session (overrides the two above)
input double   InpDayLot         = 0.05;    // lot for entries 12 AM - 4 PM IST
input double   InpEveningLot     = 0.05;    // lot for entries 4 PM - 12 AM IST
//  Sizing precedence, highest first:
//    1) InpUseSessionLots -> InpDayLot / InpEveningLot, chosen by the IST session of the entry
//    2) InpUseFixedLot    -> InpFixedLot for every trade
//    3) neither           -> risk-%% sizing off InpRiskPercent and the real stop distance
//  Both session lots default to 0.05. Remember the evening stop is halved, so the SAME lot
//  there risks HALF the money of a day trade - set InpEveningLot higher if you want them equal.
input double   InpSlAtrMult      = 2.0;     // SL = ATR * this (source default 2.0)

input group "-- Take-profit: 5-level target ladder --"
input bool     InpUseScaleOut    = true;    // ON = 5 partial TPs; OFF = single TP
input double   InpTP1_R          = 1.0;     // target 1 in R
input double   InpTP2_R          = 2.0;
input double   InpTP3_R          = 3.0;
input double   InpTP4_R          = 4.0;
input double   InpTP5_R          = 5.0;
input double   InpPartialPct      = 20.0;   // % of the ORIGINAL position closed at each TP
input bool     InpTrailBehindTP  = true;    // BE after TP1, then SL to the previous TP
input double   InpTpRMultiple     = 3.0;    // (single-TP mode only) TP in R
input bool     InpMoveToBE_Single = true;   // (single-TP mode only) BE after +1R

input group "-- FULL TARGET: never book a partial --"
input bool     InpUseFullTarget     = true;  // ON = NO partial is ever booked. Full size runs to TP5,
                                             //      the stop steps up one level at a time:
                                             //      TP1 -> breakeven, TP2 -> TP1, TP3 -> TP2, TP4 -> TP3, TP5 -> close.
                                             // OFF = fall back to the old 20%-per-TP scale-out.

input group "-- Strategy Tester --"
input bool     InpTesterFreshLog = true;  // in the Tester, wipe the log and state files at the start of
                                          // each run so one backtest = one clean file. Off = runs append
                                          // to each other, which makes the report meaningless.

input group "-- Signal audit --"
input bool     InpLogSkips       = true;  // log every EMA cross that was NOT taken, with the reason.
                                          // One SKIP row per closed bar, only when a cross actually
                                          // happened - so the report can finally show what the filters
                                          // and gates rejected, not just the trades that got through.

input group "-- Heartbeat --"
input int      InpHeartbeatMin   = 5;    // rewrite the state file every N minutes even when nothing
                                         // happens, so its timestamp proves the EA is alive rather
                                         // than only proving something last traded. 0 = off.
                                         // Runs on a timer, not on ticks, so it still beats when the
                                         // market is quiet - a stale timestamp then means the EA is
                                         // actually down, which is the whole point of it.

input group "-- TP5: book it, or let it run --"
input bool     InpBookAtTP5       = true;  // TRUE  = book at TP5 and close the trade. This is the
                                           //         default and the behaviour you already have.
                                           // FALSE = TP5 no longer closes. The position runs on and the
                                           //         stop keeps stepping one rung behind, exactly as it
                                           //         does below TP5: 6R -> SL to TP5, 7R -> SL to 6R, ...
                                           //         The trade then ends on the opposite EMA cross, the
                                           //         trailed stop, or any of the usual guards.
//  The two inputs below only do anything when InpBookAtTP5 is FALSE.
input double   InpRunnerStepR     = 1.0;   // R spacing of the rungs above TP5 (1.0 = 6R, 7R, 8R, ...)
input bool     InpFlipExitAnyTime = true;  // ON = an opposite cross CLOSES a runner even outside the
                                           //      entry window. No new position is opened there - the
                                           //      window still governs entries. OFF = the runner waits
                                           //      for the window to reopen, with only the stop guarding it.

input group "-- IST session: stop size only (12 AM - 4 PM vs 4 PM - 12 AM) --"
input int      InpDaySessionStartIST = 0;    // DAY session START hour IST, INCLUSIVE (0 = 12 AM midnight)
input int      InpDaySessionEndIST   = 16;   // DAY session END   hour IST, EXCLUSIVE (16 = 4 PM)
input bool     InpUseHalfSlOutside   = true; // ON = entries in the EVENING session use a smaller stop
input double   InpOutsideSlFactor    = 0.5;  // multiplier on the usual ATR stop (0.5 = half the usual SL)
input bool     InpTpFromHalvedRisk   = true; // TRUE  = 1R is the HALVED stop, so TP1..TP5 come proportionally closer
                                             // FALSE = TP1..TP5 stay at the FULL ATR distances, only the stop tightens
//  The stop width is what the two sessions change by default:
//    12 AM - 4 PM IST (day)     -> usual stop, ATR * InpSlAtrMult
//    4 PM - 12 AM IST (evening) -> that stop multiplied by InpOutsideSlFactor (0.5 = half)
//  Management is identical in both: no partials, full size to TP5, SL stepped one level at a time.
//  The session is decided ONCE, at the moment the entry is taken, and stays with that trade.
//  Start == End => the whole day counts as the day session. Start > End => the window wraps past midnight.
//
//  With InpTpFromHalvedRisk = TRUE the whole R structure simply shrinks in the evening: same 1R..5R
//  ladder, half the distance, and risk-% sizing gives a bigger lot for the same money at risk.
//  With FALSE the targets stay where they were and evening trades become 2R..10R plays off a
//  half-size stop - better reward per unit of risk, lower hit rate. Test both.

input group "-- EVENING SESSION: skip it, narrow it, or punch holes in it --"
input bool     InpTradeEvening     = true;   // master switch for the 4 PM - 12 AM IST session.
                                             // FALSE = no NEW entries in the evening at all. An open
                                             // trade is never touched by this - it runs to its own
                                             // SL/TP exactly as before.
input int      InpEveEntryStartIST = 16;     // narrow the evening ENTRY window, IST hour, INCLUSIVE
input int      InpEveEntryEndIST   = 0;      // ...and EXCLUSIVE end (0 = midnight). 16/0 = the whole
                                             // evening block. 16/20 would allow only 4 PM - 8 PM.
//  Per-hour toggles. Untick a single hour to skip it while keeping the rest of the evening.
//  These apply ONLY to hours that fall inside the evening session - the day session is never
//  affected by them. An evening hour with no toggle listed here is allowed.
input bool     InpEveH16 = true;   // 4 PM - 5 PM IST
input bool     InpEveH17 = true;   // 5 PM - 6 PM IST
input bool     InpEveH18 = true;   // 6 PM - 7 PM IST
input bool     InpEveH19 = true;   // 7 PM - 8 PM IST
input bool     InpEveH20 = true;   // 8 PM - 9 PM IST
input bool     InpEveH21 = true;   // 9 PM - 10 PM IST
input bool     InpEveH22 = true;   // 10 PM - 11 PM IST
input bool     InpEveH23 = true;   // 11 PM - 12 AM IST
//  All three compose. An evening entry is allowed only when the master switch is on AND the IST
//  hour is inside the window above AND that hour's toggle is ticked. Every refusal is written to
//  the log as its own SKIP row, so the dashboard shows exactly which hours you turned off and
//  what they would have cost you.
//
//  The stop is UNCHANGED by any of this: the evening still uses InpOutsideSlFactor (half by
//  default). These inputs decide WHETHER to enter, never how wide the stop goes.
//
//  IMPORTANT: the server-clock entry window (InpSessionStartHour / InpSessionEndHour) still
//  applies on top. With the default 0-11 on a GMT+3 broker that is 02:30-13:30 IST, which never
//  reaches the evening at all - so none of these settings can do anything until you widen it.
//  The EA prints a warning at startup when that is the case.

input group "-- Per-session risk % (only when session lots and fixed lot are both off) --"
input bool     InpUseSessionRisk   = false;  // ON = use the two figures below instead of InpRiskPercent
input double   InpDayRiskPct       = 0.5;    // risk per trade, 12 AM - 4 PM IST
input double   InpEveningRiskPct   = 0.25;   // risk per trade, 4 PM - 12 AM IST
//  Sizing precedence is unchanged: session lots beat fixed lot, fixed lot beats risk-%. This only
//  splits the risk-% branch in two. Remember the evening stop is already halved, so the SAME risk %
//  there buys roughly double the lot - set InpEveningRiskPct lower if you want the smaller size too.

input group "-- IST clock conversion --"
input bool     InpAutoGmtOffset   = false;  // OFF by default. Auto-detect derives the offset from
                                            // TimeCurrent(), which is the last QUOTE time and stops
                                            // advancing when ticks stop - so a quiet feed silently
                                            // shifts it. Set InpServerGmtOffset to your broker's real
                                            // offset instead, and revisit it when the broker changes
                                            // for DST (most are GMT+2 winter / GMT+3 summer).
input double   InpServerGmtOffset = 3.0;    // fallback / tester value: broker server offset from GMT in hours (GMT+3 = 3.0)
//  IST is GMT+5:30. The EA converts server time -> IST using the offset above, so the
//  window inputs are read as real Indian time whatever clock your broker runs on.

input group "-- Weekend handling --"
input bool     InpHoldOverWeekend   = false; // FALSE = flatten before the Friday close and take no new trades after it
                                             // TRUE  = leave positions open over the weekend
input int      InpFridayCloseBufferMin = 15; // close this many minutes BEFORE the Friday session close
input int      InpFridayCloseHour    = -1;   // -1 = read the Friday close from the broker's trading sessions (recommended)
                                             //  0..23 = force a fixed hour on the SERVER clock instead
input int      InpFridayCloseMinute  = 0;    // minute of that fixed hour (only used when the hour above is >= 0)
input bool     InpBlockFridayEntries = true; // also refuse NEW entries once the cutoff is reached
//  With auto-detect the EA asks the broker when Friday trading ends for this symbol and works
//  backwards by the buffer. It prints the resulting cutoff on startup, so check the Experts tab once.
//  If your broker reports no session data, set InpFridayCloseHour/Minute manually.

input group "-- FUNDED / PROP ACCOUNT MODE --"
input bool     InpPropMode          = false; // OFF by default. Turn ON only on a funded/prop account.
//  OFF: none of the funding guards run and none of their lines are printed - the EA trades
//       with only the spread, session, weekend and news checks.
//  ON : the baseline, daily loss cap, losing-trade count and overall loss guard below all
//       become active, print on startup and at each session open, and alert on Telegram.
//  NOTE: with this OFF there is NO daily loss cap, even though the % below has a value.
//        Turn it on if you want that protection on a personal account too.

input group "-- On-chart dashboard --"
input bool     InpShowPanel       = true;   // draw the status panel on the chart
input int      InpPanelCorner     = 0;      // 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right
input int      InpPanelX          = 12;     // pixels from that corner
input int      InpPanelY          = 22;
input int      InpPanelFont       = 9;
input string   InpPanelFontName   = "Consolas";  // a monospaced font keeps the columns aligned
input color    InpPanelBg         = C'18,22,30';
input color    InpPanelText       = clrGainsboro;

input group "-- Restart recovery --"
input bool     InpPersistState      = true;  // remember the open trade + the day's tally across restarts
//  Without this, an MT5 restart mid-trade leaves the position open at the broker while the EA
//  forgets it: no TP ladder, no stop steps, no exit audit, and the day's loss count resets.
//  State is written to <CsvPrefix>_<symbol>_<tf>_state.txt in MQL5/Files after every event.

input group "-- Account baseline (all loss limits measure against this) --"
input double   InpBaselineBalance   = 0.0;   // funded-account starting balance. 0 = use the balance at EA start
//  A funded account's limits are set against the ORIGINAL account size, not whatever the
//  balance happens to be today. Enter that figure here (e.g. 100000) and every cap below
//  is computed from it. Leave 0 and the EA falls back to the balance when it first loaded.

input group "-- Daily loss guard --"
input int      InpDayResetHour      = 0;     // hour the trading day RESETS (prop firms rarely use midnight)
input int      InpDayResetMinute    = 0;
input bool     InpDayResetUseIST    = false; // false = broker/server clock, true = IST
input double   InpMaxDailyLossPct   = 4.0;   // daily loss cap, % of the baseline above (0 = off)
input double   InpMaxDailyLossMoney = 0.0;   // daily loss cap in cash (0 = off). The TIGHTER of the two applies
input double   InpDailyWarnPct      = 75.0;  // warn on Telegram once the day's loss reaches this % of the cap
input int      InpMaxLossesPerDay   = 3;     // stop after this many losing trades in a day (0 = off)
input bool     InpCloseOnDailyCap   = true;  // flatten the open position when a cap is hit

input group "-- Overall loss guard (account-level) --"
input int      InpDrawdownMode      = 2;     // 0 = from the static baseline, 1 = from PEAK equity (trailing), 2 = both
//  Firms differ: some measure max loss from the account's starting balance, some from the
//  highest equity ever reached (trailing drawdown). 2 applies BOTH and stops at whichever
//  is hit first - the safe choice when you are not certain which your firm uses.
input double   InpMaxTotalLossPct   = 10.0;  // max loss from the baseline, % (0 = off)
input double   InpMaxTotalLossMoney = 0.0;   // max loss from the baseline, cash (0 = off)
input double   InpTotalLossStopPct  = 90.0;  // STOP at this % of the max, so the real limit is never touched
input double   InpTotalWarnPct      = 70.0;  // warn on Telegram at this % of the max
//  Example: baseline 100000, max total loss 10% = 10000, stop at 90% = the EA halts for good
//  once equity is 9000 below the baseline - leaving 1000 of headroom before the breach.

input group "-- News filter --"
input bool     InpUseNewsFilter   = false;  // OFF by default. ON = pause NEW entries around scheduled news
input int      InpNewsMinsBefore  = 15;     // no new entries from this many minutes BEFORE the release
input int      InpNewsMinsAfter   = 15;     // and until this many minutes AFTER it
input int      InpNewsImportance  = 2;      // minimum importance: 0 = low, 1 = moderate, 2 = high
input string   InpNewsCurrencies  = "";     // comma list, e.g. "USD,EUR". Empty = the symbol's own currencies
input bool     InpNewsCloseOpen   = false;  // FALSE = an open trade keeps running through the news (recommended)
input string   InpNewsManualTimes = "";     // manual releases "2026.09.19 18:00;2026.09.20 12:30" (tester / fallback)
input bool     InpNewsManualIsIST = false;  // true = the times above are IST, false = server time
input bool     InpNewsTgAlerts    = true;   // Telegram: post what is coming, and when entries pause / resume
input int      InpNewsAlertMins   = 15;     // post the heads-up this many minutes before the release
//  How it behaves with InpUseNewsFilter = true:
//    T-15min  entries stop. An open trade is NOT touched - it runs to its own SL/TP.
//    T+15min  entries resume; the next signal is taken normally.
//  InpNewsTgAlerts works INDEPENDENTLY of the filter: leave the filter off and you still get
//  a formatted heads-up on Telegram telling you what is due and when.
//  The live calendar needs the terminal connected. Calendar functions are NOT available in
//  the Strategy Tester - there, list the releases in InpNewsManualTimes instead.

input group "-- Other guards --"
input int      InpMaxSpreadPts    = 50;     // skip entries above this spread (points, 0=off)
input long     InpMagic           = 990021;

input group "-- Run mode --"
input bool     InpSignalsOnly    = false;     // TRUE = broadcast Telegram signals only, place NO orders
//  Run TWO copies of this EA:
//    * one with InpSignalsOnly=TRUE  -> pure signal feed (lot size / booking are irrelevant here)
//    * one with InpSignalsOnly=FALSE -> trades your account with your own lots & booking

input group "-- Session / time filter  (EDIT THESE TO TEST) --"
input bool     InpUseSessionFilter = true;   // ON = only enter inside the window below
input int      InpSessionStartHour  = 0;     // window START hour, INCLUSIVE  (broker/server clock)
input int      InpSessionEndHour    = 11;    // window END hour,   EXCLUSIVE  (broker/server clock)
//  Hours are your BROKER/SERVER time (the clock shown top-right on the chart / in the tester).
//  From the YTD analysis the only profitable block is Asian + Off-hours. On a GMT+3 server that is:
//        InpSessionStartHour = 0 ,  InpSessionEndHour = 11        (trades 00:00 - 10:59 server)
//  Tighter "Asian only":  Start = 3 ,  End = 11.
//  If your server is GMT+2, shift both back one hour (e.g. Start = 23 , End = 10 - the wrap is handled).
//  Start == End  => filter off (whole day). Start > End  => window wraps past midnight.

input group "-- Telegram alerts  (live/demo only - NOT in Strategy Tester) --"
input bool     InpUseTelegram    = false;      // master switch for Telegram push
input string   InpTgToken        = "";         // bot token from @BotFather
input string   InpTgChatId       = "";         // your chat id (@userinfobot; groups/channels are negative)
input string   InpTgPrefix       = "SniperEA"; // label prefixed to every message
input bool     InpTgNotifyStart  = true;       // ping on EA start (use once to test the pipe)
input bool     InpTgNotifyEntry  = true;       // BUY / SELL opened
input bool     InpTgNotifyTP     = true;       // each TP hit
input bool     InpTgNotifyClose  = true;       // position fully closed / stopped out
input bool     InpTgNotifyHalt   = true;       // daily loss cap hit
input bool     InpTgNotifyEOD    = true;       // end-of-day consolidated result
input bool     InpTgNotifyPeriod = true;       // weekly / monthly roll-up, same table treatment
input bool     InpTgHtmlStyle    = true;       // send styled (bold/monospace) messages instead of plain text
input bool     InpTgDayTable     = true;       // end-of-day: table of every trade taken that day
input double   InpPipSize        = 0.0;        // price value of 1 pip (0 = auto: 10 points on 3/5-digit, else 1 point)
//  SETUP (one time): MT5 -> Tools -> Options -> Expert Advisors ->
//  tick "Allow WebRequest for listed URL" and add:  https://api.telegram.org
//  Without that, WebRequest returns -1 and nothing sends. WebRequest never runs in the tester.

input group "-- CSV event log (for reports) --"
input bool     InpUseCsvLog      = true;       // write every event to MQL5/Files/<name>.csv
input string   InpCsvPrefix      = "SniperEA_Log";  // file becomes <prefix>_<symbol>_<tf>.csv
input bool     InpUseJsonLog    = false;       // ALSO write a machine-readable .jsonl file (one JSON object per line)
input bool     InpEchoLogToTerminal = true;    // echo each event to the Experts tab as a JSON object
//  One row per event, ALWAYS the same columns (see CSV_HEADER below):
//  ENTRY / TP1..TP5 / SL_MOVE / EXIT. Open it in Excel or read it with pandas as-is.

input group "-- Signal Quality Filter (optional) --"
input bool     InpEnableQFilter  = false;
input bool     InpQfTrend        = true;    // ADX >= adxMin
input double   InpAdxMin         = 25.0;
input bool     InpQfStruct       = true;    // |EMA21-EMA50| >= structMult*ATR
input double   InpStructMult     = 0.5;
input bool     InpQfEma50        = true;
input bool     InpQfVwap         = true;
input bool     InpQfBias         = false;
input double   InpBiasMin        = 70.0;
input bool     InpQfVolume       = false;
input bool     InpQfCooldown     = true;
input int      InpCooldownBars   = 5;

input group "-- Bias score inputs --"
input int      InpRsiPeriod      = 14;
input int      InpMacdFast       = 12;
input int      InpMacdSlow       = 26;
input int      InpMacdSignal     = 9;
input int      InpAdxPeriod      = 14;
input int      InpVolAvgPeriod   = 20;

//====================================================================
//  GLOBALS
//====================================================================
CTrade   trade;
int      hEma9, hEma21, hEma50, hAtr, hAdx, hRsi, hRsiM5, hMacd;

datetime g_lastBarTime = 0;
int      g_lastSignal  = 0;      // 1 long, -1 short, 0 flat
datetime g_lastSigTime = 0;

datetime g_dayStamp    = 0;
double   g_dayStartBal = 0;      // balance at the start of the current trading day
double   g_baseline    = 0;      // account baseline every loss limit is measured from
bool     g_dayLocked   = false;  // day cap / loss-count hit - no more trades today
bool     g_acctLocked  = false;  // overall loss guard hit - no more trades at all
bool     g_warnDaily   = false;  // daily warning already sent today
bool     g_warnTotal   = false;  // overall warning already sent
double   g_peakEquity  = 0;      // highest equity seen - the trailing-drawdown reference

// ---- scale-out position state ----
long     g_posId   = 0;          // identifier of the position we're managing
int      g_dir     = 0;
double   g_entry   = 0.0;
double   g_risk    = 0.0;        // price distance of the actual stop (what is really risked)
double   g_tpUnit  = 0.0;        // price distance used as 1R when laying out TP1..TP5
double   g_slFactor= 1.0;        // 1.0 = usual ATR stop, 0.5 = halved stop (outside the IST window)
double   g_origVol = 0.0;        // volume at entry (for equal 20% slices)
double   g_initSL  = 0.0;        // SL as placed at entry
double   g_curSL   = 0.0;        // SL after the last trail step
bool     g_fullTgt = false;      // TRUE = this trade runs to the full target, no partials
int      g_runLevel = 0;         // runner: rungs cleared ABOVE TP5 (0 = none yet / not running)
datetime g_entryBar = 0;         // bar the trade was opened on (excluded from bar-extreme folding)
datetime g_excBar   = 0;         // last completed bar already folded into MFE/MAE
double   g_mfe     = 0.0;        // best price distance IN FAVOUR since entry (price units)
double   g_mae     = 0.0;        // worst price distance AGAINST since entry (negative)
datetime g_lastSkipBar = 0;      // one SKIP row per closed bar, no more
int      g_skipDir = 0;          // direction of the cross that was refused
bool     g_virtActive = false;   // signals-only: a virtual trade is being tracked from price
double   g_virtSL     = 0.0;     // signals-only: current (virtual) stop, moves to BE/prev-TP
bool     g_tpHit[5];
double   g_tpPrice[5];

// ---- weekend state ----
int      g_friCloseSec = -1;     // cached Friday session close, seconds from server midnight
bool     g_weekendFlat = false;  // TRUE once we have flattened for this weekend

// ---- news blackout windows ----
struct NewsWin
{
   datetime evTime;        // the release itself
   datetime from, to;      // the no-entry window around it
   string   name, cur;
   string   fc, pv;        // forecast / previous, as text
   int      imp;
   bool     said;
};
NewsWin  g_news[];
string   g_newsSaid[];      // events already announced, so each is posted once
datetime g_newsRefreshed = 0;
bool     g_newsOk        = true;    // false once we learn the calendar is unavailable here
bool     g_newsWarned    = false;
string   g_newsActive    = "";      // event currently blocking, so it is announced once

// ---- dashboard ----
#define PANEL_PFX  "SNP_PANEL_"
#define PANEL_ROWS 13
uint     g_panelTick = 0;

// ---- IST session tracking (-1 = nothing printed yet) ----
int      g_sessNow = -1;

// ---- flip link ----
long     g_flipFrom = 0;         // trade_id this entry flipped out of (0 = not a flip)

// ---- per-trade record, for the end-of-day table ----
struct DayTrade
{
   string tIst;        // ENTRY time, IST, HH:MM
   string xIst;        // EXIT  time, IST, HH:MM
   int    dir;
   double entry, sl, exitPx, pips, r, net;
   string result;      // WIN / LOSS / BE
};
DayTrade g_dayLog[];
string   g_entryIst = "";   // entry time of the live trade, IST HH:MM (kept short for the
                            // end-of-day Telegram table, whose columns are width-aligned)
datetime g_entryTimeSrv=0; // the RAW entry instant on the broker clock. The
                            // formatted strings below are derived from it and can be
                            // rebuilt; a bad GMT offset once froze "05:45" into the
                            // state file with no way to correct it.
string   g_entryIstFull=""; // the same instant with its DATE, IST - what the dashboard shows
string   g_entrySrvFull=""; // and on the BROKER's clock, so the conversion can be checked

// ---- one row per finished day, for the weekly / monthly roll-ups ----
struct DaySum
{
   datetime day;
   int      trades, wins, losses;
   double   gp, gl, net, r, pips;
};
DaySum g_dayHist[];

// ---- end-of-day tally ----
int      g_dTrades=0, g_dWins=0, g_dLoss=0;
double   g_dGrossP=0, g_dGrossL=0, g_dSwap=0, g_dComm=0, g_dR=0, g_dBest=0, g_dWorst=0;

// ---- logging state ----
bool     g_logCsvOnly = false;   // set while the day summary writes its CSV row (its JSON is emitted separately)
long     g_tradeId  = 0;         // groups every row belonging to one trade
int      g_logSeq   = 0;
string   g_qfFlags  = "";        // quality-filter pass/fail captured at entry
string   g_entryTag = "";        // "FULLTGT" / "SCALEOUT" / "SINGLETP" / "SIGNAL"

// one fixed column set for EVERY event row
#define CSV_HEADER "seq,time_server,time_ist,event,symbol,tf,trade_id,direction,exit_mode,ist_session,flip_from,entry_price,init_sl,cur_sl,sl_distance,sl_factor,tp_unit,tp1,tp2,tp3,tp4,tp5,lots_initial,lots_event,lots_remaining,event_price,r_target,r_realized,profit,ema9,ema21,ema50,ema9_prev,ema21_prev,ema21_50_gap_atr,atr,adx,rsi,rsi_m5,macd_main,macd_signal,macd_hist,vwap,close,volume,vol_avg,bull_pct,bear_pct,spread_pts,qfilter_on,qf_flags,mfe_r,mae_r,balance,equity,note"

//--------------------------------------------------------------------
//  ONE print style for the whole EA:
//      [SNIPER][TAG    ] message
//  TAG is padded so the column lines up and you can scan the Experts
//  tab down the tag column. Tags used:
//      INIT  CONFIG  SIGNAL  SKIP  ENTRY  TP  SL  EXIT  GUARD  HALT
//      ERROR  TG  DATA
//--------------------------------------------------------------------
//--------------------------------------------------------------------
//  Emoji by Unicode code point.
//
//  NOT written as "\x...." escapes. MQL5's escape parser does not reliably
//  yield a UTF-16 code unit from a 4-digit form, and an emoji outside the BMP
//  needs a surrogate PAIR, which no single escape can express at all. Writing
//  the character directly into the source is worse again: MetaEditor can save
//  the file as ANSI and destroy it silently.
//
//  ShortToString() takes a UTF-16 code unit and is unambiguous.
//--------------------------------------------------------------------
string Emo(uint cp)
{
   if(cp < 0x10000) return ShortToString((ushort)cp);
   cp -= 0x10000;
   return ShortToString((ushort)(0xD800 + (cp >> 10)))
        + ShortToString((ushort)(0xDC00 + (cp & 0x3FF)));
}

void Say(const string tag,const string msg)
{
   Print(StringFormat("[SNIPER][%-6s] %s",tag,msg));
}

// prints the indicator state and the filter verdicts as two separate lines,
// always immediately after the [ENTRY] line so the three read together.
void SayEntryLogic();
void SayEntryFilters();

// snapshot of everything the entry decision was based on
struct SnapVals
{
   double ema9, ema21, ema50, ema9p, ema21p, atr, adx, rsi, rsi5;
   double macdM, macdS, vwap, close, vol, volAvg, bull, bear;
   long   spread;
};

//====================================================================
//  INIT
//====================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   hEma9  = iMA(_Symbol,_Period,InpEmaFast, 0,MODE_EMA,PRICE_CLOSE);
   hEma21 = iMA(_Symbol,_Period,InpEmaMid,  0,MODE_EMA,PRICE_CLOSE);
   hEma50 = iMA(_Symbol,_Period,InpEmaTrend,0,MODE_EMA,PRICE_CLOSE);
   hAtr   = iATR(_Symbol,_Period,InpAtrPeriod);
   hAdx   = iADX(_Symbol,_Period,InpAdxPeriod);
   hRsi   = iRSI(_Symbol,_Period,InpRsiPeriod,PRICE_CLOSE);
   hRsiM5 = iRSI(_Symbol,PERIOD_M5,InpRsiPeriod,PRICE_CLOSE);
   hMacd  = iMACD(_Symbol,_Period,InpMacdFast,InpMacdSlow,InpMacdSignal,PRICE_CLOSE);

   if(hEma9==INVALID_HANDLE||hEma21==INVALID_HANDLE||hEma50==INVALID_HANDLE||
      hAtr==INVALID_HANDLE ||hAdx==INVALID_HANDLE  ||hRsi==INVALID_HANDLE ||
      hRsiM5==INVALID_HANDLE||hMacd==INVALID_HANDLE)
   { Say("ERROR","indicator handle creation failed - EA not started"); return(INIT_FAILED); }

   g_baseline    = (InpBaselineBalance>0) ? InpBaselineBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   g_dayStamp    = TradingDayStart(TimeCurrent());
   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   ResetPosState();

   TesterFreshStart();     // backtest: start from nothing, not from the last run
   LoadState();            // restore the day tally and any open-trade state
   if(InpBaselineBalance>0) g_baseline=InpBaselineBalance;   // the input always wins
   AdoptOpenPosition();    // re-attach to a position that survived the restart

   // Write the state file once, right away. Without this its timestamp still
   // reads from the last event before the restart - so after a weekend the
   // dashboard would call a perfectly healthy EA stale until the first trade.
   SaveState();
   // no heartbeat in the tester - nothing is watching, and it would rewrite the
   // state file thousands of times over a simulated year for no reason
   if(InpHeartbeatMin>0 && !InTester()) EventSetTimer(InpHeartbeatMin*60);

   SayStartupBanner("startup");

   if(InTester())
   {
      Say("CONFIG",StringFormat("TESTER | json log %s | csv log %s | skip audit %s | fresh files %s",
          (InpUseJsonLog?"ON":"OFF - the report script needs this"),
          (InpUseCsvLog?"ON":"off"),
          (InpLogSkips?"ON":"off - refused signals will not be recorded"),
          (InpTesterFreshLog?"ON":"off - this run APPENDS to the last one")));
      Say("CONFIG","TESTER | MFE/MAE fold each closed bar's high/low, so they hold up on "
                   "'Open prices only' and '1 minute OHLC' as well as on every tick");
      if(InpServerGmtOffset==0)
         Say("CONFIG","TESTER | InpServerGmtOffset is 0 - set it to your broker's offset "
                      "or the IST sessions land in the wrong place");
   }

   if(InpTgNotifyStart)
      TelegramSend(Emo(0x1F916) + " " + TgB("EA online") + "\n"
                 + _Symbol + "  " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7) + "\n\n"
                 + TgPre(StringFormat("%-9s %.2f / %.2f\n%-9s %s\n%-9s %s",
                         "Lots d/e",(InpUseSessionLots?InpDayLot:InpFixedLot),
                                    (InpUseSessionLots?InpEveningLot:InpFixedLot),
                         "Mode",(InpSignalsOnly?"signals only":"live trading"),
                         "IST now",IstClock(TimeCurrent())))
                 + "\n" + TgB("Reading the close card") + "\n"
                 + TgPre("R      what the trade actually made, in multiples of the risk\n"
                         "Best   furthest it ran IN FAVOUR before it ended   (MFE)\n"
                         "Worst  furthest it ran AGAINST you before it ended (MAE)")
                 + "\nBoth are measured after entry, so they only appear on the closing "
                   "message - never on the signal itself.\n"
                 + TgM("Best far above R = the target closed too early. "
                       "Worst near 0 = the stop was wider than it needed to be."));
   return(INIT_SUCCEEDED);
}

//====================================================================
//  TESTER HOUSEKEEPING
//
//  Every run of a backtest writes to the same agent sandbox, so without this
//  run two appends to run one and the report reads a blend of both. Only ever
//  touches files inside the Tester - a live account's log is never deleted.
//====================================================================
bool InTester()
{
   return (MQLInfoInteger(MQL_TESTER)!=0 || MQLInfoInteger(MQL_OPTIMIZATION)!=0);
}

void TesterFreshStart()
{
   if(!InTester() || !InpTesterFreshLog) return;
   string files[3];
   files[0]=LogFileName(".csv");
   files[1]=LogFileName(".jsonl");
   files[2]=StateFileName();
   for(int i=0;i<3;i++)
      if(FileIsExist(files[i])) FileDelete(files[i]);
   Say("CONFIG","tester | previous run's log and state cleared (InpTesterFreshLog)");
}

//====================================================================
//  EXCURSION - how far the trade ran in favour, and against, before it ended
//
//  Sampled on every tick while a position is open. MFE says whether the
//  targets were ever reachable; MAE says how much of the stop was actually
//  needed. Together they answer "is my stop too wide and my ladder too
//  ambitious" - which nothing in the log could answer before.
//====================================================================
double ExcursionR(double priceDist)
{
   return (g_risk>0.0) ? priceDist/g_risk : 0.0;
}

void TrackExcursion()
{
   if(g_dir==0 || g_risk<=0.0 || g_entry<=0.0) return;
   if(!PositionOnSymbol() && !g_virtActive) return;

   // 1) the live price, every tick
   double px  = (g_dir==1) ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                           : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double fav = (g_dir==1) ? (px-g_entry) : (g_entry-px);
   if(fav>g_mfe) g_mfe=fav;
   if(fav<g_mae) g_mae=fav;

   // 2) and the high/low of every bar that has closed since entry.
   //
   //    This is what makes MFE/MAE trustworthy in the Strategy Tester. On
   //    "Open prices only" or "1 minute OHLC" the tester calls OnTick a
   //    handful of times per bar, so tick sampling alone would badly
   //    understate both figures. The bars themselves are real OHLC either
   //    way, so folding their extremes in gives the same magnitudes on every
   //    modelling mode - and it also catches a live spike that happened
   //    between two ticks.
   //
   //    The entry bar is skipped: its range includes movement from before
   //    the trade existed. Tick sampling already covers it from entry on.
   datetime b = iTime(_Symbol,_Period,1);
   if(b>0 && b!=g_excBar && b>g_entryBar)
   {
      g_excBar = b;
      double hi = iHigh(_Symbol,_Period,1);
      double lo = iLow (_Symbol,_Period,1);
      if(hi>0.0 && lo>0.0)
      {
         double fHi = (g_dir==1) ? (hi-g_entry) : (g_entry-hi);
         double fLo = (g_dir==1) ? (lo-g_entry) : (g_entry-lo);
         double best  = MathMax(fHi,fLo);
         double worst = MathMin(fHi,fLo);
         if(best >g_mfe) g_mfe=best;
         if(worst<g_mae) g_mae=worst;
      }
   }
}

//  The close card for a signals-only trade. Same shape as the live one in
//  AuditAndLogExit(), minus Net: there is no position, so there is no money.
//  Printing "Net 0.00" would be a fabricated figure rather than a missing one.
string TgVirtualClose(double exitPx)
{
   return TgPre(StringFormat("%-7s %s\n%-7s %s\n%-7s %+.1f\n%-7s %+.2fR\n%-7s %+.2fR\n%-7s %+.2fR",
          "Entry", DoubleToString(g_entry,_Digits),
          "Exit",  DoubleToString(exitPx,_Digits),
          "Pips",  PipsCaught(exitPx),
          "R",     RealizedR(exitPx),
          "Best",  ExcursionR(g_mfe),      // furthest in favour after entry
          "Worst", ExcursionR(g_mae)))     // furthest against
        + "\n" + TgM("Best/Worst = furthest in favour / against after entry, in R");
}

//====================================================================
//  SKIP AUDIT - the signals that were NOT taken
//
//  Without this the log only ever holds trades that got through, so every
//  filter is judged on survivors. One row per closed bar, and only when an
//  EMA cross actually happened - an idle EA writes nothing.
//====================================================================
int CrossDirection()
{
   double e9_1,e9_2,e21_1,e21_2;
   if(!Val(hEma9,1,e9_1)  || !Val(hEma9,2,e9_2))   return 0;
   if(!Val(hEma21,1,e21_1)|| !Val(hEma21,2,e21_2)) return 0;
   if((e9_2<=e21_2) && (e9_1> e21_1)) return  1;
   if((e9_2>=e21_2) && (e9_1< e21_1)) return -1;
   return 0;
}

void LogSkip(const string reason)
{
   if(!InpLogSkips) return;
   datetime bar = iTime(_Symbol,_Period,1);
   if(bar==g_lastSkipBar) return;          // already recorded this bar
   int dir = CrossDirection();
   if(dir==0) return;                      // no signal to refuse
   g_lastSkipBar = bar;
   g_skipDir     = dir;
   Say("SKIP",StringFormat("%s cross NOT taken | %s",(dir==1?"BUY":"SELL"),reason));
   LogEvent("SKIP",0.0,0.0,0.0,0.0,0.0,0.0,reason);
}

//====================================================================
//  HEARTBEAT - proof of life, independent of the tick stream
//
//  On a timer rather than OnTick on purpose: ticks stop when the market
//  is quiet or the feed dies, and a heartbeat that stops with them cannot
//  tell those apart from a terminal that has crashed. On the timer, a
//  stale state file means one thing only - this EA is not running.
//====================================================================
void OnTimer()
{
   if(!InpPersistState || InpHeartbeatMin<=0) return;
   SaveState();                       // best effort; it never blocks trading
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   PanelDestroy();

   // Wrap the day up only when the EA is actually going away - the terminal
   // closing, the EA removed, the chart closed.
   //
   // NOT on a recompile, a parameter change, a timeframe switch or a template
   // reload: the EA is back within seconds in those cases, and LogDaySummary
   // both emits a summary and calls ResetDayTally(). Doing that mid-day would
   // publish a partial day and, worse, hand back a fresh daily loss allowance
   // the moment anyone touched the inputs.
   //
   // SaveState() after it is what the old code was missing. RollDayIfNeeded()
   // saves after its own roll; this path did not, so the finished day's row
   // was pushed into g_dayHist in memory and then thrown away with the
   // process - leaving it out of the weekly and monthly roll-ups after a
   // shutdown. The DAY_SUMMARY event still reached the log either way.
   if(reason==REASON_CLOSE || reason==REASON_REMOVE || reason==REASON_CHARTCLOSE
      || InTester())        // a finished backtest must always close its last day
   {
      LogDaySummary(g_dayStamp);     // so the last day of a run is never lost
      SaveState();                   // ...and neither is its row in the history
   }

   IndicatorRelease(hEma9);  IndicatorRelease(hEma21); IndicatorRelease(hEma50);
   IndicatorRelease(hAtr);   IndicatorRelease(hAdx);   IndicatorRelease(hRsi);
   IndicatorRelease(hRsiM5); IndicatorRelease(hMacd);
}

//====================================================================
//  MAIN
//====================================================================
void OnTick()
{
   RollDayIfNeeded();
   CheckSessionChange();          // prints a banner when the IST session flips
   PanelUpdate();                 // on-chart status panel

   if(InpSignalsOnly)
   {
      MonitorVirtual();                     // track TP/SL from price, broadcast, place no orders
   }
   else
   {
      // position closed (stopped out or fully scaled) -> audit the exit, log it, clear tracking
      if(!PositionOnSymbol() && g_posId != 0)
      {
         AuditAndLogExit();
         ResetPosState();
         SaveState();          // record that we are flat
      }
      if(InpUseScaleOut) ManageScaleOut();  // partials / full-target ladder
      else               ManageSingleTP();  // single TP + BE/trail
      ManageRunner();                       // the ladder above TP5, when run-until-flip is on
   }
   TrackExcursion();                        // MFE / MAE while the trade is live

   // weekend guard runs on EVERY tick, before the closed-bar gate, so the exit is not
   // delayed until the next bar forms right as the market is shutting.
   if(WeekendCutoffReached())
   {
      DoWeekendClose();
      if(InpBlockFridayEntries){ LogSkip("weekend cutoff"); return; }
   }
   else g_weekendFlat = false;               // fresh week / before the cutoff: re-arm

   // news blackout is checked every tick too - flattening before a release
   // must not wait for the next bar to close.
   if(NewsBlocksTrading()){ LogSkip("news blackout"); return; }  // open trades still managed above

   if(InpTradeOnClose)
   {
      datetime bt = iTime(_Symbol,_Period,0);
      if(bt == g_lastBarTime) return;
      g_lastBarTime = bt;
   }

   // a runner must be able to end on an opposite cross even when the entry
   // window is shut, or it rides on until the window reopens with nothing but
   // the trailed stop under it. This closes only; it never opens.
   if(RunnerFlipExit()) return;

   if(GuardsBlockTrading()){ LogSkip("loss guard locked"); return; }
   if(!SessionAllowed()){ LogSkip("outside the entry window"); return; }
   {
      string eveWhy;
      if(EveningEntryBlocked(eveWhy)){ LogSkip(eveWhy); return; }
   }
   EvaluateSignal();
}

//====================================================================
//  SIGNAL EVALUATION - EMA9 / EMA21 cross
//====================================================================
void EvaluateSignal()
{
   double e9_1,e9_2,e21_1,e21_2,e50_1,atr_1;
   if(!Val(hEma9,1,e9_1)||!Val(hEma9,2,e9_2))   return;
   if(!Val(hEma21,1,e21_1)||!Val(hEma21,2,e21_2))return;
   if(!Val(hEma50,1,e50_1)) return;
   if(!Val(hAtr,1,atr_1))   return;
   if(atr_1 <= 0) return;

   double closePx = iClose(_Symbol,_Period,1);
   double vwap    = SessionVWAP();

   bool buyCond  = (e9_2 <= e21_2) && (e9_1 > e21_1);
   bool sellCond = (e9_2 >= e21_2) && (e9_1 < e21_1);
   if(!buyCond && !sellCond) return;

   double adx=0; Val(hAdx,1,adx);
   double volNow = (double)iVolume(_Symbol,_Period,1);
   double volAvg = VolumeSMA(InpVolAvgPeriod);

   bool qTrend  = (!InpQfTrend)   || (adx >= InpAdxMin);
   bool qStruct = (!InpQfStruct)  || (MathAbs(e21_1-e50_1) >= InpStructMult*atr_1);
   bool qVolume = (!InpQfVolume)  || (volNow > volAvg);
   bool qCool   = (!InpQfCooldown)|| (g_lastSigTime==0) ||
                  (BarsBetween(g_lastSigTime, iTime(_Symbol,_Period,1)) >= InpCooldownBars);
   bool qCommon = qTrend && qStruct && qVolume && qCool;

   double bullPct,bearPct; BiasScores(closePx,vwap,bullPct,bearPct);

   bool qEma50L = (!InpQfEma50)||closePx>e50_1;
   bool qEma50S = (!InpQfEma50)||closePx<e50_1;
   bool qVwapL  = (!InpQfVwap) ||closePx>vwap;
   bool qVwapS  = (!InpQfVwap) ||closePx<vwap;
   bool qBiasL  = (!InpQfBias) ||bullPct>=InpBiasMin;
   bool qBiasS  = (!InpQfBias) ||bearPct>=InpBiasMin;

   bool qLong  = qCommon && qEma50L && qVwapL && qBiasL;
   bool qShort = qCommon && qEma50S && qVwapS && qBiasS;

   bool qualityLong  = (!InpEnableQFilter)||qLong;
   bool qualityShort = (!InpEnableQFilter)||qShort;

   // The cross direction is known now, so freeze the reason set here rather
   // than after the decision - a refused signal has to record which filter
   // refused it, or the SKIP rows say nothing useful.
   int dir = buyCond ? 1 : -1;
   g_qfFlags = StringFormat("CROSS=%s;TREND=%d;STRUCT=%d;VOL=%d;COOL=%d;EMA50=%d;VWAP=%d;BIAS=%d",
                            (dir==1?"EMA9>EMA21":"EMA9<EMA21"),
                            (int)qTrend,(int)qStruct,(int)qVolume,(int)qCool,
                            (int)(dir==1?qEma50L:qEma50S),
                            (int)(dir==1?qVwapL :qVwapS ),
                            (int)(dir==1?qBiasL :qBiasS ));

   bool triggerBuy  = buyCond  && g_lastSignal<=0 && qualityLong;
   bool triggerSell = sellCond && g_lastSignal>=0 && qualityShort;
   if(!triggerBuy && !triggerSell)
   {
      bool sameWay = (buyCond && g_lastSignal>0) || (sellCond && g_lastSignal<0);
      LogSkip(sameWay ? "already positioned that way" : "quality filter");
      return;
   }

   if(InpMaxSpreadPts > 0)
   {
      long spr = SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(spr > InpMaxSpreadPts)
      { LogSkip(StringFormat("spread %d > max %d",(int)spr,InpMaxSpreadPts)); return; }
   }

   OpenTrade(dir, atr_1);
}

//====================================================================
//  ORDER PLACEMENT
//====================================================================
void OpenTrade(int dir, double atr)
{
   // --- FLIP: an opposite signal arrived before SL or target was reached ---
   g_flipFrom = 0;
   if(PositionOnSymbol())
   {
      long   oldId  = g_posId;
      int    oldDir = g_dir;
      double px     = (oldDir==1)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      // one clearly named row BEFORE the exit, so the log reads FLIP -> EXIT_FLIP -> ENTRY
      LogEvent("FLIP",px,0.0,0.0,0.0,RealizedR(px),0.0,
               StringFormat("opposite signal before SL/target | %s -> %s | closing trade %d",
                            (oldDir==1?"BUY":"SELL"),(dir==1?"BUY":"SELL"),oldId));
      Say("FLIP",StringFormat("%s -> %s | closing trade %d @ %s before SL/target",
          (oldDir==1?"BUY":"SELL"),(dir==1?"BUY":"SELL"),oldId,DoubleToString(px,_Digits)));

      ClosePositionTagged("FLIP exit","EXIT_FLIP");

      // audit NOW - the replacement position opens on this same tick, so the usual
      // "position gone" check in OnTick would never see this one close.
      AuditAndLogExit();
      ResetPosState();
      SaveState();
      g_flipFrom = oldId;
   }

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double entry=(dir==1)?ask:bid;

   // no partials at all when full-target mode is on - this applies to BOTH sessions
   bool fullTgt = InpUseScaleOut && InpUseFullTarget;

   // the IST session sets the stop width (entry gating is EveningEntryBlocked)
   //   12 AM - 4 PM IST -> usual ATR stop
   //   4 PM - 12 AM IST -> that stop x InpOutsideSlFactor (0.5 = half)
   bool dayTime    = InDaySessionIST(TimeCurrent());
   double slFactor = (!dayTime && InpUseHalfSlOutside) ? InpOutsideSlFactor : 1.0;
   if(slFactor<=0.0) slFactor=1.0;

   double fullR = atr*InpSlAtrMult;          // the usual ATR stop distance
   double risk  = fullR*slFactor;            // what is ACTUALLY risked on this trade
   double tpUnit= InpTpFromHalvedRisk ? risk : fullR;   // the distance one R step of TP uses
   double sl    =(dir==1)?entry-risk:entry+risk;

   // --- SIGNALS-ONLY: set up a virtual trade, broadcast, and DO NOT place an order ---
   if(InpSignalsOnly)
   {
      // An opposite signal ends the virtual trade that is still running. Without
      // this the old one is simply overwritten and never gets an EXIT row, which
      // leaves it open forever in the logs - and with InpBookAtTP5 off, the
      // flip IS the exit, so it has to be recorded. Runs before g_dir/g_entry are
      // reassigned, so RealizedR still measures the trade being closed.
      if(g_virtActive)
      {
         double fpx=(g_dir==1)?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                              :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         Say("FLIP",StringFormat("%s -> %s | virtual trade %d ended by the opposite signal @ %s",
             (g_dir==1?"BUY":"SELL"),(dir==1?"BUY":"SELL"),g_tradeId,DoubleToString(fpx,_Digits)));
         LogEvent("EXIT_FLIP",fpx,0.0,0.0,0.0,RealizedR(fpx),0.0,
                  "virtual trade ended by the opposite signal");
         if(InpTgNotifyClose)
            TelegramSend(Emo(0x1F501) + " " + TgB("FLIP - signal ended") + "\n"
                       + _Symbol + "  " + (g_dir==1?"BUY":"SELL") + "\n\n"
                       + TgVirtualClose(fpx));
         g_virtActive=false;
      }

      sl = NormalizeDouble(sl,_Digits);
      g_dir=dir; g_entry=NormalizeDouble(entry,_Digits); g_risk=risk;
      g_tpUnit=tpUnit; g_slFactor=slFactor;
      g_virtSL=sl; g_initSL=sl; g_curSL=sl; g_origVol=0.0; g_posId=0;
      g_fullTgt=fullTgt; g_tradeId=(long)TimeCurrent();
      g_entryTag = ModeTag(fullTgt,slFactor);
      StampEntryClock(TimeCurrent());
      g_entryBar = iTime(_Symbol,_Period,0);
      double Rs[5]={InpTP1_R,InpTP2_R,InpTP3_R,InpTP4_R,InpTP5_R};
      for(int i=0;i<5;i++){ g_tpHit[i]=false;
         g_tpPrice[i]=NormalizeDouble((dir==1)?g_entry+tpUnit*Rs[i]:g_entry-tpUnit*Rs[i],_Digits); }
      g_virtActive=true;
      g_lastSignal=dir; g_lastSigTime=iTime(_Symbol,_Period,1);
      Say("ENTRY",StringFormat("%-4s SIGNAL @ %s | SL %s (x%.2f) | mode %s | %s session | IST %s",
          dir==1?"BUY":"SELL", DoubleToString(g_entry,_Digits), DoubleToString(sl,_Digits),
          slFactor, g_entryTag, dayTime?"DAY":"EVENING",
          TimeToString(ServerToIST(TimeCurrent()),TIME_MINUTES)));
      SayEntryLogic();
      SayEntryFilters();
      LogEvent("ENTRY",g_entry,0.0,0.0,0.0,0.0,0.0,"signals-only virtual entry");
      SendEntrySignal(sl);
      return;
   }

   // scale-out manages TPs manually, so no broker TP; single-TP mode sets one.
   double tp=0.0;
   if(!InpUseScaleOut && InpTpRMultiple>0)
      tp=(dir==1)?entry+tpUnit*InpTpRMultiple:entry-tpUnit*InpTpRMultiple;

   double lots=CalcLots(risk,dayTime);  // session lot, fixed lot, or risk-% off the REAL stop
   if(lots<=0){ LogSkip("lot size calculated as 0"); return; }

   sl=NormalizeDouble(sl,_Digits);
   tp=NormalizeDouble(tp,_Digits);

   string modeTag = ModeTag(fullTgt,slFactor);
   string cmt     = "SNP " + (dir==1?"BUY ":"SELL ") + modeTag;     // stays under the 31-char limit

   bool ok=(dir==1)?trade.Buy(lots,_Symbol,0.0,sl,tp,cmt)
                   :trade.Sell(lots,_Symbol,0.0,sl,tp,cmt);
   if(!ok)
   {
      Say("ERROR",StringFormat("order rejected | retcode %d | %s | lots %.2f sl %s",
          trade.ResultRetcode(),trade.ResultRetcodeDescription(),lots,DoubleToString(sl,_Digits)));
      return;
   }

   g_lastSignal =dir;
   g_lastSigTime=iTime(_Symbol,_Period,1);

   if(PositionSelect(_Symbol))
   {
      g_posId  =PositionGetInteger(POSITION_IDENTIFIER);
      g_tradeId=g_posId;
      g_dir    =dir;
      g_entry  =PositionGetDouble(POSITION_PRICE_OPEN);
      g_risk   =risk;
      g_tpUnit =tpUnit;
      g_slFactor=slFactor;
      g_origVol=PositionGetDouble(POSITION_VOLUME);
      g_initSL =sl;
      g_curSL  =sl;
      g_fullTgt=fullTgt;
      g_entryTag=modeTag;
      StampEntryClock(TimeCurrent());
      g_entryBar=iTime(_Symbol,_Period,0);
      double Rmult[5]={InpTP1_R,InpTP2_R,InpTP3_R,InpTP4_R,InpTP5_R};
      for(int i=0;i<5;i++)
      {
         g_tpHit[i]=false;
         g_tpPrice[i]=(dir==1)?g_entry+tpUnit*Rmult[i]:g_entry-tpUnit*Rmult[i];
      }
      string lotSrc = InpUseSessionLots ? (dayTime?"day lot":"evening lot")
                    : (InpUseFixedLot ? "fixed lot"
                    : StringFormat("risk %.2f%%%s",
                        (InpUseSessionRisk ? (dayTime?InpDayRiskPct:InpEveningRiskPct) : InpRiskPercent),
                        (InpUseSessionRisk ? (dayTime?" day":" evening") : "")));
      Say("ENTRY",StringFormat("%-4s %.2f lots (%s) @ %s | SL %s (x%.2f) | mode %s | %s session | IST %s",
          dir==1?"BUY":"SELL", g_origVol, lotSrc,
          DoubleToString(g_entry,_Digits), DoubleToString(sl,_Digits), slFactor, modeTag,
          dayTime?"DAY":"EVENING",
          TimeToString(ServerToIST(TimeCurrent()),TIME_MINUTES)));
      SayEntryLogic();
      SayEntryFilters();
      SaveState();

      LogEvent("ENTRY",g_entry,g_origVol,g_origVol,0.0,0.0,0.0,
               StringFormat("%s session: stop x%.2f of usual; %s%s",
                            (dayTime?"DAY 12AM-4PM IST":"EVENING 4PM-12AM IST"), slFactor,
                            (fullTgt ? "no partials, full size to TP5, SL steps BE->TP1->TP2->TP3"
                                     : "partials at TP1-TP4"),
                            (g_flipFrom!=0 ? StringFormat("; flipped from trade %d",g_flipFrom) : "")));
      SendEntrySignal(sl);
   }
}

//====================================================================
//  TARGET MANAGER
//    * full-target mode (default, BOTH sessions) -> nothing booked, SL stepped one level
//      at a time, full size carried to TP5
//    * InpUseFullTarget = OFF -> the old behaviour: 20% booked at each TP
//====================================================================
void ManageScaleOut()
{
   if(!PositionOnSymbol()) return;
   if(PositionGetInteger(POSITION_IDENTIFIER) != g_posId) return;   // not our tracked trade

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   for(int i=0;i<5;i++)
   {
      if(g_tpHit[i]) continue;

      bool hit=(g_dir==1)?(bid>=g_tpPrice[i]):(ask<=g_tpPrice[i]);
      if(!hit) continue;
      g_tpHit[i]=true;

      double remaining=PositionGetDouble(POSITION_VOLUME);
      double evPrice  =(g_dir==1)?bid:ask;

      // --- shared bits for the Telegram exit alerts ---
      double tgR5[5]  = {InpTP1_R,InpTP2_R,InpTP3_R,InpTP4_R,InpTP5_R};
      string tgTf     = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
      string tgSide   = (g_dir==1) ? "BUY" : "SELL";
      string tgRtxt   = "+" + DoubleToString(tgR5[i],1) + "R";
      string tgHead   = _Symbol + "  " + tgTf;
      string tpTag    = "TP" + IntegerToString(i+1);

      //----------------------------------------------------------------
      //  FULL-TARGET MODE (default): never book a partial, only step the stop up.
      //  Runs in both the day and the evening session - only the stop WIDTH differs.
      //----------------------------------------------------------------
      if(g_fullTgt)
      {
         if(i<4)
         {
            string slLine = "SL unchanged";
            if(InpTrailBehindTP)
            {
               // one level at a time: TP1 -> breakeven, TP2 -> TP1, TP3 -> TP2, TP4 -> TP3
               double newSL = (i==0) ? g_entry : g_tpPrice[i-1];
               newSL=NormalizeDouble(newSL,_Digits);
               double curTP=PositionGetDouble(POSITION_TP);
               if(trade.PositionModify(_Symbol,newSL,curTP))
               {
                  g_curSL = newSL;
                  slLine  = (i==0)
                          ? "SL -> Breakeven " + DoubleToString(newSL,_Digits)
                          : "SL -> TP" + IntegerToString(i) + " " + DoubleToString(newSL,_Digits);
                  LogEvent("SL_MOVE",newSL,0.0,remaining,tgR5[i],0.0,0.0,
                           (i==0 ? "stop to breakeven" : "stop trailed to TP"+IntegerToString(i)));
                  SaveState();
               }
               else
                  Say("ERROR",StringFormat("%s | stop move rejected | retcode %d",tpTag,trade.ResultRetcode()));
            }

            Say("TP",StringFormat("%s reached @ %s | +%.1fR | nothing booked (full target) | %s",
                tpTag,DoubleToString(g_tpPrice[i],_Digits),tgR5[i],slLine));
            LogEvent(tpTag+"_REACHED",g_tpPrice[i],0.0,remaining,tgR5[i],tgR5[i],0.0,
                     "full target: no partial booked");
            SaveState();

            if(InpTgNotifyTP)
               TelegramSend(Emo(0x2705) + " " + TgB(tpTag + " reached  " + tgRtxt) + "\n"
                          + tgHead + "  " + tgSide + "\n\n"
                          + TgPre(StringFormat("%-6s %s\n%-6s %s\n%-6s %s",
                                  tpTag,DoubleToString(g_tpPrice[i],_Digits),
                                  "Booked","nothing - running to TP5",
                                  "Stop",slLine)));
         }
         else if(RunnerOn())
         {
            // RUNNER: TP5 is just one more rung. Step the stop to TP4 and keep going -
            // ManageRunner() takes over the trail from here, one rung at a time.
            string slLine = "SL unchanged";
            if(InpTrailBehindTP)
            {
               double newSL=NormalizeDouble(g_tpPrice[3],_Digits);
               double curTP=PositionGetDouble(POSITION_TP);
               if(trade.PositionModify(_Symbol,newSL,curTP))
               {
                  g_curSL = newSL;
                  slLine  = "SL -> TP4 " + DoubleToString(newSL,_Digits);
                  LogEvent("SL_MOVE",newSL,0.0,remaining,tgR5[4],0.0,0.0,"stop trailed to TP4");
               }
               else
                  Say("ERROR",StringFormat("TP5 | stop move rejected | retcode %d",trade.ResultRetcode()));
            }
            g_runLevel = 0;                       // armed: rungs above TP5 start at 1

            Say("TP",StringFormat("TP5 reached @ %s | +%.1fR | RUNNING ON (run-until-flip) | %s",
                DoubleToString(g_tpPrice[4],_Digits),tgR5[4],slLine));
            LogEvent("TP5_REACHED",g_tpPrice[4],0.0,remaining,tgR5[4],tgR5[4],0.0,
                     "runner: not closed at TP5, running until the opposite signal");
            SaveState();

            if(InpTgNotifyTP)
               TelegramSend(Emo(0x1F680) + " " + TgB("TP5 reached - RUNNING ON  " + tgRtxt) + "\n"
                          + tgHead + "  " + tgSide + "\n\n"
                          + TgPre(StringFormat("%-6s %s\n%-6s %s\n%-6s %s",
                                  "TP5",DoubleToString(g_tpPrice[4],_Digits),
                                  "Booked","nothing - running until the flip",
                                  "Stop",slLine)));
            continue;
         }
         else
         {
            // final target -> close the whole position, comment tagged with the level
            if(CloseAllTagged("TP5 exit"))
            {
               Say("EXIT",StringFormat("TP5 hit @ %s | +%.1fR | full target reached | closed in full",
                   DoubleToString(g_tpPrice[i],_Digits),tgR5[i]));
               LogEvent("TP5_EXIT",evPrice,remaining,0.0,tgR5[i],tgR5[i],0.0,
                        "full target reached, closed in full");
               if(InpTgNotifyTP)
                  TelegramSend(Emo(0x1F3C1) + " " + TgB("TP5 HIT - FULL TARGET  " + tgRtxt) + "\n"
                             + tgHead + "  " + tgSide + "\n\n"
                             + TgPre(StringFormat("%-6s %s\n%-6s %s",
                                     "TP5",DoubleToString(g_tpPrice[i],_Digits),
                                     "Closed","full position")));
            }
            else g_tpHit[i]=false;      // close failed -> let the next tick retry
            return;
         }
         continue;
      }

      //----------------------------------------------------------------
      //  ORIGINAL SCALE-OUT MODE (unchanged behaviour)
      //----------------------------------------------------------------
      if(i<4)
      {
         // close a slice equal to InpPartialPct% of the ORIGINAL volume
         double slice=NormalizeLots(g_origVol*InpPartialPct/100.0);
         if(slice<minLot) slice=minLot;

         if(remaining-slice < minLot)
         {
            // can't leave a valid remainder -> book the WHOLE position at this TP
            // (this is what happens on 0.01 lots: full exit at TP1 / 1R)
            if(CloseAllTagged(tpTag + " exit full"))
            {
               Say("EXIT",StringFormat("%s hit @ %s | +%.1fR | remainder below min lot | closed in full",
                   tpTag,DoubleToString(g_tpPrice[i],_Digits),tgR5[i]));
               LogEvent(tpTag+"_EXIT",evPrice,remaining,0.0,tgR5[i],tgR5[i],0.0,
                        "remainder below min lot, closed in full");
               if(InpTgNotifyTP)
                  TelegramSend(Emo(0x2705) + " " + TgB(tpTag + " hit - closed in full  " + tgRtxt) + "\n"
                             + tgHead + "  " + tgSide + "\n\n"
                             + TgPre(StringFormat("%-6s %s\n%-6s %s",
                                     tpTag,DoubleToString(g_tpPrice[i],_Digits),
                                     "Reason","remainder below min lot")));
            }
            else g_tpHit[i]=false;
            return;
         }

         if(!ClosePartialTagged(slice, tpTag + " exit"))
         { g_tpHit[i]=false; return; }

         LogEvent(tpTag+"_PARTIAL",evPrice,slice,remaining-slice,tgR5[i],tgR5[i],0.0,
                  StringFormat("booked %.0f%% of original size",InpPartialPct));

         // trail the stop behind the target just hit (BE after TP1, then to previous TP)
         string tgSlLine = "SL unchanged";
         if(InpTrailBehindTP)
         {
            double newSL=(i==0)?g_entry:g_tpPrice[i-1];
            newSL=NormalizeDouble(newSL,_Digits);
            double curTP=PositionGetDouble(POSITION_TP);
            if(trade.PositionModify(_Symbol,newSL,curTP))
            {
               g_curSL = newSL;
               tgSlLine = (i==0)
                  ? "SL -> Breakeven " + DoubleToString(g_entry,_Digits)
                  : "SL -> TP" + IntegerToString(i) + " " + DoubleToString(g_tpPrice[i-1],_Digits);
               LogEvent("SL_MOVE",newSL,0.0,remaining-slice,tgR5[i],0.0,0.0,
                        (i==0?"stop to breakeven":"stop trailed to TP"+IntegerToString(i)));
            }
         }
         Say("TP",StringFormat("%s hit @ %s | +%.1fR | booked %.2f lots | %s",
             tpTag,DoubleToString(g_tpPrice[i],_Digits),tgR5[i],slice,tgSlLine));
         if(InpTgNotifyTP)
            TelegramSend(Emo(0x2705) + " " + TgB(tpTag + " booked  " + tgRtxt) + "\n"
                       + tgHead + "  " + tgSide + "\n\n"
                       + TgPre(StringFormat("%-6s %s\n%-6s %.2f lots\n%-6s %s",
                               tpTag,DoubleToString(g_tpPrice[i],_Digits),
                               "Booked",slice,"Stop",tgSlLine)));
      }
      else if(RunnerOn())
      {
         // RUNNER, scale-out mode: the four partials are already booked; let the
         // remainder run instead of closing it, stop stepped to TP4.
         string slLine = "SL unchanged";
         if(InpTrailBehindTP)
         {
            double newSL=NormalizeDouble(g_tpPrice[3],_Digits);
            double curTP=PositionGetDouble(POSITION_TP);
            if(trade.PositionModify(_Symbol,newSL,curTP))
            {
               g_curSL = newSL;
               slLine  = "SL -> TP4 " + DoubleToString(newSL,_Digits);
               LogEvent("SL_MOVE",newSL,0.0,remaining,tgR5[4],0.0,0.0,"stop trailed to TP4");
            }
         }
         g_runLevel = 0;

         Say("TP",StringFormat("TP5 reached @ %s | +%.1fR | remainder RUNNING ON | %s",
             DoubleToString(g_tpPrice[4],_Digits),tgR5[4],slLine));
         LogEvent("TP5_REACHED",g_tpPrice[4],0.0,remaining,tgR5[4],tgR5[4],0.0,
                  "runner: remainder left open, running until the opposite signal");
         SaveState();

         if(InpTgNotifyTP)
            TelegramSend(Emo(0x1F680) + " " + TgB("TP5 reached - remainder RUNNING  " + tgRtxt) + "\n"
                       + tgHead + "  " + tgSide + "\n\n"
                       + TgPre("TP5    " + DoubleToString(g_tpPrice[4],_Digits) + "\n"
                             + "Stop   " + slLine));
         continue;
      }
      else
      {
         // final target -> close whatever remains
         if(CloseAllTagged("TP5 exit"))
         {
            Say("EXIT",StringFormat("TP5 hit @ %s | +%.1fR | remainder closed",
                DoubleToString(g_tpPrice[i],_Digits),tgR5[i]));
            LogEvent("TP5_EXIT",evPrice,remaining,0.0,tgR5[i],tgR5[i],0.0,"final target, closed remainder");
            if(InpTgNotifyTP)
               TelegramSend(Emo(0x1F3C1) + " " + TgB("TP5 hit - fully closed  " + tgRtxt) + "\n"
                          + tgHead + "  " + tgSide + "\n\n"
                          + TgPre("TP5    " + DoubleToString(g_tpPrice[i],_Digits)));
         }
         else g_tpHit[i]=false;
         return;
      }
   }
}

//====================================================================
//  RUNNER ON?  - one place decides it
//
//  The input is phrased as "book at TP5" because that is the decision you are
//  actually making. Everything downstream asks this instead of negating the
//  input itself, so the sense cannot drift between call sites.
//====================================================================
bool RunnerOn(){ return !InpBookAtTP5; }

//====================================================================
//  RUNNER - the ladder above TP5
//
//  Same rule as TP1..TP5, carried on indefinitely: when the price clears
//  rung k the stop moves to rung k-1, where rung 0 IS TP5. Nothing is ever
//  booked and the stop never retreats, so the trade can only end on the
//  trailed stop, the opposite EMA cross, or one of the usual guards.
//====================================================================
double RunnerRungPrice(int k)              // k >= 1, counted above TP5
{
   double rr = InpTP5_R + InpRunnerStepR*k;
   return NormalizeDouble((g_dir==1) ? g_entry + g_tpUnit*rr
                                     : g_entry - g_tpUnit*rr, _Digits);
}

void ManageRunner()
{
   if(!RunnerOn() || InpRunnerStepR<=0.0) return;
   if(!PositionOnSymbol()) return;
   if(PositionGetInteger(POSITION_IDENTIFIER) != g_posId) return;
   if(!g_tpHit[4]) return;                 // the runner only starts once TP5 is behind us
   if(g_tpUnit<=0.0 || g_dir==0) return;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   // a gap can clear several rungs in one tick, so step through them; the
   // counter is bounded so a bad tpUnit can never spin here.
   for(int guard=0; guard<50; guard++)
   {
      int    k  = g_runLevel + 1;
      double px = RunnerRungPrice(k);
      bool   hit=(g_dir==1)?(bid>=px):(ask<=px);
      if(!hit) break;

      g_runLevel = k;
      double rr    = InpTP5_R + InpRunnerStepR*k;
      double newSL = (k==1) ? NormalizeDouble(g_tpPrice[4],_Digits) : RunnerRungPrice(k-1);
      string tag   = "TP" + IntegerToString((int)MathRound(rr));

      double remaining=PositionGetDouble(POSITION_VOLUME);
      LogEvent(tag+"_REACHED",px,0.0,remaining,rr,rr,0.0,
               StringFormat("runner rung %d above TP5",k));

      // only ever tighten - never hand back ground already locked in
      bool better = (g_dir==1) ? (newSL > g_curSL) : (newSL < g_curSL || g_curSL==0.0);
      if(InpTrailBehindTP && better)
      {
         double curTP=PositionGetDouble(POSITION_TP);
         if(trade.PositionModify(_Symbol,newSL,curTP))
         {
            g_curSL = newSL;
            string behind = (k==1) ? "TP5" : ("+" + DoubleToString(rr-InpRunnerStepR,1) + "R");
            Say("TP",StringFormat("runner +%.1fR @ %s | SL -> %s %s",
                rr,DoubleToString(px,_Digits),behind,DoubleToString(newSL,_Digits)));
            LogEvent("SL_MOVE",newSL,0.0,remaining,rr,0.0,0.0,
                     "runner: stop trailed to "+behind);
            if(InpTgNotifyTP)
               TelegramSend(Emo(0x1F680) + " " + TgB(StringFormat("Runner +%.1fR",rr)) + "\n"
                          + _Symbol + "  " + (g_dir==1?"BUY":"SELL") + "\n\n"
                          + TgPre("Price  " + DoubleToString(px,_Digits) + "\n"
                                + "Stop   " + behind + " " + DoubleToString(newSL,_Digits)));
         }
         else
            Say("ERROR",StringFormat("runner | stop move rejected | retcode %d",trade.ResultRetcode()));
      }
      SaveState();
   }
}

//====================================================================
//  RUNNER FLIP EXIT - an opposite cross ends the trade even when the
//  entry window is shut. It only ever CLOSES: opening the other side
//  stays gated by SessionAllowed(), exactly as before.
//====================================================================
bool RunnerFlipExit()
{
   if(!RunnerOn() || !InpFlipExitAnyTime) return false;
   if(InpSignalsOnly) return false;
   if(!PositionOnSymbol() || g_dir==0) return false;
   if(PositionGetInteger(POSITION_IDENTIFIER) != g_posId) return false;
   if(SessionAllowed()) return false;      // inside the window EvaluateSignal flips properly

   double e9_1,e9_2,e21_1,e21_2;
   if(!Val(hEma9,1,e9_1) ||!Val(hEma9,2,e9_2))  return false;
   if(!Val(hEma21,1,e21_1)||!Val(hEma21,2,e21_2))return false;

   bool buyCross  = (e9_2<=e21_2) && (e9_1> e21_1);
   bool sellCross = (e9_2>=e21_2) && (e9_1< e21_1);
   if(!((g_dir==1 && sellCross) || (g_dir==-1 && buyCross))) return false;

   double px=(g_dir==1)?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                       :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   Say("FLIP",StringFormat("opposite cross outside the entry window | closing %s trade %d @ %s"
                           " | no new entry until the window reopens",
       (g_dir==1?"BUY":"SELL"),g_tradeId,DoubleToString(px,_Digits)));

   ClosePositionTagged("FLIP exit (out of session)","EXIT_FLIP");
   AuditAndLogExit();
   ResetPosState();
   SaveState();
   return true;
}

//====================================================================
//  SINGLE-TP MANAGER (used only when scale-out is OFF)
//====================================================================
void ManageSingleTP()
{
   if(!PositionOnSymbol()) return;
   if(!InpMoveToBE_Single)  return;

   long   type=PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL=PositionGetDouble(POSITION_SL);
   double curTP=PositionGetDouble(POSITION_TP);
   double atr; if(!Val(hAtr,1,atr)) return;
   double risk=atr*InpSlAtrMult;
   double px=(type==POSITION_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                      :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double newSL=curSL;
   if(type==POSITION_TYPE_BUY  && px>=open+risk && curSL<open) newSL=open;
   if(type==POSITION_TYPE_SELL && px<=open-risk && (curSL>open||curSL==0)) newSL=open;
   newSL=NormalizeDouble(newSL,_Digits);
   if(newSL!=curSL && newSL!=0 && trade.PositionModify(_Symbol,newSL,curTP))
   {
      g_curSL=newSL;
      LogEvent("SL_MOVE",newSL,0.0,PositionGetDouble(POSITION_VOLUME),1.0,0.0,0.0,"single-TP mode: stop to breakeven");
   }
}

//====================================================================
//  CLOSING HELPERS - every close carries a comment naming the level
//  (CTrade has no comment argument, so the request is built by hand)
//====================================================================
ENUM_ORDER_TYPE_FILLING PickFilling()
{
   long f=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((f & SYMBOL_FILLING_IOC)!=0) return ORDER_FILLING_IOC;
   if((f & SYMBOL_FILLING_FOK)!=0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

bool CloseWithComment(double volume,const string comment)
{
   if(!PositionSelect(_Symbol)) return false;

   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);

   long type = PositionGetInteger(POSITION_TYPE);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.position     = PositionGetInteger(POSITION_TICKET);
   req.volume       = NormalizeLots(volume);
   req.magic        = InpMagic;
   req.deviation    = 20;
   req.type         = (type==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   req.price        = (type==POSITION_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                               :SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   req.type_filling = PickFilling();
   req.comment      = comment;                 // <- "TP2 exit", "TP5 exit", "FLIP exit", ...

   if(!OrderSend(req,res) || (res.retcode!=TRADE_RETCODE_DONE && res.retcode!=TRADE_RETCODE_PLACED))
   {
      Say("ERROR",StringFormat("close rejected | %s | retcode %d | %s | falling back to library close",
          comment,res.retcode,res.comment));
      // fall back to the library call so a trade is never left hanging because of a comment
      return (volume>=PositionGetDouble(POSITION_VOLUME))
             ? trade.PositionClose(_Symbol)
             : trade.PositionClosePartial(_Symbol,volume);
   }
   return true;
}

bool ClosePartialTagged(double volume,const string comment){ return CloseWithComment(volume,comment); }

bool CloseAllTagged(const string comment)
{
   if(!PositionSelect(_Symbol)) return false;
   return CloseWithComment(PositionGetDouble(POSITION_VOLUME),comment);
}

void ClosePositionTagged(const string comment,const string evt)
{
   if(!PositionOnSymbol()) return;
   double vol=PositionGetDouble(POSITION_VOLUME);
   double px =(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
              ?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(CloseAllTagged(comment))
   {
      LogEvent(evt,px,vol,0.0,0.0,RealizedR(px),0.0,comment);
      g_lastSignal=0;
   }
}

//====================================================================
//  EXIT AUDIT - reads the closing deals so the log says WHY it ended
//====================================================================
void AuditAndLogExit()
{
   if(g_posId==0) return;

   double gross=0.0, swap=0.0, comm=0.0, lastPrice=0.0, lots=0.0;
   string reasonTxt="UNKNOWN", cmt="";

   if(HistorySelectByPosition(g_posId))
   {
      int total=HistoryDealsTotal();
      for(int d=0; d<total; d++)
      {
         ulong tk=HistoryDealGetTicket(d);
         if(tk==0) continue;
         long entryType=HistoryDealGetInteger(tk,DEAL_ENTRY);
         gross += HistoryDealGetDouble(tk,DEAL_PROFIT);
         swap  += HistoryDealGetDouble(tk,DEAL_SWAP);
         comm  += HistoryDealGetDouble(tk,DEAL_COMMISSION);
         if(entryType==DEAL_ENTRY_OUT || entryType==DEAL_ENTRY_OUT_BY)
         {
            lastPrice = HistoryDealGetDouble(tk,DEAL_PRICE);
            lots     += HistoryDealGetDouble(tk,DEAL_VOLUME);
            cmt       = HistoryDealGetString(tk,DEAL_COMMENT);
            long rsn  = HistoryDealGetInteger(tk,DEAL_REASON);
            if(rsn==DEAL_REASON_SL)      reasonTxt="SL";
            else if(rsn==DEAL_REASON_TP) reasonTxt="TP";
            else if(rsn==DEAL_REASON_SO) reasonTxt="STOPOUT";
            else                         reasonTxt="EA";
         }
      }
   }

   string evt="EXIT_OTHER";
   string note=cmt;
   if(reasonTxt=="SL")
   {
      bool atBE = (MathAbs(g_curSL-g_entry) < _Point*2);
      if(atBE)        { evt="EXIT_BE"; note="stopped at breakeven"; }
      else if(MathAbs(g_curSL-g_initSL) < _Point*2)
                      { evt="EXIT_SL";
                        note=StringFormat("stopped at the initial SL (x%.2f of usual)",g_slFactor); }
      else            { evt="EXIT_TRAIL_SL"; note="stopped at a trailed level"; }
   }
   else if(reasonTxt=="TP") { evt="EXIT_TP"; note="broker TP hit"; }
   else if(StringFind(cmt,"WEEKEND")>=0){ evt="EXIT_WEEKEND"; note="flattened before the Friday close"; }
   else if(StringFind(cmt,"NEWS")>=0)   { evt="EXIT_NEWS";    note="flattened before a news release"; }
   else if(StringFind(cmt,"TP")>=0) { evt="EXIT_TP"; note=cmt; }

   double net = gross + swap + comm;
   double rr  = RealizedR(lastPrice);

   // --- feed the end-of-day tally ---
   g_dTrades++;
   if(net>=0){ g_dWins++;  g_dGrossP += net; }
   else      { g_dLoss++;  g_dGrossL += -net; }
   g_dSwap += swap; g_dComm += comm; g_dR += rr;
   if(net>g_dBest)  g_dBest =net;
   if(net<g_dWorst) g_dWorst=net;

   // keep the trade for the end-of-day table
   int n=ArraySize(g_dayLog);
   if(n<500)
   {
      ArrayResize(g_dayLog,n+1);
      g_dayLog[n].tIst   = (g_entryIst==""?TimeToString(ServerToIST(TimeCurrent()),TIME_MINUTES):g_entryIst);
      g_dayLog[n].xIst   = TimeToString(ServerToIST(TimeCurrent()),TIME_MINUTES);
      g_dayLog[n].dir    = g_dir;
      g_dayLog[n].entry  = g_entry;
      g_dayLog[n].sl     = g_initSL;
      g_dayLog[n].exitPx = lastPrice;
      g_dayLog[n].pips   = PipsCaught(lastPrice);
      g_dayLog[n].r      = rr;
      g_dayLog[n].net    = net;
      g_dayLog[n].result = (net>0.005 ? "WIN" : (net<-0.005 ? "LOSS" : "BE"));
   }

   SaveState();
   Say("EXIT",StringFormat("%-13s | %.2f lots @ %s | %+.2fR | net %+.2f (gross %+.2f, comm %+.2f, swap %+.2f) | %s",
       evt,lots,DoubleToString(lastPrice,_Digits),rr,net,gross,comm,swap,note));
   LogEvent(evt,lastPrice,lots,0.0,0.0,rr,net,note);

   if(InpTgNotifyClose)
   {
      string icon = (net>0) ? Emo(0x1F4B0) : ((net<0) ? Emo(0x274C) : Emo(0x2796));
      TelegramSend(icon + " " + TgB("CLOSED  " + evt) + "\n"
                 + _Symbol + "  " + (g_dir==1?"BUY":"SELL") + "\n\n"
                 + TgPre(StringFormat("%-7s %s\n%-7s %s\n%-7s %+.1f\n%-7s %+.2fR\n%-7s %+.2f\n"
                                      "%-7s %+.2fR\n%-7s %+.2fR",
                         "Entry",DoubleToString(g_entry,_Digits),
                         "Exit", DoubleToString(lastPrice,_Digits),
                         "Pips", PipsCaught(lastPrice),
                         "R",    rr,
                         "Net",  net,
                         "Best", ExcursionR(g_mfe),      // how far it ran in favour
                         "Worst",ExcursionR(g_mae))));   // how much of the stop was used
   }
}

double PipSize()
{
   if(InpPipSize>0) return InpPipSize;
   return ((_Digits==3||_Digits==5) ? 10*_Point : _Point);
}

double PipsCaught(double exitPx)
{
   double ps=PipSize();
   if(ps<=0 || g_entry<=0 || exitPx<=0) return 0.0;
   return ((exitPx-g_entry)/ps)*(double)g_dir;
}

double RealizedR(double px)
{
   if(g_risk<=0 || g_entry<=0 || px<=0) return 0.0;
   return ((px-g_entry)/g_risk)*(double)g_dir;
}

//====================================================================
//  SIZING
//====================================================================
double CalcLots(double riskPriceDist,bool dayTime)
{
   if(InpUseSessionLots) return NormalizeLots(dayTime ? InpDayLot : InpEveningLot);
   if(InpUseFixedLot)    return NormalizeLots(InpFixedLot);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double pct=InpRiskPercent;
   if(InpUseSessionRisk) pct = dayTime ? InpDayRiskPct : InpEveningRiskPct;
   if(pct<=0.0) return 0;
   double riskMoney=bal*pct/100.0;
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0||tickVal<=0) return 0;
   double lossPerLot=(riskPriceDist/tickSize)*tickVal;
   if(lossPerLot<=0) return 0;
   return NormalizeLots(riskMoney/lossPerLot);
}

double NormalizeLots(double lots)
{
   double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   lots=MathFloor(lots/step)*step;
   if(lots<minL) lots=minL;
   if(lots>maxL) lots=maxL;
   return NormalizeDouble(lots,2);
}

//====================================================================
//  DAILY-LOSS GUARD
//====================================================================
void RollDayIfNeeded()
{
   datetime today=TradingDayStart(TimeCurrent());
   if(today!=g_dayStamp)
   {
      datetime ended = g_dayStamp;
      LogDaySummary(ended);                      // wrap up the day that just ended

      // a finished day may also close a week and/or a month
      if(ended>0)
      {
         // the week roll-up only READS its days - the month still needs them
         if(WeekIndex(today) != WeekIndex(ended))
            EmitPeriodSummary("WEEK",WeekIndex(ended));

         // the month is the last consumer, so its days are dropped here
         if(MonthIndex(today) != MonthIndex(ended))
         {
            EmitPeriodSummary("MONTH",MonthIndex(ended));
            DropPeriodFromHistory("MONTH",MonthIndex(ended));
         }
      }

      g_dayStamp=today;
      g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
      g_dayLocked=false;
      g_warnDaily=false;
      SaveState();
      SayStartupBanner("new trading day");       // settings in force for the day ahead
   }
}

//====================================================================
//  END-OF-DAY CONSOLIDATED RESULT
//====================================================================
void LogDaySummary(datetime dayEnded)
{
   if(g_dTrades<=0){ ResetDayTally(); return; }   // nothing traded - stay quiet

   double net     = g_dGrossP - g_dGrossL;
   double winPct  = (double)g_dWins/(double)g_dTrades*100.0;
   double profFac = (g_dGrossL>0) ? g_dGrossP/g_dGrossL : 0.0;
   double balNow  = AccountInfoDouble(ACCOUNT_BALANCE);
   string dstr    = TimeToString(dayEnded,TIME_DATE);

   // readable line
   Say("DAILY",StringFormat("%s | trades %d (W %d / L %d, %.0f%%) | gross +%.2f / -%.2f | net %+.2f | "
                            "comm %+.2f swap %+.2f | PF %.2f | netR %+.2fR | best %+.2f worst %+.2f | bal %.2f -> %.2f",
       dstr, g_dTrades, g_dWins, g_dLoss, winPct,
       g_dGrossP, g_dGrossL, net, g_dComm, g_dSwap, profFac, g_dR,
       g_dBest, g_dWorst, g_dayStartBal, balNow));

   // same figures as a JSON object, in the same style as every other event
   string j="{";
   j += Js("event","DAY_SUMMARY")                      + ",";
   j += Js("date",dstr)                                + ",";
   j += Js("sym",_Symbol)                              + ",";
   j += "\"trades\":{" + Ji("total",g_dTrades) + "," + Ji("wins",g_dWins) + ","
                       + Ji("losses",g_dLoss) + "," + Jn("win_pct",winPct,1) + "},";
   j += "\"pnl\":{"    + Jn("gross_profit",g_dGrossP,2) + "," + Jn("gross_loss",g_dGrossL,2) + ","
                       + Jn("net_profit",net,2) + "," + Jn("commission",g_dComm,2) + ","
                       + Jn("swap",g_dSwap,2) + "," + Jn("profit_factor",profFac,2) + ","
                       + Jn("net_r",g_dR,2) + "," + Jn("best",g_dBest,2) + ","
                       + Jn("worst",g_dWorst,2) + "},";
   j += "\"balance\":{"+ Jn("open",g_dayStartBal,2) + "," + Jn("close",balNow,2) + ","
                       + Jn("equity",AccountInfoDouble(ACCOUNT_EQUITY),2) + "}";
   j += "}";

   if(InpEchoLogToTerminal) Say("EVENT",j);
   if(InpUseJsonLog)        WriteTextRow(LogFileName(".jsonl"),"",j);
   if(InpUseCsvLog)
   {
      g_logCsvOnly=true;
      LogEvent("DAY_SUMMARY",0.0,0.0,0.0,0.0,g_dR,net,
               StringFormat("%s trades=%d W=%d L=%d gross_profit=%.2f gross_loss=%.2f net=%.2f PF=%.2f",
                            dstr,g_dTrades,g_dWins,g_dLoss,g_dGrossP,g_dGrossL,net,profFac));
      g_logCsvOnly=false;
   }

   double dayPips=0;
   for(int i=0;i<ArraySize(g_dayLog);i++) dayPips += g_dayLog[i].pips;
   PushDayHistory(dayEnded,dayPips);

   if(InpTgNotifyEOD) TelegramDaySummary(dstr,net,winPct,profFac,balNow);

   ResetDayTally();
}

//--------------------------------------------------------------------
//  WEEKLY / MONTHLY ROLL-UP - the day table, one row per day
//--------------------------------------------------------------------
// 1970-01-01 was a Thursday, so +3 days makes each week start on Monday
int WeekIndex(datetime t){ return (int)(((long)t + 3*86400) / 604800); }
int MonthIndex(datetime t){ MqlDateTime d; TimeToStruct(t,d); return d.year*12 + d.mon; }

void PushDayHistory(datetime day,double pips)
{
   int n=ArraySize(g_dayHist);
   if(n>400){ ArrayResize(g_dayHist,0); n=0; }
   ArrayResize(g_dayHist,n+1);
   g_dayHist[n].day    = day;
   g_dayHist[n].trades = g_dTrades;
   g_dayHist[n].wins   = g_dWins;
   g_dayHist[n].losses = g_dLoss;
   g_dayHist[n].gp     = g_dGrossP;
   g_dayHist[n].gl     = g_dGrossL;
   g_dayHist[n].net    = g_dGrossP - g_dGrossL;
   g_dayHist[n].r      = g_dR;
   g_dayHist[n].pips   = pips;
}

// kind = "WEEK" or "MONTH"; idx = the week/month index of the period that just ended
void EmitPeriodSummary(const string kind,int idx)
{
   int    days=0, trades=0, wins=0, losses=0, greenDays=0;
   double gp=0, gl=0, r=0, pips=0, best=0, worst=0;
   string rows="";

   for(int i=0;i<ArraySize(g_dayHist);i++)
   {
      int mine = (kind=="WEEK") ? WeekIndex(g_dayHist[i].day) : MonthIndex(g_dayHist[i].day);
      if(mine!=idx) continue;

      days++; trades+=g_dayHist[i].trades; wins+=g_dayHist[i].wins; losses+=g_dayHist[i].losses;
      gp+=g_dayHist[i].gp; gl+=g_dayHist[i].gl; r+=g_dayHist[i].r; pips+=g_dayHist[i].pips;
      if(g_dayHist[i].net>0) greenDays++;
      if(g_dayHist[i].net>best)  best =g_dayHist[i].net;
      if(g_dayHist[i].net<worst) worst=g_dayHist[i].net;

      rows += Pad(TimeToString(g_dayHist[i].day,TIME_DATE),11)
            + PadL(IntegerToString(g_dayHist[i].trades),4)
            + PadL(StringFormat("%d/%d",g_dayHist[i].wins,g_dayHist[i].losses),7)
            + PadL(StringFormat("%+.1f",g_dayHist[i].pips),9)
            + PadL(StringFormat("%+.1f",g_dayHist[i].r),6)
            + PadL(StringFormat("%+.2f",g_dayHist[i].net),10) + "\n";
   }
   if(days==0) return;

   double net     = gp-gl;
   double winPct  = (trades>0) ? (double)wins/(double)trades*100.0 : 0.0;
   double profFac = (gl>0) ? gp/gl : 0.0;
   string label   = (kind=="WEEK") ? "WEEK" : "MONTH";

   Say("PERIOD",StringFormat("%s closed | %d days | trades %d (W %d / L %d, %.0f%%) | green days %d/%d | "
                             "gross +%.2f / -%.2f | net %+.2f | PF %.2f | netR %+.2fR | pips %+.1f",
       label, days, trades, wins, losses, winPct, greenDays, days,
       gp, gl, net, profFac, r, pips));

   // same JSON style as every other event
   string j="{";
   j += Js("event",label+"_SUMMARY")                   + ",";
   j += Js("sym",_Symbol)                              + ",";
   j += Ji("days",days)                                + ",";
   j += Ji("green_days",greenDays)                     + ",";
   j += "\"trades\":{" + Ji("total",trades) + "," + Ji("wins",wins) + ","
                       + Ji("losses",losses) + "," + Jn("win_pct",winPct,1) + "},";
   j += "\"pnl\":{"    + Jn("gross_profit",gp,2) + "," + Jn("gross_loss",gl,2) + ","
                       + Jn("net_profit",net,2) + "," + Jn("profit_factor",profFac,2) + ","
                       + Jn("net_r",r,2) + "," + Jn("pips",pips,1) + ","
                       + Jn("best_day",best,2) + "," + Jn("worst_day",worst,2) + "}";
   j += "}";
   if(InpEchoLogToTerminal) Say("EVENT",j);
   if(InpUseJsonLog)        WriteTextRow(LogFileName(".jsonl"),"",j);
   if(InpUseCsvLog)
   {
      g_logCsvOnly=true;
      LogEvent(label+"_SUMMARY",0.0,0.0,0.0,0.0,r,net,
               StringFormat("days=%d trades=%d W=%d L=%d gross_profit=%.2f gross_loss=%.2f net=%.2f PF=%.2f pips=%.1f",
                            days,trades,wins,losses,gp,gl,net,profFac,pips));
      g_logCsvOnly=false;
   }

   if(InpTgNotifyPeriod)
   {
      string hdr = Pad("Date",11) + PadL("Trd",4) + PadL("W/L",7)
                 + PadL("Pips",9) + PadL("R",6) + PadL("Net",10) + "\n";
      string tot = Pad("TOTAL",11) + PadL(IntegerToString(trades),4)
                 + PadL(StringFormat("%d/%d",wins,losses),7)
                 + PadL(StringFormat("%+.1f",pips),9)
                 + PadL(StringFormat("%+.1f",r),6)
                 + PadL(StringFormat("%+.2f",net),10);

      string msg = Emo(0x1F5D3) + " " + TgB(label + " SUMMARY") + "\n"
                 + _Symbol + "  " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7)
                 + "   " + TgM("dates IST") + "\n\n"
                 + TgPre(hdr + rows + tot) + "\n"
                 + TgB("Totals") + "\n"
                 + TgPre(StringFormat("%-13s %d\n%-13s %d of %d\n%-13s %d  (W %d / L %d)\n%-13s %.0f%%\n"
                                      "%-13s +%.2f\n%-13s -%.2f\n%-13s %+.2f\n%-13s %.2f\n%-13s %+.2fR\n%-13s %+.2f / %+.2f",
                         "Days traded", days,
                         "Green days",  greenDays, days,
                         "Trades",      trades, wins, losses,
                         "Win rate",    winPct,
                         "Gross profit",gp,
                         "Gross loss",  gl,
                         "NET",         net,
                         "Profit factor",profFac,
                         "Net R",       r,
                         "Best/worst day", best, worst));
      TelegramSend(msg);
   }
}

void DropPeriodFromHistory(const string kind,int idx)
{
   DaySum keep[];
   for(int i=0;i<ArraySize(g_dayHist);i++)
   {
      int mine = (kind=="WEEK") ? WeekIndex(g_dayHist[i].day) : MonthIndex(g_dayHist[i].day);
      if(mine==idx) continue;
      int n=ArraySize(keep); ArrayResize(keep,n+1); keep[n]=g_dayHist[i];
   }
   ArrayResize(g_dayHist,0);
   for(int i=0;i<ArraySize(keep);i++)
   { int n=ArraySize(g_dayHist); ArrayResize(g_dayHist,n+1); g_dayHist[n]=keep[i]; }
}

//--------------------------------------------------------------------
//  End-of-day Telegram post: one row per trade, then the totals
//--------------------------------------------------------------------
void TelegramDaySummary(const string dstr,double net,double winPct,double profFac,double balNow)
{
   int dg = _Digits;
   int n  = ArraySize(g_dayLog);

   string msg = Emo(0x1F4CA) + " " + TgB("DAY SUMMARY  " + dstr) + "\n"
              + _Symbol + "  " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7)
              + "   " + TgM("times IST") + "\n\n";

   if(InpTgDayTable && n>0)
   {
      // widths sized off the symbol's own price length so the columns stay aligned
      int pw = StringLen(DoubleToString(g_dayLog[0].entry,dg));
      if(pw<5) pw=5;

      string t = Pad("#",3) + Pad("In",6) + Pad("Out",6) + Pad("S",2)
               + Pad("Entry",pw+1) + Pad("SL",pw+1) + Pad("Exit",pw+1)
               + PadL("Pips",7) + PadL("R",6) + PadL("Net",8) + "\n";

      double sumPips=0;
      for(int i=0;i<n;i++)
      {
         sumPips += g_dayLog[i].pips;
         t += Pad(IntegerToString(i+1),3)
            + Pad(Hm12(g_dayLog[i].tIst),6)
            + Pad(Hm12(g_dayLog[i].xIst),6)
            + Pad((g_dayLog[i].dir==1?"B":"S"),2)
            + Pad(DoubleToString(g_dayLog[i].entry,dg),pw+1)
            + Pad(DoubleToString(g_dayLog[i].sl,dg),pw+1)
            + Pad(DoubleToString(g_dayLog[i].exitPx,dg),pw+1)
            + PadL(StringFormat("%+.1f",g_dayLog[i].pips),7)
            + PadL(StringFormat("%+.1f",g_dayLog[i].r),6)
            + PadL(StringFormat("%+.2f",g_dayLog[i].net),8)
            + "\n";
      }
      t += Pad("",3) + Pad("",6) + Pad("",6) + Pad("",2)
         + Pad("",pw+1) + Pad("",pw+1) + Pad("TOTAL",pw+1)
         + PadL(StringFormat("%+.1f",sumPips),7)
         + PadL(StringFormat("%+.1f",g_dR),6)
         + PadL(StringFormat("%+.2f",net),8);

      msg += TgPre(t) + "\n";
   }

   msg += TgB("Totals") + "\n";
   msg += TgPre(StringFormat(
            "%-13s %d  (W %d / L %d)\n%-13s %.0f%%\n%-13s +%.2f\n%-13s -%.2f\n"
            "%-13s %+.2f\n%-13s %.2f\n%-13s %+.2fR\n%-13s %+.2f / %+.2f\n%-13s %.2f -> %.2f",
            "Trades",   g_dTrades, g_dWins, g_dLoss,
            "Win rate", winPct,
            "Gross profit", g_dGrossP,
            "Gross loss",   g_dGrossL,
            "NET",          net,
            "Profit factor",profFac,
            "Net R",        g_dR,
            "Best/worst",   g_dBest, g_dWorst,
            "Balance",      g_dayStartBal, balNow));

   if(g_dComm!=0 || g_dSwap!=0)
      msg += "\n" + TgM(StringFormat("costs: commission %+.2f, swap %+.2f",g_dComm,g_dSwap));

   TelegramSend(msg);
}

void ResetDayTally()
{
   ArrayResize(g_dayLog,0);
   g_dTrades=0; g_dWins=0; g_dLoss=0;
   g_dGrossP=0; g_dGrossL=0; g_dSwap=0; g_dComm=0; g_dR=0; g_dBest=0; g_dWorst=0;
}

//--------------------------------------------------------------------
//  Limits are measured against the BASELINE, not today's balance.
//  Each cap can be a %, a cash figure, or both - the tighter one wins.
//--------------------------------------------------------------------
string DDModeText()
{
   if(InpDrawdownMode==1) return "trailing from peak equity";
   if(InpDrawdownMode==0) return "static from baseline";
   return "static + trailing, whichever is worse";
}

double DailyCap()
{
   double capPct   = (InpMaxDailyLossPct>0)   ? g_baseline*InpMaxDailyLossPct/100.0 : DBL_MAX;
   double capMoney = (InpMaxDailyLossMoney>0) ? InpMaxDailyLossMoney                : DBL_MAX;
   return MathMin(capPct,capMoney);
}

double TotalCap()
{
   double capPct   = (InpMaxTotalLossPct>0)   ? g_baseline*InpMaxTotalLossPct/100.0 : DBL_MAX;
   double capMoney = (InpMaxTotalLossMoney>0) ? InpMaxTotalLossMoney                : DBL_MAX;
   return MathMin(capPct,capMoney);
}

void HaltAndFlatten(const string evt,const string cmt,const string sayMsg,double lossAmt)
{
   Say("HALT",sayMsg);
   LogEvent(evt,0.0,0.0,0.0,0.0,0.0,-lossAmt,sayMsg);
   if(InpCloseOnDailyCap && PositionOnSymbol())
   {
      ClosePositionTagged(cmt,"EXIT_GUARD");
      ResetPosState();
   }
}

//====================================================================
//  GUARDS - overall loss, daily loss, losing-trade count
//  Returns TRUE when no new entry may be taken.
//====================================================================
bool GuardsBlockTrading()
{
   if(!InpPropMode) return false;          // funding guards are opt-in
   if(g_acctLocked) return true;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>g_peakEquity) g_peakEquity=eq;         // trailing-drawdown reference

   // 0 = from the static baseline, 1 = from peak equity, 2 = whichever is worse
   double lossStatic = g_baseline   - eq;
   double lossTrail  = g_peakEquity - eq;
   double totalLoss;
   if(InpDrawdownMode==1)      totalLoss = lossTrail;
   else if(InpDrawdownMode==0) totalLoss = lossStatic;
   else                        totalLoss = MathMax(lossStatic,lossTrail);

   double dayLoss   = g_dayStartBal - eq;       // since this trading day opened

   //---------------- 1. OVERALL loss - the hard one ----------------
   double tCap = TotalCap();
   if(tCap < DBL_MAX)
   {
      // stop EARLY, at a fraction of the real limit, so the limit itself is never breached
      double stopAt = tCap * (InpTotalLossStopPct>0 ? InpTotalLossStopPct/100.0 : 1.0);
      double warnAt = tCap * (InpTotalWarnPct>0     ? InpTotalWarnPct/100.0     : 1.0);

      if(totalLoss >= stopAt)
      {
         g_acctLocked=true; g_dayLocked=true;
         HaltAndFlatten("HALT_TOTALLOSS","MAXLOSS exit",
            StringFormat("overall loss guard [%s] | -%.2f of max %.2f (stop at %.0f%% = %.2f) | TRADING STOPPED",
                         DDModeText(),totalLoss,tCap,InpTotalLossStopPct,stopAt), totalLoss);
         if(InpTgNotifyHalt)
            TelegramSend(Emo(0x1F6D1) + " " + TgB("MAX LOSS GUARD - TRADING STOPPED") + "\n"
                       + _Symbol + "\n\n"
                       + TgPre(StringFormat("%-11s %.2f\n%-11s %.2f\n%-11s %.2f\n%-11s %.2f\n%-11s %.2f\n%-11s %.2f",
                               "Baseline", g_baseline,
                               "Peak eq",  g_peakEquity,
                               "Equity",   eq,
                               "Loss",     totalLoss,
                               "Stop at",  stopAt,
                               "Real max", tCap))
                       + "\nNo further trades. Restart the EA once the account is reviewed.");
         return true;
      }

      if(!g_warnTotal && totalLoss >= warnAt)
      {
         g_warnTotal=true;
         Say("HALT",StringFormat("overall loss WARNING | -%.2f is %.0f%% of the max %.2f",
             totalLoss, (tCap>0?totalLoss/tCap*100.0:0), tCap));
         if(InpTgNotifyHalt)
            TelegramSend(Emo(0x26A0) + Emo(0xFE0F) + " " + TgB("MAX LOSS WARNING") + "\n"
                       + _Symbol + "\n\n"
                       + TgPre(StringFormat("%-11s %.2f\n%-11s %.2f\n%-11s %.0f%%\n%-11s %.2f",
                               "Loss",      totalLoss,
                               "Max",       tCap,
                               "Used",      (tCap>0?totalLoss/tCap*100.0:0),
                               "Stops at",  stopAt))
                       + "\nTrading continues - the EA halts itself before the limit.");
      }
   }

   if(g_dayLocked) return true;

   //---------------- 2. DAILY loss ----------------
   double dCap = DailyCap();
   if(dCap < DBL_MAX)
   {
      if(dayLoss >= dCap)
      {
         g_dayLocked=true;
         HaltAndFlatten("HALT_DAILYCAP","DAYCAP exit",
            StringFormat("daily loss cap | -%.2f >= %.2f | halted for the day",dayLoss,dCap), dayLoss);
         if(InpTgNotifyHalt)
            TelegramSend(Emo(0x1F6D1) + " " + TgB("DAILY LOSS CAP") + "\n"
                       + _Symbol + "\n\n"
                       + TgPre(StringFormat("%-11s %.2f\n%-11s %.2f\n%-11s %d\n%-11s %.2f",
                               "Day loss", dayLoss,
                               "Day cap",  dCap,
                               "Trades",   g_dTrades,
                               "Equity",   eq))
                       + "\nNo more trades today. Resets at the configured day reset time.");
         return true;
      }

      if(!g_warnDaily && InpDailyWarnPct>0 && dayLoss >= dCap*InpDailyWarnPct/100.0)
      {
         g_warnDaily=true;
         Say("HALT",StringFormat("daily loss WARNING | -%.2f is %.0f%% of the cap %.2f",
             dayLoss, dayLoss/dCap*100.0, dCap));
         if(InpTgNotifyHalt)
            TelegramSend(Emo(0x26A0) + Emo(0xFE0F) + " " + TgB("DAILY LOSS WARNING") + "\n"
                       + _Symbol + "\n\n"
                       + TgPre(StringFormat("%-11s %.2f\n%-11s %.2f\n%-11s %.0f%%\n%-11s %.2f",
                               "Day loss", dayLoss,
                               "Day cap",  dCap,
                               "Used",     dayLoss/dCap*100.0,
                               "Left",     dCap-dayLoss)));
      }
   }

   //---------------- 3. LOSING-TRADE COUNT ----------------
   if(InpMaxLossesPerDay>0 && g_dLoss >= InpMaxLossesPerDay)
   {
      g_dayLocked=true;
      HaltAndFlatten("HALT_LOSSCOUNT","LOSSCOUNT exit",
         StringFormat("loss count | %d losing trades today (max %d) | halted for the day",
                      g_dLoss,InpMaxLossesPerDay), dayLoss);
      if(InpTgNotifyHalt)
         TelegramSend(Emo(0x1F6D1) + " " + TgB("MAX LOSSES PER DAY") + "\n"
                    + _Symbol + "\n\n"
                    + TgPre(StringFormat("%-11s %d of %d\n%-11s %d\n%-11s %.2f",
                            "Losses",  g_dLoss, InpMaxLossesPerDay,
                            "Trades",  g_dTrades,
                            "Day P/L", -dayLoss))
                    + "\nNo more trades today.");
      return true;
   }

   return false;
}

//====================================================================
//  STATE PERSISTENCE - survive an MT5 restart mid-trade
//    Saved after every event. Holds the open trade, the day tally and
//    the day's trade rows, so a restart resumes instead of forgetting.
//====================================================================
string StateFileName(){ return LogFileName("_state.txt"); }

void SaveState()
{
   if(!InpPersistState) return;

   int h=FileOpen(StateFileName(),FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;                     // best effort - never block trading

   FileWriteString(h,"ver=2\r\n");
   FileWriteString(h,StringFormat("day=%d\r\n",(int)g_dayStamp));
   FileWriteString(h,StringFormat("dayStartBal=%.2f\r\n",g_dayStartBal));
   FileWriteString(h,StringFormat("baseline=%.2f\r\n",g_baseline));
   FileWriteString(h,StringFormat("peakEquity=%.2f\r\n",g_peakEquity));
   FileWriteString(h,StringFormat("dayLocked=%d\r\n",(int)g_dayLocked));
   FileWriteString(h,StringFormat("acctLocked=%d\r\n",(int)g_acctLocked));
   FileWriteString(h,StringFormat("warnDaily=%d\r\n",(int)g_warnDaily));
   FileWriteString(h,StringFormat("warnTotal=%d\r\n",(int)g_warnTotal));
   FileWriteString(h,StringFormat("lastSignal=%d\r\n",g_lastSignal));
   FileWriteString(h,StringFormat("dTrades=%d\r\n",g_dTrades));
   FileWriteString(h,StringFormat("dWins=%d\r\n",g_dWins));
   FileWriteString(h,StringFormat("dLoss=%d\r\n",g_dLoss));
   FileWriteString(h,StringFormat("dGrossP=%.2f\r\n",g_dGrossP));
   FileWriteString(h,StringFormat("dGrossL=%.2f\r\n",g_dGrossL));
   FileWriteString(h,StringFormat("dSwap=%.2f\r\n",g_dSwap));
   FileWriteString(h,StringFormat("dComm=%.2f\r\n",g_dComm));
   FileWriteString(h,StringFormat("dR=%.4f\r\n",g_dR));
   FileWriteString(h,StringFormat("dBest=%.2f\r\n",g_dBest));
   FileWriteString(h,StringFormat("dWorst=%.2f\r\n",g_dWorst));

   // the open trade
   FileWriteString(h,StringFormat("posId=%d\r\n",g_posId));
   FileWriteString(h,StringFormat("tradeId=%d\r\n",g_tradeId));
   FileWriteString(h,StringFormat("dir=%d\r\n",g_dir));
   FileWriteString(h,StringFormat("entry=%.8f\r\n",g_entry));
   FileWriteString(h,StringFormat("risk=%.8f\r\n",g_risk));
   FileWriteString(h,StringFormat("tpUnit=%.8f\r\n",g_tpUnit));
   FileWriteString(h,StringFormat("slFactor=%.4f\r\n",g_slFactor));
   FileWriteString(h,StringFormat("origVol=%.2f\r\n",g_origVol));
   FileWriteString(h,StringFormat("initSL=%.8f\r\n",g_initSL));
   FileWriteString(h,StringFormat("curSL=%.8f\r\n",g_curSL));
   FileWriteString(h,StringFormat("fullTgt=%d\r\n",(int)g_fullTgt));
   FileWriteString(h,StringFormat("runLevel=%d\r\n",g_runLevel));
   FileWriteString(h,StringFormat("mfe=%.8f\r\n",g_mfe));
   FileWriteString(h,StringFormat("mae=%.8f\r\n",g_mae));
   FileWriteString(h,StringFormat("entryBar=%d\r\n",(int)g_entryBar));
   FileWriteString(h,StringFormat("entryTag=%s\r\n",g_entryTag));
   FileWriteString(h,StringFormat("entryTimeSrv=%d\r\n",(int)g_entryTimeSrv));
   FileWriteString(h,StringFormat("entryIst=%s\r\n",g_entryIst));
   FileWriteString(h,StringFormat("entryIstFull=%s\r\n",g_entryIstFull));
   FileWriteString(h,StringFormat("entrySrvFull=%s\r\n",g_entrySrvFull));
   FileWriteString(h,StringFormat("gmtOffset=%.1f\r\n",ServerGmtOffsetHours()));
   FileWriteString(h,StringFormat("flipFrom=%d\r\n",g_flipFrom));
   FileWriteString(h,StringFormat("qfFlags=%s\r\n",g_qfFlags));
   string hits="", tps="";
   for(int i=0;i<5;i++)
   {
      hits += (i?",":"") + IntegerToString((int)g_tpHit[i]);
      tps  += (i?",":"") + DoubleToString(g_tpPrice[i],8);
   }
   FileWriteString(h,"tpHit="+hits+"\r\n");
   FileWriteString(h,"tpPrice="+tps+"\r\n");

   // finished days, for the weekly / monthly roll-ups
   for(int i=0;i<ArraySize(g_dayHist);i++)
      FileWriteString(h,StringFormat("D|%d|%d|%d|%d|%.2f|%.2f|%.2f|%.4f|%.4f\r\n",
         (int)g_dayHist[i].day,g_dayHist[i].trades,g_dayHist[i].wins,g_dayHist[i].losses,
         g_dayHist[i].gp,g_dayHist[i].gl,g_dayHist[i].net,g_dayHist[i].r,g_dayHist[i].pips));

   // the day's closed trades, for the end-of-day table
   for(int i=0;i<ArraySize(g_dayLog);i++)
      FileWriteString(h,StringFormat("T|%s|%s|%d|%.8f|%.8f|%.8f|%.4f|%.4f|%.2f|%s\r\n",
         g_dayLog[i].tIst,g_dayLog[i].xIst,g_dayLog[i].dir,
         g_dayLog[i].entry,g_dayLog[i].sl,g_dayLog[i].exitPx,
         g_dayLog[i].pips,g_dayLog[i].r,g_dayLog[i].net,g_dayLog[i].result));

   FileClose(h);
}

void StateApply(const string key,const string val)
{
   if(key=="dayStartBal")      g_dayStartBal=StringToDouble(val);
   else if(key=="baseline")    g_baseline   =StringToDouble(val);
   else if(key=="peakEquity")  g_peakEquity =StringToDouble(val);
   else if(key=="dayLocked")   g_dayLocked  =(StringToInteger(val)!=0);
   else if(key=="acctLocked")  g_acctLocked =(StringToInteger(val)!=0);
   else if(key=="warnDaily")   g_warnDaily  =(StringToInteger(val)!=0);
   else if(key=="warnTotal")   g_warnTotal  =(StringToInteger(val)!=0);
   else if(key=="lastSignal")  g_lastSignal =(int)StringToInteger(val);
   else if(key=="dTrades")     g_dTrades    =(int)StringToInteger(val);
   else if(key=="dWins")       g_dWins      =(int)StringToInteger(val);
   else if(key=="dLoss")       g_dLoss      =(int)StringToInteger(val);
   else if(key=="dGrossP")     g_dGrossP    =StringToDouble(val);
   else if(key=="dGrossL")     g_dGrossL    =StringToDouble(val);
   else if(key=="dSwap")       g_dSwap      =StringToDouble(val);
   else if(key=="dComm")       g_dComm      =StringToDouble(val);
   else if(key=="dR")          g_dR         =StringToDouble(val);
   else if(key=="dBest")       g_dBest      =StringToDouble(val);
   else if(key=="dWorst")      g_dWorst     =StringToDouble(val);
   else if(key=="posId")       g_posId      =(long)StringToInteger(val);
   else if(key=="tradeId")     g_tradeId    =(long)StringToInteger(val);
   else if(key=="dir")         g_dir        =(int)StringToInteger(val);
   else if(key=="entry")       g_entry      =StringToDouble(val);
   else if(key=="risk")        g_risk       =StringToDouble(val);
   else if(key=="tpUnit")      g_tpUnit     =StringToDouble(val);
   else if(key=="runLevel")    g_runLevel   =(int)StringToInteger(val);
   else if(key=="mfe")         g_mfe        =StringToDouble(val);
   else if(key=="mae")         g_mae        =StringToDouble(val);
   else if(key=="entryBar")    g_entryBar   =(datetime)StringToInteger(val);
   else if(key=="slFactor")    g_slFactor   =StringToDouble(val);
   else if(key=="origVol")     g_origVol    =StringToDouble(val);
   else if(key=="initSL")      g_initSL     =StringToDouble(val);
   else if(key=="curSL")       g_curSL      =StringToDouble(val);
   else if(key=="fullTgt")     g_fullTgt    =(StringToInteger(val)!=0);
   else if(key=="entryTag")    g_entryTag   =val;
   else if(key=="entryIst")    g_entryIst   =val;
   else if(key=="entryTimeSrv")g_entryTimeSrv=(datetime)StringToInteger(val);
   else if(key=="entryIstFull")g_entryIstFull=val;
   else if(key=="entrySrvFull")g_entrySrvFull=val;
   else if(key=="flipFrom")    g_flipFrom   =(long)StringToInteger(val);
   else if(key=="qfFlags")     g_qfFlags    =val;
   else if(key=="tpHit")
   {
      string a[]; if(StringSplit(val,',',a)==5)
         for(int i=0;i<5;i++) g_tpHit[i]=(StringToInteger(a[i])!=0);
   }
   else if(key=="tpPrice")
   {
      string a[]; if(StringSplit(val,',',a)==5)
         for(int i=0;i<5;i++) g_tpPrice[i]=StringToDouble(a[i]);
   }
}

void StateAddDayRow(const string line)
{
   string f[];
   if(StringSplit(line,'|',f)<10) return;
   int n=ArraySize(g_dayHist);
   ArrayResize(g_dayHist,n+1);
   g_dayHist[n].day    = (datetime)StringToInteger(f[1]);
   g_dayHist[n].trades = (int)StringToInteger(f[2]);
   g_dayHist[n].wins   = (int)StringToInteger(f[3]);
   g_dayHist[n].losses = (int)StringToInteger(f[4]);
   g_dayHist[n].gp     = StringToDouble(f[5]);
   g_dayHist[n].gl     = StringToDouble(f[6]);
   g_dayHist[n].net    = StringToDouble(f[7]);
   g_dayHist[n].r      = StringToDouble(f[8]);
   g_dayHist[n].pips   = StringToDouble(f[9]);
}

void StateAddTradeRow(const string line)
{
   string f[];
   if(StringSplit(line,'|',f)<11) return;
   int n=ArraySize(g_dayLog);
   ArrayResize(g_dayLog,n+1);
   g_dayLog[n].tIst   = f[1];
   g_dayLog[n].xIst   = f[2];
   g_dayLog[n].dir    = (int)StringToInteger(f[3]);
   g_dayLog[n].entry  = StringToDouble(f[4]);
   g_dayLog[n].sl     = StringToDouble(f[5]);
   g_dayLog[n].exitPx = StringToDouble(f[6]);
   g_dayLog[n].pips   = StringToDouble(f[7]);
   g_dayLog[n].r      = StringToDouble(f[8]);
   g_dayLog[n].net    = StringToDouble(f[9]);
   g_dayLog[n].result = f[10];
}

void LoadState()
{
   if(!InpPersistState) return;
   string fn=StateFileName();
   if(!FileIsExist(fn)) return;

   int h=FileOpen(fn,FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;

   datetime savedDay=0;
   string   pending[];
   int      np=0;
   ArrayResize(pending,0);

   // first pass: read everything, we decide what to keep afterwards
   string lines[];
   ArrayResize(lines,0);
   while(!FileIsEnding(h))
   {
      string ln=FileReadString(h);
      StringTrimRight(ln);
      if(ln=="") continue;
      int n=ArraySize(lines); ArrayResize(lines,n+1); lines[n]=ln;
   }
   FileClose(h);

   // the day stamp decides whether the tally is still ours
   for(int i=0;i<ArraySize(lines);i++)
   {
      if(StringSubstr(lines[i],0,4)=="day=")
      { savedDay=(datetime)StringToInteger(StringSubstr(lines[i],4)); break; }
   }
   bool sameDay = (savedDay==TradingDayStart(TimeCurrent()));

   for(int i=0;i<ArraySize(lines);i++)
   {
      string ln=lines[i];
      if(StringSubstr(ln,0,2)=="T|")
      {
         if(sameDay) StateAddTradeRow(ln);
         continue;
      }
      if(StringSubstr(ln,0,2)=="D|")      // finished days are kept whatever day it is now
      {
         StateAddDayRow(ln);
         continue;
      }
      int eq=StringFind(ln,"=");
      if(eq<1) continue;
      string k=StringSubstr(ln,0,eq);
      string v=StringSubstr(ln,eq+1);

      // day-scoped values are dropped when the saved state is from an earlier day
      bool dayScoped = (k=="dayStartBal"||k=="dayLocked"||k=="warnDaily"||
                        k=="dTrades"||k=="dWins"||k=="dLoss"||k=="dGrossP"||k=="dGrossL"||
                        k=="dSwap"||k=="dComm"||k=="dR"||k=="dBest"||k=="dWorst");
      if(dayScoped && !sameDay) continue;
      if(k=="day" || k=="ver")  continue;
      StateApply(k,v);
   }

   Say("STATE",StringFormat("loaded | saved day %s | %s | tally %s",
       TimeToString(savedDay,TIME_DATE),
       (sameDay?"same trading day - tally and trade rows restored":"new trading day - tally reset"),
       StringFormat("%d trades",g_dTrades)));
}

//--------------------------------------------------------------------
//  Re-attach to a position that is already open at the broker
//--------------------------------------------------------------------
void AdoptOpenPosition()
{
   if(!PositionOnSymbol()) return;

   long   liveId = PositionGetInteger(POSITION_IDENTIFIER);
   double liveSL = PositionGetDouble(POSITION_SL);
   double liveEntry = PositionGetDouble(POSITION_PRICE_OPEN);
   int    liveDir = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? 1 : -1;
   double liveVol = PositionGetDouble(POSITION_VOLUME);

   if(g_posId==liveId && g_entry>0 && g_risk>0)
   {
      // state file matched the live position - nothing to reconstruct
      g_curSL = liveSL;
      // ...except the clock. Re-derive the entry time from the RAW instant with
      // whatever offset is in force now, so a restart repairs a stamp that was
      // written while the offset was wrong instead of carrying it forever.
      if(g_entryTimeSrv==0) g_entryTimeSrv=(datetime)PositionGetInteger(POSITION_TIME);
      StampEntryClock(g_entryTimeSrv);
      Say("STATE",StringFormat("resumed | %s %.2f lots from %s | SL %s | TPs hit %d%d%d%d%d | full state recovered",
          (liveDir==1?"BUY":"SELL"), liveVol, DoubleToString(liveEntry,_Digits),
          DoubleToString(liveSL,_Digits),
          (int)g_tpHit[0],(int)g_tpHit[1],(int)g_tpHit[2],(int)g_tpHit[3],(int)g_tpHit[4]));
      return;
   }

   // no usable state - rebuild what we can and say plainly that it is approximate
   double atr; if(!Val(hAtr,1,atr)) atr=0;
   bool   dayTime = InDaySessionIST(TimeCurrent());
   double slFac   = (!dayTime && InpUseHalfSlOutside) ? InpOutsideSlFactor : 1.0;
   double risk    = (liveSL>0) ? MathAbs(liveEntry-liveSL) : atr*InpSlAtrMult*slFac;
   if(risk<=0) risk = atr*InpSlAtrMult;

   g_posId    = liveId;
   g_tradeId  = liveId;
   g_dir      = liveDir;
   g_entry    = liveEntry;
   g_risk     = risk;
   g_tpUnit   = risk;
   g_slFactor = slFac;
   g_origVol  = liveVol;
   g_initSL   = (liveSL>0?liveSL:0);
   g_curSL    = liveSL;
   g_fullTgt  = InpUseScaleOut && InpUseFullTarget;
   g_entryTag = ModeTag(g_fullTgt,slFac) + "-ADOPTED";
   StampEntryClock((datetime)PositionGetInteger(POSITION_TIME));
   g_entryBar = (datetime)PositionGetInteger(POSITION_TIME);
   g_qfFlags  = "";
   g_lastSignal = liveDir;

   double Rm[5]={InpTP1_R,InpTP2_R,InpTP3_R,InpTP4_R,InpTP5_R};
   double px=(liveDir==1)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   for(int i=0;i<5;i++)
   {
      g_tpPrice[i]=(liveDir==1)?g_entry+risk*Rm[i]:g_entry-risk*Rm[i];
      // treat a level price has already passed as done, so the ladder does not jump backwards
      g_tpHit[i]=(liveDir==1)?(px>=g_tpPrice[i]):(px<=g_tpPrice[i]);
   }

   Say("STATE",StringFormat("ADOPTED (approximate) | %s %.2f lots from %s | SL %s | 1R assumed %s | TPs marked %d%d%d%d%d",
       (liveDir==1?"BUY":"SELL"), liveVol, DoubleToString(liveEntry,_Digits),
       DoubleToString(liveSL,_Digits), DoubleToString(risk,_Digits),
       (int)g_tpHit[0],(int)g_tpHit[1],(int)g_tpHit[2],(int)g_tpHit[3],(int)g_tpHit[4]));
   Say("STATE","note | 1R was rebuilt from the live SL distance, so the TP ladder may differ from the original");
   LogEvent("ADOPTED",g_entry,liveVol,liveVol,0.0,0.0,0.0,"position adopted after restart without saved state");
}

//====================================================================
//  ON-CHART DASHBOARD
//    One background box plus PANEL_ROWS labels, refreshed about once a
//    second. Everything shown is already computed elsewhere - the panel
//    only formats it.
//====================================================================
void PanelRow(int row,const string text,color clr)
{
   string nm=PANEL_PFX+"L"+IntegerToString(row);
   if(ObjectFind(0,nm)<0)
   {
      ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,nm,OBJPROP_CORNER,InpPanelCorner);
      ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,InpPanelX+8);
      ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,InpPanelY+8+row*(InpPanelFont+6));
      ObjectSetString (0,nm,OBJPROP_FONT,InpPanelFontName);
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,InpPanelFont);
      ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,nm,OBJPROP_BACK,false);
   }
   ObjectSetString (0,nm,OBJPROP_TEXT,text);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,clr);
}

void PanelCreate()
{
   string bg=PANEL_PFX+"BG";
   if(ObjectFind(0,bg)<0)
   {
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,InpPanelCorner);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,InpPanelX);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,InpPanelY);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,430);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,PANEL_ROWS*(InpPanelFont+6)+18);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,InpPanelBg);
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,C'60,70,88');
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   }
}

void PanelDestroy()
{
   ObjectsDeleteAll(0,PANEL_PFX);
}

void PanelUpdate()
{
   if(!InpShowPanel) return;
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   if(GetTickCount()-g_panelTick < 1000) return;      // ~1 Hz is plenty
   g_panelTick=GetTickCount();

   PanelCreate();

   bool   day = InDaySessionIST(TimeCurrent());
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double net = g_dGrossP - g_dGrossL;
   int    r   = 0;

   color cHead = clrDeepSkyBlue;
   color cTxt  = InpPanelText;
   color cGood = clrMediumSpringGreen;
   color cBad  = clrTomato;
   color cWarn = clrGold;

   PanelRow(r++,StringFormat("%s  %s   %s",
            _Symbol, StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7),
            (InpSignalsOnly?"SIGNALS ONLY":"LIVE")), cHead);

   PanelRow(r++,StringFormat("IST %s   server %s",
            TimeToString(ServerToIST(TimeCurrent()),TIME_MINUTES),
            TimeToString(TimeCurrent(),TIME_MINUTES)), cTxt);

   PanelRow(r++,StringFormat("Session   %-8s  lot %s",
            (day?"DAY":"EVENING"),
            (InpUseSessionLots?DoubleToString(day?InpDayLot:InpEveningLot,2)
                              :(InpUseFixedLot?DoubleToString(InpFixedLot,2):"risk %"))), cTxt);

   PanelRow(r++,StringFormat("Stop      x%.2f of usual   %s",
            (day||!InpUseHalfSlOutside)?1.0:InpOutsideSlFactor,
            (InpUseFullTarget?"full target, no partials":"partials TP1-TP4")), cTxt);

   PanelRow(r++,"------------------------------------------", cTxt);

   if(PositionOnSymbol())
   {
      double px   = (g_dir==1)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double open = PositionGetDouble(POSITION_PROFIT);
      int    hits = 0;
      for(int i=0;i<5;i++) if(g_tpHit[i]) hits++;

      PanelRow(r++,StringFormat("OPEN  %-4s %.2f lots @ %s",
               (g_dir==1?"BUY":"SELL"), PositionGetDouble(POSITION_VOLUME),
               DoubleToString(g_entry,_Digits)), (open>=0?cGood:cBad));
      PanelRow(r++,StringFormat("SL %s   next TP %s",
               DoubleToString(g_curSL,_Digits),
               (hits<5?DoubleToString(g_tpPrice[hits],_Digits):"-")), cTxt);
      PanelRow(r++,StringFormat("Now %s   %+.2fR   float %+.2f",
               DoubleToString(px,_Digits), RealizedR(px), open), (open>=0?cGood:cBad));
   }
   else
   {
      PanelRow(r++,"FLAT", cTxt);
      PanelRow(r++,StringFormat("Last signal  %s",
               (g_lastSignal==1?"BUY":(g_lastSignal==-1?"SELL":"none"))), cTxt);
      PanelRow(r++,"", cTxt);
   }

   PanelRow(r++,"------------------------------------------", cTxt);

   PanelRow(r++,StringFormat("Today  %d trades  W %d / L %d   net %+.2f",
            g_dTrades,g_dWins,g_dLoss,net), (net>=0?cGood:cBad));

   if(InpPropMode)
   {
      double dCap=DailyCap(), tCap=TotalCap();
      double dayLoss=g_dayStartBal-eq;
      string room;
      if(dCap<DBL_MAX)
         room=StringFormat("Day room %.2f of %.2f", MathMax(dCap-dayLoss,0), dCap);
      else
         room="Day cap off";
      if(InpMaxLossesPerDay>0)
         room+=StringFormat("   losses %d/%d",g_dLoss,InpMaxLossesPerDay);
      color rc=cTxt;
      if(dCap<DBL_MAX && dayLoss>=dCap*InpDailyWarnPct/100.0) rc=cWarn;
      if(g_dayLocked||g_acctLocked) rc=cBad;
      PanelRow(r++,room,rc);
   }
   else
      PanelRow(r++,"Funding guards off", cTxt);

   string gate="", gateWhy="";
   if(g_acctLocked)                         gate="ACCOUNT LOCKED";
   else if(g_dayLocked)                     gate="DAY LOCKED";
   else if(g_newsActive!="")                gate="NEWS PAUSE: "+g_newsActive;
   else if(!SessionAllowed())               gate="outside the entry window";
   else if(EveningEntryBlocked(gateWhy))    gate=gateWhy;
   else if(WeekendCutoffReached())          gate="weekend cutoff";
   else                                     gate="entries allowed";
   PanelRow(r++,gate,(StringFind(gate,"allowed")>=0?cGood:cWarn));

   PanelRow(r++,NextNewsText(), cTxt);

   ChartRedraw(0);
}

//====================================================================
//  SESSION BANNER - printed whenever the IST session changes, so each
//  block of the log opens with what that session is running on and
//  where the day already stands.
//====================================================================
string NextNewsText()
{
   if(!NewsModuleOn()) return "news module off";
   datetime now=TimeCurrent();
   int    best=-1;
   long   bestSecs=LONG_MAX;
   for(int i=0;i<ArraySize(g_news);i++)
   {
      long secs=(long)g_news[i].evTime-(long)now;
      if(secs<0) continue;
      if(secs<bestSecs){ bestSecs=secs; best=i; }
   }
   if(best<0) return "no releases queued in the next 24h";
   return StringFormat("%s %s at %s IST (in %d min)",
          g_news[best].cur, NewsImpText(g_news[best].imp),
          TimeToString(ServerToIST(g_news[best].evTime),TIME_MINUTES),
          (int)(bestSecs/60));
}

void SaySessionBanner(bool day)
{
   string nm = day ? "DAY" : "EVENING";
   Say("SESS",StringFormat("----- %s session open | %s - %s IST (inputs %d/%d) | %s IST | %s -----",
       nm,
       IstHourLabel(day?InpDaySessionStartIST:InpDaySessionEndIST),
       IstHourLabel(day?InpDaySessionEndIST:InpDaySessionStartIST),
       (day?InpDaySessionStartIST:InpDaySessionEndIST),
       (day?InpDaySessionEndIST:InpDaySessionStartIST),
       TimeToString(ServerToIST(TimeCurrent()),TIME_MINUTES),
       _Symbol));

   // what this session trades on
   Say("SESS",StringFormat("rules | %s | %s | %s | %s",
       SessionLotText(day), SessionStopText(day), SessionTargetText(day), SessionExitText()));

   // where the day already stands
   double eq      = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayLoss = g_dayStartBal - eq;
   double net     = g_dGrossP - g_dGrossL;
   double dCap    = InpPropMode ? DailyCap() : DBL_MAX;
   double tCap    = InpPropMode ? TotalCap() : DBL_MAX;

   Say("SESS",StringFormat("today | trades %d (W %d / L %d) | net %+.2f | netR %+.2fR | balance %.2f | equity %.2f",
       g_dTrades, g_dWins, g_dLoss, net, g_dR,
       AccountInfoDouble(ACCOUNT_BALANCE), eq));

   if(InpPropMode)
   {
   string room = "";
   if(dCap<DBL_MAX)
      room += StringFormat("daily cap %.2f, used %.2f, left %.2f",dCap,MathMax(dayLoss,0),MathMax(dCap-dayLoss,0));
   else
      room += "daily cap off";
   if(InpMaxLossesPerDay>0)
      room += StringFormat(" | losses %d of %d",g_dLoss,InpMaxLossesPerDay);
   if(tCap<DBL_MAX)
   {
      double ls=g_baseline-eq, lt=g_peakEquity-eq;
      double used=(InpDrawdownMode==1)?lt:((InpDrawdownMode==0)?ls:MathMax(ls,lt));
      room += StringFormat(" | overall used %.2f of %.2f (stops at %.2f, %s; peak %.2f)",
              MathMax(used,0), tCap, tCap*InpTotalLossStopPct/100.0, DDModeText(), g_peakEquity);
   }
   Say("SESS","room | " + room);
   }

   // gates and open risk
   string gate = InpUseSessionFilter
               ? StringFormat("entry window %02d:00-%02d:00 server",InpSessionStartHour,InpSessionEndHour)
               : "entry window off";
   if(InpPropMode && g_acctLocked)     gate += " | ACCOUNT LOCKED";
   else if(InpPropMode && g_dayLocked) gate += " | DAY LOCKED";
   Say("SESS","gates | " + gate + " | " + NextNewsText());

   if(PositionOnSymbol())
      Say("SESS",StringFormat("open | %s %.2f lots from %s | SL %s | carried into this session",
          (g_dir==1?"BUY":"SELL"), PositionGetDouble(POSITION_VOLUME),
          DoubleToString(g_entry,_Digits), DoubleToString(g_curSL,_Digits)));
   else
      Say("SESS","open | flat");
}

void CheckSessionChange()
{
   int now = InDaySessionIST(TimeCurrent()) ? 1 : 0;
   if(now == g_sessNow) return;
   g_sessNow = now;
   SaySessionBanner(now==1);
}

//====================================================================
//  STARTUP / DAILY BANNER - every setting that applies, per IST session
//====================================================================
string SessionLotText(bool day)
{
   if(InpUseSessionLots) return StringFormat("lot %.2f",(day?InpDayLot:InpEveningLot));
   if(InpUseFixedLot)    return StringFormat("lot %.2f (fixed, both sessions)",InpFixedLot);
   if(InpUseSessionRisk)
      return StringFormat("lot auto (risk %.2f%% of balance, %s)",
                          (day?InpDayRiskPct:InpEveningRiskPct),(day?"day":"evening"));
   return StringFormat("lot auto (risk %.2f%% of balance)",InpRiskPercent);
}

string SessionStopText(bool day)
{
   double f = (day || !InpUseHalfSlOutside) ? 1.0 : InpOutsideSlFactor;
   string t = StringFormat("SL ATR(%d) x%.2f",InpAtrPeriod,InpSlAtrMult*f);
   if(f!=1.0) t += StringFormat(" (x%.2f of usual)",f);
   return t;
}

string SessionTargetText(bool day)
{
   double f = (day || !InpUseHalfSlOutside) ? 1.0 : InpOutsideSlFactor;
   string basis = (f==1.0) ? "" : (InpTpFromHalvedRisk ? " off the reduced stop" : " off the FULL ATR stop");
   return StringFormat("TP %.0f/%.0f/%.0f/%.0f/%.0fR%s",
                       InpTP1_R,InpTP2_R,InpTP3_R,InpTP4_R,InpTP5_R,basis);
}

string SessionExitText()
{
   if(!InpUseScaleOut) return StringFormat("single TP at %.1fR",InpTpRMultiple);
   if(RunnerOn())
      return StringFormat("no partials, TP5 NOT booked - runs on in %.1fR rungs until the signal flips",
                          InpRunnerStepR);
   if(InpUseFullTarget)
      return "no partials, full size to TP5, SL steps BE>TP1>TP2>TP3";
   return StringFormat("book %.0f%% at TP1-TP4, SL trails each level",InpPartialPct);
}

void SayStartupBanner(const string why)
{
   Say("CONFIG",StringFormat("===== EMA Strategy v1.20 | %s %s | %s | magic %d | %s =====",
       _Symbol, StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7),
       TimeToString(TimeCurrent(),TIME_DATE), InpMagic, why));

   Say("CONFIG",StringFormat("clock | server GMT%+.1f | server now %s | IST now %s",
       ServerGmtOffsetHours(),
       TimeToString(TimeCurrent(),TIME_MINUTES),
       TimeToString(ServerToIST(TimeCurrent()),TIME_DATE|TIME_MINUTES)));

   // --- the two IST sessions, side by side ---
   Say("CONFIG",StringFormat("DAY     %s - %s IST (inputs %d/%d) | %s | %s | %s | %s",
       IstHourLabel(InpDaySessionStartIST), IstHourLabel(InpDaySessionEndIST), InpDaySessionStartIST, InpDaySessionEndIST,
       SessionLotText(true), SessionStopText(true), SessionTargetText(true), SessionExitText()));

   Say("CONFIG",StringFormat("EVENING %s - %s IST (inputs %d/%d) | %s | %s | %s | %s",
       IstHourLabel(InpDaySessionEndIST), IstHourLabel(InpDaySessionStartIST), InpDaySessionEndIST, InpDaySessionStartIST,
       SessionLotText(false), SessionStopText(false), SessionTargetText(false), SessionExitText()));

   // --- what gates an entry ---
   string ent = InpUseSessionFilter
              ? StringFormat("entry window %02d:00-%02d:00 SERVER time",InpSessionStartHour,InpSessionEndHour)
              : "entry window OFF (all hours)";
   ent += InpMaxSpreadPts>0 ? StringFormat(" | max spread %d pts",InpMaxSpreadPts) : " | spread filter off";
   ent += InpTradeOnClose ? " | closed-bar entries" : " | every-tick entries";
   ent += InpEnableQFilter ? " | quality filter ON" : " | quality filter OFF";
   Say("CONFIG","entries | " + ent);

   // --- the evening session gate ---
   {
      string ev;
      if(!InpTradeEvening)
         ev = "evening session OFF - no entries 4 PM - 12 AM IST";
      else
      {
         ev = StringFormat("evening ON | entry window %02d:00-%02d:00 IST",
                           InpEveEntryStartIST, InpEveEntryEndIST);
         string off="";
         for(int h=16; h<24; h++)
            if(!EveningHourAllowed(h)) off += (off==""?"":",") + StringFormat("%02d",h);
         ev += (off=="" ? " | all hours on" : " | hours OFF: " + off);
      }
      if(InpUseSessionRisk)
         ev += StringFormat(" | risk %.2f%% day / %.2f%% evening",InpDayRiskPct,InpEveningRiskPct);
      Say("CONFIG","evening | " + ev);

      // the failure that is otherwise silent: evening settings that can never fire because
      // the SERVER-clock entry window does not overlap the evening at all.
      if(InpTradeEvening && !EveningReachable())
         Say("CONFIG",StringFormat("evening | WARNING: the server entry window %02d:00-%02d:00 never "
             "reaches an evening IST hour on a GMT%+.1f server, so the evening settings above - and "
             "InpEveningLot / InpOutsideSlFactor - can never apply. Widen InpSessionStartHour/EndHour "
             "or ignore the evening inputs.",
             InpSessionStartHour, InpSessionEndHour, ServerGmtOffsetHours()));
   }

   // --- guards ---
   if(InpPropMode)
   {
   double dCap=DailyCap(), tCap=TotalCap();
   Say("CONFIG",StringFormat("baseline | %.2f %s | trading day resets %02d:%02d %s",
       g_baseline, (InpBaselineBalance>0?"(user input)":"(balance at EA start)"),
       InpDayResetHour, InpDayResetMinute, (InpDayResetUseIST?"IST":"server")));

   Say("CONFIG",StringFormat("daily guard | cap %s | warn at %.0f%% (%s) | max losing trades %s | flatten on cap %s",
       (dCap<DBL_MAX?DoubleToString(dCap,2):"off"),
       InpDailyWarnPct,
       (dCap<DBL_MAX?DoubleToString(dCap*InpDailyWarnPct/100.0,2):"-"),
       (InpMaxLossesPerDay>0?IntegerToString(InpMaxLossesPerDay):"off"),
       (InpCloseOnDailyCap?"yes":"no")));

   Say("CONFIG",StringFormat("drawdown | %s | peak equity %.2f",DDModeText(),g_peakEquity));
   Say("CONFIG",StringFormat("overall guard | max %s | STOPS at %.0f%% (%s) | warn at %.0f%% (%s)",
       (tCap<DBL_MAX?DoubleToString(tCap,2):"off"),
       InpTotalLossStopPct,
       (tCap<DBL_MAX?DoubleToString(tCap*InpTotalLossStopPct/100.0,2):"-"),
       InpTotalWarnPct,
       (tCap<DBL_MAX?DoubleToString(tCap*InpTotalWarnPct/100.0,2):"-")));
   }
   else
      Say("CONFIG","funding guards | OFF (InpPropMode=false) - no daily cap, loss count or overall loss guard");

   string wk;
   if(InpHoldOverWeekend) wk="positions HELD over the weekend";
   else
   {
      int cs=FridayCloseSeconds();
      if(cs>0)
      {
         int cut=cs-InpFridayCloseBufferMin*60; if(cut<0) cut=0;
         wk=StringFormat("weekend flat by %02d:%02d server (close %02d:%02d)",
                         cut/3600,(cut%3600)/60, cs/3600,(cs%3600)/60);
      }
      else wk="weekend guard ARMED BUT INACTIVE - no friday session reported, set InpFridayCloseHour";
   }
   Say("CONFIG","guards | " + wk);

   {
      string ncur = (InpNewsCurrencies!="") ? InpNewsCurrencies
                  : SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE)+","+SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
      Say("CONFIG",StringFormat("news | filter %s | alerts %s | importance %d+ | pause -%d/+%d min | heads-up %d min | currencies %s | open trade %s%s",
          (InpUseNewsFilter?"ON":"off"),
          (InpNewsTgAlerts?"ON":"off"),
          InpNewsImportance, InpNewsMinsBefore, InpNewsMinsAfter, InpNewsAlertMins, ncur,
          (InpNewsCloseOpen?"flattened":"left running"),
          (InpNewsManualTimes!="" ? " | manual times supplied" : "")));
   }

   // --- run mode and logging ---
   Say("CONFIG",StringFormat("mode | %s | logging csv %s, json %s, telegram %s",
       (InpSignalsOnly?"SIGNALS ONLY (no orders)":"LIVE TRADING"),
       (InpUseCsvLog?"ON":"off"), (InpUseJsonLog?"ON":"off"),
       (InpUseTelegram?"ON":"off")));
}

//====================================================================
//  NEWS FILTER
//    Live: MT5's economic calendar (needs the terminal connected).
//    Tester / fallback: InpNewsManualTimes, a semicolon list of releases.
//  Blocks NEW entries inside the blackout, and optionally flattens first.
//====================================================================
// the module does its work when EITHER the blocking filter or the alerts are wanted
bool NewsModuleOn(){ return (InpUseNewsFilter || InpNewsTgAlerts); }

string NewsImpText(int imp)
{
   if(imp>=2) return "HIGH";
   if(imp==1) return "Moderate";
   return "Low";
}

// calendar figures arrive scaled by 1e6, LONG_MIN when the field is empty
string NewsVal(long v,int digits)
{
   if(v==LONG_MIN) return "-";
   return DoubleToString((double)v/1000000.0,digits);
}

void NewsAddWindow(datetime evTime,const string name,const string cur,int imp,
                   const string fc,const string pv)
{
   int n=ArraySize(g_news);
   ArrayResize(g_news,n+1);
   g_news[n].evTime = evTime;
   g_news[n].from   = evTime - InpNewsMinsBefore*60;
   g_news[n].to     = evTime + InpNewsMinsAfter*60;
   g_news[n].name   = name;
   g_news[n].cur    = cur;
   g_news[n].imp    = imp;
   g_news[n].fc     = fc;
   g_news[n].pv     = pv;
   g_news[n].said   = false;
}

// the currencies we care about: the input list, or the symbol's own two
void NewsCurrencyList(string &out[])
{
   if(InpNewsCurrencies!="")
   {
      StringSplit(InpNewsCurrencies,',',out);
      for(int i=0;i<ArraySize(out);i++)
      {
         StringTrimLeft(out[i]); StringTrimRight(out[i]);
         StringToUpper(out[i]);
      }
      return;
   }
   ArrayResize(out,2);
   out[0]=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE);
   out[1]=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
}

// an event is only announced once - remembered across refreshes by time+name
bool NewsAlreadySaid(const string key)
{
   for(int i=0;i<ArraySize(g_newsSaid);i++)
      if(g_newsSaid[i]==key) return true;
   return false;
}
void NewsMarkSaid(const string key)
{
   int n=ArraySize(g_newsSaid);
   if(n>200){ ArrayResize(g_newsSaid,0); n=0; }   // a day's worth is plenty
   ArrayResize(g_newsSaid,n+1);
   g_newsSaid[n]=key;
}

void NewsLoadManual()
{
   if(InpNewsManualTimes=="") return;
   string items[];
   int n=StringSplit(InpNewsManualTimes,';',items);
   for(int i=0;i<n;i++)
   {
      string it=items[i];
      StringTrimLeft(it); StringTrimRight(it);
      if(it=="") continue;
      datetime t=StringToTime(it);
      if(t<=0){ Say("NEWS","could not parse manual time: "+it); continue; }
      if(InpNewsManualIsIST) t=ISTToServer(t);
      NewsAddWindow(t,"scheduled release","",InpNewsImportance,"-","-");
   }
}

void NewsRefresh()
{
   if(!NewsModuleOn()) return;
   if(TimeCurrent()-g_newsRefreshed < 300) return;      // every 5 minutes is plenty
   g_newsRefreshed = TimeCurrent();

   ArrayResize(g_news,0);
   NewsLoadManual();                                    // manual entries always apply

   if(!g_newsOk) return;                                // calendar already known unavailable
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
   {
      if(!g_newsWarned)
      {
         g_newsWarned=true;
         Say("NEWS","calendar is not available in the Strategy Tester | using InpNewsManualTimes only");
      }
      g_newsOk=false;
      return;
   }

   datetime from = TimeCurrent() - 4*3600;
   datetime to   = TimeCurrent() + 24*3600;

   string curs[];
   NewsCurrencyList(curs);

   int added=0;
   for(int c=0;c<ArraySize(curs);c++)
   {
      if(curs[c]=="") continue;
      MqlCalendarValue vals[];
      int nv=CalendarValueHistory(vals,from,to,NULL,curs[c]);
      if(nv<0)
      {
         if(!g_newsWarned)
         {
            g_newsWarned=true;
            Say("NEWS",StringFormat("calendar unavailable (err %d) | falling back to manual times",GetLastError()));
         }
         g_newsOk=false;
         return;
      }
      for(int i=0;i<nv;i++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id,ev)) continue;

         int imp = 0;
         if(ev.importance==CALENDAR_IMPORTANCE_MODERATE) imp=1;
         else if(ev.importance==CALENDAR_IMPORTANCE_HIGH) imp=2;
         if(imp < InpNewsImportance) continue;

         NewsAddWindow(vals[i].time, ev.name, curs[c], imp,
                       NewsVal(vals[i].forecast_value,ev.digits),
                       NewsVal(vals[i].prev_value,    ev.digits));
         added++;
      }
   }
   if(added>0)
      Say("NEWS",StringFormat("calendar refreshed | %d release(s) in the next 24h at importance %d+",
          added,InpNewsImportance));
}

//--------------------------------------------------------------------
//  Heads-up post: fires InpNewsAlertMins before the release, whether or
//  not the blocking filter is on.
//--------------------------------------------------------------------
void NewsAnnounceUpcoming()
{
   if(!InpNewsTgAlerts) return;
   datetime now=TimeCurrent();

   for(int i=0;i<ArraySize(g_news);i++)
   {
      long secs = (long)g_news[i].evTime - (long)now;
      if(secs < 0 || secs > InpNewsAlertMins*60) continue;

      string key = TimeToString(g_news[i].evTime,TIME_DATE|TIME_MINUTES) + "|" + g_news[i].name;
      if(NewsAlreadySaid(key)) continue;
      NewsMarkSaid(key);

      int mins = (int)(secs/60);
      Say("NEWS",StringFormat("upcoming in %d min | %s %s | %s",
          mins, g_news[i].cur, NewsImpText(g_news[i].imp), g_news[i].name));

      string body = StringFormat("%-9s %s\n%-9s %s\n%-9s %s\n%-9s %s IST  (%s srv)\n%-9s in %d min",
                    "Event",    HtmlEsc(g_news[i].name),
                    "Currency", (g_news[i].cur==""?"-":g_news[i].cur),
                    "Impact",   NewsImpText(g_news[i].imp),
                    "Time",     IstClock(g_news[i].evTime),
                                TimeToString(g_news[i].evTime,TIME_MINUTES),
                    "Starts",   mins);

      if(g_news[i].fc!="-" || g_news[i].pv!="-")
         body += StringFormat("\n%-9s %s\n%-9s %s","Forecast",g_news[i].fc,"Previous",g_news[i].pv);

      string tail;
      if(InpUseNewsFilter)
         tail = StringFormat("\nNo new entries %s - %s IST. Open trades keep running%s.",
                IstClock(g_news[i].from),
                IstClock(g_news[i].to),
                (InpNewsCloseOpen?" until the flatten":""));
      else
         tail = "\nHeads-up only - the news filter is off, trading continues as normal.";

      TelegramSend(Emo(0x1F4F0) + " " + TgB("NEWS AHEAD") + "\n"
                 + _Symbol + "\n\n" + TgPre(body) + tail);
   }
}

// TRUE while inside a blackout; why = the event name
bool NewsBlackout(string &why)
{
   why="";
   if(!InpUseNewsFilter) return false;
   datetime now=TimeCurrent();
   for(int i=0;i<ArraySize(g_news);i++)
   {
      if(now>=g_news[i].from && now<=g_news[i].to)
      {
         why = g_news[i].name + (g_news[i].cur==""?"":" ("+g_news[i].cur+")");
         return true;
      }
   }
   return false;
}

// every tick: refresh, announce what is coming, then report whether entries are paused
bool NewsBlocksTrading()
{
   if(!NewsModuleOn()) return false;

   NewsRefresh();
   NewsAnnounceUpcoming();

   string why;
   if(!NewsBlackout(why))
   {
      if(g_newsActive!="")
      {
         Say("NEWS",StringFormat("window clear | %s | entries resume",g_newsActive));
         if(InpNewsTgAlerts)
            TelegramSend(Emo(0x2705) + " " + TgB("NEWS WINDOW CLEAR") + "\n"
                       + _Symbol + "\n\nEntries resume. (" + HtmlEsc(g_newsActive) + ")");
         g_newsActive="";
      }
      return false;
   }

   if(g_newsActive!=why)
   {
      g_newsActive=why;
      Say("NEWS",StringFormat("entries paused | %s | -%d/+%d min around the release",
          why,InpNewsMinsBefore,InpNewsMinsAfter));
      LogEvent("NEWS_PAUSE",0.0,0.0,0.0,0.0,0.0,0.0,"no new entries: "+why);

      // open positions are LEFT ALONE unless the user asked otherwise
      if(InpNewsCloseOpen && PositionOnSymbol())
      {
         Say("NEWS","flattening the open position before the release (InpNewsCloseOpen)");
         ClosePositionTagged("NEWS exit","EXIT_NEWS");
      }

      if(InpNewsTgAlerts)
         TelegramSend(Emo(0x23F8) + " " + TgB("NEW ENTRIES PAUSED") + "\n"
                    + _Symbol + "\n\n"
                    + TgPre(StringFormat("%-9s %s\n%-9s -%d / +%d min\n%-9s %s",
                            "Event",   HtmlEsc(why),
                            "Window",  InpNewsMinsBefore, InpNewsMinsAfter,
                            "Open pos",(InpNewsCloseOpen?"flattened":"left running"))));
   }
   return true;
}

//====================================================================
//  WEEKEND GUARD - flatten before the Friday close, skip new entries
//====================================================================
int FridayCloseSeconds()
{
   if(InpFridayCloseHour>=0)
      return InpFridayCloseHour*3600 + InpFridayCloseMinute*60;

   if(g_friCloseSec>=0) return g_friCloseSec;      // cached

   datetime from,to;
   int last=-1;
   for(uint idx=0; idx<8; idx++)
   {
      if(!SymbolInfoSessionTrade(_Symbol,FRIDAY,idx,from,to)) break;
      last=(int)to;                                 // keep the LAST session of the day
   }
   g_friCloseSec = last;
   return last;
}

// TRUE from (Friday close - buffer) until the end of Friday
bool WeekendCutoffReached()
{
   if(InpHoldOverWeekend) return false;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(dt.day_of_week != FRIDAY) return false;

   int closeSec = FridayCloseSeconds();
   if(closeSec <= 0) return false;                  // broker gave us nothing and no manual hour set

   int cutoff = closeSec - InpFridayCloseBufferMin*60;
   if(cutoff < 0) cutoff = 0;
   int nowSec = dt.hour*3600 + dt.min*60 + dt.sec;
   return (nowSec >= cutoff);
}

void DoWeekendClose()
{
   if(g_weekendFlat) return;                        // already handled this weekend

   if(InpSignalsOnly)
   {
      if(g_virtActive)
      {
         double px=(g_dir==1)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         LogEvent("EXIT_WEEKEND",px,0.0,0.0,0.0,RealizedR(px),0.0,"signal closed before the weekend");
         if(InpTgNotifyClose)
            TelegramSend(Emo(0x1F4F4) + " " + TgB("WEEKEND CLOSE - signal ended") + "\n"
                       + _Symbol + "  " + (g_dir==1?"BUY":"SELL") + "\n\n"
                       + TgVirtualClose(px));
         g_virtActive=false;
      }
      g_weekendFlat=true;
      return;
   }

   if(PositionOnSymbol())
   {
      Say("GUARD",StringFormat("weekend | flattening before the friday close | server %s | IST %s",
          TimeToString(TimeCurrent(),TIME_MINUTES),
          TimeToString(ServerToIST(TimeCurrent()),TIME_MINUTES)));
      ClosePositionTagged("WEEKEND exit","EXIT_WEEKEND");
      if(InpTgNotifyClose)
         TelegramSend(Emo(0x1F4F4) + " " + TgB("WEEKEND CLOSE") + "\n"
                    + _Symbol + "\n\nPosition flattened before the Friday close.");
   }
   g_weekendFlat=true;
}

//====================================================================
//  SESSION / TIME FILTER  (server clock - unchanged)
//====================================================================
bool SessionAllowed()
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);            // TimeCurrent() = broker/server time
   int h = dt.hour;
   int s = InpSessionStartHour, e = InpSessionEndHour;
   if(s==e) return true;                       // whole day (filter effectively off)
   if(s< e) return (h>=s && h<e);              // normal same-day window
   return (h>=s || h<e);                       // window wraps past midnight
}

//====================================================================
//  EVENING ENTRY GATE
//
//  Only ever refuses an entry. It never closes, never modifies a stop and
//  never touches the day session. An open trade carried into a switched-off
//  hour keeps running on its own SL/TP - stopping NEW entries and flattening
//  an existing one are different decisions, and only the first was asked for.
//====================================================================
bool EveningHourAllowed(int h)
{
   switch(h)
   {
      case 16: return InpEveH16;
      case 17: return InpEveH17;
      case 18: return InpEveH18;
      case 19: return InpEveH19;
      case 20: return InpEveH20;
      case 21: return InpEveH21;
      case 22: return InpEveH22;
      case 23: return InpEveH23;
   }
   return true;                                 // an evening hour with no toggle is allowed
}

bool InEveningEntryWindow(int h)
{
   int s=InpEveEntryStartIST, e=InpEveEntryEndIST;
   if(s==e) return true;                        // whole evening block
   if(s< e) return (h>=s && h<e);
   return (h>=s || h<e);                        // wraps past midnight, e.g. 16 -> 0
}

// TRUE = refuse this entry; why explains which of the three rules refused it
bool EveningEntryBlocked(string &why)
{
   why="";
   if(InDaySessionIST(TimeCurrent())) return false;   // day session is never gated here

   if(!InpTradeEvening){ why="evening session switched off"; return true; }

   MqlDateTime dt; TimeToStruct(ServerToIST(TimeCurrent()),dt);
   int h=dt.hour;

   if(!InEveningEntryWindow(h))
   {
      why=StringFormat("IST %02d:00 outside the evening entry window %02d:00-%02d:00",
                       h,InpEveEntryStartIST,InpEveEntryEndIST);
      return true;
   }
   if(!EveningHourAllowed(h))
   {
      why=StringFormat("IST hour %02d:00-%02d:00 switched off",h,(h+1)%24);
      return true;
   }
   return false;
}

// Can the server-clock entry window ever reach an evening IST hour at all?
// Answers the one failure nobody would spot: evening settings that cannot fire.
bool EveningReachable()
{
   for(int sh=0; sh<24; sh++)
   {
      int s=InpSessionStartHour, e=InpSessionEndHour;
      bool inSrv = (s==e) ? true : ((s<e) ? (sh>=s && sh<e) : (sh>=s || sh<e));
      if(!inSrv) continue;
      // server hour sh -> IST, using the configured offset
      double istF = (double)sh - ServerGmtOffsetHours() + 5.5;
      while(istF<0)   istF+=24.0;
      while(istF>=24) istF-=24.0;
      int ih=(int)istF;
      int ds=InpDaySessionStartIST, de=InpDaySessionEndIST;
      bool isDay = (ds==de) ? true : ((ds<de) ? (ih>=ds && ih<de) : (ih>=ds || ih<de));
      if(!isDay) return true;                   // this server hour lands in the evening
   }
   return false;
}

//====================================================================
//  IST CLOCK + FULL-TARGET WINDOW
//====================================================================
double ServerGmtOffsetHours()
{
   if(InpAutoGmtOffset && !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
   {
      long diff=(long)TimeCurrent()-(long)TimeGMT();
      if(MathAbs(diff) <= 14*3600)
         return MathRound((double)diff/1800.0)/2.0;    // snapped to the nearest half hour
   }
   return InpServerGmtOffset;
}

// Label for an INPUT hour. The session inputs are 24-hour (0 = midnight,
// 16 = 4 PM) and must stay that way - everything compares against dt.hour.
// The banner prints both so "4" is never mistaken for 4 PM.
string IstHourLabel(int h)
{
   int h12 = h % 12; if(h12==0) h12 = 12;
   return StringFormat("%d %s", h12, (h < 12 ? "AM" : "PM"));
}

// IST on a 12-hour clock, the way it is read locally: "02:29 AM".
// 24-hour "02:29" is what caused a 2 AM message to be mistaken for 2 PM.
string IstClock(datetime tServer)
{
   MqlDateTime d; TimeToStruct(ServerToIST(tServer),d);
   int h12 = d.hour % 12; if(h12==0) h12 = 12;
   return StringFormat("%02d:%02d %s", h12, d.min, (d.hour < 12 ? "AM" : "PM"));
}

// "14:05" -> "02:05p". The stored value stays 24-hour because the state file
// and the dashboard read it; only the Telegram table is rendered 12-hour.
string Hm12(const string hhmm)
{
   if(StringLen(hhmm) < 4) return hhmm;
   int h = (int)StringToInteger(StringSubstr(hhmm,0,2));
   string mm = StringSubstr(hhmm,3,2);
   int h12 = h % 12; if(h12==0) h12 = 12;
   return StringFormat("%02d:%s%s", h12, mm, (h < 12 ? "a" : "p"));
}

datetime ServerToIST(datetime tServer)
{
   long offSec=(long)MathRound(ServerGmtOffsetHours()*3600.0);
   return (datetime)((long)tServer - offSec + 19800);   // IST = GMT + 5:30
}

// Record the entry instant on BOTH clocks.
//
// g_entryIst stays HH:MM because the end-of-day Telegram table pads its columns
// to a fixed width. But HH:MM alone is ambiguous the moment a trade is held
// overnight - and with InpBookAtTP5 off a runner can be held for days - so the
// dashboard needs the date too. Keeping the broker's own time alongside it
// means the IST conversion can be checked rather than trusted.
void StampEntryClock(datetime tServer)
{
   g_entryTimeSrv = tServer;
   g_entryIst     = TimeToString(ServerToIST(tServer),TIME_MINUTES);
   g_entryIstFull = TimeToString(ServerToIST(tServer),TIME_DATE|TIME_MINUTES);
   g_entrySrvFull = TimeToString(tServer,TIME_DATE|TIME_MINUTES);
}

// short label that says how this trade is being managed (used in comments, logs, alerts)
string ModeTag(bool fullTgt,double slFactor)
{
   if(!InpUseScaleOut) return "SINGLETP";
   if(!fullTgt)        return (slFactor<1.0) ? "PART_HALFSL" : "SCALEOUT";
   return (slFactor<1.0) ? "FULLTGT_HALFSL" : "FULLTGT";
}

// TRUE while IST time is inside the DAY session [InpDaySessionStartIST , InpDaySessionEndIST)
// i.e. 12 AM - 4 PM IST by default. FALSE = the evening session, where the stop is halved.
bool InDaySessionIST(datetime tServer)
{
   MqlDateTime dt; TimeToStruct(ServerToIST(tServer),dt);
   int h=dt.hour;
   int s=InpDaySessionStartIST, e=InpDaySessionEndIST;
   if(s==e) return true;                       // whole day
   if(s< e) return (h>=s && h<e);
   return (h>=s || h<e);                       // wraps past midnight
}

//====================================================================
//  UNIFIED EVENT LOG - one fixed CSV layout for every event type
//====================================================================
string LogFileName(const string ext)
{
   string tf=StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7);
   return InpCsvPrefix + "_" + _Symbol + "_" + tf + ext;
}

void TakeSnapshot(SnapVals &s)
{
   s.ema9=0; s.ema21=0; s.ema50=0; s.ema9p=0; s.ema21p=0; s.atr=0; s.adx=0;
   s.rsi=0;  s.rsi5=0;  s.macdM=0; s.macdS=0;
   Val(hEma9,1,s.ema9);   Val(hEma9,2,s.ema9p);
   Val(hEma21,1,s.ema21); Val(hEma21,2,s.ema21p);
   Val(hEma50,1,s.ema50);
   Val(hAtr,1,s.atr);     Val(hAdx,1,s.adx);
   Val(hRsi,1,s.rsi);     Val(hRsiM5,1,s.rsi5);
   Val2(hMacd,0,1,s.macdM); Val2(hMacd,1,1,s.macdS);
   s.close = iClose(_Symbol,_Period,1);
   s.vwap  = SessionVWAP();
   s.vol   = (double)iVolume(_Symbol,_Period,1);
   s.volAvg= VolumeSMA(InpVolAvgPeriod);
   BiasScores(s.close,s.vwap,s.bull,s.bear);
   s.spread= SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
}

void LogEvent(const string evt,double evPrice,double evLots,double remLots,
              double rTarget,double rRealized,double profit,const string note)
{
   if(!InpUseCsvLog && !InpUseJsonLog && !InpEchoLogToTerminal) return;

   SnapVals s; TakeSnapshot(s);
   g_logSeq++;

   int    dg   = _Digits;
   string tf   = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7);
   string dirS = (g_dir==1)?"BUY":((g_dir==-1)?"SELL":"FLAT");
   double gap  = (s.atr>0)?(s.ema21-s.ema50)/s.atr:0.0;

   string row=
      IntegerToString(g_logSeq)                                        + "," +
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)               + "," +
      TimeToString(ServerToIST(TimeCurrent()),TIME_DATE|TIME_SECONDS)  + "," +
      evt                                                              + "," +
      _Symbol                                                          + "," +
      tf                                                               + "," +
      IntegerToString(g_tradeId)                                       + "," +
      dirS                                                             + "," +
      (g_entryTag=="" ? "NA" : g_entryTag)                             + "," +
      (InDaySessionIST(TimeCurrent())?"DAY":"EVENING")                   + "," +
      IntegerToString(g_flipFrom)                                        + "," +
      DoubleToString(g_entry,dg)                                       + "," +
      DoubleToString(g_initSL,dg)                                      + "," +
      DoubleToString(g_curSL,dg)                                       + "," +
      DoubleToString(g_risk,dg)                                        + "," +
      DoubleToString(g_slFactor,2)                                     + "," +
      DoubleToString(g_tpUnit,dg)                                      + "," +
      DoubleToString(g_tpPrice[0],dg) + "," + DoubleToString(g_tpPrice[1],dg) + "," +
      DoubleToString(g_tpPrice[2],dg) + "," + DoubleToString(g_tpPrice[3],dg) + "," +
      DoubleToString(g_tpPrice[4],dg)                                  + "," +
      DoubleToString(g_origVol,2)                                      + "," +
      DoubleToString(evLots,2)                                         + "," +
      DoubleToString(remLots,2)                                        + "," +
      DoubleToString(evPrice,dg)                                       + "," +
      DoubleToString(rTarget,2)                                        + "," +
      DoubleToString(rRealized,2)                                      + "," +
      DoubleToString(profit,2)                                         + "," +
      DoubleToString(s.ema9,dg)   + "," + DoubleToString(s.ema21,dg)  + "," +
      DoubleToString(s.ema50,dg)  + "," + DoubleToString(s.ema9p,dg)  + "," +
      DoubleToString(s.ema21p,dg) + "," + DoubleToString(gap,3)       + "," +
      DoubleToString(s.atr,dg)    + "," + DoubleToString(s.adx,2)     + "," +
      DoubleToString(s.rsi,2)     + "," + DoubleToString(s.rsi5,2)    + "," +
      DoubleToString(s.macdM,dg)  + "," + DoubleToString(s.macdS,dg)  + "," +
      DoubleToString(s.macdM-s.macdS,dg)                               + "," +
      DoubleToString(s.vwap,dg)   + "," + DoubleToString(s.close,dg)  + "," +
      DoubleToString(s.vol,0)     + "," + DoubleToString(s.volAvg,0)  + "," +
      DoubleToString(s.bull,1)    + "," + DoubleToString(s.bear,1)    + "," +
      IntegerToString(s.spread)                                        + "," +
      (InpEnableQFilter?"1":"0")                                       + "," +
      (g_qfFlags==""?"NA":g_qfFlags)                                   + "," +
      DoubleToString(ExcursionR(g_mfe),2)                              + "," +
      DoubleToString(ExcursionR(g_mae),2)                              + "," +
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)             + "," +
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)              + "," +
      CsvSafe(note);

   // the same event as one JSON object - readable in the Experts tab, parseable in reports
   string json = BuildJson(evt,evPrice,evLots,remLots,rTarget,rRealized,profit,note,s,gap,dirS,tf);

   if(InpUseCsvLog)                       WriteTextRow(LogFileName(".csv"), CSV_HEADER, row);
   if(g_logCsvOnly) return;               // summary rows emit their own JSON object
   if(InpEchoLogToTerminal)               Say("EVENT",json);
   if(InpUseJsonLog)                      WriteTextRow(LogFileName(".jsonl"), "", json);
}

//--------------------------------------------------------------------
//  JSON builders - small helpers so every object is quoted the same way
//--------------------------------------------------------------------
string Js(const string k,const string v){ return "\""+k+"\":\""+JsonEsc(v)+"\""; }           // string value
string Jn(const string k,double v,int d) { return "\""+k+"\":"+DoubleToString(v,d);   }        // number
string Ji(const string k,long v)         { return "\""+k+"\":"+IntegerToString(v);    }        // integer
string Jb(const string k,bool v)         { return "\""+k+"\":"+(v?"true":"false");    }        // boolean

string JsonEsc(const string src)
{
   string t=src;
   StringReplace(t,"\\","\\\\");
   StringReplace(t,"\"","\\\"");
   StringReplace(t,"\n"," ");
   StringReplace(t,"\r"," ");
   StringReplace(t,"\t"," ");
   return t;
}

// "CROSS=EMA9<EMA21;TREND=0;STRUCT=1" -> "cross":"EMA9<EMA21","trend":0,"struct":1
string FlagsToJson(const string flags)
{
   if(flags=="" || flags=="NA") return "";
   string parts[];
   int n=StringSplit(flags,';',parts);
   string out="";
   for(int i=0;i<n;i++)
   {
      string kv[];
      if(StringSplit(parts[i],'=',kv)!=2) continue;
      string k=kv[0]; StringToLower(k);
      string v=kv[1];
      if(out!="") out+=",";
      out += (v=="0"||v=="1") ? Ji(k,(long)StringToInteger(v)) : Js(k,v);
   }
   return out;
}

string BuildJson(const string evt,double evPrice,double evLots,double remLots,
                 double rTarget,double rRealized,double profit,const string note,
                 SnapVals &s,double gap,const string dirS,const string tf)
{
   int  dg      = _Digits;
   bool isSkip  = (evt=="SKIP");
   bool isEntry = (evt=="ENTRY" || evt=="FLIP" || isSkip); // decision moment -> log the LOGIC
   bool isExit  = (StringFind(evt,"EXIT")==0);            // outcome moment  -> log the RESULT

   string j="{";
   j += Ji("seq",g_logSeq)                                                          + ",";
   j += Js("t_srv",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS))              + ",";
   j += Js("t_ist",TimeToString(ServerToIST(TimeCurrent()),TIME_DATE|TIME_SECONDS)) + ",";
   j += Js("event",evt)                                                             + ",";
   j += Js("sym",_Symbol)                                                           + ",";
   j += Js("tf",tf)                                                                 + ",";
   j += Ji("trade",g_tradeId)                                                       + ",";
   j += Js("dir",dirS)                                                              + ",";
   j += Js("mode",(g_entryTag==""?"NA":g_entryTag))                                 + ",";
   j += Js("session",(InDaySessionIST(TimeCurrent())?"DAY":"EVENING"))              + ",";
   if(g_flipFrom!=0) j += Ji("flip_from",g_flipFrom)                                + ",";

   if(isEntry)
   {
      // WHY the trade was taken - indicator state only, no price levels.
      // Entry / SL / TP levels live in the CSV and in the [ENTRY] line above.
      j += "\"logic\":{";
         j += Jn("ema9",s.ema9,dg)       + ",";
         j += Jn("ema21",s.ema21,dg)     + ",";
         j += Jn("ema50",s.ema50,dg)     + ",";
         j += Jn("ema9_prev",s.ema9p,dg) + ",";
         j += Jn("ema21_prev",s.ema21p,dg)+ ",";
         j += Jn("ema_gap_atr",gap,3)    + ",";
         j += Jn("atr",s.atr,dg)         + ",";
         j += Jn("adx",s.adx,2)          + ",";
         j += Jn("rsi",s.rsi,2)          + ",";
         j += Jn("rsi_m5",s.rsi5,2)      + ",";
         j += Jn("macd",s.macdM,dg)      + ",";
         j += Jn("macd_sig",s.macdS,dg)  + ",";
         j += Jn("macd_hist",s.macdM-s.macdS,dg) + ",";
         j += Jn("vwap",s.vwap,dg)       + ",";
         j += Jn("close",s.close,dg)     + ",";
         j += Jn("vol",s.vol,0)          + ",";
         j += Jn("vol_avg",s.volAvg,0)   + ",";
         j += Jn("bull_pct",s.bull,1)    + ",";
         j += Jn("bear_pct",s.bear,1)    + ",";
         j += Ji("spread",s.spread);
      j += "},";

      string fl=FlagsToJson(g_qfFlags);
      j += "\"filters\":{" + Jb("enabled",InpEnableQFilter) + (fl==""?"":","+fl) + "},";
      if(isSkip) j += Js("skip_dir",(g_skipDir==1?"BUY":"SELL")) + ",";
   }
   else
   {
      // TP / SL_MOVE / EXIT - what actually happened, nothing else
      j += "\"result\":{";
         j += Jn("price",evPrice,dg)   + ",";
         j += Jn("r_target",rTarget,2) + ",";
         j += Jn("r_real",rRealized,2) + ",";
         j += Jn("lots",evLots,2)      + ",";
         j += Jn("lots_left",remLots,2);
         if(isExit) j += "," + Jn("profit",profit,2)
                        + "," + Jn("mfe_r",ExcursionR(g_mfe),2)
                        + "," + Jn("mae_r",ExcursionR(g_mae),2);
      j += "},";
   }

   if(isEntry || isExit)
      j += "\"acct\":{" + Jn("balance",AccountInfoDouble(ACCOUNT_BALANCE),2) + ","
                        + Jn("equity", AccountInfoDouble(ACCOUNT_EQUITY),2)  + "},";

   j += Js("note",note);
   j += "}";
   return j;
}

//--------------------------------------------------------------------
//  [LOGIC] and [FILTER] - the reasoning behind the entry, printed as
//  two separate lines right under [ENTRY]
//--------------------------------------------------------------------
void SayEntryLogic()
{
   SnapVals s; TakeSnapshot(s);
   int dg=_Digits;
   double gap=(s.atr>0)?(s.ema21-s.ema50)/s.atr:0.0;

   Say("LOGIC",StringFormat(
       "EMA 9/21/50 %s / %s / %s | prev 9/21 %s / %s | gap %.3f ATR | ATR %s | ADX %.2f",
       DoubleToString(s.ema9,dg),DoubleToString(s.ema21,dg),DoubleToString(s.ema50,dg),
       DoubleToString(s.ema9p,dg),DoubleToString(s.ema21p,dg),
       gap,DoubleToString(s.atr,dg),s.adx));

   Say("LOGIC",StringFormat(
       "RSI %.2f (M5 %.2f) | MACD %s / sig %s / hist %s | VWAP %s | close %s | vol %.0f vs avg %.0f | bias bull %.1f%% bear %.1f%% | spread %d",
       s.rsi,s.rsi5,
       DoubleToString(s.macdM,dg),DoubleToString(s.macdS,dg),DoubleToString(s.macdM-s.macdS,dg),
       DoubleToString(s.vwap,dg),DoubleToString(s.close,dg),
       s.vol,s.volAvg,s.bull,s.bear,(int)s.spread));
}

void SayEntryFilters()
{
   string line = InpEnableQFilter ? "quality filter ON " : "quality filter OFF";

   if(g_qfFlags!="" && g_qfFlags!="NA")
   {
      string parts[];
      int n=StringSplit(g_qfFlags,';',parts);
      for(int i=0;i<n;i++)
      {
         string kv[];
         if(StringSplit(parts[i],'=',kv)!=2) continue;
         string k=kv[0]; StringToLower(k);
         string v=kv[1];
         if(v=="1")      v="PASS";
         else if(v=="0") v="FAIL";          // shown even when the filter is off, so you can
         line += " | " + k + " " + v;       // see what WOULD have been blocked
      }
   }
   Say("FILTER",line);
}

string CsvSafe(const string src)
{
   string t=src;
   StringReplace(t,",",";");                  // keep the column count fixed
   StringReplace(t,"\n"," ");
   StringReplace(t,"\r"," ");
   return t;
}

// one writer for both files: header is written once, only if the file is new and a header was given
void WriteTextRow(const string fn,const string header,const string row)
{
   bool isNew=!FileIsExist(fn);
   int  h=FileOpen(fn,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE){ Say("ERROR",StringFormat("log file open failed | err %d | %s",GetLastError(),fn)); return; }
   FileSeek(h,0,SEEK_END);
   if(isNew && header!="") FileWriteString(h,header+"\r\n");
   FileWriteString(h,row+"\r\n");
   FileClose(h);
}

//====================================================================
//  TELEGRAM PUSH  (uses WebRequest -> Telegram Bot API)
//====================================================================
string UrlEncode(const string src)
{
   string res="";
   uchar b[];
   int n = StringToCharArray(src, b, 0, WHOLE_ARRAY, CP_UTF8) - 1;   // drop trailing 0
   for(int i=0;i<n;i++)
   {
      uchar c = b[i];
      if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||
         c=='-'||c=='_'||c=='.'||c=='~')
         res += CharToString(c);
      else
         res += StringFormat("%%%02X", c);
   }
   return res;
}

// escape the three characters Telegram's HTML parser cares about.
// Needed for anything dynamic (filter text contains "<", notes may contain "&").
string HtmlEsc(const string src)
{
   string t=src;
   StringReplace(t,"&","&amp;");
   StringReplace(t,"<","&lt;");
   StringReplace(t,">","&gt;");
   return t;
}

// MQL5's StringFormat has no "%-*s" star width, so columns are padded by hand
string Pad(const string v,int w)
{
   string t=v;
   while(StringLen(t)<w) t+=" ";
   return t;
}
string PadL(const string v,int w)
{
   string t=v;
   while(StringLen(t)<w) t=" "+t;
   return t;
}

string TgB(const string v){ return InpTgHtmlStyle ? "<b>"+v+"</b>" : v; }          // bold
string TgM(const string v){ return InpTgHtmlStyle ? "<code>"+v+"</code>" : v; }    // monospace inline
string TgPre(const string v)                                                        // monospace block
{
   return InpTgHtmlStyle ? "<pre>"+v+"</pre>" : v;
}

void TelegramSendRaw(const string text)
{
   if(!InpUseTelegram) return;
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return; // WebRequest is disabled in the tester
   if(InpTgToken=="" || InpTgChatId==""){ Say("TG","token or chat_id is empty | nothing sent"); return; }

   string url  = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "chat_id=" + InpTgChatId + "&text=" + UrlEncode(text);
   if(InpTgHtmlStyle) body += "&parse_mode=HTML";
   body += "&disable_web_page_preview=true";

   uchar post[];
   int len = StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8) - 1;   // bytes without trailing 0
   if(len < 0) len = 0;
   ArrayResize(post, len);

   uchar  result[];
   string rh;
   ResetLastError();
   int code = WebRequest("POST", url,
                         "Content-Type: application/x-www-form-urlencoded\r\n",
                         5000, post, result, rh);
   if(code == -1)
      Say("TG",StringFormat("send failed | err %d | allow https://api.telegram.org in Tools>Options>Expert Advisors", GetLastError()));
   else if(code != 200)
      Say("TG",StringFormat("HTTP %d | %s", code, CharArrayToString(result)));
}

// Telegram caps a message at 4096 chars - split on line breaks so a long
// end-of-day table arrives as several readable messages instead of failing.
void TelegramSend(const string text)
{
   if(!InpUseTelegram) return;
   string full = (InpTgPrefix=="" ? text : TgB(HtmlEsc(InpTgPrefix)) + "\n" + text);

   if(StringLen(full) <= 3800){ TelegramSendRaw(full); return; }

   string lines[];
   int n=StringSplit(full,'\n',lines);
   string chunk="";
   for(int i=0;i<n;i++)
   {
      if(StringLen(chunk)+StringLen(lines[i])+1 > 3800)
      { TelegramSendRaw(chunk); chunk=""; }
      chunk += (chunk==""?"":"\n") + lines[i];
   }
   if(chunk!="") TelegramSendRaw(chunk);
}

//====================================================================
//  ENTRY-SIGNAL MESSAGE  (same layout for live trading and signals-only)
//====================================================================
void SendEntrySignal(double slPrice)
{
   if(!InpTgNotifyEntry) return;
   SnapVals s; TakeSnapshot(s);

   string side = (g_dir==1) ? "BUY" : "SELL";
   string arrow= (g_dir==1) ? Emo(0x1F7E2) : Emo(0x1F534);   // green / red circle
   string tf   = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
   int    dg   = _Digits;

   string msg = arrow + " " + TgB(side + "  " + _Symbol + "  " + tf) + "\n";
   msg += (InpSignalsOnly ? "Signal only" : "Entry taken") + "  -  "
        + TgM(g_entryTag) + "  "
        + (InDaySessionIST(TimeCurrent())?"DAY":"EVENING") + " session\n";
   msg += "\n";

   // levels as an aligned monospace block
   string tbl = StringFormat("%-7s %s\n","Entry",DoubleToString(g_entry,dg))
              + StringFormat("%-7s %s\n","SL",   DoubleToString(slPrice,dg));
   for(int t=0;t<5;t++)
      tbl += StringFormat("%-7s %s\n","TP"+IntegerToString(t+1),DoubleToString(g_tpPrice[t],dg));
   if(!InpSignalsOnly && g_origVol>0)
      tbl += StringFormat("%-7s %.2f\n","Lots",g_origVol);
   msg += TgPre(tbl);

   msg += "\n" + TgB("Why") + "\n";
   msg += TgPre(StringFormat("EMA  %s / %s / %s\nADX  %.1f    RSI %.1f (M5 %.1f)\nMACD %s / %s\nATR  %s    VWAP %s\nVol  %.0f vs %.0f\nBias %.0f%% bull / %.0f%% bear\nSprd %d pts",
          DoubleToString(s.ema9,dg),DoubleToString(s.ema21,dg),DoubleToString(s.ema50,dg),
          s.adx, s.rsi, s.rsi5,
          DoubleToString(s.macdM,dg), DoubleToString(s.macdS,dg),
          DoubleToString(s.atr,dg), DoubleToString(s.vwap,dg),
          s.vol, s.volAvg, s.bull, s.bear, (int)s.spread));

   if(g_qfFlags!="" && g_qfFlags!="NA")
      msg += "\n" + TgM(HtmlEsc(g_qfFlags)) + "\n";

   msg += "\n" + (g_fullTgt ? "No partials - full size to TP5, SL steps up one level at a time\n"
                             : StringFormat("Booking %.0f%% at TP1-TP4\n",InpPartialPct));
   msg += TgM(TimeToString(TimeCurrent(),TIME_MINUTES) + " srv / "
            + IstClock(TimeCurrent()) + " IST");
   TelegramSend(msg);
}

//====================================================================
//  SIGNALS-ONLY VIRTUAL TRACKER
//  Follows the trade from PRICE alone (no position, no lots) and pushes
//  each TP reached + suggested SL move, then the SL/BE hit. Booking-agnostic.
//====================================================================
void MonitorVirtual()
{
   if(!g_virtActive) return;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double Rmult[5]={InpTP1_R,InpTP2_R,InpTP3_R,InpTP4_R,InpTP5_R};
   string tf   = StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period), 7);
   string side = (g_dir==1) ? "BUY" : "SELL";
   string head = _Symbol + "  " + tf;

   // --- TP progression (targets are ordered, so stop at the first not-yet-hit) ---
   for(int i=0;i<5;i++)
   {
      if(g_tpHit[i]) continue;
      bool hit=(g_dir==1)?(bid>=g_tpPrice[i]):(ask<=g_tpPrice[i]);
      if(!hit) break;
      g_tpHit[i]=true;
      string rtxt = "+" + DoubleToString(Rmult[i],1) + "R";
      string tpTag= "TP" + IntegerToString(i+1);

      if(i<4)
      {
         string slLine = "SL unchanged";
         if(InpTrailBehindTP)
         {
            g_virtSL = (i==0) ? g_entry : g_tpPrice[i-1];
            g_virtSL = NormalizeDouble(g_virtSL,_Digits);
            g_curSL  = g_virtSL;

            slLine = (i==0)
                   ? "Move SL -> Breakeven " + DoubleToString(g_virtSL,_Digits)
                   : "Move SL -> TP" + IntegerToString(i) + " " + DoubleToString(g_virtSL,_Digits);

            LogEvent("SL_MOVE",g_virtSL,0.0,0.0,Rmult[i],0.0,0.0,slLine);
         }

         LogEvent(tpTag+"_REACHED",g_tpPrice[i],0.0,0.0,Rmult[i],Rmult[i],0.0,
                  g_fullTgt?"full target: no partial":"scale-out mode: book slice here");

         if(InpTgNotifyTP)
            TelegramSend(Emo(0x2705) + " " + TgB(tpTag + " reached  " + rtxt) + "\n"
                       + head + "  " + side + "\n\n"
                       + TgPre(StringFormat("%-6s %s\n%-6s %s\n%-6s %s",
                               tpTag, DoubleToString(g_tpPrice[i],_Digits),
                               "Booked", (g_fullTgt ? "nothing - running to TP5"
                                                    : "book slice here"),
                               "Stop", slLine)));
      }
      else if(RunnerOn())
      {
         // mirror the live runner, so a signals-only instance and a trading
         // instance on the same symbol tell the same story
         if(InpTrailBehindTP)
         {
            g_virtSL = NormalizeDouble(g_tpPrice[3],_Digits);
            g_curSL  = g_virtSL;
            LogEvent("SL_MOVE",g_virtSL,0.0,0.0,Rmult[i],0.0,0.0,"stop trailed to TP4");
         }
         g_runLevel = 0;
         LogEvent("TP5_REACHED",g_tpPrice[i],0.0,0.0,Rmult[i],Rmult[i],0.0,
                  "runner: not closed at TP5, running until the opposite signal");
         if(InpTgNotifyTP)
            TelegramSend(Emo(0x1F680) + " " + TgB("TP5 reached - RUNNING ON  " + rtxt) + "\n"
                       + head + "  " + side + "\n\n"
                       + TgPre(StringFormat("%-6s %s\n%-6s %s\n%-6s %s",
                               "TP5", DoubleToString(g_tpPrice[i],_Digits),
                               "Booked", "nothing - running until the flip",
                               "Stop", "SL -> TP4 " + DoubleToString(g_virtSL,_Digits))));
      }
      else
      {
         LogEvent("TP5_EXIT",g_tpPrice[i],0.0,0.0,Rmult[i],Rmult[i],0.0,"signal complete at full target");
         if(InpTgNotifyTP)
            TelegramSend(Emo(0x1F3C1) + " " + TgB("TP5 REACHED - SIGNAL COMPLETE  " + rtxt) + "\n"
                       + head + "  " + side + "\n\n"
                       + TgVirtualClose(g_tpPrice[i]));
         g_virtActive=false;
         return;
      }
   }

   // --- virtual runner: the rungs above TP5 ---
   if(g_virtActive && RunnerOn() && g_tpHit[4] && InpRunnerStepR>0.0 && g_tpUnit>0.0)
   {
      for(int guard=0; guard<50; guard++)
      {
         int    k  = g_runLevel + 1;
         double px = RunnerRungPrice(k);
         bool   hit=(g_dir==1)?(bid>=px):(ask<=px);
         if(!hit) break;

         g_runLevel = k;
         double rr    = InpTP5_R + InpRunnerStepR*k;
         double newSL = (k==1) ? NormalizeDouble(g_tpPrice[4],_Digits) : RunnerRungPrice(k-1);
         LogEvent("TP"+IntegerToString((int)MathRound(rr))+"_REACHED",px,0.0,0.0,rr,rr,0.0,
                  StringFormat("runner rung %d above TP5",k));

         bool better = (g_dir==1) ? (newSL > g_virtSL) : (newSL < g_virtSL || g_virtSL==0.0);
         if(InpTrailBehindTP && better)
         {
            g_virtSL = newSL; g_curSL = newSL;
            string behind = (k==1) ? "TP5" : ("+" + DoubleToString(rr-InpRunnerStepR,1) + "R");
            LogEvent("SL_MOVE",newSL,0.0,0.0,rr,0.0,0.0,"runner: stop trailed to "+behind);
            if(InpTgNotifyTP)
               TelegramSend(Emo(0x1F680) + " " + TgB(StringFormat("Runner +%.1fR",rr)) + "\n"
                          + head + "  " + side + "\n\n"
                          + TgPre(StringFormat("%-6s %s\n%-6s %s",
                                  "Price", DoubleToString(px,_Digits),
                                  "Stop",  behind + " " + DoubleToString(newSL,_Digits))));
         }
      }
   }

   // --- SL / breakeven hit (uses the possibly-updated virtual stop) ---
   if(g_virtActive)
   {
      bool slHit=(g_dir==1)?(bid<=g_virtSL):(ask>=g_virtSL);
      if(slHit)
      {
         bool atBE    = (MathAbs(g_virtSL - g_entry) < _Point*2);
         bool atInit  = (MathAbs(g_virtSL - g_initSL) < _Point*2);
         string tag   = atBE ? "BREAKEVEN STOP HIT" : (atInit ? "SL HIT" : "TRAILED STOP HIT");
         string evt   = atBE ? "EXIT_BE"            : (atInit ? "EXIT_SL" : "EXIT_TRAIL_SL");

         LogEvent(evt,g_virtSL,0.0,0.0,0.0,RealizedR(g_virtSL),0.0,tag);
         if(InpTgNotifyClose)
            TelegramSend((atBE ? Emo(0x2796) + " " : Emo(0x274C) + " ") + TgB(tag) + "\n"
                       + head + "  " + side + "\n\n"
                       + TgVirtualClose(g_virtSL));
         g_virtActive=false;
      }
   }
}

//====================================================================
//  BIAS SCORE
//====================================================================
void BiasScores(double closePx,double vwap,double &bullPct,double &bearPct)
{
   double rsi=50,m=0,s=0,rsi5=50,adx=0;
   Val(hRsi,1,rsi);
   double macdMain,macdSig;
   if(Val2(hMacd,0,1,macdMain)&&Val2(hMacd,1,1,macdSig)){ m=macdMain; s=macdSig; }
   Val(hRsiM5,1,rsi5); Val(hAdx,1,adx);
   double e9; Val(hEma9,1,e9);
   double e21;Val(hEma21,1,e21);
   double volNow=(double)iVolume(_Symbol,_Period,1);
   double volAvg=VolumeSMA(InpVolAvgPeriod);
   double openPx=iOpen(_Symbol,_Period,1);

   double b=0;
   if(closePx>vwap) b+=1; if(rsi>50) b+=1; if(m>s) b+=1; if(e9>e21) b+=1;
   if(adx>25&&closePx>e9) b+=1; if(volNow>volAvg&&closePx>openPx) b+=1; if(rsi5>50) b+=1;
   bullPct=b/7.0*100.0;

   double r=0;
   if(closePx<vwap) r+=1; if(rsi<50) r+=1; if(m<s) r+=1; if(e9<e21) r+=1;
   if(adx>25&&closePx<e9) r+=1; if(volNow>volAvg&&closePx<openPx) r+=1; if(rsi5<50) r+=1;
   bearPct=r/7.0*100.0;
}

//====================================================================
//  VWAP / VOLUME HELPERS
//====================================================================
double SessionVWAP()
{
   datetime dayStart=DayStart(iTime(_Symbol,_Period,1));
   double pv=0,vv=0;
   for(int sh=1;sh<5000;sh++)
   {
      datetime t=iTime(_Symbol,_Period,sh);
      if(t<dayStart||t==0) break;
      double typ=(iHigh(_Symbol,_Period,sh)+iLow(_Symbol,_Period,sh)+iClose(_Symbol,_Period,sh))/3.0;
      double v=(double)iVolume(_Symbol,_Period,sh);
      pv+=typ*v; vv+=v;
   }
   return (vv>0)?pv/vv:iClose(_Symbol,_Period,1);
}

double VolumeSMA(int period)
{
   double sum=0; int n=0;
   for(int sh=1;sh<=period;sh++){ sum+=(double)iVolume(_Symbol,_Period,sh); n++; }
   return (n>0)?sum/n:0;
}

//====================================================================
//  MISC HELPERS
//====================================================================
bool Val(int handle,int shift,double &out)
{
   double buf[]; ArraySetAsSeries(buf,true);
   if(CopyBuffer(handle,0,shift,1,buf)<1) return false;
   out=buf[0]; return true;
}
bool Val2(int handle,int bufIdx,int shift,double &out)
{
   double buf[]; ArraySetAsSeries(buf,true);
   if(CopyBuffer(handle,bufIdx,shift,1,buf)<1) return false;
   out=buf[0]; return true;
}
// IST -> server, the inverse of ServerToIST
datetime ISTToServer(datetime tIst)
{
   long offSec=(long)MathRound(ServerGmtOffsetHours()*3600.0);
   return (datetime)((long)tIst + offSec - 19800);
}

// Start of the CURRENT trading day, honouring InpDayResetHour/Minute and the chosen clock.
// Prop firms rarely reset at server midnight, so this is what the daily cap measures from.
datetime TradingDayStart(datetime tServer)
{
   long t     = (long)(InpDayResetUseIST ? ServerToIST(tServer) : tServer);
   long reset = (long)InpDayResetHour*3600 + (long)InpDayResetMinute*60;
   long shift = t - reset;
   if(shift < 0) shift -= 86399;                       // floor toward the earlier day
   long start = (shift/86400)*86400 + reset;           // in the chosen clock
   return InpDayResetUseIST ? ISTToServer((datetime)start) : (datetime)start;
}

datetime DayStart(datetime t)
{
   MqlDateTime mt; TimeToStruct(t,mt); mt.hour=0; mt.min=0; mt.sec=0;
   return StructToTime(mt);
}
int BarsBetween(datetime a,datetime b)
{
   int s=PeriodSeconds(_Period); if(s<=0) return 0; return (int)((b-a)/s);
}
bool PositionOnSymbol()
{
   if(!PositionSelect(_Symbol)) return false;
   return (PositionGetInteger(POSITION_MAGIC)==InpMagic);
}
void ResetPosState()
{
   g_posId=0; g_dir=0; g_entry=0; g_risk=0; g_tpUnit=0; g_slFactor=1.0; g_origVol=0;
   g_initSL=0; g_curSL=0; g_fullTgt=false; g_entryTag=""; g_runLevel=0;
   g_mfe=0; g_mae=0; g_entryBar=0; g_excBar=0;
   g_virtActive=false; g_virtSL=0;
   for(int i=0;i<5;i++){ g_tpHit[i]=false; g_tpPrice[i]=0; }
}
//+------------------------------------------------------------------+
