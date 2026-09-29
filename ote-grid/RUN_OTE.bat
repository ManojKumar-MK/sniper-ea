@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\  -  PowerShell will not run a script from
REM  the current directory otherwise:   .\RUN_OTE.bat
REM  In cmd.exe, or by double-clicking, the bare name works.
REM
REM  Fib OTE model - 25 sets x M15/M5 x 4 years = 200 backtests.
REM
REM  A different model from everything else in this repo: session
REM  impulse, then a pullback into the 0.618-0.79 retrace, entered in
REM  the direction of the leg. Structural stop, ONE fixed R target.
REM
REM  The ladder is OFF in every set (InpUseScaleOut=false). The Pine
REM  script has a single take-profit at an R multiple, and leaving the
REM  5-level ladder on would silently ignore it.
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
set EXPERT=SniperOTE_Fib_v1.00.ex5
set BASE=--skip-done --deposit 25000 --symbol XAUUSD ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  echo   Compile SniperOTE_Fib_v1.00.mq5 with F7 and copy it there first.
  echo.
  pause & exit /b 1
)

for %%Y in (2026 2025 2024 2023) do (
  for %%P in (M15 M5) do (
    echo.
    echo ===== %%Y  %%P =====
    python run_backtests.py --sets sets_ote --out results_ote_%%Y_%%P --period %%P ^
      --from %%Y.01.01 --to %%Y.12.31 %BASE%
  )
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   OTE_ctrl is the Pine script's own defaults. Read it first - if the
echo   model has nothing, no amount of zone tuning will supply it.
pause
