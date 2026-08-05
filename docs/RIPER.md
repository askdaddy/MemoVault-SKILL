# SDD-RIPER process record

This is the spec-driven process record for MemoVault. SDD = Spec-Driven
Development. RIPER = the five phases every change moves through: Research,
Innovate, Plan, Execute, Review.

It is both the methodology charter and the running log of decisions.

## 1. The workflow

```
Research  ->  Innovate  ->  Plan  ->  Execute  ->  Review
  read only    compare       spec        implement    verify
               options       (approved)  exactly      vs plan
```

Phase rules:
- **Research**: read code, docs, external facts. No edits. Ask when uncertain.
- **Innovate**: enumerate design alternatives and tradeoffs. No edits.
- **Plan**: produce a concrete spec (files, names, behavior). Must be approved by
  the user before any write. This is the "Spec" in SDD.
- **Execute**: implement exactly the approved plan. No scope creep.
- **Review**: verify against the plan, the naming contract (`AGENTS.md` section
  2), and the no-emoji rule.

Hard rules:
- Research/Innovate/Plan are read only. Execution without an approved plan is a
  violation.
- Open questions go to the user; the agent does not decide them autonomously.
- Every phase's output is recorded below as an entry.

## 2. Entry template

Append a new entry per change:

```
### YYYY-MM-DD - <short title>
- Research: <what was read, key facts>
- Innovate: <options considered, tradeoffs>
- Plan: <approved spec: files, names, behavior>
- Execute: <what was written, files touched>
- Review: <verification result, deviations>
```

## 3. Foundational entry: project creation (2026-07-13)

### Research
- Read existing skills in `~/.agents/skills/` (lark-*, byted-ark-seedream) to
  learn the SKILL.md convention: YAML frontmatter (`name`, `version`,
  `description`), optional `references/` and `scripts/`, `package.json`,
  `INSTALL.md`.
- Pulled the official Obsidian CLI reference from
  `help.obsidian.md/Extending Obsidian/Obsidian CLI.md` (saved locally as
  `/tmp/obsidian-cli-reference.md`, 1534 lines). Key facts:
  - The CLI is bundled with the Obsidian desktop app (installer 1.12.7+), not an
    npm package.
  - The Obsidian app must be running; the CLI connects to the live instance.
  - A vault is identified by being registered in Obsidian; the CLI selects by
    active vault, `vault=<name|id>`, or cwd.
  - Rich surface: create/read/append/prepend/move/rename/delete, daily:*,
    search/search:context, tags/tag, properties/property:set, backlinks/links/
    unresolved/orphans/deadends, tasks, templates, vault/vaults.
- Inspected the local machine:
  - Obsidian 1.12.4 installed (below the 1.12.7 CLI requirement).
  - `obsidian-cli` binary absent from the app bundle; `/usr/local/bin/obsidian`
    not registered.
  - An existing personal vault is registered at
    `~/Library/CloudStorage/OneDrive-Personal/Notes.md`.
  - Vault registry file: `~/Library/Application Support/obsidian/obsidian.json`
    with shape `{"vaults":{<id>:{path,ts,open}}, "cli":bool}`.

### Innovate
- Dependency model: (a) depend on a third party npm CLI, (b) official Obsidian
  CLI, (c) self contained bash only. Chose (b) per the user, with (c) as the
  fallback layer (hybrid).
- Runtime mode: require app running vs hybrid fallback. Chose hybrid so capture
  still works when Obsidian is closed.
- Vector search: build now vs defer. Chose defer (Phase 2); v1 = full text +
  tags + backlinks, all native to the CLI.
- Vault identity: arbitrary path vs Obsidian registered vault. Reconciled by
  resolving `$AGENT_MEMO_VAULT` as a path and ensuring the installer registers
  that folder as an Obsidian vault named `agent-memo-vault`; the helper `cd`s
  into it so the CLI selects it by cwd.
- Naming: keep `obsidian-brain` vs cohesive `agent-memo-vault` stem. Chose
  `agent-memo-vault` to avoid leaking the implementation and to stay cohesive
  with the skill name.
- Classification: domain folders + heat tiers. Heat uses text tiers
  (`seedling`/`growing`/`evergreen`) because of the no-emoji constraint.

### Plan (approved)
- Naming contract as in `AGENTS.md` section 2.
- Repo layout as in `AGENTS.md` section 3.
- Skill surface: `preflight`, `new`, `append`, `prepend`, `read`, `daily`,
  `search`, `tags`, `by-tag`, `backlinks`, `links`, `orphans`, `unresolved`,
  `move`, `rename`, `promote`, `moc`, `by-heat`.
- Hybrid implementation: `lib/cli.sh` (official CLI) and `lib/fs.sh` (pure fs)
  behind one dispatcher.
- Installer: copy skill to `~/.agent-memo-vault-skill/`, scaffold vault at
  `~/.agent-memo-vault/`, optionally register vault into `obsidian.json`, and
  inject pointer stubs into each target agent's rules location.
- Supported agents: claude, codex, opencode, cline, cursor, crush, gemini,
  copilot, trae, pi.
- Vector search explicitly out of scope for v0.1.

### Execute
- Wrote `AGENTS.md`, `CLAUDE.md`, `README.md`, `SKILL.md`, `VERSION`.
- Wrote `docs/`: ARCHITECTURE, CLASSIFICATION, CLI-REFERENCE, DEVELOPMENT,
  RIPER, INSTALL.
- Wrote `scripts/memovault.sh`, `scripts/lib/cli.sh`, `scripts/lib/fs.sh`,
  `scripts/lib/classify.sh`.
- Wrote `install/install.sh`, `install/targets.sh`,
  `install/adapters/<agent>.{md,mdc}` for all supported agents.
- Wrote `templates/note.md`, `templates/daily.md`, `templates/moc.md`.

### Review
Self-tested against bash 3.2.57 with a throwaway vault. Findings and fixes:

