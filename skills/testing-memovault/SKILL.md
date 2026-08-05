---
name: testing-memovault
description: "Use when verifying MemoVault end-to-end, running the memovault e2e suite, or validating the memory protocol against an isolated vault."
---

# testing-memovault

对 MemoVault 做端到端验收。机械层由 harness 断言；本 skill 编排执行并补 memory protocol。

## 硬规则

- 只测仓库内 helper：`./scripts/memovault.sh`（或 `scripts/e2e/run.sh` 封装）。
- 绝不把 `AGENT_MEMO_VAULT` 设为 `~/.agent-memo-vault`。
- 官方门禁为单阶段 shell；不要对官方验收使用 `--fs-only`（它已是 no-op 兼容别名）。
- 运行时不再依赖 Obsidian 桌面端或 `obsidian` CLI；Obsidian 仅用于人浏览 vault。
- 无 emoji。

## 前置

- 当前工作目录为 MemoVault-SKILL 仓库根。
- PATH 上有 `rg` 或 `grep`（搜索后端自动探测）。
- 不需要 `jq`、不需要 Obsidian 运行。

## 步骤 A — 机械 harness

```bash
./scripts/e2e/run.sh --keep
```

要求 exit 0。从输出捕获 `E2E_ROOT=` 与 `E2E_VAULT=`。非 0 则 overall=FAIL，protocol 标 SKIP 或仍跑但不得 overall PASS。

## 步骤 B — Memory protocol 检查清单

```bash
export AGENT_MEMO_VAULT="$E2E_VAULT"
MM=./scripts/memovault.sh
```

按序执行并记录到报告：

1. **recall** — `"$MM" search "<窄关键词>" --limit 10`，在报告中写明如何按 heat/kind 排序偏好解读结果。
2. **propose_capture** — 先写出 propose 文本（尚未 `new`）；在报告日志写入 `user: yes`；再 `"$MM" new ... --kind atom`。
3. **explicit_remember** — 模拟用户说 `remember this`，立即 `new`，报告确认标题/路径。
4. **distill** — `daily:append` 一行 → `new ... --kind atom`，frontmatter/`sources` 或正文含 `[[YYYY-MM-DD]]`。
5. **skill_sop** — `new skills "..." --kind skill`，正文含 Trigger / Steps / Verify / Related。

任一项未做到 → 对应字段 FAIL。

## 步骤 C — 报告（必须原样字段）

```
# MemoVault E2E report
repo: <path>
date: <ISO date>
harness: PASS|FAIL
  shell: PASS|FAIL
  asserts_pass: <n>
  asserts_fail: <n>
protocol: PASS|FAIL|SKIP
  recall: PASS|FAIL
  propose_capture: PASS|FAIL
  explicit_remember: PASS|FAIL
  distill: PASS|FAIL
  skill_sop: PASS|FAIL
overall: PASS|FAIL
notes: <one line>
```

harness 失败或任一 protocol 子项 FAIL → `overall: FAIL`。

## 清理

非调试：`rm -rf "$E2E_ROOT"`。
