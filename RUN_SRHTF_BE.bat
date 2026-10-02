@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_BE.bat
REM
REM  5 sets x the TWO DEAD YEARS only. 10 passes, ~3 hours.
REM
REM  THE HYPOTHESIS THIS TESTS
REM  Over eight real-tick years PASS_s1_tgt10 passed six and blew two.
REM  The two deaths have the same fingerprint, and it is not bad luck:
REM
REM             win%%   avg win   avg loss   outcome
REM    2019     50.0    $17.30    -$118.03   DEAD
REM    2022     48.0    $13.02    -$121.68   DEAD
REM    2020     43.8   $288.67    -$127.60   passed
REM    2021     57.1   $723.40    -$126.41   passed
REM
REM  The win RATE barely moves. What collapses is the size of the wins:
REM  17 and 13 dollars against 120-dollar losses. That is the
REM  break-even move triggering at 1R and then stopping the trade out
REM  at entry-plus-offset - a "win" worth almost nothing. In the years
REM  it survived, the winners ran instead.
REM
REM  So: does loosening or removing the BE move rescue 2019 and 2022?
REM
REM    BE_base     control, identical to PASS_s1_tgt10 (expect ~-1500)
REM    BE_off      InpBreakEven=false
REM    BE_r15      BE at 1.5R instead of 1R
REM    BE_r20      BE at 2.0R
REM    BE_r15_tr   BE at 1.5R, then trail at 2x ATR instead of sitting
REM
REM  TESTED ON THE FAILURES FIRST, ON PURPOSE. Only a variant that
REM  turns BOTH dead years into passes is worth the 2 hours it then
REM  costs to re-check the six years that already worked - a change
REM  that rescues 2019 but breaks 2024 is not progress.
REM
REM  Reports: srhtf-grid\results_^<year^>_M5_be\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=4
set OUTTAG=_be

echo.
echo   Compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   5 sets x 2019 and 2022 - the two years that blew the account
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_be SR_HTF_StopEntry_EA.ex5 M5 2019 2022 nostop

echo.
echo ==================================================================
echo   net ~ +2500  target reached        net ~ -1500  account dead
echo.
echo   BE_base should come back ~-1500 in both. If it does not, the
echo   harness changed under us and nothing else here is comparable.
echo.
echo   If a variant passes BOTH years, run it over the other six:
echo     set MODEL=4 ^& set OUTTAG=_be
echo     .\RUNSETS.bat srhtf-grid\sets_srhtf_be SR_HTF_StopEntry_EA.ex5 M5 2020 2021 2023 2024 2025 2026 nostop
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
