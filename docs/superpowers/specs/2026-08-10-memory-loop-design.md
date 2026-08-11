# 设计：Memory Loop（召回增强 + 代理 L2 可观测 + daily/templates 降级）

日期：2026-08-10  
状态：已批准（2026-08-10）  
仓库：MemoVault-SKILL  
版本目标：`0.6.0`（minor；协议与主路径叙事有 breaking 语义，子命令以增量为主）

## 1. 目标

在 **bash-only、跨主流 agent** 的前提下，建成可验证的记忆飞轮：

1. **高效召回**：结构化过滤 + heat/kind 加权；任务入口优先 `recall`。
2. **可观测（L0–L2）**：库存健康 + 协议遵从 ledger + **代理型效果指标**（非人工打分）。
3. **进化**：沉淀越多 → 检索先验越强 + 策展建议越准；不自动改已安装 SKILL 源。
4. **通用性**：能力下限 = 能跑 shell + 读写本地 vault；不绑专有 hook。

产品北极星：vault 中可复用知识增加后，同类任务 **cite_rate 上升、无谓 read 不上升、inbox/raw 积压可控**。

## 2. 已锁定决策

| 主题 | 选择 |
|---|---|
| 总方案 | Loop + 代理型 L2（方案 1） |
| Daily | **C**：退出主叙事；证据用 `inbox` / `kind: raw` + `sources` |
| Templates | **A**：降级可选（Obsidian 人用）；agent 契约 = helper + CLASSIFICATION/协议 |
| 可观测一期 | **C**：L0 + L1 + L2（L2 为代理指标） |
| 进化边界 | 进化发生在 vault 内容、检索加权、health 建议；改 adapter/SKILL 需用户确认后 `upgrade` |

## 3. 非目标

- 向量 / 语义检索（仍按 `docs/DEVELOPMENT.md` 预留）
- 云端同步指标、GUI 仪表盘、人工「回答质量」评分
- 以某一家 agent 的 event hook 作为一期硬依赖
- 强制批量迁移既有 `daily/` 笔记
- 让 vault `templates/*.md` 成为 `new` 的渲染真源
- 自动无确认 `promote` / 自动改写已安装协议文件

## 4. 记忆模型

| 对象 | 角色 | 默认是否进 `recall`/`search` |
|---|---|---|
| `atom` / `scenario` / `persona` / `skill` | 可复用记忆 | 是（加权） |
| `kind: raw`（建议 `brain/inbox/`） | L0 证据，待蒸馏 | 否（`--include-raw` 可开） |
| `daily/YYYY-MM-DD` | Legacy / 人用兼容 | 否 |
| `sources` + `[[wikilinks]]` | 溯源与图（不绑日历） | — |

## 5. 架构与数据流

```text
Agent (any harness)
  -> memovault.sh
       -> recall/search  -> 过滤 + 排序 -> stdout 摘要
       -> read/new/append/distill/promote/cite
       -> 旁路追加 .memovault/ledger.log
       -> health/stats 聚合 vault + ledger
  Vault: brain/  (notes)
         .memovault/  (ledger; 不参与检索)
         daily/  (legacy only)
         templates/  (optional human Obsidian)
```

检索默认扫描 `brain/`，排除 `kind: raw`（读 frontmatter）与路径 `daily/`。

## 6. Helper 表面

### 6.1 增强 / 新增

| 命令 | 行为 |
|---|---|
| `search <q> [--domain] [--kind] [--heat] [--limit] [--include-raw]` | 全文 + 过滤；默认排除 raw 与 daily |
| `recall <q> [--limit 5]` | 过滤 → heat/kind 排序 → 稳定机器可读摘要行（path/title/kind/heat/snippet） |
| `cite "<title>"` | 追加 ledger `cite`（协议：实质采用某笔记时调用） |
| `distill "<raw-ref>" <domain> "<Title>" [--kind atom\|scenario]` | 建结构化笔记、写 `sources`、正文回链、可选 raw 指针、ledger `distill` |
| `health` / `stats` | L0 +（若有 ledger）L1/L2 代理汇总，`key=value` 少行输出 |
| `ledger:rotate`（可选一期或紧随） | 按行数/天数截断 ledger |

### 6.2 降级但保留

- `daily` / `daily:append`：兼容与人用；协议主路径不再要求；文档标 legacy。
- vault `templates/`：installer best-effort 拷贝；`--verify` 不再因缺 templates 失败。

### 6.3 排序先验（helper 内实现）

1. heat：`evergreen` > `growing` > `seedling`（缺省按 seedling）  
2. kind：`persona|skill|scenario|atom` > 无 kind > `raw`  
3. 同分：`updated` 新近优先  

### 6.4 输出约定

