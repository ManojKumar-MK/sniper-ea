@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_V3.bat
REM
REM  35 sets for SR_HTF_StopEntry_EA v1.20, M5, fast model. ~60 min.
REM
REM  Baseline is V2_freq2_t100 - the best-balanced set of the v2 grid
REM  (37 trades, PF 1.99, 2.11%% equity DD, 100 USD daily target).
REM
REM  WHAT IS NEW HERE
REM  Every set has InpDiagCSV=true, so each pass also writes
REM  diag_<set>.csv listing WHY setups were rejected. That settles the
REM  v2 ambiguity: V3_q_ag1 and V3_q_m1 returned byte-identical trades
REM  in v2 with their inputs verifiably applied, which should not be
REM  possible - the tally says whether the branch was ever reached.
REM  READ THOSE TWO FIRST. If an input is a no-op the rest of the grid
REM  is built on sand.
REM
REM  Then three quality ideas, each from a measurement rather than a
REM  hunch:
REM    gate vs target  - InpMinRR did both jobs; 2R beat 3R on the SAME
REM                      trades, so the two are now separate inputs
REM    scale out/trail - turning BE off collapsed the win rate 63->23%%,
REM                      so the BE move is where the edge lives; these
REM                      sets build on it instead of around it
REM    direction       - shorts beat longs on every set so far. Tested,
REM                      not assumed
REM
REM  Reports + diagnostics: srhtf-grid\results_2026_M5_v3_m1\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_v3

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA v1.20
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.
  echo   Compile produced no .ex5 - stopping rather than running 35
  echo   passes against a build that does not exist.
  echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - 35 sets, fast model, with rejection diagnostics
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_v3 SR_HTF_StopEntry_EA.ex5 M5 2026 nostop

echo.
echo ==================================================================
echo   Reports: srhtf-grid\results_2026_M5_v3_m1\
echo     report_^<set^>.htm   the usual tester report
echo     diag_^<set^>.csv     why setups were rejected
echo.
echo   Commit the whole folder - the .csv files are the point of this
echo   grid as much as the .htm ones.
echo ==================================================================
set "NOPAUSE="
pause
