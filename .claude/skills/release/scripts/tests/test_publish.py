"""Tests for publish.sh, against a scratch repository and a stand-in for gh (gh_stub.py).

    python3 -m unittest discover -s .claude/skills/release/scripts/tests
"""
import unittest

from helpers import REPO, Sandbox, notes, output


class PublishTestCase(unittest.TestCase):
    def setUp(self):
        self.box = Sandbox(self)

    def assert_stopped(self, result, expected, changed_nothing=True):
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("STOPPED:", result.stderr)
        self.assertIn(expected, result.stderr)
        if changed_nothing:
            self.assertIn("Nothing has been changed.", result.stderr)
            self.assertEqual(self.box.tag_on_origin("v1.1.0"), "")
            self.assertEqual(self.box.calls("release", "edit"), [])

    def assert_published(self, result, sha, build=None):
        self.assertEqual(result.returncode, 0, output(result))
        self.assertIn("=== Published ===", result.stdout)
        self.assertEqual(self.box.tag_on_origin("v1.1.0"), sha)
        release = self.box.state()["release"]
        self.assertEqual(release["name"], "StarBar 1.1.0 — A heart that bursts")
        expected = notes().split("\n", 2)[2] + (
            "\n**Source:** `%s`.\n\n**Package:** version 1.1.0, build %s.\n" % (sha[:7], build or 2))
        self.assertEqual(release["body"], expected)
        return release


class Publishing(PublishTestCase):
    def test_it_tags_waits_and_puts_the_notes_on_the_release(self):
        sha = self.box.release_commit()
        result = self.box.publish("1.1.0", sha)
        self.assert_published(result, sha)
        self.assertEqual(self.box.tag_message("v1.1.0"), "StarBar 1.1.0: A heart that bursts")
        self.assertIn("Release:  https://github.com/%s/releases/tag/v1.1.0" % REPO, result.stdout)
        self.assertIn("Source:   %s, build 2" % sha[:7], result.stdout)
        self.assertIn("SHA-256:  " + "ab" * 32, result.stdout)
        self.assertIn("Latest:   v1.1.0", result.stdout)
        self.assertEqual(self.box.calls("run", "watch"), [["run", "watch", "7001", "--exit-status"]])

    def test_it_runs_straight_out_of_the_commit(self):
        # The release command is `bash <(git show <commit>:.../publish.sh) ...`, where the
        # script has no file of its own to read its neighbours from
        sha = self.box.release_commit()
        # Whatever the checkout has in its working tree must not be what runs
        self.box.write(".claude/skills/release/scripts/check-notes.sh", "exit 1\n")
        self.box.write("docs/releases/v1.1.0.md", "not the notes\n")
        result = self.box.publish_as_committed(sha, "1.1.0", sha)
        self.assert_published(result, sha)

    def test_a_patch_release_has_a_title_without_a_tagline(self):
        sha = self.box.release_commit(text=notes(tagline=""))
        result = self.box.publish("1.1.0", sha)
        self.assertEqual(result.returncode, 0, output(result))
        self.assertEqual(self.box.state()["release"]["name"], "StarBar 1.1.0")
        self.assertEqual(self.box.tag_message("v1.1.0"), "StarBar 1.1.0")

    def test_the_notes_keep_no_blank_lines_before_the_source_line(self):
        sha = self.box.release_commit(text=notes() + "\n\n\n")
        result = self.box.publish("1.1.0", sha)
        self.assert_published(result, sha)

    def test_a_dry_run_checks_everything_and_changes_nothing(self):
        sha = self.box.release_commit()
        result = self.box.publish("1.1.0", sha, "--dry-run")
        self.assertEqual(result.returncode, 0, output(result))
        self.assertIn("Dry run: everything checks out", result.stdout)
        self.assertIn('Would tag:   v1.1.0 on %s ("StarBar 1.1.0: A heart that bursts")' % sha[:7], result.stdout)
        self.assertEqual(self.box.tag_on_origin("v1.1.0"), "")
        self.assertEqual(self.box.git("tag", "-l", "v1.1.0"), "")
        self.assertEqual(self.box.calls("run", "watch"), [])
        self.assertEqual(self.box.calls("release", "edit"), [])

    def test_it_leaves_the_checkout_alone(self):
        sha = self.box.release_commit()
        self.box.git("checkout", "-q", "-b", "something-else", self.box.first)
        self.box.write("scratch.txt", "uncommitted work\n")
        before = self.box.git("status", "--porcelain", "--branch")
        result = self.box.publish("1.1.0", sha)
        self.assert_published(result, sha)
        self.assertEqual(self.box.git("status", "--porcelain", "--branch"), before)


