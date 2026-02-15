# Reflect Skill Implementation Plan

## Context

LLMs don't learn from user corrections across sessions. Every conversation starts from zero. You correct a button reference, a naming convention, an input validation pattern -- and next session, the same mistake happens again. "I just told you this yesterday."

The fix: a **reflect skill** that analyzes sessions, extracts corrections and successful patterns, and updates skill files so the same mistakes don't repeat. Skills versioned in git so you can see how the system learns over time, roll back regressions, and track evolution.

**Goal:** Correct once, never again.

---

## How It Works (from transcript)

**Two modes:**
1. **Manual:** User calls `/reflect` or `/reflect <skill-name>` after a session. Claude has full conversation context, analyzes it, proposes skill updates, user approves.
2. **Automatic:** Stop hook fires at session end, checks if reflect is enabled, signals Claude to run the reflect flow. Same analysis + approval, just triggered automatically.

**Three controls:** `reflect on`, `reflect off`, `reflect status`

**Signal types:**
- Corrections (user says "actually use X", "never do Y") = signals for new memories
- Approvals (user confirms something worked) = confirmations of existing patterns

**Confidence levels:**
- **HIGH:** Direct user directives -- "never do X", "always use Y", explicit corrections
- **MEDIUM:** Patterns that worked well -- successful approaches, approved solutions
- **LOW:** Observations to review later -- emerging patterns, repeated behaviors

**Approval flow:**
1. Show detected signals
2. Show proposed changes to skill file
3. Show commit message
4. User approves (Y), rejects (N), or edits with natural language
5. Skill file updated, committed to git, pushed

---

## Key Design Principle

**Claude does the analysis. Scripts are just triggers.**

A Claude Code skill is instructions in SKILL.md that tell Claude how to behave. When `/reflect` is called, Claude already has the full conversation in context. It doesn't need a JavaScript module to parse transcripts with regex -- it can read the conversation directly and reason about what happened.

The scripts exist only for:
- Shell entry points (reflect.sh)
- Hook triggers (stop-reflect.sh)
- State management (on/off toggle -- a simple file read)

Everything else -- analyzing signals, classifying confidence, formatting the approval UI, editing skill files, running git commands -- is Claude following SKILL.md instructions using its standard tools (Read, Write, Edit, Bash, AskUserQuestion).

---

## Architecture

```
~/.claude/skills/reflect/
├── SKILL.md              # The brain -- all instructions for Claude
├── scripts/
│   ├── reflect.sh        # Entry point for /reflect command
│   └── stop-reflect.sh   # Stop hook for automatic mode
└── state/
    └── reflect-state.json  # On/off toggle + history
```

That's it. No lib/ directory with 6 JS modules. The complexity lives in SKILL.md where it belongs.

---

## Critical Files

### 1. SKILL.md (~200-300 lines)

This is the most important file. It tells Claude exactly how to run the reflect workflow.

**Frontmatter:**
```yaml
---
name: reflect
version: 1.0.0
description: |
  Analyze Claude Code sessions and update specified skills with learnings
  from user corrections and successful patterns. Supports manual /reflect
  command and automatic mode via stop hook.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
---
```

**Body must cover these sections:**

**A. Invocation modes**
- `/reflect <skill-name>` -- analyze current session, update the named skill
- `/reflect on` -- enable automatic mode (write state file)
- `/reflect off` -- disable automatic mode (write state file)
- `/reflect status` -- show current toggle state and recent history

**B. Session analysis instructions**
- Scan the conversation for two types of signals:
  - **Corrections:** User corrected Claude's behavior (e.g., "actually use X", "not that, do Y", "never generate X on your own")
  - **Approvals/confirmations:** User confirmed something worked well ("perfect", "that's exactly right", "yes, always do it that way")
- Classify each signal by confidence:
  - HIGH: Explicit user directives, corrections with clear alternatives
  - MEDIUM: Patterns that worked, confirmed approaches
  - LOW: Observations, emerging patterns worth noting

**C. Skill update instructions**
- Read the target skill's SKILL.md file
- Determine what changes the learnings imply (new rules, refined instructions, additional examples)
- Do NOT just append a changelog -- integrate learnings into the skill's actual instructions so Claude follows them naturally
- Preserve the skill's existing structure and voice

**D. Approval workflow**
- Present to the user:
  1. **Signals detected** -- list each signal with its confidence level and the conversation context it came from
  2. **Proposed changes** -- show a before/after diff or describe the edits to the skill file
  3. **Commit message** -- a concise summary of what changed and why
- Wait for user response:
  - "Y" or "approve" -- apply changes
  - "N" or "reject" -- cancel, make no changes
  - Any other text -- treat as natural language edits to the proposal, apply the edits, re-present for approval

**E. Git integration**
- After updating the skill file:
  1. Check if the skills directory is a git repo: `git -C <skills-dir> rev-parse --git-dir`
  2. If yes: stage the file, commit with message, push to remote
  3. If no remote or push fails: commit locally, inform user
  4. If not a git repo: skip git, just update the file
- Commit message format: concise description of learnings applied
- Always version skill changes so regressions can be rolled back

**F. State file management**
- State file location: `~/.claude/skills/reflect/state/reflect-state.json`
- Structure:
  ```json
  {
    "enabled": false,
    "lastRun": "2026-02-15T10:30:00Z",
    "history": [
      {
        "timestamp": "2026-02-15T10:30:00Z",
        "skill": "frontend-patterns",
        "signalsDetected": 3,
        "approved": true
      }
    ]
  }
  ```
