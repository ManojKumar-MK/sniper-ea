@echo off
setlocal
REM ===================================================================
REM  FvgGold — FVG + Order Block, M15
REM  4 years x M15. Generating the evidence that does not exist.
REM
REM  Neither of these EAs ships a backtest. That is not a reason to
REM  discard them - it is a reason to run one. This is that run.
REM
REM  COMPILE FIRST (F7) and CLOSE the tester terminal before running.
REM ===================================================================

cd /d "%~dp0"
set MT5DIR=C:\MetaTrade-Live
set EXPERT=FvgGold.ex5
set BASE=--skip-done --deposit 25000 --symbol XAUUSD ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  pause & exit /b 1
)

for %%Y in (2026 2025 2024 2023) do (
  echo.
  echo ===== %%Y  M15 =====
  python run_backtests.py --sets sets_fvg --out results_fvg_%%Y_M15 --period M15 ^
    --from %%Y.01.01 --to %%Y.12.31 %BASE%
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   Read the CONTROL first - it is the author's own defaults. If that has
echo   no edge across four years, nothing downstream of it will supply one.
echo   Then check 2025: it is the year that broke SniperTurtle on M5 and where
echo   0 of 128 filter combinations made money.
pause
