@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  RUNSETS  -  batch-run a folder of .set files in MetaTrader's own
REM              Strategy Tester. NO PYTHON ANYWHERE.
REM
REM  IN POWERSHELL prefix with .\   ->   .\RUNSETS.bat grid-grid\sets_grid ...
REM
REM  USAGE
REM    RUNSETS.bat <setsfolder-OR-one.set> <Expert.ex5> <TF> <year> [...] [nostop]
REM
REM  DIAGNOSE A FAILURE IN 30 SECONDS - point it at ONE set file:
REM    .\RUNSETS.bat grid-grid\sets_grid\G_fn_ctrl.set SniperGrid_v1.00.ex5 M5 2026
REM
REM  It STOPS at the first failed run and prints the MT5 log, because 100
REM  identical failures tell you nothing that the first one did not. Add
REM  "nostop" to push through regardless.
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
REM  Set NOPAUSE=1 before calling to suppress the "press any key" stops,
REM  so this can be chained from a wrapper as one continuous run.
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
set STOPFIRST=1
:collect
if "%~1"=="" goto :checks
if /I "%~1"=="nostop" (set STOPFIRST=0) else (set YEARS=!YEARS! %~1)
shift
goto :collect

:checks
if "!YEARS!"=="" goto :usage
set TERM=%MT5DIR%\terminal64.exe
set TESTERDIR=%MT5DIR%\MQL5\Profiles\Tester
REM  Parenthesised blocks, not "if COND a & b & c". In that form only the
REM  FIRST command is conditional and the rest run regardless - which is why
REM  a missing sets folder printed "not found" and then carried on to report
REM  0 files and 0 runs as though nothing were wrong.
if not exist "%TERM%" (
  echo.
  echo   terminal64.exe not at %TERM%
  echo.
  if not defined NOPAUSE pause
  exit /b 1
)
if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo.
  echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ - compile it first
  echo.
  if not defined NOPAUSE pause
  exit /b 1
)
if not exist "%SETS%" (
  echo.
  echo   NOT FOUND: %SETS%
  echo   If that is a sets folder, the .set files may never have been
  echo   committed - check .gitignore and "git ls-files".
  echo.
  if not defined NOPAUSE pause
  exit /b 1
)
if not exist "%TESTERDIR%" mkdir "%TESTERDIR%"

REM  A single .set FILE is accepted as well as a folder, so one run can be
REM  tested in seconds instead of discovering a problem 100 passes in.
set "ONESET="
if /I "%~x1"==".set" (
  for %%A in ("%SETS%") do set "ONESET=%%~fA"
  for %%A in ("%SETS%") do set "SETS=%%~dpA"
)

REM  ABSOLUTE PATHS, and this is not cosmetic. With /portable the terminal
REM  resolves a RELATIVE Report= against its OWN data folder, not against the
REM  directory this script was launched from - so a relative path writes the
REM  report into C:\MT5-Tester\... while the "did it appear?" check looks in
REM  the repo, and every run reports NO REPORT even when it succeeded.
for %%A in ("%SETS%\.") do set "SETSABS=%%~fA"
for %%A in ("!SETSABS!") do set "GRIDDIR=%%~dpA"

REM  MT5 cannot read a /config: path containing a space or a bracket - it
REM  opens, finds nothing and quits, leaving .ini files and no reports. The
REM  Python runner refused outright in that case; same here, with the reason.
if not "!SETSABS!"=="!SETSABS: =!" (
  echo.
  echo   This path contains a SPACE:
  echo       !SETSABS!
  echo   MT5 cannot read a /config: path with spaces or brackets - it would
  echo   open, find nothing and quit, writing .ini files but no reports.
  echo   Move the repo somewhere plain, e.g. C:\ema, and rerun.
  echo.
  if not defined NOPAUSE pause & exit /b 1
)

REM  The tester will not start while that same terminal is open - a second
REM  launch hands the /config: to the running instance and exits at once.
tasklist /FI "IMAGENAME eq terminal64.exe" 2>nul | find /I "terminal64.exe" >nul && (
  echo.
  echo   A terminal64.exe is running. If it is the TESTER one, close it -
  echo   otherwise every pass finishes in seconds with no report. Your LIVE
  echo   terminal is fine to leave open.
  echo.
  if not defined NOPAUSE pause
)

