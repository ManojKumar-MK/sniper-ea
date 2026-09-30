@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  Compile the EAs headlessly with MetaEditor's command line, straight
REM  into the tester's Experts folder so the .ex5 lands where the runner
REM  looks for it. No MetaEditor window, no F7.
REM
REM  IN POWERSHELL YOU MUST PREFIX WITH .\  --  PowerShell does not run
REM  scripts from the current directory otherwise:
REM      .\COMPILE.bat
REM      .\COMPILE.bat all
REM      .\COMPILE.bat all "D:\MT5-Tester"
REM  In cmd.exe the bare name works.
REM
REM  Arguments, in any order:
REM      all        build every .mq5 found in the repo (discovered, not listed)
REM      <file.mq5> build just that one, e.g. .\COMPILE.bat SniperGrid_v1.00.mq5
REM      <path>     the MT5 folder to use (anything containing \ or :)
REM  Or set MT5DIR as an environment variable.
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
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
REM  "all" builds everything discovered, a *.mq5 name builds just that one,
REM  anything else is the MT5 folder.
set BUILDALL=0
set ONEFILE=
for %%A in (%*) do (
  if /I "%%~A"=="all" (set BUILDALL=1) else (
    if /I "%%~xA"==".mq5" (set ONEFILE=%%~A) else (set MT5DIR=%%~A)
  )
)

REM --- metaeditor64.exe comes from the SAME folder as terminal64.exe ---
set ME=%MT5DIR%\metaeditor64.exe
if not exist "%ME%" (
  echo.
  echo   metaeditor64.exe not found at:
  echo       %ME%
  echo.
  echo   It ships beside terminal64.exe in every MT5 install. Looking elsewhere...
  for %%P in ("C:\MT5-Tester" "C:\MetaTrade-Live" "C:\Program Files\MetaTrader 5") do (
    if exist "%%~P\metaeditor64.exe" echo       found one at %%~P
  )
  echo.
  echo   Pass the right folder:   .\COMPILE.bat all "C:\Your\MT5"
  echo   or set it:               set MT5DIR=C:\Your\MT5
  echo.
  pause & exit /b 1
)

set EXPDIR=%MT5DIR%\MQL5\Experts
if not exist "%EXPDIR%" mkdir "%EXPDIR%"

REM  --- what to build -----------------------------------------------
REM  DISCOVERED, not hand-listed. The list went stale twice - a new EA was
REM  added and COMPILE.bat did not know about it, so the grid failed with
REM  "not in MQL5\Experts" and looked like a missing file.
REM
REM  Only one file is skipped: vendor\GOLD_ORB\GOLD_ORB.mq5, the original
REM  that needs its nine .mqh files from an Include\ folder.
REM  GOLD_ORB_single.mq5 has them inlined and builds alone.
set LIST=
if not "%ONEFILE%"=="" (
  set LIST="%ONEFILE%"
) else (
  if %BUILDALL%==1 (
    for /r %%F in (*.mq5) do (
      if /I not "%%~nxF"=="GOLD_ORB.mq5" call set LIST=%%LIST%% "%%F"
    )
  ) else (
    set LIST="vendor\GOLD_ORB\GOLD_ORB_single.mq5" "vendor\GridMasterPro\GridMaster Pro.mq5"
  )
)

echo.
echo ==================================================================
echo   MT5 folder  : %MT5DIR%
echo   MetaEditor  : %ME%
echo   Output to   : %EXPDIR%
echo ==================================================================

set FAILED=0
for %%F in (%LIST%) do (
  echo.
  echo --- %%~nxF
  if not exist "%%~F" (
    echo     FAIL  source not found - are you in the repo root?
    set FAILED=1
  ) else (
    copy /Y "%%~F" "%EXPDIR%\%%~nxF" >nul
    del "%EXPDIR%\%%~nF.ex5" 2>nul
    "%ME%" /compile:"%EXPDIR%\%%~nxF" /log:"%TEMP%\mecomp.log" >nul 2>&1
    if exist "%EXPDIR%\%%~nF.ex5" (
      echo     OK    %%~nF.ex5
    ) else (
      echo     FAIL  no .ex5 produced. MetaEditor said:
      powershell -NoProfile -Command "Get-Content -LiteralPath '%TEMP%\mecomp.log' -ErrorAction SilentlyContinue | Select-String -Pattern 'error|warning' | Select-Object -First 15 | ForEach-Object { '          ' + $_.Line }" 2>nul
      set FAILED=1
    )
  )
)

echo.
echo ==================================================================
if %FAILED%==1 (echo   Some builds FAILED - see above.) else (echo   All builds OK.)
echo ==================================================================
echo.
echo   Note: vendor\GOLD_ORB\GOLD_ORB.mq5 is NOT built - it is the original
echo   and needs its nine .mqh files from an Include\ folder. The
echo   GOLD_ORB_single.mq5 built above has them inlined.
echo.
pause
