# Linux /tmp Runtime 实现计划

基于 `codex_with_cc/LINUX_TMP_RUNTIME_PLAN.md` 的具体代码修改步骤。

---

## 阶段 1：核心参数和路径解析（delegate_to_claude.sh）

文件：`codex_with_cc/unix_scripts/delegate_to_claude.sh`

### 1.1 添加 `--tmp-runtime` 参数解析

在变量声明区（第 31 行 `DRY_RUN=false` 之后）添加：

```bash
TMP_RUNTIME=false
```

在 `usage()` 函数中（第 62 行 `--dry-run` 之前）添加：

```bash
  --tmp-runtime             Use /tmp/codex_with_cc/<repo>/claude-delegate as artifact root
```

在参数解析 while 循环中（第 165 行 `--dry-run` 之前）添加 case：

```bash
        --tmp-runtime)
            TMP_RUNTIME=true
            shift
            ;;
```

### 1.2 读取环境变量 `CODEX_WITH_CC_TMP_RUNTIME`

在参数解析循环结束后、`SCRIPT_DIR` 定义之前，添加环境变量读取：

```bash
if [[ "$TMP_RUNTIME" != "true" ]]; then
    case "${CODEX_WITH_CC_TMP_RUNTIME:-}" in
        1|true|TRUE)
            TMP_RUNTIME=true
            ;;
    esac
fi
```

### 1.3 添加 `get_tmp_delegate_artifact_root` 辅助函数

在 `get_default_delegate_artifact_root` 函数（第 188-201 行）之后添加：

```bash
get_tmp_delegate_artifact_root() {
    local repo_root="$1"
    local repo_name
    repo_name=$(basename "$repo_root" | sed 's/[^A-Za-z0-9_.-]/_/g')
    printf '/tmp/codex_with_cc/%s/claude-delegate\n' "$repo_name"
}
```

### 1.4 修改 artifact root 解析逻辑

将第 229-232 行的 artifact root 解析逻辑替换为：

```bash
ARTIFACT_ROOT_SOURCE=""

if [[ -n "$ARTIFACT_ROOT" ]]; then
    ARTIFACT_ROOT_SOURCE="explicit"
elif [[ "$TMP_RUNTIME" == "true" ]]; then
    ARTIFACT_ROOT="$(get_tmp_delegate_artifact_root "$REPO_ROOT")"
    ARTIFACT_ROOT_SOURCE="tmp-runtime"
else
    preferred="$REPO_ROOT/.codex/codex_with_cc/claude-delegate"
    writable=$(test_claude_delegate_path_writable "$preferred/.artifact_probe")
    if [[ "$writable" == "true" ]]; then
        ARTIFACT_ROOT="$preferred"
        ARTIFACT_ROOT_SOURCE="repo-default"
    else
        ARTIFACT_ROOT="$(get_tmp_delegate_artifact_root "$REPO_ROOT")"
        ARTIFACT_ROOT_SOURCE="auto-tmp-fallback"
    fi
fi
```

### 1.5 添加 tmp runtime 元数据到 config JSON

在所有 config JSON 写入中添加以下三个字段。注意：config 有 3 个写入点（初始第 430 行、session lease 更新后第 689 行、complete_claude_delegate_startup_failure 第 565 行）。

每个 config JSON 需要添加：

```json
  "tmpRuntimeRequested": $TMP_RUNTIME,
  "tmpRuntimeEffective": $([ "$ARTIFACT_ROOT_SOURCE" = "explicit" -o "$ARTIFACT_ROOT_SOURCE" = "tmp-runtime" -o "$ARTIFACT_ROOT_SOURCE" = "auto-tmp-fallback" ] && echo true || echo false),
  "artifactRootSource": $(json_quote "$ARTIFACT_ROOT_SOURCE"),
```

具体修改位置：
- **初始 config**（约第 462 行 `"updatedAt":` 之前）
- **session lease 更新后 config**（约第 721 行 `"updatedAt":` 之前）
- **failure config**（约第 600 行 `"updatedAt":` 之前）

### 1.6 添加 tmp runtime 元数据到 status JSON

