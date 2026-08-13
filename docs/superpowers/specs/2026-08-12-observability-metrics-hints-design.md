# 设计：可观测指标可信度 + hint（最小一包）

日期：2026-08-12  
状态：已批准（2026-08-12，对话确认方案 1 + 兼容 B + §1–§3）；2026-08-13 按审阅修订可行性（§2 决策不变）  
仓库：MemoVault-SKILL  
版本目标：`0.7.2`（patch；纯增量字段与 hint，不改主路径写库行为）  
依据：本地 vault 观测；[[Memory Loop 0.6.0 产品决策]]；[[Agent memory 前瞻调研 2026-08]]

## 1. 目标

在已有 L0–L2 可观测骨架上，做**最小一包**优化，同时覆盖：

1. **指标可信度**：解释召回是否命中、miss 后是否仍 capture、重复是否为真重复。
2. **Agent 可行动性**：用新 `hint=` 驱动收窄查询 / 补 kind 等建议（不静默改库）。
3. **效果证明**：e2e 断言新字段 + 新 hint + 现有 fixture `eval` 不回归。本包不做本机 vault 金标 `eval`（与 §11 手工冒烟不是同一件事）。

产品信号对齐：协议「调过 recall」不等于「召回有用」；应用 `recall_hit_rate` 等新字段纠正虚高 `cite_rate` 叙事。

## 2. 已锁定决策

| 主题 | 选择 |
|---|---|
| 范围切法 | 方案 1：Metrics + Hints（非 Live Eval、非仅补丁） |
| 兼容策略 | **B**：保留旧字段公式；并列新字段；旧字段文档标 deprecated |
| 版本 | `0.7.2` patch |
| `suggest` 启发式 | 本包**不改**阈值 |
| 本机 vault eval | **不做**（下一包） |

`0.7.2` 标 patch 的理由：不改旧字段公式、不改写库主路径、不加子命令。仍有 agent 可见增量（新 health 键、新 `hint=`、新 ledger `event=search`、协议话术）。已安装 agent 必须 `upgrade` 后才会吃到 `_protocol.md` 新话术；helper 本身随源码更新即可打出新字段。

## 3. 非目标

- 本机 vault 金标 `eval` / GUI / 向量检索 / 云端指标
- 改旧 `cite_rate`、`recapture_dup` 计算公式
- 改现有 hint 的触发条件（含 `low_cite_rate`）
- 为「整窗零 recall 仍 capture」新增 hint（继续看现有 `capture_without_recall_7d`）
- 自动 promote / 自动补 `kind` / 自动补链
- 为 `search` 记录 `top=` 或完整对话原文
- 改 `search` stdout 格式（仍为 rg/grep 行；`hits` 在 ledger 内按去重笔记计数，见 §6）
- 改各家 adapter 模板结构（协议真源仍为 `_protocol.md`；需用户 `upgrade`）

## 4. 兼容与废弃

| 字段 / hint | 行为 |
|---|---|
| `cite_rate` | 保留旧公式 `100 * cite_7d / recall_hits_7d`（整数除法）；文档与协议标 deprecated；建议改看 `recall_hit_rate` + `cite_7d` |
| `recapture_dup` | 保留旧行为（含 `op=append` 污染）；文档标 deprecated；建议改看 `recapture_new_dup` |
| `low_cite_rate` | **现网条件与公式不动**（仍用旧 `cite_rate`）。协议将其视为遗留 hint：若同时出现本包新 hint，优先响应新 hint；若只有 `low_cite_rate`，不作为本包行动依据，改看 `recall_hit_rate` + `cite_7d` |
| 新字段 / 新 hint | 并列输出；**新 `hint=` 与协议优先依据新字段** |

不加与 `cite_rate` 同值的第三比率字段，避免命名污染。本包**打印**已经算过的 `recall_hits_7d`（计数，不是比率），以便审计旧 `cite_rate` 分母。

