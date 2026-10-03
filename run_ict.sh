#!/usr/bin/env bash
# One click on macOS / Linux. Windows VPS uses RUN_ICT.bat.
#   ./run_ict.sh              demo + backtest + grid, 120 days
#   ./run_ict.sh 250          250 days
#   ./run_ict.sh 120 demo     stop after the demo
set -uo pipefail
cd "$(dirname "$0")"
DAYS="${1:-120}"
ONLY="${2:-}"
VENV=".venv_ict"

# A venv keeps smartapi-python and its pins out of the system python, which on
# a shared machine is the difference between this working and breaking
# something else.
if [ ! -d "$VENV" ]; then
  echo "== creating $VENV"
  python3 -m venv "$VENV" || { echo "python3 -m venv failed"; exit 1; }
fi
PY="$VENV/bin/python"
"$PY" -c "import pandas, numpy, requests" 2>/dev/null || {
  echo "== installing packages"
  "$PY" -m pip install -q --upgrade pip
  "$PY" -m pip install -q pandas numpy requests pyotp smartapi-python logzero websocket-client \
    || { echo "pip install failed - read the error above"; exit 1; }
}
echo "== $("$PY" -V)"

echo; echo "=== STEP 1/3  demo (synthetic data, no API) ==="
"$PY" -u ict_options.py demo || { echo "engine failed on synthetic data - fix this first"; exit 1; }
[ "$ONLY" = "demo" ] && { echo "stopping after demo as asked"; exit 0; }

if [ ! -f .env ]; then
  echo
  echo "No .env - steps 2 and 3 need Angel One credentials."
  echo "  cp .env.example .env     then fill it in"
  echo "Offline alternative, no credentials:"
  echo "  $PY ict_options.py backtest --csv-dir ./csv"
  exit 0
fi

echo; echo "=== STEP 2/3  backtest, $DAYS days ==="
"$PY" -u ict_options.py backtest --days "$DAYS" || exit 1

echo; echo "=== STEP 3/3  grid, 30% of sessions held out ==="
"$PY" -u ict_options.py grid --days "$DAYS" --oos 0.3 || exit 1

echo
echo "Done. Results in ./ict_data/"
echo "  Read: refused-by-caps, then the WORST month, then the oos_ columns only."
