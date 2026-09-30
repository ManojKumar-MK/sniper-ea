@echo off
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF.bat
REM
REM  SR_HTF_StopEntry_EA - 36 sets x M5 x four years = 144 runs.
REM  No python: wraps RUNSETS.bat, which drives MetaTrader directly.
REM
REM  Compile first:  .\COMPILE.bat SR_HTF_StopEntry_EA.mq5
REM
REM  Test ONE set first - 30 seconds, and it proves the harness before
REM  144 passes:
REM    .\RUNSETS.bat srhtf-grid\sets_srhtf\SR_ctrl.set SR_HTF_StopEntry_EA.ex5 M5 2026
REM ===================================================================
cd /d "%~dp0"
call RUNSETS.bat srhtf-grid\sets_srhtf SR_HTF_StopEntry_EA.ex5 M5 2026 2025 2024 2023
