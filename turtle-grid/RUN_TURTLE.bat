@echo off
setlocal
REM ===================================================================
REM  KILLZONE RANGE grid - one click, M5 + M3, then one merged table.
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
REM    5. CLOSE that terminal. Leave your LIVE one running.
REM       This matters on every run, not just the first: a second launch of
REM       the SAME terminal hands the /config: off to the open instance and
REM       exits in seconds, so every pass "finishes" with no report. The
REM       script now refuses to start in that state and says so. Your LIVE
REM       terminal does not trigger it - the check compares paths.
REM
REM  COMPILE FIRST (F7). None of the InpKzr* inputs exist in any older
REM  .ex5, and MT5 silently ignores keys it does not recognise - you
REM  would get 9 identical runs and never know why.
REM ===================================================================

set MT5DIR=C:\MT5-Tester
set EXPERT=SniperTurtle_KZ_v1.00.ex5
set OPTS=--skip-done --symbol XAUUSD --from 2026.01.01 --to 2026.09.18 ^
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
echo   Sets            : sets_turtle  (33 runs x 3 timeframes = 99 backtests)
echo   Portable cmd    : %MT5DIR%\terminal64.exe /portable
echo   Your LIVE terminal is not touched.
echo.
REM  Open the portable terminal once, by hand, if you still need to log in
REM  or download history. Close it again before the runs start - MT5 will
REM  not start a tester pass while the same portable instance is open.
REM      start "" "%MT5DIR%\terminal64.exe" /portable


echo ===== turtle grid, M5 =====
python run_backtests.py --sets sets_turtle --out results_tu_M5  --period M5  %OPTS%
echo. & echo ===== turtle grid, M3 =====
python run_backtests.py --sets sets_turtle --out results_tu_M3  --period M3  %OPTS%

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   all_results.csv holds every run. TU_ref_kz60 is the control - every
echo   other set changes ONE thing against it, so read it first and rank
echo   the rest by their WORST timeframe, not their best.
pause
