"""Tests for watch-run.sh, which publish.sh uses at a terminal to watch a workflow run.

It is driven here with a stand-in gh that answers each API path with the fields the real
one's --jq filter would print, so these tests check the script's own logic, not the filters.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from helpers import BASH, SCRIPTS

WATCH = SCRIPTS / "watch-run.sh"
US = "\x1f"
REPO = "example/StarBar"


def fields(*values):
    return US.join(str(v) for v in values)


class WatchRun(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="watch-run-test."))
        self.addCleanup(shutil.rmtree, str(self.dir), True)
        (self.dir / "bin").mkdir()
        self.answers = self.dir / "answers"
        self.answers.mkdir()
        gh = self.dir / "bin" / "gh"
        # gh api <path> ...: print answers/<path with / and ? made safe>, or fail
        gh.write_text(
            '#!/bin/sh\n'
            '[ "$1" = api ] || exit 2\n'
            'f="%s/$(printf %%s "$2" | tr \'/?&=\' \'____\')"\n'
            '[ -f "$f" ] || exit 1\n'
            'cat "$f"\n' % self.answers)
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.dir / "bin") + os.pathsep + os.environ["PATH"],
                        WATCH_RUN_POLL="0")

    def answer(self, path, text):
        (self.answers / path.translate(str.maketrans("/?&=", "____"))).write_text(text)

    def run_watch(self, run="7001"):
        return subprocess.run([BASH, str(WATCH), run, REPO], env=self.env, capture_output=True,
                              text=True, check=False, timeout=60)

    def a_run(self, conclusion, steps):
        self.answer("repos/%s/actions/runs/7001" % REPO,
                    fields("completed", conclusion, "v1.1.0", "Release", 1700000000, 99,
                           "https://example.invalid/runs/7001") + "\n")
        jobs = [fields("J", "release", "completed", conclusion, 1700000000, 1700000300)]
        jobs += [fields("S", *step) for step in steps]
        self.answer("repos/%s/actions/runs/7001/jobs?per_page=100" % REPO, "\n".join(jobs) + "\n")

    def test_a_run_that_passed_exits_0_and_marks_skipped_steps(self):
        self.a_run("success", [
            ("Run tests", "completed", "success", 1700000000, 1700000125),
            ("Sign with Developer ID", "completed", "skipped", "", ""),
        ])
        result = self.run_watch()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("✓ Run tests", result.stdout)
        self.assertIn("2m 05s", result.stdout)
        self.assertIn("– Sign with Developer ID", result.stdout)
        self.assertIn("skipped", result.stdout)
        self.assertIn("Run completed: success", result.stdout)

    def test_a_run_that_failed_exits_1_and_marks_the_step(self):
        self.a_run("failure", [("Run tests", "completed", "failure", 1700000000, 1700000040)])
        result = self.run_watch()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("✗ Run tests", result.stdout)
        self.assertIn("Run completed: failure", result.stdout)

    def test_a_run_github_does_not_know_exits_1(self):
        result = self.run_watch("424242")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("GitHub has no run 424242", result.stdout)

    def test_it_needs_a_run_id(self):
        result = subprocess.run([BASH, str(WATCH)], env=self.env, capture_output=True, text=True,
                                check=False, timeout=60)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
