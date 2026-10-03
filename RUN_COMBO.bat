@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_COMBO.bat
REM
REM  THE COMBINATION SEARCH. 960 combinations, genetic, TWO YEARS
REM  (2025.01.01 - 2026.09.30), last third held out. All CPU cores.
REM
REM  Expect 2-6 hours. MT5's genetic algorithm stops when it stops
REM  improving, so it does not run all 960 - a complete enumeration
REM  would be ~54 core-hours.
REM
REM  WHY ONLY SIX PARAMETERS
REM  The full space was ten parameters and 1.24 MILLION combinations.
REM  On two years of M5 that is days. These six are the ones eight
REM  years of real-tick evidence actually points at; everything else
REM  is pinned at PASS_s1_tgt10, the configuration that reached target
REM  in 6 of 8 years.
REM
REM    InpBE_R          0.5-2.5   THE prime suspect. 2019 and 2022 both
REM                               died with a ~50%% win rate and average
REM                               WINS of 17 and 13 dollars against 120
REM                               dollar losses - break-even at 1R
REM                               cutting winners to nothing.
REM    InpMinAgree      1-3       every set that passed 6/8 uses 2
REM    InpTPRMult       0-3       target R, separate from the gate
REM    InpMinRR         1.5-3.0   the gate itself
REM    InpPartialPct    0 / 50    scale out or do not
REM    InpTrailATRMult  0 / 1.5   trail the remainder or do not
REM
REM  WHAT MAKES IT A SEARCH AND NOT NOISE MINING
REM    CRITERION=6  the EA's own OnTester(), which scores what the
REM                 ACCOUNT experiences: -1000 for hitting the static
REM                 floor, -2000 for taking no trades, +1000 and up for
REM                 reaching target with a bonus for arriving sooner.
REM                 MT5's built-ins rank on profit or drawdown and none
REM                 of them know what a blown challenge is.
REM    FORWARD=2    the last third is held out and never optimised on.
REM                 With 960 combinations the best in-sample result is
REM                 probably the luckiest one.
REM    MODEL=1      a search cannot run on real ticks. SURVIVORS MUST
REM                 be re-run on MODEL=4 before they mean anything.
REM
REM  Reports: the tester's Optimization Results tab (an optimisation
REM  does not write per-pass .htm files).
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=1
set OPTIMIZE=2
set CRITERION=6
set FORWARD=2
set OUTTAG=_combo
set FROMDATE=2025.01.01
set TODATE=2026.09.30
set PERIODTAG=COMBO2Y

echo.
echo   STEP 1 of 2 - compiling SR_HTF_StopEntry_EA
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   STEP 2 of 2 - genetic search, 960 combinations, 2 years
echo ==================================================================
echo   Every core will be busy for hours. That is the optimiser
echo   working, not a hang. Watch the tester's progress bar.
echo.
call RUNSETS.bat srhtf-grid\sets_srhtf_combo SR_HTF_StopEntry_EA.ex5 M5 %PERIODTAG% nostop

echo.
echo ==================================================================
echo   HOW TO READ IT
echo   Strategy Tester -^> Optimization Results -^> switch to FORWARD,
echo   sort by the Custom column, descending.
echo.
echo     Custom  +1000 and up = target reached (higher = sooner)
echo             -1000        = static floor hit, account dead
echo             -2000        = took no trades at all
echo.
echo   1. Read the FORWARD tab, not Back. Back is the fitted one.
echo   2. Take a CLUSTER, not a spike. Neighbouring values of BE_R and
echo      MinAgree scoring similarly is a plateau and means something.
echo      One isolated winner is what V3_ema_50_100 looked like, and it
echo      went 0 for 23 out of sample.
echo   3. Then re-run the top 4-6 on REAL TICKS year by year and judge
echo      on the WORST year. The bar is PASS_s1_tgt10 at 6 of 8.
echo.
echo   Right-click the results grid -^> Export, commit the file, and I
echo   will pick the clusters.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
