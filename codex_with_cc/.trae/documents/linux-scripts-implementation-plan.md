# Linux/macOS 脚本实现计划

## 概述

将 codex_with_cc 项目的 Windows PowerShell 脚本移植到 Linux/macOS，使用 Bash 实现。在移植前，先修复审查发现的 PowerShell 脚本问题。

## 当前状态分析

### 项目结构
```
analyze-project-structure-YnSoTm/
├── CODEX_WITH_CC.md              # 工作流入口文档
├── .gitignore
├── macos_scripts/
│   └── README.md                 # 占位符，待实现
└── windows_scripts/              # 9 个 PowerShell 脚本
    ├── delegate_to_claude.ps1              # 核心委托入口 (735 行)
    ├── claude_session_pool.ps1             # 会话池管理 (523 行)
    ├── claude_delegate_backend_helpers.ps1 # 后端辅助函数 (442 行)
    ├── verify_delegate_artifacts.ps1       # 单次运行验证 (242 行)
    ├── verify_delegate_chain.ps1           # 链路验证 (168 行)
    ├── run_real_delegate_chain_validation.ps1 # 验证脚手架 (173 行)
    ├── test_delegate_runtime.ps1           # 运行时测试 (657 行)
    ├── test_delegate_session_pool.ps1      # 会话池测试 (559 行)
    └── test_helpers.ps1                    # 测试辅助 (85 行)
```

### 审查发现的问题

#### 1. 文档不一致问题
- **PrimaryAnchor 与 PrimaryReuse 行为相同**: 文档描述 `PrimaryAnchor` 是"并行批处理锚点"，但代码中两者行为完全相同
- **Scope 分隔符不一致**: `run_real_delegate_chain_validation.ps1` 使用换行符，而 `delegate_to_claude.ps1` 期望分号
- **任务文件名格式不一致**: 文档描述 `<HHmmssfff>`，代码生成 `<HHmmss-fff>`

#### 2. 逻辑错误
- **verify_delegate_artifacts.ps1 状态检查矛盾**: 允许 `starting`/`running` 状态检查，但随后又要求必须是 `completed` 或 `failed`
- **Acquire-ClaudeSessionLease 返回 null**: 在主会话被租用时返回 null 而非抛出异常，调用方需处理意外情况
- **PID 重用风险**: 仅检查进程是否存在，未结合时间戳验证

#### 3. 错误处理不完整
- **delegate_to_claude.ps1 异常类型过滤不完整**: 只捕获 `IOException`，其他异常类型可能导致锁未正确处理
- **DateTimeOffset 解析失败静默处理**: 时间戳格式错误时静默返回 true，可能掩盖数据损坏问题
- **chcp.com 错误被忽略**: 可能在没有控制台的环境中失败

---

## 实施计划

### 阶段 1: 修复 Windows PowerShell 脚本问题

#### 1.1 修复 claude_session_pool.ps1

**文件**: `windows_scripts/claude_session_pool.ps1`

**修改内容**:

1. **Acquire-ClaudeSessionLease 返回 null 问题** (第 304-306 行)
   - 问题: 主会话被租用时返回 null，调用方需处理意外情况
   - 修复: 保持当前行为，但在调用方 `delegate_to_claude.ps1` 中添加明确处理

2. **Test-LeaseExpired 时间戳解析** (第 86-90 行)
   - 问题: 解析失败静默返回 true
   - 修复: 添加警告日志，记录解析失败的具体值

```powershell
# 修改前
} catch {
    return $true
}

# 修改后
} catch {
    Write-Warning "Failed to parse leasedAt timestamp '$($Item.leasedAt)': $($_.Exception.Message)"
    return $true
}
```

#### 1.2 修复 delegate_to_claude.ps1

**文件**: `windows_scripts/delegate_to_claude.ps1`

**修改内容**:

1. **参数验证时机** (第 334-338 行)
   - 问题: `LockTimeoutSeconds` 验证只在 `-not $AllowParallel` 时执行
   - 修复: 将验证移到脚本开头

