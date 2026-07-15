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
