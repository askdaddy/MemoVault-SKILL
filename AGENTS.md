# AGENTS.md

This file is the entry point for any coding agent working in this repository.
It defines what the project is, how it is built, and the working process every
change must follow.

Human contributors: read this too. It is the project charter.

---

## 1. Project identity

**MemoVault** is a pure local filesystem skill. It teaches coding agents how to
sink knowledge into an Obsidian vault using bash commands. No Obsidian plugin is
required, and the Obsidian desktop app / CLI is not a runtime dependency: the
helper reads and writes plain markdown directly under `$AGENT_MEMO_VAULT`.
Humans may open the same vault in Obsidian for browsing.

- Skill name: `memovault`
- Knowledge vault (Obsidian vault, optional for browsing): `~/.agent-memo-vault/`
- Vault path override env var: `AGENT_MEMO_VAULT` (default `~/.agent-memo-vault`)
- Canonical skill source after install: `~/.agents/skills/memovault/`
- Heat tiers (no symbols): `seedling`, `growing`, `evergreen`
- Supported platforms: macOS and Linux (bash 3.2 compatible subset); Windows
  via WSL2 running the same bash scripts (no native PowerShell business logic)

## 2. Naming contract (do not deviate)

| Concept | Value |
|---|---|
| Skill name / `name` field | `memovault` |
| Agent skill subdirectory | `memovault/` |
| Skill source dir (home) | `~/.agents/skills/memovault/` |
| Knowledge vault dir | `~/.agent-memo-vault/` |
| Env var (vault path) | `AGENT_MEMO_VAULT` |
| Obsidian registered vault name | `agent-memo-vault` |
| Helper script | `scripts/memovault.sh` |

Hard constraints:
- No emoji anywhere: files, comments, docs, scripts, chat output. Plain text only.
- The skill never writes outside `$AGENT_MEMO_VAULT` (the vault). All vault
  operations resolve this path first.

## 3. Repository layout

```
AGENTS.md              entry point (this file)
CLAUDE.md              pointer to AGENTS.md for Claude Code
README.md              human overview
SKILL.md               canonical skill definition (source of truth, gets installed)
docs/
  ARCHITECTURE.md      single shell layer, data flow
  CLASSIFICATION.md    domain + heat classification scheme
  CLI-REFERENCE.md     optional Obsidian CLI reference (humans; not a runtime dependency)
  DEVELOPMENT.md       how to extend: adapters, phases, vector search slot
  RIPER.md             SDD-RIPER process record (spec + decisions)
  INSTALL.md           per agent install guide
scripts/
  memovault.sh         entry: preflight + subcommand dispatch
  lib/fs.sh            pure filesystem runtime (heredoc, rg/grep, awk)
  lib/rewrite.sh       [[wikilink]] rewriter used by rename
  lib/classify.sh      domain/heat/MOC helpers
install/
  install.sh           installer: --agent <x> | --all | --register-vault
  targets.sh           agent -> {path, adapter, kind} mapping
  adapters/<agent>.md  per agent injection stub templates
templates/
  note.md daily.md moc.md skill.md
VERSION
```

## 4. How the skill works (summary)

The helper `scripts/memovault.sh` exposes subcommands to the agent. There is a
single shell/filesystem runtime: every subcommand reads and writes markdown
directly under `$AGENT_MEMO_VAULT` via `scripts/lib/fs.sh`. `rename` rewrites
`[[wikilinks]]` across the vault via `scripts/lib/rewrite.sh`. There is no
`cli` mode, no Obsidian binary probe, and no GUI launch. `MM_FORCE_FS` is
accepted for backward compatibility but ignored (the runtime is always shell).

Full surface: `preflight`, `new`, `append`, `prepend`, `read`, `distill`,
`daily`, `search`, `recall`, `cite`, `feedback`, `dedupe`, `suggest`, `tags`,
`by-tag`, `backlinks`, `links`, `orphans`, `unresolved`, `move`, `rename`,
`promote`, `supersede`, `moc`, `by-heat`, `health`, `stats`, `eval`,
`ledger:rotate`.

`preflight` prints a single machine readable line:

```
runtime=shell mode=fs vault=<path> search=rg|grep forced=0
```

`mode=fs` and `forced=0` are transitional fields kept for one minor version so
older agent stubs that parse the legacy line do not break; `runtime=shell` is
the authoritative field. They may be removed in a future minor version.

See `SKILL.md` for the agent facing contract and `docs/ARCHITECTURE.md` for internals.

## 5. Working process: SDD-RIPER (mandatory)

Every non trivial change to this repository MUST go through the SDD-RIPER
workflow defined in `docs/RIPER.md`. Summary:

1. **Research** - read the relevant code, docs, and external facts. Do not edit.
2. **Innovate** - compare design alternatives. Record the tradeoffs.
3. **Plan** - produce a concrete spec: files, names, behavior. Get explicit
   user approval before writing.
4. **Execute** - implement exactly the approved plan. Do not expand scope.
5. **Review** - verify the change against the plan and the naming contract.

Rules:
- In Research/Innovate/Plan you may only READ. Ask the user when uncertain; do
  not decide open questions autonomously.
- Do not skip Plan approval. Execution without an approved plan is a violation.
- Respect the naming contract in section 2 and the no-emoji constraint.

## 6. Conventions

- Shell scripts use `#!/usr/bin/env bash` with `set -uo pipefail`. Quote all
  variables. Never use `set -e` inside the helper (fallback logic needs explicit
  error handling).
- Markdown files: lowercase filenames, kebab-case. Headings in sentence case.
- All user facing strings and all comments are written in English. The skill may
  contain a Chinese trigger phrase list in `SKILL.md` because users speak Chinese.
- Dates: ISO 8601 (`YYYY-MM-DD`).

## 7. Pointers

- Architecture and data flow: `docs/ARCHITECTURE.md`
- Classification scheme: `docs/CLASSIFICATION.md`
- CLI reference: `docs/CLI-REFERENCE.md`
- Extending the skill: `docs/DEVELOPMENT.md`
- Install guide: `docs/INSTALL.md`
- Process record and spec history: `docs/RIPER.md`
