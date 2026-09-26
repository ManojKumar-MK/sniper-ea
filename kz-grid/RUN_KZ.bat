@echo off
setlocal
REM ===================================================================
REM  KILLZONE grid - one click, M3 + M5 + M15, then one merged table.
REM
REM  Runs against a SEPARATE PORTABLE MT5 so your live terminal keeps
REM  running untouched. Set up once:
REM    1. Install a second MT5 to C:\MT5-Tester (not the default path)
REM    2. Shortcut with /portable appended - this exact command line:
REM         C:\MT5-Tester\terminal64.exe /portable
REM       /portable is what makes the terminal keep its data folder
REM       BESIDE terminal64.exe instead of under %APPDATA%. This script
REM       passes it to every tester run too, so both halves agree on
REM       where MQL5\Profiles\Tester actually is.
REM    3. Launch it, log in, copy the .ex5 into C:\MT5-Tester\MQL5\Experts\
REM    4. Open an XAUUSD M3 chart there and scroll back past 1 Jan so it
REM       downloads the history
REM    5. Close that terminal. Leave your LIVE one running.
REM
REM  COMPILE FIRST. The killzone inputs do not exist in an .ex5 built
REM  before this change, and MT5 will silently ignore every InpKz* key.
REM ===================================================================

set MT5DIR=C:\MT5-Tester
set EXPERT=SniperEntry_Strict_SessionFilter_Telegram_v1.30.ex5
set OPTS=--skip-done --allow-running --symbol XAUUSD --from 2026.01.01 --to 2026.09.18 ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\terminal64.exe" (
  echo.
  echo   Cannot find %MT5DIR%\terminal64.exe
  echo   Install the second MT5 there, or edit MT5DIR at the top of this file.
  echo.
  pause
  exit /b 1
)

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo.
  echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\
  echo   Compile it with F7 and copy it there first.
  echo.
  pause
  exit /b 1
)

echo.
echo   Tester terminal : %MT5DIR%\terminal64.exe
echo   Sets            : sets_kz  (10 runs x 3 timeframes = 30 backtests)
echo   Portable cmd    : %MT5DIR%\terminal64.exe /portable
echo   Your LIVE terminal is not touched.
echo.
REM  Open the portable terminal once, by hand, if you still need to log in
REM  or download history. Close it again before the runs start - MT5 will
REM  not start a tester pass while the same portable instance is open.
REM      start "" "%MT5DIR%\terminal64.exe" /portable


echo ===== killzone grid, M15 =====
python run_backtests.py --sets sets_kz --out results_kz_M15 --period M15 %OPTS%
echo. & echo ===== killzone grid, M5 =====
python run_backtests.py --sets sets_kz --out results_kz_M5  --period M5  %OPTS%
echo. & echo ===== killzone grid, M3 =====
python run_backtests.py --sets sets_kz --out results_kz_M3  --period M3  %OPTS%

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   all_results.csv holds every run. Read REF_nokz first - it is the
echo   control, and a killzone run only means something against it.
pause