```powershell
# 在第 94 行后添加
if ($LockTimeoutSeconds -lt 0) {
    throw "LockTimeoutSeconds must be >= 0. Current: $LockTimeoutSeconds"
}
if ($LockPollMilliseconds -lt 50) {
    throw "LockPollMilliseconds must be >= 50. Current: $LockPollMilliseconds"
}
```

2. **异常类型过滤** (第 367 行)
   - 问题: 只捕获 `IOException`
   - 修复: 捕获所有异常类型

```powershell
# 修改前
} catch [System.IO.IOException] {

# 修改后
} catch {
```

#### 1.3 修复 verify_delegate_artifacts.ps1

**文件**: `windows_scripts/verify_delegate_artifacts.ps1`

**修改内容**:

1. **状态检查逻辑矛盾** (第 78-85 行)
   - 问题: 允许 `starting`/`running` 但随后又拒绝它们
   - 修复: 只允许 `completed` 和 `failed` 状态

```powershell
# 修改前
if ([string]$status.status -notin @('starting', 'running', 'completed', 'failed')) {
    throw "Unexpected delegate status value: $([string]$status.status)"
}
$isCompleted = ([string]$status.status -eq 'completed')
$isStructuredFailure = ([string]$status.status -eq 'failed')
if (-not $isCompleted -and -not $isStructuredFailure) {
    throw "Delegate status is neither completed nor failed: $([string]$status.status)"
}

# 修改后
if ([string]$status.status -notin @('completed', 'failed')) {
    throw "Delegate status must be 'completed' or 'failed'. Current: $([string]$status.status)"
}
$isCompleted = ([string]$status.status -eq 'completed')
$isStructuredFailure = ([string]$status.status -eq 'failed')
```

#### 1.4 修复 run_real_delegate_chain_validation.ps1

**文件**: `windows_scripts/run_real_delegate_chain_validation.ps1`

**修改内容**:

1. **Scope 分隔符不一致** (第 37-38 行等)
   - 问题: 使用换行符分隔，而 `delegate_to_claude.ps1` 期望分号
   - 修复: 改用分号分隔

```powershell
# 修改前
Scope = "docs/codex_with_cc/windows_scripts/delegate_to_claude.ps1`ndocs/codex_with_cc/..."

