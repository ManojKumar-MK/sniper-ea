@echo off
setlocal
REM ===================================================================
REM  ONE CLICK - every grid, every timeframe, then collect the results.
REM
REM  kz-grid + sweep-grid + turtle-grid, each across M5 and M3,
REM  merged per grid and copied into backtest-results\<timestamp>\
REM  ready to commit.
REM
REM  SETUP, once:
REM    1. Install a SECOND MT5 to C:\MT5-Tester (not the default path)
REM    2. Shortcut with /portable appended - this exact command line:
REM         C:\MT5-Tester\terminal64.exe /portable
REM    3. Launch it, log in, compile each EA with F7 and copy the .ex5
REM       files into C:\MT5-Tester\MQL5\Experts\
REM    4. Open an XAUUSD M3 chart there and scroll back past 1 Jan so it
REM       downloads the history
REM    5. CLOSE that terminal. MT5 will not start a tester pass while the
REM       same portable instance is open. Leave your LIVE one running.
REM
REM  run_all.py checks each .ex5 is present and asks before running
REM  without one - a stale build silently ignores inputs it does not
REM  have, which looks like a grid where nothing makes any difference.
REM ===================================================================

cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo.
  echo   python is not on PATH.
  echo   Install it from python.org and tick "Add python.exe to PATH".
  echo.
  pause
  exit /b 1
)

python run_all.py %*

echo.
echo ===== done =====
echo   Results are in backtest-results\ - commit that folder to keep them.
echo   Read all_results.csv per grid, and rank by the WORST timeframe.
pause
