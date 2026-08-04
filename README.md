# MemoVault

[中文](README_CN.md)

A pure local filesystem skill that teaches coding agents how to sink knowledge
into an Obsidian vault with bash. No Obsidian plugin is required.

When the Obsidian desktop app is running, MemoVault uses the official
[Obsidian CLI](https://obsidian.md/cli). When it is not, it falls back to plain
markdown + `rg`/`grep` on the same vault files.

| | |
|---|---|
| Skill name | `memovault` |
| Version | `0.4.1` (see `VERSION`) |
| Skill source (after install) | `~/.agents/skills/memovault/` |
| Knowledge vault | `~/.agent-memo-vault/` |
| Vault override | `AGENT_MEMO_VAULT` |
| Heat tiers | `seedling` / `growing` / `evergreen` |
| Optional note kinds | `raw` / `atom` / `scenario` / `persona` / `skill` |

## Why

Coding agents forget across sessions. MemoVault gives them a durable, local
second brain: capture once, link with `[[wikilinks]]`, retrieve by search / tags /
backlinks, and keep promoting notes as they mature.

Agents follow an always-on memory protocol (auto recall, semi-auto capture,
distill raw evidence into atoms/scenarios, and skill SOPs under `brain/skills/`).

## Features

- **Capture / edit:** `new`, `append`, `prepend`, `read`, `daily`, `daily:append`
- **Retrieve:** full-text `search`, `tags` / `by-tag`, `by-heat`
- **Graph:** `backlinks`, `links`, `orphans`, `unresolved`
- **Organize:** `move`, `rename` (link-safe in `cli` mode), `promote`, `moc`
- **Layered memory:** optional `kind` + `sources` for distill provenance
- **Dual runtime:** `cli` when Obsidian+CLI work; `fs` otherwise (or forced with
  `MM_FORCE_FS=1` for headless hosts)
- **Multi-agent install:** Claude, Cursor, Codex, Gemini, Cline, Copilot, and more

Vector / semantic search is deferred; see `docs/DEVELOPMENT.md`.

## Requirements

- Bash (macOS ships 3.2; scripts stay compatible)
- `jq` for vault registration / e2e CLI phase; `rg` recommended (`grep` fallback)
- Obsidian installer **1.12.7+** only if you want `cli` mode
  (Settings -> General -> Command line interface, then register on PATH)

`fs` mode works without Obsidian installed.

## Quick start

```bash
# From this repository
./install/install.sh --all              # skill source + inject all supported agents
./install/install.sh --register-vault   # register ~/.agent-memo-vault in Obsidian
./install/install.sh --verify           # read-only health check
```

Useful variants:

```bash
./install/install.sh --agent cursor
./install/install.sh --force-fs         # pin MM_FORCE_FS=1 in env.sh (headless)
./install/install.sh --upgrade          # re-sync from this repo + re-inject agents
```

Restart the terminal and your agent after install. Full guide: `docs/INSTALL.md`.

## Everyday use (agents)

Helper after install:

```bash
MM="$HOME/.agents/skills/memovault/scripts/memovault.sh"

"$MM" preflight
"$MM" new travel "Trip Plan" --kind atom --tags trip --body "See [[City Guide]]"
"$MM" search "Trip Plan" --limit 10
"$MM" backlinks "Trip Plan"
"$MM" promote "Trip Plan"
```

In this repo during development, use `./scripts/memovault.sh` instead.

Canonical agent contract: `SKILL.md`.

## Always-on memory protocol

Injected adapters tell agents to:

1. **Recall** at the start of a task (`search`, prefer evergreen/growing and richer kinds)
2. **Propose then capture** durable knowledge (or write immediately on explicit
   "remember" / "记一下" phrases)
3. **Distill** daily/raw evidence into `atom` / `scenario` with `sources` and
   `[[YYYY-MM-DD]]` provenance links
4. **Skill SOPs** under `brain/skills/` with `--kind skill` (see `templates/skill.md`)

## Testing

End-to-end harness (isolated temp vault; never touches `~/.agent-memo-vault`):

```bash
./scripts/e2e/run.sh            # official gate: fs + cli (needs Obsidian+CLI)
./scripts/e2e/run.sh --fs-only  # headless / CI-friendly escape hatch
```

Agent orchestration skill: `skills/testing-memovault/SKILL.md`  
Design: `docs/superpowers/specs/2026-08-03-e2e-testing-design.md`

## Docs map

| Doc | Purpose |
|---|---|
| `AGENTS.md` | Project charter and naming contract |
| `SKILL.md` | Agent-facing skill definition (source of truth) |
| `docs/INSTALL.md` | Install, verify, upgrade, uninstall |
| `docs/ARCHITECTURE.md` | cli/fs layers and data flow |
| `docs/CLASSIFICATION.md` | Domain, heat, and memory kinds |
| `docs/CLI-REFERENCE.md` | Curated Obsidian CLI notes |
| `docs/DEVELOPMENT.md` | Extending adapters / phases / e2e pointers |
| `docs/RIPER.md` | Spec-driven change log |

## Hard constraints

- No emoji in files, comments, docs, scripts, or note content
- Never write outside `$AGENT_MEMO_VAULT`
- Confirm with the user before delete or bulk move

## License

[MIT](LICENSE) — Copyright (c) 2026 Seven Chan
