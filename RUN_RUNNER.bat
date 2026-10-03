@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_RUNNER.bat
REM
REM  ONE backtest pass with the event log ON, to answer one question:
REM
REM     can a TP3+ trade be told apart AT ENTRY?
REM
REM  Trades that run to TP3/TP4/TP5 are real. Whether anything visible
REM  at entry separates them from the ones that stall at TP1 is a
REM  different question, and it is measurable - the EA already logs
REM  mfe_r (how far each trade ran, in R) next to every entry feature:
REM  ADX, RSI, MACD, VWAP, EMA gap, ATR, volume, spread, bias score.
REM
REM  After this finishes, the log is at
REM      %%MT5DIR%%\MQL5\Files\RUNNER_XAUUSD_M5.csv
REM  copy it here and run:
REM      python3 runner_analysis.py RUNNER_XAUUSD_M5.csv
REM
REM  WHAT THE ANSWER MEANS
REM    separates     -> build the filter, then prove it OUT OF SAMPLE
REM    does not      -> the runners are a TAIL. You cannot pick them,
REM                     so the system has to take every trade small
REM                     rather than few trades big. That is a different
REM                     EA, and knowing it is worth more than guessing.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_runner
set FROMDATE=2025.10.01
set TODATE=2026.09.30
set PERIODTAG=LAST12M
set "EA=SniperEntry_Strict_SessionFilter_Telegram_v1.30"

echo.
echo   Compiling %EA%
echo ==================================================================
call COMPILE.bat %EA%.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\%EA%.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   One pass, 12 months, M5, event log ON
echo ==================================================================
call RUNSETS.bat sq-grid\sets_sq_log\RUNNER_log.set %EA%.ex5 M5 %PERIODTAG% nostop

echo.
echo ==================================================================
echo   Now copy the event log out of the tester and analyse it:
echo.
echo     copy "%MT5DIR%\MQL5\Files\RUNNER_XAUUSD_M5.csv" .
echo     python3 runner_analysis.py RUNNER_XAUUSD_M5.csv
echo.
echo   If the tester wrote it to an agent sandbox instead, find it:
echo     dir /s /b "%MT5DIR%\RUNNER_*.csv"
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
