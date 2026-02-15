#!/bin/bash
# reflect.sh -- Entry point for /reflect command
# Handles on/off/status subcommands via state file manipulation.
# For /reflect <skill-name>, outputs a trigger message for Claude
# to pick up and run the full workflow from SKILL.md instructions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/../state"
STATE_FILE="${STATE_DIR}/reflect-state.json"

mkdir -p "$STATE_DIR"

# Ensure state file exists
if [ ! -f "$STATE_FILE" ]; then
  echo '{"enabled": false, "lastRun": null, "history": []}' > "$STATE_FILE"
fi

case "${1:-}" in
  on)
    node -e "
      const fs = require('fs');
      const state = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
      state.enabled = true;
      fs.writeFileSync('$STATE_FILE', JSON.stringify(state, null, 2));
    "
    >&2 echo "[Reflect] Automatic mode: ON"
    ;;
  off)
    node -e "
      const fs = require('fs');
      const state = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
      state.enabled = false;
      fs.writeFileSync('$STATE_FILE', JSON.stringify(state, null, 2));
    "
    >&2 echo "[Reflect] Automatic mode: OFF"
    ;;
  status)
    node -e "
      const fs = require('fs');
      const state = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
      const enabled = state.enabled ? 'ON' : 'OFF';
      const lastRun = state.lastRun || 'never';
      const runs = state.history ? state.history.length : 0;
      console.error('[Reflect] Status');
      console.error('  Automatic mode: ' + enabled);
      console.error('  Last run: ' + lastRun);
      console.error('  Total runs: ' + runs);
      if (state.history && state.history.length > 0) {
        console.error('  Recent:');
        state.history.slice(-5).forEach(h => {
          console.error('    ' + h.timestamp + ' | ' + h.skill + ' | ' + (h.approved ? 'approved' : 'rejected'));
        });
      }
    "
    ;;
  "")
    >&2 echo "[Reflect] Usage: /reflect <skill-name> | on | off | status"
    ;;
  *)
    >&2 echo "[Reflect] Analyzing session for skill: ${1}"
    ;;
esac