- 面向脚本：优先 `key=value` 或稳定 TSV；不引入 JSON 强依赖。
- bash 3.2；无 TTY 交互；失败码非零；ledger 写入失败 **不阻断** 主命令（stderr 提示）。

## 7. 可观测性

### 7.1 存储

`$AGENT_MEMO_VAULT/.memovault/ledger.log`  
- 一行一事；空格分隔 `key=value`（必含 `ts=` `event=`）  
- 不进入 `brain/`，不参与 `search`/`recall`  
- 不写用户对话原文

### 7.2 事件

| event | 触发 | 关键字段 |
|---|---|---|
| `recall` | `recall` /（可选）`search` | `q`, `hits`, `top` |
| `read` | `read` | `title` |
| `capture` | `new` / `append` | `title`, `kind`, `domain` |
| `cite` | `cite` | `title` |
| `promote` | `promote` | `title`, `from`, `to` |
| `distill` | `distill` | `from`, `to` |

### 7.3 指标

**L0（vault 扫描）**  
笔记数；按 kind/heat/domain；`orphan_pct`；`inbox_raw_count`；`legacy_daily_count`。

**L1（ledger 聚合）**  
近 N 天 recall 次数；无 recall 却 capture 的粗比例；capture 后笔记含 `sources` 或正文 wikilink 的比例。

**L2 代理**  
- `cite_rate` ≈ cite / recall(hits>0)  
- `skill_reuse`：同一 skill 笔记被 read/cite 的重复次数  
- `promote_rate`：promote 相对新笔记  
- `recapture_dup`：短窗口相似 title/tag 再次 capture  

### 7.4 协议自评

适时运行 `health`；若 inbox 积压高、`cite_rate` 低、`orphan_pct` 高，则 **建议** distill / 收窄查询 / 补链 / promote——不静默改库。

## 8. 协议与安装

- 重写 `install/adapters/_protocol.md`：更短；`recall` → 预算 `read` → 半自动 capture → inbox/distill → `cite` → 适时 `health`。  
- 删除「daily 为默认 L0」主路径叙述；daily 仅 legacy 提及。  
- Skill 体例留在协议/CLASSIFICATION；不依赖 `templates/skill.md`。  
- `install --verify`：必查 source、helper、`brain/`、注入；templates 可选。  
- `upgrade` 重注入新协议。现有 agent target 列表不变。  
- `SKILL.md`：协议与 CLI 手册分层；版本 bump 至 `0.6.0`。

## 9. 错误处理与安全

- 所有写入仍经 vault 路径解析；禁止写出 `$AGENT_MEMO_VAULT`。  
- `.memovault/` 仅在 vault 下创建。  
- 破坏性操作仍需用户确认。  
- 无 emoji。  
- ledger 损坏时 `health` 降级只报 L0，并 stderr 说明。

## 10. 测试要点

- 单元/脚本：过滤排除 raw/daily；排序顺序；`recall` 输出稳定。  
- `distill`：`sources` + 回链；raw 可选指针。  
- ledger：主命令成功且事件追加；ledger 不可写时主命令仍成功。  
- `health`：空 vault、仅 seedling、含 inbox、含 legacy daily 的快照断言。  
- e2e：更新协议相关用例；daily 改为兼容用例而非主路径门禁。  
- `install --verify`：无 templates 目录时仍可通过（若其他必查项 OK）。

## 11. 文档与 RIPER

- 更新：`SKILL.md`、`docs/CLASSIFICATION.md`、`docs/ARCHITECTURE.md`、`AGENTS.md` 表面列表、`README`/`README_CN` 中 daily/templates 表述。  
- `docs/RIPER.md` 追加本变更条目。  
- 设计稿与 RIPER 新条目默认中文（命令名/路径/标识符保持英文）。

## 12. 实现分期（建议，计划阶段可再切）

| 阶段 | 内容 |
|---|---|
| P0 | `search` 过滤 + `recall` 排序；协议改短；daily/templates 文档与 verify 降级 |
| P1 | `.memovault/ledger` + `cite` + 写路径埋点；`health` L0+L1 |
| P2 | L2 代理聚合；`distill`；health 建议话术；e2e 与 RIPER |

向量搜索不在本期。

## 13. 实现细节裁定（计划锁定）

- ledger 路径：`$AGENT_MEMO_VAULT/.memovault/ledger.log`；每行空格分隔 `key=value`（必含 `ts=` `event=`）；bash 3.2 友好，不用 JSON 解析。  
- `health` 与 `stats` 互为别名（同一实现）。  
- `recapture_dup`：规范化 title（小写、去首尾空白；无 bash 关联数组时用 `tr`/`awk`）在 7 天窗口内重复 `capture`。  
- `cite`：仅正式子命令 `cite "<title>"`（无额外别名）。  
- P0–P2 同一版本 `0.6.0` 发布。
