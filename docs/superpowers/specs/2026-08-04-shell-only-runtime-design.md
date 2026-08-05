# 设计：纯 shell 运行时（移除 Obsidian CLI）与跨平台

日期：2026-08-04  
状态：已批准  
仓库：MemoVault-SKILL  
版本目标：`0.5.0`（breaking）

## 1. 目标

将 MemoVault 从「Obsidian CLI 优先 + fs 回退」改为 **唯一的 bash/文件系统运行时**：

1. 删除对有头 Obsidian / `obsidian` CLI 的运行时依赖与模式探测。
2. 在纯 shell 下为 `rename` / `move` 提供 **wikilink 自动改写**。
3. 官方支持平台：**macOS**、**Linux**（bash 3.2 兼容子集）；**Windows 仅通过 WSL2** 使用同一套脚本（不维护原生 PowerShell 业务逻辑）。
4. e2e 官方门禁改为单阶段 shell，并断言 link rewrite。

## 2. 已锁定决策

| 主题 | 选择 |
|---|---|
| 运行时 | A：完全替换 CLI；仅强化 fs/shell |
| Windows | WSL2 跑 bash；无原生 `.ps1` 实现 |
| 版本 | bump `0.4.1` → `0.5.0` |
| `MM_FORCE_FS` | 废弃；出现则忽略（兼容旧 `env.sh`） |
| `--register-vault` | 保留为可选（方便人用 Obsidian 打开 vault）；非运行时前置 |
| aliases | v1 **要**参与 rename 匹配（读 frontmatter `aliases`） |
| 代码块 | v1 简单跳过 fenced ` ``` `；文档标明局限 |

## 3. 非目标

- 原生 PowerShell / 官方保证 Git Bash
- 向量搜索
- 复刻 Obsidian GUI（打开文件、命令面板等）
- 保留 `mode=cli` 双路径
- 完美 Markdown AST（嵌套 fence、行内代码中的 `[[...]]` 等边角可后续加强）

## 4. 架构

### 4.1 之前

```
Agent -> memovault.sh -> cli.sh (若 app+CLI) / fs.sh (回退)
```

### 4.2 之后

```
Agent -> memovault.sh -> fs.sh (+ rewrite.sh)
         preflight: runtime=shell（或固定 mode=fs）, 无 Obsidian 探测
```

| 组件 | 职责 |
|---|---|
| `scripts/memovault.sh` | 派发；去掉 `mm_w_*` 的 cli 优先分支 |
| `scripts/lib/fs.sh` | 读写、搜索、图谱、move/rename 文件操作 |
| `scripts/lib/rewrite.sh`（新） | 扫描并改写 `[[wikilinks]]` |
| `scripts/lib/cli.sh` | **删除**（或缩成空 stub 一个版本后删除；推荐直接删） |
| `scripts/lib/classify.sh` | `promote` 只走 `mmfs_set_prop` |

### 4.3 `preflight` 输出（合同）

建议机器可读行（breaking，文档同步）：

```
runtime=shell vault=<path> search=rg|grep
source=<skill-source>
```

兼容过渡（可选，同一行额外字段）：`mode=fs forced=0` 仍打印一版，但 SKILL 以 `runtime=shell` 为准。  
**本规格选定：** 打印

```
runtime=shell mode=fs vault=... search=rg|grep forced=0
```

其中 `mode=fs` 保留一个次要版本，降低旧 stub 误读；`forced` 恒为 `0`；不再出现 `bin=` / `app=`。若需更干净，可在 `0.6.0` 再删 `mode`/`forced`。

不再：探测 `obsidian` 二进制、`pgrep`、GUI 启动风险、`MM_FORCE_FS` 短路逻辑。

## 5. Link rewrite 合同

### 5.1 触发

- `rename <ref> <New Title>`：文件改名成功后，用旧标题键集合 → 新标题 stem 做全库改写。
- `move <ref> <to>`：若 basename（标题 stem）未变，**不**改写链接；若 move 实现伴随改名则同 rename。当前 `mmfs_move` 不改 basename → v1 仅对 **rename** 强制 rewrite；move 日志改为不再说「links will NOT update」除非未来支持改名式 move。

### 5.2 旧标题键（匹配集合）

对即将改名的笔记收集：

1. 文件名 stem（sanitize 后）
2. frontmatter `title:`（若有）
3. frontmatter `aliases:` 列表中每一项

新标题：sanitize(`New Title`)，并更新目标文件 frontmatter `title:` 与（可选）保持 aliases 不变。

### 5.3 替换形态

在 vault 的 `brain/**/*.md` 与 `daily/**/*.md` 中：

| 原文 | 结果 |
|---|---|
| `[[Old]]` | `[[New]]` |
| `[[Old\|label]]` | `[[New\|label]]` |
| `[[  Old  ]]` | 归一为 `[[New]]`（允许匹配时 trim） |

不改：`[[Old/Something]]` 若整段 target 不等于旧键（精确匹配 trim 后的 link target，在 `|` 之前）。

### 5.4 代码块

维护简易状态机：处于 ` ``` ` 围栏内则不改写。不处理缩进代码块、行内 `` `[[x]]` ``（v1 可误改行内代码中的链接——文档标明；优先保证 fence）。

