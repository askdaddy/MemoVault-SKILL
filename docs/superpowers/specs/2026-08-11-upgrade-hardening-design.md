# 设计：Upgrade 硬化（选最新完整树 + env 稳定）

日期：2026-08-11  
状态：已批准（2026-08-11）  
仓库：MemoVault-SKILL  
版本目标：`0.7.1`  
依据：用户观察到多次 upgrade 翻车；锁定选源策略 **B**

## 1. 目标

系统性修复 install/upgrade，使：

1. **可升级**：正常安装后 `memovault upgrade` 一定能找到 installer。  
2. **源可信**：默认在候选完整树中选 **VERSION 最新**者（策略 B）；两套 resolver 行为一致。  
3. **vault 稳定**：upgrade 默认保留已有 `env.sh`；shell 里临时 `AGENT_MEMO_VAULT` 不得覆盖用户配置。  
4. **闸门诚实**：newer 升级；equal 需 `--force`；older 默认拒绝，仅 `--force` 降级。  
5. **可测**：隔离目录下的 install/upgrade 回归套件。

## 2. 已锁定决策

| 项 | 选择 |
|---|---|
| 选源 | **B**：候选完整树中取 VERSION newest；并列 ROOT > origin > cache |
| 强制覆盖源 | `MEMOVAULT_DEV_REPO` 仍最高优先（不参与比较） |
| 安装包 | `mm_install_source` **拷贝 `install/`** |
| env.sh | 已存在则 upgrade **默认保留**；仅 `--vault` / `--reset-env` 重写 |
| shell 污染 | 当前进程 `AGENT_MEMO_VAULT` **不得**在 upgrade 时写入 env.sh 默认值 |
| 版本闸门 | older → exit 1（除非 `--force`） |
| cache | upgrade 开始时若 cache 存在则 **尽力更新**（非致命），再选 newest |
| 版本号 | `0.7.1` |

## 3. 非目标

- 重写 curl\|bash 远程主路径（可选：remote 前对 `--help` 短路）  
- 自动卸载旧 agent stub  
- 包管理器 / GitHub Release 资产  
- 改变 vault 笔记内容的升级语义（笔记永不被 upgrade 改写）

## 4. 问题根因（摘要）

1. `install/` 未拷入 skill → `memovault upgrade` 恒失败。  
2. install.sh 与 memovault.sh 两套 `mm_resolve_dev_repo`；curl cache 可长期陈旧。  
3. `mm_write_env` 每次覆盖，且用当前 shell `AGENT_MEMO_VAULT` 烘焙路径。  
4. `dev older` 只打日志仍继续 → 可静默降级。  
5. 无 install/upgrade e2e → 回归靠人肉。

## 5. 选源算法

### 5.1 完整树

与现有 `mm_is_full_tree` 一致：`VERSION` + `SKILL.md` + `install/targets.sh` + `scripts/memovault.sh`。

### 5.2 `mm_pick_upgrade_tree`

输入：`SOURCE`（已安装 skill 根）、可选 `ROOT`（当前 installer 所在仓库根）。

1. 若 `MEMOVAULT_DEV_REPO` 为存在目录且为完整树 → 直接返回（日志 `picked=dev_repo`）。  
2. 若 `~/.cache/memovault/repo`（或 `MEMOVAULT_CACHE_REPO`）存在：尽力 `fetch/pull`（失败 warning）。  
3. 收集候选（存在且完整）：  
   - `ROOT`（若非空）  
   - `$SOURCE/.source-origin` 所指路径  
   - cache 路径  
4. 对候选读 `VERSION`，`mm_vercmp` 取 **newest**。  
5. 并列：优先级 **ROOT > origin > cache**。  
6. 无候选 → 失败，提示设置 `MEMOVAULT_DEV_REPO` 或从完整 checkout / curl 安装。

日志一行：

```text
upgrade: picked=<path> ver=<v> (candidates: ...)
```

### 5.3 共享实现

