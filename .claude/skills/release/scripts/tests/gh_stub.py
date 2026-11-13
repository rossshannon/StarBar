#!/usr/bin/env python3
"""A stand-in for gh, for the release scripts' tests.

It answers only the calls publish.sh makes, from a JSON file named by GH_STUB_STATE, and
exits 97 for anything else, so a call the tests don't expect fails loudly. It keeps every
call it gets under "calls" in that file.

It plays GitHub's side of a release: once the tag is on the origin repository a Release run
"appears", and watching that run to the end "publishes" a release with the one-line body
the real workflow writes.
"""
import json
import os
import subprocess
import sys


def git(state, *args):
    result = subprocess.run(
        ["git", "--git-dir", state["origin"], *args],
        capture_output=True, text=True, check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def option(args, name):
    return args[args.index(name) + 1] if name in args else None


def unexpected(args, why):
    sys.stderr.write("gh stub: unexpected call (%s): %s\n" % (why, " ".join(args)))
    return 97


def release_for(state, tag):
    release = state.get("release")
    return release if release and release["tag"] == tag else None


def handle(args, state):
    if args[:2] == ["auth", "status"]:
        return 0 if state.get("signed_in", True) else 1

    # Everything else has to be aimed at the repository under test
    if os.environ.get("GH_REPO") != state["repo"]:
        return unexpected(args, "GH_REPO is %r" % os.environ.get("GH_REPO"))

    if args[:2] == ["run", "list"]:
        workflow = option(args, "--workflow")
        if workflow == "test.yml":
            if option(args, "--event") != "push" or not option(args, "--commit"):
                return unexpected(args, "the test runs must be asked for by commit and push event")
            runs = state.get("test_runs", {}).get(option(args, "--commit"), [])
            sys.stdout.write("".join(line + "\n" for line in runs))
            return 0
        if workflow == "release.yml" and option(args, "--json") == "databaseId,status":
            # The runs for a tag that have not finished
            sys.stdout.write("".join(run + "\n" for run in state.get("unfinished_release_runs", [])))
            return 0
        if workflow == "release.yml":
            tag = option(args, "--branch")
            lines = list(state.get("other_release_runs", []))
            tagged = git(state, "rev-parse", "-q", "--verify", "refs/tags/%s^{commit}" % tag)
            # GitHub takes a few seconds to start a run: "release_run_appears_after" is how
            # many times the list is asked for before the run is in it
            asked_before = sum(1 for call in state["calls"][:-1]
                               if call[:2] == ["run", "list"] and "release.yml" in call)
            appeared = asked_before >= state.get("release_run_appears_after", 0)
            if tagged and appeared and state.get("release_run_appears", True):
                lines.insert(0, "%s %s" % (state["release_run"], tagged))
            sys.stdout.write("".join(line + "\n" for line in lines))
            return 0
        return unexpected(args, "unknown workflow")

    if args[:2] == ["run", "watch"]:
        run = args[2]
        code = state.get("watch_exit", {}).get(run, 0)
        print("watching run %s" % run)
        if run == str(state.get("release_run")) and code == 0 and state.get("workflow_publishes", True):
            tag = state["tag"]
            if not release_for(state, tag):
                build = state.get("workflow_build") or git(state, "rev-list", "--count", tag)
                signing = state.get(
                    "signing",
                    "Signed ad hoc, not notarised: macOS blocks it the first time it opens.",
                )
                state["release"] = {
                    "tag": tag,
                    "name": "StarBar %s" % tag[1:],
                    "body": "Build %s. %s\n\n**Full Changelog**: https://example.invalid/compare\n" % (build, signing),
                    "assets": state.get("assets", ["StarBar-%s.zip" % tag, "StarBar-%s.zip.sha256" % tag]),
                }
        return code

    if args[:2] == ["release", "view"]:
        release = release_for(state, args[2])
        if not release:
            sys.stderr.write("release not found\n")
            return 1
        field = option(args, "--json")
        if field == "body":
            sys.stdout.write(release["body"] + "\n")
        elif field == "name":
            print(release["name"])
        elif field == "url":
            print("https://github.com/%s/releases/tag/%s" % (state["repo"], release["tag"]))
        elif field == "tagName":
            print(json.dumps({"tagName": release["tag"]}))
        elif field == "assets":
            sys.stdout.write("".join(name + "\n" for name in release["assets"]))
        else:
            return unexpected(args, "unknown field")
        return 0

    if args[:2] == ["release", "edit"]:
        release = release_for(state, args[2])
        if not release or state.get("edit_fails"):
            sys.stderr.write("could not edit the release\n")
            return 1
        release["name"] = option(args, "--title")
        with open(option(args, "--notes-file"), encoding="utf-8") as notes:
            release["body"] = notes.read()
        return 0

    if args[:2] == ["release", "list"]:
        release = state.get("release")
        latest = state.get("latest", release["tag"] if release else "")
        if latest:
            print(latest)
        return 0

    if args[:2] == ["release", "download"]:
        release = release_for(state, args[2])
        wanted = "StarBar-%s.zip.sha256" % args[2]
        if not release or option(args, "--pattern") != wanted or wanted not in release["assets"]:
            sys.stderr.write("no assets match\n")
            return 1
        print("%s  StarBar-%s.zip" % ("ab" * 32, args[2]))
        return 0

    return unexpected(args, "not a call publish.sh is known to make")


def main():
    args = sys.argv[1:]
    path = os.environ["GH_STUB_STATE"]
    with open(path, encoding="utf-8") as handle_in:
        state = json.load(handle_in)
    state.setdefault("calls", []).append(args)
    code = handle(args, state)
    with open(path, "w", encoding="utf-8") as handle_out:
        json.dump(state, handle_out, indent=1)
    sys.exit(code)


if __name__ == "__main__":
    main()