# 修改后
Scope = "docs/codex_with_cc/windows_scripts/delegate_to_claude.ps1;docs/codex_with_cc/..."
```

#### 1.5 更新 CODEX_WITH_CC.md

**文件**: `CODEX_WITH_CC.md`

**修改内容**:

1. **明确 PrimaryAnchor 语义**
   - 当前文档描述与实现不符
   - 选择: 保持代码行为，更新文档说明 `PrimaryAnchor` 和 `PrimaryReuse` 行为相同，区别在于语义标记

---

### 阶段 2: 创建 Linux/macOS Bash 脚本

#### 2.1 目录结构

创建 `unix_scripts/` 目录，包含所有 Bash 脚本：

```
unix_scripts/
├── delegate_to_claude.sh              # 核心委托入口
├── claude_session_pool.sh             # 会话池管理 (source 库)
├── claude_delegate_backend_helpers.sh # 后端辅助函数 (source 库)
├── verify_delegate_artifacts.sh       # 单次运行验证
├── verify_delegate_chain.sh           # 链路验证
├── run_real_delegate_chain_validation.sh # 验证脚手架
├── test_delegate_runtime.sh           # 运行时测试
├── test_delegate_session_pool.sh      # 会话池测试
└── test_helpers.sh                    # 测试辅助函数 (source 库)
```

#### 2.2 核心脚本实现

##### 2.2.1 delegate_to_claude.sh

**核心功能**:
- 参数解析 (使用 `getopts` 或手动解析)
- 子线程标记验证 (`CODEX_CLAUDE_CHILD_THREAD=1`)
- 会话租约获取/释放
- Claude CLI 调用与输出捕获
- 重试逻辑

**Linux 特有实现**:

| 功能 | Windows API | Linux 实现 |
|------|-------------|------------|
| 文件锁 | `[System.IO.File]::Open()` | `flock` 命令 |
| 进程检测 | `Get-Process -Id $pid` | `kill -0 $pid` 或检查 `/proc/$pid` |
| 环境变量 | `[Environment]::GetEnvironmentVariable()` | `${VAR:-default}` |
| UTF-8 编码 | `System.Text.UTF8Encoding` | 默认 UTF-8，无需特殊处理 |
| JSON 处理 | `ConvertFrom-Json` | `jq` 命令或 Python 内联 |
| 原子写入 | `Move-Item -Force` | `mv` (原子操作) |

**文件锁实现**:
```bash
acquire_lock() {
    local lockfile="$1"
    local timeout="$2"
    local deadline=$(($(date +%s) + timeout))
    
    exec 3>"$lockfile"
    while true; do
        if flock -x -n 3; then
            return 0
        fi
        if [[ $(date +%s) -ge $deadline ]]; then
            echo "Lock acquisition timeout" >&2
            return 1
        fi
        sleep 0.1
    done
}
```

**进程检测实现**:
```bash
is_process_alive() {
    local pid="$1"
    if [[ -d "/proc/$pid" ]]; then
        return 0
    fi
    return 1
}
```

##### 2.2.2 claude_session_pool.sh

**核心函数**:
- `new_claude_session_id`: 生成 UUID 格式会话 ID
- `get_effective_session_key`: 获取有效会话键
- `get_task_fingerprint`: 计算 SHA256 任务指纹
- `test_lease_expired`: 检测租约是否过期
- `acquire_claude_session_lease`: 获取会话租约
- `release_claude_session_lease`: 释放会话租约
- `reset_claude_session_lease_for_fresh_session`: 重置为全新会话

**UUID 生成**:
```bash
new_claude_session_id() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        python3 -c "import uuid; print(uuid.uuid4())"
    fi
}
```

**SHA256 指纹**:
```bash
get_task_fingerprint() {
    local text="$1"
    local scope="$2"
    local tests="$3"
    local mode="$4"
    
    local raw="mode=$mode
scope=$scope
tests=$tests
task=${text:0:1000}"
    
    echo -n "$raw" | sha256sum | cut -d' ' -f1
}
```

##### 2.2.3 claude_delegate_backend_helpers.sh

**核心函数**:
- `write_claude_delegate_json_file`: 原子写入 JSON 文件
- `test_claude_delegate_text_has_final_result_heading`: 检测 Final Result 标题
- `get_claude_delegate_output_resolution`: 解析输出结果
- `update_claude_delegate_stream_capture`: 捕获流式输出
- `new_claude_delegate_cli_args`: 构建 Claude CLI 参数
- `get_claude_delegate_retry_decision`: 决定重试策略

**原子 JSON 写入**:
```bash
write_claude_delegate_json_file() {
    local path="$1"
    local data="$2"
    local dir=$(dirname "$path")
    local tmpfile="${dir}/.$(basename "$path").$$.tmp"
    
    mkdir -p "$dir"
    echo "$data" > "$tmpfile"
    mv "$tmpfile" "$path"
}
```

##### 2.2.4 verify_delegate_artifacts.sh

**验证逻辑**:
- Schema 验证 (`artifactSchema = 2`)
- 子线程标记验证
- 状态验证
- 尝试记录验证
- 租约释放验证

##### 2.2.5 verify_delegate_chain.sh

**链路验证**:
- Anchor 运行验证
- Parallel 运行验证
- Reuse 运行验证
- 会话状态验证

#### 2.3 测试脚本实现

##### 2.3.1 test_helpers.sh

**断言函数**:
```bash
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
```

##### 2.3.2 test_delegate_runtime.sh

**测试场景**:
- 子线程标记缺失拒绝
- 文件锁竞争
- 非结构化输出规范化
- 过期会话重试
- stream-json 启动错误重试

##### 2.3.3 test_delegate_session_pool.sh

**测试场景**:
- 原子写入竞争
- 主会话创建
- Anchor 模式
- ParallelPool 创建/复用
- 过期租约回收
- 死进程回收

---

### 阶段 3: 更新文档

#### 3.1 更新 CODEX_WITH_CC.md

添加 Linux/macOS 使用说明：

```markdown
## Platform-Specific Scripts

- Windows: `docs/codex_with_cc/windows_scripts/delegate_to_claude.ps1`
- Linux/macOS: `docs/codex_with_cc/unix_scripts/delegate_to_claude.sh`

