@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\PROBE_SRHTF.bat
REM
REM  THREE passes, ~6 minutes. Run this BEFORE any more grids.
REM
REM  Every .set in the repo wrote enums by name ("InpTF1=PERIOD_H1").
REM  MT5 stores enums as integers, so those lines never parsed and the
REM  inputs became 0 = PERIOD_CURRENT: the H1/H4/D1 bias, the H4
REM  dealing range and the M5 entry were ALL running on the chart
REM  timeframe. Three grids measured something other than the strategy.
REM
REM  The sets are now written as integers and v1.30 refuses to start on
REM  a PERIOD_CURRENT input. This probe checks all of that cheaply:
REM
REM    V3_base   must now differ from its old result (1769.1, 37 trades)
REM    V3_short  must now differ from V3_base, and show 0 long trades
REM    V3_q_m1   must now differ from V3_base
REM
REM  If V3_short still shows long trades, stop and say so - the
REM  diagnostic CSV will name the reason.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_probe

echo.
echo   Compiling SR_HTF_StopEntry_EA v1.30
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

for %%S in (V3_base V3_short V3_q_m1) do (
  echo.
  echo   ---- %%S ----
  call RUNSETS.bat srhtf-grid\sets_srhtf_v3\%%S.set SR_HTF_StopEntry_EA.ex5 M5 2026 nostop
)

echo.
echo ==================================================================
echo   srhtf-grid\results_2026_M5_probe_m1\
echo     report_^<set^>.htm  and  diag_^<set^>.csv
echo.
echo   The diag CSV now carries the RESOLVED inputs at the top. Those
echo   are what the EA actually used - the tester report only echoes
echo   the .set as written, which is why this bug hid for three grids.
echo.
echo   Commit the folder and report back.
echo ==================================================================
set "NOPAUSE="
pause