class ChecksBeforeTagging(PublishTestCase):
    def test_wrong_arguments_are_a_wrong_call(self):
        sha = self.box.release_commit()
        for args in (["v1.1.0", sha], ["1.1", sha], ["1.1.0", sha[:7]], ["1.1.0"], [],
                     ["1.1.0", sha, "extra"], ["1.1.0", sha, "--force"]):
            with self.subTest(args=args):
                result = self.box.publish(*args)
                self.assertEqual(result.returncode, 2, output(result))
        self.assertEqual(self.box.tag_on_origin("v1.1.0"), "")

    def test_it_stops_when_gh_is_not_signed_in(self):
        sha = self.box.release_commit()
        self.box.set_state(signed_in=False)
        self.assert_stopped(self.box.publish("1.1.0", sha), "gh is not signed in")

    def test_it_stops_when_main_has_moved_on(self):
        sha = self.box.release_commit()
        self.box.write("later.txt", "merged after the release was prepared\n")
        later = self.box.commit("Something else")
        self.box.git("push", "-q", "origin", "main")
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped(result, "origin/main is at %s, not %s" % (later[:7], sha[:7]))

    def test_it_stops_for_a_commit_that_was_never_pushed(self):
        sha = self.box.release_commit(push=False)
        self.assert_stopped(self.box.publish("1.1.0", sha), "origin/main is at")

    def test_it_stops_for_a_commit_that_does_not_exist(self):
        self.box.release_commit()
        self.assert_stopped(self.box.publish("1.1.0", "0" * 40), "there is no commit")

    def test_it_stops_when_a_higher_version_exists(self):
        self.box.git("tag", "-a", "v2.0.0", "-m", "StarBar 2.0.0")
        self.box.git("push", "-q", "origin", "v2.0.0")
        sha = self.box.release_commit()
        self.assert_stopped(self.box.publish("1.1.0", sha), "v2.0.0 already exists and 1.1.0 is not above it")

    def test_it_stops_when_the_commit_does_not_contain_the_last_release(self):
        # A release tagged on a branch that main never took
        self.box.git("checkout", "-q", "-b", "side", self.box.first)
        self.box.write("side.txt", "a side line\n")
        self.box.commit("Side work")
        self.box.git("tag", "-a", "v1.0.5", "-m", "StarBar 1.0.5")
        self.box.git("push", "-q", "origin", "v1.0.5")
        self.box.git("checkout", "-q", "main")
        sha = self.box.release_commit()
        self.assert_stopped(self.box.publish("1.1.0", sha), "does not contain v1.0.5")

    def test_it_stops_without_the_notes_file(self):
        self.box.write("other.txt", "a change with no notes\n")
        sha = self.box.commit("No notes")
        self.box.git("push", "-q", "origin", "main")
        self.box.set_state(test_runs={sha: ["5001 completed success"]})
        self.assert_stopped(self.box.publish("1.1.0", sha), "there is no docs/releases/v1.1.0.md")

    def test_it_stops_when_the_notes_fail_their_check(self):
        sha = self.box.release_commit(text=notes(extra="\n**Package:** version 1.1.0, build BUILD_NUMBER.\n"))
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped(result, "the notes in %s don't pass" % sha[:7])
        self.assertIn("has a placeholder or a Source/Package line", result.stdout)

    def test_it_stops_when_the_entitlements_changed_and_the_notes_say_nothing(self):
        self.box.write("StarBar/StarBar.entitlements", "<plist><dict><key>network</key></dict></plist>\n")
        sha = self.box.release_commit()
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped(result, "don't pass")
        self.assertIn("StarBar/StarBar.entitlements changed since v1.0.0", result.stdout)

    def test_it_stops_when_the_tests_failed(self):
        sha = self.box.release_commit(tests="completed failure")
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped(result, "the tests did not pass on %s" % sha[:7])
        self.assertIn("/actions/runs/5001", result.stderr)

    def test_it_stops_when_no_tests_ran(self):
        sha = self.box.release_commit(tests=None)
        self.assert_stopped(self.box.publish("1.1.0", sha), "no Tests run is recorded")

    def test_it_waits_for_tests_still_running(self):
        sha = self.box.release_commit(tests="in_progress ")
        result = self.box.publish("1.1.0", sha)
        self.assert_published(result, sha)
        self.assertEqual(self.box.calls("run", "watch")[0], ["run", "watch", "5001", "--exit-status"])

    def test_it_stops_when_the_running_tests_then_fail(self):
        sha = self.box.release_commit(tests="queued ")
        self.box.set_state(watch_exit={"5001": 1})
        self.assert_stopped(self.box.publish("1.1.0", sha), "the tests failed on %s" % sha[:7])

    def test_an_earlier_failure_does_not_block_a_later_pass(self):
        sha = self.box.release_commit(tests=None)
        self.box.set_state(test_runs={sha: ["5002 completed success", "5001 completed failure"]})
        self.assert_published(self.box.publish("1.1.0", sha), sha)


