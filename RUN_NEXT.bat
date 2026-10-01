@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_NEXT.bat
REM
REM  ONE CLICK for everything outstanding. Start it, walk away.
REM  Total about two hours.
REM
REM    STEP 1  FvgGold killzones, 28 sets, 6 months, fast model  ~35 min
REM    STEP 2  SR_HTF shortlist, 4 sets x 2026, REAL TICKS       ~1.3 h
REM
REM  Cheap first on purpose: step 1 either finds a session edge or
REM  rules the idea out in half an hour, and it needs no decision from
REM  you either way. Step 2 asks whether V4_s1_part50's scale-out
REM  survives real fills - 2026 only, which is the year it was chosen
REM  on, so it tests the FILL MODEL and not out-of-sample survival.
REM  2023-2025 is a separate ~3.7 hours whenever you want it:
REM     set MODEL=4 & set OUTTAG=_final
REM     .\RUNSETS.bat srhtf-grid\sets_srhtf_final SR_HTF_StopEntry_EA.ex5 M5 2023 2024 2025 nostop
REM
REM  Both steps SKIP any pass whose report already exists, so if this
REM  is interrupted - reboot, closed window, anything - just run it
REM  again and it picks up where it stopped. Nothing is redone.
REM
REM  Results land in:
REM    fvg-grid\results_2026H2_M15_kz_m1\
REM    srhtf-grid\results_2026_M5_final\
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
echo #  STEP 2 of 2 - SR_HTF shortlist, real ticks, 2026     ~1.3 hours
echo ###################################################################
call RUN_SRHTF_FINAL.bat "%MT5DIR%"

echo.
echo ===================================================================
echo   BOTH DONE. Commit the results:
echo.
echo     git add fvg-grid/results_2026H2_M15_kz_m1
echo     git add srhtf-grid/results_2026_M5_final
echo     git commit -m "fvg killzones + srhtf real-tick finals"
echo     git push
echo.
echo   Or just:   git add -A ^&^& git commit -m results ^&^& git push
echo ===================================================================
set "CHAINED="
pause
