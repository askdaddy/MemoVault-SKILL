# Changelog

All notable changes to MemoVault are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses `VERSION` (`MAJOR.MINOR.PATCH`). Breaking changes to the
agent contract bump MINOR at minimum.

Process decisions and RIPER phases live in `docs/RIPER.md`. This file is the
human-facing release log. Every agent change in this repository must add an
entry here in the same Execute (`AGENTS.md` section 5): use `[Unreleased]`
unless `VERSION` also bumps, in which case add `## [x.y.z] - YYYY-MM-DD`.

## [Unreleased]

### Changed

- Charter (`AGENTS.md`) requires every agent change to update this changelog
  in the same Execute. `docs/DEVELOPMENT.md` versioning matches.

## [0.7.2] - 2026-08-14

### Added

- Ledger `event=search` for the public `search` subcommand (unique-note `hits`;
  zero-hit searches still log; `dedupe` internal retrieval is not logged).
- `health` / `stats` fields: `kind_other_pct`, `search_7d`, `recall_hits_7d`,
  `recall_hit_rate`, `capture_after_miss_7d`, `cite_7d`, `recapture_new_dup`.
- Hints: `low_recall_hit_rate`, `capture_after_miss`, `high_kind_other`.
- Charter and guide alignment with the shipped helper (`AGENTS.md`,
  architecture, classification, development).

### Changed

- Protocol / `SKILL.md` Health: prefer the new hints and metrics. Installed
  agents pick this up only after `upgrade`.

### Deprecated

- `cite_rate` and `recapture_dup` keep their original formulas but are marked
  deprecated. Prefer `recall_hit_rate` + `cite_7d` and `recapture_new_dup`.
- `hint=low_cite_rate` is legacy: ignore it when a new hint is present.

## [0.7.1] - 2026-08-11

### Fixed

- `upgrade` copies `install/` into the skill tree so `memovault upgrade` can
  find the installer.
- Upgrade picks the newest complete tree (`VERSION`); tie-break ROOT >
  `.source-origin` > cache.
- Existing `env.sh` is preserved by default; ambient `AGENT_MEMO_VAULT` is not
  baked in on upgrade.
- Version gate: newer upgrades; equal needs `--force`; older refuses unless
  `--force`.

## [0.7.0] - 2026-08-11

### Added

- Optional `status: superseded` and `supersede <old> <new>`.
- Default `search` / `recall` skip superseded notes (`--include-superseded` to
  include).
- `feedback <title> +1|-1` (ledger only).
- `dedupe` and `suggest` (promote / near-duplicate hints; no mutations).
- `recall` one-hop graph neighbors + RRF merge (`--no-graph` to disable).
- `eval` recall hit@k gate on a fixture vault.

## [0.6.1] - 2026-08-11

### Fixed

- `health` L1/L2 semantics: domain counts, `provenance_pct`, `skill_reuse`
  limited to `kind: skill`, soft `hint=` lines.
- e2e coverage for filters, daily exclusion, ledger-write failure, and
  `--verify` without templates.
- Upgrade prefers a newer installer ROOT over a stale curl cache
  `.source-origin`.

## [0.6.0] - 2026-08-10

### Added

- Ranked `recall` (heat/kind; excludes `kind: raw` by default).
- `search` filters: `--domain`, `--kind`, `--heat`, `--include-raw`.
- `cite`, `health` / `stats`, `ledger:rotate`.
- `distill` from raw into `atom` / `scenario` with `sources` and a backlink.
- Ledger at `$AGENT_MEMO_VAULT/.memovault/ledger.log`.

### Changed

- Always-on protocol: recall first, then budgeted `read`, then capture.
- Agent L0 is `kind: raw` (typically `brain/inbox/`), not `daily/`.

### Deprecated

- `daily` / `daily:append` remain for humans; they are not the agent capture
  path.
- Vault `templates/` are optional Obsidian Templates, not the agent write
  source.

## [0.5.1] - 2026-08-05

### Added

- One-line remote install: `curl .../install/install.sh | bash` (no prior
  clone). Syncs `~/.cache/memovault/repo` then re-execs.
- No flags now means `--all` (source + every agent).

## [0.5.0] - 2026-08-04

Breaking: the helper no longer calls the Obsidian CLI.

### Added

- Link-safe `rename` via `scripts/lib/rewrite.sh` (rewrites `[[wikilinks]]`;
  skips fenced code; aliases participate).
- Official platforms: macOS and Linux; Windows via WSL2 only.

### Changed

- Single shell/filesystem runtime. Notes are plain markdown under
  `$AGENT_MEMO_VAULT`.
- `preflight` prints `runtime=shell` (`mode=fs` and `forced=0` are transitional).
- e2e gate is a single shell phase (no Obsidian required).

### Deprecated

- `MM_FORCE_FS` and `install.sh --force-fs` are accepted and ignored.
- `--register-vault` is optional for human browsing only.

### Removed

- `scripts/lib/cli.sh` and all Obsidian binary / GUI probes.

## [0.4.1] - 2026-08-03

### Added

- Optional `kind`: `raw`, `atom`, `scenario`, `persona`, `skill`.
- Distill / provenance protocol (`sources` plus body `[[wikilinks]]`).
- Skill SOP notes under `brain/skills/` (`--kind skill` defaults to `growing`).
- Dual-mode e2e harness and `skills/testing-memovault` (later replaced by the
  0.5.0 single shell gate).

## [0.3.1] - 2026-07-29

### Added

- Installer writes `env.sh`; helper sources it so every caller gets the vault
  path without exporting env vars.
- `install.sh --force-fs` (later a no-op in 0.5.0).

## [0.3.0] - 2026-07-28

### Added

- `MM_FORCE_FS` headless short-circuit (later ignored; runtime is always shell).
- `upgrade` subcommand (re-sync skill source and re-inject adapters).

## [0.1.0] - 2026-07-13

### Added

- Initial skill: capture, search, tags, graph, organize, install adapters,
  always-on memory protocol, self-contained source under
  `~/.agents/skills/memovault/`.
