#!/bin/bash

# Checks how a build finds the Last.fm API key and shared secret and keeps them out of what it
# prints (Scripts/lastfm-credentials.sh), with made-up values.
#
#   Scripts/test-lastfm-credentials.sh
#
# ./build.sh --test runs it first, under /bin/bash as build.sh itself runs, which on macOS is
# bash 3.2: reading a named pipe with a time limit leans on `read -t`, process substitution and
# a second pipe, which is where an old bash would differ from the one this was written with.
#
# It never reads a real .env. Every case runs in an empty folder of its own under the temporary
# folder, with HOME pointed there too, the build's variables cleared, and git kept from looking
# above it. A case still running after its time limit fails, so a read that never gives up fails
# here instead of hanging the run.

set -o pipefail

LIBRARY="$(cd "$(dirname "$0")" && pwd -P)/lastfm-credentials.sh"
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/starbar-credentials-test.XXXXXX") || exit 1
SANDBOX=$(cd "$SANDBOX" && pwd -P)
trap 'rm -rf "$SANDBOX"' EXIT

# Made up, in the form Last.fm issues: 32 hexadecimal characters
KEY="0123456789abcdef0123456789abcdef"
SECRET="fedcba9876543210fedcba9876543210"
# Each XORed with LastfmCredentials.pad by hand (Python). The first pair is the one
# LastfmCredentialsTests holds the app's own conceal and reveal to, so the two can't drift apart.
KEY_CONCEALED="634553417654441d745812164d020847634553417654441d745812164d020847"
SECRET_CONCEALED="3511051120004b127b5746401d545c113511051120004b127b5746401d545c11"

CASES=0
FAILED=0

# Ends the case it is called from
fail() {
    echo "$*"
    exit 1
}

expect_both_values() {
    [ "$LASTFM_KEY" = "$KEY" ] || fail "the key read was [$LASTFM_KEY]"
    [ "$LASTFM_SECRET" = "$SECRET" ] || fail "the secret read was [$LASTFM_SECRET]"
}

# run_case <what it checks> <seconds it may take> <function>
run_case() {
    local name="$1" limit="$2" body="$3" dir="$SANDBOX/case$CASES" pid polls=0
    CASES=$((CASES + 1))
    mkdir -p "$dir/work" "$dir/home"
    (
        cd "$dir/work" || exit 1
        export HOME="$dir/home"
        export GIT_CEILING_DIRECTORIES="$SANDBOX"
        unset LASTFM_API_KEY LASTFM_SHARED_SECRET STARBAR_SECRETS_FILE STARBAR_ENV_WAIT
        # A commit hook sets these, and they would point the worktree case at the real checkout
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX
        # As build.sh runs them
        set -e
        "$body"
    ) > "$dir/output" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2> /dev/null; do
        if [ "$polls" -ge $((limit * 5)) ]; then
            kill "$pid" 2> /dev/null
            wait "$pid" 2> /dev/null
            echo "FAILED: $name (still running after $limit s)"
            sed 's/^/    /' "$dir/output"
            FAILED=$((FAILED + 1))
            return 0
        fi
        sleep 0.2
        polls=$((polls + 1))
    done
    if wait "$pid"; then
        echo "ok: $name"
    else
        echo "FAILED: $name"
        sed 's/^/    /' "$dir/output"
        FAILED=$((FAILED + 1))
    fi
}

# Windows line endings, export, both kinds of quotes, and a last line with no newline
case_plain_file() {
    printf "# keys\r\nOTHER=1\r\n  export LASTFM_API_KEY=\"%s\"\r\nLASTFM_SHARED_SECRET=' %s '" "$KEY" "$SECRET" > .env
    source "$LIBRARY"
    find_lastfm_credentials
    expect_both_values
}

case_environment_first() {
    printf 'LASTFM_API_KEY=fromthefile\nLASTFM_SHARED_SECRET=fromthefile\n' > .env
    export LASTFM_API_KEY=" $KEY " LASTFM_SHARED_SECRET="$SECRET"
    source "$LIBRARY"
    if env | grep -q '^LASTFM_'; then
        fail "the values were left in the environment, where xcodebuild would inherit them"
    fi
    find_lastfm_credentials
    expect_both_values
}

