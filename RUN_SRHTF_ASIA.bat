@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_ASIA.bat
REM
REM  4 sets x 2019-2026 on REAL TICKS. 32 passes, ~10 hours. Overnight.
REM
REM  WHY
REM  The SniperEntry book grid produced one clear winner: replacing the
REM  N-bar extreme with the PRIOR ASIAN RANGE as the liquidity pool.
REM  Best net AND best per-trade on BOTH M3 and M5 - +14%% and +41%% per
REM  trade - and the tally confirmed it was binding, not passing
REM  everything through.
REM
REM  SR_HTF's FindBullSetup had exactly the same weakness: it swept
REM  "the lowest low of the last 20 bars", which is a guess at where
REM  stops are resting. The Asian high and low are a named level.
REM
REM  This tests it on the EA that actually has a record - 6 of 8
REM  real-tick years reaching target - rather than on the EMA cross.
REM
REM    ASIA_off      control, identical to PASS_s1_tgt10
REM    ASIA_on       Asian range 00-05 GMT as the pool
REM    ASIA_on_0_3   the tighter 00-03 killzone window instead
REM    ASIA_on_ag1   Asian pool + InpMinAgree=1, since a named level may
REM                  carry its own selectivity and need less HTF gating
REM
REM  JUDGE IT THE SAME WAY
REM    net ~ +2500  target reached        net ~ -1500  account dead
REM  ASIA_off must reproduce 6 passes and 2 deaths (2019 and 2022). If
REM  it does not, something changed and nothing else is comparable.
REM
REM  The bar to beat is 6/8. Anything that turns 2019 or 2022 into a
REM  pass without breaking the other six is the first real improvement
REM  this strategy has had.
REM ===================================================================

cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
if not defined MT5DIR set MT5DIR=C:\MT5-Tester
if not "%~1"=="" set MT5DIR=%~1

set NOPAUSE=1
set MODEL=4
set OUTTAG=_asia

echo.
echo   Compiling SR_HTF_StopEntry_EA v1.60
echo ==================================================================
call COMPILE.bat SR_HTF_StopEntry_EA.mq5 "%MT5DIR%"
if not exist "%MT5DIR%\MQL5\Experts\SR_HTF_StopEntry_EA.ex5" (
  echo.  & echo   No .ex5 - stopping. & echo.
  set "NOPAUSE=" & pause & exit /b 1
)

echo.
echo   4 sets x 8 years, real ticks
echo ==================================================================
call RUNSETS.bat srhtf-grid\sets_srhtf_asia SR_HTF_StopEntry_EA.ex5 M5 2019 2020 2021 2022 2023 2024 2025 2026 nostop

echo.
echo ==================================================================
echo   Commit all eight results_^<year^>_M5_asia folders.
echo ==================================================================
set "NOPAUSE="
if not defined CHAINED pause