Status JSON 有 3 个写入点（初始第 487 行、running 状态第 802 行、complete_claude_delegate_startup_failure 第 562 行）。每个 status JSON 需要添加：

```json
  "tmpRuntimeRequested": $TMP_RUNTIME,
  "tmpRuntimeEffective": $([ "$ARTIFACT_ROOT_SOURCE" = "explicit" -o "$ARTIFACT_ROOT_SOURCE" = "tmp-runtime" -o "$ARTIFACT_ROOT_SOURCE" = "auto-tmp-fallback" ] && echo true || echo false),
  "artifactRootSource": $(json_quote "$ARTIFACT_ROOT_SOURCE"),
```

**注意**：在 `complete_claude_delegate_startup_failure` 里，`$ARTIFACT_ROOT_SOURCE` 变量已被设置（因为 artifact root 解析在该函数调用之前已完成）。

### 1.7 修改 `write_trusted_local_terminal_rerun_script` 保留 `--tmp-runtime`

修改第 338-352 行的 rerun 脚本生成逻辑。当 `TMP_RUNTIME=true` 且没有显式 `--artifact-root` 时，rerun 脚本应包含 `--tmp-runtime` 而不是显式的 `--artifact-root`。

具体修改：在 `write_trusted_local_terminal_rerun_script` 函数中，artifact-root 行改为条件逻辑：

```bash
# 替换现有的 --artifact-root 行（约第 349 行）
if [[ -n "${ORIGINAL_ARTIFACT_ROOT_ARG:-}" ]]; then
    # 用户显式传了 --artifact-root
    printf ' \\\n  --artifact-root %s' "$(shell_quote "$RESOLVED_ARTIFACT_ROOT")"
elif [[ "$TMP_RUNTIME" == "true" ]]; then
    printf ' \\\n  --tmp-runtime'
else
    printf ' \\\n  --artifact-root %s' "$(shell_quote "$RESOLVED_ARTIFACT_ROOT")"
fi
```

为实现此逻辑，需要在参数解析阶段记住用户是否显式传了 `--artifact-root`：

```bash
# 在解析到 --artifact-root 时设置
ORIGINAL_ARTIFACT_ROOT_ARG="$2"
```

### 1.8 在启动信息输出中展示 artifact root 来源

在约第 725-736 行的 echo 信息块末尾添加：

```bash
echo "Artifact Root Source: $ARTIFACT_ROOT_SOURCE"
if [[ "$TMP_RUNTIME" == "true" ]]; then
    echo "Tmp Runtime: requested"
else
    echo "Tmp Runtime: not requested"
fi
```

---

## 阶段 2：验证和链路脚本

### 2.1 `run_real_delegate_chain_validation.sh`

文件：`codex_with_cc/unix_scripts/run_real_delegate_chain_validation.sh`

**修改点 1**：在第 13 行 `ARTIFACT_ROOT=...` 之后添加 `TMP_RUNTIME` 支持。

在脚本顶部变量区添加参数解析，支持 `--tmp-runtime`：

```bash
TMP_RUNTIME=false
```

解析命令行参数（在 `$TIME_DIR` 创建之前插入）：

```bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tmp-runtime)
            TMP_RUNTIME=true
            shift
            ;;
        *)
            break
            ;;
    esac
done
```

同时读取环境变量：

```bash
if [[ "$TMP_RUNTIME" != "true" ]]; then
    case "${CODEX_WITH_CC_TMP_RUNTIME:-}" in
        1|true|TRUE) TMP_RUNTIME=true ;;
    esac
fi
```

**修改点 2**：修改 `ARTIFACT_ROOT` 的默认值（第 13 行）。

```bash
if [[ "$TMP_RUNTIME" == "true" ]]; then
    REPO_NAME=$(basename "$REPO_ROOT" | sed 's/[^A-Za-z0-9_.-]/_/g')
    ARTIFACT_ROOT="/tmp/codex_with_cc/$REPO_NAME/claude-delegate"
else
    ARTIFACT_ROOT="$REPO_ROOT/.codex/codex_with_cc/claude-delegate"
fi
```

