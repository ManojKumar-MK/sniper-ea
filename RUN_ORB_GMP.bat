@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\  -  PowerShell will not run a script from
REM  the current directory otherwise:   .\RUN_ORB_GMP.bat
REM  In cmd.exe, or by double-clicking, the bare name works.
REM
REM  ONE CLICK - GOLD_ORB + GridMaster Pro, four years each.
REM
REM    GOLD_ORB         19 sets x H1   x 2023-2026  =  76 runs
REM    GridMaster Pro   20 sets x M15  x 2023-2026  =  80 runs
REM                                                   ---------
REM                                                   156 runs
REM
REM  GOLD_ORB runs on H1 and GridMaster on M15 - each on the timeframe
REM  its author built it for, which is why this is not one loop.
REM
REM  Results land in orb-grid\ and gmp-grid\, then get collected into
REM  backtest-results\<timestamp>\ ready to commit.
REM
REM  SETUP, once:
REM    1. Second MT5 at C:\MT5-Tester, launched with /portable
REM    2. Compile BOTH and copy the .ex5 into C:\MT5-Tester\MQL5\Experts\
REM         vendor\GOLD_ORB\GOLD_ORB_single.mq5   -> GOLD_ORB_single.ex5
REM         vendor\GridMasterPro\GridMaster Pro.mq5 -> GridMaster Pro.ex5
REM       Use GOLD_ORB_single - it needs no Include\ folder, and upstream's
REM       own .ex5 is built from the version whose drawdown guard is broken.
REM    3. Scroll an XAUUSD H1 and M15 chart back past Jan 2023 so the
REM       history downloads
REM    4. CLOSE the tester terminal. Leave your live one running.
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

where python >nul 2>nul
if errorlevel 1 (
  echo. & echo   python is not on PATH. Install from python.org and tick
  echo   "Add python.exe to PATH". & echo.
  pause & exit /b 1
)

REM  MT5 folder: first argument, else the MT5DIR environment variable,
REM  else the default. Same convention as COMPILE.bat and CHECK_SETUP.bat.
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1
set MISSING=0
if not exist "%MT5DIR%\MQL5\Experts\GOLD_ORB_single.ex5"   set MISSING=1
if not exist "%MT5DIR%\MQL5\Experts\GridMaster Pro.ex5"     set MISSING=1
if %MISSING%==1 (
  echo.
  echo   One or both .ex5 files are missing from %MT5DIR%\MQL5\Experts\
  echo     GOLD_ORB_single.ex5
  echo     GridMaster Pro.ex5
  echo.
  echo   MT5 silently ignores inputs an older .ex5 does not have, so a stale
  echo   or missing build gives a grid of identical runs and no error.
  echo.
  pause
  exit /b 1
)

echo.
echo ==================================================================
echo   GOLD_ORB       19 sets x H1   x 4 years
echo   GridMaster Pro 20 sets x M15  x 4 years
echo   156 backtests, 25,000 USD deposit, XAUUSD
echo ==================================================================

python run_all.py --grids orb --periods H1  --years 2023,2024,2025,2026 --mt5dir "%MT5DIR%"
python run_all.py --grids gmp --periods M15 --years 2023,2024,2025,2026 --mt5dir "%MT5DIR%"

echo.
echo ===== done =====
echo.
echo   HOW TO READ IT
echo     1. ORB_ctrl and GMP_ctrl first - the authors' own defaults. If those
echo        have no edge over four years, nothing downstream supplies one.
echo     2. EQUITY drawdown, not balance drawdown. Across the eleven geraked
echo        grid EAs that ratio was never below 3.4x, and the gap is exactly
echo        where a funded account dies. 6%% equity DD is the limit.
echo     3. Then 2025 - the year that broke SniperTurtle on M5 and where 0 of
echo        128 filter combinations made money.
echo     4. Rank by the WORST year, never the best.
echo.
pause