class TagsAlreadyThere(PublishTestCase):
    def tag_elsewhere(self, push=True):
        """Put v1.1.0 on a commit that is no longer the release."""
        old = self.box.release_commit()
        self.box.git("tag", "-a", "v1.1.0", "-m", "StarBar 1.1.0: first try")
        if push:
            self.box.git("push", "-q", "origin", "v1.1.0")
        self.box.write("fix.txt", "the fix for what broke the first run\n")
        sha = self.box.commit("Fix the build")
        self.box.git("push", "-q", "origin", "main")
        self.box.set_state(test_runs={sha: ["5003 completed success"]})
        return old, sha

    def test_a_tag_already_on_the_commit_is_not_pushed_again(self):
        sha = self.box.release_commit()
        self.box.git("tag", "-a", "v1.1.0", "-m", "StarBar 1.1.0: pushed by an earlier run")
        self.box.git("push", "-q", "origin", "v1.1.0")
        result = self.box.publish("1.1.0", sha)
        self.assert_published(result, sha)
        self.assertIn("won't be pushed again", result.stdout)
        self.assertEqual(self.box.tag_message("v1.1.0"), "StarBar 1.1.0: pushed by an earlier run")

    def test_a_tag_made_but_never_pushed_is_pushed(self):
        sha = self.box.release_commit()
        self.box.git("tag", "-a", "v1.1.0", "-m", "StarBar 1.1.0: made by an earlier run")
        result = self.box.publish("1.1.0", sha)
        self.assert_published(result, sha)
        self.assertIn("only needs pushing", result.stdout)

    def test_a_tag_on_another_commit_stops_it(self):
        old, sha = self.tag_elsewhere()
        result = self.box.publish("1.1.0", sha)
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("v1.1.0 is already on %s, a different commit" % old[:7], result.stderr)
        self.assertIn("--retag", result.stderr)
        self.assertEqual(self.box.tag_on_origin("v1.1.0"), old)

    def test_retag_moves_a_tag_that_has_no_release(self):
        old, sha = self.tag_elsewhere()
        result = self.box.publish("1.1.0", sha, "--retag")
        self.assert_published(result, sha, build=3)
        self.assertEqual(self.box.tag_message("v1.1.0"), "StarBar 1.1.0: A heart that bursts")

    def test_retag_never_moves_a_tag_that_has_a_release(self):
        old, sha = self.tag_elsewhere()
        self.box.set_state(release={"tag": "v1.1.0", "name": "StarBar 1.1.0", "body": "Build 2.\n",
                                    "assets": ["StarBar-v1.1.0.zip", "StarBar-v1.1.0.zip.sha256"]})
        result = self.box.publish("1.1.0", sha, "--retag")
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("A published tag never moves", result.stderr)
        self.assertEqual(self.box.tag_on_origin("v1.1.0"), old)
        self.assertEqual(self.box.state()["release"]["body"], "Build 2.\n")

    def test_retag_waits_for_the_old_commits_run_to_end(self):
        # Still running, it would publish the old commit's build under the moved tag
        old, sha = self.tag_elsewhere()
        self.box.set_state(unfinished_release_runs=["6999"])
        result = self.box.publish("1.1.0", sha, "--retag")
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("a Release run for the old v1.1.0 is still going (run 6999)", result.stderr)
        self.assertIn("Nothing has been changed.", result.stderr)
        self.assertEqual(self.box.tag_on_origin("v1.1.0"), old)

    def test_a_stale_tag_that_was_never_pushed_stops_it(self):
        old, sha = self.tag_elsewhere(push=False)
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped(result, "that was never pushed")

    def test_retag_replaces_a_stale_tag_that_was_never_pushed(self):
        old, sha = self.tag_elsewhere(push=False)
        result = self.box.publish("1.1.0", sha, "--retag")
        self.assert_published(result, sha, build=3)

    def test_the_run_for_a_moved_tags_old_commit_is_not_the_one_watched(self):
        old, sha = self.tag_elsewhere()
        # For the first look, the only run listed for the tag is the old commit's
        self.box.set_state(other_release_runs=["6999 " + old], watch_exit={"6999": 1},
                           release_run_appears_after=1)
        result = self.box.publish("1.1.0", sha, "--retag")
        self.assert_published(result, sha, build=3)
        self.assertEqual(self.box.calls("run", "watch"), [["run", "watch", "7001", "--exit-status"]])

    def test_it_waits_for_the_run_to_appear(self):
        sha = self.box.release_commit()
        self.box.set_state(release_run_appears_after=1)
        self.assert_published(self.box.publish("1.1.0", sha), sha)
        self.assertEqual(len(self.box.calls("run", "list", "--workflow", "release.yml")), 2)