## Standard Worker Command (Linux/macOS)

```bash
export CODEX_CLAUDE_CHILD_THREAD=1
bash docs/codex_with_cc/unix_scripts/delegate_to_claude.sh \
  -TaskFile .codex/codex_with_cc/tasks/<yyyyMMdd>/<task-file>.md \
  -SessionMode PrimaryReuse \
  -SessionKey <session-key> \
  -BypassPermissions
```
```

#### 3.2 更新 macos_scripts/README.md

指向统一的 `unix_scripts/` 目录：

```markdown
# macOS Scripts

macOS uses the unified Unix scripts located in `../unix_scripts/`.

Please refer to `../unix_scripts/` for the implementation.
```

---

## 文件变更清单

### 阶段 1: 修复 PowerShell 脚本

| 文件 | 操作 | 说明 |
|------|------|------|
| `windows_scripts/claude_session_pool.ps1` | 修改 | 添加时间戳解析失败警告 |
| `windows_scripts/delegate_to_claude.ps1` | 修改 | 参数验证前移、异常类型扩展 |
| `windows_scripts/verify_delegate_artifacts.ps1` | 修改 | 修复状态检查逻辑 |
| `windows_scripts/run_real_delegate_chain_validation.ps1` | 修改 | 修复 Scope 分隔符 |
| `CODEX_WITH_CC.md` | 修改 | 明确 PrimaryAnchor 语义 |

### 阶段 2: 创建 Bash 脚本

| 文件 | 操作 | 说明 |
|------|------|------|
| `unix_scripts/delegate_to_claude.sh` | 新建 | 核心委托入口 |
| `unix_scripts/claude_session_pool.sh` | 新建 | 会话池管理库 |
| `unix_scripts/claude_delegate_backend_helpers.sh` | 新建 | 后端辅助函数库 |
| `unix_scripts/verify_delegate_artifacts.sh` | 新建 | 单次运行验证 |
| `unix_scripts/verify_delegate_chain.sh` | 新建 | 链路验证 |
| `unix_scripts/run_real_delegate_chain_validation.sh` | 新建 | 验证脚手架 |
| `unix_scripts/test_delegate_runtime.sh` | 新建 | 运行时测试 |
| `unix_scripts/test_delegate_session_pool.sh` | 新建 | 会话池测试 |
| `unix_scripts/test_helpers.sh` | 新建 | 测试辅助函数库 |

### 阶段 3: 更新文档

| 文件 | 操作 | 说明 |
|------|------|------|
| `CODEX_WITH_CC.md` | 修改 | 添加 Linux/macOS 使用说明 |
| `macos_scripts/README.md` | 修改 | 指向 unix_scripts 目录 |

---

## 假设与决策

### 假设
1. Linux/macOS 环境已安装 `jq` 用于 JSON 处理
2. Linux/macOS 环境已安装 `flock` (util-linux 包)
3. Claude Code CLI 已安装并在 PATH 中
4. Bash 版本 >= 4.0 (支持关联数组)

### 决策
1. **脚本语言**: 使用 Bash，与 PowerShell 风格相近
2. **功能范围**: 完整移植所有 9 个脚本
3. **macOS 支持**: 与 Linux 使用统一脚本，放入 `unix_scripts/` 目录
4. **JSON 处理**: 使用 `jq` 命令，必要时内联 Python
5. **文件锁**: 使用 `flock` 命令
6. **进程检测**: 使用 `/proc/$pid` 目录存在性检查

---

## 验证步骤

### 阶段 1 验证
1. 运行 PowerShell 测试脚本确认修复无回归
   ```powershell
   pwsh -NoProfile -File .\windows_scripts\test_delegate_runtime.ps1
   pwsh -NoProfile -File .\windows_scripts\test_delegate_session_pool.ps1
   ```

### 阶段 2 验证
1. 运行 Bash 测试脚本
   ```bash
   bash unix_scripts/test_delegate_runtime.sh
   bash unix_scripts/test_delegate_session_pool.sh
   ```

### 阶段 3 验证
1. 在 Linux 环境执行真实委托链路验证
2. 在 macOS 环境执行真实委托链路验证
