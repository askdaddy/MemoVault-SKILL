# recall argv + use-loop protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `0.9.1`: parse recall flags before or after the query, reject flag-only recall, and tell agents to read-then-cite when a hit is actually used.

**Architecture:** One argv walk in `mmfs_recall`. Known flags (`--limit N`, `--no-graph`, `--include-superseded`) may appear anywhere; leftover non-flag args concatenate as the query. Matching, ranking, and ledger keys stay the same. Protocol text in SKILL / `_protocol.md` / AGENTS.

**Tech Stack:** bash 3.2, existing e2e harness (`scripts/e2e/suites/03-retrieve.sh`).

## Global Constraints

- No emoji. English comments and user-facing helper strings.
- Quote all variables. `set -uo pipefail`. No `set -e` in the helper.
- Never write outside `$MM_VAULT` / the repo (vault promote/capture is an explicit confirmed task).
- Do not change recall matching, ranking, or health formulas.
- Do not change `search` / `dedupe` argv in this patch.

---

### Task 1: Failing e2e for flag-first recall

**Files:**
- Modify: `scripts/e2e/suites/03-retrieve.sh` (append after the MOC block)

**Interfaces:**
- Consumes: `e2e_mm`, `E2E_VAULT`, `E2E_STEM`, `E2E_PHASE`, `assert_contains`, `e2e_pass`, `e2e_fail`
- Produces: two failing asserts that Task 2 will make pass

- [ ] **Step 1: Write the failing tests**

Append:

```bash
# 0.9.1: flags may precede the query; --limit is never the query
flag_tok="FLAGTOK_${E2E_STEM// /_}"
flag_t="${E2E_STEM} FlagFirst"
e2e_mm new "$dom" "$flag_t" --kind atom --body "unique $flag_tok" >/dev/null 2>&1 || true
rout_flag="$(e2e_mm recall --limit 3 "$flag_tok" --no-graph 2>/dev/null || true)"
assert_contains "$rout_flag" "title=$flag_t" "recall flag-first finds query ($E2E_PHASE)"
last_flag="$(grep 'event=recall' "$E2E_VAULT/.memovault/ledger.log" | tail -1)"
case "$last_flag" in
  *"q=$flag_tok"*) e2e_pass "recall flag-first ledger q is query ($E2E_PHASE)" ;;
  *) e2e_fail "recall flag-first ledger q is query ($E2E_PHASE)" "line=$last_flag" ;;
esac
case "$last_flag" in
  *"q=--limit"*) e2e_fail "recall flag-first ledger q is not --limit ($E2E_PHASE)" "line=$last_flag" ;;
  *) e2e_pass "recall flag-first ledger q is not --limit ($E2E_PHASE)" ;;
esac

if e2e_mm recall --limit 3 >/dev/null 2>&1; then
  e2e_fail "recall --limit without query exits nonzero ($E2E_PHASE)"
else
  e2e_pass "recall --limit without query exits nonzero ($E2E_PHASE)"
fi
```

- [ ] **Step 2: Run 03-retrieve and confirm RED**

Setup: source e2e env, `e2e_begin_shell_phase`, run suite 03. Expect
`recall flag-first finds query` and/or ledger q asserts FAIL (today `$1` is
`--limit`). `recall --limit without query` currently exits 0, so that assert
FAILS too.

- [ ] **Step 3: Implement argv walk in `mmfs_recall`**

Replace the `$1` then flag-loop header of `scripts/lib/fs.sh` `mmfs_recall`
(comment + function start through the usage check) with:

```bash
# Flags may appear before or after the query. Unknown --* is an error so
# `recall --limit 5 tokens` cannot log q=--limit.
mmfs_recall() {
  local q="" limit=5 use_graph=1 include_superseded=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit)
        [ $# -ge 2 ] || mm_die "recall: --limit requires a value"
        limit="$2"
        shift 2
        ;;
      --no-graph) use_graph=0; shift ;;
      --include-superseded) include_superseded=1; shift ;;
      --*) mm_die "recall: unknown flag $1" ;;
      *)
        if [ -n "$q" ]; then
          q="$q $1"
        else
          q="$1"
        fi
        shift
        ;;
    esac
  done
  [ -n "$q" ] || mm_die "usage: recall <query> [--limit N] [--no-graph] [--include-superseded]"
```

Keep the rest of the function (vault scan, rank, ledger) unchanged.

- [ ] **Step 4: Re-run 03-retrieve and confirm GREEN**

Same command as Step 2. The four new asserts pass. Existing recall asserts
still pass (`recall "<query>" --limit N` order).

---

### Task 2: Protocol, usage, version 0.9.1

**Files:**
- Modify: `SKILL.md`, `install/adapters/_protocol.md`, `AGENTS.md`,
  `scripts/memovault.sh` usage, `docs/ARCHITECTURE.md`, `README.md`,
  `README_CN.md`, `VERSION`, `CHANGELOG.md`, `docs/RIPER.md`

**Interfaces:**
- Consumes: Task 1 helper behavior
- Produces: agent-visible contract at 0.9.1

- [ ] **Step 1: Helper usage + SKILL command line**

`scripts/memovault.sh` usage line stays
`recall <query> [--limit N] [--no-graph] [--include-superseded]`
but add a note in SKILL retrieve block: flags may precede `<query>`.

`SKILL.md` frontmatter `version: 0.9.1`.

Recall protocol (section 6): after the `recall` command sentence, add that
`recall --limit 5 "tokens"` is valid and the query must not start with `--`.
Cite bullet: when a hit materially affects the answer, `read` (if the snippet
is not enough) then `cite`; do not cite unused ritual hits.

- [ ] **Step 2: `_protocol.md` + AGENTS.md**

Same two sentences in `install/adapters/_protocol.md` section 1 (recall /
cite). `AGENTS.md` health/recall summary: flags may precede query.

- [ ] **Step 3: VERSION + CHANGELOG + RIPER + README**

`VERSION` = `0.9.1\n`. README* version table `0.9.1`.

`CHANGELOG.md`: keep `[Unreleased]` health-report bullets. Add
`## [0.9.1] - 2026-09-09` **Fixed**: recall parses flags before or after the
query; `recall --limit N` without a query errors. **Changed**: protocol
read-then-cite; unused ritual recall is not cited.

`docs/RIPER.md` entry 25 for this change.

`docs/ARCHITECTURE.md` recall row: flags may precede query.

---

### Task 3: Vault promote + capture (confirmed)

**Files:** vault only (`$AGENT_MEMO_VAULT`), not git.

- [ ] **Step 1: Promote**

```bash
"$MM" promote "Memory Loop 0.6.0 产品决策"
"$MM" promote "文档默认使用中文"
```

Expect seedling -> growing each.

- [ ] **Step 2: Capture atom**

`dedupe` the title first. Then `new memovault "recall flags may precede query" --kind atom` with wikilinks to [[Memory Loop 0.6.0 产品决策]] and the 0.9.1 contract (flag-first OK; `--*` is not a query).
