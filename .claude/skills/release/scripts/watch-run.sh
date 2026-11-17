#!/bin/bash
# Watch a GitHub Actions run step by step. The step that is running is marked, with how long it has
# run and how long it took in the workflow's last successful run. `gh run watch` marks a running
# step and a waiting one with the same `*`, so a long step looked stuck (1.10.0, "Run tests").
# Usage: watch-run.sh <run ID> [owner/repo]   (repo defaults to rossshannon/StarBar)
# Exits 0 when the run succeeds and 1 when it doesn't. It only reads: Ctrl-C stops watching and
# leaves the run alone. Needs gh, signed in. Runs under the Mac's bash 3.2.
set -uo pipefail
RUN="${1:?pass the run ID}"
REPO="${2:-rossshannon/StarBar}"
POLL="${WATCH_RUN_POLL:-5}"   # seconds between questions to GitHub (tests shorten it); the clock on screen ticks every second
US=$'\x1f'      # field separator: not whitespace, so `read` keeps empty fields

command -v gh >/dev/null || { echo "This needs gh (brew install gh), signed in to GitHub"; exit 1; }

if [ -t 1 ]; then
  TTY=1
  GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
else
  TTY=0; GREEN=""; RED=""; YELLOW=""; DIM=""; BOLD=""; OFF=""
fi
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# ISO times to epoch seconds, empty for null. GitHub sometimes adds fractions of a second.
JQ_TIME='def t: if . == null or . == "" then "" else (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) end;'

duration() {   # seconds -> "45s" or "2m 05s"
  local s=$1
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"; else printf '%dm %02ds' $((s / 60)) $((s % 60)); fi
}

