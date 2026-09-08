# 设计：本地 CLI snippet 库（pet 语义，bash 原生）

日期：2026-09-04
仓库：MemoVault-SKILL
版本目标：`0.9.0`（minor：新子命令 + 新 `kind`）
状态：已批准（2026-09-04；方案 B；v1 从一开始锁定 CLI / pet 语义）
参考：https://github.com/knqyf263/pet

## 1. 目标

让 coding agent 把**可复用的 CLI / 脚本命令**沉到 vault 里，用非交互命令按描述、标签、正文检索，并把 **command 原文**打到 stdout。人类可在 Obsidian 打开同一批 markdown。数据模型对齐 pet（description + command + tags + `<param=default>`），实现不依赖 pet 二进制。

产品边界一句话：MemoVault 继续是知识库；snippet 是平行的命令抽屉，默认不进开场 `recall`。

## 2. 已锁定决策

| 主题 | 选择 |
|---|---|
| 总方案 | **B**：bash 原生，pet 启发，vault 内，非交互 |
| 片段类型 | **CLI / 脚本命令**（pet 语义）。不是通用语言代码库 |
| Runtime | 不包装 pet；不要求 fzf / peco / Go |
| 存储 | 一篇 snippet 一个 markdown；`$VAULT/brain/snippets/<Title>.md` |
| 唯一键 | `title` = pet 的 description；与 `mmfs_find_note` 相同，整个 vault 的文件名 stem 唯一 |
| 参数 | 存储并展开 `<name>` 与 `<name=default>` |
| 执行 | helper **永不** `exec` 存储的命令 |
| 默认识别 | `recall` / `search` 默认排除 `kind: snippet` |
| 人类 pet 互操作 | v1 不写 TOML、不读 `~/.config/pet`、不做 gist/gitlab sync |

## 3. 非目标（v1）

- 包装或探测 `pet` 二进制
- fzf / peco、交互 `new` / `search`
- `exec` / `clip` / 打开编辑器
- GitHub Gist / GitLab / 任意云同步
- 从 `~/.config/pet/snippet.toml` 导入，或导出 pet TOML
- 通用语言 snippet（Python 函数、SQL、VS Code 片段）
- pet 列表默认值语法 `<name=\|_a_\|\|_b_\|>` 的选项 UI（字符串原样存储；`--set` 可整段替换）
- `recall --include-snippet`（v1 只走 `snip search`）
- 向量检索
- 改 `use_rate` 等既有效应公式

## 4. 数据模型

### 4.1 路径与 kind

- 规范家：`brain/snippets/`，`domain: snippets`，`kind: snippet`
- `snip new` **只**写这个目录
- 默认 heat：`growing`（与 `skill` 相同：拿来就能用）
- 通用 `new <domain> "<title>" --kind snippet` 必须被 kind 枚举接受（否则会进 `kind_other`），heat 同样 `growing`。协议要求 agent 用 `snip new`，不要用通用 `new` 建 snippet
- `snip list` / `snip search` 按 **`kind: snippet`** 扫整个 `brain/`，不限文件夹
- `snip get` 按 title 做 `mmfs_locate`，再校验 `kind: snippet`

`kind` 合法值变为：`raw` | `atom` | `scenario` | `persona` | `skill` | `snippet`。

### 4.2 文件形状

`snip new` 自己写文件，**不**走 `mmfs_new` 的 `# Title` 标题（避免污染 command 抽取）。不写 `status:`（省略 = `active`，与现有 `new` 一致）。

文件内容形状：YAML frontmatter（无 `status:`），空行，然后一个 language=`bash` 的 fenced code block，内部是 command。示例 command：

`echo | openssl s_client -connect <host=example.com>:443 2>/dev/null | openssl x509 -dates -noout`

规则：

- frontmatter 键恰好为：`title` `domain` `kind` `tags` `heat` `aliases` `sources` `created` `updated`（无 `status`）
- `title` 经现有 `mmfs_sanitize_title`（去 `/` 与 `:`）
- 正文第一块 fenced code 就是 command。`snip new` 写入时 language 标 `bash`
- fence 之后允许可选 `Related:` 行或 `[[wikilinks]]`；`snip get` 忽略它们
- 无 emoji；正文就是要跑的命令，不是 SOP（SOP 仍用 `kind: skill`）

### 4.3 Command 抽取（`get` / `list` / `search` 共用）

对一篇笔记去掉 YAML frontmatter 之后：

1. 若存在 fenced code block（行以三个反引号开头、直到下一组三个反引号），取**第一块**的内部文本，去掉首尾换行
2. 否则取剩余正文：丢掉 `^#` 标题行，在 `^Related:` 或 `^## ` 处截断，trim

抽到空字符串视为损坏：`get` 非零退出；`list`/`search` 仍打印该行但 `command=` 为空。

### 4.4 参数语法（pet 子集）

