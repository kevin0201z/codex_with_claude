# Real Delegate Chain Validation Task

- SessionKey: delegate-real-chain-fab4b8acedc1
- ArtifactRoot: D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts
- SessionMode: ParallelPool
- Child-thread only: This task must run inside a Codex spawn_agent child thread with model 'gpt-5.3-codex', reasoning_effort 'high', fork_context 'false'.
- Required child-thread marker: set process environment CODEX_CLAUDE_CHILD_THREAD=1 before invoking the worker entry script.
- Worker entry script: docs/codex_with_cc/scripts/delegate_to_claude.ps1
- Required worker arguments: -TaskFile "D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\tasks\parallel-artifact-audit.md" -ArtifactRoot "D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts" -SessionKey "delegate-real-chain-fab4b8acedc1" -SessionMode ParallelPool -AllowParallel -BypassPermissions

Allowed scope:
docs/codex_with_cc/scripts/verify_delegate_artifacts.ps1
docs/codex_with_cc/scripts/verify_delegate_chain.ps1
.codex/claude-delegate

Verification command to run after this task completes:
pwsh -NoProfile -File .\docs\codex_with_cc\scripts\verify_delegate_artifacts.ps1 -RunId <parallel-a-run-id> -ArtifactRoot 'D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts'

只读验证任务：审查新 schema delegate artifacts 与 verify_delegate_artifacts.ps1 的契约要求。

要求：
- 只读，不修改任何仓库文件。
- 聚焦 artifactSchema / invocationContract / attempts[] / initialSessionId / initialResume 等字段是否支撑新链路验收。
- 输出必须包含 Process Log / Summary / Changed Files / Verification / Final Result / Risks Or Follow-ups。
