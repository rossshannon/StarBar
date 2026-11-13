"""Tests for check-notes.sh.

    python3 -m unittest discover -s .claude/skills/release/scripts/tests
"""
import subprocess
import tempfile
import unittest
from pathlib import Path

from helpers import BASH, CHECK_NOTES, SCRIPTS, Sandbox, notes, output


class NotesFileRules(unittest.TestCase):
    """The rules that need only the file. Run outside any repository, with --file."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory(prefix="starbar-notes-test.")
        self.addCleanup(self.dir.cleanup)
        self.file = Path(self.dir.name) / "notes.md"

    def check(self, text, version="1.1.0", *more):
        self.file.write_bytes(text.encode("utf-8"))
        return subprocess.run(
            [BASH, str(CHECK_NOTES), version, "--file", str(self.file), *more],
            cwd=self.dir.name, capture_output=True, text=True, check=False, timeout=60,
        )

    def assert_problem(self, text, expected, *more):
        result = self.check(text, "1.1.0", *more)
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn(expected, result.stdout)
        return result

    def test_good_notes_pass(self):
        result = self.check(notes())
        self.assertEqual(result.returncode, 0, output(result))
        self.assertIn("check-notes: ready", result.stdout)

    def test_a_patch_release_needs_no_tagline(self):
        result = self.check(notes(tagline=""))
        self.assertEqual(result.returncode, 0, output(result))

    def test_the_title_must_name_this_version(self):
        self.assert_problem(notes().replace("# StarBar 1.1.0", "# StarBar 1.0.9", 1), "line 1 must be")

    def test_the_title_needs_an_em_dash_not_a_hyphen(self):
        self.assert_problem(notes(tagline=" - A heart that bursts"), "line 1 must be")

    def test_a_title_missing_altogether_is_reported(self):
        self.assert_problem(notes().split("\n", 2)[2], "line 1 must be")

    def test_the_title_has_no_full_stop(self):
        self.assert_problem(notes(tagline=" — A heart that bursts."), "ends with a full stop")

    def test_line_two_must_be_blank(self):
        self.assert_problem(notes().replace("\n\n", "\n", 1), "line 2 must be blank")

    def test_the_notes_open_with_the_app_and_version(self):
        self.assert_problem(
            notes().replace("StarBar 1.1.0 makes", "This release makes"), "line 3 must open the notes")

    def test_only_one_top_level_heading(self):
        self.assert_problem(notes(extra="\n# Another title\n"), "only line 1 may be a '# ' heading")

    def test_the_recommended_line_is_required(self):
        text = notes().replace(
            "**This is the recommended release. Requires macOS 13 or later, and Music or Spotify.**\n\n", "")
        self.assert_problem(text, "This is the recommended release")

    def test_the_recommended_line_appears_once(self):
        line = "**This is the recommended release. Requires macOS 13 or later, and Music or Spotify.**"
        result = self.assert_problem(notes(extra="\n" + line + "\n"), "This is the recommended release")
        self.assertIn("(found 2)", result.stdout)

    def test_installation_is_required(self):
        self.assert_problem(notes().replace("## Installation", "## Installing"), "one '## Installation' section")

    def test_installation_is_the_last_section(self):
        text = notes().replace("\n[Changes since", "\n## Thanks\n\nTo everyone who wrote in.\n\n[Changes since")
        self.assertLess(text.index("## Installation"), text.index("## Thanks"))
        self.assert_problem(text, "must be the last section")

    def test_the_compare_link_is_required(self):
        text = notes().rsplit("\n[Changes since", 1)[0] + "\n"
        self.assert_problem(text, "the last line must be '[Changes since")

    def test_the_compare_link_must_end_at_this_version(self):
        self.assert_problem(notes().replace("...v1.1.0", "...v1.1.1"), "compares up to v1.1.1")

    def test_the_compare_link_label_matches_its_range(self):
        self.assert_problem(notes().replace("Changes since 1.0.0", "Changes since 0.9.0"),
                            "says 'Changes since 0.9.0' but compares from v1.0.0")

    def test_the_compare_link_starts_before_this_version(self):
        self.assert_problem(notes(previous="1.2.0"), "which is not before v1.1.0")

    def test_the_compare_link_starts_at_the_release_before(self):
        self.assert_problem(notes(previous="0.9.0"), "the release before this one is v1.0.0",
                            "--previous", "v1.0.0")

    def test_versions_compare_as_numbers(self):
        # 1.9.0 is before 1.10.0, which sorting as text gets wrong
        result = self.check(notes("1.10.0", "1.9.0"), "1.10.0")
        self.assertEqual(result.returncode, 0, output(result))

    def test_placeholders_are_reported_with_their_line(self):
        text = notes(extra="\n**Source:** `MERGE_COMMIT`.\n")
        result = self.assert_problem(text, "has a placeholder or a Source/Package line")
        self.assertIn("line 11 ", result.stdout)

    def test_a_package_line_is_left_to_publish(self):
        self.assert_problem(notes(extra="\n**Package:** version 1.1.0, build 12.\n"),
                            "has a placeholder or a Source/Package line")

    def test_drafting_marks_are_reported(self):
        for mark in ("TODO: the clip", "<!-- HEART-BURST-CLIP -->", "build BUILD_NUMBER"):
            with self.subTest(mark=mark):
                self.assert_problem(notes(extra="- %s\n" % mark), "has a placeholder")

    def test_windows_line_endings_are_reported(self):
        self.assert_problem(notes().replace("\n", "\r\n"), "Windows line endings")

    def test_every_problem_is_listed_in_one_run(self):
        text = notes(tagline=" - Hyphen").replace("## Installation", "## Installing")
        result = self.check(text)
        self.assertEqual(result.returncode, 1)
        self.assertIn("line 1 must be", result.stdout)
        self.assertIn("one '## Installation' section", result.stdout)
        self.assertIn("2 problem(s)", result.stdout)

    def test_a_missing_file_is_a_problem(self):
        result = subprocess.run(
            [BASH, str(CHECK_NOTES), "1.1.0", "--file", str(self.file)],
            cwd=self.dir.name, capture_output=True, text=True, check=False, timeout=60,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("there are no notes at", result.stdout)

    def test_a_wrong_version_is_a_wrong_call(self):
        for version in ("v1.1.0", "1.1", "1.1.0-beta1", ""):
            with self.subTest(version=version):
                result = self.check(notes(), version)
                self.assertEqual(result.returncode, 2, output(result))

    def test_outside_a_repository_the_file_must_be_named(self):
        result = subprocess.run(
            [BASH, str(CHECK_NOTES), "1.1.0"],
            cwd=self.dir.name, capture_output=True, text=True, check=False, timeout=60,
        )
        self.assertEqual(result.returncode, 2, output(result))
        self.assertIn("pass --file", result.stderr)


class NotesInARepository(unittest.TestCase):
    """The rules that read the repository: which release came before, and what changed."""

    def setUp(self):
        self.box = Sandbox(self)

    def test_the_default_file_is_the_one_in_docs_releases(self):
        self.box.write("docs/releases/v1.1.0.md", notes())
        result = self.box.check_notes("1.1.0")
        self.assertEqual(result.returncode, 0, output(result))
        self.assertIn("docs/releases/v1.1.0.md", result.stdout)
        self.assertIn("the release before is v1.0.0", result.stdout)

    def test_the_release_before_is_the_highest_tag_below(self):
        for tag in ("v1.2.0", "v1.9.0", "v1.10.0", "v2.0.0", "nightly", "v3"):
            self.box.git("tag", tag)
        self.box.write("docs/releases/v1.11.0.md", notes("1.11.0", "1.10.0"))
        result = self.box.check_notes("1.11.0")
        self.assertEqual(result.returncode, 0, output(result))
        self.assertIn("the release before is v1.10.0", result.stdout)

    def test_a_link_from_an_older_release_is_caught(self):
        self.box.git("tag", "v1.0.1")
        self.box.write("docs/releases/v1.1.0.md", notes("1.1.0", "1.0.0"))
        result = self.box.check_notes("1.1.0")
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("the release before this one is v1.0.1", result.stdout)

    def test_changed_entitlements_need_a_section(self):
        self.box.write("StarBar/StarBar.entitlements", "<plist><dict><key>network</key></dict></plist>\n")
        sha = self.box.release_commit("1.1.0", push=False)
        result = self.box.check_notes("1.1.0", "--commit", sha)
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("StarBar/StarBar.entitlements changed since v1.0.0", result.stdout)

    def test_a_network_access_section_answers_changed_entitlements(self):
        self.box.write("StarBar/StarBar.entitlements", "<plist><dict><key>network</key></dict></plist>\n")
        text = notes(extra="\n## Network access\n\nStarBar now downloads covers.\n")
        sha = self.box.release_commit("1.1.0", text=text, push=False)
        result = self.box.check_notes("1.1.0", "--commit", sha)
        self.assertEqual(result.returncode, 0, output(result))

    def test_a_privacy_section_answers_a_changed_policy(self):
        self.box.write("Privacy Policy.md", "# Privacy\n\nStarBar now reads your library.\n")
        missing = self.box.release_commit("1.1.0", push=False)
        result = self.box.check_notes("1.1.0", "--commit", missing)
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("Privacy Policy.md changed since v1.0.0", result.stdout)

        text = notes(extra="\n## Privacy\n\nStarBar reads the names in your library.\n")
        fixed = self.box.release_commit("1.1.0", text=text, push=False)
        result = self.box.check_notes("1.1.0", "--commit", fixed)
        self.assertEqual(result.returncode, 0, output(result))

    def test_an_uncommitted_change_counts_without_a_commit(self):
        self.box.write("docs/releases/v1.1.0.md", notes())
        self.box.write("Privacy Policy.md", "# Privacy\n\nEdited, not committed.\n")
        result = self.box.check_notes("1.1.0")
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("Privacy Policy.md changed since v1.0.0", result.stdout)

    def test_unchanged_entitlements_need_no_section(self):
        sha = self.box.release_commit("1.1.0", push=False)
        result = self.box.check_notes("1.1.0", "--commit", sha)
        self.assertEqual(result.returncode, 0, output(result))
        self.assertNotIn("note:", result.stdout)

    def test_without_tags_the_rule_is_skipped_and_said_so(self):
        self.box.git("tag", "-d", "v1.0.0")
        self.box.write("docs/releases/v1.1.0.md", notes())
        result = self.box.check_notes("1.1.0")
        self.assertEqual(result.returncode, 0, output(result))
        self.assertIn("note: no earlier release to compare with", result.stdout)


class NotesInThisRepository(unittest.TestCase):
    """Every notes file the repository holds passes, so a release's notes are checked by
    the same run that tests its code."""

    def test_every_notes_file_passes(self):
        root = SCRIPTS.parents[3]
        files = sorted((root / "docs" / "releases").glob("v*.md"))
        if not files:
            self.skipTest("no docs/releases beside this skill")
        for path in files:
            version = path.stem[1:]
            with self.subTest(version=version):
                args = [BASH, str(CHECK_NOTES), version]
                # A release already tagged is compared at its tag; one still being written,
                # with the working tree
                tagged = subprocess.run(
                    ["git", "rev-parse", "-q", "--verify", "refs/tags/v%s^{commit}" % version],
                    cwd=str(root), capture_output=True, text=True, check=False,
                )
                if tagged.returncode == 0:
                    args += ["--commit", "v" + version]
                result = subprocess.run(args, cwd=str(root), capture_output=True, text=True,
                                        check=False, timeout=60)
                self.assertEqual(result.returncode, 0, output(result))


if __name__ == "__main__":
    unittest.main()