比率一律整数除法，与现网 `cite_rate` 一致（例：`2/5 = 40`）。阈值比较按整数结果，不引入浮点。

## 5. 新增 health 字段

窗口：与现有 L1 一致，沿用 `mm_obs_days_ago 7` 的现网边界（`ts` 日期部分 `>=` 该日；含当天）。不在本包纠正「7 日」与含端点日历日数是否差一天。

L0 新字段（扫 vault，无 7 日窗口）：

| 字段 | 定义 | 无数据时 |
|---|---|---|
| `kind_other_pct` | `100 * kind_other / notes_total`（整数除法）。分母分子与现网 `kind_other=` / `notes_total=` 同一扫描：缺 `kind` 与非法 `kind` 都计入 `kind_other` | 无笔记 → `-1` |

L1 / L2 新字段（ledger，近窗）：

| 字段 | 层 | 定义 | 无数据时 |
|---|---|---|---|
| `search_7d` | L1 | 近窗 `event=search` 条数 | `0` |
| `recall_hits_7d` | L1 | 近窗 `event=recall` 且 `hits>0` 的条数（现仅内部用于 `cite_rate`，本包打印） | `0` |
| `recall_hit_rate` | L2 | `100 * recall_hits_7d / recall_7d` | 无 recall → `-1` |
| `capture_after_miss_7d` | L1 | 见 §5.1 | `0` |
| `cite_7d` | L1 | 近窗 `event=cite` 条数（现仅内部计算，本包打印） | `0` |
| `recapture_new_dup` | L2 | 近窗内同一规范化 title 的 `event=capture` 且 `op=new` 出现 ≥2 的 **title 个数**（每种 title 计 1，与现网 `recapture_dup` 的「title 个数」计法一致，但只认 `op=new`） | `0` |

`search_7d` 本包**不**配 hint。解读：与 `recall_7d` 并列，看 agent 是在走协议主路径 `recall`，还是频繁落到 `search`。不据此自动改库。

「整窗一次 recall 都没有、但仍有 capture」继续用现有 `capture_without_recall_7d`。该场景下 `capture_after_miss_7d` 为 `0`（没有 miss 日），本包不新增 hint。

### 5.1 `capture_after_miss_7d` 口径

按 **UTC 日**（ledger `ts=` 的 `YYYY-MM-DD`）：

- 若某日至少一次 `event=recall` 且 `hits=0`，则该日所有 `event=capture` 计入总和。
- 不要求严格时间序配对（避免 bash 状态机）；不按 title 去重。

已知偏差（本包接受，不修）：同一 UTC 日只要出现过一次 miss，当天 hit 前后的 capture 全部计入。hint 阈值 `>= 3` 因此可能在「一次试探 miss + 当天多次已确认 new」时误触发。e2e 只断言计数口径，不把「误触发」当失败。

### 5.2 输出位置

旧键相对顺序与公式不变。插入 / 追加规则：

1. 在现有 `kind_other=` **之后**插入 `kind_other_pct=`（L0，避免被读成 7 日指标）。
2. 在现有 `recapture_dup=` **之后**、现有 hint 行**之前**，按此顺序追加：`search_7d=`、`recall_hits_7d=`、`recall_hit_rate=`、`capture_after_miss_7d=`、`cite_7d=`、`recapture_new_dup=`。
3. 现有四条 hint 仍按现网顺序输出；本包三条新 hint 接在它们后面，顺序：`low_recall_hit_rate`、`capture_after_miss`、`high_kind_other`（仅输出满足条件的行）。

## 6. Ledger 埋点

| 事件 | 触发 | 字段 |
|---|---|---|
| `search`（新） | 公开子命令 `search` **成功返回**时恰好一条 | `event=search q=<tok> hits=N` |
| 既有事件 | 不变 | 不变 |

覆盖 0.6.0 设计里「`recall` 事件可选覆盖 search」：本包起 search 用独立 `event=search`，`event=recall` 仍只由 `recall` 子命令写。

### 6.1 谁写、谁不写

