# Real Delegate Chain Validation Task

- SessionKey: delegate-real-chain-fab4b8acedc1
- ArtifactRoot: D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts
- SessionMode: PrimaryReuse
- Child-thread only: This task must run inside a Codex spawn_agent child thread with model 'gpt-5.3-codex', reasoning_effort 'high', fork_context 'false'.
- Required child-thread marker: set process environment CODEX_CLAUDE_CHILD_THREAD=1 before invoking the worker entry script.
- Worker entry script: docs/codex_with_cc/scripts/delegate_to_claude.ps1
- Required worker arguments: -TaskFile "D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\tasks\reuse-cross-check-2.md" -ArtifactRoot "D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts" -SessionKey "delegate-real-chain-fab4b8acedc1" -SessionMode PrimaryReuse -BypassPermissions

Allowed scope:
docs/codex_with_cc/scripts/delegate_to_claude.ps1
docs/codex_with_cc/scripts/claude_delegate_backend_helpers.ps1
docs/codex_with_cc/scripts/claude_session_pool.ps1
docs/codex_with_cc/scripts/verify_delegate_artifacts.ps1
docs/codex_with_cc/scripts/verify_delegate_chain.ps1
docs/codex_with_cc/scripts/run_real_delegate_chain_validation.ps1
docs/codex_with_cc/scripts/test_delegate_runtime.ps1
docs/codex_with_cc/scripts/test_delegate_session_pool.ps1
docs/codex_with_cc/CODEX_WITH_CC.md
docs/codex_with_cc/CLAUDE_CODE_DELEGATION.md
docs/codex_with_cc/HOST_PROJECT_RULES.md
docs/codex_with_cc/PROJECT_MEMORY.md

Verification command to run after this task completes:
pwsh -NoProfile -File .\docs\codex_with_cc\scripts\verify_delegate_artifacts.ps1 -RunId <reuse-2-run-id> -ArtifactRoot 'D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts'

只读验证任务：再次在同一 SessionKey 下顺序续接主线，验证高缓存命中不是偶发成功。

要求：
- 只读，不修改任何仓库文件。
- 必须复核主线 session 是否连续、并发池租约是否释放、lastTaskFingerprint 是否保留。
- 如果发现仍有问题，明确指出需要进入新的串行返工轮次，不要做范围外修改。
- 输出必须包含 Process Log / Summary / Changed Files / Verification / Final Result / Risks Or Follow-ups。
