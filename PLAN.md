# Reflect Skill Implementation Plan

## Context

**Why this change is needed:**

Current LLMs, including Claude, don't learn from user corrections across sessions. Every conversation starts from zero. Users repeatedly correct the same mistakes—for instance, correcting a specific button reference or coding pattern—but these corrections aren't retained. By the next session, the same mistakes reoccur, leading to frustration and wasted time.

**The problem:**
- No memory mechanism for user preferences and corrections
- Skills don't improve from session learnings
- Users repeat themselves across sessions
- "I told you this yesterday" syndrome

**The solution:**

A **reflect skill** that analyzes Claude Code sessions, detects learnings from user corrections and successful patterns, and updates specified skill files with confidence-labeled improvements. This enables "correct once, never again" behavior through continuous skill improvement.

**User requirements:**
1. Manual `/reflect <skill-name>` command to trigger updates after a session
2. Automatic mode that detects learnings at session end but requires approval
3. Control commands: `reflect on`, `reflect off`, `reflect status`
4. Confidence-based classification (high/medium/low)
5. Review/approval UI showing detected signals and proposed changes
6. Natural language editing of proposals before approval
7. Git integration: auto-commit and push skill updates if ~/.claude/skills/ is a git repo

---

## Recommended Approach

Create a new standalone **reflect** skill in `~/.claude/skills/reflect/` that follows existing skill patterns (humanizer, continuous-learning) and integrates with the Claude Code hook system.

### Architecture

**Modular design with focused responsibilities:**

```
~/.claude/skills/reflect/
├── SKILL.md                      # Skill definition for Claude
├── reflect.sh                    # Entry point (bash wrapper)
├── config.json                   # Configuration options
├── lib/
│   ├── analyze-session.js       # Main orchestrator
│   ├── confidence-classifier.js # Pattern detection with confidence levels
│   ├── skill-parser.js          # SKILL.md parsing and updating
│   ├── git-utils.js             # Git operations (add, commit, push)
│   ├── approval-ui.js           # Interactive review workflow
│   └── state-manager.js         # On/off toggle and history
├── state/
│   └── reflect-state.json       # State file (on/off, history)
└── hooks/
    └── stop-reflect.js          # Stop hook for automatic mode
```

### Data Flow

**Manual mode:** `/reflect <skill-name>`
1. reflect.sh invokes lib/analyze-session.js with skill name
2. Read transcript from CLAUDE_TRANSCRIPT_PATH env var
3. confidence-classifier.js analyzes conversation and extracts learnings by confidence level
4. approval-ui.js presents formatted review (signals → proposed changes → commit message)
5. User approves, rejects, or edits with natural language
6. skill-parser.js updates SKILL.md file
7. git-utils.js commits and pushes (if ~/.claude/skills/ is git repo)

**Automatic mode:** Stop hook trigger
1. Session ends → Stop hook fires
2. Check state/reflect-state.json (is reflect enabled?)
3. If enabled: quick scan for learning signals (user corrections, error resolutions)
4. If signals detected: show notification to Claude
5. Require approval before proceeding with same flow as manual mode

### Confidence Level Classification

**HIGH confidence** - Direct user corrections:
- "Actually, use X instead of Y"
- "Not X, do Y"
- "Never do X" or "Always do Y"
- Explicit rejections with alternatives

**MEDIUM confidence** - Successful patterns:
- Error → Solution that worked
- User approval after Claude's solution ("perfect", "works great")
- Repeated successful approaches

**LOW confidence** - Observations to review later:
- Tools that worked well (high usage count)
- Repeated questions (may indicate unclear instructions)
- Emerging patterns worth noting

### Git Integration

**Strategy:** Required for skills directory (auto-commit if git repo exists)

1. Check if `~/.claude/skills/` is a git repository
2. If YES:
   - Stage updated skill file: `git add <skill-file>`
   - Commit with formatted message + Co-Authored-By line
   - Push to remote (if configured)
   - Handle errors gracefully: no remote = commit locally, network error = commit locally
3. If NO: Just update skill file, skip git operations silently

**Error handling:**
- Not a git repo: Skip git, just update file
- No remote configured: Commit locally, notify user
- Network errors: Commit locally, suggest manual push
- Merge conflicts: Abort and notify user

---

## Critical Files to Create

### 1. **lib/confidence-classifier.js** (~300 lines)

**Purpose:** Core pattern detection logic

**Key methods:**
- `classifyLearnings(transcript, skillName)` - Returns `{ high: [], medium: [], low: [] }`
- `detectUserCorrections(messages)` - Detects HIGH confidence signals
  - Patterns: "actually", "instead", "not X do Y", "never", "always"
- `detectSuccessPatterns(messages)` - Detects MEDIUM confidence signals
  - Error → Solution sequences
  - Approval indicators ("works", "perfect", "great")
- `detectObservations(messages)` - Detects LOW confidence signals
  - Tool usage patterns
  - Repeated questions

**References existing code:**
- Parse JSONL transcript format (see evaluate-session.js:60)
- Use regex matching for pattern detection

### 2. **lib/analyze-session.js** (~200 lines)

