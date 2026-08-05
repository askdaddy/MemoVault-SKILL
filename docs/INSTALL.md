# Install guide

How to install MemoVault into the canonical source location and inject it into
one or more coding agents.

## 1. Prerequisites

- Bash, `find`, `awk`, `mv`, `mktemp`. `rg` (ripgrep) recommended; `grep` is the
  fallback for search.
- `git` is required for the one-line remote install (`curl | bash`). A local
  checkout install does not need network git operations at install time.
- `jq` only for the optional `--register-vault` step (the helper itself does not
  need it).
- Obsidian is optional. Install it only if you want to browse the vault in the
  desktop app. The helper never depends on the Obsidian CLI or on the app
  running, so there is no "must enable Settings -> Command line interface" step
  anymore.

### Windows

Windows is supported only through WSL2. Install WSL2 and run the same bash
commands from inside the WSL shell. No native `.ps1` implementation is
maintained.

## 2. Concepts

- **Skill source** = `~/.agents/skills/memovault/`. The authoritative copy of the
  skill that the helper and the docs live in.
- **Knowledge vault** = `~/.agent-memo-vault/`. The Obsidian vault where notes
  are written. Override with `AGENT_MEMO_VAULT`.
- **Adapter stub** = the small file dropped into each agent's rules/skill
  location. It points to the skill source so there is one source of truth.
- **Cache repo** (remote install only) = `~/.cache/memovault/repo` by default.
  The one-line installer clones or updates this tree, then runs the real
  `install.sh` from it. `.source-origin` then points here so `upgrade` can
  `git pull` the same cache.

## 3. One-line install

No prior `git clone` of this repository is required:

```bash
curl -fsSL https://raw.githubusercontent.com/askdaddy/MemoVault-SKILL/main/install/install.sh | bash
```

With no flags, this defaults to `--all` (install skill source + inject every
supported agent). Custom flags need `bash -s`:

```bash
curl -fsSL https://raw.githubusercontent.com/askdaddy/MemoVault-SKILL/main/install/install.sh | bash -s -- --agent cursor
curl -fsSL https://raw.githubusercontent.com/askdaddy/MemoVault-SKILL/main/install/install.sh | bash -s -- --source-only
```

How it works: if `install.sh` is not running from a full checkout, it syncs
`$MEMOVAULT_CACHE_REPO` (default `~/.cache/memovault/repo`) from
`$MEMOVAULT_REPO_URL` at `$MEMOVAULT_REF` (default `main`), then `exec`s that
tree's `install/install.sh`. Running `./install/install.sh` inside a clone
skips the remote sync and uses the working tree.

| Env | Meaning | Default |
|---|---|---|
| `MEMOVAULT_CACHE_REPO` | Clone directory for remote mode | `~/.cache/memovault/repo` |
| `MEMOVAULT_REPO_URL` | Git remote URL | `https://github.com/askdaddy/MemoVault-SKILL.git` |
| `MEMOVAULT_REF` | Branch or tag | `main` |

## 4. Commands

Run from the repository root (or rely on the one-line path above).

```bash
# No flags: same as --all
./install/install.sh

# Install the skill source and scaffold the vault (no agent injection yet)
./install/install.sh --source-only

# Optional: register the vault into Obsidian for browsing (backs up obsidian.json first)
./install/install.sh --register-vault

# Inject into one agent
./install/install.sh --agent claude

# Inject into every supported agent
./install/install.sh --all

# Preview without writing
./install/install.sh --agent cursor --dry-run

# Check source + always-on injection (no writes; exit 1 if incomplete)
./install/install.sh --verify

# Use a non default vault location
./install/install.sh --agent claude --vault ~/MyVault

# Embed the full SKILL.md instead of a pointer stub
./install/install.sh --agent cline --inline
```

Flags:
- (no flags): same as `--all`.
- `--source-only`: copy skill to the source dir and scaffold the vault only.
- `--register-vault`: optional. Adds `~/.agent-memo-vault` to `obsidian.json` as
  `agent-memo-vault` (id derived from the path) so you can browse the vault in
  the Obsidian desktop app. This is NOT required by the helper; the helper never
  reads `obsidian.json` and never checks whether the app is running. Skipped
  silently if `obsidian.json` is absent; prints guidance instead.
- `--agent <name>`: inject into one agent.
- `--all`: inject into every agent in `targets.sh`.
- `--vault <path>`: override the vault path (and `AGENT_MEMO_VAULT`).
- `--source <path>`: override the skill source dir.
- `--inline`: embed the full `SKILL.md` in each adapter instead of a pointer.
- `--force`: overwrite existing files.
- `--force-fs`: deprecated. Accepted for backward compatibility but is a no-op:
  the runtime is always shell, so there is nothing to force. Prints a warning.
- `--dry-run`: print actions only.
- `--verify`: read-only check of skill source, vault scaffold, and always-on
  agent injections. Optional `--agent` to limit scope. Exit 1 on failure.
- `--stdout`: print the rendered body for one agent (for UI-only targets such as
  Trae global AI Rules) instead of writing a file; requires `--agent <name>`.

## 5. Environment

