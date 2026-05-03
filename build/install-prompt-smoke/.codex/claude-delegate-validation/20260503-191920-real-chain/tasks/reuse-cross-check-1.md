# Real Delegate Chain Validation Task

- SessionKey: delegate-real-chain-fab4b8acedc1
- ArtifactRoot: D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts
- SessionMode: PrimaryReuse
- Child-thread only: This task must run inside a Codex spawn_agent child thread with model 'gpt-5.3-codex', reasoning_effort 'high', fork_context 'false'.
- Required child-thread marker: set process environment CODEX_CLAUDE_CHILD_THREAD=1 before invoking the worker entry script.
- Worker entry script: docs/codex_with_cc/scripts/delegate_to_claude.ps1
- Required worker arguments: -TaskFile "D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\tasks\reuse-cross-check-1.md" -ArtifactRoot "D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts" -SessionKey "delegate-real-chain-fab4b8acedc1" -SessionMode PrimaryReuse -BypassPermissions

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
pwsh -NoProfile -File .\docs\codex_with_cc\scripts\verify_delegate_artifacts.ps1 -RunId <reuse-1-run-id> -ArtifactRoot 'D:\Develop\GitHub\codex_with_cc\build\install-prompt-smoke\.codex\claude-delegate-validation\20260503-191920-real-chain\artifacts'

真实复核/返工任务：在锚点与并发旁路完成后，使用同一 SessionKey 续接主线，对前三份结果做交叉复核。

要求：
- 先复核，不做无关修改。
- 必须确认 PrimaryReuse 优先尝试 resume=true；如果恢复为 fresh session，必须解释审计链。
- 如果发现真实缺陷，允许在允许范围内修改仓库文件，并补齐最小必要测试。
- 如果修改任何仓库文件，必须遵守 docs/codex_with_cc/HOST_PROJECT_RULES.md，并在 Verification 中列出实际运行的验证命令。
- 输出必须包含 Process Log / Summary / Changed Files / Verification / Final Result / Risks Or Follow-ups。