- Caught and fixed a parse error: a `case` pattern with a `[...]` glob class
  before a space (`*[Nn]ot found*)`) is rejected by bash 3.2. Replaced with a
  lowercased value and a quoted literal (`*"not found"*`). Documented the rule
  in `DEVELOPMENT.md`.
- Fixed false cli mode: on this host `obsidian` resolves to the GUI app binary
  (Obsidian 1.12.4, below the 1.12.7 CLI requirement), which exits 0 with
  `Vault not found.` Detection now does a functional probe (`obsidian version`,
  backgrounded with a manual timeout, output validated) instead of trusting
  binary presence plus a running app.
- Fixed path traversal: `mmfs_move` validated with a string prefix match, so
  `$VAULT/../escape` passed. Now rejects any `..` path segment and re-checks
  the canonicalized destination.
- Verified round trips in fs mode: new/read/append/prepend/search/tags/backlinks/
  links/orphans/unresolved/promote (seedling->growing->evergreen)/moc/by-heat/
  daily:append, plus move/rename within `brain/`.
- Verified installer `--dry-run` renders stubs and resolves placeholders for
  every supported agent.
- Naming contract (`AGENTS.md` section 2) upheld; no emoji in any file.

## 4. Entry: always-on memory protocol (2026-07-14)

### Research
- User asked whether triggering must be explicit or can be automatic.
- Confirmed the mechanism: skill "trigger" is always the agent's own decision
  based on loaded instructions; there is no OS-level hook without extra
  integration. opencode keeps `~/.config/opencode/AGENTS.md` in context every
  turn, so an always-on instruction there is effectively automatic.

### Innovate
- Passive pointer stub vs proactive protocol vs event hooks. Chose the proactive
  protocol embedded in the always-loaded instructions (reliable and cross-agent);
  deferred true event-driven hooks (opencode plugins, Claude Code hooks) to a
  later phase.
- Split behavior: recall (read) fully automatic; capture (write) semi-automatic
  (propose then confirm) to avoid noise and wrong captures.

### Plan (approved)
- Author the protocol once in `install/adapters/_protocol.md`.
- Slim every per-agent adapter to a header; `install.sh` composes header +
  protocol via a new `mm_compose`.
- Document the protocol in `SKILL.md` (new section 6) and renumber subsequent
  sections.
- Re-inject opencode with `--force`.

### Execute
- Added `install/adapters/_protocol.md`.
- Rewrote all 10 adapter files to minimal headers; cursor adapter set
  `alwaysApply: true`.
- `install.sh`: added `mm_compose`; skill/rules/agents injection now emits the
  composed body.
- `SKILL.md`: inserted section 6 (Memory protocol), renumbered 7-10.
- Reinstalled source; re-injected opencode (`--force`).

### Review
- `bash -n install.sh` passes; `--dry-run` shows header + protocol composed with
  placeholders resolved for every agent.
- opencode `~/.config/opencode/AGENTS.md` now carries the full protocol block
  (idempotent markers intact, CodeGraph block untouched).
- No emoji in any changed file.

## 5. Entry: self-contained skill under ~/.agents/skills/ (2026-07-15)

### Research
- User enabled Trae's "`.agents` skills directory" setting. Confirmed
  `~/.agents/skills/` is this machine's shared skills dir (28 skills, each a
  self-contained `<name>/SKILL.md` folder; pi and the npx-skills ecosystem read
  it). Trae scans this directory; `.skill-lock.json` is another manager's
  registry and is not consulted for discovery.

### Innovate
- Two-location model (source at `~/.agent-memo-vault-skill/` + per-agent copies)
  vs single self-contained folder under `~/.agents/skills/memovault/`. Chose the
  latter: it is the idiom (matches byted-ark / lark skills), removes an
  indirection, and is auto-discovered by pi/Trae.

### Plan (approved)
- Canonical skill home becomes `~/.agents/skills/memovault/` (SKILL.md + scripts
  + templates + docs). Drop `~/.agent-memo-vault-skill/`.
- `pi` and `trae` become `native` kind: `--agent pi`/`--agent trae` just installs
  the source here (auto-discovered); no stub. Other agents keep pointer
  stubs/blocks that now reference `~/.agents/skills/memovault/SKILL.md`.
- Vault data `~/.agent-memo-vault/` and env `AGENT_MEMO_VAULT` unchanged.
- Bump version 0.1.0 -> 0.2.0.

### Execute
- Bulk path replace `.agent-memo-vault-skill` -> `.agents/skills/memovault` in
  README, SKILL, AGENTS, INSTALL, install.sh (RIPER historical entries left
  intact).
- install.sh: added `native` kind branch in `mm_inject_one`.
- targets.sh: `pi|trae` -> native; merged path; removed the bogus `~/.trae/rules`
  entry.
- docs/INSTALL.md: table + notes updated for native pi/trae and the skills home.
- Version bumped to 0.2.0.

### Review
- `bash -n` passes; `--dry-run --all` shows native (pi/trae) and stubs (others).
- Migrated the live machine: reinstalled source to the new path, re-injected
  opencode (`--force`) to repoint its block, removed the old source dir.
- preflight and search verified from the new helper path.

## 6. Entry: install.sh --verify (2026-07-16)

### Research
- User found memovault listed under several agents but `~/.agent-memo-vault/`
  had no notes. Helper preflight/new/search worked; always-on adapter injection
  was missing for Cursor (`~/.cursor/rules/memovault.mdc` absent) and most
  other agents (only opencode had the protocol block).
- Root cause: skill discovery (`~/.agents/skills/memovault`) is not always-on;
  capture also stays propose-then-confirm unless the user says remember/记一下.

### Innovate
- One-off reinstall vs lasting check. Chose both: re-ran `--all --force` on the
  machine, and add `--verify` so incomplete injection is visible next time.
- Keep verify read-only and exit non-zero on failure.

### Plan (approved via user "执行")
- Add `install.sh --verify` (optional `--agent`); check source, helper, vault
  scaffold, and each agent's Memory protocol injection (Cursor also requires
  `alwaysApply: true`).
- Document in `docs/INSTALL.md` section 6; record here.

