@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_COMBO2.bat
REM
REM  92,160 combinations, genetic, 2025.01-2026.09, forward third held
REM  out. 2-6 hours.
REM
REM  WHAT THE FIRST COMBO GRID MISSED
REM  RUN_COMBO swept targets, risk and break-even - what to DO with a
REM  setup once found. It did not touch a single input that decides
REM  WHICH setups are found. This one sweeps exactly those:
REM
REM      InpSwingStrength    1-4      fractal strength for TFBias
REM      InpSwingLookback    50-300   how far back swings count
REM      InpRangeBars        15-75    dealing-range length
REM      InpSweepLookback    10-40    bars forming the liquidity pool
REM      InpSweepWindow      6-24     how recent the sweep must be
REM      InpEntryBufPts      5-45     stop order distance beyond structure
REM      InpSLBufPts         10-70    stop distance beyond the sweep
REM      InpOrderExpiryBars  3-15     pending order life
REM
REM  The first four move the two gates that reject 98%% of evaluations.
REM  The last four are pure execution on a stop-entry model, where the
REM  buffer decides whether a setup fills at all.
REM
REM  Same three disciplines as before, and all three are required:
REM    CRITERION=6  the EA's OnTester - scores a blown account at -1000
REM                 and a reached target at +1000, which no built-in does
REM    FORWARD=2    last third held out; with 92k combinations the best
REM                 in-sample row is the luckiest, not the best
REM    MODEL=1      a search cannot run on real ticks. Survivors must.
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
set OUTTAG=_combo2
set FROMDATE=2025.01.01
set TODATE=2026.09.30
set PERIODTAG=COMBO2

echo.
echo   Compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   genetic search over the DETECTION and EXECUTION numbers
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_combo2 SR_HTF_StopEntry_EA.ex5 M5 %PERIODTAG% nostop

echo.
echo ==================================================================
echo   Optimization Results tab -^> FORWARD -^> sort by Custom.
echo   Take a CLUSTER, not a spike. Then real ticks, year by year,
echo   judged on the worst year. The bar is 6 of 8.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
