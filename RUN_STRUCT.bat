@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_STRUCT.bat
REM
REM  13 sets x 2019-2026, FAST MODEL. 104 passes, ~3 hours.
REM
REM  WHY THESE THIRTEEN
REM  The v1.30 diagnostic says where every evaluation dies:
REM
REM      no HTF bias                79.5%%
REM      wrong side of equilibrium  18.6%%
REM      everything else combined    1.9%%
REM
REM  Those two gates ARE the strategy, and not one of the inputs behind
REM  them has ever been varied on a real-tick grid. Risk, targets,
REM  break-even and sessions have all been swept repeatedly; the two
REM  things doing 98%% of the selecting have not been touched.
REM
REM    bias gate   ST_tf_fast / _mid / _slow   the H1/H4/D1 triple itself
REM                ST_swing1 / _swing3         fractal strength
REM                ST_look80 / _look300        how far back swings count
REM    location    ST_range_h1 / _range_d1     the dealing-range timeframe
REM                ST_range15 / _range60       its length
REM                ST_nopd                     the PD filter OFF entirely
REM
REM  ST_nopd is the one to watch. It removes 18.6%% of all rejections in
REM  a single switch, and has never been run on real data.
REM
REM  MODEL=1 because 104 real-tick passes is 33 hours. This is a SCREEN:
REM  whatever beats ST_ctrl gets re-run on MODEL=4 before it counts.
REM
REM  Reports: srhtf-grid\results_^<year^>_M5_struct_m1\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1
set NOPAUSE=1
set MODEL=1
set OUTTAG=_struct

echo.
echo   Compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   13 structure sets x 8 years, fast model
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_struct SR_HTF_StopEntry_EA.ex5 M5 2019 2020 2021 2022 2023 2024 2025 2026 nostop

echo.
echo ==================================================================
echo   ST_ctrl is the baseline in every year. Read each set against it,
echo   and rank on the WORST year as always. Also read diag_^<set^>.csv:
echo   if "no HTF bias" has not moved, that set did not change the gate
echo   it was meant to change.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
