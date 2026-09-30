@echo off
REM ===================================================================
REM  IN POWERSHELL prefix with .\   ->   .\RUN_GRID_NOPY.bat
REM
REM  SniperGrid, 25 sets x M5 x four years = 100 runs, WITHOUT PYTHON.
REM  Wraps RUNSETS.bat so there is still one thing to double-click.
REM
REM  Compile first:  .\COMPILE.bat SniperGrid_v1.00.mq5
REM ===================================================================
cd /d "%~dp0"
call RUNSETS.bat grid-grid\sets_grid SniperGrid_v1.00.ex5 M5 2026 2025 2024 2023
