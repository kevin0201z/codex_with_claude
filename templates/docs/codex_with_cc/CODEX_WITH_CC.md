# Codex With Claude Code

This document is the portable entry point for the Codex -> Codex child agent -> Claude Code CLI workflow.

## Required Reading
1. Read this file before using the workflow in this repository.
2. Read `docs/codex_with_cc/PROJECT_MEMORY.md` for the compact workflow map.
3. Read `docs/codex_with_cc/HOST_PROJECT_RULES.md` for host-project rules before making changes.
4. Read `docs/codex_with_cc/CLAUDE_CODE_DELEGATION.md` before delegating work to Claude Code.

## Core Contract
1. The Codex main thread must not run `claude` directly.
2. The Codex main thread must not run `docs/codex_with_cc/scripts/delegate_to_claude.ps1` directly.
3. Every Claude Code delegation must be carried by a Codex `spawn_agent` child thread.
4. The child thread must set `CODEX_CLAUDE_CHILD_THREAD=1` before invoking `delegate_to_claude.ps1`.
5. The child thread should use `model: gpt-5.3-codex`, `reasoning_effort: high`, and `fork_context: false`.
6. Medium and large tasks should be written to a task file and passed with `-TaskFile`.

## Standard Worker Command
Run this only inside a Codex child thread:

```powershell
$env:CODEX_CLAUDE_CHILD_THREAD = '1'
pwsh -NoProfile -File .\docs\codex_with_cc\scripts\delegate_to_claude.ps1 `
  -TaskFile .\docs\codex_with_cc\tasks\<task-file>.md `
  -SessionMode PrimaryReuse `
  -SessionKey <stable-session-key> `
  -BypassPermissions
```

Use `PrimaryAnchor -AllowParallel` for the main branch of a parallel batch and `ParallelPool -AllowParallel` for independent side work.

## Verification
Run the local regression tests after installing or changing this workflow:

```powershell
pwsh -NoProfile -File .\docs\codex_with_cc\scripts\test_delegate_runtime.ps1
pwsh -NoProfile -File .\docs\codex_with_cc\scripts\test_delegate_session_pool.ps1
```

Generate a real chain validation scaffold with:

```powershell
pwsh -NoProfile -File .\docs\codex_with_cc\scripts\run_real_delegate_chain_validation.ps1
```
