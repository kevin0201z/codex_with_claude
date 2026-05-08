#!/usr/bin/env bash
set -euo pipefail

RUN_ID=""
ARTIFACT_ROOT=""
TIMEOUT_SECONDS=1800
POLL_MILLISECONDS=1000
QUIET=false

usage() {
    cat <<EOF
Usage: $0 -r RUN_ID -a ARTIFACT_ROOT [OPTIONS]

Options:
  -r, --run-id RUN_ID          Delegate run id
  -a, --artifact-root PATH     Delegate artifact root
  --timeout-seconds N          Wait timeout in seconds (default: 1800)
  --poll-milliseconds N        Poll interval in milliseconds (default: 1000)
  --quiet                      Print only errors
  -h, --help                   Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--run-id)
            RUN_ID="$2"
            shift 2
            ;;
        -a|--artifact-root)
            ARTIFACT_ROOT="$2"
            shift 2
            ;;
        --timeout-seconds)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --poll-milliseconds)
            POLL_MILLISECONDS="$2"
            shift 2
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$RUN_ID" ]]; then
    echo "RunId is required." >&2
    exit 1
fi

if [[ -z "$ARTIFACT_ROOT" ]]; then
    echo "Artifact root is required." >&2
    exit 1
fi

STATUS_PATH="$ARTIFACT_ROOT/status_${RUN_ID}.json"
CONFIG_PATH="$ARTIFACT_ROOT/config_${RUN_ID}.json"
OUTPUT_PATH="$ARTIFACT_ROOT/claude_${RUN_ID}.md"
TRACE_PATH="$ARTIFACT_ROOT/trace_${RUN_ID}.log"

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))

while true; do
    if [[ -f "$STATUS_PATH" ]]; then
        delegate_status=$(jq -r '.status // ""' "$STATUS_PATH")
        case "$delegate_status" in
            completed|failed)
                break
                ;;
        esac
    fi

    if [[ $(date +%s) -ge $deadline ]]; then
        echo "Timed out waiting for delegate run $RUN_ID. Status file: $STATUS_PATH" >&2
        exit 124
    fi

    poll_secs=$(awk "BEGIN {printf \"%.3f\", $POLL_MILLISECONDS / 1000}")
    sleep "$poll_secs"
done

delegate_status=$(jq -r '.status // ""' "$STATUS_PATH")
exit_code=$(jq -r '.exitCode // ""' "$STATUS_PATH")
resolved_output_path=$(jq -r '.outputPath // ""' "$STATUS_PATH")
resolved_trace_path=$(jq -r '.tracePath // ""' "$STATUS_PATH")
failure_summary=""
if [[ -f "$CONFIG_PATH" ]]; then
    failure_summary=$(jq -r '.failureSummary // ""' "$CONFIG_PATH")
fi

if [[ "$QUIET" != "true" ]]; then
    echo "RunId: $RUN_ID"
    echo "Delegate Status: $delegate_status"
    echo "Exit Code: ${exit_code:-<null>}"
    echo "Status File: $STATUS_PATH"
    echo "Config File: $CONFIG_PATH"
    echo "Output File: ${resolved_output_path:-$OUTPUT_PATH}"
    echo "Trace File: ${resolved_trace_path:-$TRACE_PATH}"
fi

if [[ "$delegate_status" == "completed" ]]; then
    if [[ "$QUIET" != "true" ]]; then
        echo "Final Result: delegate completed successfully."
    fi
    exit 0
fi

if [[ -n "$failure_summary" ]]; then
    echo "Delegate failed: $failure_summary" >&2
else
    echo "Delegate failed. See artifacts for details." >&2
fi
exit 1

