@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  IN POWERSHELL prefix with .\  -  PowerShell will not run a script from
REM  the current directory otherwise:   .\CHECK_SETUP.bat
REM  In cmd.exe, or by double-clicking, the bare name works.
REM
REM  Pre-flight check. Runs nothing, changes nothing, places no trade.
REM  Verifies the tester setup before you burn an evening on 156 passes.
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
set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

echo.
echo ==================================================================
echo   Tester folder : %MT5DIR%
echo ==================================================================
echo.

set FAIL=0

echo [1] python on PATH
where python >nul 2>nul && (for /f "delims=" %%v in ('python --version 2^>^&1') do echo     OK   %%v) || (echo     FAIL  install from python.org, tick "Add python.exe to PATH" & set FAIL=1)

echo [1b] python actually runs
python -c "import sys,encodings; print('     OK   '+sys.executable)" 2>nul || (
  echo     FAIL  python.exe starts but cannot load its standard library.
  echo           Almost always a stale PYTHONHOME or PYTHONPATH:
  echo             PYTHONHOME = %PYTHONHOME%
  echo             PYTHONPATH = %PYTHONPATH%
  echo           The launchers clear both for their own window. If it still
  echo           fails, clear them for good:
  echo             setx PYTHONHOME ""
  echo             setx PYTHONPATH ""
  echo           then open a NEW terminal. Or reinstall python and tick
  echo           "Add python.exe to PATH".
  set FAIL=1
)

echo [2] tester terminal exists
if exist "%MT5DIR%\terminal64.exe" (echo     OK   %MT5DIR%\terminal64.exe) else (echo     FAIL  not found - install a SECOND MT5 there, or pass the path: CHECK_SETUP.bat "D:\Your\Path" & set FAIL=1)

echo [3] it is PORTABLE  ^(data folder beside the exe, not under %%APPDATA%%^)
if exist "%MT5DIR%\MQL5\Profiles\Tester" (echo     OK   %MT5DIR%\MQL5\Profiles\Tester) else (echo     FAIL  launch it once as: %MT5DIR%\terminal64.exe /portable & set FAIL=1)

echo [4] tester terminal is CLOSED
tasklist /FI "IMAGENAME eq terminal64.exe" 2>nul | find /I "terminal64.exe" >nul && (echo     WARN  a terminal64.exe is running. If it is the TESTER one, close it - a & echo           second launch hands off to the open instance and every pass & echo           finishes in seconds with no report. Your LIVE terminal is fine.) || echo     OK   nothing running

echo [5] compiled EAs in %MT5DIR%\MQL5\Experts
for %%E in ("GOLD_ORB_single.ex5" "GridMaster Pro.ex5" "FvgGold.ex5" "SniperTurtle_KZ_v1.00.ex5") do (
  if exist "%MT5DIR%\MQL5\Experts\%%~E" (echo     OK   %%~E) else (echo     --   %%~E   missing ^(only needed for its own grid^))
)

echo [6] no spaces or brackets in this folder path
echo %CD% | findstr /C:" " >nul && (echo     WARN  "%CD%" contains a space. MT5 cannot read a /config: path with & echo           spaces - move the repo somewhere plain like C:\ema and rerun.) || echo     OK   %CD%

echo [7] what the runner will actually do
python run_all.py --list --grids orb --periods H1 --years 2023,2024,2025,2026 --mt5dir "%MT5DIR%" 2>nul || echo     FAIL  run_all.py did not run - see [1]

echo.
echo ==================================================================
if %FAIL%==1 (echo   NOT READY - fix the FAIL lines above.) else (echo   Checks passed. WARN lines are yours to judge.)
echo ==================================================================
echo.
echo   Then, in MT5 itself:
echo     * Open XAUUSD H1 and M15 charts in the TESTER terminal and scroll
echo       back past Jan 2023, so the history downloads. Missing history
echo       still completes the runs - with far fewer trades, which reads as
echo       a weak strategy rather than a data gap.
echo     * Tools ^> Options ^> Expert Advisors: allow automated trading.
echo     * Close the tester terminal again before running a grid.
echo.
pause
