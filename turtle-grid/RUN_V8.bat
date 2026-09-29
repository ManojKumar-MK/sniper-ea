@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\  -  PowerShell will not run a script from
REM  the current directory otherwise:   .\RUN_V8.bat
REM  In cmd.exe, or by double-clicking, the bare name works.
REM
REM  v8 - the new session windows, crossed with everything.
REM       120 sets x M15/M5 x 2 years (2025, 2026) = 480 backtests.
REM
REM  The windows were given in IST. The EA defines killzones on the NY
REM  clock, and IST-fixed hours land on DIFFERENT NY hours in summer
REM  and winter, so BOTH readings are in the grid and the data decides:
REM
REM    prefix WS..  IST -> NY, US summer   A 2000-2400  L 0300-0500  N 0800-1000
REM    prefix WW..  IST -> NY, US winter   A 1900-2300  L 0200-0400  N 0700-0900
REM    prefix WO..  what was configured    A 1900-2400  L 0200-0500  N 0700-1000
REM
REM  crossed with lead 0 or 60, four killzone combinations (AN / ALN /
REM  A / N) and the five strongest filter sets from v7.
REM
REM  NAME FORMAT:  W<session><lead>_<killzones>_<filters>
REM     e.g. WS60_AN_VC = summer windows, 60-min lead, Asia+NY,
REM                       VWAP + cooldown filters
REM
REM  COMPILE FIRST (F7) and CLOSE the tester terminal before running.
REM ===================================================================

cd /d "%~dp0"

REM  ---------------------------------------------------------------
REM  Clear PYTHONHOME / PYTHONPATH for this window only.
REM  A stale PYTHONHOME makes python.exe start and then die with
REM      Could not find platform independent libraries <prefix>
REM      ModuleNotFoundError: No module named 'encodings'
REM  because it looks for its standard library where that variable
REM  points instead of beside the exe. Clearing them here affects only
REM  this script's environment, never the system.
REM  ---------------------------------------------------------------
set "PYTHONHOME="
set "PYTHONPATH="
set MT5DIR=C:\MT5-Tester
set EXPERT=SniperTurtle_KZ_v1.00.ex5
set BASE=--skip-done --deposit 25000 --symbol XAUUSD ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  pause & exit /b 1
)

for %%Y in (2026 2025) do (
  for %%P in (M15 M5) do (
    echo.
    echo ===== %%Y  %%P =====
    python run_backtests.py --sets sets_v8 --out results_v8_%%Y_%%P --period %%P ^
      --from %%Y.01.01 --to %%Y.12.31 %BASE%
  )
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   FIRST question: do WS, WW and WO differ at all? If the three session
echo   readings give the same numbers, the hour does not matter and the
echo   timezone ambiguity was never worth resolving.
echo.
echo   Two years only, and BOTH were used to select everything upstream -
echo   so this grid can rank the windows against each other, but it cannot
echo   tell you whether any of them will hold up next year.
pause
