# StarBar — Claude Code

@AGENTS.md

The project guide above applies to every tool. This file adds only what is specific to Claude Code.

## Skills

- `install-and-verify` (`.claude/skills/install-and-verify/`): use it whenever you install, reinstall, relaunch or "try out" the app, and before telling the user a change is ready to test. It says how to read the install verification block and how to prove from the log that the changed code runs.

## Working in this repo

- `.claude/` is gitignored except for `.claude/skills/`, so project skills are shared and everything else there is local.
- Make worktrees with `git worktree add .worktrees/<name>`, as `AGENTS.md` says, not with `claude --worktree` or `EnterWorktree`'s default, which put them in `.claude/worktrees/`. A `WorktreeCreate` hook could move those, but it replaces Claude Code's git handling entirely, including the check for unsaved work when a worktree session ends, so there isn't one. The temporary worktrees Claude Code makes for subagents (`isolation: worktree`) are its own to clean up; leave them where it puts them.
- Anything worth keeping from a session belongs in `AGENTS.md`, in a skill, or in a commit message.
- If a problem occurs that a rule could have prevented, suggest the rule. Put it in `AGENTS.md` unless it is about Claude Code itself.