Token 形如 `<name>` 或 `<name=default>`。`name` 是第一个 `=` 之前的部分；`default` 是第一个 `=` 之后、闭合 `>` 之前的部分（可含空格）。不解析嵌套 `>`。

`snip get` 展开规则，按 token 从左到右：

1. 若有 `--set name=value` 且 name 匹配：整段 `<...>` 换成 value（最后一次 `--set` 胜出）
2. 否则若 token 含 `=`：换成 default
3. 否则原样保留 `<name>`

未匹配的 `--set` 忽略，不报错。v1 不实现交互提问。

## 5. Helper 表面

新库 `scripts/lib/snip.sh`，由 `scripts/memovault.sh` source。子命令 `snip`，别名 `snippet`。无子命令时打印 usage 到 stdout，退出 0。

```text
snip new "<description>" --command "..." [--tags a,b]
snip list [--tag t] [--limit N]
snip search "<query>" [--tag t] [--limit N]
snip get "<description>" [--set name=value ...]
snip rm "<description>" --yes
```

`--command` 必填且 trim 后非空。不设 `--body` 别名（避免和 `new --body` 混淆）。未知 flag 非零退出。

### 5.1 stdout

| 命令 | stdout |
|---|---|
| `new` | 一行：`path=brain/snippets/<file>.md title=<title>` |
| `list` / `search` | 每条一行：`title=<t> tags=<a,b> command=<单行>` |
| `get` | **只有**展开后的 command（可多行）。没有 `key=value` 前缀 |
| `rm` 无 `--yes` | stdout 一行 `path=... title=...`；stderr 说明需要 `--yes`；退出 2 |
| `rm --yes` | 一行：`deleted=1 path=... title=...` |