**修改点 3**：所有 5 条委派命令和链验证命令添加 `--tmp-runtime`（仅当 `TMP_RUNTIME=true`）。

在生成每个委派命令时（约第 90-113 行），改为条件添加：

```bash
# 每个命令的构建中，在 --bypass-permissions 之前添加
$(if [[ "$TMP_RUNTIME" == "true" ]]; then printf ' \\\n  --tmp-runtime'; fi)
```

同样，链验证命令也需要条件添加 tmp artifact root：

```bash
  -a "$ARTIFACT_ROOT"
```

（因为 ARTIFACT_ROOT 已经根据 TMP_RUNTIME 设置了正确的值，-a 参数不需要变，但生成的任务文件（task scope/test 中的 artifact root 引用）需要使用正确的 $ARTIFACT_ROOT。

### 2.2 `verify_delegate_artifacts.sh`

文件：`codex_with_cc/unix_scripts/verify_delegate_artifacts.sh`

在现有验证逻辑末尾（约第 420 行 session state path 检查之后），添加 tmp runtime 兼容校验：

```bash
# Tmp runtime metadata compatibility checks (non-breaking)
TMP_REQUESTED_STATUS=$(echo "$STATUS" | jq -r '.tmpRuntimeRequested // ""')
TMP_REQUESTED_CONFIG=$(echo "$CONFIG" | jq -r '.tmpRuntimeRequested // ""')

if [[ -n "$TMP_REQUESTED_STATUS" ]] && [[ -n "$TMP_REQUESTED_CONFIG" ]]; then
    if [[ "$TMP_REQUESTED_STATUS" != "$TMP_REQUESTED_CONFIG" ]]; then
        echo "tmpRuntimeRequested mismatch. status=$TMP_REQUESTED_STATUS config=$TMP_REQUESTED_CONFIG" >&2
        exit 1
    fi
fi

TMP_EFFECTIVE_STATUS=$(echo "$STATUS" | jq -r '.tmpRuntimeEffective // ""')
TMP_EFFECTIVE_CONFIG=$(echo "$CONFIG" | jq -r '.tmpRuntimeEffective // ""')

if [[ -n "$TMP_EFFECTIVE_STATUS" ]] && [[ -n "$TMP_EFFECTIVE_CONFIG" ]]; then
    if [[ "$TMP_EFFECTIVE_STATUS" != "$TMP_EFFECTIVE_CONFIG" ]]; then
        echo "tmpRuntimeEffective mismatch. status=$TMP_EFFECTIVE_STATUS config=$TMP_EFFECTIVE_CONFIG" >&2
        exit 1
    fi
fi

ARTIFACT_ROOT_SOURCE_STATUS=$(echo "$STATUS" | jq -r '.artifactRootSource // ""')
ARTIFACT_ROOT_SOURCE_CONFIG=$(echo "$CONFIG" | jq -r '.artifactRootSource // ""')

if [[ -n "$ARTIFACT_ROOT_SOURCE_STATUS" ]] || [[ -n "$ARTIFACT_ROOT_SOURCE_CONFIG" ]]; then
    if [[ "$ARTIFACT_ROOT_SOURCE_STATUS" != "$ARTIFACT_ROOT_SOURCE_CONFIG" ]]; then
        echo "artifactRootSource mismatch. status=$ARTIFACT_ROOT_SOURCE_STATUS config=$ARTIFACT_ROOT_SOURCE_CONFIG" >&2
        exit 1
    fi

    VALID_SOURCES=("explicit" "tmp-runtime" "repo-default" "auto-tmp-fallback")
    local source_valid="false"
    for src in "${VALID_SOURCES[@]}"; do
        if [[ "$ARTIFACT_ROOT_SOURCE_STATUS" == "$src" ]]; then
            source_valid="true"
            break
        fi
    done
    if [[ "$source_valid" != "true" ]]; then
        echo "Unknown artifactRootSource: $ARTIFACT_ROOT_SOURCE_STATUS" >&2
        exit 1
    fi
fi
```

同时在最终成功消息中显示 artifact root source：