**Purpose:** Main orchestrator that coordinates the workflow

**Key responsibilities:**
- Read CLAUDE_TRANSCRIPT_PATH from environment
- Load config from config.json
- Invoke confidence-classifier to analyze session
- Generate proposed changes (markdown diff format)
- Generate commit message from learnings
- Invoke approval-ui for review
- Coordinate skill update and git operations
- Record run in state manager

**Follows pattern:** evaluate-session.js structure (lines 24-73)

### 3. **lib/approval-ui.js** (~250 lines)

**Purpose:** Interactive review workflow

**Key methods:**
- `presentApproval(analysis, skillName, proposedChanges, commitMessage)`
  - Formats approval prompt with:
    - Signals detected (organized by confidence level)
    - Proposed changes (markdown diff)
    - Commit message preview
    - Approval options (Y/N/natural language edits)
  - Outputs to stderr so Claude sees it (use `log()` from utils.js)
- `processApprovalResponse(userResponse)` - Parse user input
  - "Y"/"approve" → proceed
  - "N"/"reject" → cancel
  - Natural language → extract edit instructions
- `parseNaturalLanguageEdits(userResponse)` - Extract edit operations
  - "Remove the first change"
  - "Reword commit message to..."
  - "Only apply high confidence changes"

### 4. **lib/skill-parser.js** (~200 lines)

**Purpose:** Parse and update SKILL.md files

**Key methods:**
- `parseSkill(skillPath)` - Split frontmatter and body
  - Handle YAML frontmatter (see humanizer/SKILL.md:1-18)
  - Return structured data: `{ frontmatter, body, raw }`
- `updateSkill(skillPath, learnings, analysis)`
  - Append learnings to "## Learnings" section
  - Organize by confidence level and timestamp
  - Preserve existing structure
- `writeSkill(skillPath, content)` - Write updated file

**Format for learnings section:**
```markdown
## Learnings

### HIGH - 2026-02-15

- Always reference the primary CTA button component, not inline styles

### MEDIUM - 2026-02-15

- error_resolution: Fixed TypeScript strict null check by using optional chaining
```

### 5. **lib/git-utils.js** (~150 lines)

**Purpose:** Git operations with error handling

**Key methods:**
- `isGitRepo()` - Check if directory is git repo (use utils.js pattern)
- `getStatus()` - Get git status for modified files
- `getDiff(skillFile)` - Show diff for skill file
- `addFile(skillFile)` - Stage file: `git add`
- `commit(message)` - Commit with formatted message + Co-Authored-By line
- `push()` - Push to remote (detect branch, handle errors)
- `commitAndPush(skillFile, commitMessage)` - Full workflow

**Error handling:**
- Try/catch around all git operations
- Return `{ success: boolean, error?: string }` objects
- Silent failures for non-critical operations

**References:** utils.js:274-298 for git patterns

### 6. **lib/state-manager.js** (~100 lines)

**Purpose:** Manage on/off toggle and run history

**State file structure:**
```json
{
  "enabled": false,
  "lastRun": null,
  "config": {
    "minSessionLength": 5,
    "requireApproval": true,
    "autoCommit": true,
    "autoPush": true
  },
  "history": [
    {
      "timestamp": "2026-02-15T10:30:00Z",
      "skill": "frontend-patterns",
      "learnings": 3,
      "approved": true
    }
  ]
}
```

**Key methods:**
- `readState()` / `writeState(state)`
- `enable()` / `disable()` - Toggle automatic mode
- `getStatus()` - Return current state + recent history
- `recordRun(skillName, learnings, approved)` - Track runs

### 7. **hooks/stop-reflect.js** (~80 lines)

**Purpose:** Stop hook for automatic mode

**Workflow:**
1. Check if reflect is enabled (read state file)
2. If disabled: exit silently
3. Get CLAUDE_TRANSCRIPT_PATH from environment
4. Count user messages (skip short sessions < 5 messages)
5. Quick scan for learning signals:
   - User corrections ("actually", "instead")
   - Error resolutions
6. If signals found: log notification to stderr
7. Exit (Claude will see notification and can invoke approval workflow)

**References:** evaluate-session.js pattern (lines 24-73)

### 8. **SKILL.md** (~100 lines)

**Purpose:** Skill definition for Claude

**Frontmatter:**
```yaml
---
name: reflect
version: 1.0.0
description: |
  Analyze Claude Code sessions and update specified skills with learnings
  from user corrections and successful patterns. Supports manual invocation
  and automatic mode with approval.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Bash
  - AskUserQuestion
---
```

**Body sections:**
- How to analyze sessions for learnings
- Confidence level definitions
- What makes a good learning vs. noise
- How to present approval UI
- When to update skills

**References:** continuous-learning/SKILL.md:1-81 for structure

### 9. **reflect.sh** (~40 lines)

**Purpose:** Entry point for `/reflect` command

**Handles:**
- `/reflect <skill-name>` → invoke analyze-session.js
- `/reflect on` → enable automatic mode
- `/reflect off` → disable automatic mode
- `/reflect status` → show current status

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-}"

