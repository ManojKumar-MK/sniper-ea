@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  Compile the EAs headlessly with MetaEditor's command line, straight
REM  into the tester's Experts folder so the .ex5 lands where the runner
REM  looks for it.
REM
REM    COMPILE.bat            the two under test (GOLD_ORB, GridMaster)
REM    COMPILE.bat all        every EA in this repo
REM
REM  No need to open MetaEditor or press F7. Errors are printed.
REM ===================================================================

cd /d "%~dp0"
set MT5DIR=C:\MT5-Tester
set EXPDIR=%MT5DIR%\MQL5\Experts
set ME=%MT5DIR%\metaeditor64.exe

if not exist "%ME%" (
  echo.
  echo   metaeditor64.exe not found at %ME%
  echo   It sits beside terminal64.exe. Check MT5DIR at the top of this file.
  echo.
  pause & exit /b 1
)
if not exist "%EXPDIR%" mkdir "%EXPDIR%"

REM --- what to build -------------------------------------------------
set LIST="vendor\GOLD_ORB\GOLD_ORB_single.mq5" "vendor\GridMasterPro\GridMaster Pro.mq5"
if /I "%~1"=="all" set LIST="vendor\GOLD_ORB\GOLD_ORB_single.mq5" "vendor\GridMasterPro\GridMaster Pro.mq5" "vendor\FvgGold-EA\FvgGold.mq5" "vendor\MT5-SMC\EA_Script.mq5" "SniperTurtle_KZ_v1.00.mq5" "SniperOTE_Fib_v1.00.mq5" "SniperSweep_PDHPDL_v1.00.mq5" "SniperEntry_Strict_SessionFilter_Telegram_v1.30.mq5"

echo.
echo ==================================================================
echo   MetaEditor : %ME%
echo   Output to  : %EXPDIR%
echo ==================================================================

set FAILED=0
for %%F in (%LIST%) do (
  echo.
  echo --- %%~nxF
  copy /Y "%%~F" "%EXPDIR%\%%~nxF" >nul
  if errorlevel 1 (
    echo     FAIL  could not copy the source
    set FAILED=1
  ) else (
    del "%EXPDIR%\%%~nF.ex5" 2>nul
    "%ME%" /compile:"%EXPDIR%\%%~nxF" /log:"%TEMP%\mecomp.log" >nul 2>&1
    if exist "%EXPDIR%\%%~nF.ex5" (
      echo     OK    %%~nF.ex5
    ) else (
      echo     FAIL  no .ex5 produced. MetaEditor said:
      REM the log is UTF-16, so strip the nulls to make it readable
      powershell -NoProfile -Command "Get-Content -LiteralPath '%TEMP%\mecomp.log' | Select-String -Pattern 'error|warning' | Select-Object -First 15 | ForEach-Object { '          ' + $_.Line }" 2>nul
      set FAILED=1
    )
  )
)

REM GOLD_ORB's ORIGINAL source needs its Include folder - the single-file
REM build above does not, which is why that is the one we compile.
echo.
echo ==================================================================
if %FAILED%==1 (echo   Some builds FAILED - see above.) else (echo   All builds OK.)
echo ==================================================================
echo.
pause
