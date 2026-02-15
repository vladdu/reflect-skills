# Project: reflect-skills

A Claude Code plugin providing the `/reflect` skill -- session analysis that turns user corrections into skill improvements.

## Structure

- `skills/reflect/SKILL.md` -- The skill definition. Contains the full workflow (locate skill, analyze conversation, classify signals, propose changes, apply on approval, git commit).
- `skills/reflect/scripts/reflect.sh` -- Shell entry point handling subcommands (`on`, `off`, `status`, `<skill-name>`).
- `skills/reflect/scripts/stop-reflect.sh` -- Stop hook for automatic mode. Checks if reflect is enabled and the session is long enough before triggering.
- `skills/reflect/state/reflect-state.json` -- Persisted state. Tracked by git but the `state/` directory contents are gitignored to avoid noisy diffs.
- `.claude-plugin/plugin.json` -- Plugin manifest for Claude Code.

## Key conventions

- All user-facing output from shell scripts goes to stderr (`>&2 echo`), not stdout.
- State file manipulation uses inline Node.js (`node -e`) for JSON handling.
- Skill changes require explicit user approval -- never auto-apply.
- Learnings are integrated into existing skill structure, not appended as a changelog section.
