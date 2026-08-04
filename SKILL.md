---
name: memovault
version: 0.4.1
description: "Sink knowledge into a local Obsidian vault with bash. Use when the user wants to capture, save, record, or sink knowledge, notes, learnings, decisions, meeting takeaways, code snippets, or research into their memo vault / second brain / Obsidian knowledge base; or to create, edit, link, search, classify by domain, promote by heat, distill raw notes, or maintain backlinks, daily notes, and skill SOPs. Trigger phrases: 记到笔记 / 记一下 / 笔记里记一下 / 沉淀 / 沉淀一下 / 存到 vault / 存一下 / 存档 / 存到知识库 / 知识库 / 备忘录 / 双链 / 回链 / 按领域归档 / 提升热度 / 日记 / 每日笔记 / remember this / save this / save to vault / save to notes / memo it / note this / capture this / second brain / knowledge base / daily note / backlinks / link this note."
---

# MemoVault

Sink knowledge into a local Obsidian vault using bash. No Obsidian plugin needed.
Depends on the official Obsidian CLI (https://obsidian.md/cli) when the desktop
app is running; falls back to pure filesystem operations when it is not.

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

# Force fs mode: skip the Obsidian CLI probe entirely so the GUI never launches.
# Set to 1 for silent/headless runs, or when the CLI binary is absent.
export MM_FORCE_FS="${MM_FORCE_FS:-0}"

# Helper location (repo during development, home after install)
MM="$HOME/.agents/skills/memovault/scripts/memovault.sh"
[ -x "$MM" ] || MM="./scripts/memovault.sh"   # fall back to repo copy
```

Everything below assumes `$MM` points at the helper and `$AGENT_MEMO_VAULT` is set.

The helper sources `env.sh` (`~/.agents/skills/memovault/env.sh`) at startup, so
variables pinned there apply to every caller without each agent exporting them.
To persistently run headless on a host whose `obsidian` binary is the GUI app
(not a real `obsidian-cli`), write `MM_FORCE_FS=1` there once:

```bash
install/install.sh --force-fs   # writes MM_FORCE_FS=1 into env.sh (re-run on upgrade)
```

## 2. Preflight (run once per session)

```bash
"$MM" preflight
```

Output reports: resolved vault path, whether the `obsidian` binary exists, whether
the Obsidian app is running, the active mode (`cli` or `fs`), and whether fs mode
was forced. Use the reported mode to set expectations:

- `cli` mode: backlinks, link safe move/rename, tags, properties, and search are
  native and authoritative.
- `fs` mode: write/read/search still work; backlinks and tag queries are
  approximated by scanning `[[wikilinks]]` and frontmatter; `move`/`rename` will
  NOT auto update links, so warn the user.

If `cli` mode is unavailable and the user wants link graph features, tell them to
start Obsidian (and, once, enable Settings -> General -> Command line interface on
Obsidian 1.12.7 or newer).

To run fully headless (never launch the Obsidian GUI), set `MM_FORCE_FS=1` before
calling the helper. The probe is skipped entirely and `preflight` reports
`forced=1`. This is the recommended setting when the CLI binary is absent or when
the agent must not open windows.

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
- `move`/`rename` in `cli` mode updates all `[[links]]` automatically; in `fs`
  mode they do not, so prefer `cli` mode for reorganization.

## 5. Operations (helper subcommands)

All subcommands are invoked as `"$MM" <subcommand> [args...]`. They auto select
`cli` or `fs` implementation.

### Capture / edit

```bash
# New note in a domain (creates frontmatter, places under brain/<domain>/)
"$MM" new <domain> "<Title>" [--tags a,b] [--kind atom] [--body "initial text"]

# Append / prepend / read an existing note (by title or path)
"$MM" append "<Title>" "<markdown to add>"
"$MM" prepend "<Title>" "<markdown to add>"   # inserted after frontmatter
"$MM" read "<Title>"

# Daily note
"$MM" daily                      # show today's daily note path/contents
"$MM" daily:append "- [ ] task"  # append to today's daily note
```

### Retrieve

```bash
"$MM" search "<query>"                 # full text; grep style path:line: text
"$MM" search "<query>" --limit 20
"$MM" tags                             # all tags with counts
"$MM" tag "<tag>"                      # notes bearing a tag
"$MM" by-tag "<tag>"
"$MM" by-heat                          # notes grouped by heat tier
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
"$MM" move "<Title>" "<new-folder-or-path>"   # link safe in cli mode
"$MM" rename "<Title>" "<New Title>"
"$MM" promote "<Title>"                       # seedling->growing->evergreen
"$MM" moc "<domain>"                          # (re)generate domain index note
```

### Low level (when the helper is not enough)

You may call the Obsidian CLI directly. Always `cd "$AGENT_MEMO_VAULT"` first so
the right vault is selected, or pass `vault=agent-memo-vault` as the first param.

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
1. Run one `search "<narrow keywords>"` (prefer `--limit 10` or tighter).
2. Rank hits: prefer `heat: evergreen` then `growing`; prefer
   `kind: persona|scenario|skill|atom` over `raw` / pure `daily/` noise.
3. Progressive disclosure: use titles/snippets first; `read` at most **3** notes
   per task (usually 1). Weave relevant knowledge into the answer and cite the
   vault note when it materially affects the answer.
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

- Raw capture (`daily/` lines, `kind: raw`, or inbox) is L0 evidence, not the
  end state.
- When durable knowledge appears, create or update an `atom` or `scenario` note.
  Set `sources: ["YYYY-MM-DD"]` (or note titles) **and** body wikilinks back to
  the raw note. Canonical daily link: `[[YYYY-MM-DD]]` (path form
  `daily/YYYY-MM-DD.md` also works with `read` / `locate`).
- Optionally leave a one-line pointer on the daily note linking to the new atom.
- Never delete raw evidence without explicit user consent.
- `kind: persona` is rare (stable preferences / hard constraints). Do not start
  as `evergreen` unless the user confirms; otherwise seedling and suggest
  `promote` later.

### Skill capture (SOPs)

When the turn produced a reusable how-to that would save future turns:
1. Propose `skills/<Title>` with `--kind skill`, or write immediately on explicit
   remember phrases.
2. Structure the body like `templates/skill.md`: Trigger, Steps, Verify, Related.
3. Link related domain atoms/scenarios with `[[wikilinks]]`.

## 7. Suggested capture flow

1. `preflight` once.
2. Decide the domain, optional `kind`, and a concise human readable title.
3. `search "<keywords>"` and `backlinks` to check for an existing note; prefer to
   `append` to an existing note over creating a duplicate.
4. `new <domain> "<Title>"` with `--tags` and optional `--kind`, then `append`
   the body, or pass `--body`.
5. Add `[[wikilinks]]` and `sources` when distilling; create linked notes as
   `seedling` if they do not exist yet.
6. If the note is clearly important, suggest `promote`.

## 8. fs mode notes

When the helper reports `fs` mode:
- Notes are plain markdown files under `$AGENT_MEMO_VAULT/brain/<domain>/`.
- `search` uses `ripgrep` (`rg`), falling back to `grep -rn`.
- `backlinks`/`links` scan for `[[Title]]` text (approximate; aliases not fully
  resolved).
- `move`/`rename` move the file only; existing `[[links]]` may break. Warn the
  user and offer to run a follow up `search` to fix stale links when `cli` mode
  returns.

fs mode can be forced with `MM_FORCE_FS=1` (see section 1). Forced mode skips the
CLI probe entirely, so the Obsidian GUI is never launched. This is the
recommended way to run the skill on hosts where the CLI binary is absent or where
opening a window is undesirable. The tradeoff is that link graph features stay
approximated even if Obsidian is later started; unset `MM_FORCE_FS` and re-run
`preflight` to re-detect `cli` mode.

## 9. Safety

- Destructive ops (`delete`, bulk `move`) require explicit user confirmation.
- The helper never deletes permanently unless asked; Obsidian trash is used in
  `cli` mode.
- Keep frontmatter valid YAML. Use the helper (`new`, `promote`) or
  `property:set` rather than hand editing when possible.

## 10. Out of scope (this version)

- Vector / semantic search: deferred. The architecture reserves a slot; see
  `docs/DEVELOPMENT.md`. For now use full text `search` plus tags and backlinks.
- Obsidian Sync, Publish, Bases, plugins: not exposed by this skill.
