#!/usr/bin/env bash
set -euo pipefail

assert_true() {
    local condition="$1"
    local name="$2"
    if [[ "$condition" != "true" ]]; then
        echo "[$name] assertion failed" >&2
        return 1
    fi
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local name="$3"
    if [[ "$actual" != "$expected" ]]; then
        echo "[$name] expected '$expected' but got '$actual'" >&2
        return 1
    fi
}

assert_contains() {
    local text="$1"
    local needle="$2"
    local name="$3"
    if [[ "$text" != *"$needle"* ]]; then
        echo "[$name] expected to contain '$needle'" >&2
        return 1
    fi
}

assert_not_contains() {
    local text="$1"
    local needle="$2"
    local name="$3"
    if [[ "$text" == *"$needle"* ]]; then
        echo "[$name] expected NOT to contain '$needle'" >&2
        return 1
    fi
}

invoke_delegate_worker_script() {
    local -a args=("$@")
    local set_child_thread_marker="${args[0]}"
    local -a script_args=("${args[@]:1}")
    local script_path="${SCRIPT_PATH:-$(dirname "${BASH_SOURCE[0]}")/delegate_to_claude.sh}"
    
    local marker_name='CODEX_CLAUDE_CHILD_THREAD'
    local original_marker="${!marker_name:-}"
    
    local output
    local exit_code
    
    if [[ "$set_child_thread_marker" == "--set-child-thread-marker" ]]; then
        export CODEX_CLAUDE_CHILD_THREAD=1
    else
        unset CODEX_CLAUDE_CHILD_THREAD
        script_args=("$set_child_thread_marker" "${script_args[@]}")
    fi
    
    set +e
    output=$(bash "$script_path" "${script_args[@]}" 2>&1)
    exit_code=$?
    set -e
    
    if [[ -n "${original_marker:-}" ]]; then
        export CODEX_CLAUDE_CHILD_THREAD="$original_marker"
    else
        unset CODEX_CLAUDE_CHILD_THREAD
    fi
    
    echo "$exit_code"$'\n'"$output"
}
