# recall argv + use-loop protocol (0.9.1)

Patch: fix the `q=--limit` footgun; tighten read/cite protocol. No recall
matching change. No health formula change.

## Problem

2026-09-09 vault health: 5 of 28 recalls logged `q=--limit`. `mmfs_recall`
takes `$1` as the query, so `recall --limit 5 "tokens"` searches for the
flag string and hits protocol notes that mention `--limit`.

Use loop: `read_7d=2` vs 24 hits. Protocol says cite when a note affected
the answer, but does not say to `read` first or to skip cite on unused
ritual recall.

## Decision

- `mmfs_recall` walks all argv: known flags anywhere; remaining non-flag
  args join (space) as the query. `--limit` requires a value. Unknown
  `--*` dies. Empty query dies (so `recall --limit 5` is an error).
- Existing `recall "<query>" --limit 5` stays valid.
- Protocol: flags may precede the query; when a hit materially affects
  the answer, `read` then `cite`; unused start-of-turn hits are not cited.
- Vault (user confirmed 2026-09-09): one `promote` each on
  `Memory Loop 0.6.0 产品决策` and `文档默认使用中文` (seedling -> growing).
  Capture one atom documenting the flag-order contract.

## Non-goals

- `search` / `dedupe` argv (same pattern, separate patch)
- `hint=low_use` relaxation / health-honesty 0.8.1 keys
- Auto-promote, evergreen in one step, split `engineering`

## Version

`0.9.0` -> `0.9.1`
