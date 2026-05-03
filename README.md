# codex_with_cc

> 如果你是 Codex / Claude / Gemini / 其他 AI 代理，并且用户让你把本仓库集成到某个项目里：请先阅读 [docs/AI_INSTALL.md](docs/AI_INSTALL.md)。下面的信息是写给人看的，别在 README 里表演施工队。

Codex 子代理任意模型大协作，Codex 穷鬼大救星！

先把话放在前面：装好 Claude Code，装好 CC Switch，再通过 CC Switch 把 Claude Code 后面的 API 换成 DeepSeek。恭喜你，Codex Plus 基本就可以爽用了：Codex 负责规划任务、统筹上下文、审核结果；子代理里再通过 Claude Code 让 DeepSeek 去干活。

重点是 DeepSeek 那个夸张的缓存命中率，俩分钱百万 token 的体感一出来，基本告别 token 焦虑。人民的 DeepSeek，小 D 的恩情还不完😭。

这个仓库做的事情很朴素：把一套 `Codex -> Codex 子代理 -> Claude Code CLI` 的委派工作流复制进任意项目，让 Codex 当 leader，Claude Code/DeepSeek 当大头兵。脏活累活、长上下文探索、大范围改代码、互相找茬，都扔给子代理；主 Codex 只管拆解、调度、验收、打回重改。

## 你需要先准备什么

1. 安装 Claude Code。
2. 安装 CC Switch。
3. 在 CC Switch 里把 Claude Code 的后端 API 切到 DeepSeek。
4. 准备一个你想接入这套工作流的目标项目。
5. 打开 Codex。

没有 Codex？那不好意思，本项目不适合你。这里就是给 Codex 当 leader、子代理当打工人的，不是给人肉复制粘贴挑战赛准备的。

Claude Code、CC Switch、DeepSeek API 的安装方式会随它们自己的版本变化，建议按各自官方说明走。这里不强行写死外部命令，免得明天就变成考古现场。

## 一句话安装

推荐安装方式就一句话：把下面这句扔给目标项目里的 Codex。

```text
集成 https://github.com/xdd666t/codex_with_cc 调度子线程工作流到本项目中。
```

你也可以更凶一点：

```text
请把 https://github.com/xdd666t/codex_with_cc 集成到当前项目，安装 docs/codex_with_cc 工作流，更新 AGENTS.md、CLAUDE.md、GEMINI.md 的入口提示，保留项目原有规则。安装后运行可用验证，并告诉我如何使用 Codex 子代理委派 Claude Code/DeepSeek 干活。
```

这才是正经用法：你负责发号施令，Codex 负责搬砖和验收。安装细节、验证命令、Windows/macOS 适配这些苦力活，已经放在 [docs/AI_INSTALL.md](docs/AI_INSTALL.md) 里让 AI 自己啃。

## macOS 用户

Mac 用户不要自己抄 Windows 命令。直接把这句扔给 Mac 上的 Codex：

```text
请把 https://github.com/xdd666t/codex_with_cc 调度子线程工作流集成到当前 macOS 项目，并把安装、委派、验证相关命令迁移为 macOS 原生命令。
```

该用 `bash`/`zsh` 就用 `bash`/`zsh`，该用 Unix 路径就用 Unix 路径，该处理可执行权限就处理可执行权限。你负责一句话下令，它负责把跨平台这锅端稳。

## 使用姿势

核心心法只有一句：让 Codex 做 leader，让子代理当大头兵。

你可以这样安排活：

```text
你拆解 xxx 任务，安排给多个子代理实现。你负责审核子代理结果，不符合要求就打回让他们重改，直到符合要求为止。
```

适合大任务拆分：

```text
你先阅读项目，拆成 3 个互不冲突的实现任务，分别交给子代理处理。每个子代理必须给出变更文件、验证命令和风险说明。你最后统一 review、整合，并跑最终验证。
```

适合多方案头脑风暴：

```text
请启动多个子代理分别提出 xxx 的实现方案。每个方案需要说明优缺点、复杂度、风险和迁移成本。你汇总后给出推荐方案，不要直接照抄任何一个子代理。
```

适合互相找茬：

```text
安排一个子代理实现 xxx，再安排另一个子代理专门做代码审查和边界情况攻击。你负责判断 review 是否成立，成立就打回实现代理修改，不成立就说明理由。
```

适合长上下文探索：

```text
请把项目里的 xxx 模块交给子代理做深度调查，要求输出调用链、关键文件、潜在风险和建议修改点。你只保留结论，别把所有噪音塞回主上下文。
```

## 这套工作流到底在干嘛

主 Codex 线程负责理解需求、拆任务、创建子代理、审核结果、打回返工和最终交付。

Codex 子代理负责作为可追踪的对话树节点，调用委派脚本，把具体实现、调查、审查这些高 token 消耗任务交给 Claude Code CLI。

Claude Code CLI 负责执行被委派的具体任务，按要求修改文件或做调查，运行验证，并输出结构化报告。

这样主线程不会被海量代码和日志淹掉，子代理干苦活，主 Codex 保持清醒。项目越大，这个分工越香。

## 适合什么场景

- 大范围代码阅读和模块梳理。
- 多文件实现任务。
- 重复但费 token 的测试修复。
- 让多个代理分别给方案，再由 Codex 汇总决策。
- 一个代理写代码，另一个代理专门 review。
- 迁移、重构、补测试、查调用链这类脏活累活。

不太适合：

- 只有一两行的小改动。
- 需要主线程实时交互判断的需求。
- 文件冲突极高、边界还没想清楚的并行任务。

## 最后一句人话

Codex 不是不能自己干活，但它更适合当架构师、项目经理、审稿人和最终责任人。真正吃 token 的苦力活，交给 Claude Code 后面的 DeepSeek 去啃。你要做的，就是学会给 Codex 下这种命令：

```text
你负责拆解、派工、审核和最终交付。子代理负责执行。结果不合格就返工，直到符合我的要求。
```

然后坐好，看小 D 把 token 焦虑按在地上摩擦。
