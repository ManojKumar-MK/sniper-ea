@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\  -  PowerShell will not run a script from
REM  the current directory otherwise:   .\RUN_GMP.bat
REM  In cmd.exe, or by double-clicking, the bare name works.
REM
REM  GridMaster Pro — bi-directional ATR grid
REM  4 years x M15. No backtest exists upstream - this makes one.
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
set EXPERT=GridMaster Pro.ex5
set BASE=--skip-done --deposit 25000 --symbol XAUUSD ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  pause & exit /b 1
)

for %%Y in (2026 2025 2024 2023) do (
  echo.
  echo ===== %%Y  M15 =====
  python run_backtests.py --sets sets_gmp --out results_gmp_%%Y_M15 --period M15 ^
    --from %%Y.01.01 --to %%Y.12.31 %BASE%
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   Read _ctrl first, then 2025. And read EQUITY drawdown, not balance
echo   drawdown - the gap between them is where a funded account dies.
pause
