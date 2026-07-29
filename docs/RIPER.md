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
