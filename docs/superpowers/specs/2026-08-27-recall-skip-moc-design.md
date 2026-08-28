# 设计：recall 跳过 MOC + 0.8.0 合并缺口

日期：2026-08-27
版本目标：折进未发布的 `0.8.0`（不 bump 0.8.1）。recall 默认结果集变化，属 agent 可见行为，已在 0.8.0 minor 内。

## 1. 问题

方案 A（分词 OR）+ 方案 B（每域一份 evergreen MOC）叠加后，`recall KillMode` 前五被 `engineering MOC` 和无关邻居占满，真正的笔记掉出 `--limit 5`。MOC 正文列出全部 `[[标题]]`，token-OR 命中整份索引；一跳图再把该域所有笔记灌进 RRF；evergreen 热度在同分时压过内容笔记。

独立代码审查还指出 0.8.0 合并缺口：`Eval Perc Sop.md` 与 spec/plan 仍未跟踪；`INSTALL.md` 未写明 0.7.2 → 0.8.0 必须 `upgrade`；`hint=wide_query` 无 e2e；epoch=0 时 `capture_after_miss` 的 overlap 分支不要求同日；`VERSION` 缺末尾换行。

本机 vault 一篇 crypto 笔记正文含明文 API key。不进 git；在 `$AGENT_MEMO_VAULT` 内改写。

## 2. 非目标

- 向量检索（方案 C）
- 拆 `engineering` 域、补 placeholder、去内容笔记 emoji、`promote`
- 给 recall 增加 `--include-moc`（YAGNI；需要索引时用 `search` 或 `moc`）
- 改 `search` / `orphans` / `backlinks` 的默认过滤
- 在仓库里提交密钥原文或轮换第三方密钥（轮换由用户在原服务完成）
- 自动 `git commit`（除非用户另说）

## 3. `mmfs_is_moc`

新函数，文件视为 MOC 当且仅当：

1. basename 匹配 `_*-MOC.md`（`mm_moc` 写入的 `brain/<domain>/_<domain>-MOC.md`），或
2. frontmatter `tags:` 含独立 token `moc`（匹配 `[moc]`、`[moc, x]`、`[x, moc]`），不把子串 `democracy` 当 moc。

## 4. `recall` 过滤

默认 `recall`（含 `--no-graph`）在 FTS 候选与一跳邻居（出链 + 回链）上调用 `mmfs_is_moc`，命中则跳过。与跳过 `kind: raw` 同级，且只作用于 `mmfs_recall`，**不**放进 `mmfs_search_file_ok`（否则 `search` 也找不到 MOC）。

查询 `engineering MOC` 时 `recall` 可以空；协议写明：找领域索引用 `search` 或 `moc <domain>`。

无新 CLI 旗标。

## 5. 观测小修

`capture_after_miss`：任一侧 `mm_obs_ts_epoch` 为 0 时，跳过 30 分钟分支（现网已如此）；**标题重叠分支**还要求 `cap_ts` 与 `miss_ts` 的 UTC 日（`cut -c1-10`）相同。两边都能解析 epoch 时，重叠仍可跨日（只要都在 7 天窗口且时序正确）。

## 6. 测试

- e2e：笔记标题含独特 token（如 `KillMode`），`moc` 该域后，`recall "<token>" --limit 5` 命中该笔记且输出不含 `_*MOC*` / `title=<domain> MOC`。`search "<token>"` 仍能看到 MOC 路径或标题。
- e2e 孤立 ledger：5 条 `token_n=4` 的 `event=recall`，`health` 含 `wide_query_7d=5` 与 `hint=wide_query`。
- 现有 suites 不回归。eval c3 夹具文件必须存在于工作树（已有则保持）。

## 7. 文档与安装

- `SKILL.md` / `_protocol.md`：recall 默认排除 MOC。
- `docs/ARCHITECTURE.md`：recall 行注明跳过 `_*-MOC.md`。
- `docs/INSTALL.md` 升级节：0.7.2 → 0.8.0 必须 `upgrade`（或 `install.sh --upgrade`），否则已安装 agent 仍按短语 FTS + 旧协议跑。
- `CHANGELOG.md` `[0.8.0]`：Added/Changed 写上跳过 MOC 与 INSTALL 提示。日期保持 2026-08-26（该 minor 的发布条目）；本轮不另开版本。
- `VERSION` 文件以换行结束。

## 8. Vault（本机，非仓库）

改写 `brain/crypto/openclaw-home 备份迁移内容.md`：保留备份里有哪些类别（env 键名、compose、cron 任务名），删除一切密钥值、token 值和可当凭证的片段。不把原文密钥写入 spec、plan、changelog 或聊天。

## 9. 验收

1. 本机 `recall KillMode --limit 5` 含 KillMode 笔记，不含 `engineering MOC`。
2. 本机 `recall PERC --limit 5` 能出现 PERC SOP 或 ops 簇内容笔记，MOC 不占满前五。
3. `./scripts/e2e/run.sh` 全绿。
4. 该 crypto 笔记正文不再匹配 `API_KEY=` 后的密钥形态。
