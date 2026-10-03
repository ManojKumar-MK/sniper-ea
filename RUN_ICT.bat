@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_ICT.bat
REM
REM  ONE CLICK for ict_options.py - the INDIAN STOCK OPTIONS system.
REM  Nothing to do with the gold EAs: NSE equities for the signal, NFO
REM  OPTSTK contracts for execution, Angel One SmartAPI.
REM
REM  It runs in order, and stops at the first thing that is wrong:
REM    0  python works, and can import its own stdlib
REM    1  the packages are installed
REM    2  demo      - synthetic data, proves the engine runs
REM    3  backtest  - real 5m history, per-setup + portfolio report
REM    4  grid      - 162 combinations with 30%% held out
REM
REM  Steps 3 and 4 need the Angel One credentials. Without them it
REM  stops after the demo and tells you what is missing - that is a
REM  pass, not a failure.
REM
REM  WARNING ABOUT THIS VPS SPECIFICALLY
REM  Python on the tester VPS was broken earlier in this project -
REM  "ModuleNotFoundError: No module named 'encodings'" with both
REM  PYTHONHOME and PYTHONPATH empty, which is a damaged install, not a
REM  stale variable. That is why the MT5 runners are pure batch. This
REM  script CANNOT be: ict_options.py is Python. Step 0 checks for
REM  exactly that failure and tells you how to fix it.
REM ===================================================================

cd /d "%~dp0"
set "PY=python"
set "DAYS=120"
if not "%~1"=="" set "DAYS=%~1"

echo.
echo ==================================================================
echo   STEP 0 of 4 - is python usable
echo ==================================================================
where %PY% >nul 2>&1
if errorlevel 1 (
  set "PY=py"
  where !PY! >nul 2>&1
  if errorlevel 1 (
    echo   No python on PATH. Install Python 3.10+ and tick
    echo   "Add python.exe to PATH" during setup.
    goto :fail
  )
)
%PY% -c "import encodings, json, csv, math" 2>nul
if errorlevel 1 (
  echo   Python is on PATH but cannot import its own standard library.
  echo   This is the damaged install seen on this VPS before, not a
  echo   stale environment variable.
  echo.
  echo   Fix: uninstall Python from Add/Remove Programs, delete any
  echo   leftover C:\Python* and %%LOCALAPPDATA%%\Programs\Python,
  echo   then reinstall from python.org with "Add to PATH" ticked.
  echo.
  echo   Check PYTHONHOME / PYTHONPATH are empty:
  echo       echo %%PYTHONHOME%%    ^&    echo %%PYTHONPATH%%
  goto :fail
)
for /f "delims=" %%V in ('%PY% -V 2^>^&1') do echo   OK  %%V

echo.
echo ==================================================================
echo   STEP 1 of 4 - packages
echo ==================================================================
%PY% -c "import pandas, numpy, requests" 2>nul
if errorlevel 1 (
  echo   Installing pandas numpy requests pyotp smartapi-python ...
  %PY% -m pip install --quiet --upgrade pip
  %PY% -m pip install --quiet pandas numpy requests pyotp smartapi-python logzero websocket-client
  %PY% -c "import pandas, numpy, requests" 2>nul
  if errorlevel 1 (
    echo   pip install did not take. Run it by hand and read the error:
    echo       %PY% -m pip install pandas numpy requests pyotp smartapi-python
    goto :fail
  )
)
echo   OK  pandas, numpy, requests present
%PY% -c "import SmartApi" 2>nul && (echo   OK  smartapi-python present) || (echo   NOTE smartapi-python missing - demo and --csv-dir still work)

echo.
echo ==================================================================
echo   STEP 2 of 4 - demo (synthetic data, no API)
echo ==================================================================
%PY% -u ict_options.py demo
if errorlevel 1 (
  echo   The engine itself failed on synthetic data. Nothing else will
  echo   work until this does - the error above is the real one.
  goto :fail
)

echo.
echo ==================================================================
echo   STEP 3 of 4 - backtest on real history (%DAYS% days)
echo ==================================================================
if "%ANGEL_API_KEY%"=="" goto :nocreds
if "%ANGEL_CLIENT%"=="" goto :nocreds
if "%ANGEL_PIN%"=="" goto :nocreds
if "%ANGEL_TOTP_SECRET%"=="" goto :nocreds

%PY% -u ict_options.py backtest --days %DAYS%
if errorlevel 1 ( echo   backtest failed - see above. & goto :fail )

echo.
echo ==================================================================
echo   STEP 4 of 4 - parameter grid, 30%% of sessions held out
echo ==================================================================
echo   162 combinations. On 25 symbols expect ~30 min. Output streams
echo   below with an ETA per combination.
echo.
%PY% -u ict_options.py grid --days %DAYS% --oos 0.3
if errorlevel 1 ( echo   grid failed - see above. & goto :fail )

echo.
echo ==================================================================
echo   DONE. Results in .\ict_data\
echo     backtest_*.csv   every setup: entry, stop, target, R, why
echo     grid_*.csv       every combination, in-sample AND out-of-sample
echo.
echo   READ IT IN THIS ORDER
echo     1. "refused by caps" in the PORTFOLIO block. If that is large,
echo        the per-setup stats describe a system you cannot run.
echo     2. The WORST month/year, not the total.
echo     3. In the grid, the oos_ columns ONLY. The best in-sample table
echo        is printed under it so you can watch those combinations fail.
echo     4. How many of 162 were positive out of sample. Near half means
echo        the grid found noise, not an edge.
echo.
echo   Then paper for a full week before anything goes live:
echo       %PY% ict_options.py paper
echo ==================================================================
goto :done

:nocreds
echo   Angel One credentials are not set, so steps 3 and 4 are skipped.
echo   The engine passed the demo, which is as far as we can get here.
echo.
echo   setx ANGEL_API_KEY      your_key
echo   setx ANGEL_CLIENT       your_client_id
echo   setx ANGEL_PIN          your_pin
echo   setx ANGEL_TOTP_SECRET  your_totp_secret
echo   setx TG_TOKEN           your_bot_token
echo   setx TG_CHAT            your_chat_id
echo.
echo   Open a NEW terminal after setx, then run this again.
echo   The VPS static IP must also be whitelisted on the SmartAPI app.
echo   Offline alternative, no credentials needed:
echo       %PY% ict_options.py backtest --csv-dir .\csv
goto :done

:fail
echo.
echo   STOPPED. Nothing further was run.
pause
exit /b 1

:done
echo.
pause
