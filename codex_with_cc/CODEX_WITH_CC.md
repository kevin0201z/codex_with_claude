# Codex With Claude Code

This document is the portable entry point for the Codex -> Codex child agent -> Claude Code CLI workflow.

## Path Context

This file is written as a portable workflow contract, so command examples below use the **installed target-project paths** under `docs/codex_with_cc/...`.

When you are editing this source repository itself, the corresponding source paths are:

- `codex_with_cc/CODEX_WITH_CC.md`
- `codex_with_cc/windows_scripts/...`
- `codex_with_cc/unix_scripts/...`

When this workflow is installed into another repository, the corresponding target-project paths are:

- `docs/codex_with_cc/CODEX_WITH_CC.md`
- `docs/codex_with_cc/windows_scripts/...`
- `docs/codex_with_cc/unix_scripts/...`

Use source-repo paths when changing this repository. Use target-project paths when writing delegate commands, verification commands, or `AGENTS.md` guidance for an installed project.

## Required Reading
1. Read this file before using the workflow in this repository.

## Core Contract
1. The Codex main thread must not run `claude` directly.
2. The Codex main thread must not run `docs/codex_with_cc/windows_scripts/delegate_to_claude.ps1` or `docs/codex_with_cc/unix_scripts/delegate_to_claude.sh` directly, except for the trusted local terminal fallback below.
3. Every Claude Code delegation must be carried by a Codex `spawn_agent` child thread.
4. The child thread must set `CODEX_CLAUDE_CHILD_THREAD=1` before invoking the delegate script.
5. The child thread should use `model: gpt-5.3-codex`, `reasoning_effort: medium`, and `fork_context: false`.
6. The delegate script must not pass `--effort`; Claude Code should use its configured default effort.
7. Medium and large tasks should be written to a dated, uniquely named task file under `.codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-name>.md` and passed with `-TaskFile` (Windows) or `-f` (Linux/macOS).
8. Linux/macOS delegate runs should prefer `--permission-profile readonly` for audits and smoke tests, `--permission-profile accept-edits` for normal implementation, and `--permission-profile bypass` only when the user explicitly approves high-trust execution.
9. Claude workers must keep changes inside the delegated scope, run the required verification, and finish with the exact report headings defined in this document.
10. If the Codex sandbox or delegated runner cannot execute the same worker command, run that exact command in a trusted local terminal instead.
11. Claude workers must read and follow all applicable Codex project skills under `.codex` before implementing or changing behavior.
12. If the delegate script exits with a non-zero code, pre-launch validation fails, or the Claude Code CLI invocation cannot proceed, the Codex main thread must report the failure reason and the resolved delegate artifacts (status, config, trace). The Codex main thread must NOT fall back to the default Codex subagent flow, a direct `claude` invocation, or any workaround that bypasses the delegate script.
13. If the delegated run is blocked because continuing would send repository content or task context to an external Claude service and the platform requires explicit user authorization, the Codex main thread must stop and ask the user for that authorization. The main thread must not grant that authorization on the user's behalf, must not silently take over the task locally, and must not switch to a different execution path unless the user explicitly instructs it to do so.

## Trusted Local Terminal Fallback
This fallback is an execution-location fallback only. Preserve the same `CODEX_CLAUDE_CHILD_THREAD=1` marker, task file, session mode, session key, artifact root, and permission flags that the child thread would have used.

Do not replace this with the default Codex subagent flow, a direct `claude` command, or a modified worker command. Report that the trusted terminal fallback was used and include the command outcome in verification.

When the delegated runner detects that the local Claude state directory is not writable, the Unix workflow may emit a repo- or `/tmp`-scoped rerun script such as `rerun_<RunId>.sh` under the delegate artifact root. That script is the preferred trusted-local-terminal handoff because it preserves the same task file, session mode, session key, artifact root, and permission flags.

### Linux/macOS Tmp Runtime

On Linux/macOS, the `--tmp-runtime` flag (or `CODEX_WITH_CC_TMP_RUNTIME=1`) explicitly uses `/tmp/codex_with_cc/<repo-name>/claude-delegate` as the artifact root from the first invocation, avoiding the need to hit a permission error before falling back to `/tmp`.

This flag only affects the artifact root; task files remain under `.codex/codex_with_cc/tasks/` in the target project. The `--tmp-runtime` flag has no effect when an explicit `--artifact-root` is provided.

## Delegation Failure Contract
When the delegate script fails, the Codex main thread must observe the following failure contract:

1. Read the delegate status file (`status_<RunId>.json`) to determine the failure disposition.
2. Read the delegate config file (`config_<RunId>.json`) for the failure summary and context.
3. Read the trace file (`trace_<RunId>.log`) for diagnostic details.
4. Report the failure reason, the resolved artifacts, and any actionable next steps to the user.
5. Do NOT retry the task using the default Codex subagent, a direct `claude` command, or any workflow that skips the delegate script.
6. Do NOT silently absorb the failure and proceed as if the task was handled by another mechanism.
7. If recovery requires explicit user authorization for external Claude execution, the main thread must request that authorization from the user and wait. Until the user explicitly approves, the task remains blocked; the main thread must not personally continue the implementation as a substitute for the delegated run.

The only valid recovery path is to fix the root cause (missing `claude` CLI, missing dependencies, invalid task file, etc.) and re-invoke the delegate script with the same contract.

## Roles
- Codex main thread: understand the request, define scope, create child threads, review results, and decide final acceptance.
- Codex child thread: provide a visible conversation-tree node and invoke the worker script.
- Claude Code CLI: execute the delegated task, run verification, and produce a structured report.

## Supervisor Child Thread Contract

By default, a Codex child thread used for delegation should behave as a **supervisor**, not merely a launcher.

Supervisor responsibilities:

1. Start the delegate run using the approved workflow.
2. Keep waiting until the delegate `status_<RunId>.json` reaches a terminal status (`completed` or `failed`).
3. Read the final delegate artifacts before returning to the main thread:
   - `status_<RunId>.json`
   - `config_<RunId>.json`
   - `trace_<RunId>.log`
   - `claude_<RunId>.md`
4. Return a final-result summary to the main thread, not only a `RunId` or startup status.

A child thread must **not** end immediately after reporting:

- preflight succeeded
- delegate started
- run id acquired
- artifact root resolved

Those are intermediate states, not task completion.

The only times a supervisor child thread may return an intermediate status instead of a final summary are:

1. the run timed out,
2. the run failed and the failure artifacts were collected,
3. the run was explicitly interrupted by the user,
4. the parent explicitly requested launcher-only behavior.

If a parent prompt truly wants launcher-only behavior, that must be stated explicitly. Otherwise, the default expectation is supervisor behavior.

## Session Modes
- `PrimaryReuse`: default serial mode. Reuses the main Claude session for continuity.
- `PrimaryAnchor`: semantic marker for the anchor task in a parallel batch. Behaviorally identical to `PrimaryReuse` (reuses the main session), but signals that this run's result becomes the reusable context for subsequent serial work in the same session.
- `ParallelPool`: independent parallel side work. Uses reusable pool sessions without writing to the main session.

Only use `-AllowParallel` when task scopes are independent.

## Permission Profiles

Linux/macOS delegate runs support these permission profiles:

- `readonly`: safest default for smoke tests, audits, reviews, and investigations. Uses Claude's normal permission flow without edit auto-accept.
- `accept-edits`: standard implementation mode. Lets Claude accept edits normally without bypassing permission checks.
- `bypass`: high-trust mode. Equivalent to the legacy bypass path and should only be used when the user explicitly approves it.

Use `--preflight` to validate child-thread marker, required tools, task file, artifact root, Claude state writability, and permission profile without invoking Claude Code.

## Recommended Delegation Gradient

If the task boundary is not yet extremely clear, prefer this gradient instead of jumping straight to `accept-edits`:

1. run `--preflight`
2. run a `readonly` audit or investigation
3. let the audit produce a minimum implementation checklist
4. narrow the task file to explicit read/write boundaries
5. rerun with `accept-edits`
6. use `PrimaryReuse` by default, and only move to `PrimaryAnchor` / `ParallelPool` when task scopes are clearly independent

Task files should ideally spell out:

- allowed read scope
- allowed write scope
- forbidden paths
- minimum verification command

This makes policy behavior more predictable and reduces the chance of the first implementation delegate being blocked by an overly broad task description.

## Worker Output
Claude Code must finish with these exact headings:

```text
Process Log
Summary
Changed Files
Verification
Final Result
Risks Or Follow-ups
```

Verification must list the commands actually run and their outcomes. If verification is blocked, the report must explain the blocker and whether it is unrelated to the delegated change.

## Artifacts

Delegation artifacts are written to an artifact root determined by priority:

1. Explicit `--artifact-root`
2. `--tmp-runtime` or `CODEX_WITH_CC_TMP_RUNTIME=1` → `/tmp/codex_with_cc/<repo>/claude-delegate`
3. Repo-local default `.codex/codex_with_cc/claude-delegate` (when writable)
4. Automatic `/tmp` fallback when repo-local is not writable

The artifact root source is recorded in `config_<RunId>.json` and `status_<RunId>.json` as `artifactRootSource` (values: `explicit`, `tmp-runtime`, `repo-default`, `auto-tmp-fallback`).

