---
name: memovault
version: 0.7.0
description: "Sink knowledge into a local Obsidian vault with bash. Use when the user wants to capture, save, record, or sink knowledge, notes, learnings, decisions, meeting takeaways, code snippets, or research into their memo vault / second brain / Obsidian knowledge base; or to create, edit, link, search, classify by domain, promote by heat, distill raw notes, recall ranked context, check vault health, or maintain backlinks and skill SOPs. Trigger phrases: 记到笔记 / 记一下 / 笔记里记一下 / 沉淀 / 沉淀一下 / 存到 vault / 存一下 / 存档 / 存到知识库 / 知识库 / 备忘录 / 双链 / 回链 / 按领域归档 / 提升热度 / 日记 / 每日笔记 / remember this / save this / save to vault / save to notes / memo it / note this / capture this / second brain / knowledge base / daily note / backlinks / link this note."
---

# MemoVault

Sink knowledge into a local Obsidian vault using bash. No Obsidian plugin
needed, and the Obsidian desktop app / CLI is not a runtime dependency: the
helper reads and writes plain markdown directly under `$AGENT_MEMO_VAULT`.
Humans may open the same vault in Obsidian for browsing.

This file is the canonical skill definition. Installed copies under agent skill
directories are pointer stubs that redirect here.

## 0. Hard rules

- No emoji anywhere in output, filenames, note content, or frontmatter.
- Never write outside the vault (`$AGENT_MEMO_VAULT`, default `~/.agent-memo-vault`).
- Always run preflight before the first vault operation in a session.
- Heat values are exactly one of: `seedling`, `growing`, `evergreen`.
- Optional `kind` is exactly one of: `raw`, `atom`, `scenario`, `persona`, `skill`.
- Confirm with the user before deleting or bulk moving notes.

## 1. Resolve the vault and the helper

The skill ships a helper script. After install it lives at
`~/.agents/skills/memovault/scripts/memovault.sh`. In this repo it is at
`scripts/memovault.sh`.

```bash
# Vault path (override per user; default below)
export AGENT_MEMO_VAULT="${AGENT_MEMO_VAULT:-$HOME/.agent-memo-vault}"

# MM_FORCE_FS is deprecated and ignored: the runtime is always shell, so there
# is nothing to force. The line is kept only for backward compatibility with
# older env.sh files; you can remove it.
export MM_FORCE_FS="${MM_FORCE_FS:-0}"

# Helper location (repo during development, home after install)
MM="$HOME/.agents/skills/memovault/scripts/memovault.sh"
[ -x "$MM" ] || MM="./scripts/memovault.sh"   # fall back to repo copy
```

Everything below assumes `$MM` points at the helper and `$AGENT_MEMO_VAULT` is set.

The helper sources `env.sh` (`~/.agents/skills/memovault/env.sh`) at startup, so
variables pinned there apply to every caller without each agent exporting them.
`install.sh --force-fs` is a no-op kept for backward compatibility; the runtime
is always shell, so there is nothing to force.

## 2. Preflight (run once per session)

```bash
"$MM" preflight
```

Output reports: `runtime=shell`, the resolved vault path, and the search backend
(`rg` or `grep`). The line looks like:

```
runtime=shell mode=fs vault=<path> search=rg forced=0
```

`runtime=shell` is the authoritative field. `mode=fs` and `forced=0` are
transitional fields kept for one minor version so older agent stubs that parse
the legacy `mode=...` line do not break; they may be removed in a future minor
version. There is no `cli` mode, no `obsidian` binary probe, and no GUI launch.

The helper always uses the same shell/filesystem implementation, so behavior is
identical across hosts. Wikilink graph features (backlinks, links, orphans,
unresolved) are approximated by scanning `[[wikilinks]]` and frontmatter;
`rename` rewrites `[[wikilinks]]` across the vault so the graph stays consistent
without Obsidian.

### Update and upgrade

