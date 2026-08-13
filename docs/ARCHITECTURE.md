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
for `rename`, `lib/obs.sh` for ledger/health/suggest, and `lib/eval.sh` for
`eval`). There is no second column
anymore; the table is single-track.

| Subcommand | Implementation |
|---|---|
| `new` | heredoc write with frontmatter under `brain/<domain>/` |
| `append` | `cat >>` after the last line |
| `prepend` | insert after frontmatter via awk |
| `read` | `cat` |
| `distill` | `new` atom/scenario + `sources` + raw pointer |
| `daily` / `daily:append` | legacy `daily/YYYY-MM-DD.md` (not agent L0) |
| `search` | `rg`/`grep` under `brain/`; filters; ledger `event=search` on the public subcommand only |
| `recall` | FTS candidates + optional one-hop neighbors; RRF + heat/kind ranking |
| `cite` / `feedback` | append ledger events |
| `dedupe` | title-normalization near-duplicate candidates |
| `suggest` | promote/dedupe suggestions from ledger + light vault scan |
| `eval` | fixture vault recall hit@k gate |
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
| `supersede` | mark old `status: superseded`; update new `supersedes` + pointers |
| `moc` | list domain files, group by heat, write index |

Ledger file: `$AGENT_MEMO_VAULT/.memovault/ledger.log` (not searchable).
Events include `recall`, `search` (public `search` subcommand only; `dedupe`
internal retrieval is not logged), `read`, `capture`, `cite`, `feedback`,
`promote`, `distill`, `supersede`. `event=search` is independent of
`event=recall` (0.6.0 optionally lumped them; 0.7.2 does not).

`health` / `stats` print L0 vault counts plus L1/L2 ledger proxies. Added in
0.7.2: `kind_other_pct`, `search_7d`, `recall_hits_7d`, `recall_hit_rate`,
`capture_after_miss_7d`, `cite_7d`, `recapture_new_dup`, and hints
`low_recall_hit_rate` / `capture_after_miss` / `high_kind_other`.
`cite_rate` and `recapture_dup` remain with their original formulas
(deprecated).

## 6. Data flow for a capture

1. Agent runs `preflight`.
2. Agent runs `dedupe`/`recall`/`search`/`backlinks` to avoid duplicates.
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

Upgrade picks the **newest complete tree** (strategy B):

1. `MEMOVAULT_DEV_REPO` if set and `mm_is_full_tree`.
2. Else refresh `~/.cache/memovault/repo` best-effort, then choose the newest
   `VERSION` among installer `ROOT`, `$SOURCE/.source-origin`, and the cache.
   Ties: ROOT > origin > cache.

Helpers live in `install/lib/resolve.sh` (copied into the skill install). The
helper `upgrade` subcommand locates `install/install.sh` under the skill,
`.source-origin`, or the cache, then `exec`s `--upgrade`.

Version gate (`mm_vercmp`): newer → upgrade; equal → need `--force`; older →
refuse unless `--force`.

`env.sh`: preserved on upgrade unless `--vault` / `--reset-env`. Ambient
`AGENT_MEMO_VAULT` is not baked into `env.sh` during upgrade.

### Flow

1. Pick upgrade tree (above); log `upgrade: picked=...`.
2. Compare versions; apply the gate.
3. Optional `git pull` on the picked tree (`--no-pull` skips).
4. Re-run `mm_install_source` (includes `install/`) + scaffold + conditional
   `mm_write_env` + agent injection with `FORCE=1`.

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
