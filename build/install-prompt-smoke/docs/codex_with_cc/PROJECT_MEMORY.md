# PROJECT_MEMORY

This file is a compact memory document for the installed `codex_with_cc` workflow.

## Workflow Root
- Main workflow document: `docs/codex_with_cc/CODEX_WITH_CC.md`
- Delegation protocol: `docs/codex_with_cc/CLAUDE_CODE_DELEGATION.md`
- Host rules: `docs/codex_with_cc/HOST_PROJECT_RULES.md`
- Worker scripts: `docs/codex_with_cc/scripts`
- Task files: `docs/codex_with_cc/tasks`

## Minimum Reading Protocol
1. Read `docs/codex_with_cc/CODEX_WITH_CC.md`.
2. Read `docs/codex_with_cc/HOST_PROJECT_RULES.md`.
3. For delegation work, read `docs/codex_with_cc/CLAUDE_CODE_DELEGATION.md`.

## Key Safety Rules
- Main-thread direct Claude invocation is forbidden.
- Worker script direct main-thread invocation is forbidden.
- Claude worker execution must happen inside a Codex `spawn_agent` child thread.
- The child thread must set `CODEX_CLAUDE_CHILD_THREAD=1`.
- Artifacts must be kept for review and verification.