set /a TOTAL=0
set "GLOB=!SETSABS!\*.set"
if defined ONESET set "GLOB=!ONESET!"
for %%S in ("!GLOB!") do set /a TOTAL+=1
set /a RUNS=0
for %%Y in (!YEARS!) do for %%S in ("!GLOB!") do set /a RUNS+=1

echo.
echo ==================================================================
echo   sets      : !SETSABS!   (!TOTAL! files)
echo   expert    : %EXPERT%
echo   timeframe : %TF%
echo   years     :!YEARS!
echo   runs      : !RUNS!
echo   terminal  : %TERM%
echo ==================================================================

if !RUNS!==0 (
  echo.
  echo   ZERO RUNS - no .set files matched. Nothing was tested.
  echo   This used to print a tidy summary and exit 0, which reads as success.
  echo.
  if not defined NOPAUSE pause
  exit /b 1
)

set /a DONE=0
for %%Y in (!YEARS!) do (
  set "OUTDIR=!GRIDDIR!results_%%Y_%TF%"
  if not exist "!OUTDIR!" mkdir "!OUTDIR!"
  for %%S in ("!GLOB!") do (
    set /a DONE+=1
    set NAME=%%~nS
    set "REPORT=!OUTDIR!\report_!NAME!"

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
      if defined ONESET (>> "!INI!" echo Visual=0) else (>> "!INI!" echo Visual=0)
      REM  ShutdownTerminal stays 1 even for a single run: without it the
      REM  terminal sits open and start /wait never returns.
      >> "!INI!" echo Report=!REPORT!
      >> "!INI!" echo ReplaceReport=1
      >> "!INI!" echo ShutdownTerminal=1

      echo   [!DONE!/!RUNS!] %%Y !NAME! ...
      start /wait "" "%TERM%" /config:"!INI!" /portable
      if exist "!REPORT!.htm" (
        echo         OK
      ) else (
        echo         NO REPORT
        REM  Say WHY, here, rather than pointing at a log directory. The three
        REM  causes look identical from outside: the EA refused to initialise,
        REM  the terminal handed off to an already-open instance, or the report
        REM  was written somewhere else.
        if exist "!REPORT!.html" echo         ...but report_!NAME!.html exists - MT5 wrote .html not .htm
        for /f "delims=" %%L in ('dir /b /s "%MT5DIR%\report_!NAME!.htm*" 2^>nul') do echo         found elsewhere: %%L
        set "MTLOG="
        for /f "delims=" %%G in ('dir /b /o-d "%MT5DIR%\logs\*.log" 2^>nul') do if not defined MTLOG set "MTLOG=%MT5DIR%\logs\%%G"
        if defined MTLOG (
          echo         --- last lines of !MTLOG!
          powershell -NoProfile -Command "Get-Content -LiteralPath '!MTLOG!' -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { '             ' + $_ }" 2>nul
        )
        set "TSLOG="
        for /f "delims=" %%G in ('dir /b /o-d "%MT5DIR%\Tester\logs\*.log" 2^>nul') do if not defined TSLOG set "TSLOG=%MT5DIR%\Tester\logs\%%G"
        if defined TSLOG (
          echo         --- last lines of !TSLOG!
          powershell -NoProfile -Command "Get-Content -LiteralPath '!TSLOG!' -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { '             ' + $_ }" 2>nul
        )
        echo         --- the .ini used: !INI!
        if /I "!STOPFIRST!"=="1" (
          echo.
          echo         Stopping after the first failure so the cause is readable.
          echo         Pass "nostop" as the last argument to run all of them anyway.
          echo.
          if not defined NOPAUSE pause & exit /b 1
        )
      )
    )
  )
)

echo.
echo ==================================================================
echo   Reports are in !GRIDDIR!results_^<year^>_%TF%\
echo   Commit that folder and the .htm files can be parsed for the
echo   comparison table.
echo ==================================================================
echo.
if not defined NOPAUSE pause
exit /b 0

:usage
echo.
echo   RUNSETS.bat ^<setsfolder^> ^<Expert.ex5^> ^<TF^> ^<year^> [year...]
echo.
echo   e.g.  RUNSETS.bat grid-grid\sets_grid SniperGrid_v1.00.ex5 M5 2023 2024 2025 2026
echo.
if not defined NOPAUSE pause
exit /b 1