- `reflect on` sets `enabled: true`
- `reflect off` sets `enabled: false`
- `reflect status` reads and displays state
- After each successful reflect run, append to history

### 2. scripts/reflect.sh (~30 lines)

Simple bash entry point. Only handles the `on`/`off`/`status` subcommands by reading/writing the state file. For the actual `/reflect <skill-name>` flow, this script is not needed -- Claude invokes the skill directly and follows SKILL.md instructions.

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/../state"
STATE_FILE="${STATE_DIR}/reflect-state.json"

mkdir -p "$STATE_DIR"

case "${1:-}" in
  on)
    # Create or update state file to enable
    if [ -f "$STATE_FILE" ]; then
      # Use node for JSON manipulation
      node -e "
        const fs = require('fs');
        const state = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
        state.enabled = true;
        fs.writeFileSync('$STATE_FILE', JSON.stringify(state, null, 2));
      "
    else
      echo '{"enabled": true, "lastRun": null, "history": []}' > "$STATE_FILE"
    fi
    echo "Reflect automatic mode: ON"
    ;;
  off)
    if [ -f "$STATE_FILE" ]; then
      node -e "
        const fs = require('fs');
        const state = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
        state.enabled = false;
        fs.writeFileSync('$STATE_FILE', JSON.stringify(state, null, 2));
      "
    else
      echo '{"enabled": false, "lastRun": null, "history": []}' > "$STATE_FILE"
    fi
    echo "Reflect automatic mode: OFF"
    ;;
  status)
    if [ -f "$STATE_FILE" ]; then
      cat "$STATE_FILE"
    else
      echo '{"enabled": false, "lastRun": null, "history": []}'
    fi
    ;;
  *)
    # For /reflect <skill-name>, output a message for Claude to pick up
    # Claude handles the actual analysis via SKILL.md instructions
    echo "Reflect: analyzing session for skill '${1:-}'"
    ;;
esac
```

### 3. scripts/stop-reflect.sh (~40 lines)

Stop hook script. Runs at session end. Checks if automatic mode is enabled. If so, signals Claude to run the reflect flow.

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/../state/reflect-state.json"

# Check if reflect is enabled
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

ENABLED=$(node -e "
  const fs = require('fs');
  try {
    const state = JSON.parse(fs.readFileSync('$STATE_FILE', 'utf8'));
    console.log(state.enabled ? 'true' : 'false');
  } catch { console.log('false'); }
")

if [ "$ENABLED" != "true" ]; then
  exit 0
fi

# Check transcript has enough messages
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
```

### 4. state/reflect-state.json

Initial state file:

```json
{
  "enabled": false,
  "lastRun": null,
  "history": []
}
```

---

## Hook Configuration

Add to `~/.claude/settings.json` to enable automatic mode:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/reflect/scripts/stop-reflect.sh"
          }
        ]
      }
    ]
  }
}
```

---

## Implementation Sequence

### Phase 1: SKILL.md
Write the skill instructions. This is where all the intelligence lives. Cover:
- Analysis methodology (what signals to look for, how to classify)
- Approval workflow format
- Skill update strategy (integrate, don't just append)
- Git workflow
- State management commands

### Phase 2: Scripts + State
1. Create directory structure
2. Write reflect.sh (on/off/status)
3. Write stop-reflect.sh (stop hook)
4. Create initial reflect-state.json
5. Make scripts executable

### Phase 3: Hook Registration
1. Add stop hook to ~/.claude/settings.json
2. Test that hook fires on session end
3. Test on/off toggle

### Phase 4: End-to-End Testing
1. Run a session, make some corrections
2. Call `/reflect <skill-name>`
3. Verify approval UI appears correctly
4. Approve, verify skill file updated
5. Verify git commit created (if applicable)
6. Test automatic mode end-to-end

---

## Verification

1. `/reflect status` shows disabled initially
2. `/reflect on` enables, `/reflect off` disables
3. `/reflect <skill-name>` after corrections shows approval with detected signals
4. Approving updates the target skill's SKILL.md with integrated learnings
5. Git commit is created if skills directory is a git repo
6. Stop hook triggers automatic reflection at session end when enabled
7. Automatic mode still requires approval before changing anything
8. Natural language edits to proposals work (e.g., "only apply the high confidence ones")

---

## What Changed from Previous Plan

The previous plan had 6 JavaScript modules (confidence-classifier.js, approval-ui.js, skill-parser.js, git-utils.js, analyze-session.js, state-manager.js) totaling ~1300 lines of code. This was over-engineered because:

1. **Claude does the analysis natively.** It reads the conversation, classifies signals, generates proposals. No need for regex-based JavaScript classifiers.
2. **Claude handles the approval UI.** It formats the output and processes user responses. No need for a Node.js approval-ui module.
3. **Claude edits skill files directly.** Using Read/Write/Edit tools. No need for a JavaScript skill-parser.
4. **Claude runs git commands.** Using Bash tool. No need for a JavaScript git-utils wrapper.

The new plan: 1 SKILL.md file (the brain), 2 shell scripts (triggers), 1 state file. Total ~300-400 lines including SKILL.md. Same functionality, fraction of the complexity.
