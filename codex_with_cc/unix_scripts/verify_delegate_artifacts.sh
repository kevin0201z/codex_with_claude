#!/usr/bin/env bash
set -euo pipefail

EXPECTED_ARTIFACT_SCHEMA=2
EXPECTED_INVOCATION_CONTRACT='spawn_agent_child_only'

RUN_ID=""
ARTIFACT_ROOT=""

usage() {
    cat <<EOF
Usage: $0 -r RUN_ID -a ARTIFACT_ROOT

Options:
  -r, --run-id RUN_ID       Run ID to verify
  -a, --artifact-root PATH  Artifact root directory
  -h, --help                Show this help message
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
    echo "ArtifactRoot is required." >&2
    exit 1
fi

STATUS_PATH="$ARTIFACT_ROOT/status_${RUN_ID}.json"
CONFIG_PATH="$ARTIFACT_ROOT/config_${RUN_ID}.json"
OUTPUT_PATH="$ARTIFACT_ROOT/claude_${RUN_ID}.md"
RAW_STREAM_PATH="$ARTIFACT_ROOT/stream_${RUN_ID}.jsonl"
TRACE_PATH="$ARTIFACT_ROOT/trace_${RUN_ID}.log"

if [[ ! -f "$STATUS_PATH" ]]; then
    echo "Missing status file: $STATUS_PATH" >&2
    exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "Missing config file: $CONFIG_PATH" >&2
    exit 1
fi

STATUS=$(cat "$STATUS_PATH")
CONFIG=$(cat "$CONFIG_PATH")

ARTIFACT_SCHEMA_STATUS=$(echo "$STATUS" | jq -r '.artifactSchema // 0')
ARTIFACT_SCHEMA_CONFIG=$(echo "$CONFIG" | jq -r '.artifactSchema // 0')

if [[ "$ARTIFACT_SCHEMA_STATUS" != "$EXPECTED_ARTIFACT_SCHEMA" ]] || \
   [[ "$ARTIFACT_SCHEMA_CONFIG" != "$EXPECTED_ARTIFACT_SCHEMA" ]]; then
    echo "Unexpected delegate artifact schema. Expected $EXPECTED_ARTIFACT_SCHEMA." >&2
    exit 1
fi

INVOCATION_CONTRACT_STATUS=$(echo "$STATUS" | jq -r '.invocationContract // ""')
INVOCATION_CONTRACT_CONFIG=$(echo "$CONFIG" | jq -r '.invocationContract // ""')

if [[ "$INVOCATION_CONTRACT_STATUS" != "$EXPECTED_INVOCATION_CONTRACT" ]] || \
   [[ "$INVOCATION_CONTRACT_CONFIG" != "$EXPECTED_INVOCATION_CONTRACT" ]]; then
    echo "Unexpected invocation contract. Expected '$EXPECTED_INVOCATION_CONTRACT'." >&2
    exit 1
fi

CHILD_THREAD_MARKER_NAME_STATUS=$(echo "$STATUS" | jq -r '.childThreadMarkerName // ""')
CHILD_THREAD_MARKER_NAME_CONFIG=$(echo "$CONFIG" | jq -r '.childThreadMarkerName // ""')
CHILD_THREAD_MARKER_VALIDATED_STATUS=$(echo "$STATUS" | jq -r '.childThreadMarkerValidated // false')
CHILD_THREAD_MARKER_VALIDATED_CONFIG=$(echo "$CONFIG" | jq -r '.childThreadMarkerValidated // false')

if [[ "$CHILD_THREAD_MARKER_NAME_STATUS" != "CODEX_CLAUDE_CHILD_THREAD" ]] || \
   [[ "$CHILD_THREAD_MARKER_NAME_CONFIG" != "CODEX_CLAUDE_CHILD_THREAD" ]]; then
    echo "Missing or incorrect childThreadMarkerName." >&2
    exit 1
fi

if [[ "$CHILD_THREAD_MARKER_VALIDATED_STATUS" != "true" ]] || \
   [[ "$CHILD_THREAD_MARKER_VALIDATED_CONFIG" != "true" ]]; then
    echo "childThreadMarkerValidated must be true." >&2
    exit 1
fi

DELEGATE_STATUS=$(echo "$STATUS" | jq -r '.status // ""')

if [[ "$DELEGATE_STATUS" != "completed" ]] && [[ "$DELEGATE_STATUS" != "failed" ]]; then
    echo "Delegate status must be 'completed' or 'failed'. Current: $DELEGATE_STATUS" >&2
    exit 1
fi

IS_COMPLETED="false"
IS_STRUCTURED_FAILURE="false"
if [[ "$DELEGATE_STATUS" == "completed" ]]; then
    IS_COMPLETED="true"
elif [[ "$DELEGATE_STATUS" == "failed" ]]; then
    IS_STRUCTURED_FAILURE="true"
fi

if [[ ! -f "$OUTPUT_PATH" ]]; then
    echo "Missing output file: $OUTPUT_PATH" >&2
    exit 1
fi

OUTPUT_CONTENT=$(cat "$OUTPUT_PATH")
if [[ "$OUTPUT_CONTENT" != *"Final Result"* ]]; then
    echo "Output file must contain 'Final Result' heading." >&2
    exit 1
fi

if [[ ! -f "$RAW_STREAM_PATH" ]]; then
    echo "Missing raw stream file: $RAW_STREAM_PATH" >&2
    exit 1
fi

if [[ ! -f "$TRACE_PATH" ]]; then
    echo "Missing trace file: $TRACE_PATH" >&2
    exit 1
fi

ATTEMPT_COUNT=$(echo "$STATUS" | jq -r '.attemptCount // 0')
RETRY_COUNT=$(echo "$STATUS" | jq -r '.retryCount // 0')
MAX_RETRY_COUNT=$(echo "$STATUS" | jq -r '.maxRetryCount // 0')

ATTEMPTS=$(echo "$STATUS" | jq -r '.attempts // []')
ATTEMPTS_LENGTH=$(echo "$ATTEMPTS" | jq 'length')

if [[ $ATTEMPT_COUNT -lt 1 ]]; then
    echo "Delegate attemptCount must be >= 1. Current: $ATTEMPT_COUNT" >&2
    exit 1
fi

if [[ $RETRY_COUNT -gt $MAX_RETRY_COUNT ]]; then
    echo "Delegate retryCount ($RETRY_COUNT) cannot exceed maxRetryCount ($MAX_RETRY_COUNT)." >&2
    exit 1
fi

RECORDED_RETRY_REASONS=$(echo "$ATTEMPTS" | jq '[.[] | select(.retryReason != null and .retryReason != "")] | length')

if [[ $RECORDED_RETRY_REASONS -ne $RETRY_COUNT ]]; then
    echo "Delegate retry count mismatch. attempts-with-retryReason=$RECORDED_RETRY_REASONS status.retryCount=$RETRY_COUNT" >&2
    exit 1
fi

if [[ $ATTEMPTS_LENGTH -gt 0 ]]; then
    PREV_ATTEMPT=0
    for ((i=0; i<ATTEMPTS_LENGTH; i++)); do
        ATTEMPT=$(echo "$ATTEMPTS" | jq -r ".[$i].attempt // 0")
        if [[ $ATTEMPT -le $PREV_ATTEMPT ]]; then
            echo "Delegate attempts must be in strictly increasing order. Found attempt $ATTEMPT after $PREV_ATTEMPT." >&2
            exit 1
        fi
        PREV_ATTEMPT=$ATTEMPT
    done
fi

SESSION_STATE_PATH=$(echo "$CONFIG" | jq -r '.sessionStatePath // ""')
SESSION_STATE_LOCK_PATH=$(echo "$CONFIG" | jq -r '.sessionStateLockPath // ""')
SESSION_KEY=$(echo "$CONFIG" | jq -r '.sessionKey // ""')
SESSION_MODE=$(echo "$CONFIG" | jq -r '.sessionMode // ""')

if [[ -n "$SESSION_STATE_PATH" ]] && [[ -f "$SESSION_STATE_PATH" ]]; then
    SESSION_STATE=$(cat "$SESSION_STATE_PATH")
    
    PRIMARY_STATUS=$(echo "$SESSION_STATE" | jq -r '.primary.status // ""')
    if [[ "$PRIMARY_STATUS" == "leased" ]]; then
        PRIMARY_LEASE_RUN_ID=$(echo "$SESSION_STATE" | jq -r '.primary.leaseRunId // ""')
        if [[ "$PRIMARY_LEASE_RUN_ID" == "$RUN_ID" ]]; then
            echo "Primary session lease was not released for run $RUN_ID." >&2
            exit 1
        fi
    fi
    
    POOL_COUNT=$(echo "$SESSION_STATE" | jq '.parallelPool | length')
    for ((i=0; i<POOL_COUNT; i++)); do
        SLOT_STATUS=$(echo "$SESSION_STATE" | jq -r ".parallelPool[$i].status // \"\"")
        if [[ "$SLOT_STATUS" == "leased" ]]; then
            SLOT_LEASE_RUN_ID=$(echo "$SESSION_STATE" | jq -r ".parallelPool[$i].leaseRunId // \"\"")
            if [[ "$SLOT_LEASE_RUN_ID" == "$RUN_ID" ]]; then
                echo "Parallel pool slot $i lease was not released for run $RUN_ID." >&2
                exit 1
            fi
        fi
    done
fi

echo "Delegate artifacts verified successfully for run $RUN_ID."
echo "Status: $DELEGATE_STATUS"
echo "Attempts: $ATTEMPT_COUNT"
echo "Retries: $RETRY_COUNT"
echo "Output: $OUTPUT_PATH"
