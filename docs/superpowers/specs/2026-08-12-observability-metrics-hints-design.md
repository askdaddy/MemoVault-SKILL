# 设计：可观测指标可信度 + hint（最小一包）

日期：2026-08-12  
状态：已批准（2026-08-12，对话确认方案 1 + 兼容 B + §1–§3）  
仓库：MemoVault-SKILL  
版本目标：`0.7.2`（patch；纯增量字段与 hint，不改主路径写库行为）  
依据：本地 vault 观测；[[Memory Loop 0.6.0 产品决策]]；[[Agent memory 前瞻调研 2026-08]]

## 1. 目标

在已有 L0–L2 可观测骨架上，做**最小一包**优化，同时覆盖：

1. **指标可信度**：解释召回是否命中、miss 后是否仍 capture、重复是否为真重复。
2. **Agent 可行动性**：用新 `hint=` 驱动收窄查询 / 补 kind 等建议（不静默改库）。
3. **效果证明**：e2e 断言新字段 + 现有 fixture `eval` 不回归（本包不做本机 vault 金标评测）。

产品信号对齐：协议「调过 recall」不等于「召回有用」；应用 `recall_hit_rate` 等新字段纠正虚高 `cite_rate` 叙事。

## 2. 已锁定决策

| 主题 | 选择 |
|---|---|
| 范围切法 | 方案 1：Metrics + Hints（非 Live Eval、非仅补丁） |
| 兼容策略 | **B**：保留旧字段公式；并列新字段；旧字段文档标 deprecated |
| 版本 | `0.7.2` patch |
| `suggest` 启发式 | 本包**不改**阈值 |
| 本机 vault eval | **不做**（下一包） |

## 3. 非目标

- 本机 vault 金标 `eval` / GUI / 向量检索 / 云端指标
- 改旧 `cite_rate`、`recapture_dup` 计算公式
- 自动 promote / 自动补 `kind` / 自动补链
- 为 `search` 记录 `top=` 或完整对话原文
- 改各家 adapter 模板结构（协议真源仍为 `_protocol.md`；需用户 `upgrade`）

## 4. 兼容与废弃

| 字段 | 行为 |
|---|---|
| `cite_rate` | 保留旧公式 `100 * cite_7d / recall_hits_7d`；文档与协议标 deprecated；建议改看 `recall_hit_rate` + `cite_7d` |
| `recapture_dup` | 保留旧行为（含 `op=append` 污染）；文档标 deprecated；建议改看 `recapture_new_dup` |
| 新字段 | 并列输出；**新 `hint=` 与协议优先依据新字段** |

不加与 `cite_rate` 同值的第三比率字段，避免命名污染。

## 5. 新增 health 字段

窗口：与现有 L1 一致，**近 7 个 UTC 日**（`mm_obs_days_ago 7`）。

| 字段 | 定义 | 无数据时 |
|---|---|---|
| `search_7d` | ledger 中 `event=search` 条数 | `0` |
| `recall_hit_rate` | `100 * count(recall hits>0) / recall_7d` | 无 recall → `-1` |
| `capture_after_miss_7d` | 见下节口径 | `0` |
| `cite_7d` | 近 7 天 `event=cite` 条数（现仅内部计算，本包打印） | `0` |
| `recapture_new_dup` | 7d 内同一规范化 title 的 `capture` 且 `op=new` 出现 ≥2 的 **title 个数** | `0` |
| `kind_other_pct` | `100 * kind_other / notes_total` | 无笔记 → `-1` |

### 5.1 `capture_after_miss_7d` 口径

按 **UTC 日**（`ts` 的 `YYYY-MM-DD`）：

- 若某日至少一次 `event=recall` 且 `hits=0`，则该日所有 `event=capture` 计入总和。
- 不要求严格时间序配对（避免 bash 状态机）；不按 title 去重。

### 5.2 输出位置

插在现有 `recall_7d` / `capture_7d` / L2 块附近，追加上述键；**旧键顺序与公式不变**。

## 6. Ledger 埋点

| 事件 | 触发 | 字段 |
|---|---|---|
| `search`（新） | `search` 子命令正常结束时 | `event=search q=<tok> hits=N` |
| 既有事件 | 不变 | 不变 |

- `q` token 化与 `recall` 一致（空格 → `_`）。
- ledger 写入失败不阻断主命令（与现网 `mm_obs_log` 一致）。
- 不为 `search` 写 `top=`。

## 7. hint 规则

保留现有：`distill_inbox`、`low_cite_rate`、`high_orphan_pct`、`low_provenance`。

新增：

| hint | 条件 |
|---|---|
| `low_recall_hit_rate` | `recall_7d >= 5` 且 `0 <= recall_hit_rate < 40` |
| `capture_after_miss` | `capture_after_miss_7d >= 3` |
| `high_kind_other` | `notes_total >= 10` 且 `kind_other_pct >= 40` |

多条 hint 可同时输出。仍不自动改库。

## 8. 协议行为（文档级）

`install/adapters/_protocol.md` / `SKILL.md` Health 段：

- 适时 `health` 时优先响应新 hint：收窄 recall 词、miss 后先 `search`/`dedupe` 再 capture、为无 kind 笔记补 `kind`（均需用户确认后执行）。
- 指标解读优先：`recall_hit_rate`、`cite_7d`、`recapture_new_dup`、`kind_other_pct`。
- 明确 `cite_rate`、`recapture_dup` 为 deprecated。

`suggest` 子命令阈值本包不动。

## 9. 错误与安全

- 无 ledger 或不可读：L0 仍输出；新计数类为 `0`；`recall_hit_rate` / `kind_other_pct` 在无分母时为 `-1`（对齐现网 `cite_rate=-1` 风格）。
- 写入仍限制在 `$AGENT_MEMO_VAULT`；无 emoji；bash 3.2；`set -uo pipefail` 惯例不变。

## 10. 文档与版本

| 文件 | 改动 |
|---|---|
| `scripts/lib/obs.sh` | 聚合新字段、新 hint |
| `scripts/lib/fs.sh`（search 路径） | `search` 结束 `mm_obs_log` |
| `scripts/e2e/suites/06-obs.sh` | 断言 |
| `install/adapters/_protocol.md` | Health / deprecated |
| `SKILL.md` | 字段表同步 |
| `docs/ARCHITECTURE.md` | ledger `search` + health 字段 |
| `README_CN.md` / `README.md`（对等一句） | 可观测一行 |
| `docs/RIPER.md` | 本变更条目 |
| `VERSION` | `0.7.1` → `0.7.2` |

## 11. 测试要点

1. `search` 后 ledger 含 `event=search`。
2. `health` 含全部新键：`search_7d`、`recall_hit_rate`、`capture_after_miss_7d`、`cite_7d`、`recapture_new_dup`、`kind_other_pct`。
3. e2e vault：一次 `hits=0` 的 recall + 同日 capture → `capture_after_miss_7d >= 1`。
4. 尽可能用真命令构造 `recapture_new_dup`；否则用可控 ledger 夹具（优先真命令）。
5. 旧字段仍存在：`cite_rate=`、`recapture_dup=`。
6. 现有 fixture `eval` / forward 套件不回归。

### 验收（真实 vault，手工）

- `health` 可见新字段；在当前多 miss / 多无 kind 状态下，阈值满足时应出现 `low_recall_hit_rate` 和/或 `high_kind_other`。
- `cite_rate` / `recapture_dup` 与改前同公式一致。

## 12. 实现分期

单 patch 一次交付；无 P0/P1 再切。Execute 前须另有经批准的 `docs/superpowers/plans/` 实现计划（SDD-RIPER）。