### 5.5 实现约束（跨平台）

- Bash 3.2；`set -uo pipefail`；不用 `set -e`
- 用 `rg -l`（若有）或 `grep -rl` 找候选文件，再逐文件 awk 改写
- **禁止**依赖 `sed -i`（GNU/BSD 分歧）；写 `mktemp` 再 `mv`
- 路径只用 `/`；依赖 `$HOME` / `$TMPDIR`
- 改写某文件失败：整体非零退出，stderr 指出路径；已 `mv` 的笔记文件不自动回滚（文档说明；可后续加事务）

### 5.6 对外日志

成功时：

```
renamed: old/path -> new/path (wikilinks updated: N files)
```

不再出现 `links NOT auto-updated in fs mode`（rename 路径）。

## 6. 跨平台

| 平台 | 状态 |
|---|---|
| macOS | 官方 |
| Linux | 官方 |
| Windows | **仅 WSL2**；README 说明在 WSL 内安装与调用；可用 `wsl ./scripts/memovault.sh ...`，但不提供业务 `.ps1` |

运行依赖：`bash`、`find`、`awk`、`grep`、`mv`、`mktemp`；推荐 `rg`。  
`jq`：仅 `--register-vault` 等可选安装步骤需要。

## 7. 安装器与 Obsidian（人用）

- 安装 / upgrade / agent 注入：**保留**
- `--register-vault`：**可选**，文案改为「若你要用 Obsidian 桌面端浏览 vault，可注册」；helper **永不**要求已注册
- `--force-fs`：写入 `MM_FORCE_FS` 可保留一版（无害），或改为 no-op 并打印废弃提示；推荐 **no-op + stderr 废弃提示**
- 删除或改写 INSTALL/CLI-REFERENCE 中「必须启用 CLI / app 必须运行」的运行时要求

## 8. e2e 变更

- `run.sh`：单阶段；删除 cli 阶段、`register.sh` 依赖、`--cli-only`
- `--fs-only`：可删除，或保留为无操作（默认即 shell）
- `05-organize.sh`：rename 后 **必须**断言源笔记正文含新标题（双模式时代常红的那条，现为官方绿条件）
- `01-preflight.sh`：断言 `runtime=shell`（或 `mode=fs` 过渡字段）与 vault 路径；删除 `forced=1` / `mode=cli` 分支
- `skills/testing-memovault/SKILL.md`：去掉「必须双模式 / Obsidian 运行」前置；官方跑 `./scripts/e2e/run.sh` 即可
- 更新 `docs/superpowers/specs/2026-08-03-e2e-testing-design.md` 或追加勘误指向本规格（推荐在本规格 §8 声明 supersede 双模式门禁）

## 9. 文档与版本触点

必须更新：

- `VERSION`、`SKILL.md` frontmatter → `0.5.0`
- `README.md` / `README_CN.md`
- `AGENTS.md`（cli/fs 叙述）
- `docs/ARCHITECTURE.md`、`INSTALL.md`、`DEVELOPMENT.md`、`CLASSIFICATION.md`（若提及 cli）
- `docs/CLI-REFERENCE.md` → 改为「可选：人用 Obsidian」附录，或大幅缩写并声明非运行时依赖
- `docs/RIPER.md` 追加条目
- adapters `_protocol.md`（若写 cli/fs）
- e2e 设计/计划/skill 如上

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 改写误伤代码块/行内代码 | fence 跳过；文档局限；e2e 覆盖常见正文 |
| rename 已 mv、rewrite 中途失败 | 明确错误；人工可 search 修复；后续可加重试 |
| 旧 agent stub 仍提 cli mode | upgrade 重注入；preflight 保留 `mode=fs` 过渡字段 |
| 用户仍期望 CLI link-safe | README 写明：shell 现为权威；Obsidian 仅浏览 |
| Windows 用户不用 WSL | 文档硬性说明；不扩展范围 |

## 11. 成功标准

- 无 Obsidian 进程、无 `obsidian` 二进制时，全命令面可用
- `rename` 后入链 `[[新标题]]` 在 e2e 中稳定 PASS
- `./scripts/e2e/run.sh` 单阶段 exit 0（在 macOS/Linux/WSL）
- 生产命名合同不变；无 emoji
- README 明确 Windows → WSL

## 12. 实现顺序（摘要）

1. 实现 `rewrite.sh` + 挂到 `mmfs_rename`；单测/e2e 断言  
2. 去掉 cli 派发与 `cli.sh`；改 `preflight`  
3. 改 e2e 为单阶段  
4. 文档与 `0.5.0`、RIPER  
5. 安装器 `--force-fs` no-op / register 文案  

（详细任务见实现计划。）
