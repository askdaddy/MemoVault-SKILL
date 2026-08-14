# MemoVault

[中文](README_CN.md)

A pure local filesystem skill that teaches coding agents how to sink knowledge
into an Obsidian vault with bash. No Obsidian plugin is required, and the
Obsidian desktop app / CLI is not a runtime dependency: MemoVault writes and
reads plain markdown directly under the vault directory. Humans may open the
same vault in Obsidian for browsing.

| | |
|---|---|
| Skill name | `memovault` |
| Version | `0.7.2` (see `VERSION`) |
| Skill source (after install) | `~/.agents/skills/memovault/` |
| Knowledge vault | `~/.agent-memo-vault/` |
| Vault override | `AGENT_MEMO_VAULT` |
| Heat tiers | `seedling` / `growing` / `evergreen` |
| Optional note kinds | `raw` / `atom` / `scenario` / `persona` / `skill` |

## Why

Coding agents forget across sessions. MemoVault gives them a durable, local
second brain: capture once, link with `[[wikilinks]]`, retrieve by search / tags /
backlinks, and keep promoting notes as they mature.

Agents follow an always-on memory protocol (`recall`, semi-auto capture,
`distill` from inbox/raw into atoms/scenarios, skill SOPs under `brain/skills/`,
and `health` proxy metrics). `daily/` is legacy/human-only; vault `templates/`
are optional.

## Features

- **Capture / edit:** `new`, `append`, `prepend`, `read`, `distill`; `daily` (legacy)
- **Retrieve:** ranked `recall` (FTS + one-hop graph RRF), filtered `search`,
  `tags` / `by-tag`, `by-heat`, `dedupe`, `eval`
- **Observability:** `cite`, `feedback`, `suggest`, `health`/`stats`, ledger (`search`, `recall_hit_rate` hints)
- **Graph:** `backlinks`, `links`, `orphans`, `unresolved`
- **Organize:** `move`, `rename` (link-safe), `promote`, `supersede`, `moc`
- **Layered memory:** optional `kind` + `status`/`supersedes` + `sources`
- **Single shell runtime:** one bash/filesystem implementation; no headless
  toggle, no GUI probe, no `obsidian` binary required
- **Cross-platform:** macOS and Linux officially; Windows via WSL2 running the
  same bash scripts (no native PowerShell business logic)
- **Multi-agent install:** Claude, Cursor, Codex, Gemini, Cline, Copilot, and more

Vector / semantic search is deferred; see `docs/DEVELOPMENT.md`.

## Requirements

- Bash (macOS ships 3.2; scripts stay compatible)
- `find`, `awk`, `grep`, `mv`, `mktemp`; `rg` recommended (`grep` fallback)
- `jq` only for the optional `--register-vault` step (not required by the helper)

Obsidian is optional: install it only if you want to browse the vault in the
desktop app. The helper never depends on the Obsidian CLI or on the app running.

### Windows

Windows is supported only through WSL2. Install WSL2, then run the same bash
commands from inside the WSL shell (e.g. `wsl ./scripts/memovault.sh ...`). No
native `.ps1` implementation is provided or maintained.

## Quick start

```bash
# One-line install (requires git); no flags => install source + all agents
curl -fsSL https://raw.githubusercontent.com/askdaddy/MemoVault-SKILL/main/install/install.sh | bash

# From a local checkout (same default)
./install/install.sh
./install/install.sh --register-vault   # optional: register vault in Obsidian for browsing
./install/install.sh --verify           # read-only health check
```

Useful variants:

```bash
./install/install.sh --agent cursor
# or: curl .../install/install.sh | bash -s -- --agent cursor
./install/install.sh --upgrade          # re-sync from origin repo + re-inject agents
```

`--force-fs` is accepted for backward compatibility but is a no-op: the runtime
is always shell, so there is nothing to force. Restart the terminal and your
agent after install. Full guide: `docs/INSTALL.md`.

## Everyday use (agents)

Helper after install:

```bash
MM="$HOME/.agents/skills/memovault/scripts/memovault.sh"

"$MM" preflight
"$MM" new travel "Trip Plan" --kind atom --tags trip --body "See [[City Guide]]"
"$MM" search "Trip Plan" --limit 10
"$MM" backlinks "Trip Plan"
"$MM" rename "Trip Plan" "Trip Plan 2026"   # wikilinks across the vault are rewritten
"$MM" promote "Trip Plan 2026"
```

In this repo during development, use `./scripts/memovault.sh` instead.

Canonical agent contract: `SKILL.md`.

## Always-on memory protocol

Injected adapters tell agents to:

1. **Recall** at the start of a task (`recall`, fall back to `search`)
2. **Propose then capture** durable knowledge (or write immediately on explicit
   "remember" / "记一下" phrases)
3. **Distill** inbox/raw into `atom` / `scenario` via `distill` (or `sources` +
   `[[raw-title]]`)
4. **Skill SOPs** under `brain/skills/` with `--kind skill`
5. **Health** via `health` when memory looks stale or the user asks. Prefer
   hints `low_recall_hit_rate` / `capture_after_miss` / `high_kind_other`.
   `cite_rate` is deprecated. Confirm before any rewrite. Installed adapters
   pick up this text only after `upgrade`.

## Testing

End-to-end harness (isolated temp vault; never touches `~/.agent-memo-vault`):

```bash
./scripts/e2e/run.sh            # official gate: single shell phase, no Obsidian needed
```

`--fs-only` is kept as a no-op alias for older callers; `--cli-only` is removed.
Agent orchestration skill: `skills/testing-memovault/SKILL.md`
Design: `docs/superpowers/specs/2026-08-04-shell-only-runtime-design.md` (section 8
supersedes the 2026-08-03 dual-mode gate).

## Docs map

| Doc | Purpose |
|---|---|
| `AGENTS.md` | Project charter and naming contract |
| `SKILL.md` | Agent-facing skill definition (source of truth) |
| `CHANGELOG.md` | Human-facing release log |
| `docs/INSTALL.md` | Install, verify, upgrade, uninstall |
| `docs/ARCHITECTURE.md` | Single shell layer and data flow |
| `docs/CLASSIFICATION.md` | Domain, heat, and memory kinds |
| `docs/CLI-REFERENCE.md` | Optional Obsidian CLI reference (humans; not a runtime dependency) |
| `docs/DEVELOPMENT.md` | Extending adapters / phases / e2e pointers |
| `docs/RIPER.md` | Spec-driven change log |

## Hard constraints

- No emoji in files, comments, docs, scripts, or note content
- Never write outside `$AGENT_MEMO_VAULT`
- Confirm with the user before delete or bulk move

## License

[MIT](LICENSE) — Copyright (c) 2026 Seven Chan
