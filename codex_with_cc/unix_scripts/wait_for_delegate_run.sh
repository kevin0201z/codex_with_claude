#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/verify_delegate_artifacts.sh"

RUN_ID=""
ARTIFACT_ROOT=""
TIMEOUT_SECONDS=1800
POLL_MILLISECONDS=1000
QUIET=false

cleanup_files=()

cleanup() {
    local path
    for path in "${cleanup_files[@]:-}"; do
        rm -f "$path"
    done
}
trap cleanup EXIT

trim_blank_lines() {
    awk '
        BEGIN { started = 0 }
        {
            lines[++count] = $0
        }
        END {
            while (count > 0 && lines[count] ~ /^[[:space:]]*$/) {
                count--
            }
            for (i = 1; i <= count; i++) {
                if (!started && lines[i] ~ /^[[:space:]]*$/) {
                    continue
                }
                started = 1
                print lines[i]
            }
        }
    '
}

extract_report_section() {
    local file_path="$1"
    local heading="$2"

    awk -v heading="$heading" '
        $0 == heading {
            capture = 1
            next
        }
        capture && $0 ~ /^(Process Log|Summary|Changed Files|Verification|Final Result|Risks Or Follow-ups)$/ {
            exit
        }
        capture {
            print
        }
    ' "$file_path" | trim_blank_lines
}

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
verify_output_file=$(mktemp)
cleanup_files+=("$verify_output_file")
last_verify_error=""

if [[ ! -x "$VERIFY_SCRIPT" ]] && [[ ! -f "$VERIFY_SCRIPT" ]]; then
    echo "Missing artifact verification script: $VERIFY_SCRIPT" >&2
    exit 1
fi

while true; do
    if [[ -f "$STATUS_PATH" ]]; then
        delegate_status=$(jq -r '.status // ""' "$STATUS_PATH")
        case "$delegate_status" in
            completed|failed)
                if bash "$VERIFY_SCRIPT" -r "$RUN_ID" -a "$ARTIFACT_ROOT" >"$verify_output_file" 2>&1; then
                    break
                fi
                last_verify_error=$(cat "$verify_output_file")
                ;;
        esac
    fi

    if [[ $(date +%s) -ge $deadline ]]; then
        echo "Timed out waiting for delegate run $RUN_ID. Status file: $STATUS_PATH" >&2
        if [[ -n "$last_verify_error" ]]; then
            echo "Artifact verification did not pass before timeout:" >&2
            echo "$last_verify_error" >&2
        fi
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
    summary_text=$(extract_report_section "${resolved_output_path:-$OUTPUT_PATH}" "Summary")
    final_result_text=$(extract_report_section "${resolved_output_path:-$OUTPUT_PATH}" "Final Result")
    if [[ -n "$summary_text" ]]; then
        echo "Summary:"
        printf '%s\n' "$summary_text"
    fi
    if [[ -n "$final_result_text" ]]; then
        echo "Final Result:"
        printf '%s\n' "$final_result_text"
    fi
fi

if [[ "$delegate_status" == "completed" ]]; then
    if [[ "$QUIET" != "true" ]]; then
        echo "Artifact Verification: passed"
    fi
    exit 0
fi

if [[ -n "$failure_summary" ]]; then
    echo "Delegate failed: $failure_summary" >&2
else
    echo "Delegate failed. See artifacts for details." >&2
fi
exit 1