`preflight` also checks for skill updates: it compares the installed `VERSION`
against the dev repo's `VERSION` (auto-detected from `.source-origin`, or set
`MEMOVAULT_DEV_REPO`). If the dev repo is newer, a hint line reads
`hint: update-available <installed> <dev> (run: memovault upgrade)`. Run the
upgrade to re-sync the skill source from the dev repo and re-inject every agent
stub:

```bash
"$MM" upgrade            # re-sync source + re-inject agents
"$MM" upgrade --no-pull  # skip the `git pull` step in the dev repo
```

The upgrade delegates to `install.sh --upgrade`. It is idempotent and safe to
re-run. If the dev repo is a git repo it pulls first (`--ff-only`); pass
`--no-pull` to skip that. The vault data (`$AGENT_MEMO_VAULT`) is never touched
by upgrade.

## 3. Classification scheme (follow exactly)

Every note carries frontmatter:

```yaml
---
title: Human Readable Title
domain: <area>            # one domain; maps to a folder under brain/<domain>/
kind: atom                 # optional: raw | atom | scenario | persona | skill
tags: [tag-a, tag-b]       # freeform; nested tags allowed as parent/child
heat: seedling             # seedling | growing | evergreen
status: active             # optional: active | superseded (omit = active)
supersedes: []             # optional; titles this note replaces
aliases: []                # alternate names; improves [[wikilink]] resolution
sources: []                # optional; required when distilled from raw/daily
created: 2026-07-13
updated: 2026-07-13
---
```

- **Domain**: the primary area. Stored both as a folder (`brain/<domain>/`) and
  as the `domain` property so search works without path assumptions.
- **Kind** (optional): layered memory role. Prefer `atom`/`scenario`/`skill`/
  `persona` over `raw` when recalling. Skill SOPs live under `brain/skills/`.
  See `docs/CLASSIFICATION.md`.
- **Status** (optional): `active` (default) or `superseded`. Default
  `search`/`recall` skip superseded notes; use `supersede <old> <new>` to mark.
- **Heat**: maturity/popularity.
  - `seedling` - just captured, unrefined.
  - `growing` - linked to other notes, being developed.
  - `evergreen` - mature, well linked, frequently referenced.
- **Promotion heuristic**: when `backlinks` count for a note crosses thresholds
  (>=2 incoming links -> consider `growing`; >=5 or user curated -> `evergreen`),
  suggest promotion. The user always confirms.
- See `docs/CLASSIFICATION.md` for the full scheme.

## 4. Wikilinks and backlinks (the core)

Backlinks are the point of using Obsidian. Prefer wikilinks over prose:

```markdown
See [[Human Readable Title]] and its alias [[Short Name]].
```

- `new` always picks a human readable, unique title and sets `aliases` for short
  names so `[[Short Name]]` resolves.
- Use `backlinks <note>` to find what references a note before editing or merging.
- Use `orphans` and `unresolved` periodically to keep the graph healthy.
- `rename` rewrites `[[wikilinks]]` across the vault (link-safe). `move` does
  not change the basename, so existing `[[links]]` stay valid; prefer `rename`
  for any title change and `move` for folder changes.

## 5. Operations (helper subcommands)

All subcommands are invoked as `"$MM" <subcommand> [args...]`. They use the
single shell/filesystem implementation in `scripts/lib/fs.sh`.

### Capture / edit

```bash
# New note in a domain (creates frontmatter, places under brain/<domain>/)
"$MM" new <domain> "<Title>" [--tags a,b] [--kind atom] [--body "initial text"]

# Distill raw evidence into atom|scenario (sets sources + wikilink + raw pointer)
"$MM" distill "<Raw Title>" <domain> "<Title>" [--kind atom]

# Append / prepend / read an existing note (by title or path)
"$MM" append "<Title>" "<markdown to add>"
"$MM" prepend "<Title>" "<markdown to add>"   # inserted after frontmatter
"$MM" read "<Title>"

# Daily note (legacy / human Obsidian habit; not the agent L0 path)
"$MM" daily                      # show today's daily note path/contents
"$MM" daily:append "- [ ] task"  # append to today's daily note
```

