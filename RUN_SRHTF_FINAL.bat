@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_FINAL.bat
REM
REM  THE DECISIVE TEST. 4 sets x 4 years on REAL TICKS.
REM  16 passes x ~19 min = about 5 hours. Start it and leave it.
REM
REM  Everything before this was Model=1 (1-minute OHLC), which fills a
REM  stop order anywhere inside the bar - including at prices the tape
REM  never printed. This EA is entirely stop-entry, and the leading
REM  candidate also scales out and trails, which is the behaviour MOST
REM  sensitive to that assumption. So Model=1 cannot settle it.
REM
REM  THE SHORTLIST, and why each is here
REM    V4_s1_part50  the only set in the v4 grid with >=30 trades, a
REM                  profit, and equity drawdown inside the 6% rule.
REM                  70 trades, +1737, 2.47% DD, 80% wins.
REM    V4_s1         the SAME set without the scale-out. 39 trades,
REM                  +2126, but 9.15% DD - it breaches. This is the
REM                  control that shows the partial is what fixed the
REM                  drawdown rather than luck.
REM    V4_ag2_opp1   best $/trade (72.41) from a different bias config.
REM    V4_s1_r025    half the risk, to separate edge from sizing.
REM
REM  2023-2025 is the point. Every strategy in this repo has looked
REM  fine on one year and failed out of sample.
REM
REM  Reports: srhtf-grid\results_<year>_M5_final\  (no _m1 - real ticks)
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=4
set OUTTAG=_final

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA v1.30
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - 4 sets x 2023 2024 2025 2026, real ticks
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_final SR_HTF_StopEntry_EA.ex5 M5 2023 2024 2025 2026 nostop

echo.
echo ==================================================================
echo   Reports: srhtf-grid\results_^<year^>_M5_final\
echo.
echo   HOW TO JUDGE IT
echo     Rank on the WORST of the four years, not the average. A set
echo     that is positive in three years and loses 8%% in the fourth is
echo     not tradeable on a 6%% account - it is already dead.
echo.
echo     V4_s1_part50 needs to survive 2023-2025 at under 6%% equity
echo     drawdown. If it does, it is worth real ticks on more sets and
echo     then a demo. If it does not, the strategy is finished and the
echo     honest answer is that nothing here reached 100 USD a day.
echo.
echo   Commit all four results folders.
echo ==================================================================
set "NOPAUSE="
REM  CHAINED is set by RUN_NEXT.bat, which runs these back to back - a bare
REM  pause here would stop the chain waiting for a keypress.
if not defined CHAINED pause
