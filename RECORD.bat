@echo off
setlocal
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RECORD.bat
REM
REM  Records today's option chain until 15:30. Meant to be started by
REM  Task Scheduler at 09:14 every weekday - it exits on its own, so
REM  there is no stop task to configure.
REM
REM  NOTE ON THIS VPS: python here was broken earlier in the project
REM  ("No module named 'encodings'"). RUN_ICT.bat step 0 diagnoses it.
REM  If this exits immediately, run .\RUN_ICT.bat first.
REM ===================================================================
cd /d "%~dp0"
set "PYTHONHOME="
set "PYTHONPATH="
set "INT=%~1"
if "%INT%"=="" set "INT=300"
if not exist ict_data mkdir ict_data
python -c "import encodings" 2>nul
if errorlevel 1 (
  echo   Python cannot import its own stdlib - run .\RUN_ICT.bat for the fix.
  pause & exit /b 1
)
echo   recording every %INT%s until 15:30
python -u chain_recorder.py --interval %INT% --window 9 --until 15:30
echo.
echo   done. Files in ict_data\chains\
pause
