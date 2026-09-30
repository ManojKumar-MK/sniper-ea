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
set "PYFAIL="

echo [1] python on PATH
where python >nul 2>nul && (for /f "delims=" %%v in ('python --version 2^>^&1') do echo     OK   %%v) || (echo     FAIL  install from python.org, tick "Add python.exe to PATH" & set FAIL=1)

echo [1b] python actually runs
python -c "import sys,encodings; print('     OK   '+sys.executable)" 2>nul || (
  echo     FAIL  python.exe starts but cannot load its standard library.
  echo           PYTHONHOME = [%PYTHONHOME%]
  echo           PYTHONPATH = [%PYTHONPATH%]
  echo.
  echo           If BOTH are empty above, this is NOT a stale variable - the
  echo           Python INSTALL is damaged or incomplete, most often a missing
  echo           or moved Lib folder. Clearing variables will not fix it.
  echo.
  echo           Repair it:  Settings ^> Apps ^> Python ^> Modify ^> Repair
  echo           or reinstall from python.org, ticking "Add python.exe to PATH".
  echo.
  echo           NOTHING IS BLOCKED ON THIS. Use RUNSETS.bat, which drives
  echo           MetaTrader directly and needs no python at all:
  echo               .\RUNSETS.bat ^<sets^> ^<Expert.ex5^> ^<TF^> ^<year^>
  set PYFAIL=1
)

echo [2] tester terminal exists
if exist "%MT5DIR%\terminal64.exe" (echo     OK   %MT5DIR%\terminal64.exe) else (echo     FAIL  not found - install a SECOND MT5 there, or pass the path: CHECK_SETUP.bat "D:\Your\Path" & set FAIL=1)

echo [3] it is PORTABLE  ^(data folder beside the exe, not under %%APPDATA%%^)
if exist "%MT5DIR%\MQL5\Profiles\Tester" (echo     OK   %MT5DIR%\MQL5\Profiles\Tester) else (echo     FAIL  launch it once as: %MT5DIR%\terminal64.exe /portable & set FAIL=1)

echo [4] tester terminal is CLOSED
set "TESTERUP="
for /f "delims=" %%P in ('powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='terminal64.exe'\" ^| ForEach-Object { $_.ExecutablePath }" 2^>nul') do (
  if /I "%%~P"=="%MT5DIR%\terminal64.exe" set "TESTERUP=1"
)
if defined TESTERUP (
  echo     FAIL  THE TESTER TERMINAL IS OPEN:
  echo             %MT5DIR%\terminal64.exe
  echo           Close it. A second launch of the SAME terminal hands the
  echo           /config: to the open instance and exits, so every pass
  echo           finishes in seconds with NO REPORT. This is the most common
  echo           cause of a whole grid producing nothing.
  set FAIL=1
) else (
  tasklist /FI "IMAGENAME eq terminal64.exe" 2>nul | find /I "terminal64.exe" >nul && (
    echo     OK   a terminal64.exe is running but it is NOT the tester one
    echo          - your live terminal is fine to leave open
  ) || echo     OK   no terminal running
)

echo [5] compiled EAs in %MT5DIR%\MQL5\Experts
REM  DISCOVERED. This was a hardcoded list of four names written before
REM  SniperGrid existed, so SniperGrid's absence looked like a finding when
REM  the check simply never looked for it. Same mistake as COMPILE.bat's list.
set /a NEX=0
for %%F in (*.mq5) do (
  if exist "%MT5DIR%\MQL5\Experts\%%~nF.ex5" (
    echo     OK   %%~nF.ex5
  ) else (
    echo     --   %%~nF.ex5   NOT BUILT
  )
  set /a NEX+=1
)
for /r vendor %%F in (*.mq5) do (
  if /I not "%%~nxF"=="GOLD_ORB.mq5" (
    if exist "%MT5DIR%\MQL5\Experts\%%~nF.ex5" (echo     OK   %%~nF.ex5) else (echo     --   %%~nF.ex5   NOT BUILT)
  )
)

echo [6] no spaces or brackets in this folder path
if not "%CD%"=="%CD: =%" (
  echo     WARN  "%CD%" contains a space. MT5 cannot read a /config: path
  echo           with spaces - move the repo somewhere plain like C:\ema.
) else (
  echo     OK   %CD%
)

echo [7] what the python runner would do (optional - RUNSETS does not need it)
python run_all.py --list --grids orb --periods H1 --years 2023,2024,2025,2026 --mt5dir "%MT5DIR%" 2>nul || (
  echo     --   skipped, python is not usable. Use RUNSETS.bat instead:
  echo            .\RUNSETS.bat grid-grid\sets_grid SniperGrid_v1.00.ex5 M5 2026
)

echo.
echo ==================================================================
if %FAIL%==1 (
  echo   NOT READY - fix the FAIL lines above.
) else (
  if defined PYFAIL (
    echo   READY for RUNSETS.bat. Python is broken but RUNSETS does not use it,
    echo   so only run_all.py and the merged comparison table are unavailable.
  ) else (
    echo   Checks passed. WARN lines are yours to judge.
  )
)
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
