@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_PASS.bat
REM
REM  4 sets x 2023-2026 on REAL TICKS. 16 passes, ~5 hours.
REM
REM  WHY THIS RUN EXISTS
REM  The 4-year real-tick finals showed V4_s1 and V4_s1_r025 reaching
REM  InpTargetPct in all four years without ever touching the static
REM  floor. But InpTargetPct was 8.0 = $2,000, and FundedNext's 2-Step
REM  25k target is $2,500 = 10%%. Those sets stopped $500 short of
REM  actually passing.
REM
REM  These four raise InpTargetPct to 10.0 and ask the only question
REM  left: can the last 2%% be reached before equity hits 23,500? The
REM  _dg2 pair also tightens the daily guard from 2.5%% to 2.0%%, since
REM  more time spent trading is more chances to trip it.
REM
REM  JUDGE IT ON THE NET, NOT ON DRAWDOWN PERCENT
REM    net ~ +2500  target reached, challenge passed
REM    net ~ -1500  static floor hit, account dead
REM  Those two numbers are the whole result. MT5's "Equity Drawdown
REM  Maximal %%" is peak-to-trough and does NOT measure a static rule -
REM  reading it as pass/fail is what made me rank these sets last.
REM
REM  Reports: srhtf-grid\results_^<year^>_M5_pass\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=4
set OUTTAG=_pass

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - 4 sets x 2023 2024 2025 2026, real ticks
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_pass SR_HTF_StopEntry_EA.ex5 M5 2023 2024 2025 2026 nostop

echo.
echo ==================================================================
echo   Reports: srhtf-grid\results_^<year^>_M5_pass\
echo.
echo   A set passes only if net is ~+2500 in ALL FOUR years. One year
echo   at ~-1500 is a blown account, and on a real challenge there is
echo   no second attempt without paying again.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
