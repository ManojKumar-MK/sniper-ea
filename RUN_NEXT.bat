@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_NEXT.bat
REM
REM  ONE CLICK for everything outstanding. Start it, walk away.
REM  About five hours. Three EAs, in order of what the answer is worth.
REM
REM    STEP 1  SR_HTF break-even variants   10 passes  ~3 h    REAL TICKS
REM    STEP 2  SniperEntry v1.40 gates      46 passes  ~90 min fast model
REM    STEP 3  FvgGold killzones            28 passes  ~35 min fast model
REM
REM  WHY THIS ORDER
REM  Step 1 is the only decisive one. SR_HTF reached its target in 6 of
REM  8 real-tick years and blew the account in 2 - 2019 and 2022 - and
REM  those two deaths share one fingerprint: the win RATE held near 50%%
REM  while the average WIN collapsed to 17 and 13 dollars against
REM  120-dollar losses. That is break-even at 1R stopping trades out at
REM  entry for nothing. Step 1 tests five ways of loosening it, ON THE
REM  TWO DEAD YEARS ONLY, because a variant that does not rescue both
REM  is not worth the two hours of re-checking the six that worked.
REM
REM  Step 2 is the first data the new SniperEntry gates have ever had -
REM  H1 structure, sweep/FVG/OTE, and a chop filter that counts EMA
REM  crosses. Worth knowing, but the trigger underneath it has already
REM  tested as having no edge (median PF 0.990 over ~1,500 runs), so
REM  this is exploratory, not decisive.
REM
REM  Step 3 is a vendor EA's session study. Cheapest, least at stake.
REM
REM  ALL THREE ARE RESUMABLE. Any pass whose report already exists is
REM  skipped, so an interruption - reboot, closed window, anything -
REM  costs nothing. Run this again and it continues where it stopped.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

REM  Suppresses the "press any key" at the end of each step so the three
REM  run back to back. The only pause is at the bottom of this file.
set CHAINED=1

echo.
echo ###################################################################
echo #  STEP 1 of 3 - SR_HTF break-even variants, 2019 + 2022   ~3 h
echo #  REAL TICKS. This is the one that decides something.
echo ###################################################################
call RUN_SRHTF_BE.bat "%MT5DIR%"

echo.
echo ###################################################################
echo #  STEP 2 of 3 - SniperEntry v1.40, 23 sets, M3+M5, 1 year ~90 min
echo ###################################################################
call RUN_SQ_1Y.bat "%MT5DIR%"

echo.
echo ###################################################################
echo #  STEP 3 of 3 - FvgGold killzones, 28 sets, 6 months      ~35 min
echo ###################################################################
call RUN_FVG_KZ.bat "%MT5DIR%"

echo.
echo ===================================================================
echo   ALL DONE. Commit everything:
echo.
echo     git add -A ^&^& git commit -m "BE variants + sq-grid + fvg killzones" ^&^& git push
echo.
echo   WHAT TO LOOK AT FIRST
echo     STEP 1: in srhtf-grid\results_2019_M5_be and ..._2022_M5_be,
echo       net ~ +2500 is a pass and ~ -1500 is a dead account.
echo       BE_base MUST come back near -1500 in both - it is the
echo       control, and if it does not the harness changed and nothing
echo       else is comparable. A variant is only interesting if it
echo       passes BOTH years.
echo     STEP 2: the SIGNAL TALLY line at the end of each pass. A gate
echo       showing 0 rejections did nothing, and that set is just
echo       SQ_base with extra inputs.
echo     STEP 3: FKZ_nokz first. If no windowed set beats trading every
echo       hour, the killzone idea is worth nothing on that EA.
echo ===================================================================
set "CHAINED="
pause
