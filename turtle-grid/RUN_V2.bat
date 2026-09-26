@echo off
setlocal
REM ===================================================================
REM  v2 grid - 28 sets x M5/M3 = 56 backtests.
REM
REM  Built from what v1 actually showed, not from a fresh guess:
REM    * the server session filter is OFF. In v1 it was ANDed with the
REM      killzone window and silently dominated it, so lead 120 came out
REM      byte-identical to "window off" and the whole window block was
REM      unreadable.
REM    * the quality filter is ON with VWAP only. It was the one single
REM      condition profitable on both timeframes, so v2 builds from
REM      there rather than from a control that lost money.
REM    * every set has a unique InpCsvPrefix, so the EA's own trade logs
REM      are collectable instead of overwriting each other.
REM
REM  COMPILE FIRST (F7) and CLOSE the tester terminal before running.
REM ===================================================================

cd /d "%~dp0"
set MT5DIR=C:\MT5-Tester
set EXPERT=SniperTurtle_KZ_v1.00.ex5
set OPTS=--skip-done --deposit 25000 --symbol XAUUSD --from 2026.01.01 --to 2026.09.18 ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo.
  echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\
  echo   Compile it with F7 and copy it there first.
  echo.
  pause
  exit /b 1
)

echo ===== v2 grid, M5 =====
python run_backtests.py --sets sets_v2 --out results_v2_M5 --period M5 %OPTS%
echo. & echo ===== v2 grid, M3 =====
python run_backtests.py --sets sets_v2 --out results_v2_M3 --period M3 %OPTS%

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   Read V2_ctrl first. Then the EXIT block - that is the axis no v1 set
echo   touched, and the one the v1 numbers point at.
pause
