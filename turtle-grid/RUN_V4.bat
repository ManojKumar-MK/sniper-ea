@echo off
setlocal
REM ===================================================================
REM  v4 - is 50/100 real, or the best of 69 draws?
REM
REM  It runs TWICE on purpose:
REM    PASS 1  2026.01.01 - 2026.09.18   the period 50/100 was found on
REM    PASS 2  2025.01.01 - 2025.12.31   dates it has never seen
REM
REM  Pass 2 is the one that matters. A result that only exists on the
REM  period it was selected from is not a strategy, it is a memory of
REM  that period. If 2025 needs downloading, open an XAUUSD M3 chart in
REM  the tester terminal and scroll back past Jan 2025 first.
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

set IS=--from 2026.01.01 --to 2026.09.18
echo ===== IN-SAMPLE 2026, M15 =====
python run_backtests.py --sets sets_v4 --out results_v4_M15 --period M15 %BASE% %IS%
echo. & echo ===== IN-SAMPLE 2026, M5 =====
python run_backtests.py --sets sets_v4 --out results_v4_M5  --period M5  %BASE% %IS%
echo. & echo ===== IN-SAMPLE 2026, M3 =====
python run_backtests.py --sets sets_v4 --out results_v4_M3  --period M3  %BASE% %IS%

set OOS=--from 2025.01.01 --to 2025.12.31
echo. & echo ===== OUT-OF-SAMPLE 2025, M15 =====
python run_backtests.py --sets sets_v4 --out results_v4oos_M15 --period M15 %BASE% %OOS%
echo. & echo ===== OUT-OF-SAMPLE 2025, M5 =====
python run_backtests.py --sets sets_v4 --out results_v4oos_M5  --period M5  %BASE% %OOS%
echo. & echo ===== OUT-OF-SAMPLE 2025, M3 =====
python run_backtests.py --sets sets_v4 --out results_v4oos_M3  --period M3  %BASE% %OOS%

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   Read the OOS (2025) rows first. If 50/100 does not hold there, it
echo   was never real and the 2026 numbers are a memory of 2026.
pause