```bash
if [[ -n "$ARTIFACT_ROOT_SOURCE_STATUS" ]]; then
    echo "Artifact Root Source: $ARTIFACT_ROOT_SOURCE_STATUS"
fi
```

### 2.3 `verify_delegate_chain.sh`

文件：`codex_with_cc/unix_scripts/verify_delegate_chain.sh`

**修改点**：在输出中添加 artifact root 显示，帮助用户定位产物位置。

在脚本开头（约第 88 行 `echo "Verifying..."` 之后）添加：

```bash
echo "Artifact Root: $ARTIFACT_ROOT"
```

---

## 阶段 3：测试

### 3.1 `test_delegate_runtime.sh`

文件：`codex_with_cc/unix_scripts/test_delegate_runtime.sh`

在现有测试函数之后、`echo "===="` 之前，添加 4 个新测试函数：

```bash
test_tmp_runtime_uses_tmp_artifact_root() {
    local tmp_root
    tmp_root=$(mktemp -d)
    local tmp_home
    tmp_home=$(mktemp -d)

    # Use dry-run so we don't need actual claude
    local result
    result=$(HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" CODEX_CLAUDE_CHILD_THREAD=1 timeout 5 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "test task" \
        --tmp-runtime \
        --dry-run \
        2>&1 || true)

    # Check config/status point to /tmp/codex_with_cc/.../claude-delegate
    local config_path
    config_path=$(find "$tmp_root" -name 'config_*.json' 2>/dev/null | head -n 1)
    # The config/status should be in /tmp/codex_with_cc/... not in $tmp_root
    # Actually since we use --tmp-runtime, artifacts go to /tmp/codex_with_cc/<repo>/claude-delegate
    # So we check the output messages instead
    local found_artifact_root
    found_artifact_root=$(echo "$result" | grep "Artifact Root:" | head -n 1)

    rm -rf "$tmp_root" "$tmp_home"

    if echo "$result" | grep -q "/tmp/codex_with_cc/"; then
        echo "true"
    else
        echo "false"
    fi
}

test_tmp_runtime_env_var_uses_tmp_artifact_root() {
    local tmp_root
    tmp_root=$(mktemp -d)
    local tmp_home
    tmp_home=$(mktemp -d)

    local result
    result=$(CODEX_WITH_CC_TMP_RUNTIME=1 HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" CODEX_CLAUDE_CHILD_THREAD=1 timeout 5 bash "$SCRIPT_DIR/delegate_to_claude.sh" \
        -t "test task" \
        --dry-run \
        2>&1 || true)

    rm -rf "$tmp_root" "$tmp_home"

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

    # Should use explicit artifact root, not /tmp
    if echo "$result" | grep -q "Artifact Root Source: explicit"; then
        echo "true"
    else
        echo "false"
    fi
}

test_rerun_script_preserves_tmp_runtime() {
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
        --tmp-runtime \
        --artifact-root "$tmp_root" \
        2>&1 || true)

    local rerun_script
    rerun_script=$(find "$tmp_root" -maxdepth 1 -name 'rerun_*.sh' | head -n 1)

    local rerun_content=""
    if [[ -n "$rerun_script" ]]; then
        rerun_content=$(cat "$rerun_script")
    fi

    chmod 755 "$readonly_home"
    rm -rf "$home_parent" "$tmp_root"

    if echo "$rerun_content" | grep -q "\-\-tmp-runtime"; then
        echo "true"
    else
        echo "false"
    fi
}
```

在 `run_test` 调用区域（约第 323 行）添加：

```bash
run_test "tmp_runtime_uses_tmp_artifact_root" test_tmp_runtime_uses_tmp_artifact_root
run_test "tmp_runtime_env_var_uses_tmp_artifact_root" test_tmp_runtime_env_var_uses_tmp_artifact_root
run_test "explicit_artifact_root_overrides_tmp_runtime" test_explicit_artifact_root_overrides_tmp_runtime
run_test "rerun_script_preserves_tmp_runtime" test_rerun_script_preserves_tmp_runtime
```

### 3.2 `test_delegate_session_pool.sh`

文件：`codex_with_cc/unix_scripts/test_delegate_session_pool.sh`