优先：`install/lib/resolve.sh`（随 `install/` 一并安装），由 `install.sh` 与 `memovault.sh`（若文件存在）source。  
Helper 内保留最小 fallback：无 `install/lib/resolve.sh` 时仍能解析 origin/cache/DEV_REPO，便于从 0.7.0 过渡到 0.7.1。

### 5.4 Helper `upgrade` 入口

查找 installer 顺序：

1. `$MM_SOURCE/install/install.sh`  
2. `$MM_SOURCE/.source-origin/install/install.sh`（若 origin 完整）  
3. `$MEMOVAULT_CACHE_REPO/install/install.sh` 或 `~/.cache/memovault/repo/install/install.sh`  
4. 否则 die，提示用 curl\|bash 或本地 `./install/install.sh --upgrade`

## 6. env.sh 与 vault

| 场景 | 行为 |
|---|---|
| 无 `env.sh` | 写入 `export AGENT_MEMO_VAULT="${AGENT_MEMO_VAULT:-$default}"`；`$default` 来自 `--vault` 或 `$HOME/.agent-memo-vault`（**不用**未通过 `--vault` 的 shell 污染值作为「已记录默认」——见下） |
| 有 `env.sh` 且未 `--vault` / `--reset-env` | **不覆盖** |
| `--vault PATH` | 重写 env.sh，默认 PATH；scaffold 该 PATH |
| `--reset-env` | 重写为 `$HOME/.agent-memo-vault`（除非同时 `--vault`） |

**污染防护（upgrade / 重装）：**

- 解析「要写入的默认 vault」时：仅认 CLI `--vault`，否则认 **已有 env.sh 解析出的默认**，再否则 `$HOME/.agent-memo-vault`。  
- **忽略**进程环境中的 `AGENT_MEMO_VAULT`，除非它与 CLI `--vault` 相同意图（实现上：upgrade 路径在写 env 前不要用 `VAULT="${AGENT_MEMO_VAULT:-...}"` 作为写入源）。  
- 注入 stub 的 `__MEMOVAULT_VAULT__` 使用上述「稳定默认」，而非污染环境。

`mm_scaffold_vault` 仍可对「本次操作目标 vault」建目录；目标 vault 与写入 env 的规则一致。

## 7. 版本闸门

| rel(dev, installed) | 行为 |
|---|---|
| newer | 继续 |
| equal | 无 `--force` → 退出 0；有 → 重同步 |
| older | 无 `--force` → **exit 1**；有 → 降级重同步 |

Usage：删除「Implies `--force`」对版本闸门的误导；写明注入在 upgrade 流程内始终 force，版本 equal/older 另需 `--force`。

## 8. 拷贝清单

`mm_install_source` 增加：`install`（目录整体 `rm -rf` + `cp -R`）。  
其余不变。`.source-origin` 仍写本次拷贝所用的 `ROOT`（即 picked 树）。

## 9. 测试

新建 `scripts/e2e/suites/09-upgrade.sh`（临时 HOME/SOURCE/VAULT，无网络）：

1. 旧式安装（无 `install/`）→ 用完整 fixture/ROOT 跑 upgrade → skill 下出现 `install/install.sh`；再经 helper `upgrade --force --no-pull` 成功。  
2. 预置自定义 `env.sh` vault；shell `export AGENT_MEMO_VAULT=/tmp/polluted` → upgrade 后 env.sh **仍**为自定义路径。  
3. installed 版本 > picked → 无 `--force` 失败；`--force` 成功。  
4. 两候选不同 VERSION → 选 newer。

注册进 `scripts/e2e/run.sh`。

## 10. 文档

更新：`docs/INSTALL.md`、`docs/ARCHITECTURE.md` §9、`SKILL.md` Update、`README.md` / `README_CN.md`、`docs/RIPER.md` Entry、`VERSION` → `0.7.1`。

## 11. 验收

- `./scripts/e2e/run.sh` 全绿（含 09）。  
- 本机从已装 0.7.0：`./install/install.sh --upgrade --no-pull` 后 `memovault upgrade --force --no-pull` 可跑；`env.sh` 仍指向 `~/.agent-memo-vault`（在未传 `--vault` 时）。  
- 无 emoji；bash 3.2；命名合同不变。
