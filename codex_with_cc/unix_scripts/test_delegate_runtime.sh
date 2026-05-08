#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/claude_delegate_backend_helpers.sh"
source "$SCRIPT_DIR/claude_session_pool.sh"

WORKFLOW_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW_CONTAINER="$(dirname "$WORKFLOW_ROOT")"
if [[ "$(basename "$WORKFLOW_CONTAINER")" == "docs" ]]; then
    REPO_ROOT="$(cd "$WORKFLOW_CONTAINER/.." && pwd)"
else
    REPO_ROOT="$WORKFLOW_CONTAINER"
fi

TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local name="$1"
    local test_func="$2"
    local result
    
    echo "Running test: $name"
    result="$($test_func)"
    printf '%s\n' "$result"
    if [[ "$result" == "true" ]]; then
        echo "  PASSED: $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAILED: $name" >&2
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_child_thread_marker_missing() {
    local result
    result=$(unset CODEX_CLAUDE_CHILD_THREAD && bash "$SCRIPT_DIR/delegate_to_claude.sh" -t "test task" 2>&1 || true)
    
    if echo "$result" | grep -q "may only run inside a Codex spawn_agent child thread"; then
        echo "true"
    else
        echo "false"
    fi
}

test_lock_timeout_rejection() {
    local tmp_root
    tmp_root=$(mktemp -d)
    local lock_path="$tmp_root/delegate.lock"
    local tmp_home
    tmp_home=$(mktemp -d)
    
    mkdir -p "$(dirname "$lock_path")"
    echo '{"runId":"other-run","pid":999999,"startedAt":"2025-01-01T00:00:00Z"}' > "$lock_path"
    
    exec 3>"$lock_path"
    flock -x 3
    
    local result
    result=$(HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" CODEX_CLAUDE_CHILD_THREAD=1 timeout 5 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "test task" \
        --artifact-root "$tmp_root" \
        --lock-timeout 2 \
        2>&1 || true)
    
    flock -u 3
    exec 3>&-
    
    rm -rf "$tmp_root"
    rm -rf "$tmp_home"
    
    if echo "$result" | grep -q "Another delegate_to_claude run is still active"; then
        echo "true"
    else
        echo "false"
    fi
}

test_unwritable_claude_state_emits_rerun_script() {
    local tmp_root
    tmp_root=$(mktemp -d)
    local home_parent
    home_parent=$(mktemp -d)
    local readonly_home="$home_parent/readonly-home"
    mkdir -p "$readonly_home"
    chmod 555 "$readonly_home"

    local result
    result=$(HOME="$readonly_home" CODEX_CLAUDE_CHILD_THREAD=1 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "test task" \
        --artifact-root "$tmp_root" \
        2>&1 || true)

    local rerun_script
    rerun_script=$(find "$tmp_root" -maxdepth 1 -name 'rerun_*.sh' | head -n 1)

    chmod 755 "$readonly_home"
    rm -rf "$home_parent" "$tmp_root"

    if echo "$result" | grep -q "Trusted local terminal fallback script" && [[ -n "$rerun_script" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_unstructured_output_normalization() {
    local text="This is a simple response without the required headings."
    
    local normalized
    normalized=$(convert_claude_delegate_unstructured_final_text "$text")
    
    if echo "$normalized" | grep -q "Final Result" && \
       echo "$normalized" | grep -q "UNSTRUCTURED_SUCCESS_NORMALIZED"; then
        echo "true"
    else
        echo "false"
    fi
}

test_stale_session_retry_detection() {
    local raw_lines='Error: No conversation found for session ID abc123
{"type":"result","subtype":"error"}'
    
    local decision
    decision=$(get_claude_delegate_retry_decision "$raw_lines" "true" 1 "true" "false" "false")
    
    local should_retry
    should_retry=$(echo "$decision" | jq -r '.shouldRetry')
    local retry_with_fresh
    retry_with_fresh=$(echo "$decision" | jq -r '.retryWithFreshSession')
    
    if [[ "$should_retry" == "true" ]] && [[ "$retry_with_fresh" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_stream_json_startup_error_retry() {
    local raw_lines='Error: stream-json output format requires --verbose flag
{"type":"result","subtype":"error"}'
    
    local decision
    decision=$(get_claude_delegate_retry_decision "$raw_lines" "false" 1 "false" "false" "false")
    
    local should_retry
    should_retry=$(echo "$decision" | jq -r '.shouldRetry')
    local retry_reason
    retry_reason=$(echo "$decision" | jq -r '.retryReason')
    
    if [[ "$should_retry" == "true" ]] && [[ "$retry_reason" == "stream_json_startup" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_tool_result_false_positive_exclusion() {
    local raw_lines='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"The error message says: No conversation found for session ID but this is just a reference in the output."}]}}
{"type":"result","subtype":"success"}'
    
    local decision
    decision=$(get_claude_delegate_retry_decision "$raw_lines" "true" 0 "true" "true" "true")
    
    local should_retry
    should_retry=$(echo "$decision" | jq -r '.shouldRetry')
    
    if [[ "$should_retry" == "false" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_stream_json_tool_result_false_positive_exclusion() {
    local raw_lines='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"This file contains the text: stream-json output format requires --verbose flag"}]}}
{"type":"result","subtype":"success"}'
    
    local decision
    decision=$(get_claude_delegate_retry_decision "$raw_lines" "false" 0 "false" "true" "false")
    
    local should_retry
    should_retry=$(echo "$decision" | jq -r '.shouldRetry')
    local saw_stream_json_verbose_error
    saw_stream_json_verbose_error=$(echo "$decision" | jq -r '.sawStreamJsonVerboseError')
    
    if [[ "$should_retry" == "false" ]] && [[ "$saw_stream_json_verbose_error" == "false" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_successful_delegate_with_tool_result_error_text_releases_lease() {
    local fake_bin
    fake_bin=$(mktemp -d)
    local artifact_root
    artifact_root=$(mktemp -d)
    local tmp_home
    tmp_home=$(mktemp -d)

    cat > "$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

prompt="${@: -1}"
output_path=$(printf '%s\n' "$prompt" | awk 'prev { print; exit } /^Delegated output report path:$/ { prev=1 }')
if [[ -z "$output_path" ]]; then
    echo "missing delegated output path" >&2
    exit 1
fi

mkdir -p "$(dirname "$output_path")"
cat > "$output_path" <<'REPORT'
Process Log
- Mock Claude wrote a structured report.

Summary
Mock delegate completed successfully.

Changed Files
None

Verification
- fake claude fixture

Final Result
PASS

Risks Or Follow-ups
None
REPORT

printf '%s\n' '{"type":"system","subtype":"init"}'
printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"fixture mentions stream-json output format requires --verbose flag inside JSON content"}]}}'
printf '%s\n' '{"type":"result","subtype":"success"}'
EOF
    chmod +x "$fake_bin/claude"

    local result
    result=$(PATH="$fake_bin:$PATH" HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" CODEX_CLAUDE_CHILD_THREAD=1 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "mock successful delegate" \
        --artifact-root "$artifact_root" \
        --session-key "mock-success" \
        --bypass-permissions \
        2>&1)

    local status_path
    status_path=$(find "$artifact_root" -maxdepth 1 -name 'status_*.json' | head -n 1)
    local run_id
    run_id=$(jq -r '.runId' "$status_path")
    local verify_output
    verify_output=$(bash "$SCRIPT_DIR/verify_delegate_artifacts.sh" -r "$run_id" -a "$artifact_root" 2>&1)

    local status
    status=$(jq -r '.status' "$status_path")
    local exit_code
    exit_code=$(jq -r '.exitCode' "$status_path")
    local attempt_count
    attempt_count=$(jq -r '.attemptCount' "$status_path")
    local attempts_length
    attempts_length=$(jq -r '.attempts | length' "$status_path")
    local retry_count
    retry_count=$(jq -r '.retryCount' "$status_path")
    local primary_status
    primary_status=$(jq -r '.primary.status' "$artifact_root/session-pools/mock-success.json")

    rm -rf "$fake_bin" "$artifact_root" "$tmp_home"

    if [[ "$status" == "completed" ]] && \
       [[ "$exit_code" == "0" ]] && \
       [[ "$attempt_count" == "1" ]] && \
       [[ "$attempts_length" == "1" ]] && \
       [[ "$retry_count" == "0" ]] && \
       [[ "$primary_status" == "available" ]] && \
       echo "$verify_output" | grep -q "Delegate artifacts verified successfully"; then
        echo "true"
    else
        printf 'delegate result:\n%s\nverify:\n%s\n' "$result" "$verify_output" >&2
        echo "false"
    fi
}

test_final_result_heading_detection() {
    local text_with_heading="Some content before

Final Result
This is the final result.

More content after."
    
    local text_without_heading="Some content without the heading"
    
    local has_heading
    has_heading=$(test_claude_delegate_text_has_final_result_heading "$text_with_heading")
    
    local no_heading
    no_heading=$(test_claude_delegate_text_has_final_result_heading "$text_without_heading")
    
    if [[ "$has_heading" == "true" ]] && [[ "$no_heading" == "false" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_output_resolution_success() {
    local final_text="Process Log
- Step 1 completed

Summary
Task completed successfully

Changed Files
- file1.sh

Verification
- All tests passed

Final Result
SUCCESS

Risks Or Follow-ups
None"
    
    local resolution
    resolution=$(get_claude_delegate_output_resolution "$final_text" "" 0 "true" "true")
    
    local delegate_succeeded
    delegate_succeeded=$(echo "$resolution" | jq -r '.delegateSucceeded')
    
    if [[ "$delegate_succeeded" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_output_resolution_normalization() {
    local final_text="This is a simple response without headings."
    
    local resolution
    resolution=$(get_claude_delegate_output_resolution "$final_text" "" 0 "true" "false")
    
    local output_was_normalized
    output_was_normalized=$(echo "$resolution" | jq -r '.outputWasNormalized')
    
    if [[ "$output_was_normalized" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_process_alive_check() {
    local current_pid=$$
    
    local is_alive
    is_alive=$(is_process_alive "$current_pid")
    
    local is_dead
    is_dead=$(is_process_alive 999999999)
    
    if [[ "$is_alive" == "true" ]] && [[ "$is_dead" == "false" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_path_writable_check() {
    local tmp_file
    tmp_file=$(mktemp)
    
    local writable
    writable=$(test_claude_delegate_path_writable "$tmp_file")
    
    rm -f "$tmp_file"
    
    if [[ "$writable" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

test_json_file_atomic_write() {
    local tmp_file
    tmp_file=$(mktemp)
    rm -f "$tmp_file"
    
    local test_data='{"test":"value","number":42}'
    write_claude_delegate_json_file "$tmp_file" "$test_data"
    
    if [[ -f "$tmp_file" ]]; then
        local field
        local number
        field=$(jq -r '.test' "$tmp_file")
        number=$(jq -r '.number' "$tmp_file")
        if [[ "$field" == "value" ]] && [[ "$number" == "42" ]]; then
            rm -f "$tmp_file"
            echo "true"
        else
            rm -f "$tmp_file"
            echo "false"
        fi
    else
        echo "false"
    fi
}

test_tmp_runtime_uses_tmp_artifact_root() {
    local tmp_home
    tmp_home=$(mktemp -d)

    local result
    result=$(HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" CODEX_CLAUDE_CHILD_THREAD=1 timeout 5 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "test task" \
        --tmp-runtime \
        --dry-run \
        2>&1 || true)

    rm -rf "$tmp_home"

    if echo "$result" | grep -q "/tmp/codex_with_cc/"; then
        echo "true"
    else
        echo "false"
    fi
}

test_tmp_runtime_env_var_uses_tmp_artifact_root() {
    local tmp_home
    tmp_home=$(mktemp -d)

    local result
    result=$(CODEX_WITH_CC_TMP_RUNTIME=1 HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" CODEX_CLAUDE_CHILD_THREAD=1 timeout 5 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "test task" \
        --dry-run \
        2>&1 || true)

    rm -rf "$tmp_home"

    if echo "$result" | grep -q "/tmp/codex_with_cc/"; then
        echo "true"
    else
        echo "false"
    fi
}

test_explicit_artifact_root_overrides_tmp_runtime() {
    local tmp_root
    tmp_root=$(mktemp -d)
    local tmp_home
    tmp_home=$(mktemp -d)

    local result
    result=$(HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" CODEX_CLAUDE_CHILD_THREAD=1 timeout 5 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "test task" \
        --tmp-runtime \
        --artifact-root "$tmp_root" \
        --dry-run \
        2>&1 || true)

    rm -rf "$tmp_root" "$tmp_home"

    if echo "$result" | grep -q "Artifact Root Source: explicit"; then
        echo "true"
    else
        echo "false"
    fi
}

test_rerun_script_preserves_tmp_runtime() {
    local home_parent
    home_parent=$(mktemp -d)
    local readonly_home="$home_parent/readonly-home"
    mkdir -p "$readonly_home"
    chmod 555 "$readonly_home"

    local result
    result=$(HOME="$readonly_home" CODEX_CLAUDE_CHILD_THREAD=1 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "test task" \
        --tmp-runtime \
        2>&1 || true)

    local rerun_base="/tmp/codex_with_cc"
    local rerun_script
    rerun_script=$(find "$rerun_base" -maxdepth 3 -name 'rerun_*.sh' -mmin -1 2>/dev/null | head -n 1)

    local rerun_content=""
    if [[ -n "$rerun_script" ]]; then
        rerun_content=$(cat "$rerun_script" 2>/dev/null || echo "")
    fi

    chmod 755 "$readonly_home"
    rm -rf "$home_parent"

    if echo "$rerun_content" | grep -q -- "--tmp-runtime"; then
        echo "true"
    else
        echo "false"
    fi
}

echo "========================================"
echo "Running delegate runtime tests"
echo "========================================"
echo ""

run_test "child_thread_marker_missing" test_child_thread_marker_missing
run_test "lock_timeout_rejection" test_lock_timeout_rejection
run_test "unwritable_claude_state_emits_rerun_script" test_unwritable_claude_state_emits_rerun_script
run_test "unstructured_output_normalization" test_unstructured_output_normalization
run_test "stale_session_retry_detection" test_stale_session_retry_detection
run_test "stream_json_startup_error_retry" test_stream_json_startup_error_retry
run_test "tool_result_false_positive_exclusion" test_tool_result_false_positive_exclusion
run_test "stream_json_tool_result_false_positive_exclusion" test_stream_json_tool_result_false_positive_exclusion
run_test "final_result_heading_detection" test_final_result_heading_detection
run_test "output_resolution_success" test_output_resolution_success
run_test "output_resolution_normalization" test_output_resolution_normalization
run_test "process_alive_check" test_process_alive_check
run_test "path_writable_check" test_path_writable_check
run_test "json_file_atomic_write" test_json_file_atomic_write
run_test "tmp_runtime_uses_tmp_artifact_root" test_tmp_runtime_uses_tmp_artifact_root
run_test "tmp_runtime_env_var_uses_tmp_artifact_root" test_tmp_runtime_env_var_uses_tmp_artifact_root
run_test "explicit_artifact_root_overrides_tmp_runtime" test_explicit_artifact_root_overrides_tmp_runtime
run_test "rerun_script_preserves_tmp_runtime" test_rerun_script_preserves_tmp_runtime
run_test "successful_delegate_with_tool_result_error_text_releases_lease" test_successful_delegate_with_tool_result_error_text_releases_lease

echo ""
echo "========================================"
echo "Test Results"
echo "========================================"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
