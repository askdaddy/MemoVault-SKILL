# AGENTS.md

This file is the entry point for any coding agent working in this repository.
It defines what the project is, how it is built, and the working process every
change must follow.

Human contributors: read this too. It is the project charter.

---

## 1. Project identity

**MemoVault** is a pure local filesystem skill. It teaches coding agents how to
sink knowledge into an Obsidian vault using bash commands. No Obsidian plugin is
required. It depends on the official Obsidian CLI (https://obsidian.md/cli) when
the Obsidian desktop app is running, and falls back to plain filesystem
operations when it is not.

- Skill name: `memovault`
- Knowledge vault (Obsidian vault): `~/.agent-memo-vault/`
- Vault path override env var: `AGENT_MEMO_VAULT` (default `~/.agent-memo-vault`)
- Canonical skill source after install: `~/.agents/skills/memovault/`
- Heat tiers (no symbols): `seedling`, `growing`, `evergreen`

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
  ARCHITECTURE.md      CLI/FS dual layer, data flow, fallback strategy
  CLASSIFICATION.md    domain + heat classification scheme
  CLI-REFERENCE.md     Obsidian CLI quick reference (curated)
  DEVELOPMENT.md       how to extend: adapters, phases, vector search slot
  RIPER.md             SDD-RIPER process record (spec + decisions)
  INSTALL.md           per agent install guide
scripts/
  memovault.sh         entry: preflight + mode detection + subcommand dispatch
  lib/cli.sh           Obsidian CLI wrapper + availability probe
  lib/fs.sh            pure filesystem fallback (heredoc, rg/grep)
  lib/classify.sh      domain/heat/MOC helpers
install/
  install.sh           installer: --agent <x> | --all | --register-vault
  targets.sh           agent -> {path, adapter, kind} mapping
  adapters/<agent>.md  per agent injection stub templates
templates/
  note.md daily.md moc.md
VERSION
```

## 4. How the skill works (summary)

The helper `scripts/memovault.sh` exposes subcommands to the agent. Each
subcommand detects the runtime mode and chooses the best implementation:

- **cli mode**: the `obsidian` binary is on PATH and the Obsidian app is
  running. Operations go through the official CLI, which gives backlink graph
  resolution, link safe move/rename, tags, properties, and native search.
- **fs mode**: fallback. Operations write markdown directly under
  `$AGENT_MEMO_VAULT` and use `rg`/`grep` for retrieval. Wikilink backlinks are
  approximated by scanning `[[link]]` text.

Full surface: `preflight`, `new`, `append`, `prepend`, `read`, `daily`,
`search`, `tags`, `by-tag`, `backlinks`, `links`, `orphans`, `unresolved`,
`move`, `rename`, `promote`, `moc`, `by-heat`.

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