不需要修改。Session pool 逻辑不涉及 artifact root 路径。

---

## 阶段 4：文档

### 4.1 `codex_with_cc/CODEX_WITH_CC.md`

文件：`codex_with_cc/CODEX_WITH_CC.md`

**修改点 1**：Trusted Local Terminal Fallback 章节（第 39-44 行），在第 44 行末尾之后添加：

```markdown
### Linux/macOS Tmp Runtime

On Linux/macOS, the `--tmp-runtime` flag (or `CODEX_WITH_CC_TMP_RUNTIME=1`) explicitly uses `/tmp/codex_with_cc/<repo-name>/claude-delegate` as the artifact root from the first invocation, avoiding the need to hit a permission error before falling back to `/tmp`.

This flag only affects the artifact root; task files remain under `.codex/codex_with_cc/tasks/` in the target project. The `--tmp-runtime` flag has no effect when an explicit `--artifact-root` is provided.
```

**修改点 2**：Artifacts 章节（第 84-96 行），修改为：

```markdown
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

Use `verify_delegate_artifacts.ps1` (Windows) or `verify_delegate_artifacts.sh` (Linux/macOS) for each run and `verify_delegate_chain.ps1` (Windows) or `verify_delegate_chain.sh` (Linux/macOS) for multi-run continuity checks.
```

**修改点 3**：Standard Worker Command (Linux/macOS) 章节（第 118-125 行），添加推荐的 `--tmp-runtime` 形式：

```markdown
## Standard Worker Command (Linux/macOS)

Recommended form with explicit tmp runtime (avoids repo permission issues):

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh \
  -f .codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-file>.md \
  --session-mode PrimaryReuse \
  --session-key <stable-session-key> \
  --tmp-runtime \
  --bypass-permissions
```

Without tmp runtime (uses repo-local artifact root by default):

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh \
  -f .codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-file>.md \
  --session-mode PrimaryReuse \
  --session-key <stable-session-key> \
  --bypass-permissions
```

Use `PrimaryAnchor --allow-parallel` for the main branch of a parallel batch and `ParallelPool --allow-parallel` for independent side work.
```

**修改点 4**：Verification 章节（约第 143-144 行），添加 tmp runtime 验证示例：

在 Linux/macOS 验证命令之后添加：

```bash
# With tmp runtime artifact root
bash docs/codex_with_cc/unix_scripts/verify_delegate_artifacts.sh -r <run-id> -a /tmp/codex_with_cc/<repo>/claude-delegate
bash docs/codex_with_cc/unix_scripts/verify_delegate_chain.sh --anchor-run-id <id> --parallel-run-ids "<ids>" --reuse-run-ids "<ids>" -a /tmp/codex_with_cc/<repo>/claude-delegate --session-key <key>
```

### 4.2 `AI_INSTALL.md`

文件：`AI_INSTALL.md`

**修改点 1**：Linux/macOS 委派模板（第 224-233 行），改为推荐使用 `--tmp-runtime`：

```markdown
Linux/macOS 模板中的子代理标准调用形态（推荐使用 `--tmp-runtime` 避免仓库权限问题）：

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash ./docs/codex_with_cc/unix_scripts/delegate_to_claude.sh \
  -f ./.codex/codex_with_cc/tasks/<yyyyMMdd>/<HHmmssfff>-<short-id>-<task-file>.md \
  --session-mode PrimaryReuse \
  --session-key <stable-session-key> \
  --tmp-runtime \
  --bypass-permissions
```

如果不使用 `--tmp-runtime`，产物默认写在目标项目 `.codex/codex_with_cc/claude-delegate`：
```

（保留原有的不带 `--tmp-runtime` 的模板作为第二选项）

**修改点 2**：产物位置章节（第 254-294 行），添加 Linux/macOS tmp runtime 产物位置说明：

在现有产物位置说明后（第 271 行之后）添加：

```markdown
Linux/macOS 下如果启用 `--tmp-runtime` 或 `CODEX_WITH_CC_TMP_RUNTIME=1`，委派运行产物会写在：

```text
/tmp/codex_with_cc/<repo-name>/claude-delegate
```