### Retrieve

```bash
"$MM" search "<query>"                 # brain/ full text; excludes kind:raw + superseded by default
"$MM" search "<query>" --limit 20 [--domain d] [--kind k] [--heat h] \
  [--include-raw] [--include-superseded]
"$MM" recall "<query>" [--limit 5] [--no-graph] [--include-superseded]
                                       # ranked + one-hop graph RRF (prefer for recall)
"$MM" cite "<Title>"                   # record that a note was used in an answer
"$MM" feedback "<Title>" +1|-1         # explicit reinforce signal (ledger only)
"$MM" dedupe "<query-or-title>"        # near-duplicate candidates before new/append
"$MM" suggest                          # promote/dedupe suggestions (no mutations)
"$MM" tags                             # all tags with counts
"$MM" tag "<tag>"                      # notes bearing a tag
"$MM" by-tag "<tag>"
"$MM" by-heat                          # notes grouped by heat tier
"$MM" health                           # L0-L2 proxy metrics (alias: stats)
"$MM" eval [--fixture dir] [--limit 5] # recall hit@k gate on fixture vault
"$MM" ledger:rotate [--keep 5000]      # trim .memovault/ledger.log
```

### Graph

```bash
"$MM" backlinks "<Title>"              # notes linking TO this note
"$MM" links "<Title>"                  # notes this note links to
"$MM" orphans                          # notes with no incoming links
"$MM" unresolved                       # [[links]] that point nowhere yet
```

### Organize / curate

```bash
"$MM" move "<Title>" "<new-folder-or-path>"   # filesystem move; basename preserved so links stay valid
"$MM" rename "<Title>" "<New Title>"          # link-safe: rewrites [[wikilinks]] across the vault
"$MM" promote "<Title>"                       # seedling->growing->evergreen
"$MM" supersede "<Old Title>" "<New Title>"   # mark old superseded; keep history
"$MM" moc "<domain>"                          # (re)generate domain index note
```

### Low level (when the helper is not enough)

For humans using Obsidian: you may call the Obsidian CLI directly to browse or
edit the vault. Always `cd "$AGENT_MEMO_VAULT"` first so the right vault is
selected, or pass `vault=agent-memo-vault` as the first param. The helper itself
does NOT call this CLI; this is purely optional for human browsing.

```bash
cd "$AGENT_MEMO_VAULT"
obsidian create name="Trip Plan" content="..." template=note
obsidian search:context query="status::active" format=json
obsidian backlinks file="Trip Plan" counts format=json
obsidian property:set name=heat value=evergreen path="brain/travel/Trip Plan.md"
```

See `docs/CLI-REFERENCE.md` for the curated command list.

## 6. Memory protocol (auto recall, semi-auto capture)

This skill is meant to be always on, not only triggered by an explicit
"remember" command. Follow this protocol every turn.

### Recall (automatic)

At the start of answering a user request:
1. Run one `recall "<narrow keywords>"` (prefer `--limit 5`). Fall back to
   `search` if needed.
2. Helper excludes `kind: raw` and ranks by heat/kind. Progressive disclosure:
   use titles/snippets first; `read` at most **3** notes per task (usually 1).
3. When a note materially affects the answer, run `cite "<title>"` and mention
   the note briefly.
4. If the vault is empty or nothing matches, skip silently (do not narrate).

### Capture (semi-automatic)

When the turn produced durable knowledge (a decision, fix or lesson, how-to,
design rationale, or non-obvious fact):
1. Propose first: "I can save this to <domain>/<title> (kind: atom|scenario),
   linking [[related]]. Do it?"
2. On confirmation: `new <domain> "<title>" --kind atom --tags ... --body "..."`,
   then add `[[wikilinks]]` and short `aliases`. Default heat is `seedling`
   (`skill` notes default to `growing`).
