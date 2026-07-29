# Architecture

This document describes how MemoVault works internally: the layers, the data
flow, the runtime modes, and the fallback strategy.

## 1. Goals and non goals

Goals:
- Let any coding agent sink knowledge into a local Obsidian vault with bash.
- Require no Obsidian plugin.
- Use the official Obsidian CLI for authoritative graph operations when possible.
- Keep working (read/write/search) when the Obsidian app is not running.

Non goals (this version):
- Vector / semantic search. Slot reserved, not implemented.
- Cloud sync, publishing, multi vault federation.
- A custom daemon or background indexer.

## 2. Layers

```
+-------------------------------------------------------------+
|  Agent (Claude Code, Codex, Cursor, Cline, Gemini, ...)     |
|  reads SKILL.md, calls: scripts/memovault.sh <subcommand>   |
+-------------------------+-----------------------------------+
                          |
          +---------------v---------------+
          |  scripts/memovault.sh         |  dispatch + preflight
          |  scripts/lib/classify.sh      |  domain/heat/MOC
          +---+-----------------------+---+
              |                       |
   +----------v----------+  +---------v----------+
   | lib/cli.sh          |  | lib/fs.sh          |
   | official obsidian   |  | plain markdown +   |
   | CLI wrapper         |  | rg/grep/awk        |
   +----------+----------+  +---------+----------+
              |                       |
              v                       v
   requires: Obsidian app     writes: $AGENT_MEMO_VAULT/**/*.md
   running + CLI registered   (the same files the CLI edits)
```

Both layers operate on the same vault directory. `cli` and `fs` are two ways to
touch the same markdown; they never run a parallel data store.

## 3. Vault resolution

```
AGENT_MEMO_VAULT env var
        |  (unset?)
        v
default: $HOME/.agent-memo-vault
```

Rules:
- All file paths are resolved under `$AGENT_MEMO_VAULT`.
- In `cli` mode the helper `cd "$AGENT_MEMO_VAULT"` before each `obsidian ...`
  call so the CLI auto selects the vault by working directory. The equivalent is
  passing `vault=agent-memo-vault` as the first parameter.
- The vault must be registered in Obsidian (`obsidian.json`) for `cli` mode to
  recognize it. The installer can register it; see `INSTALL.md`.
- At startup the helper sources `env.sh` from the skill source dir, so
  `AGENT_MEMO_VAULT` (and `MM_FORCE_FS`, if set there) apply to every caller
  without each agent exporting them. `install.sh --force-fs` writes
  `MM_FORCE_FS=1` into `env.sh` for persistent headless operation on hosts whose
  `obsidian` binary is the GUI app.

## 4. Runtime mode detection (`preflight`)

`preflight` returns a single machine readable line plus a human summary:

```
mode=cli vault=/Users/me/.agent-memo-vault bin=/usr/local/bin/obsidian app=running forced=0
mode=fs  vault=/Users/me/.agent-memo-vault bin= app=stopped forced=0
mode=fs  vault=/Users/me/.agent-memo-vault bin= app=stopped forced=1
```

Detection order:
1. If `MM_FORCE_FS=1`, short-circuit: `mode=fs`, `forced=1`, no probe runs.
   The Obsidian binary is not located and the app is not probed, so the GUI is
   never launched. This is the headless path.
2. `bin` = first existing of: `command -v obsidian`,
   `/usr/local/bin/obsidian`, `~/.local/bin/obsidian`,
   `/Applications/Obsidian.app/Contents/MacOS/obsidian-cli`.
3. `app` = running if a process named `Obsidian` (macOS) or `obsidian` (Linux)
  is alive (`pgrep`).
4. `mode` = `cli` when both `bin` and `app` are present and the functional
   probe (`obsidian version`, backgrounded with a timeout) succeeds, else `fs`.

Caveat: invoking the CLI when the app is stopped may launch the app and block.
`preflight` therefore probes the process, not the binary, before declaring
`cli` mode. When this side effect is itself undesirable (e.g. the `obsidian`
binary on PATH is actually the GUI app, or the agent must not open windows), set
`MM_FORCE_FS=1` to skip the probe entirely.

## 5. Operation mapping

