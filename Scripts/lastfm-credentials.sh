# Where a build finds StarBar's Last.fm API key and shared secret, and how they reach Xcode
# without being printed. build.sh sources this file; Scripts/test-lastfm-credentials.sh runs
# the same functions with made-up values, which ./build.sh --test does first. The comment at
# the top of build.sh says where the values come from.
#
# Paths are relative to the folder the caller is in, which for build.sh is the checkout.

# Last.fm's API key and shared secret from the environment, kept in shell variables that aren't
# exported, so neither xcodebuild nor anything else this script starts inherits them
LASTFM_KEY_FROM_ENV="${LASTFM_API_KEY:-}"
LASTFM_SECRET_FROM_ENV="${LASTFM_SHARED_SECRET:-}"
unset LASTFM_API_KEY LASTFM_SHARED_SECRET
# The same bytes as LastfmCredentials.pad in StarBar/Lastfm/LastfmCredentials.swift
LASTFM_PAD=(0x53 0x74 0x61 0x72 0x42 0x61 0x72 0x2A 0x4C 0x61 0x73 0x74 0x2E 0x66 0x6D 0x21)
LASTFM_XCCONFIG="build/StarBarSecrets.xcconfig"
# Set by find_lastfm_credentials
LASTFM_KEY=""
LASTFM_SECRET=""
# Set by prepare_lastfm_credentials before each build
LASTFM_BUILD_ARGS=()
LASTFM_CONCEALED_KEY=""
LASTFM_CONCEALED_SECRET=""

# Sets ENV_VALUE to an env file's value as written after the "=": whitespace trimmed, then one
# pair of matching quotes taken off, then whitespace inside them. Everything that touches the
# key or the secret uses shell builtins only, so neither appears on a command line, where other
# processes could read it.
tidy_env_value() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    ENV_VALUE="$value"
}

# Reads an env file's lines on standard input and sets LASTFM_KEY and LASTFM_SECRET from its
# LASTFM_API_KEY= and LASTFM_SHARED_SECRET= lines, each only when it isn't set already. The
# lines are read, never run.
take_lastfm_lines() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line#export }"
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            LASTFM_API_KEY=*)
                if [ -z "$LASTFM_KEY" ]; then
                    tidy_env_value "${line#LASTFM_API_KEY=}"
                    LASTFM_KEY="$ENV_VALUE"
                fi ;;
            LASTFM_SHARED_SECRET=*)
                if [ -z "$LASTFM_SECRET" ]; then
                    tidy_env_value "${line#LASTFM_SHARED_SECRET=}"
                    LASTFM_SECRET="$ENV_VALUE"
                fi ;;
        esac
    done
    ENV_VALUE=""
}

# Reads a named pipe as an env file, giving up after a while. 1Password mounts an Environment's
# local .env file as one: opening it waits until 1Password is unlocked and the read approved,
# which nobody can do for a build nobody is watching. So a helper opens the file and copies its
# lines into a pipe of this script's own, where a read can time out, and what it read stays in
# memory.
read_lastfm_env_pipe() {
    local file="$1" limit="${STARBAR_ENV_WAIT:-}" relay reader line
    local started=$SECONDS had_key="$LASTFM_KEY" had_secret="$LASTFM_SECRET"
    if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -lt 1 ]; then
        # Someone at a terminal can answer 1Password's prompt; nobody can otherwise
        if [ -t 0 ] || [ -t 1 ]; then limit=60; else limit=10; fi
    fi
    relay=$(mktemp -u "${TMPDIR:-/tmp}/starbar-env.XXXXXX") || return 0
    mkfifo -m 600 "$relay" || return 0
    echo "Last.fm: reading $file, which 1Password has to release (waiting up to $limit s; approve its prompt if it asks)"
    ( exec 3> "$relay"
      while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >&3; done < "$file"
    ) 2> /dev/null &
    reader=$!
    # Opens once the helper has the other end, which it takes before it touches the file
    exec 4< "$relay"
    rm -f "$relay"
    take_lastfm_lines < <(
        if IFS= read -r -t "$limit" -u 4 line; then
            printf '%s\n' "$line"
            while IFS= read -r -t 5 -u 4 line || [ -n "$line" ]; do printf '%s\n' "$line"; done
        fi
    )
    exec 4<&-
    # The helper has finished unless the file never opened. Either way it isn't left behind.
    kill "$reader" 2> /dev/null || true
    wait "$reader" 2> /dev/null || true
    if [ "$LASTFM_KEY" = "$had_key" ] && [ "$LASTFM_SECRET" = "$had_secret" ] && [ $((SECONDS - started)) -ge "$limit" ]; then
        echo "Note: nothing for Last.fm came from $file within $limit s (is 1Password locked?)"
    fi
}

# Reads one env file, if there is one, into LASTFM_KEY and LASTFM_SECRET
read_lastfm_env_file() {
    local file="$1"
    if [ -p "$file" ]; then
        read_lastfm_env_pipe "$file"
    elif [ -f "$file" ] && [ -r "$file" ]; then
        take_lastfm_lines < "$file"
    fi
}

# Prints the main checkout's folder when this one is a git worktree of it, else nothing
main_checkout_dir() {
    local common here
    common=$(cd "$(git rev-parse --git-common-dir 2> /dev/null)" 2> /dev/null && pwd -P) || return 0
    here=$(pwd -P)
    case "$common" in
        */.git) common="${common%/.git}" ;;
        *) return 0 ;;
    esac
    if [ "$common" != "$here" ]; then
        printf '%s' "$common"
    fi
}

