@echo off
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_SRHTF_4Y.bat
REM
REM  The four-year version: 36 sets x M5 x 2023-2026 = 144 runs.
REM  Run this AFTER RUN_SRHTF.bat has shown which sets are worth it -
REM  2026 alone is a ranking, four years is the test.
REM ===================================================================
cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
call RUNSETS.bat srhtf-grid\sets_srhtf SR_HTF_StopEntry_EA.ex5 M5 2026 2025 2024 2023 nostop