# Each value comes from the first place that has it
case_order_of_files() {
    printf 'LASTFM_API_KEY=%s\n' "$KEY" > named.env
    printf 'LASTFM_API_KEY=beside\n' > .env
    mkdir -p "$HOME/.config/starbar"
    printf 'LASTFM_API_KEY=home\nLASTFM_SHARED_SECRET=%s\n' "$SECRET" > "$HOME/.config/starbar/secrets.env"
    export STARBAR_SECRETS_FILE="$PWD/named.env"
    source "$LIBRARY"
    find_lastfm_credentials
    expect_both_values
}

case_worktree_reads_main_checkout() {
    if ! command -v git > /dev/null; then
        echo "git not found, so this case checked nothing"
        return 0
    fi
    git init main > /dev/null 2>&1 || fail "git init failed"
    git -C main -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -m first > /dev/null 2>&1 || fail "git commit failed"
    git -C main worktree add --detach .worktrees/feature > /dev/null 2>&1 || fail "git worktree add failed"
    printf 'LASTFM_API_KEY=%s\nLASTFM_SHARED_SECRET=%s\n' "$KEY" "$SECRET" > main/.env
    cd main/.worktrees/feature
    source "$LIBRARY"
    find_lastfm_credentials
    expect_both_values
}

case_one_value_missing() {
    mkdir build
    echo "STARBAR_LASTFM_KEY = stale" > build/StarBarSecrets.xcconfig
    printf 'LASTFM_API_KEY=%s\n' "$KEY" > .env
    source "$LIBRARY"
    prepare_lastfm_credentials > said.txt
    grep -q "no shared secret" said.txt || fail "didn't say the secret was missing: $(cat said.txt)"
    [ ! -e build/StarBarSecrets.xcconfig ] || fail "an xcconfig from an earlier build was left in place"
    [ "${#LASTFM_BUILD_ARGS[@]}" -eq 0 ] || fail "xcodebuild was still given ${LASTFM_BUILD_ARGS[*]}"
    if grep -qF "$KEY" said.txt; then
        fail "the key was printed"
    fi
}

case_xcconfig() {
    printf 'LASTFM_API_KEY=%s\nLASTFM_SHARED_SECRET=%s\n' "$KEY" "$SECRET" > .env
    source "$LIBRARY"
    prepare_lastfm_credentials > said.txt 2>&1
    grep -qxF "STARBAR_LASTFM_KEY = $KEY_CONCEALED" build/StarBarSecrets.xcconfig \
        || fail "the key isn't in the xcconfig as LastfmCredentials.reveal expects it"
    grep -qxF "STARBAR_LASTFM_SECRET = $SECRET_CONCEALED" build/StarBarSecrets.xcconfig \
        || fail "the secret isn't in the xcconfig as LastfmCredentials.reveal expects it"
    [ "$(grep -c '' build/StarBarSecrets.xcconfig)" -eq 2 ] || fail "the xcconfig holds more than the two settings"
    case "$(ls -l build/StarBarSecrets.xcconfig)" in
        -rw-------*) ;;
        *) fail "the xcconfig can be read by others: $(ls -l build/StarBarSecrets.xcconfig)" ;;
    esac
    [ "${LASTFM_BUILD_ARGS[*]}" = "-xcconfig build/StarBarSecrets.xcconfig" ] || fail "xcodebuild was given [${LASTFM_BUILD_ARGS[*]}]"
    [ -z "$LASTFM_KEY$LASTFM_SECRET" ] || fail "the plain values were kept after concealing them"
    grep -q "building with the API key and shared secret" said.txt || fail "didn't say it had them: $(cat said.txt)"
    if grep -qF -e "$KEY" -e "$SECRET" -e "$KEY_CONCEALED" -e "$SECRET_CONCEALED" said.txt; then
        fail "a value was printed, plain or concealed"
    fi
}

