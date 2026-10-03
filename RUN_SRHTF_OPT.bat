@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_OPT.bat
REM
REM  THE COMBINATION SEARCH. 1,244,160 combinations, genetic, across
REM  2019.01.01 - 2026.09.30, with the last THIRD held out.
REM  Uses every CPU core the VPS has. Expect 1-4 hours.
REM
REM  WHY THIS AND NOT MORE HAND-WRITTEN SETS
REM  We have been testing 20-40 combinations at a time, by hand. The
REM  tester has had an optimiser the whole time. Ten parameters at the
REM  ranges below is 1.24 MILLION combinations - complete enumeration
REM  would take about 31,000 hours, so the genetic algorithm does it in
REM  a few thousand passes instead.
REM
REM  WHAT MAKES THIS DIFFERENT FROM NOISE MINING
REM  Three things, and all three are required:
REM
REM  1. CRITERION=6 - the EA's own OnTester(), new in v1.50. MT5's
REM     built-in criteria rank on profit, Sharpe or drawdown, and none
REM     of them know what a blown challenge is. "Max balance" would
REM     happily hand back a set that dies in one year and recovers in
REM     another. OnTester scores it the way the account does:
REM         floor hit      -1000   nothing recovers from this
REM         no trades      -2000   worse than losing - it was not tested
REM         target reached +1000, and sooner is better
REM         neither        the return in %%
REM
REM  2. FORWARD=2 - the last third of the window is held out, and the
REM     tester optimises ONLY on the first two thirds. With 1.24M
REM     combinations the best in-sample result is almost certainly the
REM     luckiest one, not the best one. The Forward column is the only
REM     number worth reading.
REM
REM  3. MODEL=1 - a search this size cannot run on real ticks. The
REM     survivors MUST then be re-run on MODEL=4 before they mean
REM     anything.
REM
REM  HOW TO READ IT, AND THIS MATTERS MORE THAN THE RUN
REM  In the tester's Optimization Results tab, switch to the FORWARD
REM  results and sort by Custom descending. Then:
REM    - ignore anything whose Back result is huge and Forward is not.
REM      That is the shape of a curve fit.
REM    - take combinations that appear in a CLUSTER - neighbours with
REM      similar parameters and similar scores. One isolated spike is
REM      what V3_ema_50_100 looked like, and it failed out of sample.
REM    - then re-run the top 4-6 on real ticks over 2019-2026 one year
REM      at a time, and judge on the WORST year.
REM
REM  Expect false positives by construction: searching 1.24M
REM  combinations will produce impressive in-sample numbers from pure
REM  chance. That is not a reason to skip the search - it is the reason
REM  the forward split and the real-tick re-run are not optional.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OPTIMIZE=2
set CRITERION=6
set FORWARD=2
set OUTTAG=_opt
set FROMDATE=2019.01.01
set TODATE=2026.09.30
set PERIODTAG=OPT8Y

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA v1.50 (adds OnTester)
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - genetic search, 1.24M combinations, forward 1/3
echo ==================================================================
echo   This uses every core. The terminal will look busy for hours -
echo   that is the optimiser working, not a hang.
echo.
call RUNSETS.bat srhtf-grid\sets_srhtf_opt SR_HTF_StopEntry_EA.ex5 M5 %PERIODTAG% nostop

echo.
echo ==================================================================
echo   Open the Strategy Tester, Optimization Results tab, switch to
echo   FORWARD, sort by Custom descending.
echo.
echo   Custom score:  +1000 and up = target reached (higher = sooner)
echo                  -1000        = static floor hit, account dead
echo                  -2000        = took no trades at all
echo.
echo   Export the table (right-click the results grid) and commit it,
echo   then the top handful get a real-tick run year by year.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
