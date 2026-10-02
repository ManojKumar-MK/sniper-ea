@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SQ_BOOK.bat
REM
REM  17 sets straight out of Practical ICT Strategies 7th Ed, on M3 and
REM  M5 over a full year. 34 passes, fast model, ~70 min.
REM
REM  WHAT THE BOOK CHANGED, AND WHY EACH IS STRICTER
REM
REM   CE (ch5 p58) - consequent encroachment is the 50%% midpoint of an
REM     FVG, "the single most reactive point inside a gap", and price
REM     "often turns from the CE rather than needing to fill the whole
REM     gap". Our HasFVG only asked that a gap existed and had not been
REM     retraced through. The book puts the ENTRY at the midpoint.
REM     -> BK_ce, BK_ce_tight
REM
REM   0.705 (ch12 p131) - the OTE band is 0.62-0.79 "with 0.705 as the
REM     sweet spot at its centre".                 -> BK_ote_sweet
REM
REM   MSS inside the band (ch12 p132, step 4) - "look for a lower-
REM     timeframe MSS or CISD up to confirm". Ours returned true on
REM     price merely being in the zone.            -> BK_ote_shift
REM
REM   Asian range (ch9 p105) - "its high and low become tomorrow's
REM     liquidity ... price often sweeps one side of that range to grab
REM     the resting liquidity, then reverses". That NAMES the level an
REM     N-bar extreme was only guessing at.        -> BK_asiasweep
REM
REM   Silver Bullet (ch15 p149) - three one-hour windows, and outside
REM     them "there is no Silver Bullet - that is the whole point".
REM     NY time: London 3-4 AM, NY AM 10-11 AM, NY PM 2-3 PM.
REM     -> BK_sb_london, BK_sb_nyam, BK_sb_nypm, BK_sb_all3
REM
REM   London Close killzone (Appendix C) - 10 AM-12 PM NY. Canonical,
REM     and never implemented here.                -> BK_lonclose
REM
REM   The book's Asian KILLZONE is 7-10 PM NY; our old sets used
REM   1900-2400, which is the Asian RANGE, not the killzone.
REM     -> BK_asia_book
REM
REM  The killzone strings are NEW YORK time - KzNameNow() converts with
REM  ServerToNY() - so the book's EST tables drop straight in with no
REM  offset arithmetic. That was checked in the code, not assumed.
REM
REM  Reports: sq-grid\results_LAST12M_M3_book_m1\ and ..._M5_book_m1\
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OUTTAG=_book
set FROMDATE=2025.10.01
set TODATE=2026.09.30
set PERIODTAG=LAST12M
set "EA=SniperEntry_Strict_SessionFilter_Telegram_v1.30"

echo.
echo   STEP 1 of 3 - compiling SniperEntry v1.41
echo ==================================================================
call COMPILE.bat %EA%.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\%EA%.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 3 - 17 book sets on M3
echo ==================================================================
call RUNSETS.bat sq-grid\sets_sq_book %EA%.ex5 M3 %PERIODTAG% nostop

echo.
echo   STEP 3 of 3 - 17 book sets on M5
echo ==================================================================
call RUNSETS.bat sq-grid\sets_sq_book %EA%.ex5 M5 %PERIODTAG% nostop

echo.
echo ==================================================================
echo   READ IN THIS ORDER
echo     1. BK_base. It is SQ_model_a, and every book set differs from
echo        it by ONE idea, so anything that does not beat it per trade
echo        is a book rule that does not survive contact with gold.
echo     2. Trade COUNT on the Silver Bullet sets. One hour a day is
echo        tiny - under ~30 trades in a year says nothing whatever the
echo        net, and three of these sets trade one hour a day.
echo     3. BK_ce against BK_base. If CE helps, the FVG test was simply
echo        too loose and every earlier FVG number is suspect.
echo     4. BK_asiasweep. This is the one that replaces a GUESS at where
echo        liquidity sits with a named level. Of everything here it is
echo        the most likely to matter and the most likely to cut the
echo        trade count hard.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
