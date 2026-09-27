@echo off
setlocal
REM ===================================================================
REM  v3 grid - 23 sets x M15/M5/M3 = 69 backtests.
REM
REM  M15 IS BACK, deliberately, against the earlier decision to drop it.
REM  v1+v2 measured a cost of about $2.13 per trade: runs under 300
REM  trades had a median net of +25, runs over 600 a median of -703. If
REM  trade COUNT is what is bleeding the account, the higher timeframe
REM  is the most direct test available and leaving it out would mean
REM  not asking the one question the data raised.
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

echo ===== v3 grid, M15 =====
python run_backtests.py --sets sets_v3 --out results_v3_M15 --period M15 %OPTS%
echo. & echo ===== v3 grid, M5 =====
python run_backtests.py --sets sets_v3 --out results_v3_M5  --period M5  %OPTS%
echo. & echo ===== v3 grid, M3 =====
python run_backtests.py --sets sets_v3 --out results_v3_M3  --period M3  %OPTS%

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   Read the EMA block first - 9/21 was never once varied across the 61
echo   sets of v1 and v2, and it is the signal itself.
pause