### Execute
- `install/install.sh`: `--verify`, `mm_verify` / `mm_verify_agent`.
- `docs/INSTALL.md`: verify section clarifies discovery vs always-on.
- Post-install next-steps line points at `--verify`.

### Review
- `bash -n install/install.sh` passes; `--verify` reports OK after `--all --force`.

## 7. Entry: MM_FORCE_FS headless mode (2026-07-28)

### Research
- User reported that invoking the skill opens the Obsidian GUI window, which is
  undesirable for silent agent runs. Asked whether the Obsidian CLI has a headless
  mode.
- Re-read `scripts/lib/cli.sh`, `scripts/memovault.sh`, `docs/ARCHITECTURE.md`,
  `docs/CLI-REFERENCE.md`, `SKILL.md`.
- Probed the live machine: `command -v obsidian` resolves to
  `/Applications/Obsidian.app/Contents/MacOS/obsidian` (the GUI app binary, not a
  real `obsidian-cli`); `obsidian version` hangs and launches the GUI, timing out
  after 30s. The official CLI bundle (`obsidian-cli`) is absent under
  `/Applications/Obsidian.app/Contents/MacOS/`.
- Confirmed the official Obsidian CLI has no headless mode: it is an IPC client to
  the running desktop app. No flag or env var exists to run it without the GUI.
- Confirmed the skill had no force-fs switch: `mmcli_detect` (cli.sh:63-71) always
  probed the binary + app, with no env var override.

### Innovate
- Option A: add a force-fs env var so the probe is skipped entirely (chosen). The
  fs layer already implements every subcommand; tradeoff is approximate backlinks
  and non-link-safe move/rename.
- Option B: correctly install the real `obsidian-cli` binary via symlink. Rejected
  as the primary fix because the binary was absent from the installed app bundle
  and it still requires the GUI app to be running (no true headless).
- Option C: accept the GUI must be open. Rejected; the user explicitly wants to
  avoid window launches.
- Naming: `MM_FORCE_FS` (matches the internal `MM_MODE`/`MM_` convention, short,
  explicit) vs `AGENT_MEMO_FORCE_FS` (matches the public `AGENT_MEMO_VAULT`
  namespace). Chose `MM_FORCE_FS` since it directly controls internal mode
  detection and preflight already surfaces `MM_MODE` to users.

### Plan (approved via user "按照方案A来做计划并落地")
- `scripts/lib/cli.sh`: `mmcli_detect` checks `MM_FORCE_FS=1` first; if set,
  short-circuits to fs mode, sets a new `MM_FORCED=1` flag, skips binary location
  and app probe so the GUI never launches.
- `scripts/memovault.sh`: `mm_preflight` adds `forced=` field and a hint line for
  forced mode.
- `SKILL.md`: document `MM_FORCE_FS` in sections 1, 2, 8.
- `docs/ARCHITECTURE.md`: update section 4 (mode detection) with the short-circuit
  step and the headless caveat.
- `docs/CLI-REFERENCE.md`: add a headless bullet to Prerequisites.
- `docs/RIPER.md`: record this entry.
- `VERSION`: bump 0.2.0 -> 0.2.1.

### Execute
- `scripts/lib/cli.sh`: added the `MM_FORCE_FS` short-circuit at the top of
  `mmcli_detect`; sets `MM_FORCED`, `MM_OBSIDIAN=""`, `MM_APP_RUNNING=0`,
  `MM_MODE=fs`.
- `scripts/memovault.sh`: `mm_preflight` prints `forced=` and a dedicated hint
  when forced.
- `SKILL.md`: added env export in section 1, preflight note in section 2, forced
  mode paragraph in section 8.
- `docs/ARCHITECTURE.md`: rewrote section 4 detection order with the short-circuit
  as step 1 and the forced= line in the example.
- `docs/CLI-REFERENCE.md`: added the headless bullet to Prerequisites.
- This entry recorded; `VERSION` bumped.

### Review
- `bash -n scripts/memovault.sh` and `bash -n scripts/lib/cli.sh` pass.
- `MM_FORCE_FS=1 scripts/memovault.sh preflight` reports `mode=fs ... forced=1`
  instantly without launching the GUI, confirming the headless path works.
- Without the env var, behavior is unchanged (probe runs as before).
- Naming contract (AGENTS.md section 2) upheld: new env var `MM_FORCE_FS` and new
  global `MM_FORCED` follow the `MM_` internal convention; no public namespace
  collision. No emoji added to any file.

## 8. Entry: upgrade subcommand and self-update (2026-07-29)

### Research
- Re-read `scripts/memovault.sh` (`mm_resolve_dev_repo`, `mm_check_update`,
  `mm_cmd_upgrade`, the dispatch `upgrade)` case, and the update hint in
  `mm_preflight`) and `install/install.sh` (`mm_resolve_dev_repo`,
  `mm_version_of`, `mm_vercmp`, `mm_upgrade`, the `--upgrade`/`--no-pull` flags,
  and the `.source-origin` write in `mm_install_source`).
- Confirmed the code was already complete and verified end-to-end in a prior
  session (0.2.0 -> 0.2.1 upgrade succeeded on this machine; all 10 agent stubs
  re-injected; `preflight` then showed no update hint). Only documentation and the
  version bump remained.
- Verified the exact runtime strings so the docs stay accurate: the preflight
  hint is emitted as `printf 'hint: %s (run: memovault upgrade)\n'` where `%s` is
  `update-available <installed> <dev>`, so the real line reads
  `hint: update-available <installed> <dev> (run: memovault upgrade)`.

### Innovate
- Version source: a remote/npm registry vs the local dev repo. Chose the dev
  repo as the single source of truth (no network dependency, matches the skill's
  pure local design). Auto-detected from `.source-origin`, overridable via
  `MEMOVAULT_DEV_REPO`.
- Trigger: fully automatic upgrade vs an explicit `upgrade` plus a non-blocking
  `preflight` hint. Chose the explicit form; `preflight` surfaces availability
  but never mutates state.
