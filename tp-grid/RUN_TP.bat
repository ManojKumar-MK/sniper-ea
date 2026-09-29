@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\  -  .\RUN_TP.bat
REM
REM  Exit shape x quality filter, on M5, from the start of this year.
REM      7 exits  x  6 filter sets  =  42 runs
REM
REM  THE EXITS
REM    tp5        ride to TP5, stop NEVER moves
REM    tp5trail   the current behaviour: BE at TP1, then SL to the
REM               previous target at every level
REM    lazy2/3/4  stop does not move until TP2 / TP3 / TP4 is reached,
REM               then goes one level behind. lazy3 is "SL to TP2 only
REM               after TP3", which is what was asked for
REM    runner3    lazy3 and let it run past TP5 instead of booking
REM    partials3  book 20%% a level and trail lazily
REM
REM  THE FILTERS
REM    qfoff  vwap  cool  vc  trend  dflt
REM
REM  Guards are OFF on purpose. With them on, a bad stretch halts the EA
REM  partway and the comparison measures when the halt fired rather than
REM  what the exit did.
REM
REM  COMPILE FIRST - InpTrailStartTP is a NEW input and an older .ex5
REM  does not have it. MT5 ignores unknown keys silently, so every lazy
REM  set would run as tp5trail and the whole grid would look flat.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="

if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1
set EXPERT=SniperTurtle_KZ_v1.00.ex5

if not exist "%MT5DIR%\MQL5\Experts\%EXPERT%" (
  echo. & echo   %EXPERT% is not in %MT5DIR%\MQL5\Experts\ & echo.
  pause & exit /b 1
)

echo.
echo ===== 2026 to date  M5  =====
python run_backtests.py --sets sets_tp --out results_tp_2026_M5 --period M5 ^
  --from 2026.01.01 --to 2026.12.31 --skip-done --deposit 25000 --symbol XAUUSD ^
  --expert "%EXPERT%" --terminal "%MT5DIR%\terminal64.exe" --data-dir "%MT5DIR%" --portable

echo.
python run_backtests.py --merge-all
echo.
echo ===== done =====
echo   Compare TP_tp5trail_* against TP_lazy3_* on the SAME filter - that is
echo   the trail question with everything else held still.
echo.
echo   One year is a ranking, not a verdict. 2026 is also the year every
echo   config in this repo was tuned on, and several that looked good on it
echo   did not survive 2023-2025. Re-run the winner across four years before
echo   trusting it: --from 2023.01.01 in the line above.
echo.
pause
