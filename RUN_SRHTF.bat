@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF.bat
REM
REM  SINGLE CLICK for SR_HTF_StopEntry_EA:
REM      1. compile it
REM      2. prove the harness on ONE set
REM      3. run all 36 sets over ONE year
REM
REM  36 sets x M5 x 2026 = 36 runs. No python anywhere.
REM
REM  Change the year at the bottom if you want a different one. Four
REM  years is .\RUN_SRHTF_4Y.bat - worth doing once a set looks good,
REM  because every strategy tested here looked fine on 2026 and several
REM  did not survive 2023-2025.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

REM  One click means one click: the steps below are chained, so suppress the
REM  "press any key" at the end of COMPILE and each RUNSETS pass. The final
REM  pause at the bottom of THIS file is the only one.
set NOPAUSE=1

echo.
echo   STEP 1 of 3 - compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.
  echo   Compile produced no .ex5 - stopping here rather than running 36
  echo   passes against a build that does not exist.
  echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 3 - one set, to prove the harness before 36 passes
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf\SR_ctrl.set SR_HTF_StopEntry_EA.ex5 M5 2026
if not exist "srhtf-grid\results_2026_M5\report_SR_ctrl.htm" (
  echo.
  echo   The single test produced no report, so the other 35 would not
  echo   either. The cause is printed above - fix that first.
  echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 3 of 3 - the remaining 35 sets
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf SR_HTF_StopEntry_EA.ex5 M5 2026 nostop

echo.
echo ==================================================================
echo   Reports: srhtf-grid\results_2026_M5\
echo.
echo   READ IN THIS ORDER
echo     1. SR_ctrl - your own defaults. Everything else is measured
echo        against it, and if it has no edge nothing downstream adds one.
echo     2. SR_agree1 and SR_agree2 against SR_ctrl. InpMinAgree=3 is the
echo        A+ premise; if 1 or 2 does as well, the premise is not doing
echo        the work it is credited with.
echo     3. EQUITY drawdown against InpMaxGuardPct, not balance drawdown.
echo     4. Trade count. Under ~30 in a year a set has said nothing,
echo        whatever its net - and InpMaxTradesDay is 2, so expect few.
echo.
echo   Then commit srhtf-grid\results_2026_M5 and the reports can be
echo   parsed into a comparison table.
echo ==================================================================
set "NOPAUSE="
pause