# How long each step took in the workflow's last successful run, as two parallel arrays
PREV_NAMES=(); PREV_SECS=()
load_previous() {
  local wf=$1 prev line name secs
  prev=$(gh api "repos/$REPO/actions/workflows/$wf/runs?status=success&per_page=5" \
    --jq "[.workflow_runs[] | select(.id != $RUN)][0].id // empty" 2>/dev/null) || return 0
  [ -n "$prev" ] || return 0
  while IFS="$US" read -r name secs; do
    [ -n "$name" ] || continue
    PREV_NAMES+=("$name"); PREV_SECS+=("$secs")
  done < <(gh api "repos/$REPO/actions/runs/$prev/jobs?per_page=100" --jq "$JQ_TIME"'
    .jobs[].steps[] | select(.conclusion == "success" and .started_at != null and .completed_at != null)
    | [.name, ((.completed_at | t) - (.started_at | t))] | map(tostring) | join("\u001f")' 2>/dev/null)
}
previous_secs() {   # step name -> seconds last time, or nothing
  local i
  for ((i = 0; i < ${#PREV_NAMES[@]}; i++)); do
    [ "${PREV_NAMES[$i]}" = "$1" ] && { echo "${PREV_SECS[$i]}"; return; }
  done
}

RUN_INFO=""; JOBS=""; FETCH_NOTE=""
fetch() {
  local info jobs
  info=$(gh api "repos/$REPO/actions/runs/$RUN" --jq "$JQ_TIME"'
    [.status, (.conclusion // ""), .head_branch, .name, (.run_started_at | t), .workflow_id, .html_url]
    | map(tostring) | join("\u001f")' 2>/dev/null) &&
  jobs=$(gh api "repos/$REPO/actions/runs/$RUN/jobs?per_page=100" --jq "$JQ_TIME"'
    .jobs[] | (["J", .name, .status, (.conclusion // ""), (.started_at | t), (.completed_at | t)] | map(tostring) | join("\u001f")),
              (.steps[] | ["S", .name, .status, (.conclusion // ""), (.started_at | t), (.completed_at | t)] | map(tostring) | join("\u001f"))' 2>/dev/null)
  if [ -n "${info:-}" ] && [ -n "${jobs:-}" ]; then
    RUN_INFO=$info; JOBS=$jobs; FETCH_NOTE=""
  else
    FETCH_NOTE="GitHub didn't answer at $(date +%H:%M:%S); asking again"
  fi
}

render() {   # prints the whole screen; with plain=1, nothing that changes every second
  local now=$1 tick=$2 plain=${3:-0} status conclusion title name started wf url
  IFS="$US" read -r status conclusion title name started wf url <<< "$RUN_INFO"
  local total=""
  [ -n "$started" ] && [ "$plain" = 0 ] && total=$(duration $((now - started)))
  printf '%s%s%s · %s · run %s%s\n\n' "$BOLD" "$title" "$OFF" "$name" "$RUN" "${total:+ · $total}"

  local width=0 kind sname sstatus sconc sstart send
  while IFS="$US" read -r kind sname _; do
    [ ${#sname} -gt $width ] && width=${#sname}
  done <<< "$JOBS"

  while IFS="$US" read -r kind sname sstatus sconc sstart send; do
    [ -n "$kind" ] || continue
    if [ "$kind" = J ]; then
      printf '%s%s%s\n' "$BOLD" "$sname" "$OFF"; continue
    fi
    local mark colour took="" note=""
    case "$sstatus/$sconc" in
      completed/success)
        mark="✓"; colour=$GREEN
        [ -n "$sstart" ] && [ -n "$send" ] && took=$(duration $((send - sstart))) ;;
      completed/skipped)
        mark="–"; colour=$DIM; note="skipped" ;;
      completed/*)
        mark="✗"; colour=$RED; note="${sconc:-failed}"
        [ -n "$sstart" ] && [ -n "$send" ] && took=$(duration $((send - sstart))) ;;
      in_progress/*)
        mark="▶"; colour="$YELLOW$BOLD"
        local last spin=""; last=$(previous_secs "$sname")
        if [ "$plain" = 0 ]; then
          [ -n "$sstart" ] && took=$(duration $((now - sstart)))
          spin="${SPINNER[$((tick % ${#SPINNER[@]}))]} "
        fi
        note="${spin}running${last:+ (last time $(duration "$last"))}" ;;
      *)
        mark="·"; colour=$DIM; note="waiting" ;;
    esac
    printf '  %s%s %-*s %8s  %s%s\n' "$colour" "$mark" "$width" "$sname" "$took" "$note" "$OFF"
  done <<< "$JOBS"

  [ -n "$FETCH_NOTE" ] && printf '\n%s%s%s\n' "$YELLOW" "$FETCH_NOTE" "$OFF"
  if [ "$status" = completed ]; then
    local c=$GREEN; [ "$conclusion" = success ] || c=$RED
    printf '\n%sRun %s: %s%s  %s\n' "$c$BOLD" "$status" "$conclusion" "$OFF" "$url"
  else
    printf '\n%sChecking GitHub every %d s. Ctrl-C stops watching; the run carries on.%s\n' "$DIM" "$POLL" "$OFF"
  fi
}

tries=0
until fetch; [ -n "$RUN_INFO" ]; do
  tries=$((tries + 1))
  [ $tries -ge 3 ] && { echo "GitHub has no run $RUN in $REPO, or didn't answer; check the ID and that gh is signed in"; exit 1; }
  sleep "$POLL"
done
load_previous "$(IFS="$US" read -r _ _ _ _ _ wf _ <<< "$RUN_INFO"; echo "$wf")"

if [ $TTY = 1 ]; then
  printf '\033[?25l\033[2J'                     # hide the cursor, clear the screen once
  trap 'printf "\033[?25h\n"; exit 130' INT TERM
fi
tick=0; last_poll=$(date +%s); last_screen=""
while :; do
  now=$(date +%s)
  if [ $((now - last_poll)) -ge $POLL ]; then fetch; last_poll=$now; fi
  if [ $TTY = 1 ]; then
    # Draw over the last screen in place, clearing each line's end and what lies below
    screen=$(render "$now" "$tick")
    printf '\033[H%s\033[J' "${screen//$'\n'/$'\033[K\n'}"
  else
    # Not a terminal (a log): print the steps again only when something has changed
    screen=$(render "$now" 0 1)
    [ "$screen" != "$last_screen" ] && { printf '%s\n\n' "$screen"; last_screen=$screen; }
  fi
  IFS="$US" read -r status conclusion _ <<< "$RUN_INFO"
  [ "$status" = completed ] && break
  sleep 1; tick=$((tick + 1))
done
[ $TTY = 1 ] && printf '\033[?25h\n'
[ "$conclusion" = success ]
