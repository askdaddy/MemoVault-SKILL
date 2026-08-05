# Remote install (curl | bash) Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox syntax.

**Goal:** Make `curl .../install/install.sh | bash` a one-line full install, while keeping local-checkout installs using the working tree.

**Architecture:** Dual-mode `install/install.sh`: if the script's parent tree is incomplete (typical of stdin/`curl | bash`), sync `~/.cache/memovault/repo` via git and `exec` the cached installer; otherwise run as today. No-args defaults to `--all`.

**Tech Stack:** bash 3.2, git, existing `install/install.sh` + docs.

**Spec:** `docs/superpowers/specs/2026-08-05-remote-install-design.md`

## Global Constraints

- No emoji; bash 3.2; quote variables; no `set -e` in helper style (installer already `set -uo pipefail`)
- No new `bootstrap.sh`
- Cache default: `$HOME/.cache/memovault/repo`
- VERSION bump: `0.5.0` -> `0.5.1`

---

### Task 1: `install/install.sh` dual-mode + default `--all`

**Files:** `install/install.sh`

- [x] Move `. targets.sh` to **after** full-tree check (piped runs have no `targets.sh` beside them)
- [x] Add `mm_is_full_tree`; resolve `HERE`/`ROOT` only when `BASH_SOURCE[0]` is a real file
- [x] Add remote sync (`MEMOVAULT_CACHE_REPO` / `REPO_URL` / `REF`) then `exec "$cache/install/install.sh" "$@"`
- [x] No-args: set `AGENTS` to full `mm_target_list` instead of printing usage
- [x] Update `mm_usage` for curl | bash and default `--all`
- [x] Soften outdated Obsidian-CLI "next steps" to match shell-only (touch only that block)

### Task 2: Docs + version

**Files:** `README.md`, `README_CN.md`, `docs/INSTALL.md`, `docs/RIPER.md`, `VERSION`, `SKILL.md` frontmatter if present

- [x] Quick start: curl | bash primary; local secondary
- [x] INSTALL: one-line section + env table + default `--all` note
- [x] RIPER entry for this change
- [x] Bump `0.5.1`

### Task 3: Verify

- [x] `bash -n install/install.sh`
- [x] Local: `./install/install.sh --dry-run --source-only` does not require/update cache as a precondition
- [x] Simulated remote: `bash -s -- ... < install/install.sh` with staged repo URL reaches install via cache exec; no-args `| bash` defaults to `--all`
