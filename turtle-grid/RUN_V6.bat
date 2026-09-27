@echo off
setlocal
REM ===================================================================
REM  v6 - every killzone combination. 14 sets x M15/M5 x 4 years.
REM
REM  Seven combinations (all-off would trade nothing), on two bases:
REM
REM    KZ_*    no prop guards. The CLEAN read on which killzone carries
REM            the edge - with guards on, a bad year halts the EA early
REM            and the comparison measures the halt, not the killzone.
REM    KZFN_*  the FundedNext 25k guards. Which combination actually
REM            passes the challenge.
REM
REM  Read KZ_* to learn, KZFN_* to decide. KZ_all and KZFN_all are the
REM  controls - they are V5_notrail and V5_fn_r050 unchanged.
REM
REM  COMPILE FIRST (F7) and CLOSE the tester terminal before running.
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
  for %%P in (M15 M5) do (
    echo.
    echo ===== %%Y  %%P =====
    python run_backtests.py --sets sets_v6 --out results_v6_%%Y_%%P --period %%P ^
      --from %%Y.01.01 --to %%Y.12.31 %BASE%
  )
)

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   M15 is the decided timeframe; M5 is only there as a robustness check.
echo   A killzone that only works in 2025 and 2026 is a killzone that was
echo   selected on 2025 and 2026 - weight 2023 and 2024 more heavily.
pause
