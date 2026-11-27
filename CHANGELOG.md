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

### Added

- Archive the v0.10.0 vault self-check in
  [2026-11-26T08-02-44Z.md](docs/health-reports/2026-11-26T08-02-44Z.md),
  with a comparison against the September report and the last pre-upgrade
  snapshot under both calendar-date and rolling 168-hour windows.

## [0.10.0] - 2026-11-26

### Changed

- `health` and `stats` use adjacent rolling 168-hour UTC windows. Existing field
  names and formulas remain available. Reports expose boundaries, ledger
  status, skipped timestamps, and raw counts. Window deltas require matching
  snapshot modes.

### Added

- The read-only recall evaluation includes 20 fixtures, exact title or path
  matching, Top 1 and Top 5, and a separate count of false returns for queries
  with no answer.

- Dated vault self-check reports under `docs/health-reports/` (Chinese), with
  generation rules and a fixed section list in `docs/health-reports/README.md`.
  Filenames use UTC ISO timestamps (`YYYY-MM-DDTHH-MM-SSZ.md`). Instances:
  `2026-09-01T01-56-50Z.md` (0.8.0), `2026-09-08T03-00-48Z.md` (0.9.0),
  `2026-09-09T02-48-17Z.md` (0.9.0), `2026-09-18T03-13-24Z.md` (0.9.1).

## [0.9.1] - 2026-09-09

### Fixed

- `recall` parses `--limit` / `--no-graph` / `--include-superseded` before or
  after the query. `recall --limit 5 "tokens"` no longer logs `q=--limit`.
  `recall --limit N` without a query exits nonzero.

### Changed

- Protocol: when a recall hit materially affects the answer, `read` then
  `cite`. Do not cite unused start-of-turn hits.


## [0.9.0] - 2026-09-04

### Added

- `snip` / `snippet` subcommands for a vault-local CLI snippet library (pet
  semantics: description, command, tags, `<name=default>`). Helper never
  executes stored commands.
- Optional `kind: snippet` (default heat `growing`, home `brain/snippets/`).
- Default `recall` / `search` exclude snippets; `search --include-snippet` and
  `search --kind snippet` include them.
- `health` field `kind_snippet=` (not counted in `kind_other`).

## [0.8.0] - 2026-08-28

### Added

- `recall` token-OR: whitespace tokens are fixed-string matches; notes rank by
  how many tokens hit, then existing graph RRF + heat/kind.
- Ledger `event=recall` field `token_n=`.
- `health` field `wide_query_7d` and `hint=wide_query` (5+ recalls in the
  window with `token_n>=4`).
- `health` efficacy block after `wide_query_7d=`: `moc_count`, `read_7d`,
  `feedback_7d`, `distill_7d`, `use_rate`, `hit_unused_7d`,
  `read_uncited_7d`, token-n buckets (`recall_n1_*` / `recall_n23_*` /
  `recall_n4_*` / `recall_nunk_7d`), previous 7-day window (`*_prev` /
  `recall_hit_rate_prev7d`), `summary=`, `hint=low_use`.
- Vault-local `.memovault/health-snap.log` (keep 200) and `delta_<key>=`
  versus the previous snapshot.
- Eval fixture case `c3` (scattered PERC / copyback / RAID / 换盘 SOP).
- Charter (`AGENTS.md`) requires every agent change to update this changelog
  in the same Execute. `docs/DEVELOPMENT.md` versioning matches.

### Changed

- Protocol: recall with 1-3 distinctive tokens; on miss, retry the shortest
  token then `search`. Installed agents pick this up only after `upgrade`.
- `capture_after_miss_7d` counts a capture only when an earlier miss shares
  title tokens or falls within 30 minutes (no same-UTC-day bagging).
- Default `recall` omits domain MOC indexes (`_*-MOC.md`) so evergreen maps
  cannot crowd out leaf notes after token-OR. `search` and `moc` still list
  them. Use `search` or `moc <domain>` when you want the map.

### Fixed

- `mm_obs_field` now reads the first ledger key (`ts=`) correctly, so `*_7d`
  health windows are real 7-day windows.

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
