# Upgrade 硬化（0.7.1）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `memovault upgrade` reliable: copy `install/`, pick newest full tree, preserve `env.sh`, honest version gates, e2e coverage — ship as `0.7.1`.

**Architecture:** Shared resolve helpers in `install/lib/resolve.sh`; `install.sh` owns upgrade/env write; helper falls back to origin/cache installer until `install/` is present; suite `09-upgrade` uses isolated HOME trees.

**Tech Stack:** bash 3.2, existing e2e harness, no network in tests.

---

## File map

| File | Action |
|---|---|
| `install/lib/resolve.sh` | Create — `mm_is_full_tree`, `mm_version_of`, `mm_vercmp`, `mm_pick_upgrade_tree`, `mm_read_env_vault_default` |
| `install/install.sh` | Modify — source resolve; copy `install/`; env preserve; gate older; cache refresh; `--reset-env` |
| `scripts/memovault.sh` | Modify — source resolve when present; upgrade installer fallback; align pick for preflight hint |
| `scripts/e2e/suites/09-upgrade.sh` | Create |
| `scripts/e2e/run.sh` | Register 09 |
| `VERSION`, `SKILL.md`, docs | Bump / document |

---

### Task 1: Shared resolve + install copy + env preserve + gates

**Files:** `install/lib/resolve.sh`, `install/install.sh`

- [ ] **Step 1: Add `install/lib/resolve.sh`**

Export (set functions, no side effects):

```bash
mm_is_full_tree() { ... }   # same checks as today
mm_version_of() { ... }
mm_vercmp() { ... }         # newer|equal|older
mm_pick_upgrade_tree() {
  # args via env: MM_RESOLVE_SOURCE, MM_RESOLVE_ROOT (optional)
  # MEMOVAULT_DEV_REPO wins; refresh cache best-effort; pick newest
  # print path on stdout; log candidates on stderr or via mm_note if defined
}
mm_read_env_vault_default() {
  # parse env.sh for ${AGENT_MEMO_VAULT:-PATH} default PATH; else empty
}
```

- [ ] **Step 2: Wire `install.sh`**

- Source `$HERE/lib/resolve.sh` after ROOT known (local mode).  
- Remove duplicate `mm_version_of` / `mm_vercmp` / `mm_is_full_tree` or keep thin wrappers.  
- `mm_install_source`: add `install` to copy list.  
- `mm_write_env`: if `$SOURCE/env.sh` exists and `RESET_ENV!=1` and no new `--vault` this run aimed at rewrite → skip.  
- Fresh write uses stable vault: `--vault` or existing default or `$HOME/.agent-memo-vault` — **not** ambient `AGENT_MEMO_VAULT` on upgrade.  
- `mm_upgrade`: pick via `mm_pick_upgrade_tree`; older without force → `mm_die`; log picked line.  
- Flags: `--reset-env`; document `--vault` forces env rewrite on upgrade.

- [ ] **Step 3: Smoke (manual, temp dirs)**

```bash
# from repo
TMP=$(mktemp -d)
export HOME="$TMP/home" MEMOVAULT_SOURCE="$TMP/skill"
unset AGENT_MEMO_VAULT
./install/install.sh --source-only
test -f "$MEMOVAULT_SOURCE/install/install.sh"
```

---

### Task 2: Helper upgrade fallback + preflight pick

**Files:** `scripts/memovault.sh`

- [ ] **Step 1:** If `$MM_SOURCE/install/lib/resolve.sh` exists, source it; else keep local vercmp.  
- [ ] **Step 2:** `mm_check_update` / resolve use `mm_pick_upgrade_tree` when available.  
- [ ] **Step 3:** `mm_cmd_upgrade` try installer paths: SOURCE, origin, cache; then exec `--upgrade "$@"`.

---

### Task 3: e2e suite 09

**Files:** `scripts/e2e/suites/09-upgrade.sh`, `scripts/e2e/run.sh`

- [ ] **Step 1: Cases**

1. After install from ROOT, `install/install.sh` exists under skill.  
2. Custom env.sh + polluted `AGENT_MEMO_VAULT` → upgrade preserves custom.  
3. Older gate: fake installed VERSION newer than fixture → exit nonzero without `--force`.  
4. Two fixture trees different VERSION → pick newer (unit-ish via install.sh logging or small script calling resolve).

- [ ] **Step 2: Register in `run.sh`; full e2e green.**

---

### Task 4: Docs + VERSION 0.7.1

- [ ] Bump `VERSION` / `SKILL.md` version.  
- [ ] Update INSTALL / ARCHITECTURE §9 / README* / RIPER Entry 16 (or next).  
- [ ] Self-check: no emoji; bash -n; e2e pass.

- [ ] **Commit only if user asks.**

---

## Spec coverage

| Spec section | Task |
|---|---|
| pick newest + DEV_REPO | 1–2 |
| copy install/ | 1 |
| env preserve / pollution | 1, 3 |
| version gates | 1, 3 |
| e2e 09 | 3 |
| docs 0.7.1 | 4 |

## Placeholder scan

None.
