@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_ALL.bat
REM
REM  EVERYTHING OUTSTANDING ON GOLD, one click. About 13-17 hours.
REM  Start it and leave it - overnight plus a morning.
REM
REM    1  BE variants       10 passes  ~3 h    REAL TICKS
REM    2  structure screen 104 passes  ~3 h    fast model
REM    3  COMBO2 genetic    92,160 combos ~2-6 h
REM    4  full-year rate    16 passes  ~5 h    REAL TICKS
REM
REM  ORDERED BY WHAT THE ANSWER IS WORTH, not by cost.
REM
REM  1 is the one that matters. It is the only hypothesis left that
REM  came from SR_HTF's OWN failures rather than from another model -
REM  and transferred ideas have now failed three times out of three
REM  (Asian sweep 6/8 -^> 0/8, drop-London 6/8 -^> 5/8, scale-out blew
REM  2 of 4 years). 2019 and 2022 both died with a ~50%% win rate while
REM  average WINS collapsed to 17 and 13 dollars against 120-dollar
REM  losses. That is break-even at 1R cutting winners to nothing, and
REM  step 1 tests five ways of loosening it on those two years only.
REM
REM  2 attacks the two gates that reject 98%% of all evaluations - no
REM  HTF bias at 79.5%%, wrong side of equilibrium at 18.6%% - whose
REM  inputs have never been varied on a real-tick grid. Everything
REM  swept so far has been the other 1.9%%.
REM
REM  3 searches the detection and execution numbers the first genetic
REM  run did not touch.
REM
REM  4 measures what a FULL year earns. Every +2500 in the results so
REM  far is InpTargetLock halting at +10%% - 2024 was over in March - so
REM  the annual rate has never actually been measured.
REM
REM  ALL FOUR ARE RESUMABLE. A pass whose report already exists is
REM  skipped, so a reboot or a closed window costs nothing: run this
REM  again and it continues where it stopped.
REM
REM  CAVEAT ON STEP 3: an MT5 optimisation writes to the tester's own
REM  Optimization Results tab, NOT to files. When it finishes you must
REM  export it by hand - right-click the grid, Export - or those hours
REM  leave no record. That already happened once with the first combo
REM  run.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

REM  Suppresses the per-step "press any key" so the four run back to
REM  back. The only pause is at the bottom of this file.
set CHAINED=1

echo.
echo ###################################################################
echo #  STEP 1 of 4 - break-even variants, 2019 + 2022    ~3 h
echo #  REAL TICKS. The one that could turn 6/8 into 8/8.
echo ###################################################################
call RUN_SRHTF_BE.bat "%MT5DIR%"

echo.
echo ###################################################################
echo #  STEP 2 of 4 - structure screen, 13 sets x 8 years ~3 h
echo #  The gates that do 98%% of the selecting.
echo ###################################################################
call RUN_STRUCT.bat "%MT5DIR%"

echo.
echo ###################################################################
echo #  STEP 3 of 4 - COMBO2 genetic, 92,160 combinations ~2-6 h
echo #  EXPORT THE RESULTS TAB BY HAND WHEN THIS FINISHES.
echo ###################################################################
call RUN_COMBO2.bat "%MT5DIR%"

echo.
echo ###################################################################
echo #  STEP 4 of 4 - full-year rate, no target lock      ~5 h
echo ###################################################################
call RUN_SRHTF_RATE.bat "%MT5DIR%"

echo.
echo ===================================================================
echo   ALL DONE. Commit everything:
echo       git add -A ^&^& git commit -m "BE + struct + combo2 + rate" ^&^& git push
echo.
echo   WHAT TO LOOK AT FIRST
echo     STEP 1: BE_base MUST come back near -1500 in BOTH 2019 and
echo       2022. It is the control - if it does not, the harness
echo       changed and nothing else is comparable. Then: only a variant
echo       that rescues BOTH dead years is worth re-checking the other
echo       six against.
echo     STEP 2: read diag_^<set^>.csv as well as the net. If "no HTF
echo       bias" has not moved, that set did not change the gate it was
echo       built to change - which is how two earlier grids wasted
echo       themselves.
echo     STEP 3: Optimization Results -^> FORWARD -^> sort by Custom.
echo       Take a CLUSTER, never an isolated spike. Then real ticks.
echo     STEP 4: average the eight years, divide by 25,000. That is the
echo       real annual rate R, and capital for 100 USD a day = 25,200/R.
echo ===================================================================
set "CHAINED="
pause