- **写**：`scripts/memovault.sh` 的 `search)` 派发所到达的那一次检索。推荐：公开入口设 `MM_SEARCH_OBS=1`（或等价内部标记）再调 `mmfs_search`；未设标记则不写 ledger。
- **不写**：`mmfs_dedupe` 内部调用的 `mmfs_search`（必须显式不带该标记）。其它内部调用同理。
- **不写**：`search` 因用法错误 `mm_die`（空 query 等）而未成功返回。

禁止把 `mm_obs_log event=search` 无条件放进 `mmfs_search` 共享路径——否则 `dedupe` 会污染 `search_7d`。

### 6.2 `hits` 与空结果

- `hits` = 通过现网过滤后的**去重笔记文件数**（unique `$MM_VAULT`-相对 `.md` 路径），不是 rg/grep 匹配行数。与 `recall` 的「笔记条数」对齐；**不**改变 `search` 的 stdout（仍可能一行一处匹配）。
- 下列成功返回都必须记账，且 `hits=0`：无 `brain/`、rg/grep 零命中、有匹配但过滤后零笔记。实现须覆盖 `mmfs_search` 的早退路径，不能只在函数尾部记一次。
- `q` token 化与 `recall` 一致：空格 → `_`。query 含 `=` 会破坏 `key=value` 行，属既有债，本包不修。
- ledger 写入失败不阻断主命令（与现网 `mm_obs_log` 一致）。
- 不为 `search` 写 `top=`。

## 7. hint 规则

保留现有（条件不动）：`distill_inbox`、`low_cite_rate`、`high_orphan_pct`、`low_provenance`。

新增：

| hint | 条件 |
|---|---|
| `low_recall_hit_rate` | `recall_7d >= 5` 且 `0 <= recall_hit_rate < 40` |
| `capture_after_miss` | `capture_after_miss_7d >= 3` |
| `high_kind_other` | `notes_total >= 10` 且 `kind_other_pct >= 40` |

`recall_hit_rate=-1` 或 `kind_other_pct=-1` 不得触发对应新 hint（比较式已排除）。

多条 hint 可同时输出。仍不自动改库。

## 8. 协议行为（文档级）

改 `install/adapters/_protocol.md` 与 `SKILL.md` 的 Health / 指标解读段落（`SKILL.md` **没有**独立字段表；改 Health 段与 §10 Out of scope 里那句 proxy 列举）。不改各家 adapter 文件骨架。

- 适时 `health` 时**优先响应本包新 hint**（均需用户确认后执行）：
  - `low_recall_hit_rate` → 收窄 recall 词后再召。
  - `capture_after_miss` → miss 后先 `search` / `dedupe` 再 capture。
  - `high_kind_other` → 为**缺 kind** 的笔记补 `kind`；若是非法 kind，改为合法枚举值。不要把「缺」和「非法」当成两种 hint。
- 指标解读优先：`recall_hit_rate`、`recall_hits_7d`、`cite_7d`、`recapture_new_dup`、`kind_other_pct`；`search_7d` 仅作对照（见 §5）。
- 明确 `cite_rate`、`recapture_dup` 为 deprecated。
- 明确 `hint=low_cite_rate` 为遗留：有新 hint 时忽略它；单独出现时不按其行动。

`suggest` 子命令阈值本包不动。

## 9. 错误与安全

- 无 ledger 或不可读：L0 仍输出；新计数类为 `0`；`recall_hit_rate` / `kind_other_pct` 在无分母时为 `-1`（对齐现网 `cite_rate=-1`）。现网不可读时仍打印 L1/L2 默认值，本包沿用，不改为「省略键」。
- 写入仍限制在 `$AGENT_MEMO_VAULT`；无 emoji；bash 3.2；`set -uo pipefail` 惯例不变。

## 10. 文档与版本