`.codex/codex_with_cc/tasks` 任务文件仍然在目标项目里，只有委派运行产物进入 `/tmp`。
```

**修改点 3**：安装完成后回复用户章节（第 298 行之后），添加 tmp runtime 汇报要求：

```markdown
如果使用了 tmp runtime，必须在汇报中明确真实 artifact root 路径（即 `/tmp/codex_with_cc/<repo>/claude-delegate`），而不是目标项目下的 `.codex/codex_with_cc/claude-delegate`。
```

### 4.3 `README.md`

文件：`README.md`

在"这不是提示词玩具"章节（约第 79 行之后），添加一句：

```markdown
Linux/macOS 还可以直接启用 `/tmp` runtime（`--tmp-runtime` 或 `CODEX_WITH_CC_TMP_RUNTIME=1`），避免仓库权限导致委派脚本先失败再回退的体验。详见 [codex_with_cc/CODEX_WITH_CC.md](codex_with_cc/CODEX_WITH_CC.md)。
```

### 4.4 `PROJECT_STRUCTURE.md`

文件：`PROJECT_STRUCTURE.md`

在"安装后目标项目结构"章节（约第 53 行之后），添加说明：

```markdown
- Linux/macOS 下如果使用 `--tmp-runtime`，委派运行产物会放在 `/tmp/codex_with_cc/<repo-name>/claude-delegate`，该路径不在安装目录内，也不进入版本库。
```

---

## 阶段 5：安装测试

### 5.1 `tests/test_install_codex_with_cc.sh`

文件：`tests/test_install_codex_with_cc.sh`

在现有断言区域（约第 100 行 `delegate_text=` 断言之后），添加两个新断言：

```bash
# Assert --tmp-runtime is documented in CODEX_WITH_CC.md
codex_with_cc_text="$(cat "$workflow_root/CODEX_WITH_CC.md")"
assert_contains "codex-with-cc-md-contains-tmp-runtime" "$codex_with_cc_text" '--tmp-runtime'

# Assert --tmp-runtime is available in delegate_to_claude.sh
assert_contains "delegate-script-contains-tmp-runtime" "$delegate_text" '--tmp-runtime'
```

### 5.2 `tests/test_install_codex_with_cc.ps1`

文件：`tests/test_install_codex_with_cc.ps1`

不做功能修改。可选断言（不强制）：CODEX_WITH_CC.md 可能提到 Linux/macOS 专属 tmp runtime，但 Windows 安装目录不包含 unix_scripts。

---

## 实施顺序

1. **阶段 1**：修改 `delegate_to_claude.sh` — 核心参数和路径解析
2. **阶段 2**：修改验证和链路脚本
3. **阶段 3**：添加测试用例到 `test_delegate_runtime.sh`
4. **阶段 4**：更新文档（CODEX_WITH_CC.md, AI_INSTALL.md, README.md, PROJECT_STRUCTURE.md）
5. **阶段 5**：更新安装测试断言

## 验证步骤

```bash
# 阶段 1-3 完成后
bash codex_with_cc/unix_scripts/test_delegate_runtime.sh
bash codex_with_cc/unix_scripts/test_delegate_session_pool.sh

# 阶段 5 完成后
bash tests/test_install_codex_with_cc.sh

# 完整安装验证
bash scripts/install_codex_with_cc.sh --target-root /tmp/codex_with_cc-install-check --platform Linux
# 检查 /tmp/codex_with_cc-install-check/docs/codex_with_cc/CODEX_WITH_CC.md 包含 --tmp-runtime
# 检查 /tmp/codex_with_cc-install-check/docs/codex_with_cc/unix_scripts/delegate_to_claude.sh 包含 --tmp-runtime
```

## 风险回滚

如果出现问题：

1. 从 `delegate_to_claude.sh` 移除 `--tmp-runtime` 参数解析（保留自动 fallback）
2. 从 config/status JSON 移除 tmp runtime 元数据字段
3. 回退文档中的主动 tmp runtime 说明
4. 删除新增测试断言
5. 回滚不影响现有 repo-local artifact root 和 failure contract
