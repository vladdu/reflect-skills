#!/bin/bash
# stop-reflect.sh -- Stop hook for automatic reflect mode.
# Runs at session end. Checks if reflect is enabled.
# If enabled and session is long enough, signals Claude to
# run the reflect workflow.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/../state/reflect-state.json"

# Check if state file exists
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Check if reflect is enabled
ENABLED=$(node -e "
  const fs = require('fs');
  try {
    const state = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
    console.log(state.enabled ? 'true' : 'false');
  } catch { console.log('false'); }
" 2>/dev/null)

if [ "$ENABLED" != "true" ]; then
  exit 0
fi

# Check transcript exists and has enough messages
TRANSCRIPT_PATH="${CLAUDE_TRANSCRIPT_PATH:-}"
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

MSG_COUNT=$(grep -c '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null || echo 0)
if [ "$MSG_COUNT" -lt 5 ]; then
  exit 0
fi

# Signal to Claude that reflect should run
>&2 echo "[Reflect] Session has ${MSG_COUNT} messages -- running automatic reflection"
>&2 echo "[Reflect] Review and approve skill updates before they are applied"
exit 0
