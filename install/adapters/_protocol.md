## Memory protocol (always on)

You have a local knowledge vault. Use it proactively, not only when asked.

- Vault path: `$AGENT_MEMO_VAULT` (default __MEMOVAULT_VAULT__)
- Helper: __MEMOVAULT_HELPER__ (run `preflight` once per session to confirm the shell runtime and vault path)
- Full command reference: __MEMOVAULT_SOURCE__/SKILL.md

### 1. Recall - automatic, every task

At the start of answering a user request, before you respond:
- Run one `__MEMOVAULT_HELPER__ search "<narrow keywords from the request>"`
  (prefer `--limit 10` or tighter).
- Rank hits: prefer `heat: evergreen` then `growing`; prefer
  `kind: persona|scenario|skill|atom` over `raw` / pure `daily/` noise.
- Progressive disclosure: titles/snippets first; `read` at most 3 notes per task
  (usually 1). Weave relevant knowledge into your answer; cite the vault note
  when it materially affects the answer.
- If the vault is empty or nothing matches, skip silently. Do not narrate "nothing
  found".

### 2. Capture - semi-automatic, on durable knowledge

When this turn produced reusable knowledge (a decision, a fix or lesson, a
how-to, design rationale, or a non-obvious fact):
- PROPOSE first: "I can save this to <domain>/<title> (kind: atom|scenario),
  linking [[related]]. Do it?"
- On confirmation, write it:
  `__MEMOVAULT_HELPER__ new <domain> "<title>" --kind atom --tags a,b --body "..."`
  then add `[[wikilinks]]` and set short `aliases`. Default heat is `seedling`
  (`--kind skill` defaults to `growing`).
- If the user explicitly says "remember this" / "save this" / "note this" /
  "capture this" / "记一下" / "记下来" / "帮我记一下" / "沉淀一下" /
  "存一下" / "存到笔记" / "记到知识库", capture without asking, then
  confirm what you saved.
- Otherwise do not capture small talk, transient debug output, or anything the
  user would not search for later.

### 3. Distill and provenance

- Raw capture (`daily/`, `kind: raw`, inbox) is evidence, not the end state.
- Distill into `atom` or `scenario`; set `sources: ["YYYY-MM-DD"]` and body
  wikilinks back to the raw note. Canonical daily link: `[[YYYY-MM-DD]]`
  (path form `daily/YYYY-MM-DD.md` also works). Optionally leave a one-line
  pointer on the daily note.
- Never delete raw evidence without explicit user consent.
- `kind: persona` is rare; do not start as evergreen unless the user confirms.

### 4. Skill capture (SOPs)

When the turn produced a reusable how-to:
- Propose `skills/<Title>` with `--kind skill`, or write immediately on explicit
  remember phrases.
- Structure body as Trigger / Steps / Verify / Related (see templates/skill.md).
- Link related domain notes with `[[wikilinks]]`.

### 5. Classify and link

- One domain per note; domains live under `brain/<domain>/`. Skill SOPs under
  `brain/skills/`.
- Optional `kind`: `raw` | `atom` | `scenario` | `persona` | `skill`.
- Heat tiers: `seedling` -> `growing` -> `evergreen`. When a note gains backlinks,
  suggest `promote "<title>"`; the user confirms.
- Before creating, `search` to avoid duplicates; prefer `append` to an existing note.
- Backlinks are the point: connect related notes with `[[wikilinks]]`.

### 6. Guardrails

- Never write outside the vault. Never use emoji in note content or frontmatter.
- Confirm before any delete or bulk move; destructive ops need explicit consent.
- `rename` rewrites `[[wikilinks]]` across the vault (link-safe). `move` does not
  change the basename, so existing `[[links]]` stay valid; warn the user only if
  a future move implementation also renames.
