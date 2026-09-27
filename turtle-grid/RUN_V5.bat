@echo off
setlocal
REM ===================================================================
REM  v5 - validation, not search. 7 sets x 3 timeframes x 2 new years.
REM
REM  The four configs that were net-positive in BOTH 2026 and 2025, put
REM  in front of 2024 and 2023 - years none of them were selected on.
REM  Plus V5_ctrl_trail_on, which is V5_notrail WITH the trail, so the
REM  one thing being claimed is measured rather than assumed.
REM
REM  Deliberately small. A big grid here would be another selection
REM  pass wearing a validation costume: search once, then validate.
REM
REM  HISTORY: 2023-2024 M3 is a lot of ticks. Open an XAUUSD M3 chart in
REM  the tester terminal and scroll back past Jan 2023 BEFORE running,
REM  or the runs finish thin and it looks like the strategy failed.
REM ===================================================================

cd /d "%~dp0"
set MT5DIR=C:\MT5-Tester
set EXPERT=SniperTurtle_KZ_v1.00.ex5
set BASE=--skip-done --deposit 25000 --symbol XAUUSD ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  pause & exit /b 1
)

for %%Y in (2024 2023) do (
  for %%P in (M15 M5 M3) do (
    echo.
    echo ===== %%Y  %%P =====
    python run_backtests.py --sets sets_v5 --out results_v5_%%Y_%%P --period %%P ^
      --from %%Y.01.01 --to %%Y.12.31 %BASE%
  )
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   Four years now: 2026 and 2025 chose these, 2024 and 2023 did not.
echo   A config positive in all four is worth demo trading. One that only
echo   works in the two it was picked from was never real.
pause
