# Delegate Max Retry Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hard retry ceiling to the Claude delegate worker so repeated retryable failures stop with a structured `NEED_HUMAN_INTERVENTION` result instead of burning compute indefinitely.

**Architecture:** Extend the delegate worker's retry loop with a configurable retry ceiling, enrich delegate artifacts with explicit human-intervention failure metadata, and emit a structured fallback report when the ceiling is hit. Keep the change scoped to the delegate runtime and artifact verification helpers so existing session-pool semantics remain intact.

**Tech Stack:** PowerShell, JSON artifact files, existing delegate runtime tests

---

### Task 1: Add red tests for retry ceiling metadata

**Files:**
- Modify: `D:\Develop\GitHub\codex_with_cc\templates\docs\codex_with_cc\scripts\test_delegate_runtime.ps1`

- [ ] **Step 1: Write the failing tests**

Add assertions that:
- a new helper can summarize non-JSON retryable errors into a short failure summary
- artifact verification accepts `failed` status with `failureDisposition = NEED_HUMAN_INTERVENTION`
- failed artifacts require a `Final Result` section and failure summary metadata

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File .\templates\docs\codex_with_cc\scripts\test_delegate_runtime.ps1`
Expected: FAIL because the new helper and failure artifact semantics do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Implement the missing helper and artifact semantics in the runtime/helper scripts only.

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -File .\templates\docs\codex_with_cc\scripts\test_delegate_runtime.ps1`
Expected: PASS

### Task 2: Add hard retry ceiling to delegate runtime

**Files:**
- Modify: `D:\Develop\GitHub\codex_with_cc\templates\docs\codex_with_cc\scripts\delegate_to_claude.ps1`
- Modify: `D:\Develop\GitHub\codex_with_cc\templates\docs\codex_with_cc\scripts\claude_delegate_backend_helpers.ps1`

- [ ] **Step 1: Add parameter and retry accounting**

Add `-MaxRetryCount` with default `5`, derive total attempts from it, and record the configured ceiling into config/status artifacts.

- [ ] **Step 2: Add structured exhaustion handling**

When the runtime sees another retryable condition after exhausting retries:
- stop retrying immediately
- set `status = failed`
- set `failureDisposition = NEED_HUMAN_INTERVENTION`
- persist `failureSummary`, `finalRetryReason`, and `maxRetryCount`
- write a structured fallback report with `Final Result` explaining the forced stop

- [ ] **Step 3: Keep successful behavior unchanged**

Ensure successful runs still mark `completed`, keep existing attempt audit data, and preserve current fresh-session reset behavior within the retry ceiling.

- [ ] **Step 4: Run focused runtime tests**

Run: `pwsh -NoProfile -File .\templates\docs\codex_with_cc\scripts\test_delegate_runtime.ps1`
Expected: PASS

### Task 3: Expand artifact verification for structured failure

**Files:**
- Modify: `D:\Develop\GitHub\codex_with_cc\templates\docs\codex_with_cc\scripts\verify_delegate_artifacts.ps1`
- Modify: `D:\Develop\GitHub\codex_with_cc\templates\docs\codex_with_cc\scripts\test_delegate_runtime.ps1`

- [ ] **Step 1: Update verifier semantics**

Allow `failed` artifacts only when they include:
- `failureDisposition = NEED_HUMAN_INTERVENTION`
- a non-empty `failureSummary`
- a `Final Result` heading in the output report

- [ ] **Step 2: Add failing-artifact verification test**

Create a synthetic failed artifact in `test_delegate_runtime.ps1` and verify `verify_delegate_artifacts.ps1` accepts it.

- [ ] **Step 3: Run focused tests**

Run: `pwsh -NoProfile -File .\templates\docs\codex_with_cc\scripts\test_delegate_runtime.ps1`
Expected: PASS

### Task 4: Run end-to-end regression checks

**Files:**
- Modify: `D:\Develop\GitHub\codex_with_cc\tests\test_install_codex_with_cc.ps1` only if new installer-surface metadata becomes required (otherwise no change)

- [ ] **Step 1: Run repository install test**

Run: `pwsh -NoProfile -File .\tests\test_install_codex_with_cc.ps1`
Expected: PASS

- [ ] **Step 2: Run template session-pool regression**

Run: `pwsh -NoProfile -File .\templates\docs\codex_with_cc\scripts\test_delegate_session_pool.ps1`
Expected: PASS

- [ ] **Step 3: Review diff**

Run: `git diff -- templates/docs/codex_with_cc/scripts tests docs/superpowers/plans`
Expected: only retry-guard and verification changes plus this plan file
