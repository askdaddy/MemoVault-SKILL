# Development guide

How to extend MemoVault: add a target agent, add a subcommand, or build a later
phase (vector search).

## 1. Working process

Every non trivial change follows SDD-RIPER (see `RIPER.md`):
Research -> Innovate -> Plan -> Execute -> Review. Do not execute without an
approved plan. Respect the naming contract in `AGENTS.md` section 2 and the
no-emoji rule.

## 2. Repository layout recap

- `SKILL.md` is the single source of truth for the agent contract. Installed
  copies are pointer stubs.
- `scripts/memovault.sh` + `scripts/lib/*.sh` implement the behavior.
- `install/install.sh` + `install/targets.sh` + `install/adapters/*.md` handle
  per agent installation.
- `templates/` are Obsidian Templates files used by `create template=`.
- `docs/` are specs for humans and deeper agent context.

## 3. Adding a subcommand

1. Add the dispatch branch in `scripts/memovault.sh` (`mm_dispatch`).
2. Implement `cli` path in `scripts/lib/cli.sh` and `fs` path in
   `scripts/lib/fs.sh`. Both must write the same on disk format.
3. If it touches classification, add a helper in `scripts/lib/classify.sh`.
4. Document it in `SKILL.md` (section 5) and the mapping table in
   `docs/ARCHITECTURE.md` (section 5).
5. Keep the path resolver (`mm_vault_path`) in front of every write so nothing
   escapes `$AGENT_MEMO_VAULT`.

Conventions:
- `set -uo pipefail`. Quote variables. Never `set -e` inside the helper.
- Print machine readable results to stdout; print diagnostics to stderr.
- Return non zero on hard failure; degrade gracefully where possible.
- Bash 3.2 compatible (the shebang is `#!/usr/bin/env bash`; macOS still ships
  3.2). Avoid: associative arrays, `${v,,}`, `mapfile`/`readarray`, and `case`
  patterns that put a `[...]` glob class immediately before a space (it fails to
  parse in 3.2). Quote literal text inside patterns, e.g. `*"not found"*`.

## 4. Adding a target agent

1. Determine the agent's rules/skill location (personal/global path) and the file
   format it expects (SKILL.md with frontmatter, an `AGENTS.md`/`GEMINI.md`
   append block, a `.mdc`/rules file, etc.).
2. Add an entry to `install/targets.sh`:
   ```bash
   mm_target_<agent>='path|adapter|kind'
   ```
   where `kind` is `skill` (drop a SKILL.md), `rules` (drop a rules file), or
   `agents` (append a block to an AGENTS.md style file).
3. Write `install/adapters/<agent>.md` using placeholders:
   - `__MEMOVAULT_SOURCE__`  -> skill source dir
   - `__MEMOVAULT_VAULT__`   -> vault path
   - `__MEMOVAULT_HELPER__`  -> helper script path
4. Test with `./install/install.sh --agent <agent> --dry-run`.
5. Document in `docs/INSTALL.md`.

Adapters default to a pointer stub (small file that tells the agent where the
canonical `SKILL.md` lives). Pass `--inline` to `install.sh` to embed the full
`SKILL.md` instead, for agents that do not follow cross-file references.

## 5. Phase 2: vector / semantic search (reserved, not built)

Goal: add `search:vector "<query>"` that returns semantically similar notes.

Reserved seam:
- A new `scripts/lib/vec.sh` behind the same dispatcher in `memovault.sh`.
- An index stored under `$AGENT_MEMO_VAULT/.memovault/vec/` (gitignored concept;
  never mixed into `brain/`).
- A reindex trigger after `new`/`append`/`move`/`rename`.

Candidate stack (decide at Plan time, not now):
- Embeddings: a local model (e.g. via `ollama`) or an API.
- Store: `sqlite-vec`, `lancedb`, or a plain `.jsonl` + cosine in awk/node.
- The CLI has no vector support, so this layer is fs/index only and must not
  depend on the Obsidian app running.

Constraints to honor when built:
- No network requirement at query time if a local model is used; or clearly mark
  an API dependency and gate behind a setting.
- Keep full text `search`, `tags`, and `backlinks` as the always-available path.
- Respect the no-emoji and never-write-outside-vault rules.

## 6. Testing

There is no test harness in v0.1. Manual checklist before shipping a change:

1. `bash -n scripts/memovault.sh scripts/lib/*.sh install/install.sh` parses.
2. `./scripts/memovault.sh preflight` reports mode correctly with app running and
   stopped.
3. `new` then `read` then `search` round trips in both `cli` and `fs` modes.
4. `promote` updates `heat` and `updated` without corrupting frontmatter.
5. A path like `../escape` is rejected.

## 7. Versioning

- `VERSION` holds `MAJOR.MINOR.PATCH`.
- Breaking changes to the agent contract (subcommand names, frontmatter shape)
  bump MINOR at minimum and are recorded in `docs/RIPER.md`.
