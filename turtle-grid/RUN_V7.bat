@echo off
setlocal
REM ===================================================================
REM  v7 - the COMPLETE filter space on the 50/100 signal.
REM
REM  All 128 on/off combinations of the seven quality conditions,
REM  M5 only, four years = 512 backtests.
REM
REM  Why it is needed: the filters were characterised on the 9/21
REM  signal - VWAP best, ADX and EMA-separation worst - and that
REM  conclusion was then carried onto 50/100 without ever being
REM  retested. On the 50/100 signal only TWO of the 128 combinations
REM  have ever been run. This closes that.
REM
REM  Guards are OFF here on purpose. With them on a bad year halts the
REM  EA partway through and the comparison measures the halt rather
REM  than the filter. Winners get re-run with guards afterwards.
REM
REM  LONG RUN - 512 passes. --skip-done makes it resumable: if it is
REM  interrupted, rerun this file and it carries on.
REM ===================================================================

cd /d "%~dp0"
set MT5DIR=C:\MT5-Tester
set EXPERT=SniperTurtle_KZ_v1.00.ex5
set BASE=--skip-done --deposit 25000 --symbol XAUUSD ^
 --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  pause & exit /b 1
)

for %%Y in (2026 2025 2024 2023) do (
  echo.
  echo ===== %%Y  M5 =====
  python run_backtests.py --sets sets_v7 --out results_v7_%%Y_M5 --period M5 ^
    --from %%Y.01.01 --to %%Y.12.31 %BASE%
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   128 combinations x 4 years is a LOT of chances to look good. The rule
echo   set before the run: a combination counts only if it is profitable in
echo   ALL FOUR years. By chance alone roughly 8 of 128 will manage that, so
echo   even a clean sweep needs the plateau check - do its NEIGHBOURS (the
echo   same set plus or minus one filter) also work?
pause
