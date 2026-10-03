@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_RATE.bat
REM
REM  2 sets x 2019-2026 on REAL TICKS. 16 passes, ~5 hours.
REM
REM  THE QUESTION THIS ANSWERS, AND WHY IT IS THE RIGHT ONE
REM  Every +2500 in the _pass results was InpTargetLock firing at +10%%
REM  and HALTING THE EA for the rest of the year. 2024 was over in
REM  March. So we have never measured what this strategy earns in a
REM  full year - only how long it takes to make 10%% and stop.
REM
REM  That matters for a daily-income target, because "$1,500 a year
REM  average" is not the strategy's rate. It is the rate of a strategy
REM  that quits in March.
REM
REM    RATE_r05_nolock   0.5%% risk, InpTargetLock=false
REM    RATE_r10_nolock   1.0%% risk, InpTargetLock=false
REM
REM  The static floor at 23,500 still applies, so a year can still end
REM  at -1500. The max-loss guard is NOT disabled - only the profit
REM  halt is.
REM
REM  WHAT TO DO WITH THE ANSWER
REM  Take the 8-year average annual return R, as a %% of 25,000. Then
REM  the capital needed for $100/day is 25,200 / R. That is the real
REM  answer to the daily-income question, and it is a capital number,
REM  not a strategy number.
REM
REM  Reports: srhtf-grid\results_^<year^>_M5_rate\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=4
set OUTTAG=_rate

echo.
echo   Compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   2 sets x 8 years, real ticks, NO target lock
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_rate SR_HTF_StopEntry_EA.ex5 M5 2019 2020 2021 2022 2023 2024 2025 2026 nostop

echo.
echo ==================================================================
echo   Net is now a REAL annual return, not a halt. A year ending at
echo   ~-1500 is still the static floor being hit.
echo.
echo   Average the eight years, divide by 25,000, and that is R.
echo   Capital needed for 100 USD a day = 25,200 / R.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
