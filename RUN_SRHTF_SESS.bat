@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_SESS.bat
REM
REM  4 sets x 2019-2026 on REAL TICKS. 32 passes, ~10 hours. Overnight.
REM
REM  WHERE THE HYPOTHESIS COMES FROM
REM  1,355 old Sniper/Turtle runs with 30+ trades, across four years and
REM  three timeframes, split cleanly on one thing - whether London was
REM  in the killzone set:
REM
REM      WITHOUT London   total +47,408   positive 24/44  (55%%)
REM      WITH London      total -17,169   positive  9/28  (32%%)
REM
REM  KZFN_asia was the best single config of the eight (+17,625) and
REM  KZFN_asia_ny the most consistent (7 of 11 positive, median +902).
REM  Every London-containing variant lost money overall.
REM
REM  That matches the oldest robust finding in this project: the London
REM  killzone was positive in only ONE year out of four, on all three
REM  timeframes. And SR_HTF's best set has London ON.
REM
REM    SESS_ctrl        London + NY + Asia  = PASS_s1_tgt10 exactly
REM    SESS_no_london   Asia + NY           <- the hypothesis
REM    SESS_ny_only     NY alone
REM    SESS_asia_only   Asia alone
REM
REM  THIS IS A HYPOTHESIS, NOT A CONCLUSION. The evidence is from a
REM  DIFFERENT EA. The last idea carried across models - the Asian-range
REM  sweep, best in the SniperEntry grid - took SR_HTF from 6/8 to 0/8.
REM  A component's value has repeatedly turned out to be model-specific.
REM
REM  JUDGE IT THE SAME WAY
REM    net ~ +2500 = target reached    net ~ -1500 = account dead
REM  SESS_ctrl must come back 6/8 with 2019 and 2022 dead. If it does
REM  not, something changed and nothing else here is comparable.
REM  The bar to beat is 6 of 8.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=4
set OUTTAG=_sess

echo.
echo   Compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   4 session configurations x 8 years, real ticks
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_sess SR_HTF_StopEntry_EA.ex5 M5 2019 2020 2021 2022 2023 2024 2025 2026 nostop

echo.
echo ==================================================================
echo   Commit all eight results_^<year^>_M5_sess folders.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