case "$COMMAND" in
  on)
    node "${SCRIPT_DIR}/lib/state-manager.js" enable
    ;;
  off)
    node "${SCRIPT_DIR}/lib/state-manager.js" disable
    ;;
  status)
    node "${SCRIPT_DIR}/lib/state-manager.js" status
    ;;
  *)
    node "${SCRIPT_DIR}/lib/analyze-session.js" "$@"
    ;;
esac
```

### 10. **config.json** (~20 lines)

**Purpose:** Configuration options

```json
{
  "min_session_length": 5,
  "require_approval": true,
  "auto_commit": true,
  "auto_push": true,
  "confidence_thresholds": {
    "high_min_signals": 1,
    "medium_min_signals": 2,
    "low_min_signals": 3
  },
  "ignore_patterns": [
    "simple_typos",
    "one_time_fixes"
  ]
}
```

---

## Implementation Sequence

### Phase 1: Core Infrastructure
1. Create directory structure: `~/.claude/skills/reflect/`
2. Create config.json with default settings
3. Create state-manager.js for on/off toggle
4. Create reflect.sh entry point
5. Test control commands: `reflect on`, `reflect off`, `reflect status`

### Phase 2: Analysis Engine
1. Create confidence-classifier.js with pattern detection
2. Create skill-parser.js for SKILL.md parsing
3. Create analyze-session.js orchestrator
4. Test manual analysis on sample transcripts

### Phase 3: Approval Workflow
1. Create approval-ui.js for interactive review
2. Integrate with analyze-session.js
3. Test approval flow with sample learnings

### Phase 4: Git Integration
1. Create git-utils.js with git operations
2. Integrate with analyze-session.js
3. Test commit and push workflow
4. Test error handling (no git, no remote, network errors)

### Phase 5: Automatic Mode
1. Create hooks/stop-reflect.js
2. Add hook configuration to ~/.claude/settings.json
3. Test automatic detection and notification
4. Test full workflow from session end to approval

### Phase 6: SKILL.md and Documentation
1. Create SKILL.md with instructions for Claude
2. Document usage patterns and examples
3. Add README with installation instructions

---

## Verification Plan

### Manual Testing

1. **Control commands:**
   ```bash
   /reflect status  # Should show disabled initially
   /reflect on      # Enable automatic mode
   /reflect status  # Should show enabled
   /reflect off     # Disable automatic mode
   ```

2. **Manual reflection:**
   - Start a session and correct Claude on something (e.g., "Actually, use PrimaryButton not Button")
   - Run `/reflect <skill-name>`
   - Verify approval UI shows detected correction
   - Approve changes
   - Verify SKILL.md was updated
   - Verify git commit was created (if ~/.claude/skills/ is git repo)

3. **Automatic mode:**
   - Enable with `/reflect on`
   - Have a session with corrections
   - End session
   - Verify notification appears about detected learnings
   - Verify approval is required before changes

4. **Confidence classification:**
   - Test HIGH: Direct user corrections ("never do X", "always use Y")
   - Test MEDIUM: Error → solution patterns
   - Test LOW: Repeated tool usage observations
   - Verify learnings are categorized correctly

5. **Git integration:**
   - Test with git repo: verify commit and push
   - Test without git repo: verify updates still work
   - Test with no remote: verify commit locally
   - Test with network error: verify graceful handling

6. **Natural language editing:**
   - Get approval UI with multiple changes
   - Edit with "Remove the first high confidence change"
   - Verify changes are modified correctly
   - Approve modified proposal
   - Verify only edited changes are applied

### Edge Cases

1. Short sessions (< 5 messages) should be skipped
2. Sessions with no learnings should not trigger approval
3. Invalid skill names should show helpful error
4. Malformed SKILL.md files should error gracefully
5. Git conflicts should abort with clear message

### Success Criteria

- ✅ Manual `/reflect <skill-name>` command works end-to-end
- ✅ Control commands (on/off/status) work correctly
- ✅ Confidence classification detects HIGH/MEDIUM/LOW patterns
- ✅ Approval UI shows clear, actionable information
- ✅ Natural language editing modifies proposals correctly
- ✅ SKILL.md files are updated with proper formatting
- ✅ Git integration commits and pushes successfully (when git repo exists)
- ✅ Automatic mode detects learnings at session end
- ✅ Automatic mode requires approval before updating
- ✅ Error handling is robust and user-friendly

---

## Notes

- **Reuse existing utilities:** The `utils.js` file at `/home/vlad/.claude/plugins/marketplaces/everything-claude-code/scripts/lib/utils.js` provides many helpful functions (readFile, writeFile, log, isGitRepo, etc.). Require and use these where applicable.

- **Follow existing patterns:** The continuous-learning skill provides a good template for hook integration and session analysis. The humanizer skill shows proper SKILL.md formatting.

- **Keep it simple initially:** Start with basic pattern detection and approval. More sophisticated NLP for learning extraction can be added later.

- **Version control is optional:** Git integration should enhance the workflow but not be required. The skill should work perfectly fine without git.

- **User control is paramount:** Automatic mode should ALWAYS require approval. Never update skills without user consent.
