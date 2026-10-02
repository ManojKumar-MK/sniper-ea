@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_ROBUST.bat
REM
REM  TWO QUESTIONS, ~5 hours total, both on REAL TICKS.
REM
REM  WHERE WE ARE
REM  PASS_s1_tgt10 reached the full +10%% target in ALL FOUR years -
REM  2023 Apr, 2024 Mar, 2025 Mar, 2026 Jul - and never touched the
REM  static floor. 2023-2025 are genuinely out of sample; the set was
REM  chosen on 2026.
REM
REM  WHY THAT IS NOT YET A GREEN LIGHT
REM  Its twin PASS_s1_tgt10_dg2, identical except InpDailyGuardPct
REM  2.5 -^> 2.0, BLEW 2024 and 2025. One parameter, two dead accounts.
REM  The mechanism: reaching the target ENDS the year, so anything that
REM  delays the target keeps the EA trading - 16 trades became 36, 14
REM  became 41, and the extra exposure found the floor. "Win fast and
REM  stop, or keep trading and die" is not robustness, it is a knife
REM  edge, and one point on a knife edge is not a strategy.
REM
REM  STEP 1  OOS_s1_tgt10 over 2019-2022  (4 passes, ~1.3 h)
REM          The same config on four MORE independent years. This is
REM          worth more than any parameter tweak: if it passes 8 years
REM          running, the 4/4 was not luck. If the broker has no real
REM          tick data that far back the passes will say so.
REM
REM  STEP 2  6 neighbours over 2023-2026  (24 passes, ~7.6 h)
REM          One step either side of the two sensitive axes: daily
REM          guard 2.25/2.75/3.0, risk 0.4/0.6, max guard 5.0. If only
REM          2.5/0.5 survives, it is a spike and must not be traded.
REM          A plateau means several neighbours also pass 4/4.
REM
REM  Reports: srhtf-grid\results_^<year^>_M5_oos\  and  ..._M5_robust\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=4

echo.
echo   Compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 1 of 2 - four MORE out-of-sample years, 2019-2022
echo ==================================================================
set OUTTAG=_oos
call RUNSETS.bat srhtf-grid\sets_srhtf_oos SR_HTF_StopEntry_EA.ex5 M5 2019 2020 2021 2022 nostop

echo.
echo   STEP 2 of 2 - six neighbours, 2023-2026
echo ==================================================================
set OUTTAG=_robust
call RUNSETS.bat srhtf-grid\sets_srhtf_robust SR_HTF_StopEntry_EA.ex5 M5 2023 2024 2025 2026 nostop

echo.
echo ==================================================================
echo   HOW TO READ BOTH
echo     net ~ +2500  target reached, year passed
echo     net ~ -1500  static floor hit, account dead
echo     anything between: still trading at year end, target not made
echo.
echo   STEP 1 verdict: 4 more clean years makes eight in a row.
echo   STEP 2 verdict: count how many of the six also pass 4/4.
echo     5 or 6 of 6  -^> a plateau. Worth a demo account.
echo     1 or 2 of 6  -^> a spike. Do NOT trade it, whatever the net.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
