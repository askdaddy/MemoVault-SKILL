# 设计：自检报告驱动的 0.8.1（诚实口径 + 使用 hint）

日期：2026-09-01
依据：`docs/health-reports/2026-09-01T01-56-50Z.md`
版本目标：建议 `0.8.1`（patch：不改 recall 语义；不改 `use_rate` 公式）
状态：待用户批准后再写 implementation plan

## 1. Research（现网事实）

0.8.0 已把检索做对：labeled 命中 94%（18/19），上一窗 hit_rate 0。`use_rate` 连续三次 snap 都是 10，cite 闭环没跟上。

| 报告项 | 事实 | 技能代码能做什么 | 不能靠代码单独解决 |
|---|---|---|---|
| P0 `use_rate=10` | 37 recall / 4 cite；仪式性开场 recall 抬高分母 | 让 hint 在「有 cite 但仍很低」时也会响；协议强调 cite | agent 不 cite，数字不会自己变好 |
| P0 `hint=low_use` 未触发 | 条件是 `hits>=5` 且 `cite_7d=0` | 放宽为看 `use_rate` | 同上 |
| P1 `capture_after_miss=4` | hint 已触发 | 协议已写；`new` 时再警告收益低、易吵 | 行为仍在 agent |
| P2 内容 evergreen=0 | `heat_evergreen=13` 全是 MOC | 打印 `heat_evergreen_content` | promote 要用户确认，改的是 vault |
| P2 `kind_other=13` | 全是 MOC | 打印不含 MOC 的 other / orphan | 给 MOC 加 kind 会改 vault 与 moc 模板 |
| P2 engineering=17 | 最大域 | 无（health 已有 `domain_*`） | 拆域是 vault 迁移 |
| P3 nunk 18/37 | 升级前 ledger | 等窗滚出；可选打印 `labeled_hit_rate` 免手算 | 不要改历史 ledger |
| P3 1 篇内容 orphan | MOC 占了 13/14 orphan | `orphan_content_count` | 补链改 vault |

结论：下一轮**开发**应修 helper 口径，让报告不必手算、hint 能指向真问题。vault 整理（promote / 拆 engineering / 补链）单列，不进本 spec 的 Execute。

不改：`use_rate` 公式（仍 `cite_7d * 100 / recall_7d`）。改分母会让 snap `delta_use_rate` 与 0.8.0 不可比，也掩盖仪式性 recall。协议召回多，分母大，这是有意的「召了有没有用」。

## 2. Innovate

### 方案 A（推荐）：helper 诚实键 + 放宽 `low_use` + 协议一句

在 `health` 现有键之后追加（仍不新开子命令）：

- 检索：一等公民 `recall_labeled_*`，`summary=` 带上 `labeled=`
- 库存：内容 evergreen / 内容 other / 内容 orphan（MOC 从这些口径排除）
- hint：`use_rate` 低且有命中时打 `low_use`（今天这份报告就会响）
- 协议：cite 条件保持；health 报告 README 改用新键，不再手算 labeled

工作量小，e2e 可测，与 0.8.0 字段顺序门禁兼容（新键仍接在功效块末尾 / `summary=` 之前或之内）。

### 方案 B：只改协议

SKILL / `_protocol.md` 把 cite 写得更硬。不 bump helper。`use_rate` 仍难看懂（含 nunk、MOC 污染 orphan/kind_other），自检报告还要手算。**不推荐**作为唯一动作。

### 方案 C：改 `use_rate` 分母为 labeled recall 或 hits

「升级后召回」口径更漂亮，但与已写入的 `health-snap.log` 不可比，且不再惩罚仪式性 4 词 miss。**不做**。若以后要，新键 `use_rate_labeled`，保留 `use_rate`。

本 spec 锁定 **A**。C 的 `use_rate_labeled` 列为明确非目标（可在 0.8.2 再开）。

## 3. Plan（锁定，待批）

### 3.1 版本与范围

- `VERSION` `0.8.0` → `0.8.1`
- 只动 helper `health`/`stats`、协议、自检 README、CHANGELOG、e2e
- 不改 vault；不改 `new`/`recall` 匹配；不改 `cite_rate` / `use_rate` / `kind_other` 旧公式

### 3.2 新 health 键（接在现有功效块之后、`delta_*` / `summary=` 之前）

由已有计数派生，不再扫一遍 vault（MOC 扫描已有 `moc_count` / `mmfs_is_moc`）。

