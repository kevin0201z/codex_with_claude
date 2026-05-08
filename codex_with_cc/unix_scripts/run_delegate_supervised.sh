#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DELEGATE_SCRIPT="$SCRIPT_DIR/delegate_to_claude.sh"
WAIT_SCRIPT="$SCRIPT_DIR/wait_for_delegate_run.sh"

WAIT_TIMEOUT_SECONDS=1800
WAIT_POLL_MILLISECONDS=1000
QUIET_WAIT=false
DELEGATE_ARGS=()

usage() {
    cat <<EOF
Usage: $0 [delegate_to_claude options] [wait options]

Wait options:
  --wait-timeout-seconds N      Wait timeout in seconds after launch (default: 1800)
  --wait-poll-milliseconds N    Wait poll interval in milliseconds (default: 1000)
  --quiet-wait                  Suppress successful wait summary
  -h, --help                    Show this help message

All other arguments are passed through to delegate_to_claude.sh.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --wait-timeout-seconds)
            WAIT_TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --wait-poll-milliseconds)
            WAIT_POLL_MILLISECONDS="$2"
            shift 2
            ;;
        --quiet-wait)
            QUIET_WAIT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            DELEGATE_ARGS+=("$1")
            shift
            ;;
    esac
done

capture_file=$(mktemp)
cleanup() {
    rm -f "$capture_file"
}
trap cleanup EXIT

set +e
bash "$DELEGATE_SCRIPT" "${DELEGATE_ARGS[@]}" 2>&1 | tee "$capture_file"
delegate_exit=${PIPESTATUS[0]}
set -e

run_id=$(sed -n 's/^RunId: //p' "$capture_file" | tail -n1)
status_path=$(sed -n 's/^Status: //p' "$capture_file" | tail -n1)

if [[ -z "$run_id" || -z "$status_path" ]]; then
    exit "$delegate_exit"
fi

artifact_root=$(dirname "$status_path")
wait_args=(
    -r "$run_id"
    -a "$artifact_root"
    --timeout-seconds "$WAIT_TIMEOUT_SECONDS"
    --poll-milliseconds "$WAIT_POLL_MILLISECONDS"
)
if [[ "$QUIET_WAIT" == "true" ]]; then
    wait_args+=(--quiet)
fi

set +e
bash "$WAIT_SCRIPT" "${wait_args[@]}"
wait_exit=$?
set -e

if [[ "$wait_exit" -ne 0 ]]; then
    exit "$wait_exit"
fi

exit "$delegate_exit"
