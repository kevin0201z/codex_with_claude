# Claude Code Delegation Protocol

This protocol defines how Codex delegates implementation or review work to Claude Code CLI while keeping the Codex conversation tree auditable.

## Roles
- Codex main thread: understand the request, define scope, create child threads, review results, and decide final acceptance.
- Codex child thread: provide a visible conversation-tree node and invoke the worker script.
- Claude Code CLI: execute the delegated task, run verification, and produce a structured report.

## Non-Negotiable Rules
1. Do not run Claude CLI directly from the Codex main thread.
2. Do not run `docs/codex_with_cc/scripts/delegate_to_claude.ps1` directly from the Codex main thread.
3. Every delegation must be carried by a Codex `spawn_agent` child thread.
4. Every child thread must set `CODEX_CLAUDE_CHILD_THREAD=1` before invoking the worker script.
5. The worker script is a child-thread-only worker entry, not a general user command.
6. Do not pass long parent-thread context to the child thread; use task files for substantial work.

## Session Modes
- `PrimaryReuse`: default serial mode. Reuses the main Claude session for continuity.
- `PrimaryAnchor`: parallel-batch anchor. Its result becomes the main reusable context for later serial work.
- `ParallelPool`: independent parallel side work. Uses reusable pool sessions without writing to the main session.

Only use `-AllowParallel` when task scopes are independent.

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
Delegation artifacts are written under `.codex/claude-delegate` by default:
- `claude_<RunId>.md`
- `status_<RunId>.json`
- `config_<RunId>.json`
- `prompt_<RunId>.md`
- `stream_<RunId>.jsonl`
- `trace_<RunId>.log`
- `session-pools/<SessionKey>.json`

Use `verify_delegate_artifacts.ps1` for each run and `verify_delegate_chain.ps1` for multi-run continuity checks.
