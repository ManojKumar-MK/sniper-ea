@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SQ_1Y.bat
REM
REM  ONE CLICK, ONE FULL YEAR. SniperEntry v1.40, 23 sets, M3 and M5.
REM  46 passes, fast model, about 90 minutes. Start it and leave it.
REM
REM  THE WINDOW: 2025.10.01 to 2026.09.30 - a genuine twelve months,
REM  ending at the last data the broker has. RUN_SQ.bat uses calendar
REM  2026, which today is only about nine months and would quietly
REM  under-report every trade count by a quarter.
REM
REM  Want a clean calendar year instead? 2025 is the last complete one:
REM     set MODEL=1 ^& set OUTTAG=_sq
REM     .\RUNSETS.bat sq-grid\sets_sq SniperEntry_Strict_SessionFilter_Telegram_v1.30.ex5 M3 2025 nostop
REM     .\RUNSETS.bat sq-grid\sets_sq SniperEntry_Strict_SessionFilter_Telegram_v1.30.ex5 M5 2025 nostop
REM
REM  Resumable: any pass whose report already exists is skipped, so an
REM  interruption costs nothing - run it again and it continues.
REM
REM  Reports: sq-grid\results_LAST12M_M3_sq_m1\
REM           sq-grid\results_LAST12M_M5_sq_m1\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_sq
set FROMDATE=2025.10.01
set TODATE=2026.09.30
set PERIODTAG=LAST12M

set "EA=SniperEntry_Strict_SessionFilter_Telegram_v1.30"

echo.
echo   STEP 1 of 3 - compiling SniperEntry v1.40
echo ==================================================================
call COMPILE.bat %EA%.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\%EA%.ex5" (
  echo.
  echo   No .ex5 - stopping rather than running 46 passes against a
  echo   build that does not exist.
  echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 3 - 23 sets on M3, 12 months
echo ==================================================================
call RUNSETS.bat sq-grid\sets_sq %EA%.ex5 M3 %PERIODTAG% nostop

echo.
echo   STEP 3 of 3 - 23 sets on M5, 12 months
echo ==================================================================
call RUNSETS.bat sq-grid\sets_sq %EA%.ex5 M5 %PERIODTAG% nostop

echo.
echo ==================================================================
echo   Reports: sq-grid\results_LAST12M_M3_sq_m1\  and  ..._M5_sq_m1\
echo.
echo   READ IN THIS ORDER
echo     1. The SIGNAL TALLY line at the end of each pass's journal:
echo          crosses=N taken=N ^| htf=N conf=N chop=N quality=N ...
echo        A gate showing 0 rejections DID NOTHING. That set is
echo        SQ_base with extra inputs and says nothing about the idea.
echo     2. SQ_base itself. Every other set can only REMOVE trades from
echo        it, so the question is never "is the net positive" but
echo        "did this gate remove the right trades".
echo     3. Expectancy PER TRADE, not net. Net falls as trades fall
echo        even when the edge improves.
echo     4. M3 against M5 for the same set. Per-trade cost is ~2.13
echo        USD and M3 pays it far more often, so a gate that works
echo        only on M5 is probably buying back spread.
echo.
echo   Then commit both folders:
echo     git add sq-grid/results_LAST12M_M3_sq_m1 sq-grid/results_LAST12M_M5_sq_m1
echo     git commit -m "sq-grid: 23 sets, M3+M5, 12 months"
echo     git push
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
