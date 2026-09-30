@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\  -  .\RUN_GRID.bat
REM
REM  SniperGrid - 25 sets x M5 x 4 years = 100 runs.
REM
REM  THE QUESTION THIS ANSWERS
REM  Every grid reviewed in this project failed the 6%% funded limit:
REM  eleven geraked EAs ran 18.9-64%% EQUITY drawdown, Gold Reaper showed
REM  1.38%% balance against 23%%+ equity. This EA's FUNDED mode refuses to
REM  start a basket whose worst case exceeds the budget, and flattens on
REM  a hard equity floor. Does that actually hold the line?
REM
REM  READ THE EQUITY DRAWDOWN COLUMN, not balance drawdown. On a grid
REM  they are different numbers and only one of them matters.
REM
REM  The G_free_* sets have no budget test and no equity floor. They are
REM  there to show what the guards cost - expect them to earn more and
REM  breach.
REM
REM  COMPILE FIRST (F7 or .\COMPILE.bat).
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1
set EXPERT=SniperGrid_v1.00.ex5

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  pause & exit /b 1
)

for %%Y in (2026 2025 2024 2023) do (
  echo.
  echo ===== %%Y  M5 =====
  python run_backtests.py --sets sets_grid --out results_grid_%%Y_M5 --period M5 ^
    --from %%Y.01.01 --to %%Y.12.31 --skip-done --deposit 25000 --symbol XAUUSD ^
    --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   1. G_fn_ctrl first, and its EQUITY drawdown. Under 6%% or not?
echo   2. Compare G_fn_ctrl against G_free_ctrl - the cost of the guards.
echo   3. Then 2024. Every grid and both of our own strategies lost there.
echo   4. A grid that is profitable in 3 years and breaches in the 4th has
echo      not passed. One breach ends a funded account permanently.
pause
