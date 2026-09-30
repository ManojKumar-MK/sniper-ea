@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_V2.bat
REM
REM  44 sets for SR_HTF_StopEntry_EA v1.10, M5, fast model.
REM  ~1.7 min a pass, so about 75 minutes for the lot.
REM
REM  WHAT THIS GRID IS FOR
REM  The 2026 screen found the EA takes 5 trades in nine months, and
REM  that the cause is InpTargetLiquidity discarding any setup whose
REM  HTF target is nearer than InpMinRR. v1.10 adds InpTPFallback so
REM  the setup is taken at a fixed target instead of thrown away, and
REM  InpMaxOppose so InpMinAgree finally means something. This grid
REM  measures whether the extra trades carry an edge or only volume.
REM
REM  A daily $100 needs BOTH frequency and size, so the stacks come in
REM  three layers: V2_freq1..4 add frequency, _r1/_r15/_r2 add size,
REM  and _t50/_t100/_t200 add the daily-target rule on top.
REM
REM  Reports: srhtf-grid\results_2026_M5_v2_m1\  (OUTTAG keeps these
REM  apart from the v1 grid, which shares the same grid folder).
REM
REM  Real ticks afterwards: set MODEL=4 and rerun the survivors only.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_v2

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA v1.10
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.
  echo   Compile produced no .ex5 - stopping rather than running 44
  echo   passes against a build that does not exist.
  echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - 44 sets, fast model
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_v2 SR_HTF_StopEntry_EA.ex5 M5 2026 nostop

echo.
echo ==================================================================
echo   Reports: srhtf-grid\results_2026_M5_v2_m1\
echo.
echo   READ IN THIS ORDER
echo     1. V2_nofb vs V2_base. nofb is the old 5-trade control. If
echo        base does not trade MORE, InpTPFallback did not take and
echo        nothing else in this grid means anything.
echo     2. V2_ag1 / V2_ag2 vs V2_opp1_ag1 / V2_opp1_ag2. The first
echo        pair should still be inert - that is the dn==0 finding
echo        reproducing. The second pair is the real A+ test.
echo     3. Expectancy PER TRADE, not net. Every set here trades more
echo        than the last grid, so net rises on volume alone.
echo     4. EQUITY drawdown against InpMaxGuardPct. The _r15 and _r2
echo        sets exist to find where size breaks the 6%% rule, and they
echo        are expected to break it - that is the measurement.
echo     5. Only then the _t100 sets. A daily target cannot create an
echo        edge, it can only stop a good day early, so compare each
echo        _t100 against the same stack without it.
echo ==================================================================
set "NOPAUSE="
pause