`list`/`search` 的 `command=` 必须是行内最后一个字段（值可含空格）。换行打成两位字符 `\` + `n`；tab 换成空格。`tags=` 为逗号连接、无空格；无标签则为 `tags=`。

`list`/`search` 无默认 limit；`--limit N` 为非负整数，0 表示不输出条目但仍退出 0。

### 5.2 语义

- **new**：sanitize 后的 title 若 `mmfs_find_note` 已命中（任意 domain / daily），非零退出，stderr 带已有路径，不覆盖。写 ledger `event=snip op=new title=...`
- **list**：所有 `kind: snippet` 且 `status` 不是 `superseded`，按 title 字节序排序。`--tag t` 为 YAML tags 里的精确 token 匹配
- **search**：在未 superseded 的 snippet 的 title、tags、正文上做固定字符串匹配（优先 `rg -F`，否则 `grep -F`）。query 是一个字面串，不拆词。同样支持 `--tag` / `--limit`。无命中：stdout 空，退出 0。ledger `event=snip op=search q=... hits=N`
- **get**：按 title `mmfs_locate`；找不到或 `kind` 不是 `snippet` 则非零。允许 get 已 superseded 的条目（显式 title）。ledger `event=snip op=get title=...`
- **rm**：只删一篇。无 `--yes` 不删文件。有 `--yes` 则 `unlink`。禁止通配 / 批量。ledger `event=snip op=rm title=...`

helper **不得**把 command 交给 `sh` / `bash` / `eval`。

### 5.3 与现有子命令的关系

`mmfs_search_file_ok` 增加 snippet 过滤，与 raw 并列：

- 默认：`kind: snippet` 排除（和 `kind: raw` 一样）
- `--include-snippet`：放行
- `--kind snippet`：**隐含** include（否则 `--kind snippet` 恒为空）。这是刻意比今天的 `--kind raw`（仍要 `--include-raw`）更可用
- `recall`：v1 无新 flag，始终排除 `kind: snippet`（以及现有 raw / MOC / superseded）
- `mmfs_kind_score`：`snippet` 与 `raw` 同为 `0`（防御；默认 recall 已排除）
- `read` / `rename` / `move` / `promote` / `cite` / `backlinks` 对 snippet 文件照常工作
- `dedupe` 不改；`snip new` 只做 title 精确冲突

`search --kind snippet` 的 e2e 必须覆盖；现有 `--kind skill` 用例不得回归。

## 6. health / ledger

`health` / `stats` 在 `kind_skill=` 之后增加 `kind_snippet=`。`kind_other` **不含** `snippet`。

不改 `use_rate`、`cite_rate`、`recall_hit_rate`、`kind_other_pct` 公式。不增加 snippet 专用 hint。

ledger 新事件 `event=snip`，字段 `op=new|get|search|rm` 与 `title=`（search 另有 `q=` `hits=`）。现有事件解析必须忽略未知 event（今天已是如此）。

## 7. 协议（SKILL.md + `_protocol.md`）

开场 `recall` 仍然只找知识笔记。新增一小节 **CLI snippets**（放在 Skill capture 之后）：

- 用户说「记这个命令」/「存成 snippet」/「这段以后要用」/「pet 一下」/「save this command」/「snippet this」/「remember this command」→ 直接 `snip new`，然后确认 title 与 command
- 本回合产生了**非平凡、可再跑**的 CLI（含 flags、管道、占位符），且用户以后会再找 → 先提议 `snip new "<desc>"`，确认后再写
- 不要把一次性调试命令、密钥、机器特定路径（除非做成 `<param>`）存进去
- 取用：`snip search` 或 `snip list`，再 `snip get`。真正影响回答时 `cite "<title>"`
- 新建前先 `snip search` / `snip list`，避免重复 description
- SOP 用 `kind: skill`；**一条可粘贴的命令**用 `kind: snippet`

`SKILL.md` description / 触发语可加 snippet 相关短语。kind 枚举、Commands 表、Hard rules 里的 kind 列表一并更新。

已安装 agent 必须 `upgrade` 后才吃到 `_protocol.md`。

## 8. 文件

| 动作 | 文件 | 职责 |
|---|---|---|
| 新增 | `scripts/lib/snip.sh` | snip CRUD、抽取、参数展开 |
| 新增 | `scripts/e2e/suites/10-snip.sh` | 本包断言 |
| 改 | `scripts/memovault.sh` | source `snip.sh`；dispatch `snip`/`snippet`；usage |
| 改 | `scripts/lib/fs.sh` | kind 枚举；`new --kind snippet` heat=growing；search/recall 排除；`--include-snippet`；`--kind snippet` 隐含 include；`kind_score` |
| 改 | `scripts/lib/obs.sh` | `kind_snippet=` |
| 改 | `scripts/e2e/run.sh` | suite 列表加入 `10-snip` |
| 改 | `SKILL.md` | 命令、kind、协议、description |
| 改 | `install/adapters/_protocol.md` | 协议小节 + kind 列表 |
| 改 | `AGENTS.md` | 表面列表、kind、health 键一句 |
| 改 | `docs/ARCHITECTURE.md` | 层图、映射表、data flow |
| 改 | `docs/CLASSIFICATION.md` | kind 表 |
| 改 | `docs/DEVELOPMENT.md` | 新库指针 |
| 改 | `README.md` / `README_CN.md` | kind 列表 |
| 改 | `CHANGELOG.md` / `VERSION` | `0.9.0` |
| 改 | `docs/RIPER.md` | Execute 时追加条目 |

不改各家 adapter 骨架。不改 `eval` fixture（不往金标库塞 snippet）。

## 9. 约束（全局）

- bash 3.2：`set -uo pipefail`；helper 内不用 `set -e`；无关联数组、`${v,,}`、`mapfile`
- 所有写入经现有路径解析，不得写出 `$AGENT_MEMO_VAULT`
- 无 emoji
- 用户可见字符串与注释用英文（本 spec 是设计记录，中文）
- 日期 ISO 8601

## 10. 验收

`scripts/e2e/suites/10-snip.sh`（孤立 vault）至少：

1. `snip new` 写出 `kind: snippet`、`domain: snippets`、`heat: growing`、fence 内 command
2. 重复 title 失败，文件不被覆盖
3. `list` / `search` 打出 `title=` `tags=` `command=`
4. `search` 能命中 command 正文里的字面串
5. `--tag` 过滤
6. `get` 只打 command；`--set host=example.org` 替换 `<host=example.com>`
7. 无 `--set` 时 `<host=example.com>` 展开成 `example.com`；无 default 的 `<path>` 保留原样
8. 默认 `recall` / `search` 看不到该 command 字面串
9. `search --include-snippet` 与 `search --kind snippet` 能看到
10. `health` 含 `kind_snippet=`；该笔记不增加 `kind_other`
11. `rm` 无 `--yes` 退出 2 且文件仍在；`--yes` 后文件消失
12. 空 `--command` 非零
13. `grep -E 'eval |sh -c|bash -c' scripts/lib/snip.sh` 无匹配（禁止 helper 执行存储的 command）。测试只断言 `get` 的 stdout 文本，不 exec 它

现有 `01`–`09` suite 与 `bash -n scripts/lib/*.sh` 不回归。

## 11. 版本与升级

- `VERSION`：`0.8.0` → `0.9.0`
- CHANGELOG：`## [0.9.0] - 2026-09-04`（Execute 当天日期）Added：`snip` 子命令、`kind: snippet`、search/recall 默认排除、`kind_snippet`
- 已安装副本：`upgrade` 后协议才出现；helper 若已指向开发树则立即有命令

## 12. 明确不在本期改的相邻债

- 今天 `search --kind raw` 仍需 `--include-raw` 才看得到 raw。本期不顺手改 raw，只让 snippet 的 `--kind snippet` 隐含 include
- 待批的 0.8.1 health-honesty spec 不并入本包
