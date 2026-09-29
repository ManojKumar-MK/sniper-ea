@echo off
REM ===================================================================
REM  IN POWERSHELL prefix with .\  -  PowerShell will not run a script from
REM  the current directory otherwise:   .\GO.bat
REM  In cmd.exe, or by double-clicking, the bare name works.
REM
REM  SINGLE CLICK: compile -> check -> run.
REM
REM  1. COMPILE.bat       builds GOLD_ORB + GridMaster into the tester
REM  2. CHECK_SETUP.bat   seven pre-flight checks
REM  3. RUN_ORB_GMP.bat   156 backtests across four years
REM
REM  Each step pauses, so you can stop if something is wrong rather
REM  than discovering it 80 runs later.
REM  Optional: pass the MT5 folder, e.g.  .\GO.bat "D:\MT5-Tester"
REM ===================================================================
cd /d "%~dp0"

REM  ---------------------------------------------------------------
REM  Clear PYTHONHOME / PYTHONPATH for this window only.
REM  A stale PYTHONHOME makes python.exe start and then die with
REM      Could not find platform independent libraries <prefix>
REM      ModuleNotFoundError: No module named 'encodings'
REM  because it looks for its standard library where that variable
REM  points instead of beside the exe. Clearing them here affects only
REM  this script's environment, never the system.
REM  ---------------------------------------------------------------
set "PYTHONHOME="
set "PYTHONPATH="
echo.
echo   STEP 1 of 3 - compiling
call COMPILE.bat %*
echo.
echo   STEP 2 of 3 - checking the setup
call CHECK_SETUP.bat %*
echo.
echo   STEP 3 of 3 - running the grids
call RUN_ORB_GMP.bat %*