| Subcommand | cli mode (authoritative) | fs mode (fallback) |
|---|---|---|
| `new` | `obsidian create path= content= template=note` | heredoc write with frontmatter |
| `append` | `obsidian append file= content=` | `cat >>` after last line |
| `prepend` | `obsidian prepend file= content=` | insert after frontmatter via awk |
| `read` | `obsidian read file=` | `cat` |
| `daily` / `daily:append` | `obsidian daily[:append]` | `daily/YYYY-MM-DD.md` |
| `search` | `obsidian search:context query= format=json` | `rg -n` / `grep -rn` |
| `tags` / `tag` | `obsidian tags counts` / `obsidian tag name=` | scan `^tags:` lines |
| `backlinks` | `obsidian backlinks file= counts format=json` | `rg -n "\[\[Title"` |
| `links` | `obsidian links file=` | scan outgoing `[[...]]` |
| `orphans` / `unresolved` | `obsidian orphans` / `obsidian unresolved` | graph scan over `[[...]]` |
| `move` / `rename` | `obsidian move` / `obsidian rename` (links auto update) | `mv` only; links may break |
| `promote` | `obsidian property:set name=heat value=...` + `updated` | awk edit frontmatter |
| `moc` | list domain files, group by heat, write index | same, fs write |
| `by-heat` | `obsidian properties` filter `heat` | scan `^heat:` lines |

## 6. Data flow for a capture

1. Agent runs `preflight`.
2. Agent runs `search`/`backlinks` to dedupe.
3. Agent runs `new <domain> "<Title>"` -> helper writes
   `$VAULT/brain/<domain>/<Title>.md` with frontmatter (`heat: seedling`).
4. Agent runs `append "<Title>" "<body>"` with `[[wikilinks]]`.
5. Optionally `promote` later.

In `cli` mode, steps 3 and 4 go through `obsidian`; in `fs` mode, through the
filesystem. The resulting file is identical in structure.

## 7. Failure handling

- Missing `obsidian` binary or stopped app -> silently use `fs` mode; `preflight`
  reports it.
- Missing `rg` -> fall back to `grep -rn`.
- Invalid frontmatter on `prepend`/`promote` -> the helper aborts with a clear
  message and does not write.
- Write outside vault -> refused by the path resolver.

## 8. Security boundary

- The helper resolves every target path and rejects anything that escapes
  `$AGENT_MEMO_VAULT` (no `../` traversal).
- Destructive subcommands (`delete`) are intentionally absent from the public
  surface in v0.1; removal goes through Obsidian trash in `cli` mode and is not
  exposed in `fs` mode.

## 9. Upgrade flow (self-update)

The skill can update itself from its dev repo without a remote registry. The
upgrade re-syncs the skill source under `~/.agents/skills/memovault/` from the
dev repo and re-injects every agent stub. Vault data (`$AGENT_MEMO_VAULT`) is
never touched.

### Version source resolution

The "dev repo" is the authoritative copy of the skill (this repository). It is
resolved, in priority order:

1. `MEMOVAULT_DEV_REPO` env var if set.
2. `.source-origin`, a one-line file written into the source dir at install time
   (`mm_install_source` records the repo root it copied from).
3. The repository the installer is running from, as a last resort.

The installed `VERSION` is compared to the dev repo `VERSION` with `mm_vercmp`
(semantic, dot-separated). If the dev repo is newer, `preflight` prints an
`update-available <installed> <dev>` hint; `upgrade` performs the re-sync.

### Flow

1. Resolve the dev repo (above).
2. Compare versions; if the dev repo is newer (or `--force`), proceed.
3. If the dev repo is a git repo, run `git pull --ff-only` (skippable with
   `--no-pull`). Git is optional; on failure the installer continues with the
   local files.
4. Re-run `mm_install_source` + `mm_scaffold_vault` + `mm_write_env` + agent
   injection with `FORCE=1`. Idempotent and safe to re-run.

The helper's `upgrade` subcommand simply `exec`s `install.sh --upgrade`, so the
installer is the single code path for both fresh install and upgrade.

## 10. Extension points

- Vector search: a new `lib/vec.sh` plus a `search:vector` subcommand, behind the
  same dispatch. See `DEVELOPMENT.md`.
- New agents: add an entry to `install/targets.sh` and a stub in
  `install/adapters/`. See `DEVELOPMENT.md` and `INSTALL.md`.
