@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SQ.bat
REM
REM  SniperEntry v1.40 - 23 sets on M3 AND M5, 2026, fast model.
REM  46 passes, ~70 min.
REM
REM  WHAT v1.40 ADDS, AND WHY IT IS NOT JUST MORE FILTERS
REM  The EMA9/21 cross on its own has no edge: ~1,500 backtests put the
REM  median profit factor at 0.990, and every indicator filter added to
REM  it made things monotonically WORSE (none +581 -> all five +200).
REM  Three different things are being tried here:
REM
REM   HTF gate      asks about swing STRUCTURE on H1, not another
REM                 moving average. Same TFBias as SR_HTF, which
REM                 reached target in 6 of 8 real-tick years - the only
REM                 component in this repo with an out-of-sample record.
REM   Confluence    asks for a REASON the level matters: a liquidity
REM                 sweep, an unfilled FVG, or a 62-79%% OTE retrace.
REM   Chop filter   counts EMA crosses in the last 30 bars. "Choppy" is
REM                 a market that keeps crossing, and no threshold in
REM                 the old quality filter measures that.
REM
REM  EVERY SET HAS ITS OWN InpCsvPrefix. 33 sets once shared one and the
REM  EA logs overwrote each other.
REM
REM  Reports: sq-grid\results_2026_M3_sq_m1\  and  ..._M5_sq_m1\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_sq

echo.
echo   STEP 1 of 3 - compiling SniperEntry v1.40
echo ==================================================================
call COMPILE.bat SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SniperEntry_Strict_SessionFilter_Telegram_v1.30.ex5" (
  echo.
  echo   No .ex5 - stopping rather than running 46 passes against a
  echo   build that does not exist.
  echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 3 - 23 sets on M3
echo ==================================================================
call RUNSETS.bat sq-grid\sets_sq SniperEntry_Strict_SessionFilter_Telegram_v1.30.ex5 M3 2026 nostop

echo.
echo   STEP 3 of 3 - 23 sets on M5
echo ==================================================================
call RUNSETS.bat sq-grid\sets_sq SniperEntry_Strict_SessionFilter_Telegram_v1.30.ex5 M5 2026 nostop

echo.
echo ==================================================================
echo   Reports: sq-grid\results_2026_M3_sq_m1\ and ..._M5_sq_m1\
echo.
echo   READ IN THIS ORDER
echo     1. SQ_base. Every other set can only REMOVE trades from it, so
echo        if base is deeply negative the question is whether any gate
echo        removes the right ones - not whether the net is positive.
echo     2. The SIGNAL TALLY line in each pass's journal:
echo          crosses=N taken=N | htf=N conf=N chop=N quality=N ...
echo        A gate showing 0 rejections did NOTHING - treat its set as
echo        identical to base, not as evidence about the idea.
echo     3. Expectancy PER TRADE, not net. Each gate cuts trade count,
echo        so net can fall while the edge improves, or rise on nothing.
echo     4. M3 against M5 for the same set. Per-trade cost here is
echo        ~2.13 USD, so M3 pays it far more often. A gate that only
echo        works on M5 is probably paying for spread, not finding edge.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