`scripts/memovault.sh` defaults `AGENT_MEMO_VAULT` to `~/.agent-memo-vault`, so no
global export is required. The helper sources `~/.agents/skills/memovault/env.sh`
at startup, so anything pinned there applies to every caller (agents rarely
export env vars themselves) without each agent sourcing it. The installer writes
that file:

```bash
export AGENT_MEMO_VAULT="${AGENT_MEMO_VAULT:-$HOME/.agent-memo-vault}"
```

`MM_FORCE_FS` is deprecated and ignored by the helper. If you previously used
`install.sh --force-fs` to write `MM_FORCE_FS=1` into `env.sh`, that line is
now harmless: the helper prints a one-line deprecation warning and proceeds as
shell. You can remove the line from `env.sh` on your next upgrade; the installer
no longer adds it.

You may still source env.sh from your shell rc for your own terminal use (not
required for the helper):

```bash
echo 'source "$HOME/.agents/skills/memovault/env.sh"' >> ~/.zshrc
```

## 6. Supported agents and locations

Default install locations (personal/global). Override per agent by editing
`install/targets.sh`.

| Agent | Kind | Default location |
|---|---|---|
| claude | skill | `~/.claude/skills/memovault/SKILL.md` |
| pi | native | `~/.agents/skills/memovault/` (self-contained; auto-discovered) |
| codex | agents | append block to `~/.codex/AGENTS.md` |
| opencode | agents | append block to `~/.config/opencode/AGENTS.md` |
| crush | agents | append block to `~/.config/crush/AGENTS.md` |
| gemini | agents | append block to `~/.gemini/GEMINI.md` |
| cline | rules | `~/.cline/rules/memovault.md` |
| cursor | rules | `~/.cursor/rules/memovault.mdc` |
| trae | native / stdout | `~/.agents/skills/memovault/` (skills dir, if enabled) or paste `install.sh --agent trae --stdout` into Trae Settings -> AI Rules |
| copilot | rules | `~/.config/github-copilot/instructions.md` (append block) |

- The canonical skill home is `~/.agents/skills/memovault/` (self-contained:
  SKILL.md + scripts + templates + docs). `pi` and `trae` are `native`: they read
  this folder directly, so `--agent pi` / `--agent trae` just (re)install the
  source here. Every other agent gets a pointer stub/rules block that references
  this folder.
- `cline`, `crush`, `copilot` global paths vary by version. The installer creates
  missing parent directories. If your tool reads a different path, set it in
  `targets.sh` and re-run.
- Trae can use the shared skills directory (enable "`.agents` skills directory"
  in Trae Settings) for auto-discovery, or `install.sh --agent trae --stdout`
  pasted into Trae Settings -> AI Rules for always-on global rules.
- For project-scoped agents (Copilot repo instructions, Cursor project rules),
  prefer running `install.sh` inside that repo with the project path.

## 7. Verify

Seeing `~/.agents/skills/memovault/` on disk is not enough for always-on
recall/capture. Cursor, Claude, and most other agents need their adapter
injection (rules / skill stub / AGENTS.md block). Check that first:

```bash
./install/install.sh --verify
./install/install.sh --verify --agent cursor   # one agent
```

`--verify` exits non-zero if the skill source, vault scaffold, or any checked
agent's Memory protocol injection is missing. Fix with:

```bash
./install/install.sh --all --force
```

Then smoke-test the helper:

```bash
~/.agents/skills/memovault/scripts/memovault.sh preflight
~/.agents/skills/memovault/scripts/memovault.sh new engineering "Test Note" --body "hello"
~/.agents/skills/memovault/scripts/memovault.sh read "Test Note"
~/.agents/skills/memovault/scripts/memovault.sh search "hello"
```

Restart your agent after injection so it reloads skills/rules.

## 8. Upgrade

An already-installed skill can be re-synced from its dev repo. The dev repo is
the source of truth; there is no remote registry. It is auto-detected from
`.source-origin` (written at install time), or set explicitly:

```bash
export MEMOVAULT_DEV_REPO="$HOME/Workspace/MemoVault-SKILL"
```

From anywhere (delegates to `install.sh --upgrade`):

```bash
~/.agents/skills/memovault/scripts/memovault.sh upgrade
~/.agents/skills/memovault/scripts/memovault.sh upgrade --no-pull
```

Or directly from the dev repo:

```bash
./install/install.sh --upgrade            # pull (if git) + re-sync + re-inject
./install/install.sh --upgrade --no-pull  # skip the `git pull` step
./install/install.sh --upgrade --dry-run  # preview
```

Notes:
- `preflight` prints `hint: update-available <installed> <dev> (run: memovault
  upgrade)` when the installed `VERSION` is older than the dev repo's.
- If the dev repo is a git repo, `upgrade` runs `git pull --ff-only` first; pass
  `--no-pull` to skip it. Git is optional; the installer falls back to local
  files if git is absent or the pull fails.
- Upgrade re-runs source copy, vault scaffold, env write, and every agent
  injection with `FORCE=1`. It is idempotent.
- Upgrade never touches vault data (`$AGENT_MEMO_VAULT`).

## 9. Uninstall

Remove the injected stub files listed by `--dry-run`, delete
`~/.agents/skills/memovault/`, and (optionally) remove the `agent-memo-vault`
entry from `obsidian.json`. The vault `~/.agent-memo-vault/` is your data; the
installer never deletes it.
