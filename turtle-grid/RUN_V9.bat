@echo off
setlocal
REM ===================================================================
REM  v9 - the v8 leaders on years they have never seen.
REM       8 sets x M15 x 2023 + 2024 = 16 backtests. Minutes, not hours.
REM
REM  WO60_ALN_none is the best of 120 sets on 2025 and 2026 - and those
REM  are the two years every configuration upstream was already tuned
REM  on. This is the only thing that can tell them apart from a fit.
REM
REM  It has happened once already: V3_ema_50_100 looked just as strong
REM  on 2025+2026 and did not survive 2023+2024.
REM ===================================================================

cd /d "%~dp0"
set MT5DIR=C:\MetaTrade-Live
set EXPERT=SniperTurtle_KZ_v1.00.ex5
set BASE=--skip-done --deposit 25000 --symbol XAUUSD ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  pause & exit /b 1
)

for %%Y in (2024 2023) do (
  echo.
  echo ===== %%Y  M15 =====
  python run_backtests.py --sets sets_v9 --out results_v9_%%Y_M15 --period M15 ^
    --from %%Y.01.01 --to %%Y.12.31 %BASE%
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   Four years now. Profitable in all four is a finding. Profitable only
echo   in the two it was chosen from is a fit, and you would be trading it.
pause