- Git: always pull vs optional pull vs no git. Chose optional `git pull
  --ff-only`, skippable with `--no-pull`; the installer never depends on git and
  falls back to local files if it is absent or the pull fails.
- Naming: the new public env var uses the `MEMOVAULT_DEV_REPO` prefix (matches the
  skill name, consistent with `AGENT_MEMO_VAULT`); new helpers/globals keep the
  lowercase `mm_` internal convention (`mm_version_of`, `mm_vercmp`,
  `mm_resolve_dev_repo`, `mm_check_update`, `mm_cmd_upgrade`, `mm_upgrade`).

### Plan (approved)
- Document the upgrade in `SKILL.md` section 2 (Preflight) and bump the
  frontmatter `version: 0.2.1` -> `0.3.0` (a feature add, not just a fix).
- Bump `VERSION` `0.2.1` -> `0.3.0`.
- Add an "Upgrade" section to `docs/INSTALL.md`.
- Add an "Upgrade flow" section to `docs/ARCHITECTURE.md`.
- Record this entry.
- Final review: `bash -n` on both scripts, emoji scan, naming-contract check.

### Execute
- `SKILL.md`: added the "Update and upgrade" subsection in section 2; bumped
  the frontmatter to 0.3.0.
- `VERSION`: bumped to 0.3.0.
- `docs/INSTALL.md`: added section 7 (Upgrade); renumbered Uninstall to 8.
- `docs/ARCHITECTURE.md`: added section 9 (Upgrade flow); renumbered Extension
  points to 10.
- This entry recorded.

### Review
- `bash -n scripts/memovault.sh` and `bash -n install/install.sh` both pass.
- Emoji scan across `*.md`/`*.sh`/`*.json` in the repo: none found.
- Naming contract (AGENTS.md section 2) upheld: new public env var
  `MEMOVAULT_DEV_REPO` and all new internal helpers/globals follow their
  respective conventions; no namespace collision. No emoji in any changed file.
- Upgrade never writes outside the skill source dir and never touches
  `$AGENT_MEMO_VAULT` data.

## 9. Entry: persistent headless via env.sh + --force-fs (2026-07-29)

### Research
- User reported that opencode invoking the skill still popped the Obsidian GUI.
- Re-read `scripts/memovault.sh` (startup resolves `MM_SOURCE`, sources
  `lib/*.sh`, then runs `mmcli_detect`) and `install/install.sh` (`mm_write_env`).
  Root cause confirmed: the helper never sourced `env.sh`; `env.sh` only set
  `AGENT_MEMO_VAULT` (not `MM_FORCE_FS`); and no caller on the opencode path
  exports `MM_FORCE_FS`. So `mmcli_detect` ran the full probe. On this host
  `obsidian` is the GUI app binary, so the functional probe (`obsidian version`,
  backgrounded) itself launched the GUI. There was no persistent,
  caller-independent headless switch.

### Innovate
- Where to anchor headless: per-call env export (fragile; agents forget) vs the
  user's shell rc (opencode may spawn non-login shells, so unreliable) vs the
  helper sourcing its own config (robust; applies to every caller). Chose the
  last.
- Default: opt-in `--force-fs` (chosen) vs inverting to headless-by-default.
  Opt-in preserves cli mode for users with a real `obsidian-cli`; headless stays
  a per-machine preference. User approved option A.
- Durability: `mm_write_env` overwrites `env.sh` on every install/upgrade, so a
  hand-edited `MM_FORCE_FS` line would be wiped. Therefore the installer must own
  the line via a flag.

### Plan (approved via user "A")
- `scripts/memovault.sh`: source `$MM_SOURCE/env.sh` at startup, before
  `MM_VAULT` resolution and `mmcli_detect`.
- `install/install.sh`: add `FORCE_FS=0` init, a `--force-fs` flag (usage + arg
  parse), and have `mm_write_env` append
  `export MM_FORCE_FS="${MM_FORCE_FS:-1}"` when set.
- Bump `VERSION` 0.3.0 -> 0.3.1; document in SKILL.md, INSTALL.md, ARCHITECTURE.md.
- Apply on this machine via `install.sh --upgrade --force-fs --no-pull`.
- Test: simulate the opencode path (clean env, no `MM_FORCE_FS`) and confirm
  `preflight` reports `forced=1` with no probe / no GUI.

### Execute
- `scripts/memovault.sh`: added the `env.sh` source line right after `MM_SOURCE`.
- `install/install.sh`: `FORCE_FS=0` init; `--force-fs` in usage and arg parsing;
  `mm_write_env` conditionally appends the `MM_FORCE_FS` export via a quoted
  heredoc (no expansion ambiguity).
- `VERSION` -> 0.3.1; SKILL.md section 1 note + frontmatter; INSTALL.md sections
  3 and 4; ARCHITECTURE.md section 3.
- Applied on this machine: installed copy 0.3.0 -> 0.3.1; `env.sh` now carries
  `export MM_FORCE_FS="${MM_FORCE_FS:-1}"`; all 10 agent stubs re-injected.
- This entry recorded.

### Review
- `bash -n` passes on both `scripts/memovault.sh` and `install/install.sh`.
- Temp-dir install test: `--force-fs` writes
  `export MM_FORCE_FS="${MM_FORCE_FS:-1}"` into `env.sh`; without `--force-fs`
  the line is absent (backward compatible; hosts with a real CLI keep probe
  behavior).
- opencode-path simulation (`env -u MM_FORCE_FS ... preflight`): reports
  `mode=fs ... forced=1` with `bin=` empty in 0.74s, proving the probe never ran
  and the GUI cannot launch. The fix comes from the helper sourcing `env.sh`,
  not from inherited env.
- Override semantics verified without triggering the probe: default (unset) -> 1,
  caller `MM_FORCE_FS=0` -> 0, caller `MM_FORCE_FS=1` -> 1. A caller can opt back
  into CLI probing per invocation.
- Naming contract (AGENTS.md section 2) upheld: no new public env var (`MM_FORCE_FS`
  is from entry 7); the installer-local `FORCE_FS` follows the existing uppercase
  convention (`FORCE`, `DRY_RUN`, `NO_PULL`); `--force-fs` is distinct from
  `--force`. No emoji in any changed file.

