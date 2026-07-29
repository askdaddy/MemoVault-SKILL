## Memory protocol (always on)

You have a local knowledge vault. Use it proactively, not only when asked.

- Vault path: `$AGENT_MEMO_VAULT` (default __MEMOVAULT_VAULT__)
- Helper: __MEMOVAULT_HELPER__ (run `preflight` once per session to detect cli/fs mode)
- Full command reference: __MEMOVAULT_SOURCE__/SKILL.md

### 1. Recall - automatic, every task

At the start of answering a user request, before you respond:
- Run `__MEMOVAULT_HELPER__ search "<narrow keywords from the request>"`
- If a hit looks relevant, read it (`__MEMOVAULT_HELPER__ read "<title>"`) and weave
  it into your answer; cite it as a vault note.
- If the vault is empty or nothing matches, skip silently. Do not narrate "nothing
  found". Keep it cheap: one search per task, narrow keywords.

### 2. Capture - semi-automatic, on durable knowledge

When this turn produced reusable knowledge (a decision, a fix or lesson, a
how-to, design rationale, or a non-obvious fact):
- PROPOSE first: "I can save this to <domain>/<title>, linking [[related]]. Do it?"
- On confirmation, write it:
  `__MEMOVAULT_HELPER__ new <domain> "<title>" --tags a,b --body "..."`
  then add `[[wikilinks]]` and set short `aliases`. New notes start `heat: seedling`.
- If the user explicitly says "remember this" / "save this" / "note this" /
  "capture this" / "记一下" / "记下来" / "帮我记一下" / "沉淀一下" /
  "存一下" / "存到笔记" / "记到知识库", capture without asking, then
  confirm what you saved.
- Otherwise do not capture small talk, transient debug output, or anything the
  user would not search for later.

### 3. Classify and link

- One domain per note; domains live under `brain/<domain>/`.
- Heat tiers: `seedling` -> `growing` -> `evergreen`. When a note gains backlinks,
  suggest `promote "<title>"`; the user confirms.
- Before creating, `search` to avoid duplicates; prefer `append` to an existing note.
- Backlinks are the point: connect related notes with `[[wikilinks]]`.

### 4. Guardrails

- Never write outside the vault. Never use emoji in note content or frontmatter.
- Confirm before any delete or bulk move; destructive ops need explicit consent.
- In fs mode, `move`/`rename` do NOT update `[[links]]`; warn the user first.
