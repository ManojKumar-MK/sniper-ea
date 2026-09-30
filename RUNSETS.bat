@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  RUNSETS  -  batch-run a folder of .set files in MetaTrader's own
REM              Strategy Tester. NO PYTHON ANYWHERE.
REM
REM  IN POWERSHELL prefix with .\   ->   .\RUNSETS.bat grid-grid\sets_grid ...
REM
REM  USAGE
REM    RUNSETS.bat <setsfolder> <Expert.ex5> <TF> <year> [year...]
REM
REM  EXAMPLES
REM    RUNSETS.bat grid-grid\sets_grid SniperGrid_v1.00.ex5 M5 2023 2024 2025 2026
REM    RUNSETS.bat orb-grid\sets_orb   GOLD_ORB_single.ex5  H1 2026
REM    RUNSETS.bat tp-grid\sets_tp     SniperTurtle_KZ_v1.00.ex5 M5 2026
REM
REM  WHY THIS EXISTS
REM  run_all.py and run_backtests.py do the same job with nicer reporting,
REM  but python.exe on this machine dies with
REM      Could not find platform independent libraries <prefix>
REM      ModuleNotFoundError: No module named 'encodings'
REM  which is a broken PYTHONHOME or a damaged install, and clearing those
REM  variables per-window did not fix it. MT5's tester only needs an .ini
REM  file, and batch can write one - so this removes python from the path
REM  entirely rather than waiting for it to be repaired.
REM
REM  WHAT IT DOES NOT DO
REM  No merged comparison table - that was the Python part. MT5 still writes
REM  a full .htm report per run into the results folder; push those and they
REM  can be parsed. Everything the analysis needs is in them.
REM ===================================================================

cd /d "%~dp0"
if not defined MT5DIR set MT5DIR=C:\MT5-Tester

set SETS=%~1
set EXPERT=%~2
set TF=%~3
if "%SETS%"=="" goto :usage
if "%EXPERT%"=="" goto :usage
if "%TF%"=="" goto :usage
shift & shift & shift
set YEARS=
:collect
if "%~1"=="" goto :checks
set YEARS=!YEARS! %~1
shift
goto :collect

:checks
if "!YEARS!"=="" goto :usage
set TERM=%MT5DIR%\terminal64.exe
set TESTERDIR=%MT5DIR%\MQL5\Profiles\Tester
if not exist "%TERM%"                        echo. & echo   terminal64.exe not at %TERM% & echo. & pause & exit /b 1
if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" echo. & echo   %EXPERT% not in %MT5DIR%\MQL5\Experts\ - compile it first & echo. & pause & exit /b 1
if not exist "%SETS%"                        echo. & echo   sets folder not found: %SETS% & echo. & pause & exit /b 1
if not exist "%TESTERDIR%" mkdir "%TESTERDIR%"

REM  The tester will not start while that same terminal is open - a second
REM  launch hands the /config: to the running instance and exits at once.
tasklist /FI "IMAGENAME eq terminal64.exe" 2>nul | find /I "terminal64.exe" >nul && (
  echo.
  echo   A terminal64.exe is running. If it is the TESTER one, close it -
  echo   otherwise every pass finishes in seconds with no report. Your LIVE
  echo   terminal is fine to leave open.
  echo.
  pause
)

set /a TOTAL=0
for %%S in ("%SETS%\*.set") do set /a TOTAL+=1
set /a RUNS=0
for %%Y in (!YEARS!) do for %%S in ("%SETS%\*.set") do set /a RUNS+=1

echo.
echo ==================================================================
echo   sets      : %SETS%   (!TOTAL! files)
echo   expert    : %EXPERT%
echo   timeframe : %TF%
echo   years     :!YEARS!
echo   runs      : !RUNS!
echo   terminal  : %TERM%
echo ==================================================================

set /a DONE=0
for %%Y in (!YEARS!) do (
  set OUT=results_%%Y_%TF%
  if not exist "%SETS%\..\!OUT!" mkdir "%SETS%\..\!OUT!"
  for %%S in ("%SETS%\*.set") do (
    set /a DONE+=1
    set NAME=%%~nS
    set REPORT=%SETS%\..\!OUT!\report_!NAME!

    if exist "!REPORT!.htm" (
      echo   [!DONE!/!RUNS!] %%Y !NAME! - already done, skipping
    ) else (
      REM  the terminal reads the .set ONLY from MQL5\Profiles\Tester
      copy /Y "%%~S" "%TESTERDIR%\%%~nxS" >nul

      set INI=%TEMP%\runsets_!NAME!.ini
      >  "!INI!" echo [Tester]
      >> "!INI!" echo Expert=%EXPERT%
      >> "!INI!" echo ExpertParameters=%%~nxS
      >> "!INI!" echo Symbol=XAUUSD
      >> "!INI!" echo Period=%TF%
      >> "!INI!" echo Model=4
      >> "!INI!" echo FromDate=%%Y.01.01
      >> "!INI!" echo ToDate=%%Y.12.31
      >> "!INI!" echo Deposit=25000
      >> "!INI!" echo Currency=USD
      >> "!INI!" echo Leverage=100
      >> "!INI!" echo Optimization=0
      >> "!INI!" echo ForwardMode=0
      >> "!INI!" echo ExecutionMode=0
      >> "!INI!" echo Visual=0
      >> "!INI!" echo Report=!REPORT!
      >> "!INI!" echo ReplaceReport=1
      >> "!INI!" echo ShutdownTerminal=1

      echo   [!DONE!/!RUNS!] %%Y !NAME! ...
      start /wait "" "%TERM%" /config:"!INI!" /portable
      if exist "!REPORT!.htm" (echo         OK) else (echo         NO REPORT - see %MT5DIR%\logs)
    )
  )
)

echo.
echo ==================================================================
echo   Reports are in %SETS%\..\results_^<year^>_%TF%\
echo   Commit that folder and the .htm files can be parsed for the
echo   comparison table.
echo ==================================================================
echo.
pause
exit /b 0

:usage
echo.
echo   RUNSETS.bat ^<setsfolder^> ^<Expert.ex5^> ^<TF^> ^<year^> [year...]
echo.
echo   e.g.  RUNSETS.bat grid-grid\sets_grid SniperGrid_v1.00.ex5 M5 2023 2024 2025 2026
echo.
pause
exit /b 1