## 10. Entry: layered recall + distill provenance + skill notes (2026-08-03)

### Research
- Read [TencentDB Agent Memory README_CN](https://github.com/TencentCloud/TencentDB-Agent-Memory/blob/feat/server_team/README_CN.md)
  (feat/server_team): four asset types (Chat Memory / Skill / Wiki / CodeGraph),
  L0→L1→L2→L3 pyramid, recall budgets (count/char/timeout), progressive
  disclosure, evidence drill-down, Agent Loadout, Memory Proxy injection.
- Compared to MemoVault: local Obsidian + bash; `domain` + `heat`; always-on
  recall = one `search` then optional `read`; capture = propose-then-confirm;
  vector search reserved; no daemon / no ACL / no proxy (by design).
- User asked for a RIPER plan covering the three highest-fit practices only:
  (1) recall budget + heat/layer priority, (2) distill + provenance, (3) skill
  note contract. No code until this plan is approved.

### Innovate
- Layer model: new L0–L3 folders vs optional `kind` frontmatter mapped onto the
  existing vault layout. Chose optional `kind` (`raw` | `atom` | `scenario` |
  `persona` | `skill`) plus existing `heat` / `daily/` / `brain/<domain>/`.
  Avoids a second taxonomy tree and stays searchable via frontmatter.
- Recall budget: helper-enforced hard caps vs protocol-only limits. Chose
  protocol-only for this entry (agents already own recall); optionally pass
  `search --limit N`. A later entry may add `search --prefer-heat` if needed.
- Provenance: body-only `[[wikilinks]]` vs frontmatter `sources: []` plus
  wikilinks. Chose both: `sources` for machine scan, `[[links]]` for the graph.
- Skill assets: separate skill-manager product vs vault notes under
  `domain: skills` with `kind: skill`. Chose vault notes + `templates/skill.md`
  so SOP lives next to related knowledge without leaving the FS skill model.
- Explicitly out of scope: Memory Proxy, team ACL/Hub, async LLM distill
  pipeline, CodeGraph inside memovault, per-agent loadout files, vector search
  (still reserved in DEVELOPMENT.md).

### Plan (approved via user "批准")

**Goal:** teach agents to recall less but better, distill raw captures into
linked structured notes, and capture reusable SOPs as first-class skill notes
— without changing the pure-local bash/Obsidian identity.

**Version:** bump `0.3.1` -> `0.4.0` (protocol + classification feature).

**Non-goals for this entry:** new daemon, vector index, loadout files, ingest
subcommand, helper changes beyond optional `new` flags and template wiring.

#### A. Classification contract (`docs/CLASSIFICATION.md`)

Add section "Memory kinds (optional frontmatter)":

| `kind` | Maps to Tencent layer | Typical home | Default heat |
|---|---|---|---|
| `raw` | L0 | `daily/` or `brain/inbox/` | seedling |
| `atom` | L1 | `brain/<domain>/` short fact/decision | seedling |
| `scenario` | L2 | project/scene notes + MOCs | growing |
| `persona` | L3 | rare preference/constraint notes | evergreen |
| `skill` | Skill asset | `brain/skills/` | growing |

Rules:
- `kind` is optional; omit = treat as ordinary domain note (today's behavior).
- `sources:` optional YAML list of note titles or vault-relative paths that
  evidence this note (required when distilling from raw/daily).
- Heat promotion heuristics unchanged; distill may *suggest* `promote` when an
  atom gains backlinks.

Update frontmatter example in CLASSIFICATION.md and `templates/note.md`:

```yaml
---
title: Human Readable Title
domain: engineering
kind: atom          # optional
tags: [tag-a]
heat: seedling
aliases: []
sources: []         # optional; fill when distilled
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

#### B. Skill note template (`templates/skill.md`)

New template with fixed body sections (plain English headings, no emoji):

```markdown
---
title: {{title}}
domain: skills
kind: skill
tags: [skill]
heat: growing
aliases: []
sources: []
created: {{date}}
updated: {{date}}
---

# {{title}}

## Trigger
When to use this skill (boundaries; when NOT to use it).

## Steps
1. ...

## Verify
How to know it worked.

## Related
- [[related note]]
```

Installer already copies templates into the vault scaffold; extend
`mm_scaffold_vault` to include `skill` if not already looping all templates
(today loops `note daily moc` — add `skill`).

#### C. Memory protocol — recall budget (`SKILL.md` §6 + `_protocol.md`)

Replace the thin recall bullets with:

1. One `search "<narrow keywords>"` per task (prefer `--limit 10` or tighter).
2. Rank hits mentally: prefer `heat: evergreen` then `growing`; prefer
   `kind: persona|scenario|skill|atom` over `raw` / pure `daily/` noise.
3. Read at most **3** notes per task (usually 1). Progressive disclosure:
   titles/snippets first, full `read` only if relevant.
4. If nothing useful, skip silently.
5. Cite used vault notes in the answer when they materially affect it.

#### D. Memory protocol — distill + provenance (`SKILL.md` + `_protocol.md`)

New subsection after Capture:

- Raw capture (daily line or `kind: raw` / inbox) is L0 evidence, not the end
  state.
- When durable knowledge appears, prefer creating/updating an `atom` or
  `scenario` note and set `sources: ["Daily 2026-08-03"]` (or titles) **and**
  body `[[wikilinks]]` back to the raw note.
- After distill, offer to leave a one-line pointer on the daily note linking to
  the new atom.
- Never delete raw evidence without explicit user consent.
- Persona notes (`kind: persona`) are rare; only for stable preferences /
  hard constraints; start `heat: evergreen` only with user confirmation
  (otherwise seedling then suggest promote).

#### E. Memory protocol — skill capture

When the turn produced a reusable SOP (how-to that would save future turns):
- Propose: `skills/<Title>` with `kind: skill`, or on explicit remember phrases
  write immediately.
- Use `templates/skill.md` structure (Trigger / Steps / Verify / Related).
- Link related domain atoms/scenarios with `[[wikilinks]]`.

#### F. Helper (minimal)

- `scripts/lib/fs.sh` `mmfs_new`: emit `sources: []`; accept optional kind
  argument (5th param or parse `--kind` in `memovault.sh` dispatch for `new`).
- CLI path: after create, `property:set` for `kind` / ensure `sources` if easy;
  if CLI create ignores unknown props, fs write remains source of truth for new
  notes in fs mode; in cli mode set properties after create.
- Prefer: `"$MM" new <domain> "<Title>" [--tags a,b] [--kind atom] [--body "..."]`
- No new subcommands (`by-kind`, `distill`) in this entry — agent uses
  `search` / `read` / `append` / `promote`.

#### G. Docs and install

- `docs/ARCHITECTURE.md`: short "Layered memory (protocol)" note pointing at
  CLASSIFICATION kinds; no new runtime layer.
- `docs/DEVELOPMENT.md`: note that vector search remains phase 2; kinds are
  orthogonal.
- `docs/RIPER.md`: this entry (Execute/Review filled after approval).
- `VERSION` + `SKILL.md` frontmatter `version: 0.4.0`.
- After Execute: `./install/install.sh --upgrade --force-fs --no-pull` (or
  equivalent on this machine) and `./install/install.sh --all --force` so
  `_protocol.md` changes reach agents; then `--verify`.

#### H. Review checklist

- `bash -n` on touched scripts.
- No emoji in any changed file.
- Naming contract: no new public env vars; `kind` / `sources` are vault
  frontmatter only.
- Manual: `new skills "Example SOP" --kind skill`, confirm frontmatter; protocol
  text present in installed `~/.cursor/rules/memovault.mdc` and Claude stub.
- Confirm `templates/skill.md` exists under skill source and vault scaffold.

**Approval gate:** do not Execute until the user explicitly approves this plan
(possibly with edits to budgets, kind enum, or whether `--kind` lands in helper
vs protocol-only).

### Execute
- `docs/CLASSIFICATION.md`: frontmatter `kind`/`sources`; new Memory kinds
  section; renumbered later sections; daily distill note; `skills` domain.
- `templates/note.md`: added optional `kind` and `sources: []`.
- `templates/skill.md`: new skill SOP template.
- `SKILL.md`: version 0.4.0; hard rules for kind; classification + protocol
  (recall budget, distill, skill capture); `new --kind` in ops reference.
- `install/adapters/_protocol.md`: aligned with SKILL protocol sections 1-6.
- `scripts/lib/fs.sh` `mmfs_new`: optional kind, `sources: []`, skill heat
  growing.
- `scripts/memovault.sh`: `new --kind`; usage updated.
- `install/install.sh`: scaffold copies `skill` template.
- `docs/ARCHITECTURE.md` section 10 layered memory; extension points -> 11.
- `docs/DEVELOPMENT.md`: kinds orthogonal to vector phase.
- `VERSION` -> 0.4.0.

### Review
- `bash -n` passes on `scripts/memovault.sh`, `scripts/lib/fs.sh`,
  `install/install.sh`.
- `new skills "..." --kind skill` writes `kind: skill`, `heat: growing`,
  `sources: []`. `new ... --kind atom` writes `kind: atom`, `heat: seedling`.
- `./install/install.sh --upgrade --force-fs --no-pull --all --force`:
  0.3.1 -> 0.4.0; `--verify` OK for all agents.
- Cursor/Claude injected protocol contains recall budget, distill, and skill
  capture sections. Vault scaffold includes `templates/skill.md`.
- No emoji. Naming contract: no new public env vars; `kind`/`sources` are vault
  frontmatter only.

## 11. Entry: fs daily note resolution for distill provenance (2026-08-03)

### Research
- Self-test of MemoVault 0.4.0 layered memory: distill trial wrote
  `[[2026-08-03]]` and `sources: [2026-08-03]`, plus a daily pointer to the
  atom. File writes succeeded; graph partially worked.
- Root cause in `scripts/lib/fs.sh`:
  - `mmfs_find_note` / `mmfs_locate` (title form) only search `brain/`.
  - `mmfs_unresolved` only treats a target as resolved if `brain/**/$target.md`
    exists.
  - `mmfs_graph` only scans `brain/**/*.md` for outgoing `[[links]]`, so links
    *from* daily notes are invisible to orphans/unresolved edge building.
  - `mmfs_backlinks` already rg's the whole `$MM_VAULT`, so daily→atom backlinks
    can appear while `unresolved` still lists `2026-08-03`.
  - `read "2026-08-03"` fails; `read "daily/2026-08-03.md"` works (path form).
  - Daily files are created with frontmatter `created:` only (no `title:`);
    filename stem is the natural Obsidian daily title.
- Protocol (Entry 10) requires distill to wikilink back to raw/daily evidence.
  That contract is broken under forced fs mode (this machine's default).

### Innovate
- A) Protocol-only: mandate `[[daily/YYYY-MM-DD]]` path wikilinks. Rejected as
  sole fix — Obsidian-native daily links are `[[YYYY-MM-DD]]`, and agents will
  keep emitting date titles.
- B) Helper resolves date titles and daily paths; unresolved/graph include
  `daily/`. Chosen. Matches Obsidian expectations and Entry 10 distill text.
- C) Move dailies under `brain/daily/`. Rejected — breaks existing vault layout
  and Obsidian daily-notes convention (`daily/` at vault root).
- Scope: fs layer + daily template/frontmatter + short protocol clarification.
  No cli-mode changes beyond docs (cli unresolved is Obsidian-native).

### Plan (approved via user "批准")

**Goal:** Make `[[YYYY-MM-DD]]` (and `daily/YYYY-MM-DD.md`) first-class in fs
mode so distill provenance closes the loop.

**Version:** bump `0.4.0` -> `0.4.1` (bugfix).

#### A. `scripts/lib/fs.sh`

1. **`mmfs_find_note`**: after brain search, if
   `$MM_VAULT/daily/$title.md` exists, print it. Prefer brain on name collision
   (unlikely for ISO dates).
2. **`mmfs_locate`**: keep existing absolute / vault-relative path handling
   (already covers `daily/YYYY-MM-DD.md`). Optionally normalize bare
   `daily/YYYY-MM-DD` (no `.md`) to the file if present — nice-to-have in same
   change if cheap.
3. **`mmfs_graph`**: scan both `brain/` and `daily/` for outgoing `[[links]]`.
4. **`mmfs_unresolved`**: a target is resolved if any of:
   - `brain/**/$target.md` exists, or
   - `daily/$target.md` exists, or
   - `$MM_VAULT/$target` or `$MM_VAULT/$target.md` exists (path-style links).
5. **`mmfs_daily` / create path**: when creating a new daily file, write
   `title: YYYY-MM-DD` in frontmatter (keep `created:`). Do not bulk-rewrite
   historical dailies in this entry.

#### B. Templates / docs / protocol

- `templates/daily.md`: add `title: {{date}}`.
- `docs/CLASSIFICATION.md` daily section: canonical distill link is
  `[[YYYY-MM-DD]]`; path form `daily/YYYY-MM-DD.md` also works with `read`/
  `locate`.
- `SKILL.md` distill bullet: same one-line clarification.
- `_protocol.md` distill bullet: same.
- `docs/ARCHITECTURE.md` fs graph/unresolved row: note daily is included.
- `docs/RIPER.md`: this entry; Execute/Review after approval.

#### C. Live vault hygiene (this machine, as part of Review)

- Ensure `daily/2026-08-03.md` is no longer listed by `unresolved` for target
  `2026-08-03`.
- `read "2026-08-03"` returns the daily note.
- Trial atom `MemoVault distill trial atom` remains valid evidence (optional:
  add `title` to that daily's frontmatter by hand if missing).

#### D. Out of scope

- Migrating all historical daily frontmatter.
- Changing orphans to list daily files as candidates.
- cli-mode Obsidian unresolved behavior.
- Auto-rewrite of existing `[[daily/...]]` path links.

#### E. Review checklist

- `bash -n scripts/lib/fs.sh`
- `read "2026-08-03"` / `unresolved` no longer reports that date when the file
  exists
- Brain-only unresolved targets still reported
- No emoji; VERSION 0.4.1; `install.sh --upgrade --force-fs --no-pull` (+
  reinject if protocol text changed)

### Execute
- `scripts/lib/fs.sh`: `mmfs_find_note` checks `daily/`; `mmfs_locate` accepts
  vault-relative paths without `.md`; `mmfs_graph` scans brain+daily;
  `mmfs_target_exists` + `mmfs_unresolved`; new dailies get `title:`.
- `templates/daily.md`: `title: {{date}}`.
- `docs/CLASSIFICATION.md`, `SKILL.md`, `_protocol.md`, `ARCHITECTURE.md`
  updated for canonical `[[YYYY-MM-DD]]`.
- `VERSION` / SKILL frontmatter -> 0.4.1.

### Review
- `bash -n scripts/lib/fs.sh` passes.
- `read "2026-08-03"` and `read "daily/2026-08-03"` both return the daily note.
- `unresolved` no longer lists `2026-08-03`; remaining hits are pre-existing
  non-daily targets.
- `orphans` no longer lists `MemoVault distill trial atom` (daily outgoing link
  now in graph); `backlinks` shows `daily/2026-08-03.md`.
- Upgraded this machine 0.4.0 -> 0.4.1 with `--force-fs --no-pull --all --force`;
  protocol stubs mention canonical `[[YYYY-MM-DD]]`.
- No emoji; no new public env vars.

### 2026-08-03 - 端到端测试（hybrid harness + agentic skill）
- Research: 确认无既有测试；helper 命令面与 cli 注册依赖；规格见 docs/superpowers/specs/2026-08-03-e2e-testing-design.md
- Innovate: 纯 skill / 纯 bash / 混合 → 选混合；隔离 vault + 临时注册满足双模式
- Plan: docs/superpowers/plans/2026-08-03-e2e-testing.md（已批准）
- Execute: scripts/e2e/* + skills/testing-memovault/SKILL.md + DEVELOPMENT/RIPER 指针
- Review: FS 阶段 35/35 通过；CLI 阶段因 Obsidian 未运行于 preflight 失败（`./scripts/e2e/run.sh` exit 1）；另：当 Obsidian 运行但 vault 未在 GUI 打开时，`cli rename updated wikilink` 仍可能失败（Obsidian CLI 产品行为）；生产 vault 无 E2E STEM 污染；完整双模式需在 Obsidian 运行时再验收

## 12. Entry: 纯 shell 运行时与跨平台（2026-08-04 / 05）

### Research
- 用户提出：MemoVault 在「Obsidian CLI 优先 + fs 回退」双运行时下，CLI 探测会
  误启 GUI、跨平台不一致、e2e 双模式门禁在无头环境永远红。要求改为纯 shell 运行时。
- 读 `scripts/memovault.sh`、`scripts/lib/cli.sh`、`scripts/lib/fs.sh`、
  `scripts/lib/classify.sh`、`install/install.sh`、`scripts/e2e/*`、`SKILL.md`、
  `docs/ARCHITECTURE.md`、`docs/INSTALL.md`、`docs/CLI-REFERENCE.md`、
  `docs/DEVELOPMENT.md`、`docs/RIPER.md`、`README.md`、`README_CN.md`、
  `install/adapters/_protocol.md`、`docs/superpowers/specs/2026-08-03-e2e-testing-design.md`。
- 外部事实：Obsidian CLI 是有头 IPC 客户端，无 headless 模式；`obsidian` 在 macOS
  常解析到 GUI 二进制；Windows 无原生 bash 业务栈，WSL2 是唯一可行路径。
- 旧 `MM_FORCE_FS` 已被多个 env.sh / e2e harness 引用；废弃需保留兼容。

### Innovate
- 运行时：A 完全替换 CLI（仅强化 fs/shell） / B 保留双轨并加 headless / C 重新
  设计 CLI 调用层。选 A：消除模式探测与 GUI 风险，单一实现可跨平台。
- wikilink 改写：A 在 fs 层新写 `lib/rewrite.sh` / B 仅文档警告 / C 依赖 Obsidian。
  选 A：让 `rename` 在纯 shell 下也链接安全，闭合 distill/图谱闭环。
- Windows：A WSL2 跑同一套 bash / B 维护原生 `.ps1` / C 不支持。选 A：业务逻辑
  单一来源；不扩范围。
- `MM_FORCE_FS`：A 立即删 / B 保留并忽略 + stderr 废弃提示 / C 仍生效。选 B：
  旧 env.sh / e2e 不破，提示用户清理。
- `--register-vault`：A 删 / B 改为可选人用浏览用途。选 B：保留 Obsidian 浏览
  价值，但 helper 永不要求。
- `preflight` 输出：A 干净 `runtime=shell` / B 保留 `mode=fs forced=0` 过渡字段。
  选 B：旧 agent stub 解析旧行不破；0.6.0 再删过渡字段。
- e2e 门禁：A 单阶段 shell / B 保留双模式 + shell 优先。选 A：无头可绿、官方
  门禁可复现。
- 代码块改写：A 完整 AST / B 简单 fence 跳过 / C 不处理。选 B：覆盖常见正文，
  文档标明局限（行内代码 `[[...]]` v1 可误改）。
- aliases：A v1 不参与 rename 匹配 / B 读 frontmatter `aliases` 参与匹配。选 B：
 闭合「`[[Short Name]]` 在 rename 后失效」的洞。

### Plan (approved via user "批准")
- 规格：`docs/superpowers/specs/2026-08-04-shell-only-runtime-design.md`（已批准）。
- 计划：`docs/superpowers/plans/2026-08-04-shell-only-runtime.md`，分 5 任务：
  1) `rewrite.sh` + 挂到 `mmfs_rename`；2) 删 `cli.sh`、新 `preflight`、忽略
  `MM_FORCE_FS`；3) e2e 单阶段 + link 断言；4) `0.5.0` / `--force-fs` no-op /
  register 文案；5) 文档 + WSL 说明。
- 版本：`0.4.1` -> `0.5.0`（breaking）。
- 平台：macOS / Linux 官方；Windows 仅 WSL2；不维护原生 PowerShell。
- 命名合同不变；无 emoji；`set -uo pipefail`；禁 `sed -i`。

### Execute
- Task 1：新建 `scripts/lib/rewrite.sh`（fence 跳过、aliases 参与匹配、精确匹配
  `|` 前 target、mktemp + mv）；`scripts/lib/fs.sh` `mmfs_rename` 在 `mv` 后调用
  改写并更新目标 `title:`；日志改为 `renamed: ... (wikilinks updated: N files)`。
- Task 2：删 `scripts/lib/cli.sh`；`scripts/memovault.sh` 去掉 `. cli.sh`、
  `mmcli_detect`、所有 cli 分支；`mm_preflight` 改为
  `runtime=shell mode=fs vault=... search=rg|grep forced=0`；`MM_FORCE_FS=1`
  时打废弃提示并忽略；`scripts/lib/classify.sh` `mm_promote` 只走 `mmfs_set_prop`。
- Task 3：`scripts/e2e/run.sh` 单阶段；删 `--cli-only`、`register.sh`；
  `--fs-only` 保留为 no-op 别名；`01-preflight.sh` 断言 `runtime=shell`；
  `05-organize.sh` rename 后断言源笔记正文含新标题（旧 cli-only 红条件转绿）；
  `skills/testing-memovault/SKILL.md` 去掉双模式前置、报告改 `shell: PASS|FAIL`。
- Task 4：`VERSION` / `SKILL.md` frontmatter -> `0.5.0`；`install/install.sh`
  `--force-fs` no-op + stderr 废弃提示；`--register-vault` 文案改为可选人用浏览。
- Task 5：`README.md` / `README_CN.md` 删双运行时叙述、改 shell-only、加 WSL、
  版本 0.5.0；`AGENTS.md` 项目身份与分层图改单 shell；`docs/ARCHITECTURE.md`
  重写为单 shell 层；`docs/INSTALL.md` register 可选、force-fs 废弃、删「必须启
  Obsidian」；`docs/DEVELOPMENT.md` e2e 指针改单阶段；`docs/CLI-REFERENCE.md`
  文首声明非运行时依赖；`install/adapters/_protocol.md` 修 cli/fs 提及；
  `SKILL.md` 正文 cli/fs 双模式段改为 shell-only；`docs/superpowers/specs/
  2026-08-03-e2e-testing-design.md` 文首加 superseded 说明指向 2026-08-04 §8；
  本条目追加 RIPER。

### Review
- `bash -n scripts/memovault.sh scripts/lib/*.sh scripts/e2e/*.sh
  scripts/e2e/lib/*.sh scripts/e2e/suites/*.sh`：全部通过。
- `./scripts/e2e/run.sh`：单阶段 shell exit 0；含 `rename updated wikilink`
  PASS（旧 cli-only 红条件现为官方绿条件）。
- `preflight` 在无 Obsidian 主机输出 `runtime=shell mode=fs vault=...
  search=rg forced=0`，无 `bin=` / `app=`，无 GUI 启动。
- `MM_FORCE_FS=1` 时 helper 打印一次废弃提示并继续；行为与未设置一致。
- 命名合同（AGENTS.md §2）保持；无 emoji；无新公开环境变量；`MM_FORCE_FS`
  废弃保留兼容。
- 文档：README/AGENTS/ARCHITECTURE/INSTALL/DEVELOPMENT/CLI-REFERENCE/SKILL/
  _protocol.md 均无「cli 运行时」叙述；2026-08-03 e2e 规格标注 superseded。
- 已知局限（文档已声明）：行内代码中的 `[[...]]` 在 rename 改写中不被保护；
  `move` 不改 basename 故不触发改写（与规格 §5.1 一致）。

