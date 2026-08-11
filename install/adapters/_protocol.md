## Memory protocol (always on)

You have a local knowledge vault. Use it proactively, not only when asked.

- Vault path: `$AGENT_MEMO_VAULT` (default __MEMOVAULT_VAULT__)
- Helper: __MEMOVAULT_HELPER__ (run `preflight` once per session to confirm the shell runtime and vault path)
- Full command reference: __MEMOVAULT_SOURCE__/SKILL.md

### 1. Recall - automatic, every task

At the start of answering a user request, before you respond:
- Run one `__MEMOVAULT_HELPER__ recall "<narrow keywords>"` (prefer `--limit 5`).
  If recall is unavailable, fall back to `search` with the same keywords.
- Helper already filters out `kind: raw` and ranks by heat/kind. Prefer the top
  hits; `read` at most 3 notes per task (usually 1).
- When a note materially affects your answer, run
  `__MEMOVAULT_HELPER__ cite "<title>"` and mention the note briefly.
- If the vault is empty or nothing matches, skip silently. Do not narrate
  "nothing found".

### 2. Capture - semi-automatic, on durable knowledge

When the turn produced reusable knowledge (a decision, a fix or lesson, a
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

- L0 evidence is `kind: raw` under `brain/inbox/` (or another domain). Do not
  use `daily/` as the default capture path (legacy only for humans).
- Distill with:
  `__MEMOVAULT_HELPER__ distill "<raw-title>" <domain> "<Title>" --kind atom`
  (or create/update an atom/scenario with `sources` and body `[[raw-title]]`).
- Never delete raw evidence without explicit user consent.
- `kind: persona` is rare; do not start as evergreen unless the user confirms.

### 4. Skill capture (SOPs)

When the turn produced a reusable how-to:
- Propose `skills/<Title>` with `--kind skill`, or write immediately on explicit
  remember phrases.
- Structure body as Trigger / Steps / Verify / Related (protocol body recipe;
  vault templates are optional for humans only).
- Link related domain notes with `[[wikilinks]]`.

### 5. Classify, link, health

- One domain per note; domains live under `brain/<domain>/`. Skill SOPs under
  `brain/skills/`.
- Optional `kind`: `raw` | `atom` | `scenario` | `persona` | `skill`.
- Optional `status`: `active` (default) | `superseded`. Prefer
  `supersede <old> <new>` when knowledge is replaced; default recall skips
  superseded notes.
- Before creating, run `dedupe "<title>"` and prefer `append` on hits.
- Heat: `seedling` -> `growing` -> `evergreen`. Run `suggest` or `health` and
  confirm before `promote`.
- When the user asks about memory health, or inbox/raw is piling up, run
  `__MEMOVAULT_HELPER__ health` / `suggest` and act on `hint=` / `suggest=`
  lines. Do not silently rewrite the vault.

### 6. Guardrails

- Never write outside the vault. Never use emoji in note content or frontmatter.
- Confirm before any delete or bulk move; destructive ops need explicit consent.
- `rename` rewrites `[[wikilinks]]` across the vault (link-safe). `move` does not
  change the basename, so existing `[[links]]` stay valid.
