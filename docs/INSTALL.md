# Install guide

How to install MemoVault into the canonical source location and inject it into
one or more coding agents.

## 1. Prerequisites

- Bash, `jq`, `rg` (ripgrep) recommended. `grep`/`awk` are fallbacks.
- Obsidian installer 1.12.7 or newer (only needed for `cli` mode; `fs` mode
  works without it).
- In Obsidian: Settings -> General -> enable Command line interface, then follow
  the on screen PATH registration. Restart the terminal afterward.

## 2. Concepts

- **Skill source** = `~/.agents/skills/memovault/`. The authoritative copy of the
  skill that the helper and the docs live in.
- **Knowledge vault** = `~/.agent-memo-vault/`. The Obsidian vault where notes
  are written. Override with `AGENT_MEMO_VAULT`.
- **Adapter stub** = the small file dropped into each agent's rules/skill
  location. It points to the skill source so there is one source of truth.

## 3. Commands

Run from the repository root.

```bash
# Install the skill source and scaffold the vault (no agent injection yet)
./install/install.sh --source-only

# Register the vault into Obsidian (backs up obsidian.json first)
./install/install.sh --register-vault

# Inject into one agent
./install/install.sh --agent claude

# Inject into every supported agent
./install/install.sh --all

# Preview without writing
./install/install.sh --agent cursor --dry-run

# Use a non default vault location
./install/install.sh --agent claude --vault ~/MyVault

# Embed the full SKILL.md instead of a pointer stub
./install/install.sh --agent cline --inline
```

Flags:
- `--source-only`: copy skill to the source dir and scaffold the vault only.
- `--register-vault`: add `~/.agent-memo-vault` to `obsidian.json` as
  `agent-memo-vault` (id derived from the path). Skipped silently if Obsidian is
  older than required or the file is absent; prints guidance instead.
- `--agent <name>`: inject into one agent.
- `--all`: inject into every agent in `targets.sh`.
- `--vault <path>`: override the vault path (and `AGENT_MEMO_VAULT`).
- `--source <path>`: override the skill source dir.
- `--inline`: embed the full `SKILL.md` in each adapter instead of a pointer.
- `--force`: overwrite existing files.
- `--dry-run`: print actions only.
- `--stdout`: print the rendered body for one agent (for UI-only targets such as
  Trae global AI Rules) instead of writing a file; requires `--agent <name>`.

## 4. Environment

`scripts/memovault.sh` defaults `AGENT_MEMO_VAULT` to `~/.agent-memo-vault`, so no
global export is required. To make the override permanent for your shell, the
installer writes `~/.agents/skills/memovault/env.sh`:

```bash
export AGENT_MEMO_VAULT="${AGENT_MEMO_VAULT:-$HOME/.agent-memo-vault}"
```

Source it from your shell rc if you change the default:

```bash
echo 'source "$HOME/.agents/skills/memovault/env.sh"' >> ~/.zshrc
```

## 5. Supported agents and locations

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

## 6. Verify

```bash
~/.agents/skills/memovault/scripts/memovault.sh preflight
~/.agents/skills/memovault/scripts/memovault.sh new engineering "Test Note" --body "hello"
~/.agents/skills/memovault/scripts/memovault.sh read "Test Note"
~/.agents/skills/memovault/scripts/memovault.sh search "hello"
```

Restart your agent after injection so it reloads skills/rules.

## 7. Uninstall

Remove the injected stub files listed by `--dry-run`, delete
`~/.agents/skills/memovault/`, and (optionally) remove the `agent-memo-vault`
entry from `obsidian.json`. The vault `~/.agent-memo-vault/` is your data; the
installer never deletes it.