class AfterTheTagIsPushed(PublishTestCase):
    def assert_stopped_with_the_tag_up(self, result, sha, expected):
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn(expected, result.stderr)
        self.assertIn("v1.1.0 is on GitHub. Running the same command again carries on from here.", result.stderr)
        self.assertEqual(self.box.tag_on_origin("v1.1.0"), sha)

    def test_it_stops_when_no_release_run_appears(self):
        sha = self.box.release_commit()
        self.box.set_state(release_run_appears=False)
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped_with_the_tag_up(result, sha, "no Release run for v1.1.0 has appeared")

    def test_it_stops_when_the_release_run_fails(self):
        sha = self.box.release_commit()
        self.box.set_state(watch_exit={"7001": 1})
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped_with_the_tag_up(result, sha, "the Release run failed")
        self.assertIn("gh run rerun 7001 --failed", result.stderr)
        self.assertEqual(self.box.calls("release", "edit"), [])

    def test_running_again_after_a_failed_run_carries_on(self):
        sha = self.box.release_commit()
        self.box.set_state(watch_exit={"7001": 1})
        self.assertEqual(self.box.publish("1.1.0", sha).returncode, 1)
        self.box.set_state(watch_exit={})     # the rerun passed
        result = self.box.publish("1.1.0", sha)
        self.assert_published(result, sha)
        self.assertIn("won't be pushed again", result.stdout)

    def test_it_stops_when_the_run_passes_but_publishes_nothing(self):
        sha = self.box.release_commit()
        self.box.set_state(workflow_publishes=False)
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped_with_the_tag_up(result, sha, "there is no release for v1.1.0")

    def test_it_stops_when_the_notes_cannot_be_set(self):
        sha = self.box.release_commit()
        self.box.set_state(edit_fails=True)
        result = self.box.publish("1.1.0", sha)
        self.assert_stopped_with_the_tag_up(result, sha, "couldn't set the title and notes")

    def test_running_again_on_a_finished_release_changes_nothing(self):
        sha = self.box.release_commit()
        first = self.assert_published(self.box.publish("1.1.0", sha), sha)
        # The body no longer starts "Build 2.", so the build comes from its Package line
        second = self.assert_published(self.box.publish("1.1.0", sha), sha)
        self.assertEqual(first, second)

    def test_a_build_number_that_is_not_the_commit_count_is_flagged(self):
        sha = self.box.release_commit()
        self.box.set_state(workflow_build="999")
        result = self.box.publish("1.1.0", sha)
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("LOOK AT THIS: the workflow built number 999, but %s is commit number 2" % sha[:7], result.stdout)
        self.assertIn("Published, with 1 thing(s) to look at", result.stdout)
        self.assertIn("build 999.", self.box.state()["release"]["body"])

    def test_notes_that_say_ad_hoc_on_a_notarised_build_are_flagged(self):
        sha = self.box.release_commit()
        self.box.set_state(signing="Signed with Developer ID and notarised.")
        result = self.box.publish("1.1.0", sha)
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("signed with Developer ID and notarised, but the notes' Installation section", result.stdout)

    def test_a_missing_zip_is_flagged(self):
        sha = self.box.release_commit()
        self.box.set_state(assets=["StarBar-v1.1.0.zip.sha256"])
        result = self.box.publish("1.1.0", sha)
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("LOOK AT THIS: the release has no StarBar-v1.1.0.zip.", result.stdout)

    def test_another_release_marked_latest_is_flagged(self):
        sha = self.box.release_commit()
        self.box.set_state(latest="v1.0.0")
        result = self.box.publish("1.1.0", sha)
        self.assertEqual(result.returncode, 1, output(result))
        self.assertIn("GitHub marks v1.0.0 as the latest release, not v1.1.0", result.stdout)


if __name__ == "__main__":
    unittest.main()
