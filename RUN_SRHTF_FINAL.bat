@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_FINAL.bat
REM
REM  4 sets x 2026 on REAL TICKS. 4 passes x ~19 min = ~1.3 hours.
REM
REM  NOTE: 2026 is the year these sets were CHOSEN on, so this measures
REM  the tick model, not out-of-sample survival. It answers "does the
REM  scale-out still hold up when fills are real?" and nothing more.
REM  For the out-of-sample question add the other years back:
REM      call RUNSETS.bat srhtf-grid\sets_srhtf_final SR_HTF_StopEntry_EA.ex5 M5 2023 2024 2025 nostop
REM  Those three are ~3.7 hours and can be run any time later - the
REM  2026 reports are kept and never redone.
REM
REM  Everything before this was Model=1 (1-minute OHLC), which fills a
REM  stop order anywhere inside the bar - including at prices the tape
REM  never printed. This EA is entirely stop-entry, and the leading
REM  candidate also scales out and trails, which is the behaviour MOST
REM  sensitive to that assumption. So Model=1 cannot settle it.
REM
REM  THE SHORTLIST, and why each is here
REM    V4_s1_part50  the only set in the v4 grid with >=30 trades, a
REM                  profit, and equity drawdown inside the 6% rule.
REM                  70 trades, +1737, 2.47% DD, 80% wins.
REM    V4_s1         the SAME set without the scale-out. 39 trades,
REM                  +2126, but 9.15% DD - it breaches. This is the
REM                  control that shows the partial is what fixed the
REM                  drawdown rather than luck.
REM    V4_ag2_opp1   best $/trade (72.41) from a different bias config.
REM    V4_s1_r025    half the risk, to separate edge from sizing.
REM
REM  Reports: srhtf-grid\results_<year>_M5_final\  (no _m1 - real ticks)
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=4
set OUTTAG=_final

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA v1.30
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - 4 sets x 2026, real ticks
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_final SR_HTF_StopEntry_EA.ex5 M5 2026 nostop

echo.
echo ==================================================================
echo   Reports: srhtf-grid\results_^<year^>_M5_final\
echo.
echo   HOW TO JUDGE IT
echo     Compare each set against its OWN fast-model number, not
echo     against the others. V4_s1_part50 was 70 trades, +1737,
echo     2.47%% equity drawdown on Model=1.
echo.
echo     The scale-out is the thing on trial. Model=1 fills a stop
echo     order anywhere inside the bar, which flatters it, so if the
echo     drawdown stays near 2.5%% on real ticks the result is real. If
echo     it blows out toward V4_s1's 9.15%%, the scale-out was an
echo     artifact of the fill model and there is nothing here.
echo.
echo     This is still ONE year, and the year the sets were picked on.
echo     A pass here earns 2023-2025, it does not replace it.
echo.
echo   Commit srhtf-grid\results_2026_M5_final.
echo ==================================================================
set "NOPAUSE="
REM  CHAINED is set by RUN_NEXT.bat, which runs these back to back - a bare
REM  pause here would stop the chain waiting for a keypress.
if not defined CHAINED pause
