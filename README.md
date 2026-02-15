# reflect-skills

A Claude Code plugin that analyzes your sessions and updates skill files with learnings from user corrections and successful patterns. Corrections become new memories; approvals confirm existing ones. 
Created with Claude using as reference https://www.youtube.com/watch?v=-4nUCaMNBR8

## What it does

After a Claude Code session, `/reflect` scans the conversation for two types of signals:

- **Corrections** -- where you told Claude to do something differently ("use X instead of Y", "don't do that", etc.)
- **Approvals** -- where you confirmed something worked well ("perfect", "yes, always do it that way")

It classifies each signal by confidence (high/medium/low), proposes edits to the target skill's `SKILL.md`, and asks for your approval before changing anything.

## Installation

Clone this repo and register it as a Claude Code plugin:

```bash
git clone https://github.com/vladdu/reflect-skills.git
claude plugin add /path/to/reflect-skills
```

## Usage

### Manual mode

```
/reflect <skill-name>
```

Runs the full workflow: find the skill, analyze the conversation, propose changes, apply on approval, commit.

### Automatic mode

```
/reflect on       # Enable auto-reflect at session end
/reflect off      # Disable it
/reflect status   # Show current state and history
```

When enabled, a stop hook checks if the session had enough messages and triggers reflection automatically. You still approve all changes before they're applied.

## How changes are applied

Reflect integrates learnings into the skill's existing structure rather than appending a changelog. If a skill has a "Component Patterns" section and you corrected inline styles, the new rule goes there. If no fitting section exists, one is created to match the skill's voice.

After approval, if the skill lives in a git repo, reflect stages, commits, and attempts to push the changes.

## Project structure

```
skills/reflect/
  SKILL.md              # Skill definition and workflow
  scripts/
    reflect.sh          # Entry point for /reflect command
    stop-reflect.sh     # Stop hook for automatic mode
  state/
    reflect-state.json  # Persisted state (enabled, history)
```

## License

MIT
