# Architecture

This document describes how MemoVault works internally: the single shell
layer, the data flow, and the wikilink rewrite strategy.

## 1. Goals and non goals

Goals:
- Let any coding agent sink knowledge into a local Obsidian vault with bash.
- Require no Obsidian plugin, no `obsidian` binary, and no running desktop app.
- Provide link-safe `rename` (rewrites `[[wikilinks]]` across the vault) in pure
  shell, so the graph stays consistent without Obsidian.
- Work on macOS, Linux, and Windows via WSL2 from the same bash scripts.

Non goals (this version):
- Vector / semantic search. Slot reserved, not implemented.
- Cloud sync, publishing, multi vault federation.
- A custom daemon or background indexer.
- Native PowerShell business logic for Windows (WSL2 only).
- A perfect Markdown AST (nested fences, inline code containing `[[...]]`).
  The rewriter handles fenced code blocks; inline code is not protected in v1.

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
          +---------------+---------------+
                          |
          +---------------v---------------+
          |  scripts/lib/fs.sh            |  plain markdown +
          |  scripts/lib/rewrite.sh        |  rg/grep/awk + wikilink rewrite
          +---------------+---------------+
                          |
                          v
          writes: $AGENT_MEMO_VAULT/**/*.md
          (the same files humans may browse in Obsidian)
```

There is one runtime layer. The helper never probes for the `obsidian` binary,
never checks whether the Obsidian app is running, and never launches a GUI.
`MM_FORCE_FS` is accepted but ignored (deprecated; the runtime is always shell).

## 3. Vault resolution

```
AGENT_MEMO_VAULT env var
        |  (unset?)
        v
default: $HOME/.agent-memo-vault
```

Rules:
- All file paths are resolved under `$AGENT_MEMO_VAULT`.
- At startup the helper sources `env.sh` from the skill source dir, so
  `AGENT_MEMO_VAULT` applies to every caller without each agent exporting it.
  `install.sh --force-fs` is a no-op kept for backward compatibility; it no
  longer writes anything into `env.sh` because there is nothing to force.
- The vault does NOT need to be registered in Obsidian for the helper to work.
  `install.sh --register-vault` is an optional convenience for humans who want
  to browse the vault in the Obsidian desktop app.

## 4. Preflight

`preflight` returns a single machine readable line plus a source line:

```
runtime=shell mode=fs vault=/Users/me/.agent-memo-vault search=rg forced=0
source=/Users/me/.agents/skills/memovault
```

`runtime=shell` is the authoritative field. `mode=fs` and `forced=0` are
transitional fields kept for one minor version so older agent stubs that parse
the legacy `mode=...` line do not break; they may be removed in a future minor
version. `search` is `rg` if `command -v rg` succeeds, otherwise `grep`. There is
no `bin=` or `app=` field anymore: the helper does not locate or probe Obsidian.

If the installed `VERSION` is older than the dev repo `VERSION`, `preflight`
also prints a `hint: update-available <installed> <dev> (run: memovault
upgrade)` line to stderr.

## 5. Operation mapping

Every subcommand is implemented in `scripts/lib/fs.sh` (with `lib/rewrite.sh`
for `rename` and `lib/obs.sh` for ledger/health). There is no second column
anymore; the table is single-track.

| Subcommand | Implementation |
|---|---|
| `new` | heredoc write with frontmatter under `brain/<domain>/` |
| `append` | `cat >>` after the last line |
| `prepend` | insert after frontmatter via awk |
| `read` | `cat` |
| `distill` | `new` atom/scenario + `sources` + raw pointer |
| `daily` / `daily:append` | legacy `daily/YYYY-MM-DD.md` (not agent L0) |
| `search` | `rg`/`grep` under `brain/`; filters; excludes `kind:raw` by default |
| `recall` | filtered + heat/kind ranked summary lines |
| `cite` | append `event=cite` to `.memovault/ledger.log` |
| `health` / `stats` | L0 vault scan + L1/L2 ledger proxies |
| `ledger:rotate` | trim ledger.log |
| `tags` / `tag` / `by-tag` | scan `^tags:` lines |
| `by-heat` | scan `^heat:` lines, group by tier |
| `backlinks` | `rg -n "\[\[Title"` across the vault (aliases not fully resolved) |
| `links` | scan outgoing `[[...]]` in the note |
| `orphans` / `unresolved` | graph scan of `[[...]]` in `brain/` + `daily/`; `unresolved` treats `daily/YYYY-MM-DD.md` (and vault-relative paths) as resolved |
| `move` | `mv` only; basename preserved so wikilinks stay valid |
| `rename` | `mv` + `lib/rewrite.sh` rewrites `[[wikilinks]]` across the vault and updates the target file's `title:` |
| `promote` | awk edit frontmatter `heat` and `updated` |
| `moc` | list domain files, group by heat, write index |

## 6. Data flow for a capture

1. Agent runs `preflight`.
2. Agent runs `recall`/`search`/`backlinks` to dedupe.
3. Agent runs `new <domain> "<Title>"` -> helper writes
   `$VAULT/brain/<domain>/<Title>.md` with frontmatter (`heat: seedling`).
4. Agent runs `append "<Title>" "<body>"` with `[[wikilinks]]`.
5. Optionally `promote` later.

All four steps go through `lib/fs.sh`. The resulting file is plain markdown
that humans can also open in Obsidian.

## 7. Failure handling

- Missing `rg` -> fall back to `grep -rn`.
- Invalid frontmatter on `prepend`/`promote` -> the helper aborts with a clear
  message and does not write.
- Write outside vault -> refused by the path resolver.
- `rename` after `mv` succeeds but a per-file rewrite fails -> the helper
  returns non-zero and prints the failing path to stderr. The renamed file is
  not rolled back (documented limitation; a later entry may add a retry).

## 8. Security boundary

- The helper resolves every target path and rejects anything that escapes
  `$AGENT_MEMO_VAULT` (no `../` traversal).
- Destructive subcommands (`delete`) are intentionally absent from the public
  surface; removal is left to the user / Obsidian trash when browsing.

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

## 10. Layered memory (protocol)

MemoVault does not run an async L0-L3 pipeline. Layering is a **protocol +
frontmatter** convention on the same markdown vault:

- Optional `kind`: `raw` | `atom` | `scenario` | `persona` | `skill`
- Optional `sources: []` plus body `[[wikilinks]]` for provenance
- Recall budget and heat/kind ranking live in `SKILL.md` / `_protocol.md`
- Spec: `docs/CLASSIFICATION.md` (Memory kinds)

No new runtime layer, daemon, or parallel store. Full-text `search` remains the
default path; vector search stays reserved (section 11 / DEVELOPMENT.md).

## 11. Extension points

- Vector search: a new `lib/vec.sh` plus a `search:vector` subcommand, behind the
  same dispatch. Orthogonal to `kind` / `sources`. See `DEVELOPMENT.md`.
- New agents: add an entry to `install/targets.sh` and a stub in
  `install/adapters/`. See `DEVELOPMENT.md` and `INSTALL.md`.
