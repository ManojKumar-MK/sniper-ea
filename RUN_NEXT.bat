@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_NEXT.bat
REM
REM  ONE CLICK for everything outstanding. Start it, walk away.
REM  Total about five and a half hours.
REM
REM    STEP 1  FvgGold killzones, 28 sets, 6 months, fast model  ~35 min
REM    STEP 2  SR_HTF shortlist, 4 sets x 2023-2026, REAL TICKS  ~5 h
REM
REM  Cheap first on purpose: step 1 either finds a session edge or
REM  rules the idea out in half an hour, and it needs no decision from
REM  you either way. Step 2 is the one that actually settles whether
REM  V4_s1_part50 is tradeable, and it is worth the night.
REM
REM  Both steps SKIP any pass whose report already exists, so if this
REM  is interrupted - reboot, closed window, anything - just run it
REM  again and it picks up where it stopped. Nothing is redone.
REM
REM  Results land in:
REM    fvg-grid\results_2026H2_M15_kz_m1\
REM    srhtf-grid\results_2023_M5_final\  ... and 2024, 2025, 2026
REM
REM  Commit all of those when it finishes.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

REM  Suppresses the "press any key" at the end of each step, so the two
REM  run back to back. The only pause is at the bottom of this file.
set CHAINED=1

echo.
echo ###################################################################
echo #  STEP 1 of 2 - FvgGold killzones, 28 sets, 6 months   ~35 min
echo ###################################################################
call RUN_FVG_KZ.bat "%MT5DIR%"

echo.
echo ###################################################################
echo #  STEP 2 of 2 - SR_HTF shortlist, real ticks, 4 years  ~5 hours
echo ###################################################################
call RUN_SRHTF_FINAL.bat "%MT5DIR%"

echo.
echo ===================================================================
echo   BOTH DONE. Commit the results:
echo.
echo     git add fvg-grid/results_2026H2_M15_kz_m1
echo     git add srhtf-grid/results_2023_M5_final
echo     git add srhtf-grid/results_2024_M5_final
echo     git add srhtf-grid/results_2025_M5_final
echo     git add srhtf-grid/results_2026_M5_final
echo     git commit -m "fvg killzones + srhtf real-tick finals"
echo     git push
echo.
echo   Or just:   git add -A ^&^& git commit -m results ^&^& git push
echo ===================================================================
set "CHAINED="
pause
