#!/usr/bin/env bash
# Record today's option chain. macOS / Linux.
#   ./record.sh                 every 5 min, 9 strikes each side, until 15:30
#   ./record.sh 300 9 15:30     same, explicit
# On a Mac, caffeinate keeps it awake for the session - a sleeping laptop
# records nothing, and the gap is not recoverable.
set -uo pipefail
cd "$(dirname "$0")"
INT="${1:-300}"; WIN="${2:-9}"; UNTIL="${3:-15:30}"
PY=".venv_ict/bin/python"
[ -x "$PY" ] || PY="python3"
mkdir -p ict_data
LOG="ict_data/recorder_$(date +%Y%m%d).log"
echo "recording every ${INT}s, ${WIN} strikes each side, until ${UNTIL}" | tee -a "$LOG"
if command -v caffeinate >/dev/null 2>&1; then
  exec caffeinate -i "$PY" -u chain_recorder.py --interval "$INT" --window "$WIN" --until "$UNTIL" 2>&1 | tee -a "$LOG"
fi
exec "$PY" -u chain_recorder.py --interval "$INT" --window "$WIN" --until "$UNTIL" 2>&1 | tee -a "$LOG"
