#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW_CONTAINER="$(dirname "$WORKFLOW_ROOT")"
if [[ "$(basename "$WORKFLOW_CONTAINER")" == "docs" ]]; then
    REPO_ROOT="$(cd "$WORKFLOW_CONTAINER/.." && pwd)"
else
    REPO_ROOT="$WORKFLOW_CONTAINER"
fi

ARTIFACT_ROOT="$REPO_ROOT/.codex/codex_with_cc/claude-delegate"
TASKS_ROOT="$REPO_ROOT/.codex/codex_with_cc/tasks"

TIMESTAMP=$(date +"%Y%m%d")
TIME_DIR="$TASKS_ROOT/$TIMESTAMP"
mkdir -p "$TIME_DIR"

SESSION_KEY="chain-validation-$(date +"%H%M%S")"

generate_task_file() {
    local name="$1"
    local mode="$2"
    local task="$3"
    local scope="$4"
    local tests="$5"
    
    local guid
    guid=$(head -c 6 /dev/urandom 2>/dev/null | xxd -p 2>/dev/null || echo "$RANDOM" | head -c 6)
    local time_part
    time_part=$(date +"%H%M%S")
    local filename="${time_part}-${guid}-${name}.md"
    local filepath="$TIME_DIR/$filename"
    
    cat > "$filepath" <<EOF
# Delegate Chain Validation Task: $name

## Session Configuration
- SessionMode: $mode
- SessionKey: $SESSION_KEY

## Task
$task

## Scope
$scope

## Tests
$tests
EOF
    
    echo "$filepath"
}

TASK_1=$(generate_task_file "anchor-read-protocol" "PrimaryAnchor" \
    "Read docs/codex_with_cc/CODEX_WITH_CC.md and summarize the delegate workflow rules in a structured format. Focus on: 1) Session modes and their purposes, 2) Worker output format requirements, 3) Retry and error handling rules." \
    "docs/codex_with_cc/unix_scripts/delegate_to_claude.sh;docs/codex_with_cc/unix_scripts/claude_session_pool.sh;docs/codex_with_cc/CODEX_WITH_CC.md" \
    "bash docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh -r <anchor-run-id> -a '$ARTIFACT_ROOT'")

TASK_2=$(generate_task_file "parallel-artifact-audit" "ParallelPool" \
    "Audit the artifact schema and invocation contract in the delegate scripts. Verify that artifactSchema=2 and invocationContract='spawn_agent_child_only' are consistently used." \
    "docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh;docs/codex_with_cc/unix_scripts/verify_delegate_chain.sh;.codex/codex_with_cc/claude-delegate" \
    "bash docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh -r <parallel-1-run-id> -a '$ARTIFACT_ROOT'")

TASK_3=$(generate_task_file "parallel-stream-audit" "ParallelPool" \
    "Audit the stream capture and retry decision logic in claude_delegate_backend_helpers.sh. Verify the retry conditions for stale sessions and stream-json errors." \
    "docs/codex_with_cc/unix_scripts/claude_delegate_backend_helpers.sh;.codex/codex_with_cc/claude-delegate" \
    "bash docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh -r <parallel-2-run-id> -a '$ARTIFACT_ROOT'")

TASK_4=$(generate_task_file "reuse-cross-check-1" "PrimaryReuse" \
    "Cross-check the anchor run's summary against the actual CODEX_WITH_CC.md content. Verify that all key rules were captured correctly." \
    "docs/codex_with_cc/unix_scripts/delegate_to_claude.sh;docs/codex_with_cc/unix_scripts/claude_delegate_backend_helpers.sh;docs/codex_with_cc/unix_scripts/claude_session_pool.sh;docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh;docs/codex_with_cc/unix_scripts/verify_delegate_chain.sh;docs/codex_with_cc/unix_scripts/run_real_delegate_chain_validation.sh;docs/codex_with_cc/unix_scripts/test_delegate_runtime.sh;docs/codex_with_cc/unix_scripts/test_delegate_session_pool.sh;docs/codex_with_cc/CODEX_WITH_CC.md" \
    "bash docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh -r <reuse-1-run-id> -a '$ARTIFACT_ROOT'")

TASK_5=$(generate_task_file "reuse-cross-check-2" "PrimaryReuse" \
    "Final validation: Review all generated artifacts and confirm the delegate chain completed successfully. Check that session state shows all leases released." \
    "docs/codex_with_cc/unix_scripts/delegate_to_claude.sh;docs/codex_with_cc/unix_scripts/claude_delegate_backend_helpers.sh;docs/codex_with_cc/unix_scripts/claude_session_pool.sh;docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh;docs/codex_with_cc/unix_scripts/verify_delegate_chain.sh;docs/codex_with_cc/unix_scripts/run_real_delegate_chain_validation.sh;docs/codex_with_cc/unix_scripts/test_delegate_runtime.sh;docs/codex_with_cc/unix_scripts/test_delegate_session_pool.sh;docs/codex_with_cc/CODEX_WITH_CC.md" \
    "bash docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh -r <reuse-2-run-id> -a '$ARTIFACT_ROOT'")

cat <<EOF
Delegate Chain Validation Tasks Generated
===========================================

Session Key: $SESSION_KEY
Tasks Directory: $TIME_DIR

Task 1 (Anchor): $TASK_1
  Mode: PrimaryAnchor
  Command: CODEX_CLAUDE_CHILD_THREAD=1 bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh -f $TASK_1 --session-mode PrimaryAnchor --session-key $SESSION_KEY --bypass-permissions

Task 2 (Parallel 1): $TASK_2
  Mode: ParallelPool
  Command: CODEX_CLAUDE_CHILD_THREAD=1 bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh -f $TASK_2 --session-mode ParallelPool --session-key $SESSION_KEY --bypass-permissions --allow-parallel

Task 3 (Parallel 2): $TASK_3
  Mode: ParallelPool
  Command: CODEX_CLAUDE_CHILD_THREAD=1 bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh -f $TASK_3 --session-mode ParallelPool --session-key $SESSION_KEY --bypass-permissions --allow-parallel

Task 4 (Reuse 1): $TASK_4
  Mode: PrimaryReuse
  Command: CODEX_CLAUDE_CHILD_THREAD=1 bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh -f $TASK_4 --session-mode PrimaryReuse --session-key $SESSION_KEY --bypass-permissions

Task 5 (Reuse 2): $TASK_5
  Mode: PrimaryReuse
  Command: CODEX_CLAUDE_CHILD_THREAD=1 bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh -f $TASK_5 --session-mode PrimaryReuse --session-key $SESSION_KEY --bypass-permissions

Chain Verification Command:
  bash docs/codex_with_cc/unix_scripts/verify_delegate_chain.sh \\
    --anchor-run-id <anchor-run-id> \\
    --parallel-run-ids "<parallel-1-run-id>;<parallel-2-run-id>" \\
    --reuse-run-ids "<reuse-1-run-id>;<reuse-2-run-id>" \\
    -a "$ARTIFACT_ROOT" \\
    --session-key "$SESSION_KEY"

EOF