| 键 | 定义 |
|---|---|
| `recall_labeled_7d` | `n1_7d + n23_7d + n4_7d` |
| `recall_labeled_hits_7d` | 对应三桶 hits 之和 |
| `recall_labeled_hit_rate` | 无 labeled 次则为 `-1`，否则 hits*100/n（整数除法） |
| `heat_evergreen_content` | evergreen 且非 `mmfs_is_moc` 的笔记数 |
| `kind_other_content` | `kind_other` 里非 MOC 的篇数 |
| `kind_other_content_pct` | 分母 `notes_total - moc_count`；分母 0 则为 `-1` |
| `orphan_content_count` | orphan 且非 MOC |
| `orphan_content_pct` | 分母 `notes_total - moc_count`；分母 0 则为 `-1` |

旧键 `kind_other` / `kind_other_pct` / `orphan_count` / `orphan_pct` / `heat_evergreen` **公式不变**。

`hint=high_kind_other` 改用 `kind_other_content_pct`（阈值仍 `notes_total >= 10` 且内容 other 占比 `>= 40`）。今日 vault 内容 other=0，hint 仍不响，这是正确的。e2e 里「10 篇无 kind 且非 MOC」的用例继续覆盖。

### 3.3 `summary=`

在现有字段中插入 `labeled=`（labeled 命中率，`-1` 时为 `-`）：

`hit_rate=% labeled=% n1=% n4=% use_rate=% cite=% read=% uncited_read=% orphan_pct=% moc=%`

`orphan_pct` 仍是含 MOC 的旧口径（summary 保持短）。内容 orphan 看独立键。

### 3.4 `hint=low_use`

现网：`recall_hits_7d >= 5` 且 `cite_7d = 0`。

改为（满足任一即输出，仍只打一行）：

- 旧条件保留；或
- `recall_hits_7d >= 5` 且 `use_rate >= 0` 且 `use_rate < 20`

今日报告：hits=21、use_rate=10 → **会**打 `low_use`。这是本包对 P0 的 helper 侧动作。

不删 `low_cite_rate`。

### 3.5 Snap

`health-snap.log` 追加：`recall_labeled_hit_rate` `heat_evergreen_content` `kind_other_content` `orphan_content_count`（旧键仍写）。`delta_*` 对新增键按现网规则（缺旧键则 `-`）。

### 3.6 协议与自检格式

- `_protocol.md` / `SKILL.md`：解读优先 `recall_labeled_hit_rate`、`use_rate`、`hint=low_use`；`kind_other_content` / `orphan_content_*` / `heat_evergreen_content` 用于库存诚实。`high_kind_other` 针对内容缺 kind，不是 MOC。
- `docs/health-reports/README.md`：功效表用 `recall_labeled_hit_rate`，不再规定手算；库存节用内容口径。

### 3.7 非目标

- 向量；新子命令；改 `use_rate` / `cite_rate` 公式
- `use_rate_labeled`
- 在 `new` 上挂 capture_after_miss 警告
- 改写历史 ledger 清 nunk
- vault：promote 六条 suggest、拆 `engineering`、给试点期笔记补链（另开 vault 任务，需用户逐条确认）
- 给 MOC 模板加 `kind:`（会让 `kind_other` 自然下降，但是 vault/模板行为变化，本包不做）

### 3.8 验收

1. e2e：孤立 ledger 上 `recall_labeled_hit_rate` 等于三桶合计；MOC 计入 `moc_count` 但不计入 `kind_other_content` / `orphan_content_count`；`use_rate=10` 且 hits>=5 时有 `hint=low_use`；0.7.2 字段顺序门禁不破。
2. 本机 `health`：`summary=` 含 `labeled=`；`heat_evergreen_content=0`；`kind_other_content=0`；`orphan_content_count=1`（若那篇孤儿仍在）。
3. `./scripts/e2e/run.sh` 全绿。
4. 下一份 `docs/health-reports/` 实例按更新后的 README 写（Execute 结束时不强制出新报告，除非用户要求）。

## 4. 建议的后续顺序（批准后）

1. 本 spec → implementation plan → 0.8.1 Execute
2. （可选，非本 spec）用户确认后的 vault 卫生：promote / 补链 / 是否拆 engineering
3. 再跑一份带 ISO 时间戳的自检，对比 `labeled` 与 `low_use`

## 5. 请批的点

请确认：

1. 采用方案 A、版本 `0.8.1`，且不改 `use_rate` 公式
2. `low_use` 在 `use_rate < 20` 且 hits>=5 时也触发
3. vault 整理（P2/P3 改库）不进这一包

批准后按 `docs/superpowers/plans/` 写实现计划再动代码。