lastfm_credentials_found() {
    [ -n "$LASTFM_KEY" ] && [ -n "$LASTFM_SECRET" ]
}

# Sets LASTFM_KEY and LASTFM_SECRET, each from the first place that has it: the environment,
# then the env files in the order the comment at the top gives. Either may be left empty.
find_lastfm_credentials() {
    local main
    tidy_env_value "$LASTFM_KEY_FROM_ENV"
    LASTFM_KEY="$ENV_VALUE"
    tidy_env_value "$LASTFM_SECRET_FROM_ENV"
    LASTFM_SECRET="$ENV_VALUE"
    ENV_VALUE=""
    if ! lastfm_credentials_found && [ -n "${STARBAR_SECRETS_FILE:-}" ]; then
        read_lastfm_env_file "$STARBAR_SECRETS_FILE"
    fi
    if ! lastfm_credentials_found; then
        read_lastfm_env_file ".env"
    fi
    if ! lastfm_credentials_found; then
        main=$(main_checkout_dir)
        if [ -n "$main" ]; then
            read_lastfm_env_file "$main/.env"
        fi
    fi
    if ! lastfm_credentials_found; then
        read_lastfm_env_file "$HOME/.config/starbar/secrets.env"
    fi
}

# Prints a value as LastfmCredentials.conceal stores it: each UTF-8 byte XORed with
# LASTFM_PAD, repeating, as two lowercase hex digits. Builtins only, as above. Run it in a
# command substitution, since it sets LC_ALL=C so that the string is walked byte by byte.
conceal_lastfm_value() {
    local value="$1" out="" i byte
    export LC_ALL=C
    for (( i = 0; i < ${#value}; i++ )); do
        printf -v byte '%d' "'${value:i:1}"
        printf -v byte '%02x' $(( (byte & 0xFF) ^ LASTFM_PAD[i % ${#LASTFM_PAD[@]}] ))
        out+="$byte"
    done
    printf '%s' "$out"
}

# Writes build/StarBarSecrets.xcconfig and sets LASTFM_BUILD_ARGS to pass it, or removes it
# when the key or the secret is missing. Called before every build, after any clean, so a
# watch-mode rebuild picks up an env file changed meanwhile. Prints nothing of either value:
# the pad is in this public repository, so a concealed value is as good as the value itself to
# anyone who reads it.
prepare_lastfm_credentials() {
    find_lastfm_credentials
    LASTFM_BUILD_ARGS=()
    LASTFM_CONCEALED_KEY=""
    LASTFM_CONCEALED_SECRET=""
    if ! lastfm_credentials_found; then
        rm -f "$LASTFM_XCCONFIG"
        if [ -n "$LASTFM_KEY" ]; then
            echo "Note: a Last.fm API key but no shared secret (LASTFM_SHARED_SECRET), so this build can't connect to Last.fm"
        elif [ -n "$LASTFM_SECRET" ]; then
            echo "Note: a Last.fm shared secret but no API key (LASTFM_API_KEY), so this build can't connect to Last.fm"
        else
            echo "Note: no Last.fm API key and shared secret (LASTFM_API_KEY, LASTFM_SHARED_SECRET), so this build can't connect to Last.fm"
        fi
        LASTFM_KEY=""
        LASTFM_SECRET=""
        return 0
    fi
    if ! [[ "$LASTFM_KEY" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "Warning: the Last.fm API key isn't 32 hexadecimal characters, the form Last.fm issues. Building with it anyway."
    fi
    if ! [[ "$LASTFM_SECRET" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "Warning: the Last.fm shared secret isn't 32 hexadecimal characters, the form Last.fm issues. Building with it anyway."
    fi
    LASTFM_CONCEALED_KEY=$(conceal_lastfm_value "$LASTFM_KEY")
    LASTFM_CONCEALED_SECRET=$(conceal_lastfm_value "$LASTFM_SECRET")
    LASTFM_KEY=""
    LASTFM_SECRET=""
    mkdir -p build
    rm -f "$LASTFM_XCCONFIG"
    # umask in a subshell, so the file is created 0600 and never readable by anyone else
    ( umask 077; printf 'STARBAR_LASTFM_KEY = %s\nSTARBAR_LASTFM_SECRET = %s\n' "$LASTFM_CONCEALED_KEY" "$LASTFM_CONCEALED_SECRET" > "$LASTFM_XCCONFIG" )
    chmod 600 "$LASTFM_XCCONFIG"
    LASTFM_BUILD_ARGS=(-xcconfig "$LASTFM_XCCONFIG")
    echo "Last.fm: building with the API key and shared secret"
}

# xcodebuild echoes the settings it reads from an -xcconfig file at the top of its output, and
# a failed build prints the whole log, so the concealed values are taken out of the log before
# any of it is shown. They go to grep through a file descriptor, not as arguments.
redact_build_log() {
    local log="$1" redacted line
    [ -n "$LASTFM_CONCEALED_KEY" ] && [ -n "$LASTFM_CONCEALED_SECRET" ] || return 0
    grep -qF -f <(printf '%s\n%s\n' "$LASTFM_CONCEALED_KEY" "$LASTFM_CONCEALED_SECRET") "$log" || return 0
    redacted=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//$LASTFM_CONCEALED_SECRET/[Last.fm secret]}"
        printf '%s\n' "${line//$LASTFM_CONCEALED_KEY/[Last.fm key]}"
    done < "$log" > "$redacted"
    mv "$redacted" "$log"
}
