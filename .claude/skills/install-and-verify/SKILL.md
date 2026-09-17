---
name: install-and-verify
description: Install StarBar into /Applications and prove the running app is the new build and the change works. Use whenever you install, reinstall, relaunch or "try out" the app, before telling the user a change is ready to test, and when the user says a change "isn't active" or "isn't working" after an install.
---

# Install and verify StarBar

An install only counts when three things are proven: the new binary is in `/Applications`, the app now running is that binary, and the changed code actually runs. "`./build.sh --install` said Done" proves none of them.

## 1. Install

```bash
./build.sh --install
```

The script ends with an **Install verification** block and exits non-zero if the check fails:

```
=== Install verification ===
Commit:     21847ff
Version:    1.5.0 (18)
Binary:     Sep 17 00:32:10 2026  sha256 3f9a1c0d2b7e
Running:    PID 41424, started Wed Sep 17 00:32:11 2026
Verified: /Applications has the new build, and it is running.
```

Read it; don't just check the exit code.
- **Commit** should be the commit you meant to test. `+ uncommitted changes` means the build includes work that isn't committed. Say so when you report.
- **Running** must show a start time from this install. An older time means an old copy is still running.
- `FAILED` lines: fix the cause before going on. Don't report the install as done.

## 2. Prove the change runs

The build being new doesn't prove the changed code runs. Menu bar gestures, for example, can be swallowed by AppKit before the new handler sees them. Check the app's log for the code path you changed:

```bash
/usr/bin/log show --last 10m --predicate 'process == "StarBar"' | grep -E "<function or message you changed>"
```

- Use `/usr/bin/log`. In zsh, `log` is a shell builtin.
- `os_log(.debug, …)` messages aren't kept. To see them, stream while the action happens:
  ```bash
  /usr/bin/log stream --level debug --style compact --predicate 'process == "StarBar"'
  ```
- If you need the user to click or drag, start the stream first. Then ask for one specific action, and read the stream afterwards.
- For rating changes, `iTunesRadioStation.setRating` logs `set timer for 2.0s and set rating for <track> <rating>`. To confirm what Music stored:
  ```bash
  osascript -e 'tell application "Music" to get {name, rating, favorited} of current track'
  ```

Don't run `./build.sh --ui-test` to check a change unless the user asks for it. It takes over the screen for about two minutes. Use the log, or ask the user to try the change.

## 3. Report

Tell the user the commit, the PID and start time, and the log lines that show the changed code ran. If step 2 found nothing, say plainly that the build is installed but the change is not confirmed to work, and say what you'll check next.
