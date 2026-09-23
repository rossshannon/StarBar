# StarBar — Claude Code

@AGENTS.md

The project guide above applies to every tool. This file adds only what is specific to Claude Code.

## Skills

- `install-and-verify` (`.claude/skills/install-and-verify/`): use it whenever you install, reinstall, relaunch or "try out" the app, and before telling the user a change is ready to test. It says how to read the install verification block and how to prove from the log that the changed code runs.

## Working in this repo

- `.claude/` is gitignored except for `.claude/skills/`, so project skills are shared and everything else there is local.
- Anything worth keeping from a session belongs in `AGENTS.md`, in a skill, or in a commit message.
- If a problem occurs that a rule could have prevented, suggest the rule. Put it in `AGENTS.md` unless it is about Claude Code itself.