3. If the user explicitly says "remember this" / "save this" / "note this" /
   "capture this" / "记一下" / "记下来" / "帮我记一下" / "沉淀一下" /
   "存一下" / "存到笔记" / "记到知识库", capture
   immediately, then confirm what you saved.
4. Do not capture small talk, transient debug output, or anything not worth
   searching for later.

### Distill and provenance

- L0 evidence is `kind: raw` (typically `brain/inbox/`). `daily/` is legacy for
  humans only; do not use it as the default agent capture path.
- Prefer `distill "<raw>" <domain> "<Title>" --kind atom|scenario`, or create
  an atom/scenario with `sources` and body `[[raw-title]]`.
- Never delete raw evidence without explicit user consent.
- `kind: persona` is rare (stable preferences / hard constraints). Do not start
  as `evergreen` unless the user confirms; otherwise seedling and suggest
  `promote` later.

### Skill capture (SOPs)

When the turn produced a reusable how-to that would save future turns:
1. Propose `skills/<Title>` with `--kind skill`, or write immediately on explicit
   remember phrases.
2. Structure the body: Trigger, Steps, Verify, Related (see CLASSIFICATION /
   protocol; vault `templates/` are optional for humans only).
3. Link related domain atoms/scenarios with `[[wikilinks]]`.

### Health (self-check)

When the user asks about memory health, or inbox/raw is piling up, run `health`
and/or `suggest` and act on `hint=` / `suggest=` lines (`provenance_pct` /
`cite_rate` / `orphan_pct` / `superseded_count`). Confirm before `promote`.
Do not silently rewrite the vault.

When knowledge is replaced, prefer `supersede "<Old>" "<New>"` over deleting.
Before creating a note, run `dedupe "<title>"` and prefer `append` on hits.

## 7. Suggested capture flow

1. `preflight` once.
2. Decide the domain, optional `kind`, and a concise human readable title.
3. `dedupe` / `search` / `backlinks` to check for an existing note; prefer to
   `append` to an existing note over creating a duplicate.
4. `new <domain> "<Title>"` with `--tags` and optional `--kind`, then `append`
   the body, or pass `--body`.
5. Add `[[wikilinks]]` and `sources` when distilling; create linked notes as
   `seedling` if they do not exist yet.
6. If the note is clearly important, suggest `promote`.

## 8. Shell runtime notes

The helper always runs in the single shell/filesystem runtime:

- Notes are plain markdown files under `$AGENT_MEMO_VAULT/brain/<domain>/`.
- `search` uses `ripgrep` (`rg`), falling back to `grep -rn`.
- `backlinks`/`links` scan for `[[Title]]` text (approximate; aliases not fully
  resolved).
- `rename` rewrites `[[wikilinks]]` across the vault (link-safe) via
  `scripts/lib/rewrite.sh`. Fenced code blocks (``` ``` ```) are skipped; inline
  code containing `[[...]]` is not protected in v1 and may be rewritten by
  accident (documented limitation).
- `move` only changes the folder/path and preserves the basename, so existing
  `[[links]]` stay valid.

`MM_FORCE_FS` is accepted for backward compatibility but ignored: the runtime is
always shell, so there is nothing to force. The helper prints a one-line
deprecation warning if it sees `MM_FORCE_FS=1`.

## 9. Safety

- Destructive ops (`delete`, bulk `move`) require explicit user confirmation.
- The helper never deletes permanently unless asked; deletion is left to the
  user / Obsidian trash when browsing.
- Keep frontmatter valid YAML. Use the helper (`new`, `promote`) rather than
  hand editing when possible.

## 10. Out of scope (this version)

- Vector / semantic search: deferred. The architecture reserves a slot; see
  `docs/DEVELOPMENT.md`. For now use `recall` / full text `search` plus tags and
  backlinks.
- Obsidian Sync, Publish, Bases, plugins: not exposed by this skill.
- Human-rated answer quality scores: `health` uses proxy metrics only
  (cite_rate, skill_reuse, promote_rate, recapture_dup).
