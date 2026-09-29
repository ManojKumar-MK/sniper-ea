@echo off
REM ===================================================================
REM  SINGLE CLICK: compile -> check -> run.
REM
REM  1. COMPILE.bat       builds GOLD_ORB + GridMaster into the tester
REM  2. CHECK_SETUP.bat   seven pre-flight checks
REM  3. RUN_ORB_GMP.bat   156 backtests across four years
REM
REM  Each step pauses, so you can stop if something is wrong rather
REM  than discovering it 80 runs later.
REM ===================================================================
cd /d "%~dp0"
echo.
echo   STEP 1 of 3 - compiling
call COMPILE.bat
echo.
echo   STEP 2 of 3 - checking the setup
call CHECK_SETUP.bat
echo.
echo   STEP 3 of 3 - running the grids
call RUN_ORB_GMP.bat