# xcodebuild echoes an -xcconfig file's settings, and a failed build prints its whole log
case_redaction() {
    printf 'LASTFM_API_KEY=%s\nLASTFM_SHARED_SECRET=%s\n' "$KEY" "$SECRET" > .env
    source "$LIBRARY"
    prepare_lastfm_credentials > /dev/null
    printf 'Build settings from configuration file:\n    STARBAR_LASTFM_KEY = %s\n    STARBAR_LASTFM_SECRET = %s\nboth %s and %s, then %s again\nCompileSwift normal arm64\nlast line, no newline' \
        "$KEY_CONCEALED" "$SECRET_CONCEALED" "$SECRET_CONCEALED" "$KEY_CONCEALED" "$SECRET_CONCEALED" > log.txt
    redact_build_log log.txt
    if grep -qF -e "$KEY_CONCEALED" -e "$SECRET_CONCEALED" log.txt; then
        fail "a concealed value is still in the log"
    fi
    grep -qxF "    STARBAR_LASTFM_KEY = [Last.fm key]" log.txt || fail "the key's line isn't marked"
    grep -qxF "    STARBAR_LASTFM_SECRET = [Last.fm secret]" log.txt || fail "the secret's line isn't marked"
    grep -qxF "both [Last.fm secret] and [Last.fm key], then [Last.fm secret] again" log.txt || fail "a line with several wasn't cleared of all of them"
    grep -qxF "CompileSwift normal arm64" log.txt || fail "a line with neither was changed"
    grep -qxF "last line, no newline" log.txt || fail "the last line was lost"
}

# 1Password's .env: a named pipe that is written once the read is approved
case_pipe_released_late() {
    mkfifo .env
    ( sleep 1; printf 'LASTFM_API_KEY=%s\nLASTFM_SHARED_SECRET=%s\n' "$KEY" "$SECRET" > .env ) &
    export STARBAR_ENV_WAIT=10
    source "$LIBRARY"
    find_lastfm_credentials > said.txt
    expect_both_values
    grep -q "waiting up to 10 s" said.txt || fail "didn't say it was waiting: $(cat said.txt)"
    if grep -q "nothing for Last.fm came" said.txt; then
        fail "said nothing came, though both values did"
    fi
}

# 1Password locked, or its prompt left unanswered: nothing ever opens the other end
case_pipe_never_released() {
    local started=$SECONDS
    mkfifo .env
    export STARBAR_ENV_WAIT=2
    source "$LIBRARY"
    find_lastfm_credentials > said.txt
    [ -z "$LASTFM_KEY$LASTFM_SECRET" ] || fail "read a value from a pipe nobody wrote to"
    [ $((SECONDS - started)) -ge 2 ] || fail "gave up before the 2 s it was told to wait"
    grep -q "nothing for Last.fm came from .env within 2 s" said.txt || fail "didn't say it had given up: $(cat said.txt)"
    jobs -pr > helpers.txt
    [ ! -s helpers.txt ] || fail "left its helper waiting on the pipe"
    # And the build goes on without them
    prepare_lastfm_credentials > said.txt
    grep -q "no Last.fm API key and shared secret" said.txt || fail "didn't say the build has neither: $(cat said.txt)"
}

run_case "an env file's quotes, export and line endings" 10 case_plain_file
run_case "the environment comes before any file" 10 case_environment_first
run_case "each value comes from the first file that has it" 10 case_order_of_files
run_case "a worktree build reads the main checkout's .env" 20 case_worktree_reads_main_checkout
run_case "one value without the other builds without either" 10 case_one_value_missing
run_case "the xcconfig holds both concealed, for its owner only, and nothing is printed" 10 case_xcconfig
run_case "the build log is cleared of both concealed values" 10 case_redaction
run_case "a named pipe that is released late is read" 20 case_pipe_released_late
run_case "a named pipe that is never released is given up on" 20 case_pipe_never_released

if [ "$FAILED" -gt 0 ]; then
    echo "$FAILED of $CASES Last.fm credentials checks failed"
    exit 1
fi
echo "All $CASES Last.fm credentials checks passed"
