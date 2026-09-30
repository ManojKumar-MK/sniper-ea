@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_FAST.bat
REM
REM  The same 36 sets as RUN_SRHTF.bat, but Model=1 (1-minute OHLC)
REM  instead of Model=4 (real ticks). Roughly 10-15x faster: about an
REM  hour for all 36 instead of about eleven.
REM
REM  THIS IS A SCREEN, NOT A RESULT. 1-minute OHLC fills a stop order
REM  at a price the market may never have traded at, and this EA lives
REM  or dies on stop-entry fills, so its numbers are optimistic. Use it
REM  to throw out the obvious failures cheaply, then re-run whatever
REM  survives on real ticks with RUN_SRHTF.bat.
REM
REM  Reports go to results_2026_M5_m1, a DIFFERENT folder from the
REM  real-tick results_2026_M5, so the two can never be mixed in one
REM  comparison table.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.
  echo   Compile produced no .ex5 - stopping rather than running 36
  echo   passes against a build that does not exist.
  echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - 36 sets, fast model
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf SR_HTF_StopEntry_EA.ex5 M5 2026 nostop

echo.
echo ==================================================================
echo   Reports: srhtf-grid\results_2026_M5_m1\
echo.
echo   READ THESE AS A SHORTLIST, NOT AS RESULTS.
echo     - Throw out anything with an equity drawdown over
echo       InpMaxGuardPct, or under ~30 trades in the year.
echo     - Of what is left, take the best few and run them on real
echo       ticks. A set that looks good here and bad there was never
echo       good - the difference is stop-entry fills that 1-minute
echo       OHLC grants and the real tape does not.
echo ==================================================================
set "NOPAUSE="
pause
