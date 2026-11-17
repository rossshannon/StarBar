"""What the release scripts' tests share: a scratch repository with an origin, a stand-in
for gh, and notes that pass.

The scripts are run with /bin/bash, which on macOS is the 3.2 they have to work in.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BASH = "/bin/bash"
SCRIPTS = Path(__file__).resolve().parent.parent
CHECK_NOTES = SCRIPTS / "check-notes.sh"
PUBLISH = SCRIPTS / "publish.sh"
# Where the scripts live in the repository, which is where publish.sh looks for its checker
SCRIPTS_IN_REPO = ".claude/skills/release/scripts"
REPO = "example/StarBar"


def notes(version="1.1.0", previous="1.0.0", tagline=" — A heart that bursts", extra=""):
    """Release notes in the house style, which check-notes.sh accepts as they are."""
    return (
        "# StarBar {version}{tagline}\n"
        "\n"
        "StarBar {version} makes the favourite heart burst when you set it.\n"
        "\n"
        "**This is the recommended release. Requires macOS 13 or later, and Music or Spotify.**\n"
        "\n"
        "## A heart that bursts\n"
        "\n"
        "- Click the heart in the menu bar and it bursts.\n"
        "{extra}"
        "\n"
        "## Installation\n"
        "\n"
        "Download the zip, extract StarBar and move it to Applications.\n"
        "\n"
        "This build is signed ad hoc and is not notarised.\n"
        "\n"
        "[Changes since {previous}](https://github.com/{repo}/compare/v{previous}...v{version}).\n"
    ).format(version=version, previous=previous, tagline=tagline, extra=extra, repo=REPO)


class Sandbox:
    """A clone ("work") of a bare repository ("origin.git") holding one release, v1.0.0,
    with a stand-in gh first on the PATH."""

    def __init__(self, test):
        self.dir = Path(tempfile.mkdtemp(prefix="starbar-release-test."))
        test.addCleanup(shutil.rmtree, str(self.dir), True)
        self.origin = self.dir / "origin.git"
        self.work = self.dir / "work"
        self.state_file = self.dir / "gh-state.json"
        bin_dir = self.dir / "bin"
        bin_dir.mkdir()
        (self.dir / "tmp").mkdir()
        (self.dir / "gitconfig").write_text("")

        stub = bin_dir / "gh"
        stub.write_text('#!/bin/sh\nexec "%s" "%s" "$@"\n' % (sys.executable, Path(__file__).with_name("gh_stub.py")))
        stub.chmod(0o755)

        env = dict(os.environ)
        # Nothing from the caller's git or gh setup may leak in (a commit hook sets GIT_DIR)
        for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GH_REPO", "GH_TOKEN", "GH_HOST"):
            env.pop(name, None)
        env.update(
            PATH=str(bin_dir) + os.pathsep + env["PATH"],
            TMPDIR=str(self.dir / "tmp"),
            GIT_CONFIG_GLOBAL=str(self.dir / "gitconfig"),
            GIT_CONFIG_NOSYSTEM="1",
            GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.invalid",
            GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.invalid",
            GH_STUB_STATE=str(self.state_file),
            STARBAR_RELEASE_REPO=REPO,
            STARBAR_RELEASE_POLL_SECONDS="0",
            STARBAR_RELEASE_POLL_TRIES="2",
        )
        self.env = env

        self.git("init", "-q", "--bare", "-b", "main", str(self.origin), cwd=self.dir)
        self.git("clone", "-q", str(self.origin), str(self.work), cwd=self.dir)
        self.git("checkout", "-q", "-B", "main")
        for script in (CHECK_NOTES, PUBLISH):
            self.write(SCRIPTS_IN_REPO + "/" + script.name, script.read_text(encoding="utf-8"))
        self.write("StarBar/StarBar.entitlements", "<plist><dict/></plist>\n")
        self.write("Privacy Policy.md", "# Privacy\n\nStarBar sends nothing.\n")
        self.write("docs/releases/v1.0.0.md", notes("1.0.0", "0.9.0"))
        self.first = self.commit("First release")
        self.git("tag", "-a", "v1.0.0", "-m", "StarBar 1.0.0")
        self.git("push", "-q", "origin", "main", "v1.0.0")
        self.set_state(repo=REPO, origin=str(self.origin), tag="v1.1.0", release_run=7001)

    # --- git ---------------------------------------------------------------------------

    def git(self, *args, cwd=None, check=True):
        result = subprocess.run(
            ["git", *args], cwd=str(cwd or self.work), env=self.env,
            capture_output=True, text=True, check=False,
        )
        if check and result.returncode != 0:
            raise AssertionError("git %s failed:\n%s%s" % (" ".join(args), result.stdout, result.stderr))
        return result.stdout.strip()

    def write(self, path, text):
        target = self.work / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def release_commit(self, version="1.1.0", text=None, push=True, tests="completed success"):
        """Commit a release's notes on main, as merging a release pull request does, and
        record a Tests run for it. Returns the commit's SHA."""
        self.write("docs/releases/v%s.md" % version, notes(version) if text is None else text)
        sha = self.commit("Release notes for %s" % version)
        if push:
            self.git("push", "-q", "origin", "main")
        if tests:
            runs = self.state().get("test_runs", {})
            runs[sha] = ["5001 " + tests]
            self.set_state(test_runs=runs)
        return sha

    def tag_on_origin(self, tag):
        """The commit a tag points at on origin, or an empty string."""
        return self.git("--git-dir", str(self.origin), "rev-parse", "-q", "--verify",
                        "refs/tags/%s^{commit}" % tag, check=False)

    def tag_message(self, tag):
        return self.git("--git-dir", str(self.origin), "tag", "-l", "--format=%(contents:subject)", tag)

    # --- the stand-in gh ---------------------------------------------------------------

    def state(self):
        if not self.state_file.exists():
            return {}
        return json.loads(self.state_file.read_text(encoding="utf-8"))

    def set_state(self, **changes):
        state = self.state()
        state.update(changes)
        self.state_file.write_text(json.dumps(state, indent=1), encoding="utf-8")

    def calls(self, *prefix):
        """The gh calls made so far that start with these words."""
        return [call for call in self.state().get("calls", []) if call[:len(prefix)] == list(prefix)]

    # --- running the scripts -----------------------------------------------------------

    def run(self, script, *args, cwd=None):
        return subprocess.run(
            [BASH, str(script), *args], cwd=str(cwd or self.work), env=self.env,
            capture_output=True, text=True, check=False, timeout=120,
        )

    def publish(self, *args):
        return self.run(PUBLISH, *args)

    def publish_as_committed(self, sha, *args):
        """Run publish.sh the way the release command does: straight out of the commit."""
        command = 'bash <(git show "$1":%s/publish.sh) "${@:2}"' % SCRIPTS_IN_REPO
        return subprocess.run(
            [BASH, "-c", command, "publish", sha, *args], cwd=str(self.work), env=self.env,
            capture_output=True, text=True, check=False, timeout=120,
        )

    def check_notes(self, *args, cwd=None):
        return self.run(CHECK_NOTES, *args, cwd=cwd)


def output(result):
    return result.stdout + result.stderr