| 文件 | 改动 |
|---|---|
| `scripts/lib/obs.sh` | 聚合新字段、新 hint、输出顺序 |
| `scripts/lib/fs.sh` + `scripts/memovault.sh` | 仅公开 `search` 子命令成功返回时 `mm_obs_log`；`dedupe` 内部检索不记；空结果 `hits=0` |
| `scripts/e2e/suites/06-obs.sh` | 本包断言（真命令优先） |
| `scripts/e2e/suites/07-acceptance.sh` | 已多次调 `search`：允许 ledger 多 `event=search`。本包**不必**改断言，除非现有断言被新输出打断（不应发生：现为 `assert_contains`） |
| `install/adapters/_protocol.md` | Health / deprecated / 遗留 `low_cite_rate` |
| `SKILL.md` | Health 段 + Out of scope 的 proxy 列举；同步 deprecated 与新字段名 |
| `docs/ARCHITECTURE.md` | ledger event 表增加 `search`；health 新键；写明 search 不再挂在 `event=recall` 上 |
| `README_CN.md` / `README.md`（对等一句） | 可观测一行 |
| `docs/RIPER.md` | 本变更条目 |
| `VERSION` | `0.7.1` → `0.7.2` |

不改：`docs/CLI-REFERENCE.md`（人用 Obsidian CLI，不含 helper health）、`AGENTS.md` 表面列表（无新子命令）。

## 11. 测试要点

优先真命令；只有「同域同 title 第二次 `new`」这种被 helper 拒绝的路径才允许改 ledger 夹具。同 title 真重复 `op=new` 的合法构造：`new <domain-a> "<Title>"` 再 `new <domain-b> "<Title>"`（不同 domain，文件不冲突）。

`06-obs.sh`（或同套件新增用例）必须覆盖：

1. 公开 `search` 成功后 ledger 含恰好对应条数的 `event=search`；`hits=` 为去重笔记数。
2. 零命中 `search`（独特 token）仍写 `event=search` 且 `hits=0`。
3. 只跑 `dedupe`（不跑 `search` 子命令）不产生 `event=search`。
4. `health` 含全部新键：`kind_other_pct`、`search_7d`、`recall_hits_7d`、`recall_hit_rate`、`capture_after_miss_7d`、`cite_7d`、`recapture_new_dup`。
5. 旧键仍在且相对顺序不变：`cite_rate=`、`recapture_dup=` 仍在新键块之前。
6. 一次 `hits=0` 的 recall + 同日至少一次 capture → `capture_after_miss_7d >= 1`。
7. 两 domain 同 title 两次 `new` → `recapture_new_dup >= 1`。
8. 同一 title 两次 `append`（无第二次 `op=new`）→ `recapture_dup >= 1` 且 `recapture_new_dup` 不因此增加。
9. 空 vault / 无 recall：`kind_other_pct=-1` 或 `recall_hit_rate=-1` 至少覆盖无 recall 的 `-1`（可在独立空窗用例，或断言未做 recall 前 `recall_hit_rate=-1`）。
10. 新 hint 真命令回归（不要绑本机真实 vault）：
    - `low_recall_hit_rate`：≥5 次零命中 recall → 该 hint 出现。
    - `capture_after_miss`：同日 1 次 miss recall + ≥3 次 capture → 该 hint 出现。
    - `high_kind_other`：≥10 条无 `--kind` 的笔记且占比 ≥40% → 该 hint 出现。
11. 现有 fixture `eval` / forward 套件不回归。`07-acceptance.sh` 不强制改。

### 验收（手工冒烟，可选）

在开发机跑一次 `health`，确认新键出现、旧 `cite_rate` / `recapture_dup` 与改前同公式。hint 以 e2e 为准；本机真实 vault 状态不作为门禁。

## 12. 实现分期

单 patch 一次交付；无 P0/P1 再切。实现计划：`docs/superpowers/plans/2026-08-13-observability-metrics-hints.md`（须用户批准后再 Execute）。计划须按本节口径写步骤，不得把 `event=search` 无条件写进共享 `mmfs_search`。
