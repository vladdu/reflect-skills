---
name: reflect
version: 1.0.0
description: |
  Analyze Claude Code sessions and update specified skills with learnings
  from user corrections and successful patterns. Supports manual /reflect
  command and automatic mode via stop hook. Corrections are signals for
  new memories. Approvals are confirmations of existing patterns.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
---

# Reflect: Self-Improving Skills

You are running the reflect skill. Your job is to analyze the current conversation, extract learnings from user corrections and successful patterns, and update a specified skill file so the same mistakes don't repeat across sessions.

## Commands

Handle these based on the argument passed:

- `/reflect <skill-name>` -- Run the full reflect workflow (see below)
- `/reflect on` -- Enable automatic mode: read the state file, set `enabled: true`, write it back. Confirm to user.
- `/reflect off` -- Disable automatic mode: read the state file, set `enabled: false`, write it back. Confirm to user.
- `/reflect status` -- Read and display the state file: whether auto-mode is on/off, last run timestamp, recent history.

The state file is located at `state/reflect-state.json` relative to this skill's directory.

## Reflect Workflow

When the user calls `/reflect <skill-name>`:

### Step 1: Locate the Target Skill

Find the SKILL.md file for the named skill. Search in order:
1. `~/.claude/skills/<skill-name>/SKILL.md`
2. `~/.claude/skills/<skill-name>.md`
3. Current project's skills directory
4. Plugin marketplace directories under `~/.claude/plugins/`

If not found, tell the user and ask them to provide the path.

Read the target skill file so you understand its current content.

### Step 2: Analyze the Conversation

Scan the full conversation history for two types of signals:

**Corrections** -- The user corrected your behavior:
- "Actually, use X instead of Y"
- "No, do it this way..."
- "Don't do X" / "Never do X" / "Stop doing X"
- "I told you to..." (re-stating an instruction you missed)
- "That's wrong because..."
- User rejected your output and provided an alternative
- User edited or rewrote something you produced

**Approvals/Confirmations** -- The user confirmed something worked:
- "Perfect" / "That's exactly right" / "Yes, always do it that way"
- "This works great" / "Keep doing it like this"
- User accepted output without changes
- User explicitly praised an approach

### Step 3: Classify by Confidence

For each signal, assign a confidence level:

**HIGH** -- Direct, unambiguous user directives:
- Explicit "never do X" or "always do Y" statements
- Clear corrections with specific alternatives ("use PrimaryButton, not Button")
- Rules stated as absolutes

**MEDIUM** -- Patterns that worked well:
- Error-then-fix sequences where the fix was confirmed
- Approaches the user approved
- Conventions the user reinforced

**LOW** -- Observations worth noting:
- Implicit preferences (user consistently chose one approach over another)
- Patterns that emerged but weren't explicitly discussed
- Things that might be project-specific vs. general preferences

### Step 4: Generate Proposed Changes

Based on the signals, determine how the target skill should be updated.

**Critical: Integrate, don't append.** Do not just add a "Learnings" changelog section at the bottom. Instead, work the learnings into the skill's existing instructions so Claude follows them naturally. For example:
- If the skill has a "Component Patterns" section and you learned to always use PrimaryButton, add that guidance within that section.
- If you learned a new validation rule, add it to the relevant rules section.
- If no appropriate section exists, create one that fits the skill's structure.

For each proposed change, note:
- Which signal it came from (with conversation context)
- The confidence level
- Where in the skill file it would go
- The actual text to add or modify

### Step 5: Present for Approval

Show the user a clear review with three sections:

**Signals Detected:**
List each signal with its confidence level and a brief quote from the conversation showing where it came from.

```
HIGH: "Never generate button styles inline -- always reference the design system"
  (from: user corrected inline style generation at turn 12)

MEDIUM: Using optional chaining for null checks worked well
  (from: user approved the fix at turn 8)
```

**Proposed Changes:**
Show the specific edits to the skill file. Use before/after format or describe the insertion clearly.

```
In section "## Component Patterns", add:
+ - Always reference design system components (PrimaryButton, SecondaryButton)
+   instead of generating inline button styles. Never invent component names.
```

**Commit Message:**
A concise summary for git, e.g.:
```
reflect(frontend-patterns): add design system component rule from session corrections
```

### Step 6: Handle User Response

- **"Y" or "yes" or "approve"** -- Apply all proposed changes. Proceed to Step 7.
- **"N" or "no" or "reject"** -- Cancel. Make no changes. Record in state history as rejected.
- **Anything else** -- Treat as natural language instructions to modify the proposal. Apply the user's edits to your proposal, then re-present for approval (go back to Step 5).

Examples of natural language edits:
- "Only apply the high confidence ones" -- remove medium and low changes
- "Change the wording of the first one to..." -- update that specific change
- "Skip the third signal, it was a one-time thing" -- remove it
- "Also add a note about..." -- add another change to the proposal

### Step 7: Apply Changes

1. Edit the target skill's SKILL.md file using the Edit tool (prefer Edit over Write to make targeted changes).
2. Update the state file: set `lastRun` to current ISO timestamp, append to `history` array with skill name, signal count, and `approved: true`.

### Step 8: Git Integration

After updating the skill file:

1. Check if the skill's parent directory is a git repo:
   ```
   git -C <skill-directory> rev-parse --git-dir
   ```

2. If it IS a git repo:
   - Stage the changed file: `git -C <dir> add <file>`
   - Commit with the approved message: `git -C <dir> commit -m "<message>"`
   - Attempt to push: `git -C <dir> push`
   - If push fails (no remote, auth error, network), inform the user the commit was made locally and they can push manually.

3. If it is NOT a git repo:
   - Just confirm the file was updated. No git operations.

## Automatic Mode

When triggered by the stop hook (the hook prints a message to stderr that you'll see), follow the same workflow as manual mode. The hook message will look like:

```
[Reflect] Session has N messages -- running automatic reflection
```

When you see this:
1. Check which skills were used in the session (look for skill invocations in the conversation)
2. Ask the user which skill they'd like to update (since automatic mode still requires user direction on the target)
3. Proceed with the standard reflect workflow from Step 2

Never update skills without user approval in automatic mode.

## Guidelines

- **Be selective.** Not every correction is a lasting preference. One-time fixes ("change this variable name") are not skill-worthy. Look for patterns and rules that apply broadly.
- **Respect skill structure.** Each skill has its own organization and voice. Match it when adding content.
- **Keep learnings actionable.** "Use PrimaryButton component" is better than "The user prefers certain button components."
- **Don't duplicate.** If the skill already covers a point, strengthen or refine it rather than adding a redundant entry.
- **Prefer precision.** "Always use `fetchUser()` from `@/lib/api` for user data" beats "Use the proper API functions."
