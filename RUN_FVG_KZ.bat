@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_FVG_KZ.bat
REM
REM  FvgGold-EA, 28 killzone sets, SIX MONTHS of XAUUSD (2026.04.01 to
REM  2026.09.30), M15, fast model. ~35 min.
REM
REM  Real ticks afterwards on the survivors:  set MODEL=4  and rerun.
REM
REM  THREE THINGS ABOUT THIS EA THAT SHAPE THE SETS
REM
REM  1. DailyLossLimit is in DOLLARS, not percent. The vendor default of
REM     5.0 means five dollars - on a 25k account that halts the EA
REM     after almost any losing trade. Every set here uses 300.
REM
REM  2. KZ_OverlapEnd does NOTHING in the default mode. In
REM     IsKillzoneActive, nySession is (hour >= KZ_OverlapStart && hour
REM     < KZ_NYEnd), which already contains the overlap window, so the
REM     live window is London u [OverlapStart, NYEnd). OverlapEnd only
REM     bites when KZ_PreferOverlap=true - which is why every
REM     FKZ_ovl_* set sets that flag.
REM
REM  3. IsKillzoneActive reads TimeGMT(). In the Strategy Tester that is
REM     derived from the HOST machine's timezone, and the EA has no
REM     GMT-offset input, so the real hours are not knowable from the
REM     code. The windows are therefore SWEPT, including whole +2 and
REM     +3 shifts (FKZ_both_sh2, FKZ_both_sh3). If a shifted set wins,
REM     the clock is the reason - not the session.
REM
REM  Reports: fvg-grid\results_2026H2_M15_kz_m1\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_kz
set FROMDATE=2026.04.01
set TODATE=2026.09.30
set PERIODTAG=2026H2

echo.
echo   STEP 1 of 2 - compiling FvgGold
echo ==================================================================
call COMPILE.bat FvgGold.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\FvgGold.ex5" (
  echo.
  echo   FvgGold.ex5 was not produced - stopping rather than running 28
  echo   passes against a build that does not exist.
  echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - 28 killzone sets, 6 months
echo ==================================================================
call RUNSETS.bat fvg-grid\sets_fvg_kz FvgGold.ex5 M15 %PERIODTAG% nostop

echo.
echo ==================================================================
echo   Reports: fvg-grid\results_2026H2_M15_kz_m1\
echo.
echo   READ IN THIS ORDER
echo     1. FKZ_nokz - no session filter at all. If no windowed set
echo        beats it, the killzone idea is worth nothing on this EA and
echo        the rest of the table is noise.
echo     2. Trade COUNT. Six months at M15 is a small sample before you
echo        even cut it to three hours a day. Under ~30 trades a set
echo        has said nothing, whatever its net.
echo     3. FKZ_both_sh2 / FKZ_both_sh3 against FKZ_ctrl. If a shifted
echo        window wins, you are looking at the VPS clock, not a
echo        session edge, and the hours need fixing before anything
echo        else is believed.
echo     4. Expectancy per trade, then equity drawdown. Six months is
echo        half a sample - treat ANY winner here as a candidate for
echo        real ticks and 2023-2025, never as a result.
echo ==================================================================
set "NOPAUSE="
pause
