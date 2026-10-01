@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_V4.bat
REM
REM  41 sets, M5, fast model. ~70 min.
REM
REM  THE FIRST GRID THAT ACTUALLY TESTS THE STRATEGY. v1-v3 ran with
REM  InpTF1/2/3, InpRangeTF and InpEntryTF all collapsed to the chart
REM  timeframe, because a .set stores enums as integers and those files
REM  used names. Those three grids are void.
REM
REM  WHAT THE PROBE FOUND, AND WHY THIS GRID LOOKS LIKE IT DOES
REM  With the real H1/H4/D1 bias, the diagnostic says 79.5%% of all
REM  evaluations are rejected as "no HTF bias" and 18.6%% as "wrong side
REM  of equilibrium". Those two are 98%% of everything. Nothing else in
REM  the EA is worth tuning until they are understood, so most of this
REM  grid aims at exactly those two gates.
REM
REM  Reports + diagnostics: srhtf-grid\results_2026_M5_v4_m1\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_v4

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA v1.30
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - 41 sets
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_v4 SR_HTF_StopEntry_EA.ex5 M5 2026 nostop

echo.
echo ==================================================================
echo   Reports: srhtf-grid\results_2026_M5_v4_m1\
echo.
echo   READ IN THIS ORDER
echo     1. diag_V4_base.csv - confirm InpTF1 says PERIOD_H1 / 16385.
echo        If any set says PERIOD_CURRENT the EA refused to run it and
echo        there will be no report for that set at all.
echo     2. Trade COUNT first. V4_base took 6 trades in nine months and
echo        lost money. Any set still under ~30 trades has said nothing,
echo        whatever its net.
echo     3. The bias block - V4_ag1/ag2 and the V4_tf_* sets. 79.5%% of
echo        rejections were "no HTF bias", so if nothing here raises the
echo        trade count the model is simply too rare to trade.
echo     4. Only then expectancy per trade, then equity drawdown.
echo.
echo   Commit the whole folder - the .csv files matter as much as the
echo   .htm ones.
echo ==================================================================
set "NOPAUSE="
pause