Standard artifact files:
- `claude_<RunId>.md`
- `status_<RunId>.json`
- `config_<RunId>.json`
- `prompt_<RunId>.md`
- `stream_<RunId>.jsonl`
- `trace_<RunId>.log`
- `session-pools/<SessionKey>.json`

If the repository-local artifact root is not writable, the Unix workflow may fall back to `/tmp/codex_with_cc/<repo>/claude-delegate`.

Use `verify_delegate_artifacts.ps1` (Windows) or `verify_delegate_artifacts.sh` (Linux/macOS) for each run and `verify_delegate_chain.ps1` (Windows) or `verify_delegate_chain.sh` (Linux/macOS) for multi-run continuity checks.

## Platform-Specific Scripts

- Windows: `docs/codex_with_cc/windows_scripts/delegate_to_claude.ps1`
- Linux/macOS: `docs/codex_with_cc/unix_scripts/delegate_to_claude.sh`
- Linux/macOS: `docs/codex_with_cc/unix_scripts/run_delegate_supervised.sh`
- Linux/macOS: `docs/codex_with_cc/unix_scripts/wait_for_delegate_run.sh`

## Standard Worker Command (Windows)

Normally run this inside a Codex child thread. If the Codex sandbox or delegated runner cannot execute it, use the trusted local terminal fallback above:

```powershell
$env:CODEX_CLAUDE_CHILD_THREAD = '1'
pwsh -NoProfile -File .\docs\codex_with_cc\windows_scripts\delegate_to_claude.ps1 `
  -TaskFile .\.codex\codex_with_cc\tasks\<yyyyMMdd>\<HHmmssfff>-<short-id>-<task-file>.md `
  -SessionMode PrimaryReuse `
  -SessionKey <stable-session-key> `
  -BypassPermissions
```

## Standard Worker Command (Linux/macOS)

Safe smoke test form with explicit tmp runtime:

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh \
  -f .codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-file>.md \
  --session-mode PrimaryReuse \
  --session-key <stable-session-key> \
  --permission-profile readonly \
  --tmp-runtime
```

Normal implementation form without bypass:

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh \
  -f .codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-file>.md \
  --session-mode PrimaryReuse \
  --session-key <stable-session-key> \
  --permission-profile accept-edits \
  --tmp-runtime
```

High-trust implementation form with explicit approval:

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh \
  -f .codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-file>.md \
  --session-mode PrimaryReuse \
  --session-key <stable-session-key> \
  --permission-profile bypass \
  --tmp-runtime \
  --bypass-permissions
```

Preflight-only validation:

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh \
  -f .codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-file>.md \
  --permission-profile readonly \
  --tmp-runtime \
  --preflight
```

Use `PrimaryAnchor --allow-parallel` for the main branch of a parallel batch and `ParallelPool --allow-parallel` for independent side work.

## Supervised Delegate Commands

Use these when you want the child thread to keep waiting for the final result and print a final summary after the delegate run finishes.

### Linux/macOS

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash codex_with_cc/unix_scripts/run_delegate_supervised.sh \
  -f .codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-file>.md \
  --session-mode PrimaryReuse \
  --session-key <stable-session-key> \
  --permission-profile readonly \
  --tmp-runtime
```

Wait on an existing run:

```bash
bash codex_with_cc/unix_scripts/wait_for_delegate_run.sh \
  -r <run-id> \
  -a /tmp/codex_with_cc/<repo>/claude-delegate
```


## Verification

Run the local regression tests after installing or changing this workflow:

### Windows

```powershell
pwsh -NoProfile -File .\docs\codex_with_cc\windows_scripts\test_delegate_runtime.ps1
pwsh -NoProfile -File .\docs\codex_with_cc\windows_scripts\test_delegate_session_pool.ps1
```

### Linux/macOS

```bash
bash docs/codex_with_cc/unix_scripts/test_delegate_runtime.sh
bash docs/codex_with_cc/unix_scripts/test_delegate_session_pool.sh
```

With tmp runtime artifact root:

```bash
bash docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh -r <run-id> -a /tmp/codex_with_cc/<repo>/claude-delegate
bash docs/codex_with_cc/unix_scripts/verify_delegate_chain.sh --anchor-run-id <id> --parallel-run-ids "<ids>" --reuse-run-ids "<ids>" -a /tmp/codex_with_cc/<repo>/claude-delegate --session-key <key>
```

Generate a real chain validation scaffold with:

### Windows

```powershell
pwsh -NoProfile -File .\docs\codex_with_cc\windows_scripts\run_real_delegate_chain_validation.ps1
```

### Linux/macOS

```bash
bash docs/codex_with_cc/unix_scripts/run_real_delegate_chain_validation.sh
```
